;;; (schevana core sources) — the world's files, loaded into "/" at boot
;;; and at every (reload!), with the user's, and "/" itself: core1's boot
;;; makes it, importing the core's facade, (schevana core), and loads the
;;; world into it. The texts of what loaded are kept, for what describes a
;;; name.

(library (schevana core sources)
  (export
    *world-env* *schevana-options* schevana-hacker? core1-boot!
    core1-exported
    user-init-file load-user-init! source-folders *user-folders?*
    source-path folder-sources folder-files world-sources source-files
    *source-texts* keep-source-text! file-text load-file! app-load!
    load-source load-sources!
    load-user-folders! source-held-libraries reload! world-libraries
    world-entries load-world!
    source-libraries-keep!)
  (import (chezscheme)
          (schevana base)
          (schevana tree)
          (schevana reload)
          (schevana core0)
          (schevana core theme-table)
          (schevana core processes)
          (schevana core loop))

  (library-layer core)

  ;; "/", the world's, once core1 has made it. Lookups by name go here, not
  ;; to (interaction-environment), which a private REPL rebinds.
  (define-state *world-env* #f)

  ;; What the command line asked (desktop-options, (schevana desktop
  ;; main)), handed down as core1 boots.
  (define-state *schevana-options* '())

  ;; Whether this is the hacker edition (src/hacker.ss): every library
  ;; spliced at the top level, "/" itself.
  (define (schevana-hacker?)
    (let ([o (assq 'hacker *schevana-options*)]) (and o (cdr o))))

  ;; For a name "/" has as a macro (a view of the core's, a state or a
  ;; hook), what reads it there: compiled once, kept till the world loads
  ;; again (load-world!), as a reload may make the core's anew.
  (define-made *world-readers* (make-eq-hashtable))

  (define (world-reader name)
    (or (hashtable-ref *world-readers* name #f)
        (let ([read (eval `(lambda () ,name) *world-env*)])
          (hashtable-set! *world-readers* name read)
          read)))

  ;; name's value as the world has it: "/"'s own, or what "/" imports of
  ;; the core. What calls a procedure by its name, so that a redefinition
  ;; takes at the next call, looks it up so.
  (set-hook! (world-value name)
    (cond
      [(not *world-env*)
       (errorf 'world-value "~s: there is no world yet" name)]
      [(top-level-bound? name *world-env*) (top-level-value name *world-env*)]
      [else ((world-reader name))]))

  ;; The names the core gives the world: its facade's.
  (define (core1-exported) (library-exports '(schevana core)))

  ;; The user's init file, ~/.schevana.ss, loaded into the world after it
  ;; booted (desktop-start!).
  (define-made user-init-file
    (format "~a/.schevana.ss" (or (getenv "HOME") ".")))

  (define (load-user-init!)
    (when (file-exists? user-init-file)
      (safely 'init (lambda () (load-file! user-init-file)))))

  ;; The folders after the core, in load order.
  (define source-folders
    '("kits" "services" "desktop" "styles" "palettes" "wallpapers" "apps"))

  ;; The desktop turns this on: a real session loads the user's folders
  ;; too, at boot and at every (reload!). The tests never do.
  (define-state *user-folders?* #f)

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
  (define (world-sources)
    (if (schevana-hacker?) (folder-files) (cons "src/base.ss" (folder-files))))

  ;; Every source file, in load order: the world's, since the core's are
  ;; libraries. The REPL's docs and the tests read this list.
  (define (source-files) (world-sources))

  ;; The text of every source as it was loaded (or, from a REPL, evaluated),
  ;; by its name: a file's path, or what the REPL calls its input. What reads
  ;; the sources (the REPL's descriptions) reads these, not the files as they
  ;; are now, so that it tells of the code that runs. (serial . text), the
  ;; serial counting the texts kept.
  (define-state *source-texts* (make-hashtable string-hash string=?))
  (define-state *source-serial* 0)

  (define (keep-source-text! name text)
    (set! *source-serial* (+ *source-serial* 1))
    (hashtable-set! *source-texts* name (cons *source-serial* text)))

  (define (file-text path) (call-with-input-file path get-string-all))

  ;; Loads a file, keeping its text (read just before load reads it).
  (define (load-file! path)
    (keep-source-text! path (file-text path))
    (load path))

  ;; Loads an app's file (one in an apps folder, the tree's or the user's):
  ;; into the world, until (schevana services grant) sets it to give each app a
  ;; sandbox of its own.
  (define-hook (app-load! path) (load-file! path))

  ;; A world's source: a file, by its path, or one of the world's
  ;; libraries, by its name, imported into "/" (once: a reload of a library
  ;; imports it again there) and run, so that what it registers (an app, a
  ;; style, a surface) is registered.
  (define (load-source f)
    (if (pair? f)
        (begin
          (unless (member f *world-imported*)
            (reload-import! *world-env* f)
            (set! *world-imported* (cons f *world-imported*)))
          (invoke-library f))
        (let ([path (source-path f)])
          (if (equal? (path-last (path-parent path)) "apps")
              (app-load! path)
              (load-file! path)))))

  ;; Loads files into the world (from a private REPL too), or into env.
  ;; Run as a process (the launcher's "Reload
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

  ;; The user's folders, after the built-in ones (desktop-start!, before
  ;; the saved theme, which may name a user's style or palette). One file at
  ;; a time, so that one which raises is named in its toast and the rest
  ;; still load.
  (define (load-user-folders!)
    (set! *user-folders?* #t)
    (add-library-directory! user-library-directory)
    (for-each (lambda (f) (safely f (lambda () (load-sources! (list f)))))
              (user-folder-files)))

  ;; Core0's libraries stay as core0 booted them, with all they import: its
  ;; thread runs them, and they change with a restart.
  (define (source-held-libraries)
    (filter (lambda (name)
              (and (> (length name) 2)
                   (eq? (car name) 'schevana)
                   (eq? (cadr name) 'core0)))
            (library-list)))

  ;; Re-read every source file: the libraries whose files changed, and those
  ;; that import them (reload-libraries!), which imports them again where
  ;; they were imported ("/" the core's facade); then the world's files into
  ;; "/". Code changes take effect; state declared with defvar or
  ;; define-state (windows, theme, processes...) survives.
  (define (reload!)
    (source-libraries-keep!
     (if (schevana-hacker?)
         ((eval 'hacker-reload-libraries! *world-env*)
          (source-held-libraries))
         (reload-libraries! (source-held-libraries))))
    (load-world!)
    (request-redraw!)
    (collector-settle!)
    (notify "Sources reloaded" 'green))

  ;; The world's libraries, (schevana <folder> <name>): those of the
  ;; tree's schevana/<folder>/, for each of source-folders.
  (define (world-libraries) (filter pair? (world-entries)))

  ;; The world's sources in load order: the folders in theirs, each
  ;; folder's libraries and files merged in file-name order, a library by
  ;; its name, a file by its path; then the user's folders' files.
  (define (world-entries)
    (append
     (apply append
            (map (lambda (folder)
                   (let* ([dir (string-append *schevana-root* "/schevana/"
                                              folder)]
                          [libs (if (file-directory? dir)
                                    (map (lambda (f)
                                           (cons (path-root f)
                                                 (list 'schevana
                                                       (string->symbol folder)
                                                       (string->symbol
                                                        (path-root f)))))
                                         (filter (lambda (f)
                                                   (string-suffix? ".sls" f))
                                                 (directory-list dir)))
                                    '())]
                          [files (map (lambda (f)
                                        (cons (path-root (path-last f)) f))
                                      (folder-sources folder))])
                     (map cdr (sort (lambda (a b) (string<? (car a) (car b)))
                                    (append libs files)))))
                 source-folders))
     (user-folder-files)))

  ;; The world's libraries "/" imports (as a reload imports them again), so
  ;; that one new since is imported at the next.
  (define-state *world-imported* '())

  ;; The world's sources into "/" (core1-boot!, reload!): in the library
  ;; edition the basics first, a copy of "/"'s own. The folders may import
  ;; the libraries shipped in the tree; each loaded by then is seen as it
  ;; reads, for the next reload to tell a change (reload-mark!), and its
  ;; text kept, as a file's is, for what describes a name.
  (define (load-world!)
    (hashtable-clear! *world-readers*)
    (add-library-directory! *schevana-root*)
    (load-sources! (if (schevana-hacker?)
                       (world-entries)
                       (cons "src/base.ss" (world-entries))))
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

  ;; Makes "/", which imports what the core gives the world (its facade,
  ;; again at each reload of a library it stands on), and loads the
  ;; world's files into it (load-world!); in the hacker edition, "/" is
  ;; where every library was spliced, this thread's environment. "/" is
  ;; then this thread's, where what evaluates by name, a load among it,
  ;; evaluates. On core1's thread, which it says is core1's. => "/".
  (define (core1-boot! options)
    (core1-thread!)
    (set! *schevana-options* options)
    (let ([world (if (schevana-hacker?)
                     (interaction-environment)
                     (copy-environment (scheme-environment) #t))])
      (set! *world-env* world)
      (unless (schevana-hacker?) (reload-import! world '(schevana core)))
      (interaction-environment world)
      (load-world!)
      world)))
