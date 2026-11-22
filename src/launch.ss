;;; launch.ss — how a launcher at the tree's root (schevana-desktop,
;;; schevana-game-demo, ...) starts the library it names: the tree's root is
;;; where import finds Schevana's libraries, each compiled once into
;;; .cache/ (a folder there for each Chez version and machine) and loaded
;;; from it after, until its file changes; then the library's main, handed
;;; the command line's arguments. A launcher, from the tree's root:
;;;
;;;   (import (chezscheme))
;;;   (let ([root (path-parent (car (command-line)))])
;;;     (load (string-append (if (string=? root "") "." root) "/src/launch.ss"))
;;;     (schevana-launch root '(schevana-demo game) 'game-main
;;;                      (command-line-arguments)))
;;;
;;; --hacker (or SCHEVANA_HACKER set, which a run started from this one
;;; inherits) is the hacker edition: every library from its source into this
;;; one top-level environment, each name of each there to see and to
;;; redefine (src/hacker.ss). Pure but for what it sets up: the library
;;; search, the compiler's parameters, the variable for the runs after.

;; root as a folder from the current one, whole.
(define (schevana-launch-root root)
  (cond [(member root '("" ".")) (current-directory)]
        [(path-absolute? root) root]
        [else (string-append (current-directory) "/" root)]))

;; Whether this run is the hacker edition's.
(define (schevana-hacker? args)
  (or (and (member "--hacker" args) #t)
      (let ([v (getenv "SCHEVANA_HACKER")])
        (and v (not (string=? v ""))))))

;; Where the tree's libraries are kept compiled: one Chez version's objects
;; aren't another's.
(define (schevana-cache-folder root)
  (call-with-values scheme-version-number
    (lambda (major minor patch)
      (format "~a/.cache/~a.~a.~a-~a" root major minor patch (machine-type)))))

(define (schevana-folder! dir)
  (unless (file-directory? dir)
    (schevana-folder! (path-parent dir))
    (guard (c [#t (unless (file-directory? dir) (raise c))]) (mkdir dir))))

;; Compiles a library to a file of a name of its own, then renames that
;; to the object's: another run loading the tree's libraries at the same
;; time finds the old file or the new one, never half of one. Quietly:
;; what runs prints nothing of its compiling.
(define (schevana-compile-library source object)
  (schevana-folder! (path-parent object))
  (let ([part (let ([t (current-time)])
                (format "~a.~a-~a" object (time-second t)
                        (time-nanosecond t)))])
    (parameterize ([console-output-port (open-output-string)]
                   [current-output-port (open-output-string)])
      (compile-library source part))
    (rename-file part object)))

;; The library search and the compiler's parameters for root's libraries:
;; compiled into the cache, or, for the hacker edition, read from source
;; into this environment through src/hacker.ss's library form.
(define (schevana-libraries! root hacker?)
  (if hacker?
      (begin
        (library-directories (cons (cons root root) (library-directories)))
        (compile-imported-libraries #f)
        (putenv "SCHEVANA_HACKER" "1")
        (load (string-append root "/src/base.ss"))
        (load (string-append root "/src/hacker.ss")))
      (begin
        (library-directories
         (cons (cons root (schevana-cache-folder root)) (library-directories)))
        (compile-imported-libraries #t)
        (compile-library-handler schevana-compile-library))))

;; procedure of library's, applied to args: the library's own, or, in the
;; hacker edition, the name spliced here.
(define (schevana-call hacker? library procedure . args)
  (if hacker?
      (begin
        (eval `(import ,library))
        (apply (eval procedure) args))
      (apply (eval procedure (environment library)) args)))

;; Starts main of library with args, root's libraries set up first.
(define (schevana-launch root library main args)
  (let ([root (schevana-launch-root root)] [hacker? (schevana-hacker? args)])
    (schevana-libraries! root hacker?)
    (schevana-call hacker? library main args)))
