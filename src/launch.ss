;;; launch.ss — how a launcher at the tree's root (desktop, game-demo,
;;; ...) starts the library it names. The tree's root is where import finds
;;; Schevana's libraries. Each is compiled once into .cache/ (which has a
;;; folder for each Chez version and machine) and loaded from there until
;;; its file changes. Then the library's main is called with the command
;;; line's arguments. A launcher at the tree's root does this:
;;;
;;;   (import (chezscheme))
;;;   (let ([root (path-parent (car (command-line)))])
;;;     (load (string-append (if (string=? root "") "." root) "/src/launch.ss"))
;;;     ((eval 'schevana-launch) root '(games fireflies) 'fireflies-main
;;;      (command-line-arguments)))
;;;
;;; --hacker (or SCHEVANA_HACKER set, which a run started from this one
;;; inherits) runs the hacker edition: every library is loaded from its
;;; source into this one top-level environment, where each of its names can
;;; be seen and redefined (src/hacker.ss). This file is pure except for what
;;; it sets up: the library search, the compiler's parameters, and the
;;; environment variable for the runs it starts.

;; Returns root as an absolute path, resolved from the current folder.
(define (schevana-launch-root root)
  (cond [(member root '("" ".")) (current-directory)]
        [(path-absolute? root) root]
        [else (string-append (current-directory) "/" root)]))

;; Whether this run is the hacker edition.
(define (schevana-hacker? args)
  (or (and (member "--hacker" args) #t)
      (let ([v (getenv "SCHEVANA_HACKER")])
        (and v (not (string=? v ""))))))

;; Where the tree's libraries are kept compiled, a folder for each Chez
;; version and machine type, since one version's objects don't load in
;; another.
(define (schevana-cache-folder root)
  (call-with-values scheme-version-number
    (lambda (major minor patch)
      (format "~a/.cache/~a.~a.~a-~a" root major minor patch (machine-type)))))

(define (schevana-folder! dir)
  (unless (file-directory? dir)
    (schevana-folder! (path-parent dir))
    (guard (c [#t (unless (file-directory? dir) (raise c))]) (mkdir dir))))

;; Compiles a library to a file with a name of its own, then renames that
;; file to the object's name, so that another run loading the tree's
;; libraries at the same time finds the old file or the new one, never
;; half of one. As each compile begins, it prints the source and the
;; object as Chez does, so a first boot shows its progress and how long
;; each library takes; everything else that compiling prints stays quiet.
(define (schevana-compile-library source object)
  (schevana-folder! (path-parent object))
  (printf "compiling ~a with output to ~a~%" source object)
  (flush-output-port (current-output-port))
  (let ([part (let ([t (current-time)])
                (format "~a.~a-~a" object (time-second t)
                        (time-nanosecond t)))])
    (parameterize ([console-output-port (open-output-string)]
                   [current-output-port (open-output-string)])
      (compile-library source part))
    (rename-file part object)))

;; Returns the library search as it was, without root's own folder: run
;; from the tree's root, Chez's "." is the tree, which the entry for root,
;; put first, already covers.
(define (schevana-search-without root)
  (remp (lambda (e)
          (let ([source (if (pair? e) (car e) e)])
            (equal? (cond [(member source '("" ".")) (current-directory)]
                          [(path-absolute? source) source]
                          [else (string-append (current-directory) "/"
                                               source)])
                    root)))
        (library-directories)))

;; Sets up the library search and the compiler's parameters for root's
;; libraries: compiled into the cache or, for the hacker edition, read
;; from source into this environment through src/hacker.ss's library form.
(define (schevana-libraries! root hacker?)
  (if hacker?
      (begin
        (library-directories (cons (cons root root)
                                   (schevana-search-without root)))
        (compile-imported-libraries #f)
        (putenv "SCHEVANA_HACKER" "1")
        (load (string-append root "/src/base.ss"))
        (load (string-append root "/src/strip.ss"))
        (load (string-append root "/src/hacker.ss")))
      (begin
        (library-directories
         (cons (cons root (schevana-cache-folder root))
               (schevana-search-without root)))
        (compile-imported-libraries #t)
        (compile-library-handler schevana-compile-library))))

;; Applies library's procedure to args: the library's own export or, in
;; the hacker edition, the name spliced into this environment.
(define (schevana-call hacker? library procedure . args)
  (if hacker?
      (begin
        (eval `(import ,library))
        (apply (eval procedure) args))
      (apply (eval procedure (environment library)) args)))

;; Sets up root's libraries, then calls library's main with args.
(define (schevana-launch root library main args)
  (let ([root (schevana-launch-root root)] [hacker? (schevana-hacker? args)])
    (schevana-libraries! root hacker?)
    (schevana-call hacker? library main args)))
