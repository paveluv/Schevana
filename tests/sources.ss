;;; tests/sources.ss — checks of the sources themselves, which guard the
;;; world's one shared namespace against collisions and the layers against
;;; crossings.
;;;
;;;   scheme --script tests/sources.ss
;;;
;;; Every line of every source file fits in 80 columns; no top-level name
;;; is defined in two files; the core stays within its budget of tokens;
;;; above the core nothing calls C; only (schevana ffi) loads a shared
;;; library; each layer names only what the layer
;;; below gives it; a library of Schevana's imports with only and names all
;;; it imports (its own parts it imports whole), and every name a library
;;; exports is used; nothing below
;;; the apps names an app's; only a world
;;; namespace shares the whole world with an environment; every file in a
;;; folder registers what it defines (a kit's or a service's names start
;;; with its prefix; desktop/ defines plain names); a style sets only
;;; settings that exist (built in, its options' or its own); in the kits,
;;; the services, the desktop layer, Tasks, Settings, Environments and the
;;; Pipeline only the drawing procedures draw or name a color, and the edit
;;; kit never does; and only styles call a part's built-in body. The suite
;;; is fast: it loads the world but does not boot it.

(define *schevana-root*
  (let ([dir (path-parent (path-parent (car (command-line))))])
    (if (string=? dir "") "." dir)))

;; Runs of Chez through /bin/sh (test-chez), for running this file again.
(load (string-append *schevana-root* "/tests/chez.ss"))
(load (string-append *schevana-root* "/tests/lib.ss"))

;; Prints the problems found, one per line; true when there are none.
(define (none? problems)
  (for-each (lambda (p) (printf "  ~a\n" p)) problems)
  (null? problems))

;; A file's lines, as wc -l counts them.
(define (file-lines f)
  (let ([ls (reverse
             (string-split (call-with-input-file (source-path f) get-string-all)
                           #\newline))])
    (reverse (if (and (pair? ls) (string=? (car ls) "")) (cdr ls) ls))))

;; Returns a file's forms; for a library's file, the forms of its body,
;; since its exports and imports only declare.
(define (file-forms f)
  (let ([forms (call-with-input-file (source-path f)
                 (lambda (p)
                   (let loop ([acc '()])
                     (let ([x (read p)])
                       (if (eof-object? x)
                           (reverse acc)
                           (loop (cons x acc)))))))])
    (if (and (pair? forms) (null? (cdr forms)) (pair? (car forms))
             (eq? (caar forms) 'library))
        (cddddr (car forms))
        forms)))

;; "schevana/styles/mac.sls" -> "schevana" (the first folder), "mac"
(define (file-folder f) (path-first f))
(define (file-stem f) (path-root (path-last f)))

;;; ------------------------------------------------------------------
;;; 80 columns

;; The .ss files directly in folder.
(define (test-files folder)
  (map (lambda (f) (string-append folder "/" f))
       (filter (lambda (f) (string=? (path-extension f) "ss"))
               (sort string<? (directory-list (source-path folder))))))

;; The libraries below the world (under schevana/): all of core0's, the
;; recorder's and the core's code is in them, sealed. The world's own
;; files are (source-files).
(define library-files test-core-libraries)

;; Every library in the tree: under schevana/, the core's and those above
;; it; under demo/, the demos'; and under games/, the games'.
(define all-library-files
  (apply append
         (map (lambda (top)
                (let walk ([dir top])
                  (apply append
                         (map (lambda (f)
                                (let ([path (string-append dir "/" f)])
                                  (cond [(file-directory? (source-path path))
                                         (walk path)]
                                        [(string=? (path-extension f) "sls")
                                         (list path)]
                                        [else '()])))
                              (sort string<?
                                    (directory-list (source-path dir)))))))
              '("schevana" "demo" "games"))))

;; Each of Schevana's libraries, under schevana/, declares its layer first
;; (library-layer, from (schevana base)), which holds its imports to the
;; layers' order as it compiles; a demo or a game, like any library from
;; outside, needs none.
(check "every library of Schevana's declares its layer first"
       (none? (filter-map
               (lambda (f)
                 (let ([body (file-forms f)])
                   (and (not (and (pair? body) (pair? (car body))
                                  (eq? (caar body) 'library-layer)))
                        (not (equal? f "schevana/base.sls"))
                        (format "~a declares no layer first" f))))
               (filter (lambda (f) (string-prefix? "schevana/" f))
                       all-library-files))))

;; Returns the names of the record types that forms define with no
;; nongenerative clause, wherever in forms they are (but in quoted data
;; and syntax templates).
(define (generative-records forms)
  (let walk ([xs forms] [acc '()])
    (fold-left
     (lambda (acc x)
       (cond
         [(not (and (pair? x) (list? x))) acc]
         [(memq (car x) '(quote quasiquote syntax quasisyntax)) acc]
         [(and (eq? (car x) 'define-record-type) (pair? (cdr x)))
          (if (exists (lambda (c)
                        (and (pair? c) (eq? (car c) 'nongenerative)))
                      (cddr x))
              acc
              (cons (if (pair? (cadr x)) (caadr x) (cadr x)) acc))]
         [else (walk x acc)]))
     acc xs)))

;; A record type outlives a reload of its library only when it is
;; nongenerative (docs/INTERNALS.md): one made anew would not recognize
;; the records made before.
(check "every record type of the tree's libraries is nongenerative"
       (none? (apply append
                     (map (lambda (f)
                            (map (lambda (name)
                                   (format "~a: ~a is not nongenerative"
                                           f name))
                                 (generative-records (file-forms f))))
                          all-library-files))))

;; A sealed layer's own libraries: its folder under schevana/, and its
;; facade beside the folder.
(define (layer-libraries folder)
  (filter (lambda (f)
            (or (string-prefix? (string-append "schevana/" folder "/") f)
                (string=? (string-append "schevana/" folder ".sls") f)))
          library-files))

(define line-files
  (append all-library-files
          (source-files)
          (test-files "tests")
          (test-files "tests/units")
          (test-files "tests/fork")
          test-launchers
          '("src/launch.ss" "src/hacker.ss" "src/strip.ss" "src/build.ss")))

(define (long-lines f)
  (let loop ([ls (file-lines f)] [n 1] [acc '()])
    (cond
      [(null? ls) (reverse acc)]
      [(> (string-length (car ls)) 80)
       (loop (cdr ls) (+ n 1)
             (cons (format "~a:~a has ~a characters"
                           f n (string-length (car ls)))
                   acc))]
      [else (loop (cdr ls) (+ n 1) acc)])))

(check (format "every line of the ~a source files is at most 80 characters"
               (length line-files))
       (none? (apply append (map long-lines line-files))))

;;; ------------------------------------------------------------------
;;; one name, one file

;; Returns what a top-level form defines: ((kind . name) ...). Plain
;; definitions are of kind name; each definer's registry is a kind of its
;; own, so a style and a palette may share a name (Genera's do).
(define (defined form)
  (define (record-names spec fields)
    (let* ([type (if (pair? spec) (car spec) spec)]
           [s (symbol->string type)]
           [sym (lambda parts (string->symbol (apply string-append parts)))])
      (append (if (pair? spec)
                  spec
                  (list type (sym "make-" s) (sym s "?")))
              (apply append
                     (map (lambda (fd)
                            (let ([f (symbol->string
                                      (if (pair? fd) (cadr fd) fd))])
                              (cond
                                ;; (immutable name accessor), (mutable name
                                ;; accessor mutator): the names given
                                [(and (pair? fd) (pair? (cddr fd)))
                                 (cddr fd)]
                                [(and (pair? fd) (eq? (car fd) 'mutable))
                                 (list (sym s "-" f) (sym s "-" f "-set!"))]
                                [else (list (sym s "-" f))])))
                          fields)))))
  (define (names kind xs) (map (lambda (x) (cons kind x)) xs))
  (if (and (pair? form) (pair? (cdr form)))
      (let ([head (cadr form)])
        (case (car form)
          [(begin at-load) (apply append (map defined (cdr form)))]
          [(define defvar define-hook define-state define-made define-syntax
            define-foreign define-foreign/collect-safe define-sdl-hook
            define-sdl-hook/collect-safe define-worklet)
           (names 'name (list (if (pair? head) (car head) head)))]
          [(define-app)
           (list (cons 'name (car head)) (cons 'app (car head)))]
          [(define-record-type)
           (let ([fields (find (lambda (c)
                                 (and (pair? c) (eq? (car c) 'fields)))
                               (cddr form))])
             (names 'name (record-names head (if fields (cdr fields) '()))))]
          [(define-part)
           (names 'name (list (car head)
                              (string->symbol (format "~a*" (car head)))))]
          [(define-style) (names 'style (list head))]
          [(define-palette) (names 'palette (list head))]
          [(define-wallpaper) (names 'wallpaper (list head))]
          [(define-surface) (names 'surface (list head))]
          [(define-strip) (names 'strip (list head))]
          [else '()]))
      '()))

(define (definitions f) (apply append (map defined (file-forms f))))

;; Names defined in two files on purpose: ((kind . name) reason) ...
(define defined-twice
  '(((name . define-hook) "a library's keeps the procedure as a state; \
                           the top level's, where any procedure may be \
                           replaced, is a definition like another")
    ((name . define-state) "a library's keeps the value in a global of \
                            Chez's; the top level's is a definition")))

(define world-files (append all-library-files (source-files)))

(check (format "no top-level name is defined in two of the world's ~a files"
               (length world-files))
       (let ([where (make-hashtable equal-hash equal?)])
         (for-each (lambda (f)
                     (for-each (lambda (d)
                                 (hashtable-update! where d
                                   (lambda (fs) (if (member f fs) fs
                                                    (cons f fs)))
                                   '()))
                               (definitions f)))
                   world-files)
         (none? (filter-map
                 (lambda (d)
                   (let ([fs (hashtable-ref where d '())])
                     (and (> (length fs) 1) (not (assoc d defined-twice))
                          (format "~a ~a: ~a" (car d) (cdr d)
                                  (reverse fs)))))
                 (vector->list (hashtable-keys where))))))

;;; ------------------------------------------------------------------
;;; the core's size
;;; Counted in tokens: the atoms the reader sees (symbols, numbers,
;;; strings, characters, booleans). Comments, whitespace, line breaks,
;;; parentheses and the length of a name are free, so the count moves only
;;; with the code itself: less of it, or some of it moved to a later layer.

;; Raise it only on purpose: the core is what the desktop needs to boot
;; and run, and everything else belongs in a later layer. The core is the
;; libraries below the world (under schevana/). What only declares is
;; left out: a library's exports and imports (file-forms), whose size
;; follows from what the library gives, and a change to either is
;; reviewed anyway.
(define src-budget 42278)

;; The number of tokens in a datum as read; a list's end counts as none.
(define (tokens x)
  (cond [(pair? x) (+ (tokens (car x))
                      (if (null? (cdr x)) 0 (tokens (cdr x))))]
        [(vector? x) (apply + (map tokens (vector->list x)))]
        [else 1]))

(let* ([counts (map (lambda (f)
                      (cons f (apply + (map tokens
                                            (remp (lambda (x)
                                                    (and (pair? x)
                                                         (memq (car x)
                                                               '(import
                                                                 export))))
                                                  (file-forms f))))))
                    library-files)]
       [n (apply + (map cdr counts))])
  (check (format "the core is ~a tokens, within its budget of ~a (to grow \
                  it, raise src-budget in tests/sources.ss on purpose)"
                 n src-budget)
         (or (<= n src-budget)
             ;; over: each file's share, the largest first
             (none? (map (lambda (c) (format "~a: ~a tokens" (car c) (cdr c)))
                         (sort (lambda (a b) (> (cdr a) (cdr b))) counts))))))

;;; ------------------------------------------------------------------
;;; one owner
;;; Outside the core, only the file that defines a global sets it; the
;;; others call its procedures. The core's hooks are the exception: they
;;; are there for a later layer to set. A fluid-let (a temporary view) is
;;; not a set.

;; The hooks that the core's facade gives settable (define-settable).
(define core-hooks
  (filter-map (lambda (x)
                (and (pair? x) (eq? (car x) 'define-settable) (cadr x)))
              (file-forms "schevana/core.sls")))

;; The names a file defines at its top level.
(define (top-level-names f)
  (filter-map (lambda (x)
                (and (pair? x) (memq (car x) '(define defvar)) (pair? (cdr x))
                     (let ([h (cadr x)])
                       (cond [(symbol? h) h]
                             [(and (pair? h) (symbol? (car h))) (car h)]
                             [else #f]))))
              (file-forms f)))

;; The names that x sets with set!, leaving out its quoted data.
(define (set-targets x)
  (cond [(not (pair? x)) '()]
        [(eq? (car x) 'quote) '()]
        [(and (eq? (car x) 'set!) (pair? (cdr x)) (symbol? (cadr x)))
         (cons (cadr x) (set-targets (cddr x)))]
        [else (let loop ([l x] [acc '()])
                (if (pair? l)
                    (loop (cdr l) (append acc (set-targets (car l))))
                    acc))]))

(check "outside src/, no file sets a global another file defines, but the \
        core's hooks"
       (let ([owner (make-eq-hashtable)])
         (for-each (lambda (f)
                     (for-each (lambda (n) (hashtable-set! owner n f))
                               (top-level-names f)))
                   world-files)
         (none?
          (apply append
                 (map (lambda (f)
                        (filter-map
                         (lambda (n)
                           (let ([o (hashtable-ref owner n #f)])
                             (and o (not (equal? o f))
                                  (not (memq n core-hooks))
                                  (format "~a sets ~a, ~a's" f n o))))
                         (apply append (map set-targets (file-forms f)))))
                      (remp (lambda (f) (string-prefix? "src/" f))
                            world-files))))))

;;; ------------------------------------------------------------------
;;; only the core calls C
;;; One of the core's roles is to keep C away from the rest: above the core
;;; (the kits, services, looks, desktop and apps, the demos and the games,
;;; and the world's files), no file names a binding from (schevana ffi),
;;; from the three SDL libraries ((schevana sdl system), (schevana sdl
;;; window), (schevana sdl gpu)), from (schevana freetype) or from
;;; (schevana fontconfig), nor a foreign-… procedure, an ftype form or
;;; load-shared-object. The tests may name all of these but the last (the
;;; next section): they inspect what is drawn and stand in for SDL.

(define ffi-names
  (map cdr (append (definitions "schevana/ffi.sls")
                   (definitions "schevana/sdl/system.sls")
                   (definitions "schevana/sdl/window.sls")
                   (definitions "schevana/sdl/gpu.sls")
                   (definitions "schevana/freetype.sls")
                   (definitions "schevana/fontconfig.sls"))))

(define (reaches-c? s)
  (or (and (memq s (append ffi-names
                           '(define-ftype make-ftype-pointer
                             load-shared-object)))
           #t)
      (exists (lambda (p) (string-prefix? p (symbol->string s)))
              '("foreign-" "ftype-"))))

;; The symbols in x, each once.
(define (symbols-in x)
  (let walk ([x x] [acc '()])
    (cond [(symbol? x) (if (memq x acc) acc (cons x acc))]
          [(pair? x) (walk (cdr x) (walk (car x) acc))]
          [(vector? x) (fold-left (lambda (acc y) (walk y acc)) acc
                                  (vector->list x))]
          [else acc])))

;; Returns the layer that library file f declares first, or #f.
(define (file-layer f)
  (let ([body (file-forms f)])
    (and (pair? body) (pair? (car body)) (eq? (caar body) 'library-layer)
         (pair? (cdar body)) (cadar body))))

;; The files above the core: the libraries under schevana/ whose layer is
;; above it, the demos' and the games', and the world's files but src/'s.
(define above-core-files
  (filter (lambda (f)
            (if (string-prefix? "schevana/" f)
                (memq (file-layer f) '(kits services looks desktop apps))
                (not (equal? (file-folder f) "src"))))
          world-files))

;; The GPU layer speaks the world's terms: above it, in the core too,
;; nothing names SDL, Vulkan, SPIR-V, Metal or MSL, so that another back
;; end, or raw Vulkan, is the GPU layer's business alone. Core0 keeps SDL,
;; along with the clock and the CPU count. Which platform this is,
;; including its GPU's API, is named only where it is decided, in
;; (schevana core platform).
(define above-gpu-files
  (remp (lambda (f)
          (member f '("schevana/ffi.sls" "schevana/shader.sls"
                      "schevana/sdl.sls" "schevana/sdl/system.sls"
                      "schevana/sdl/window.sls"
                      "schevana/sdl/gpu.sls"
                      "schevana/core0/mail.sls"
                      "schevana/core0/renderer.sls"
                      "schevana/core0/present.sls"
                      "schevana/core0/platform.sls"
                      "schevana/core0/gpu.sls"
                      "schevana/core0/window.sls"
                      "schevana/core/fonts.sls"
                      "schevana/core/platform.sls")))
        world-files))

(define (names-a-back-end? s)
  (let ([name (symbol->string s)])
    (or (string-prefix? "sdl-" name)
        (string-contains-ci? name "spirv")
        (string-contains-ci? name "vulkan")
        (string-contains-ci? name "msl")
        (string-contains-ci? name "metal"))))

(check (format "above the GPU layer (~a files) no name is SDL's, Vulkan's, \
                SPIR-V's, Metal's or MSL's" (length above-gpu-files))
       (none? (apply append
                     (map (lambda (f)
                            (map (lambda (s) (format "~a names ~a" f s))
                                 (reverse (filter names-a-back-end?
                                                  (symbols-in
                                                   (file-forms f))))))
                          above-gpu-files))))

(check (format "above the core (~a files) nothing reaches C: no binding of \
                core0's or core1's (~a), no foreign-… or ftype form"
               (length above-core-files) (length ffi-names))
       (none? (apply append
                     (map (lambda (f)
                            (map (lambda (s) (format "~a names ~a" f s))
                                 (reverse (filter reaches-c?
                                                  (symbols-in
                                                   (file-forms f))))))
                          above-core-files))))

;;; ------------------------------------------------------------------
;;; only (schevana ffi) loads a shared library
;;; Chez's load-shared-object keeps each library's handle where its
;;; collector reads it as an object, and a Mac's handle need not look like
;;; one that the collector leaves alone: once the heap has grown over the
;;; address the handle names, a full collection ends the process. (schevana
;;; ffi) loads every library the tree binds, on a Mac without Chez's
;;; procedure (ffi-load-library). So no other file names
;;; load-shared-object anywhere, its imports included: not a library, a
;;; file of the world's or of src/, a launcher or a test. Two tests name it
;;; to check for the name, and call nothing. A page of the docs doesn't
;;; show it as code either (below, with the docs' checks).

;; The files that name load-shared-object on purpose, and how many times
;; each does: (file times reason) ...
(define shared-object-namers
  '(("schevana/ffi.sls" 2 "it loads the process itself, and a library \
                           where Chez's own loading is safe")
    ("tests/sources.ss" 1 "the names that reach C")
    ("tests/units/env.ss" 1 "the names a confined environment never holds")))

;; The tree's Scheme files: the programs at its root but the shell
;; scripts, and every .ss and .sls under its folders of sources, wherever
;; it is (but a file whose name starts with a dot, an editor's).
(define scheme-files
  (append
   (remp (lambda (f) (string=? (path-extension f) "sh")) test-launchers)
   (apply append
          (map (lambda (top)
                 (let walk ([dir top])
                   (apply append
                          (map (lambda (f)
                                 (let ([path (string-append dir "/" f)])
                                   (cond [(string-prefix? "." f) '()]
                                         [(file-directory? (source-path path))
                                          (walk path)]
                                         [(member (path-extension f)
                                                  '("ss" "sls"))
                                          (list path)]
                                         [else '()])))
                               (sort string<?
                                     (directory-list (source-path dir)))))))
               '("schevana" "demo" "games" "src" "tests")))))

;; Whether s is Chez's name for loading a shared library, under a prefix
;; that an import gave it too.
(define (shared-object-name? s)
  (and (symbol? s) (string-suffix? "load-shared-object" (symbol->string s))))

;; Returns how many times x, something read, names load-shared-object.
(define (shared-object-count x)
  (cond [(shared-object-name? x) 1]
        [(pair? x)
         (+ (shared-object-count (car x)) (shared-object-count (cdr x)))]
        [(vector? x) (shared-object-count (vector->list x))]
        [else 0]))

;; Returns how many times f names load-shared-object, among all that the
;; reader finds in f, a library's exports and imports included. A
;; launcher's first line, #!/usr/bin/env ..., is the shell's, and is
;; passed over as load passes over it.
(define (shared-object-names f)
  (let* ([text (call-with-input-file (source-path f) get-string-all)]
         [p (open-input-string text)])
    (when (and (> (string-length text) 2)
               (string=? (substring text 0 2) "#!")
               (memv (string-ref text 2) '(#\/ #\space)))
      (get-line p))
    (shared-object-count
     (let loop ([acc '()])
       (let ([x (read p)])
         (if (eof-object? x) acc (loop (cons x acc))))))))

(check (format "of the ~a Scheme files only (schevana ffi) names \
                load-shared-object, and two tests that check for the name; \
                each file listed for it names it as many times as listed"
               (length scheme-files))
       (none? (filter-map
               (lambda (f)
                 (let ([names (shared-object-names f)]
                       [listed (cond [(assoc f shared-object-namers) => cadr]
                                     [else 0])])
                   (and (not (= names listed))
                        (format "~a names load-shared-object ~a time~:p, \
                                 and is listed for ~a"
                                f names listed))))
               (append scheme-files
                       (remp (lambda (f) (member f scheme-files))
                             (map car shared-object-namers))))))

;;; ------------------------------------------------------------------
;;; which platform this is, said in one place
;;; Which OS, windowing system or desktop this is, and the places where
;;; the system keeps what it says about itself, are read only in the
;;; platform files (AGENTS.md); the rest of the code asks their predicates
;;; and facts. Monitor's Platform tab shows Chez's machine type as it is,
;;; so the inspect kit is among the files.

;; (schevana sdl window) is among them too: it binds SDL's call for the
;; video driver, for core0's platform file to read
(define platform-files
  '("schevana/base.sls" "schevana/core/platform.sls"
    "schevana/sdl/window.sls"
    "schevana/core0/platform.sls" "schevana/kits/inspect.sls"))

;; The strings in x.
(define (strings-in x)
  (cond [(string? x) (list x)]
        [(pair? x) (append (strings-in (car x)) (strings-in (cdr x)))]
        [(vector? x) (apply append (map strings-in (vector->list x)))]
        [else '()]))

(define (reads-the-platform? x)
  (or (and (symbol? x)
           (memq x '(machine-type sdl-get-current-video-driver)))
      (and (string? x)
           (or (string-prefix? "/proc/" x)
               (string-prefix? "/etc/os-release" x)
               (string=? "XDG_CURRENT_DESKTOP" x)))))

(check "only the platform files read which platform this is"
       (none? (apply append
                     (map (lambda (f)
                            (map (lambda (x) (format "~a reads ~s" f x))
                                 (filter reads-the-platform?
                                         (append (symbols-in (file-forms f))
                                                 (strings-in
                                                  (file-forms f))))))
                          (remp (lambda (f) (member f platform-files))
                                world-files)))))

;;; ------------------------------------------------------------------
;;; the chain: core0, the recorder, core1, the world
;;; Each layer is given what the layer below gives it (its facade), and
;;; names nothing else of that layer's, nor of the layers under it whose
;;; names the facade gives again; core0 names nothing of the core above
;;; it, which a launcher boots. A library can't reach past a facade
;;; anyway, since it is held to its layer as it compiles; these checks say
;;; where it tries, before a boot finds out.

;; The names that a layer's files define; src/base.ss's are left out,
;; being every environment's own.
(define (layer-names files)
  (map cdr (apply append (map definitions (remove "src/base.ss" files)))))

;; A layer is its libraries, its code sealed in them.
(define core0-chain-files (layer-libraries "core0"))
(define recorder-chain-files (layer-libraries "recorder"))
(define core1-chain-files (layer-libraries "core"))

(define core0-names (layer-names core0-chain-files))
(define recorder-names (layer-names recorder-chain-files))

;; Core1's names: what its libraries define and what they export,
;; including the names their macros make (a layout's fields); not Chez's,
;; nor src/base.ss's, nor those of the libraries below the layers, which
;; any layer may import.
(define core1-names
  (let* ([chez (scheme-environment)]
         [sealed (append core0-chain-files recorder-chain-files
                         core1-chain-files)]
         [base (map cdr (append (definitions "src/base.ss")
                                (apply append
                                       (map definitions
                                            (remp (lambda (f)
                                                    (member f sealed))
                                                  library-files)))))])
    (remp (lambda (s)
            (or (gensym? s) (memq s base)
                (top-level-bound? s chez) (top-level-syntax? s chez)))
          (append (layer-names core1-chain-files)
                  (apply append
                         (map (lambda (f)
                                (library-exports
                                 (cadr (call-with-input-file (source-path f)
                                         read))))
                              core1-chain-files))))))

;; The world's own files: the basics, the folders' files, and every
;; library above the core (the desktop's start among them).
(define world-own-files
  (append (source-files)
          (remp (lambda (f) (member f library-files)) all-library-files)))

;; The symbols x names as code, each once: what's quoted is data, and in a
;; quasiquote only what's unquoted is code.
(define (code-symbols-in x)
  (define (data x acc)
    (cond [(and (pair? x) (memq (car x) '(unquote unquote-splicing)))
           (code (cdr x) acc)]
          [(pair? x) (data (cdr x) (data (car x) acc))]
          [(vector? x) (fold-left (lambda (a y) (data y a)) acc
                                  (vector->list x))]
          [else acc]))
  (define (code x acc)
    (cond [(symbol? x) (if (memq x acc) acc (cons x acc))]
          [(and (pair? x) (eq? (car x) 'quote)) acc]
          [(and (pair? x) (eq? (car x) 'quasiquote)) (data (cdr x) acc)]
          [(pair? x) (code (cdr x) (code (car x) acc))]
          [(vector? x) (fold-left (lambda (a y) (code y a)) acc
                                  (vector->list x))]
          [else acc]))
  (code x '()))

;; Returns what files name as code out of names, except what is given and
;; what they define themselves, each as "f names s".
(define (names-beyond files names given)
  (let ([own (apply append (map (lambda (f) (map cdr (definitions f)))
                                files))])
    (apply append
           (map (lambda (f)
                  (map (lambda (s) (format "~a names ~a" f s))
                       (filter (lambda (s)
                                 (and (memq s names) (not (memq s given))
                                      (not (memq s own))))
                               (reverse
                                (code-symbols-in
                                 ;; an import form names libraries
                                 (remp (lambda (x)
                                         (and (pair? x) (eq? (car x) 'import)))
                                       (file-forms f)))))))
                files))))

;; What core0 names of the core above it: nothing, since a launcher boots
;; both (src/launch.ss).
(define core0-reaches-up '())

(check "core0 names nothing of the recorder's or core1's"
       (none? (names-beyond core0-chain-files
                            (append recorder-names core1-names)
                            core0-reaches-up)))

(check "the recorder names nothing of core0's but what core0 gives it"
       (none? (names-beyond recorder-chain-files core0-names
                            (library-exports '(schevana core0 for-recorder)))))

(check "core1 names nothing of core0's or the recorder's but what their \
        facades give it"
       (none? (names-beyond core1-chain-files
                            (append core0-names recorder-names)
                            (append (library-exports '(schevana core0))
                                    (library-exports '(schevana recorder))))))

(check "the world names nothing of the core's (core0's, the recorder's, \
        core1's) but what the core's facade gives it"
       (none? (names-beyond world-own-files
                            (append core0-names recorder-names core1-names)
                            (library-exports '(schevana core)))))

;; In a library, a hook made as it loads (define-hook, set-hook!) names
;; nothing that the library defines after it: Chez would check each such
;; reference at every call, and the check's flag would go into closures
;; made as the world runs, which would then allocate
;; (tests/units/allocation.ss).
(define (hook-faults f)
  (let loop ([forms (file-forms f)] [acc '()])
    (if (null? forms)
        (reverse acc)
        (let* ([x (car forms)]
               [hook? (and (pair? x) (pair? (cdr x))
                           (memq (car x) '(define-hook set-hook!)))]
               [later (if hook?
                          (map cdr (apply append (map defined (cdr forms))))
                          '())]
               [name (and hook? (if (pair? (cadr x)) (caadr x) (cadr x)))])
          (loop (cdr forms)
                (append (reverse
                         (map (lambda (s)
                                (format "~a: hook ~a names ~a, defined after it"
                                        f name s))
                              (filter (lambda (s) (memq s later))
                                      (if hook? (code-symbols-in (cddr x))
                                          '()))))
                        acc))))))

(check "in a library, no hook names what the library defines after it"
       (none? (apply append (map hook-faults all-library-files))))

;; src/base.ss belongs to every environment, a copy each, so it keeps no
;; state and calls no C. Neither does (schevana base), the basics'
;; library.
(check "src/base.ss and (schevana base) are pure: no defvar, no set! of \
        their own names, no C"
       (let ([forms (append (file-forms "src/base.ss")
                            (file-forms "schevana/base.sls"))]
             [own (map cdr (append (definitions "src/base.ss")
                                   (definitions "schevana/base.sls")))])
         (none? (append
                 (filter-map (lambda (x)
                               (and (pair? x) (eq? (car x) 'defvar)
                                    (format "defvar ~a" (cadr x))))
                             forms)
                 (map (lambda (n) (format "sets ~a" n))
                      (filter (lambda (n) (memq n own))
                              (apply append (map set-targets forms))))
                 (map (lambda (s) (format "names ~a" s))
                      (filter reaches-c? (reverse (symbols-in forms))))))))

;; The SDL calls that the core above core0 still makes: none. The list
;; stays for what a later change may have to list.
(define core-sdl-left '())

;; SDL's calls that may block: getting and handing back the screen's
;; image, the event poll (SDL's handlers inside it took 65 ms over a
;; window's change), and the waits for the GPU. Each is collect-safe, so
;; that a core0 held in one stalls no collection that another thread needs
;; (.work/gpu-design.md 9.6).
(define sdl-blocking
  '("SDL_AcquireGPUSwapchainTexture"
    "SDL_SubmitGPUCommandBuffer"
    "SDL_SubmitGPUCommandBufferAndAcquireFence"
    "SDL_PollEvent"
    "SDL_WaitEventTimeout"
    "SDL_PushEvent"
    "SDL_WaitForGPUFences"
    "SDL_WaitForGPUIdle"
    "SDL_SetGPUSwapchainParameters"))

(check "every SDL call that may block is collect-safe"
       (let ([forms (append (file-forms "schevana/sdl/window.sls")
                            (file-forms "schevana/sdl/gpu.sls"))])
         (none? (filter-map
                 (lambda (c)
                   (let ([f (find (lambda (x)
                                    (and (pair? x) (pair? (cdr x))
                                         (pair? (cddr x))
                                         (equal? (caddr x) c)))
                                  forms)])
                     (cond [(not f) (format "not bound: ~a" c)]
                           [(memq (car f) '(define-foreign/collect-safe
                                            define-sdl-hook/collect-safe))
                            #f]
                           [else (format "not collect-safe: ~a" c)])))
                 sdl-blocking))))

(check "only core0 names SDL's bindings, but what's listed, on its way out"
       (let ([sdl (filter (lambda (n)
                            (string-prefix? "sdl-" (symbol->string n)))
                          core0-names)])
         (none? (apply append
                       (map (lambda (f)
                              (map (lambda (s) (format "~a names ~a" f s))
                                   (filter (lambda (s)
                                             (and (memq s sdl)
                                                  (not (memq s core-sdl-left))))
                                           (reverse (symbols-in
                                                     (file-forms f))))))
                            (remp (lambda (f) (member f core0-chain-files))
                                  world-files))))))

;;; ------------------------------------------------------------------
;;; imports and exports
;;; A library of Schevana's (under schevana/) imports each of the tree's
;;; libraries with only, naming what it uses, and uses every name it names.
;;; Its own parts, the libraries in the folder of its name, it imports
;;; whole, as a part does its siblings; a demo or a game imports every
;;; library whole, as a program from outside would.
;;; A library exports only what something uses: a library that imports it,
;;; a program at the tree's root or in src/, or, where "/" has the
;;; library's names (the world's libraries and the core's facade), the
;;; docs or a lookup by name. The tests reach the rest by themselves
;;; (tests/build.ss).

;; The symbols that x names as code, each once. What's quoted is data, and
;; in a quasiquote only what's unquoted is code; so are a layer's name, a
;; case's labels, what a macro's patterns match and a record's fields.
(define (code-references x)
  (define (data x acc)
    (cond [(and (pair? x) (memq (car x) '(unquote unquote-splicing)))
           (code (cdr x) acc)]
          [(pair? x) (data (cdr x) (data (car x) acc))]
          [(vector? x) (fold-left (lambda (a y) (data y a)) acc
                                  (vector->list x))]
          [else acc]))
  (define (codes xs acc)
    (if (pair? xs) (codes (cdr xs) (code (car xs) acc)) acc))
  (define (clauses cs acc)   ; a macro's: the fender and template are code
    (if (pair? cs)
        (clauses (cdr cs) (if (pair? (car cs)) (codes (cdar cs) acc) acc))
        acc))
  (define (code x acc)
    (cond
      [(symbol? x) (if (memq x acc) acc (cons x acc))]
      [(vector? x) (fold-left (lambda (a y) (code y a)) acc (vector->list x))]
      [(not (pair? x)) acc]
      [(eq? (car x) 'quote) acc]
      [(eq? (car x) 'quasiquote) (data (cdr x) acc)]
      [(eq? (car x) 'library-layer) (code (car x) acc)]
      [(and (eq? (car x) 'case) (pair? (cdr x)))
       (fold-left (lambda (a c) (if (pair? c) (codes (cdr c) a) a))
                  (code (cadr x) (code (car x) acc))
                  (cddr x))]
      [(and (eq? (car x) 'syntax-rules) (pair? (cdr x)))
       (clauses (cddr x) (code (car x) acc))]
      [(and (eq? (car x) 'syntax-case) (pair? (cdr x)) (pair? (cddr x)))
       (clauses (cdddr x) (code (cadr x) (code (car x) acc)))]
      [(and (eq? (car x) 'define-record-type) (pair? (cdr x)))
       (fold-left (lambda (a c)
                    (if (and (pair? c)
                             (memq (car c) '(fields nongenerative sealed
                                             opaque)))
                        a
                        (code c a)))
                  (code (car x) acc)
                  (cddr x))]
      [else (code (cdr x) (code (car x) acc))]))
  (code x '()))

;; The quoted symbols in x: in a quote, and in a quasiquote's data.
(define (quoted-symbols x)
  (let walk ([x x] [quoted? #f] [acc '()])
    (cond [(symbol? x) (if quoted? (cons x acc) acc)]
          [(and (pair? x) (memq (car x) '(quote quasiquote)) (pair? (cdr x)))
           (walk (cadr x) #t acc)]
          [(and (pair? x) (memq (car x) '(unquote unquote-splicing)))
           (walk (cdr x) #f acc)]
          [(pair? x) (walk (cdr x) quoted? (walk (car x) quoted? acc))]
          [(vector? x) (fold-left (lambda (a y) (walk y quoted? a)) acc
                                  (vector->list x))]
          [else acc])))

;; The tree's libraries, each (file . library form).
(define tree-forms
  (map (lambda (f) (cons f (call-with-input-file (source-path f) read)))
       all-library-files))

(define (tree-file e) (car e))
(define (tree-name e) (cadr (cdr e)))
(define (tree-imports e) (cdr (cadddr (cdr e))))
(define (tree-body e) (cddddr (cdr e)))

;; The names an export clause gives, as the importers see them.
(define (clause-exports clause)
  (apply append
         (map (lambda (s)
                (cond [(symbol? s) (list s)]
                      [(and (pair? s) (eq? (car s) 'rename))
                       (map cadr (cdr s))]
                      [else '()]))
              (cdr clause))))

;; The names an export clause gives as the library itself names them.
(define (clause-own-names clause)
  (apply append
         (map (lambda (s)
                (cond [(symbol? s) (list s)]
                      [(and (pair? s) (eq? (car s) 'rename))
                       (map car (cdr s))]
                      [else '()]))
              (cdr clause))))

;; Returns the library an import spec names, and what it gives, as
;; (name (exported . local) ...); #f for a library of Chez's own.
;; exports-of returns a tree library's exports, or #f.
(define (spec-names spec exports-of)
  (let resolve ([s spec])
    (define (inner f)
      (let ([r (resolve (cadr s))]) (and r (cons (car r) (f (cdr r))))))
    (cond
      [(and (pair? s) (eq? (car s) 'only))
       (inner (lambda (ps) (filter (lambda (p) (memq (cdr p) (cddr s))) ps)))]
      [(and (pair? s) (eq? (car s) 'except))
       (inner (lambda (ps) (remp (lambda (p) (memq (cdr p) (cddr s))) ps)))]
      [(and (pair? s) (eq? (car s) 'prefix))
       (inner (lambda (ps)
                (map (lambda (p)
                       (cons (car p)
                             (string->symbol
                              (string-append (symbol->string (caddr s))
                                             (symbol->string (cdr p))))))
                     ps)))]
      [(and (pair? s) (eq? (car s) 'rename))
       (inner (lambda (ps)
                (map (lambda (p)
                       (let ([m (assq (cdr p) (cddr s))])
                         (if m (cons (car p) (cadr m)) p)))
                     ps)))]
      [(exports-of s) => (lambda (ns) (cons s (map (lambda (n) (cons n n))
                                                   ns)))]
      [else #f])))

;; The import specs of a body's (export (import spec ...)): what the
;; library gives again whole.
(define (body-given body)
  (apply append
         (map (lambda (x)
                (if (and (pair? x) (eq? (car x) 'export) (pair? (cdr x))
                         (pair? (cadr x)) (eq? (caadr x) 'import))
                    (cdadr x)
                    '()))
              body)))

;; Each library's exports: its export clause's, and what its body gives
;; again.
(define tree-export-table
  (let ([clauses (map (lambda (e)
                        (cons (tree-name e) (clause-exports (caddr (cdr e)))))
                      tree-forms)])
    (map (lambda (e)
           (cons (tree-name e)
                 (append (cdr (assoc (tree-name e) clauses))
                         (apply append
                                (map (lambda (spec)
                                       (map cdr
                                            (cdr (spec-names
                                                  spec
                                                  (lambda (n)
                                                    (let ([c (assoc n clauses)])
                                                      (and c (cdr c))))))))
                                     (body-given (tree-body e)))))))
         tree-forms)))

(define (tree-exports name)
  (let ([e (assoc name tree-export-table)]) (and e (cdr e))))

;; A macro that names something in its user's scope: define-part defines
;; a hook there, so its user imports define-hook.
(define implied-names '((define-part define-hook)))

;; Returns what library e names as code, its export clause included (a
;; facade gives again what it imports) and what its macros need.
(define (library-references e)
  (let ([named (append (code-references (tree-body e))
                       (clause-own-names (caddr (cdr e))))])
    (append (apply append (map (lambda (i) (if (memq (car i) named)
                                               (cdr i)
                                               '()))
                               implied-names))
            named)))

;; Whether the library name is a part of e's own: one in the folder of e's
;; name, or, when e is a part, of its front's. The sealed layers' libraries,
;; beside their facades, are not parts.
(define (own-part? e name)
  (define (front n) (list-head n (- (length n) 1)))
  (and (> (length name) 3)
       (assoc (front name) tree-export-table)
       (or (equal? (front name) (tree-name e))
           (and (> (length (tree-name e)) 3)
                (equal? (front name) (front (tree-name e)))))))

;; Returns the problems with library e's imports of the tree's libraries:
;; one imported whole, or a name it lists and never names; or one of its
;; own parts imported with only, or whole but never named.
(define (import-problems e)
  (let ([named (library-references e)])
    (apply append
           (map (lambda (spec)
                  (let ([r (spec-names spec tree-exports)]
                        [only (let strip ([s spec])
                                (cond [(and (pair? s) (eq? (car s) 'prefix))
                                       (strip (cadr s))]
                                      [(and (pair? s) (eq? (car s) 'only)) s]
                                      [else #f]))])
                    (cond
                      [(not r) '()]
                      [(and only (own-part? e (car r)))
                       (list (format "~a imports its part ~s with only"
                                     (tree-file e) (car r)))]
                      [(own-part? e (car r))
                       (if (exists (lambda (p) (memq (cdr p) named)) (cdr r))
                           '()
                           (list (format "~a imports ~s and names none of it"
                                         (tree-file e) (car r))))]
                      [(not only)
                       (list (format "~a imports ~s whole" (tree-file e)
                                     (car r)))]
                      [else
                       (map (lambda (p)
                              (format "~a imports ~a from ~s and never names \
                                       it" (tree-file e) (cdr p) (car r)))
                            (remp (lambda (p) (memq (cdr p) named))
                                  (cdr r)))])))
                (tree-imports e)))))

(check "a library of Schevana's imports each of the tree's libraries with \
        only, and names every name it imports, but its own parts whole"
       (none? (apply append
                     (map import-problems
                          (filter (lambda (e)
                                    (string-prefix? "schevana/" (tree-file e)))
                                  tree-forms)))))

;; Whether "/" has library e's names: one of the world's (a library with
;; no layer, or one above the core) or the core's facade.
(define (world-visible? e)
  (or (equal? (tree-name e) '(schevana core))
      (not (memq (file-layer (tree-file e))
                 '(foundation core0 recorder core)))))

;; Returns the forms in file f, past a #! line; none if it holds no Scheme.
(define (program-forms f)
  (guard (c [#t '()])
    (call-with-input-file (source-path f)
      (lambda (p)
        (when (eqv? (peek-char p) #\#) (get-line p))
        (let loop ([acc '()])
          (let ([x (read p)])
            (if (eof-object? x) (reverse acc) (loop (cons x acc)))))))))

;; Returns a table of the symbols in xs.
(define (symbol-table xs)
  (let ([t (make-eq-hashtable)])
    (for-each (lambda (s) (hashtable-set! t s #t)) xs)
    t))

;; What the programs at the tree's root and in src/ name, by name too (a
;; launcher names its library's main).
(define program-names
  (symbol-table
   (apply append
          (map (lambda (f) (symbols-in (program-forms f)))
               (append test-launchers
                       (map (lambda (f) (string-append "src/" f))
                            (filter (lambda (f)
                                      (string=? (path-extension f) "ss"))
                                    (directory-list (source-path "src")))))))))

;; The docs' pages, and what they show: in their scheme blocks, what the
;; code names; in their prose, between backquotes, a call's head, or a
;; name alone but on the pages about the core's insides and the platforms.
(define doc-pages
  (cons "README.md"
        (map (lambda (f) (string-append "docs/" f))
             (filter (lambda (f) (string-suffix? ".md" f))
                     (sort string<? (directory-list (source-path "docs")))))))

(define (doc-names-of page)
  (let loop ([ls (file-lines page)] [block #f] [code '()] [prose '()])
    (define (read-all text)
      (let ([p (open-string-input-port text)])
        (let next ([acc '()])
          (let ([x (guard (c [#t (eof-object)]) (read p))])
            (if (eof-object? x) (reverse acc) (next (cons x acc)))))))
    (define (spans text)   ; what sits between backquotes
      (let next ([i 0] [acc '()])
        (let* ([a (let find ([k i])
                    (cond [(>= k (string-length text)) #f]
                          [(char=? (string-ref text k) #\`) k]
                          [else (find (+ k 1))]))]
               [b (and a (let find ([k (+ a 1)])
                           (cond [(>= k (string-length text)) #f]
                                 [(char=? (string-ref text k) #\`) k]
                                 [else (find (+ k 1))])))])
          (if b
              (next (+ b 1) (cons (substring text (+ a 1) b) acc))
              acc))))
    (define (name code)
      (let ([x (guard (c [#t #f]) (read (open-string-input-port code)))])
        (cond [(and (pair? x) (symbol? (car x))) (list (car x))]
              [(and (symbol? x)
                    (not (member page '("docs/INTERNALS.md"
                                        "docs/PLATFORMS.md"))))
               (list x)]
              [else '()])))
    (cond
      [(null? ls)
       (append (code-references
                (read-all (apply string-append (reverse code))))
               (apply append
                      (map name
                           (spans (apply string-append (reverse prose))))))]
      [(and (not block) (string-prefix? "```scheme" (car ls)))
       (loop (cdr ls) 'scheme code prose)]
      [(and (not block) (string-prefix? "```" (car ls)))
       (loop (cdr ls) 'other code prose)]
      [(and block (string=? (car ls) "```")) (loop (cdr ls) #f code prose)]
      [(eq? block 'scheme)
       (loop (cdr ls) block (cons (string-append (car ls) "\n") code) prose)]
      [block (loop (cdr ls) block code prose)]
      [else
       (loop (cdr ls) block code (cons (string-append (car ls) "\n") prose))])))

(define doc-names (symbol-table (apply append (map doc-names-of doc-pages))))

;; Returns the texts of page's scheme blocks, those that run and those
;; only shown.
(define (doc-scheme-blocks page)
  (let loop ([ls (file-lines page)] [block #f] [acc '()])
    (cond
      [(null? ls) (reverse acc)]
      [(and (not block) (string-prefix? "```scheme" (car ls)))
       (loop (cdr ls) '() acc)]
      [(and block (string=? (car ls) "```"))
       (loop (cdr ls) #f
             (cons (apply string-append (reverse block)) acc))]
      [block (loop (cdr ls) (cons (string-append (car ls) "\n") block) acc)]
      [else (loop (cdr ls) #f acc)])))

;; A page's scheme blocks run at "/", which has Chez's names
;; (tests/units/docs.ss), and a reader types what a page shows. So no block
;; names load-shared-object, among what the reader finds in it before
;; anything it can't read.
(check "no page of the docs shows load-shared-object as code"
       (none? (filter-map
               (lambda (page)
                 (and (exists
                       (lambda (text)
                         (let ([p (open-input-string text)])
                           (let next ()
                             (let ([x (guard (c [#t (eof-object)])
                                        (read p))])
                               (and (not (eof-object? x))
                                    (or (> (shared-object-count x) 0)
                                        (next)))))))
                       (doc-scheme-blocks page))
                      (format "~a names load-shared-object" page)))
               (cons "CREDITS.md" doc-pages))))

;; What the tree's libraries look up in "/" by name: world-value's name;
;; a symbol in a registry's form or a theme setting's, which names a
;; procedure; a part's built-in body (name*), which its default names; and
;; a symbol in a quasiquote's data, code made to be evaluated.
(define by-name-forms
  '(define-style define-palette define-wallpaper define-surface define-strip
    theme-default! set-theme! override!))

(define (by-name-references x)
  (let walk ([x x] [acc '()])
    (cond [(not (pair? x)) acc]
          [(and (eq? (car x) 'world-value) (pair? (cdr x))
                (pair? (cadr x)) (eq? (caadr x) 'quote) (pair? (cdadr x)))
           (cons (cadadr x) acc)]
          [(memq (car x) (cons 'quasiquote by-name-forms))
           (append (quoted-symbols x) acc)]
          [(and (eq? (car x) 'define-part) (pair? (cdr x)) (pair? (cadr x)))
           (cons (string->symbol (format "~a*" (caadr x)))
                 (walk (cddr x) acc))]
          [else (walk (cdr x) (walk (car x) acc))])))

(define by-name-names
  (symbol-table
   (apply append (map (lambda (e) (by-name-references (tree-body e)))
                      tree-forms))))

;; Returns each export that nothing uses, as "nothing uses n of library".
(define (export-problems)
  (let ([used (make-hashtable equal-hash equal?)])   ; (library . name)
    (define (use! lib n) (hashtable-set! used (cons lib n) #t))
    (for-each
     (lambda (e)
       (let ([named (library-references e)])
         (for-each (lambda (spec)
                     (let ([r (spec-names spec tree-exports)])
                       (when r
                         (for-each (lambda (p)
                                     (when (memq (cdr p) named)
                                       (use! (car r) (car p))))
                                   (cdr r)))))
                   (tree-imports e))))
     tree-forms)
    ;; what a body gives again is used where the library's own export is
    (for-each
     (lambda (e)
       (for-each (lambda (spec)
                   (let ([r (spec-names spec tree-exports)])
                     (for-each (lambda (p)
                                 (when (hashtable-ref used
                                                      (cons (tree-name e)
                                                            (cdr p))
                                                      #f)
                                   (use! (car r) (car p))))
                               (cdr r))))
                 (body-given (tree-body e))))
     tree-forms)
    (apply append
           (map (lambda (e)
                  (map (lambda (n)
                         (format "nothing uses ~a of ~s" n (tree-name e)))
                       (remp (lambda (n)
                               (or (hashtable-ref used (cons (tree-name e) n)
                                                  #f)
                                   (hashtable-ref program-names n #f)
                                   (and (world-visible? e)
                                        (or (hashtable-ref doc-names n #f)
                                            (hashtable-ref by-name-names n
                                                           #f)))))
                             (tree-exports (tree-name e)))))
                tree-forms))))

(check "every name a library exports is used: by a library that imports \
        it, by a program at the tree's root or in src/, or, where \"/\" has \
        it, by the docs or by a lookup by name"
       (none? (export-problems)))

;;; ------------------------------------------------------------------
;;; nothing below the apps names an app
;;; An app, a demo or a game may be anyone's, and come and go: the layers
;;; below them (core0, the core, the kits, the services, the looks and the
;;; desktop) name nothing that one defines or registers, in code or by
;;; name (a setting a style gives, world-value's name). What a style
;;; changes in an app's look is a kit's part, which the app draws with. An
;;; app's launcher is left out: its name is a plain word, which the world
;;; has other uses for (the status bar's clock).

;; The libraries of the apps, the demos and the game.
(define app-files
  (filter (lambda (f)
            (or (not (string-prefix? "schevana/" f))
                (eq? (file-layer f) 'apps)))
          all-library-files))

;; The theme keys that forms register: color-default!'s and
;; theme-default!'s first argument.
(define (registered-keys x)
  (let walk ([x x] [acc '()])
    (cond [(not (pair? x)) acc]
          [(and (memq (car x) '(color-default! theme-default!))
                (pair? (cdr x)) (pair? (cadr x)) (eq? (caadr x) 'quote)
                (pair? (cdadr x)))
           (cons (cadadr x) acc)]
          [else (walk (cdr x) (walk (car x) acc))])))

;; Each name an app, a demo or the game owns, with its file.
(define app-owned
  (let ([t (make-eq-hashtable)])
    (for-each
     (lambda (f)
       (let* ([ds (definitions f)]
              [launchers (map cdr (filter (lambda (d) (eq? (car d) 'app))
                                          ds))])
         (for-each (lambda (n)
                     (unless (memq n launchers) (hashtable-set! t n f)))
                   (append (map cdr ds) (registered-keys (file-forms f))))))
     app-files)
    t))

(check "nothing below the apps names what an app, a demo or a game defines \
        or registers"
       (none? (apply append
                     (map (lambda (f)
                            (map (lambda (n)
                                   (format "~a names ~a, ~a's" f n
                                           (hashtable-ref app-owned n #f)))
                                 (filter (lambda (n)
                                           (hashtable-ref app-owned n #f))
                                         (reverse
                                          (symbols-in (file-forms f))))))
                          (filter (lambda (f)
                                    (and (string-prefix? "schevana/" f)
                                         (not (member f app-files))))
                                  all-library-files)))))

;;; ------------------------------------------------------------------
;;; sharing the whole world
;;; Code that makes an environment shares a list of names with it. Every
;;; name of the world's, kept in step with the world, is a world
;;; namespace's alone, which a person asks for on purpose (a REPL's, or a
;;; fork in the Environments app). So only that kind shares the whole
;;; world ((schevana services env)).

(check "only a world namespace shares the whole world with an environment"
       (none? (filter-map
               (lambda (f)
                 (and (not (member f '("schevana/services/env.sls")))
                      (memq 'env-share-world! (symbols-in (file-forms f)))
                      (format "~a calls env-share-world!" f)))
               world-files)))

;;; ------------------------------------------------------------------
;;; memory order between threads
;;; box-cas! orders no memory (Chez's guide), and ARM keeps no order of
;;; its own: another thread may see the writes made before a box-cas! only
;;; after it sees the box-cas! itself. So a procedure that hands data to
;;; another thread fences with a release before its box-cas!, and the
;;; procedure that takes the data fences with an acquire after its own; a
;;; flag, or a count that hands nothing over, needs neither. Every
;;; procedure that calls box-cas! or fences is listed with its fences, so a
;;; new one is a reviewed change; and since box-cas! may fail on ARM with
;;; nothing in its way, each one tries again until it succeeds.

(define thread-fences
  '((post-core1! memory-order-release)
    (run-core1-mail! memory-order-acquire)
    (vat-flag-up!)
    (vat-put! memory-order-release)
    (vat-take! memory-order-acquire)
    (crew-join! memory-order-acquire memory-order-release)
    (crew-leave! memory-order-release)
    (crew-error!)
    (crew-add!)
    (crew-done? memory-order-acquire)
    (crew-push! memory-order-release)
    (crew-remove!)
    (crew-claim!)
    (core0-put! memory-order-release)
    (core0-take! memory-order-acquire)
    (gpu-publish! memory-order-release)
    (gpu-present-published! memory-order-acquire)
    (gpu-give-back! memory-order-release)
    (gpu-frames-back! memory-order-acquire)
    (gpu-send-writes! memory-order-release)
    (gpu-present! memory-order-release)
    (core0-frame-report memory-order-acquire)
    (present-sent! memory-order-release)
    (present-publish! memory-order-release)
    (mac-presented! memory-order-release)
    (mac-pump! memory-order-acquire)
    (core0-trace! memory-order-release)
    (core0-trace-rows-of memory-order-acquire)
    (core0-trace-watch! memory-order-acquire)
    (core0-input-set!)
    (core0-input-take!)
    (rec-free? memory-order-acquire)))

(define thread-fence-names '(memory-order-acquire memory-order-release))

;; f's procedures that call box-cas! or fence, each in the form the table
;; lists one: (name fence ...).
(define (file-thread-fences f)
  (filter-map
   (lambda (x)
     (let ([d (defined x)] [s (code-symbols-in x)])
       (and (pair? d)
            (or (memq 'box-cas! s)
                (exists (lambda (n) (memq n s)) thread-fence-names))
            (cons (cdar d)
                  (filter (lambda (n) (memq n s)) thread-fence-names)))))
   (file-forms f)))

(check "every procedure that calls box-cas! or fences is listed, with its \
        fences"
       (let ([found (apply append
                           (map file-thread-fences
                                world-files))])
         (none? (append
                 (filter-map (lambda (p)
                               (and (not (member p thread-fences))
                                    (format "not listed: ~s" p)))
                             found)
                 (filter-map (lambda (p)
                               (and (not (member p found))
                                    (format "not in the tree: ~s" p)))
                             thread-fences)))))

;;; ------------------------------------------------------------------
;;; folders

;; Each file in styles/, palettes/ and wallpapers/ defines one of its kind,
;; named after the file; each file in apps/ defines at least the app named
;; after it. desktop/ has no kind and no prefix: its files define plain
;; names.
(define folder-kinds
  '(("styles" . style) ("palettes" . palette) ("wallpapers" . wallpaper)
    ("apps" . app)))

(define world-symbols (environment-symbols (interaction-environment)))

;; Whether d is registered: a name in the world, an app, a style ...
(define (registered? d)
  (case (car d)
    [(name) (and (memq (cdr d) world-symbols) #t)]
    [(app) (and (memq (cdr d) (apps)) #t)]
    [(style) (and (find-style (cdr d)) #t)]
    [(palette) (and (assq (cdr d) *palettes*) #t)]
    [(wallpaper) (and (assq (cdr d) *wallpapers*) #t)]
    [(surface) (and (find-surface (cdr d)) #t)]
    [(strip) (and (assq (cdr d) *strips*) #t)]))

;; The world's sources from its own folders, as files, in load order, a
;; library given by its file. What else loads with the world (the demos)
;; is not held to the folders' rules.
(define (world-entry-files)
  (filter-map (lambda (e)
                (cond [(string? e) e]
                      [(eq? (car e) 'schevana)
                       (format "schevana/~a/~a.sls" (cadr e) (caddr e))]
                      [else #f]))
              (world-entries)))

;; The folder that a world's source belongs to: kits for
;; schevana/kits/x.sls.
(define (world-folder f)
  (if (string-prefix? "schevana/" f)
      (path-first (substring f 9 (string-length f)))
      (file-folder f)))

(define (folder-problems f)
  (let* ([ds (definitions f)]
         [stem (string->symbol (file-stem f))]
         [kind (cdr (or (assoc (world-folder f) folder-kinds) '(#f . #f)))]
         [own (filter (lambda (d) (eq? (car d) kind)) ds)])
    (append
     (map (lambda (d)
            (format "~a: ~a ~a is not registered" f (car d) (cdr d)))
          (remp registered? ds))
     (cond
       [(equal? (world-folder f) "desktop") '()]
       [(not kind)
        ;; a kit or a service: its names start with its own name (ui-,
        ;; make-ui-state, *complete-open*), or are those of its record of
        ;; the same name (edit, make-edit, edit?)
        (filter-map
         (lambda (d)
           (let* ([s (symbol->string (cdr d))]
                  [s (cond [(string-prefix? "make-" s)
                            (substring s 5 (string-length s))]
                           [(string-prefix? "*" s)
                            (substring s 1 (string-length s))]
                           [else s])]
                  [p (symbol->string stem)])
             (and (not (or (string=? s p) (string=? s (string-append p "?"))
                           (string-prefix? (string-append p "-") s)))
                  (format "~a: ~a lacks the kit's prefix ~a-" f (cdr d) p))))
         ds)]
       [(and (not (eq? kind 'app)) (not (= (length own) 1)))
        (list (format "~a defines ~a of kind ~a, not one" f (length own)
                      kind))]
       [(not (member (cons kind stem) own))
        (list (format "~a does not define the ~a ~a" f kind stem))]
       [else '()]))))

(check (format "every file in ~a registers what it defines"
               (string-join source-folders ", "))
       (none? (apply append (map folder-problems (world-entry-files)))))

;; What the files of everything that loads with the world, the demos too,
;; define of one kind, in load order.
(define (defined-in-files kind)
  (map cdr (filter (lambda (d) (eq? (car d) kind))
                   (apply append
                          (map definitions
                               (map (lambda (e)
                                      (if (pair? e)
                                          (string-append
                                           (string-join
                                            (map symbol->string e) "/")
                                           ".sls")
                                          e))
                                    (world-entries)))))))

;; An app registers as its library runs, after any library it imports
;; (the Debug REPL's library runs the REPL's first), so the apps are
;; compared in any order: the launcher lists them by their titles anyway.
(check "styles, palettes and wallpapers are listed in file-name order, \
        and every app is"
       (let ([sorted (lambda (l)
                       (sort (lambda (a b)
                               (string<? (symbol->string a) (symbol->string b)))
                             l))])
         (and (equal? (styles) (defined-in-files 'style))
              (equal? (palettes) (defined-in-files 'palette))
              (equal? (wallpapers) (defined-in-files 'wallpaper))
              (equal? (sorted (apps)) (sorted (defined-in-files 'app))))))

;; Every app of the tree's (Schevana's own, the demos' and the games')
;; draws its own icon, given after its title (define-app's 'icon), so that
;; where an app shows, its icon shows rather than the stand-in tile.
(define (app-definitions forms)
  (apply append
         (map (lambda (x)
                (cond [(and (pair? x) (memq (car x) '(begin at-load)))
                       (app-definitions (cdr x))]
                      [(and (pair? x) (eq? (car x) 'define-app)) (list x)]
                      [else '()]))
              forms)))

(check "every app of the tree's gives its icon (define-app's 'icon)"
       (none? (apply append
                     (map (lambda (f)
                            (filter-map
                             (lambda (d)
                               (and (not (and (> (length d) 4)
                                              (equal? (list-ref d 3) ''icon)))
                                    (format "~a: ~a" f (caadr d))))
                             (app-definitions (file-forms f))))
                          all-library-files))))

;;; ------------------------------------------------------------------
;;; styles' settings

;; A style sets built-in keys, keys its options declare, and keys of its
;; own, named after it or a parent, so a misspelled key fails here.
(define (style-key-problems s)
  (let* ([chain (style-chain (style-name s))]
         [declared (map car (filter pair? (chain-ref chain 'options '())))]
         [own (map (lambda (c) (format "~a-" (style-name c))) chain)])
    (filter-map
     (lambda (k)
       (and (not (or (memq k meta-keys) (plist-has? default-theme k)
                     (memq k declared)
                     (exists (lambda (p) (string-prefix? p (symbol->string k)))
                             own)))
            (format "style ~a sets ~a, which is no setting" (style-name s) k)))
     (plist-keys (style-settings s)))))

(check "every style sets only settings that exist"
       (none? (apply append (map style-key-problems *styles*))))

;;; ------------------------------------------------------------------
;;; the seam
;;; In the kits, the services, the desktop layer, Tasks, Settings,
;;; Environments and the Pipeline only the drawing procedures draw or
;;; choose a color: parts (define-part), procedures named like a drawing
;;; primitive (draw-…, fill-…) or ui-draw-…, complete-draw-…,
;;; tasks-draw-…, settings-draw-…, envs-draw-…, pipeline-draw-…,
;;; text-draw-…, transcript-draw-… and profile-draw-… (a table of colors
;;; a chart draws with), and the defaults they give (theme-default!,
;;; color-default!: a style may give its own). No other top-level form
;;; calls a drawing primitive or quotes a theme color key (except 'text,
;;; which is also an event's name), so a style restyles all they draw.
;;; The edit kit never draws. And outside styles/ nothing calls a part's
;;; built-in body (name*): a style's own part would be passed by.

(define seam-files
  (append (filter (lambda (f) (member (world-folder f)
                                      '("kits" "services" "desktop")))
                  (world-entry-files))
          '("schevana/apps/tasks.sls" "schevana/apps/settings.sls"
            "schevana/apps/envs.sls" "schevana/apps/pipeline.sls")))

;; The parts: the theme keys whose built-in value is name*, a body of
;; their own.
(define parts
  (filter (lambda (k)
            (let ([v (theme-default k)])
              (and (symbol? v) (string=? (symbol->string v) (format "~a*" k)))))
          (plist-keys default-theme)))
(define built-ins
  (map (lambda (k) (string->symbol (format "~a*" k))) parts))

;; Whether s paints or chooses paint. Calling a part is what other code
;; does (a style's own part then draws); finding where the device's pixels
;; lie (draw-scale) is not painting.
(define (drawing-primitive? s)
  (and (not (memq s parts))
       (not (memq s '(draw-scale)))
       (or (exists (lambda (p) (string-prefix? p (symbol->string s)))
                   '("fill-" "stroke-" "draw-" "px-"))
           (and (memq s '(invert-box add-box pixmap-draw)) #t))))

;; Returns what a form does that only a drawing procedure may do:
;; ((draws . name) (color . key) ...).
(define (seam-problems form)
  (define (quoted x)
    (cond [(and (symbol? x) (memq x color-keys) (not (eq? x 'text)))
           (list (cons 'color x))]
          [(pair? x) (append (quoted (car x)) (quoted (cdr x)))]
          [(vector? x) (quoted (vector->list x))]
          [else '()]))
  (define (quasi x)
    (cond [(and (pair? x) (memq (car x) '(unquote unquote-splicing)))
           (code (cadr x))]
          [(pair? x) (append (quasi (car x)) (quasi (cdr x)))]
          [else (quoted x)]))
  (define (code x)
    (cond
      [(not (pair? x)) '()]
      [(eq? (car x) 'quote) (quoted (cadr x))]
      [(eq? (car x) 'quasiquote) (quasi (cadr x))]
      [else (append (if (and (symbol? (car x)) (drawing-primitive? (car x)))
                        (list (cons 'draws (car x)))
                        '())
                    (let loop ([l x] [acc '()])
                      (if (pair? l)
                          (loop (cdr l) (append acc (code (car l))))
                          acc)))]))
  (code form))

(define (form-name form)
  (and (pair? form)
       (memq (car form) '(define defvar define-hook define-made define-state))
       (pair? (cdr form))
       (if (pair? (cadr form)) (caadr form) (cadr form))))

(define (drawing-form? form)
  (let ([name (form-name form)])
    (or (and name
             (or (drawing-primitive? name)
                 (exists (lambda (p) (string-prefix? p (symbol->string name)))
                         '("ui-draw-" "complete-draw-" "tasks-draw-"
                           "settings-draw-" "envs-draw-" "pipeline-draw-"
                           "text-draw-" "transcript-draw-" "profile-draw-"))))
        (and (pair? form)
             (memq (car form) '(define-part theme-default! color-default!))
             #t))))

;; A file's forms, including those a library runs as it loads (inside
;; at-load).
(define (seam-forms f)
  (let loop ([forms (file-forms f)])
    (apply append
           (map (lambda (x)
                  (if (and (pair? x) (eq? (car x) 'at-load))
                      (loop (cdr x))
                      (list x)))
                forms))))

(define (seam-file-problems f)
  (apply append
         (map (lambda (form)
                (if (drawing-form? form)
                    '()
                    (map (lambda (p)
                           (format "~a: ~a ~a ~a" f
                                   (or (form-name form) (car form))
                                   (car p) (cdr p)))
                         (seam-problems form))))
              (seam-forms f))))

(check (format "in ~a, only drawing procedures draw or name a color"
               (string-join seam-files ", "))
       (none? (apply append (map seam-file-problems seam-files))))

;; The names x calls, its definitions' heads and its data left out.
(define (calls-in x)
  (cond
    [(not (pair? x)) '()]
    [(memq (car x) '(quote quasiquote)) '()]
    [(and (memq (car x) '(define define-part)) (pair? (cdr x))
          (pair? (cadr x)))
     (apply append (map calls-in (cddr x)))]
    [else (append (if (symbol? (car x)) (list (car x)) '())
                  (let loop ([l (cdr x)] [acc '()])
                    (if (pair? l)
                        (loop (cdr l) (append acc (calls-in (car l))))
                        acc)))]))

(check (format "outside styles/ no file calls a part's built-in body (~a \
                parts)" (length built-ins))
       (none? (apply append
                     (map (lambda (f)
                            (map (lambda (n) (format "~a calls ~a" f n))
                                 (filter (lambda (n) (memq n built-ins))
                                         (apply append
                                                (map calls-in
                                                     (file-forms f))))))
                          (remp (lambda (f)
                                  (string-prefix? "schevana/styles/" f))
                                world-files)))))

(check "the REPL's docs read the folders too, parts and their built-ins"
       (for-all (lambda (name) (hashtable-contains? (name-docs) name))
                '("ui-button" "mac-draw-under" "px-bevel" "settings"
                  "ui-draw-button" "ui-draw-button*")))

(check "the tests never load ~/.schevana.d"
       (and (not *user-folders?*) (not (exists path-absolute? (source-files)))))

;; Runs this file again with SCHEVANA_CHECK set to text, as the units'
;; runner runs a topic (through test-chez, so that a Mac's loader path
;; reaches it), and returns its exit status.
(define (sources-run-checking text)
  (system (string-append
           (test-chez (list (cons "SCHEVANA_CHECK" text))
                      (string-append *schevana-root* "/tests/sources.ss"))
           " > /dev/null 2>&1")))

(unless test-only
  (check "SCHEVANA_CHECK stops a run after the first check whose name has \
          its text, as a pass, and a run where none has it fails"
         (and (zero? (sources-run-checking "OUTSIDE SRC/, no file sets"))
              (= 1 (sources-run-checking "no check is named so")))))

(test-verdict!)
