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
    source-path folder-files world-sources source-files *auto-loads*
    auto-loads auto-load! auto-load-forget! auto-load-entries auto-load-layer
    world-app-file? world-after-load!
    *source-texts* keep-source-text! file-text load-file! app-load!
    load-source load-sources!
    load-user-folders! source-held-libraries reload! world-libraries
    world-entries load-world! program-world! look-load! *world-later*
    *world-later-ms* world-load-now!
    source-libraries-keep!)
  (import (chezscheme)
          (schevana base)
          (schevana tree)
          (schevana reload)
          (schevana core0)
          (schevana core theme-table)
          (schevana core processes)
          (schevana core loop)
          (only (schevana core theme) style-chain chain-ref theme-default)
          (only (schevana core platform) now-ms))

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

  ;; The folders after the core, in load order: the layers' (library-layer,
  ;; (schevana base)), the looks before the desktop.
  (define source-folders
    '("kits" "services" "styles" "palettes" "wallpapers" "desktop" "apps"))

  ;; The desktop turns this on: a real session loads the user's folders
  ;; too, at boot and at every (reload!). The tests never do.
  (define-state *user-folders?* #f)

  ;; A file name relative to the tree, or an absolute one (the user's).
  (define (source-path f)
    (if (path-absolute? f) f (string-append *schevana-root* "/" f)))

  ;;; ---- what loads
  ;;; The world loads folders, at boot and at every (reload!), each read
  ;;; again each time, recursively, its libraries (.sls) and files (.ss) in
  ;;; file-name order. Schevana's own come first: the tree's folders in the
  ;;; layers' order, its apps' files, and, once the desktop turns them on,
  ;;; the user's folders; then the folders of the library search that
  ;;; auto-load (auto-load!, the desktop's command line, Settings' Paths),
  ;;; in the order they were turned on.

  ;; The library search's folders that auto-load, in full.
  (define-state *auto-loads* '())

  ;; The user's folders, of source-folders' names, in ~/.schevana.d.
  (define (user-folders)
    (map (lambda (f) (path-full (string-append user-directory "/" f)))
         source-folders))

  ;; Every file and folder that loads, in full, in order.
  (define (auto-loads)
    (append (map (lambda (f)
                   (path-full (format "~a/schevana/~a" *schevana-root* f)))
                 source-folders)
            (list (path-full (string-append *schevana-root* "/apps")))
            (if *user-folders?* (user-folders) '())
            *auto-loads*))

  ;; folder, in full (path-full), joins the library search if it isn't
  ;; there (add-library-directory!) and auto-loads; with a world, what it
  ;; holds loads now. => those that auto-load
  (define (auto-load! folder)
    (let ([p (path-full folder)])
      (when (and (file-exists? p) (not (file-directory? p)))
        (errorf 'auto-load! "~a is not a folder" p))
      (add-library-directory! p)
      (unless (member p (auto-loads))
        (set! *auto-loads* (append *auto-loads* (list p)))
        (when *world-env* (load-sources! (auto-load-entries p))))
      *auto-loads*))

  ;; folder no longer auto-loads, from the next (reload!) or boot; it
  ;; stays in the library search, and what it loaded stays. Only one turned
  ;; on may be turned off. => those that auto-load
  (define (auto-load-forget! folder)
    (set! *auto-loads* (remove (path-full folder) *auto-loads*))
    *auto-loads*)

  ;; What path holds, in load order: a library by its name, a file by its
  ;; path (relative to the tree, inside it); a folder's, recursively, in
  ;; file-name order, names starting with a dot (editors' lock files) left
  ;; out; nothing for what isn't there.
  (define (auto-load-entries path)
    (cond
      [(file-directory? path)
       (apply append
              (map (lambda (f) (auto-load-entries (string-append path "/" f)))
                   (sort string<?
                         (remp (lambda (f) (string-prefix? "." f))
                               (directory-list path)))))]
      [(string-suffix? ".sls" path)
       (let ([name (auto-load-library path)]) (if name (list name) '()))]
      [(and (string-suffix? ".ss" path) (file-exists? path))
       (list (tree-relative path))]
      [else '()]))

  ;; f relative to the tree when inside it, else as it is; f and the tree
  ;; in full.
  (define (tree-relative f)
    (let ([root (string-append (path-full *schevana-root*) "/")])
      (if (string-prefix? root f)
          (substring f (string-length root) (string-length f))
          f)))

  ;; The layer each library auto-loaded declares ((library-layer layer),
  ;; first in its body), by its name: what tells an app's library, which a
  ;; desktop loads after the screen shows, from a kit's or a look's.
  (define-made *auto-load-layers* (make-hashtable equal-hash equal?))
  (define (auto-load-layer name) (hashtable-ref *auto-load-layers* name #f))

  ;; The name of the library in file, as its first form says, the folder
  ;; it is found from by that name added to the library search, and the
  ;; layer it declares kept (auto-load-layer); #f if it holds none.
  (define (auto-load-library file)
    (let* ([head (library-head-in file)] [name (and head (car head))])
      (when name
        (hashtable-set! *auto-load-layers* name (cdr head))
        (add-library-directory!
         (let up ([dir (path-parent file)] [n (- (length name) 1)])
           (if (= n 0) dir (up (path-parent dir) (- n 1))))))
      name))

  ;; A library's name and the layer it declares, (name . layer), its layer
  ;; #f where its body begins with none; read no further than that: the
  ;; comments and #! lines before its first form skipped, then its
  ;; "(library", its name, its export and import forms and the next. #f
  ;; for a file that holds no library.
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
          (for-each (lambda (f)
                      (when p (set! *reloading* (cons p f)))
                      (load-source f))
                    files)
          (when outer? (set! *reloading* #f))))))

  ;; The user's folders, after the built-in ones (desktop-start!, before
  ;; the saved theme, which may name a user's style or palette). One entry
  ;; at a time, so that one which raises is named in its toast and the rest
  ;; still load.
  (define (load-user-folders!)
    (set! *user-folders?* #t)
    (add-library-directory! user-library-directory)
    (for-each (lambda (f)
                (if (and *world-later?* (world-app-file? f))
                    (set! *world-later* (append *world-later* (list f)))
                    (safely f (lambda () (load-sources! (list f))))))
              (apply append (map auto-load-entries (user-folders)))))

  ;;; What of the world loads after the screen shows (core1-boot!'s later?:
  ;;; the desktop's apps): one entry a quiet step, a step that drew no frame
  ;;; and wants none, so that the first frame waits for none of them and no
  ;;; frame for one; while frames flow, one a second anyway. One asked for
  ;;; before its turn loads at once (world-load-now!).

  ;; The entries waiting, in load order; whether the world was booted with
  ;; some to wait (the user's apps wait too, then); when one last loaded.
  (define-state *world-later* '())
  (define-state *world-later?* #f)
  (define-state *world-later-ms* 0)

  ;; Whether f, a file, is an app's: in an apps folder, the tree's or the
  ;; user's.
  (define (world-app-file? f)
    (and (string? f)
         (equal? (path-last (path-parent (source-path f))) "apps")))

  ;; entry (a library's name or a file's path) loaded now if it waits:
  ;; => whether it did.
  (define (world-load-now! entry)
    (and (member entry *world-later*)
         (begin
           (set! *world-later* (remove entry *world-later*))
           (set! *world-later-ms* (now-ms))
           (safely entry (lambda () (load-sources! (list entry))))
           #t)))

  ;; What runs once all of the world has loaded, the entries that waited
  ;; too, in order: at once if none waits. Code that names what a waiting
  ;; library gives (the user's init file, a command line's expressions)
  ;; runs here: a name evaluated at "/" before a library is imported there
  ;; stays a name of "/"'s own.
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

  ;; The world's libraries, by their names.
  (define (world-libraries) (filter pair? (world-entries)))

  ;; The world's sources in load order, read again from what loads
  ;; (auto-loads): a library by its name, a file by its path.
  (define (world-entries) (apply append (map auto-load-entries (auto-loads))))

  ;; The world's libraries "/" imports (as a reload imports them again), so
  ;; that one new since is imported at the next.
  (define-state *world-imported* '())

  ;; The world's sources into "/" (core1-boot!, reload!): in the library
  ;; edition the basics first, a copy of "/"'s own. The folders may import
  ;; the libraries shipped in the tree; each loaded by then is seen as it
  ;; reads, for the next reload to tell a change (reload-mark!), and its
  ;; text kept, as a file's is, for what describes a name. The entries
  ;; later? holds wait (*world-later*); none do at a reload.
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

  ;; A program's "/", where what calls by name finds it (a part's built-in,
  ;; the procedures a style names, world-value): Chez's names, the core's
  ;; facade and the world's libraries the program has loaded, a kit, a
  ;; look, a demo, as "/" has them on the desktop; and each of those run,
  ;; as the desktop runs them, so that what it registers (a style, a
  ;; palette) is registered though the program named none of it. Made once,
  ;; as the program runs (schevana-main); a world booted (core1-boot!) is
  ;; its own.
  (define (program-world!)
    (unless *world-env*
      (let ([world (copy-environment (scheme-environment) #t)]
            [names (filter (lambda (name)
                             (or (eq? (car name) 'schevana-demo)
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

  ;; A look of the tree's by its name, as a program asks for one (a host
  ;; app): the style's library loaded and run, then the palettes it names
  ;; (its palette, its dark one, or the default), and nothing else of the
  ;; looks. Into "/" when there is one, as the world's libraries go; before,
  ;; the program's "/" takes them as it is made (program-world!). => name,
  ;; or #f when the tree has no such style.
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
  ;; again at each reload of a library it stands on), and loads the
  ;; world's files into it (load-world!); in the hacker edition, "/" is
  ;; where every library was spliced, this thread's environment. "/" is
  ;; then this thread's, where what evaluates by name, a load among it,
  ;; evaluates. On core1's thread, which it says is core1's. The entries
  ;; later? holds, if given, load after the screen shows. => "/".
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
