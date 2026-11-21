;;; core1/sources.ss — the world's files, loaded into "/" at boot and at
;;; every (reload!), with the user's: what the old boot's environments
;;; need of the loop, kept as a file of "/core1" while the core's own code
;;; is sealed in its libraries (lib/schevana/core/). The texts of what
;;; loaded are kept, for what describes a name.

;; The user's init file, ~/.schevana.ss, loaded into the world after it
;; booted (world.ss).
(define user-init-file
  (format "~a/.schevana.ss" (or (getenv "HOME") ".")))

(define (load-user-init!)
  (when (file-exists? user-init-file)
    (safely 'init (lambda () (load-file! user-init-file)))))

;;; ------------------------------------------------------------------ sources
;;; The core is main.ss's list, in "/core1". The world, in "/", is a copy
;;; of src/base.ss and the folders, one definition per file, each folder's
;;; files in file-name order: drop a file in and it loads at the next boot
;;; or (reload!). A real session then loads the same folders from
;;; ~/.schevana.d.

;; The folders after the core, in load order.
(define source-folders
  '("kits" "services" "desktop" "styles" "palettes" "wallpapers" "apps"))

;; main.ss turns this on: a real session loads the user's folders too, at
;; boot and at every (reload!). The tests never do.
(defvar *user-folders?* #f)

;; A file name relative to the tree, or an absolute one (the user's).
(define (source-path f)
  (if (path-absolute? f) f (string-append *schevana-root* "/" f)))

;; The .ss files in the folder dir, by name; none if it does not exist.
;; Names starting with a dot (editors' lock files) are left out.
(define (folder-sources dir)
  (let ([path (source-path dir)])
    (if (file-directory? path)
        (map (lambda (f) (string-append dir "/" f))
             (sort string<?
                   (filter (lambda (f)
                             (and (string-suffix? ".ss" f)
                                  (not (string-prefix? "." f))))
                           (directory-list path))))
        '())))

(define (user-folder-files)
  (if *user-folders?*
      (apply append
             (map (lambda (d)
                    (folder-sources (string-append user-directory "/" d)))
                  source-folders))
      '()))

(define (folder-files)
  (append (apply append (map folder-sources source-folders))
          (user-folder-files)))

;; The world's own files, in load order: a copy of the basics, then the
;; folders.
(define (world-sources) (cons "src/base.ss" (folder-files)))

;; Every source file, the core's and the world's, in load order. The REPL's
;; docs and the tests read this list.
(define (source-files) (append *schevana-core1-sources* (world-sources)))

;; The text of every source as it was loaded (or, from a REPL, evaluated),
;; by its name: a file's path, or what the REPL calls its input. What reads
;; the sources (the REPL's descriptions) reads these, not the files as they
;; are now, so that it tells of the code that runs. (serial . text), the
;; serial counting the texts kept.
(defvar *source-texts* (make-hashtable string-hash string=?))
(defvar *source-serial* 0)

(define (keep-source-text! name text)
  (set! *source-serial* (+ *source-serial* 1))
  (hashtable-set! *source-texts* name (cons *source-serial* text)))

(define (file-text path) (call-with-input-file path get-string-all))

;; Loads a file, keeping its text (read just before load reads it).
(define (load-file! path)
  (keep-source-text! path (file-text path))
  (load path))

;; Loads an app's file (one in an apps folder, the tree's or the user's):
;; into the world, until services/grant.ss sets it to give each app a
;; sandbox of its own.
(define-hook (app-load! path) (load-file! path))

(define (load-source f)
  (let ([path (source-path f)])
    (if (equal? (path-last (path-parent path)) "apps")
        (app-load! path)
        (load-file! path))))

;; Loads files into the world (from a private REPL too), or into env
;; ("/core1", the core's). Run as a process (the launcher's "Reload
;; sources", (reload!) in a REPL), it names itself and the file in
;; *reloading* until it ends, so the world holds still meanwhile
;; (schevana-step!), yet it is still preempted and Ctrl+C kills it. Not
;; with dynamic-wind: an engine runs its exits at every preemption.
(define (load-sources! files . env)
  (let* ([p (current-proc)]
         [outer? (and p (not (and *reloading* (eq? (car *reloading*) p))))])
    (parameterize ([interaction-environment
                    (if (pair? env) (car env) *world-env*)])
      (guard (c [outer? (reload-ended!
                         (format "Reload failed in ~a: ~a"
                                 (cdr *reloading*) (condition->string c)))
                        (raise c)])
        (for-each (lambda (f i)
                    (when p (set! *reloading* (cons p f)))
                    (load-source f)
                    ;; the boot screen's bar
                    (core0-world-loaded! (+ i 1) (length files)))
                  files (iota (length files)))
        (when outer? (set! *reloading* #f))))))

;; The user's folders, after the built-in ones (main.ss, before the saved
;; theme, which may name a user's style or palette). One file at a time, so
;; that one which raises is named in its toast and the rest still load.
(define (load-user-folders!)
  (set! *user-folders?* #t)
  (add-library-directory! user-library-directory)
  (for-each (lambda (f) (safely f (lambda () (load-sources! (list f)))))
            (user-folder-files)))

;; The core's source files main.ss lists, read from the file itself so
;; that a reload picks up new ones.
(define (read-source-list)
  (guard (c [#t *schevana-core1-sources*])
    (call-with-input-file (string-append *schevana-root* "/main.ss")
      (lambda (p)
        (let loop ()
          (let ([x (read p)])
            (cond
              [(eof-object? x) *schevana-core1-sources*]
              [(and (list? x) (= (length x) 3) (eq? (car x) 'define)
                    (eq? (cadr x) '*schevana-core1-sources*)
                    (pair? (caddr x)) (eq? (car (caddr x)) 'quote)
                    (list? (cadr (caddr x))))
               (cadr (caddr x))]
              [else (loop)])))))))

;; Core0's libraries stay as core0 booted them, with all they import: its
;; thread runs them, and they change with a restart.
(define (source-held-libraries)
  (filter (lambda (name)
            (and (> (length name) 2)
                 (eq? (car name) 'schevana)
                 (eq? (cadr name) 'core0)))
          (library-list)))

;; Re-read every source file: the libraries whose files changed, and those
;; that import them (reload-libraries!); the core's into "/core1"; then
;; the world's into "/", given first what the core exports that it wasn't
;; before; what it was keeps its forwarder. Code changes take effect;
;; state declared with defvar or define-state (windows, theme,
;; processes...) survives.
(define (reload!)
  (source-libraries-keep! (reload-libraries! (source-held-libraries)))
  (let ([files (read-source-list)] [before (core1-exported)])
    (set! *schevana-core1-sources* files)
    (load-sources! files *core1-env*)
    (exports-install! (map (lambda (clause)
                             (cons (car clause)
                                   (remp (lambda (e) (memq (car e) before))
                                         (cdr clause))))
                           core1-exports)
                      *core1-env* 'world *world-env*))
  (load-world!)
  (request-redraw!)
  (collector-settle!)
  (notify "Sources reloaded" 'green))

;; Core0 loads the core before this file can keep its texts: kept now,
;; moments after (a reload keeps them as it loads them).
(at-load
 (for-each (lambda (f)
             (let ([path (source-path f)])
               (unless (hashtable-contains? *source-texts* path)
                 (keep-source-text! path (file-text path)))))
           *schevana-core1-sources*))

;; The world's files into "/" (core1-boot!, reload!). The folders may
;; import the libraries shipped in lib/; each loaded by then is seen as it
;; reads, for the next reload to tell a change (reload-mark!), and its
;; text kept, as a file's is, for what describes a name.
(define (load-world!)
  (add-library-directory! (string-append *schevana-root* "/lib"))
  (load-sources! (world-sources))
  (reload-mark!)
  (source-libraries-keep! (library-list)))

;; The texts of the libraries named that are read from a file, those
;; that changed: a text kept again is read again by what describes names.
(define (source-libraries-keep! names)
  (for-each (lambda (name)
              (let ([file (reload-source name)])
                (when file
                  (let ([text (file-text file)]
                        [had (hashtable-ref *source-texts* file #f)])
                    (unless (and had (string=? (cdr had) text))
                      (keep-source-text! file text))))))
            names))
