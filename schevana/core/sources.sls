;;; (schevana core sources) — the world's files, loaded into "/" at boot
;;; and at every (reload!), with the user's files, and "/" itself: core1's
;;; boot makes "/", importing the core's facade, (schevana core), and loads
;;; the world into it. The texts of what was loaded are kept, for whatever
;;; describes a name.

(library (schevana core sources)
  (export
    *world-env* *schevana-options* schevana-hacker? core1-boot! core1-exported
    load-user-init! source-files *auto-loads* auto-loads auto-load!
    auto-load-forget! auto-load-entries auto-load-layer library-file-layer
    world-app-file? world-after-load! *source-texts* keep-source-text!
    load-file! load-user-folders! reload! program-world! look-load!
    *world-later* world-load-now!)
  (import (chezscheme)
          (only (schevana base) condition->string define-made define-state
                library-layer set-hook! string-prefix? string-suffix?)
          (only (schevana tree) *schevana-root*)
          (only (schevana reload) reload-import! reload-libraries! reload-mark!
                reload-source)
          (only (schevana core theme-table) world-value)
          (only (schevana core processes) *reloading* core1-thread! current-proc
                notify request-redraw! safely)
          (only (schevana core loop) add-library-directory! collector-settle!
                loop-stepped! path-full reload-ended! user-directory
                user-library-directory)
          (only (schevana core theme) style-chain chain-ref theme-default)
          (only (schevana core platform) now-ms))

  (library-layer core)

  ;; "/", the world's environment, once core1 has made it. Lookups by name
  ;; go here, not to (interaction-environment), which a private REPL
  ;; rebinds.
  (define-state *world-env* #f)

  ;; What the command line asked for (desktop-options, (schevana desktop
  ;; main)), handed down as core1 boots.
  (define-state *schevana-options* '())

  ;; Whether this is the hacker edition (src/hacker.ss), where every library
  ;; is spliced into the top level, which is "/" itself.
  (define (schevana-hacker?)
    (let ([o (assq 'hacker *schevana-options*)]) (and o (cdr o))))

  ;; For a name that "/" has as a macro (a view of the core's, a state or a
  ;; hook), a procedure that reads it there. Each is compiled once and kept
  ;; until the world loads again (load-world!), since a reload may make the
  ;; core's names anew.
  (define-made *world-readers* (make-eq-hashtable))

  (define (world-reader name)
    (or (hashtable-ref *world-readers* name #f)
        (let ([read (eval `(lambda () ,name) *world-env*)])
          (hashtable-set! *world-readers* name read)
          read)))

  ;; Returns name's value as the world has it: "/"'s own, or what "/"
  ;; imports from the core. Code that calls a procedure by its name, so that
  ;; a redefinition takes effect at the next call, looks it up this way.
  (set-hook! (world-value name)
    (cond
      [(not *world-env*)
       (errorf 'world-value "~s: there is no world yet" name)]
      [(top-level-bound? name *world-env*) (top-level-value name *world-env*)]
      [else ((world-reader name))]))

  ;; The names the core gives the world: its facade's.
  (define (core1-exported) (library-exports '(schevana core)))

  ;; The user's init file, ~/.schevana.ss, loaded into the world after the
  ;; world has booted (desktop-start!).
  (define-made user-init-file
    (format "~a/.schevana.ss" (or (getenv "HOME") ".")))

  (define (load-user-init!)
    (when (file-exists? user-init-file)
      (safely 'init (lambda () (load-file! user-init-file)))))

  ;; The folders after the core, in load order, which is the layers' order
  ;; (library-layer, (schevana base)): the looks before the desktop.
  (define source-folders
    '("kits" "services" "styles" "palettes" "wallpapers" "desktop" "apps"))

  ;; The desktop turns this on: a real session loads the user's folders
  ;; too, at boot and at every (reload!).
  (define-state *user-folders?* #f)

  ;; A file name relative to the tree, or an absolute one (the user's).
  (define (source-path f)
    (if (path-absolute? f) f (string-append *schevana-root* "/" f)))

  ;;; ---- what loads
  ;;; The world loads folders at boot and at every (reload!). Each folder is
  ;;; read again each time, recursively, and its libraries (.sls) and files
  ;;; (.ss) load in file-name order. Schevana's own come first: the tree's
  ;;; folders in the layers' order and, once the desktop turns them on, the
  ;;; user's folders. Then come the folders of the library search that
  ;;; auto-load (auto-load!, the desktop's command line, Settings' Paths),
  ;;; in the order they were turned on.

  ;; The library search's folders that auto-load, in full.
  (define-state *auto-loads* '())

  ;; The user's folders, named as in source-folders, in ~/.schevana.d.
  (define (user-folders)
    (map (lambda (f) (path-full (string-append user-directory "/" f)))
         source-folders))

  ;; Every file and folder that loads, in full, in order.
  (define (auto-loads)
    (append (map (lambda (f)
                   (path-full (format "~a/schevana/~a" *schevana-root* f)))
                 source-folders)
            (if *user-folders?* (user-folders) '())
            *auto-loads*))

  ;; folder, in full (path-full), joins the library search if it isn't
  ;; there (add-library-directory!) and auto-loads; with a world, what it
  ;; holds loads now. Returns the folders that auto-load.
  (define (auto-load! folder)
    (let ([p (path-full folder)])
      (when (and (file-exists? p) (not (file-directory? p)))
        (errorf 'auto-load! "~a is not a folder" p))
      (add-library-directory! p)
      (unless (member p (auto-loads))
        (set! *auto-loads* (append *auto-loads* (list p)))
        (when *world-env* (load-sources! (auto-load-entries p))))
      *auto-loads*))

  ;; folder no longer auto-loads, from the next (reload!) or boot on; it
  ;; stays in the library search, and what it loaded stays. Only a folder
  ;; turned on by auto-load! can be turned off. Returns the folders that
  ;; auto-load.
  (define (auto-load-forget! folder)
    (set! *auto-loads* (remove (path-full folder) *auto-loads*))
    *auto-loads*)

  ;; Returns what path holds, in load order: a library by its name, a file
  ;; by its path (relative to the tree when inside it). A folder's entries
  ;; come recursively, in file-name order, leaving out names that start with
  ;; a dot (editors' lock files) and a folder beside a library of its name
  ;; (demo/boids3d/ beside demo/boids3d.sls): that folder holds the
  ;; library's parts, which load as its imports and are none of the
  ;; world's. A path that isn't there gives nothing.
  (define (auto-load-entries path)
    (cond
      [(file-directory? path)
       (apply append
              (map (lambda (f) (auto-load-entries (string-append path "/" f)))
                   (sort string<?
                         (remp (lambda (f)
                                 (or (string-prefix? "." f)
                                     (file-exists?
                                      (string-append path "/" f ".sls"))))
                               (directory-list path)))))]
      [(string-suffix? ".sls" path)
       (let ([name (auto-load-library path)]) (if name (list name) '()))]
      [(and (string-suffix? ".ss" path) (file-exists? path))
       (list (tree-relative path))]
      [else '()]))

  ;; Returns f relative to the tree when it is inside it, else f as it is;
  ;; f and the tree are in full.
  (define (tree-relative f)
    (let ([root (string-append (path-full *schevana-root*) "/")])
      (if (string-prefix? root f)
          (substring f (string-length root) (string-length f))
          f)))

  ;; The layer that each auto-loaded library declares ((library-layer
  ;; layer), first in its body), by the library's name. It tells an app's
  ;; library, which a desktop loads after the screen shows, from a kit's or
  ;; a look's.
  (define-made *auto-load-layers* (make-hashtable equal-hash equal?))
  (define (auto-load-layer name) (hashtable-ref *auto-load-layers* name #f))

  ;; Returns the name of the library in file, as its first form says, or #f
  ;; if file holds none. It also adds to the library search the folder from
  ;; which that name finds the file, and keeps the layer the library
  ;; declares (auto-load-layer).
  (define (auto-load-library file)
    (let* ([head (library-head-in file)] [name (and head (car head))])
      (when name
        (hashtable-set! *auto-load-layers* name (cdr head))
        (add-library-directory!
         (let up ([dir (path-parent file)] [n (- (length name) 1)])
           (if (= n 0) dir (up (path-parent dir) (- n 1))))))
      name))

  ;; Returns the layer that the library in file declares, or #f: its
  ;; library-layer form, first in its body or later ((schevana base)'s comes
  ;; after the definitions that make the form).
  (define (library-file-layer file)
    (let ([head (library-head-in file)])
      (and head
           (or (cdr head)
               (guard (c [#t #f])
                 (exists (lambda (form)
                           (and (pair? form) (eq? (car form) 'library-layer)
                                (pair? (cdr form)) (cadr form)))
                         (cddddr (call-with-input-file file read))))))))

  ;; Returns a library's name and the layer it declares, (name . layer),
  ;; with layer #f when its body doesn't begin with one. It reads no further
  ;; than that: past the comments and #! lines before the first form, then
  ;; "(library", the name, the export and import forms and the next form.
  ;; Returns #f for a file that holds no library.
  (define (library-head-in file)
    (guard (c [#t #f])
      (call-with-input-file file
        (lambda (p)
          (let skip ()
            (let ([c (peek-char p)])
              (cond
                [(eof-object? c) #f]
                [(char-whitespace? c) (read-char p) (skip)]
                [(memv c '(#\; #\#)) (get-line p) (skip)]
                [(char=? c #\()
                 (read-char p)
                 (and (eq? (read p) 'library)
                      (let ([name (read p)])
                        (and (list? name) (for-all symbol? name)
                             (begin
                               (read p)   ; its exports
                               (read p)   ; its imports
                               ;; a body with no form ends here
                               (let ([form (guard (c [#t #f]) (read p))])
                                 (cons name
                                       (and (pair? form)
                                            (eq? (car form) 'library-layer)
                                            (pair? (cdr form))
                                            (cadr form))))))))]
                [else #f])))))))

  ;; The world's files, in load order.
  (define (folder-files) (filter string? (world-entries)))

  ;; The world's own files, in load order: a copy of the basics (in the
  ;; library edition), then the folders' files.
  (define (world-sources)
    (if (schevana-hacker?) (folder-files) (cons "src/base.ss" (folder-files))))

  ;; Every source file, in load order: the world's, since the core's are
  ;; libraries. The REPL's docs read this list.
  (define (source-files) (world-sources))

  ;; The text of every source as it was loaded (or, from a REPL, evaluated),
  ;; by its name: a file's path, or what the REPL calls its input. Whatever
  ;; reads the sources (the REPL's descriptions) reads these, not the files
  ;; as they are now, so that it describes the code that runs. Each is
  ;; (serial . text), where the serial counts the texts kept.
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

  ;; Loads one of the world's sources: a file, by its path, or one of the
  ;; world's libraries, by its name, which is imported into "/" (once: a
  ;; reload of a library imports it again there) and run, so that what it
  ;; registers (an app, a style, a surface) is registered.
  (define (load-source f)
    (if (pair? f)
        (begin
          (unless (member f *world-imported*)
            (reload-import! *world-env* f)
            (set! *world-imported* (cons f *world-imported*)))
          (invoke-library f))
        (load-file! (source-path f))))

  ;; Loads files into the world (from a private REPL too), or into env. Run
  ;; as a process (the launcher's "Reload sources", or (reload!) in a REPL),
  ;; it names itself and the file in *reloading* until it ends, so that the
  ;; world holds still meanwhile (schevana-step!); yet it is still
  ;; preempted, and Ctrl+C kills it. It doesn't use dynamic-wind, because
  ;; an engine runs its exits at every preemption.
  (define (load-sources! files . env)
    (let* ([p (current-proc)]
           [outer? (and p (not (and *reloading* (eq? (car *reloading*) p))))])
      (parameterize ([interaction-environment
                      (if (pair? env) (car env) *world-env*)])
        (guard (c [outer? (reload-ended!
                           (format "Reload failed in ~a: ~a"
                                   (cdr *reloading*) (condition->string c)))
                          (raise c)])
          (for-each (lambda (f)
                      (when p (set! *reloading* (cons p f)))
                      (load-source f))
                    files)
          (when outer? (set! *reloading* #f))))))

  ;; Loads the user's folders, after the built-in ones (desktop-start!,
  ;; before the saved theme, which may name a user's style or palette). It
  ;; loads one entry at a time, so that one that raises is named in its
  ;; toast and the rest still load.
  (define (load-user-folders!)
    (set! *user-folders?* #t)
    (add-library-directory! user-library-directory)
    (for-each (lambda (f)
                (if (and *world-later?* (world-app-file? f))
                    (set! *world-later* (append *world-later* (list f)))
                    (safely f (lambda () (load-sources! (list f))))))
              (apply append (map auto-load-entries (user-folders)))))

  ;;; The parts of the world that load after the screen shows (core1-boot!'s
  ;;; later?: the desktop's apps) load one entry per quiet step, a step that
  ;;; drew no frame and wants none, so that the first frame waits for none
  ;;; of them and no frame waits for one; while frames flow, one loads each
  ;;; second anyway. An entry asked for before its turn loads at once
  ;;; (world-load-now!).

  ;; The entries waiting, in load order; whether the world was booted with
  ;; some waiting (then the user's apps wait too); and when an entry last
  ;; loaded.
  (define-state *world-later* '())
  (define-state *world-later?* #f)
  (define-state *world-later-ms* 0)

  ;; Whether f, a file, is an app's: in a folder named apps (the user's, or
  ;; one that auto-loads).
  (define (world-app-file? f)
    (and (string? f)
         (equal? (path-last (path-parent (source-path f))) "apps")))

  ;; Loads entry (a library's name or a file's path) now if it waits.
  ;; Returns whether it did.
  (define (world-load-now! entry)
    (and (member entry *world-later*)
         (begin
           (set! *world-later* (remove entry *world-later*))
           (set! *world-later-ms* (now-ms))
           (safely entry (lambda () (load-sources! (list entry))))
           #t)))

  ;; Thunks to run, in order, once all of the world has loaded, the entries
  ;; that waited too; a thunk runs at once if none waits. Code that names
  ;; what a waiting library gives (the user's init file, a command line's
  ;; expressions) runs here, because a name evaluated at "/" before a
  ;; library is imported there stays a name of "/"'s own.
  (define-state *world-loaded-thunks* '())

  (define (world-after-load! thunk)
    (if (null? *world-later*)
        (thunk)
        (set! *world-loaded-thunks*
          (append *world-loaded-thunks* (list thunk)))))

  (set-hook! (loop-stepped! quiet?)
    (cond
      [(and (pair? *world-later*)
            (or quiet? (>= (- (now-ms) *world-later-ms*) 1000)))
       (world-load-now! (car *world-later*))]
      [(and (null? *world-later*) (pair? *world-loaded-thunks*))
       (let ([ts *world-loaded-thunks*])
         (set! *world-loaded-thunks* '())
         (for-each (lambda (t) (safely 'loaded t)) ts))]))


  ;; Core0's libraries stay as core0 booted them, with all they import: its
  ;; thread runs them, and they change with a restart.
  (define (source-held-libraries)
    (filter (lambda (name)
              (and (> (length name) 2)
                   (eq? (car name) 'schevana)
                   (eq? (cadr name) 'core0)))
            (library-list)))

  ;; Re-reads every source file: the libraries whose files changed and
  ;; those that import them (reload-libraries!), which imports them again
  ;; where they were imported ("/" imports the core's facade); then the
  ;; world's files into "/". Code changes take effect; state declared with
  ;; defvar or define-state (windows, theme, processes...) survives.
  ;; Run as a process, a reload holds the world still from its start, while
  ;; it evaluates the libraries again too, until the world's files are
  ;; loaded (load-sources! names each file in *reloading* as it goes).
  (define (reload!)
    (let ([p (current-proc)])
      (when p (set! *reloading* (cons p "the libraries")))
      (guard (c [p (reload-ended! (format "Reload failed in ~a: ~a"
                                          (cdr *reloading*)
                                          (condition->string c)))
                   (raise c)])
        (source-libraries-keep!
         (if (schevana-hacker?)
             ((eval 'hacker-reload-libraries! *world-env*)
              (source-held-libraries))
             (reload-libraries! (source-held-libraries))))
        (load-world!))
      (when p (set! *reloading* #f)))
    (request-redraw!)
    (collector-settle!)
    (notify "Sources reloaded" 'green))

  ;; The world's sources in load order, read again from what loads
  ;; (auto-loads): a library by its name, a file by its path.
  (define (world-entries) (apply append (map auto-load-entries (auto-loads))))

  ;; The world's libraries that "/" imports (a reload imports them again),
  ;; so that a library new since the last load is imported at the next one.
  (define-state *world-imported* '())

  ;; Loads the world's sources into "/" (core1-boot!, reload!): in the
  ;; library edition, the basics first, a copy of "/"'s own. The folders may
  ;; import the libraries shipped in the tree; each one loaded by then is
  ;; marked as it reads now, so that the next reload can tell a change
  ;; (reload-mark!), and its text is kept, as a file's is, for whatever
  ;; describes a name. The entries that later? picks wait (*world-later*);
  ;; none wait at a reload.
  (define (load-world! . later?)
    (hashtable-clear! *world-readers*)
    (add-library-directory! *schevana-root*)
    (let* ([entries (if (schevana-hacker?)
                        (world-entries)
                        (cons "src/base.ss" (world-entries)))]
           [wait? (if (pair? later?) (car later?) (lambda (e) #f))])
      (set! *world-later* (filter wait? entries))
      (set! *world-later?* (pair? later?))
      (set! *world-later-ms* (now-ms))
      (load-sources! (remp wait? entries)))
    (reload-mark!)
    (source-libraries-keep! (library-list)))

  ;; Keeps the texts of the named libraries that are read from a file, for
  ;; those that changed: a text kept again is read again by whatever
  ;; describes names.
  (define (source-libraries-keep! names)
    (for-each (lambda (name)
                (let ([file (reload-source name)])
                  (when file
                    (let ([text (file-text file)]
                          [had (hashtable-ref *source-texts* file #f)])
                      (unless (and had (string=? (cdr had) text))
                        (keep-source-text! file text))))))
              names))

  ;; Makes a program's "/", where code that calls by name finds what it
  ;; calls (a part's built-in, the procedures a style names, world-value).
  ;; It holds Chez's names, the core's facade and the world's libraries that
  ;; the program has loaded (a kit, a look, a demo, a game), as "/" has them
  ;; on the desktop. The looks among them are run, as the desktop runs
  ;; them, so that what they register (a style, a palette) is registered
  ;; though the program named none of it. It is made once, as the program
  ;; runs (schevana-main); a world booted by core1-boot! has its own.
  (define (program-world!)
    (unless *world-env*
      (let ([world (copy-environment (scheme-environment) #t)]
            [names (filter (lambda (name)
                             (or (memq (car name) '(demo games))
                                 (and (eq? (car name) 'schevana)
                                      (= (length name) 3)
                                      (member (symbol->string (cadr name))
                                              source-folders))))
                           (library-list))])
        (eval `(import (schevana core) ,@names) world)
        (set! *world-env* world)
        (for-each invoke-library
                  (filter (lambda (name)
                            (memq (cadr name) '(styles palettes wallpapers)))
                          names)))))

  ;; Loads a look of the tree's by its name, as a program asks for one (a
  ;; host app): the style's library is loaded and run, then the palettes it
  ;; names (its palette, its dark one, or the default), and nothing else of
  ;; the looks. They go into "/" when there is one, as the world's libraries
  ;; do; before that, the program's "/" takes them as it is made
  ;; (program-world!). Returns name, or #f when the tree has no such style.
  (define (look-load! name)
    (and (look-file? "styles" name)
         (begin
           (look-run! (list 'schevana 'styles name))
           (for-each
            (lambda (p)
              (when (and p (look-file? "palettes" p))
                (look-run! (list 'schevana 'palettes p))))
            (let ([chain (style-chain name)])
              (list (chain-ref chain 'palette (theme-default 'palette))
                    (chain-ref chain 'palette-dark #f))))
           name)))

  (define (look-file? folder name)
    (file-exists? (format "~a/schevana/~a/~a.sls" *schevana-root* folder
                          name)))

  (define (look-run! name)
    (if *world-env*
        (load-source name)
        (begin (environment name) (invoke-library name))))

  ;; Makes "/", which imports what the core gives the world (its facade,
  ;; imported again at each reload of a library it stands on), and loads the
  ;; world's files into it (load-world!). In the hacker edition, "/" is the
  ;; environment where every library was spliced, this thread's. "/" then
  ;; becomes this thread's interaction environment, where whatever
  ;; evaluates by name (a load, say) evaluates. It runs on core1's thread
  ;; and marks that thread as core1's. The entries that later? picks, if
  ;; given, load after the screen shows. Returns "/".
  (define (core1-boot! options . later?)
    (core1-thread!)
    (set! *schevana-options* options)
    (let ([world (if (schevana-hacker?)
                     (interaction-environment)
                     (copy-environment (scheme-environment) #t))])
      (set! *world-env* world)
      (unless (schevana-hacker?) (reload-import! world '(schevana core)))
      (interaction-environment world)
      (apply load-world! later?)
      world)))
