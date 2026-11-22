;;; tests/sources.ss — guards against the one global world's collisions.
;;;
;;;   scheme --script tests/sources.ss
;;;
;;; Every line of every source file fits in 80 columns; no top-level name
;;; is defined in two files; src/ stays within its size budget; outside
;;; src/ nothing calls C; only a world namespace shares the whole world
;;; with an environment; every file in a folder registers what it defines
;;; (a kit's names keep its prefix; desktop/, like src/, defines plain
;;; names); a style sets only settings that exist (built in, its options'
;;; or its own); in the kits, the desktop layer, Tasks, Settings and
;;; Environments only the drawing procedures draw or name a color, and the
;;; edit kit never does; and only styles call a part's built-in body.
;;; Fast: it loads the world but does not boot it.

(define *schevana-root*
  (let ([dir (path-parent (path-parent (car (command-line))))])
    (if (string=? dir "") "." dir)))

;; A run of Chez through /bin/sh (test-chez), for this file run again.
(load (string-append *schevana-root* "/tests/chez.ss"))
(load (string-append *schevana-root* "/tests/lib.ss"))

;; Prints the problems found, one per line; true when there are none.
(define (none? problems)
  (for-each (lambda (p) (printf "  ~a\n" p)) problems)
  (null? problems))

;; Its lines, as wc -l counts them.
(define (file-lines f)
  (let ([ls (reverse
             (string-split (call-with-input-file (source-path f) get-string-all)
                           #\newline))])
    (reverse (if (and (pair? ls) (string=? (car ls) "")) (cdr ls) ls))))

;; A file's forms; a library's file's, those of its body: what it exports
;; and imports declares.
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

;; "(schevana styles mac)" -> "styles", "mac"
(define (file-folder f) (path-first f))
(define (file-stem f) (path-root (path-last f)))

;;; ------------------------------------------------------------------
;;; 80 columns

;; The sources directly in folder.
(define (test-files folder)
  (map (lambda (f) (string-append folder "/" f))
       (filter (lambda (f) (string=? (path-extension f) "ss"))
               (sort string<? (directory-list (source-path folder))))))

;; The libraries below the world (schevana/): core0's, the recorder's and
;; the core's code is all in them, sealed. The world's files are
;; (source-files).
(define library-files test-core-libraries)

;; Every library in the tree: under schevana/, the core's and those above
;; it, and the demos', under schevana-demo/.
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
              '("schevana" "schevana-demo"))))

;; Each declares its layer first (library-layer, (schevana base)), which
;; holds its imports to the layers' order as it compiles.
(check "every library in the tree declares its layer first"
       (none? (filter-map
               (lambda (f)
                 (let ([body (file-forms f)])
                   (and (not (and (pair? body) (pair? (car body))
                                  (eq? (caar body) 'library-layer)))
                        (not (equal? f "schevana/base.sls"))
                        (format "~a declares no layer first" f))))
               all-library-files)))

;; Those of a layer's own, sealed: its folder of schevana/, and its
;; facade beside it.
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
          '("src/launch.ss" "src/hacker.ss" "src/build.ss")))

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

;; What a top-level form defines: ((kind . name) ...). Plain definitions
;; are of kind name; each definer's registry is a kind of its own, so a
;; style and a theme may share a name (Genera's do).
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

;; An app in a sandbox ((schevana services grant)): what its file defines is the
;; sandbox's, but for the app itself, so it collides with nothing.
(define (sandboxed-file? f)
  (and (equal? (file-folder f) "apps")
       (grant-env (string->symbol (file-stem f)))
       #t))

(define (world-definitions f)
  (if (sandboxed-file? f)
      (remp (lambda (d) (eq? (car d) 'name)) (definitions f))
      (definitions f)))

(check (format "no top-level name is defined in two of the world's ~a files"
               (length world-files))
       (let ([where (make-hashtable equal-hash equal?)])
         (for-each (lambda (f)
                     (for-each (lambda (d)
                                 (hashtable-update! where d
                                   (lambda (fs) (if (member f fs) fs
                                                    (cons f fs)))
                                   '()))
                               (world-definitions f)))
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
;;; In tokens: the atoms the reader sees (symbols, numbers, strings,
;;; characters, booleans). Comments, whitespace, line breaks, parentheses
;;; and the length of a name are free, so the count moves only with the
;;; code itself: less of it, or some of it moved to a later layer.

;; Raise it deliberately: the core is what the desktop needs to boot and
;; run; everything else belongs in a folder. The core is the libraries
;; below the world (schevana/). What declares is left out, sized by
;; what's given, each a reviewed change: a library's exports and imports
;; (file-forms).
(define src-budget 38876)

;; The tokens of a datum as read; a list's end is none.
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
;;; are there for a later layer to set. fluid-let (a view for a while) is
;;; not a set.

;; What the core's facade gives settable (define-settable).
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

;; What x sets with set!, its data left out.
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
                   (remp sandboxed-file? world-files))
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
;;; One of the core's roles is to keep C away from the rest: outside src/
;;; and the core's libraries no file names a binding of (schevana ffi)'s,
;;; (schevana sdl)'s three, (schevana freetype)'s or (schevana fontconfig)'s, a
;;; foreign-… procedure, an ftype form or load-shared-object. The tests
;;; may: they inspect what is drawn and stand in for SDL.

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

(define outside-src
  (remp (lambda (f) (member (file-folder f) '("src" "schevana")))
        world-files))

;; The GPU layer speaks the world's terms: above it, in the core too, nothing
;; names SDL's windowless half, Vulkan, SPIR-V, Metal or MSL, so that another
;; back end, or raw Vulkan, is the GPU layer's business alone. Core0 keeps
;; SDL, the clock and the CPU count among it. Which platform this is, its
;; GPU's API among it, is named only where it's said,
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

(check (format "outside src/ (~a files) nothing reaches C: no binding of \
                core0's or core1's (~a), no foreign-… or ftype form"
               (length outside-src) (length ffi-names))
       (none? (apply append
                     (map (lambda (f)
                            (map (lambda (s) (format "~a names ~a" f s))
                                 (reverse (filter reaches-c?
                                                  (symbols-in
                                                   (file-forms f))))))
                          outside-src))))

;;; ------------------------------------------------------------------
;;; which platform this is, said in one place
;;; Which OS, windowing system or desktop this is, and where the system
;;; keeps what it says of itself, are read only in the platform files
;;; (AGENTS.md); the rest asks their predicates and facts. Monitor's
;;; Platform tab shows Chez's machine type as it is.

;; and (schevana sdl window), which binds SDL's video driver for core0's to
;; read
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
;;; Each layer is given what the one below gives it (its facade), and
;;; names nothing else of that one's, nor of those it gave again; core0
;;; names nothing of the core above it, which it boots by name. A library
;;; can't reach past a facade anyway, held to its layer as it compiles;
;;; these say where, before a boot finds it.

;; The names each layer defines; base.ss's are every environment's own.
(define (layer-names files)
  (map cdr (apply append (map definitions (remove "src/base.ss" files)))))

;; A layer is its libraries, its code sealed in them.
(define core0-chain-files (layer-libraries "core0"))
(define recorder-chain-files (layer-libraries "recorder"))
(define core1-chain-files (layer-libraries "core"))

(define core0-names (layer-names core0-chain-files))
(define recorder-names (layer-names recorder-chain-files))

;; Core1's: what its libraries define, and what they export, their
;; macros' too (a layout's fields); not Chez's, nor base.ss's, nor the
;; libraries' below the layers, which any layer may import.
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

;; The world's own files: the basics, the folders, and the libraries above
;; the core (the desktop's start).
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

;; What files name as code of names, but given and their own: "f names s"
;; each.
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

;; What core0 names of the core above it: nothing, as a launcher boots both
;; (src/launch.ss).
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
;; nothing the library defines after it: Chez would check each such
;; reference at every call, and the check's flag goes into closures made
;; as the world runs, which then allocate (tests/units/allocation.ss).
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

;; The docs name what's given for a person at a REPL, which no file may.
(define doc-texts
  (map (lambda (f) (call-with-input-file (source-path f) get-string-all))
       (cons "README.md"
             (map (lambda (f) (string-append "docs/" f))
                  (filter (lambda (f) (string-suffix? ".md" f))
                          (directory-list (source-path "docs")))))))

(check "every name the core gives the world, some file of the world's \
        names, or the docs do"
       (let ([named (make-eq-hashtable)])
         (for-each (lambda (f)
                     (for-each (lambda (s) (hashtable-set! named s #t))
                               (symbols-in (file-forms f))))
                   world-own-files)
         (none? (map (lambda (n) (format "nothing names ~a" n))
                     (remp (lambda (n)
                             (or (hashtable-ref named n #f)
                                 (exists (lambda (text)
                                           (string-contains-ci?
                                            text (symbol->string n)))
                                         doc-texts)))
                           (library-exports '(schevana core)))))))

;; base.ss is every environment's, a copy each: so it keeps no state, and
;; calls no C. Nor does the library the basics are.
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

;; The SDL the core above core0 still calls: none since the window went down
;; to core0; kept for what a later change may have to list.
(define core-sdl-left '())

;; SDL's calls that may block: the screen's hold, the event poll (SDL's
;; handlers inside it took 65 ms over a window's change), waits for the
;; GPU. Each is collect-safe, so that a core0 held in one stalls no
;; collection another thread needs (.work/gpu-design.md 9.6).
(define sdl-blocking
  '("SDL_AcquireGPUSwapchainTexture"
    "SDL_SubmitGPUCommandBuffer"
    "SDL_SubmitGPUCommandBufferAndAcquireFence"
    "SDL_PollEvent"
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
;;; sharing the whole world
;;; Code shares a list of names with an environment it makes; every name
;;; of the world's, followed, is a world namespace's, which a person asks
;;; for on purpose (a REPL's, the Environments app's fork). So only the
;;; kind does ((schevana services env)).

(check "only a world namespace shares the whole world with an environment"
       (none? (filter-map
               (lambda (f)
                 (and (not (member f '("schevana/services/env.sls")))
                      (memq 'env-share-world! (symbols-in (file-forms f)))
                      (format "~a calls env-share-world!" f)))
               world-files)))

;;; ------------------------------------------------------------------
;;; memory order between threads
;;; box-cas! orders no memory (Chez's guide), and ARM keeps no order of its
;;; own: another thread may see what was written before a box-cas! only
;;; after it. So a procedure that hands data to another thread fences with
;;; a release before its box-cas!, and the one that takes the data with an
;;; acquire after; a flag, or a count that hands nothing over, needs
;;; neither. Every procedure that calls box-cas! or fences is listed with
;;; its fences, so a new one is a reviewed change; and as box-cas! may fail
;;; on ARM with nothing in its way, each tries again until it lands.

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

;; f's procedures that call box-cas! or fence, each as the table lists one.
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
;; named after the file; each in apps/ at least the app named after it.
;; desktop/ has no kind and no prefix: its files define plain names.
(define folder-kinds
  '(("styles" . style) ("palettes" . palette) ("wallpapers" . wallpaper)
    ("apps" . app)))

(define world-symbols (environment-symbols (interaction-environment)))

;; d is registered: a name in the world, or in box, the sandbox of the
;; app whose file defines it ((schevana services grant)).
(define (registered? d box)
  (case (car d)
    [(name) (and (memq (cdr d) (if box
                                   (environment-symbols (env-environment box))
                                   world-symbols))
                 #t)]
    [(app) (and (memq (cdr d) (apps)) #t)]
    [(style) (and (find-style (cdr d)) #t)]
    [(palette) (and (assq (cdr d) *palettes*) #t)]
    [(wallpaper) (and (assq (cdr d) *wallpapers*) #t)]
    [(surface) (and (find-surface (cdr d)) #t)]
    [(strip) (and (assq (cdr d) *strips*) #t)]))

;; The world's sources as files, in load order: a library's file for its
;; name.
(define (world-entry-files)
  (map (lambda (e)
         (if (pair? e) (format "schevana/~a/~a.sls" (cadr e) (caddr e)) e))
       (world-entries)))

;; The folder a world's source is of: kits for (schevana kits x) and for
;; schevana/kits/x.sls.
(define (world-folder f)
  (if (string-prefix? "schevana/" f)
      (path-first (substring f 9 (string-length f)))
      (file-folder f)))

(define (folder-problems f)
  (let* ([ds (definitions f)]
         [stem (string->symbol (file-stem f))]
         [kind (cdr (or (assoc (world-folder f) folder-kinds) '(#f . #f)))]
         [own (filter (lambda (d) (eq? (car d) kind)) ds)]
         [box (and (eq? kind 'app) (grant-env stem))])
    (append
     (map (lambda (d)
            (format "~a: ~a ~a is not registered" f (car d) (cdr d)))
          (remp (lambda (d) (registered? d box)) ds))
     (cond
       [(equal? (world-folder f) "desktop") '()]
       [(not kind)
        ;; a kit: its names start with its own (ui-, make-ui-state,
        ;; *complete-open*), or are its record's of the same name (edit,
        ;; make-edit, edit?)
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

;; What the files define, in load order, of one kind.
(define (defined-in-files kind)
  (map cdr (filter (lambda (d) (eq? (car d) kind))
                   (apply append (map definitions (world-entry-files))))))

;; An app registers as its library runs, after any it imports (the Debug
;; REPL's runs the REPL's): the launcher lists them by their titles.
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

;;; ------------------------------------------------------------------
;;; styles' settings

;; A style sets built-in keys, keys its options declare, and its own,
;; named after it or a parent: so a misspelled key fails here.
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
;;; In the kits, the desktop layer, Tasks, Settings and Environments only
;;; the drawing procedures draw or choose a color: parts (define-part),
;;; procedures named like a drawing primitive (draw-…, fill-…) or
;;; ui-draw-…, complete-draw-…, tasks-draw-…, settings-draw-… and
;;; envs-draw-…, and the settings they give (theme-default!: a style may
;;; give its own). No other top-level form calls a drawing primitive or
;;; quotes a theme color key ('text, also an event's name, aside), so a
;;; style restyles all they draw. The edit kit never draws. And outside
;;; styles/ nothing calls a part's built-in body (name*): a style's own
;;; part would be passed by.

(define seam-files
  (append (filter (lambda (f) (member (world-folder f)
                                      '("kits" "services" "desktop")))
                  (world-entry-files))
          '("schevana/apps/tasks.sls" "schevana/apps/settings.sls"
            "schevana/apps/envs.sls" "schevana/apps/pipeline.sls")))

;; The parts: the keys whose built-in is name*, a body of their own.
(define parts
  (filter (lambda (k)
            (let ([v (theme-default k)])
              (and (symbol? v) (string=? (symbol->string v) (format "~a*" k)))))
          (plist-keys default-theme)))
(define built-ins
  (map (lambda (k) (string->symbol (format "~a*" k))) parts))

;; What paints or chooses paint. Calling a part is what other code does
;; (a style's own then draws); finding where the device's pixels lie is not
;; painting.
(define (drawing-primitive? s)
  (and (not (memq s parts))
       (not (memq s '(draw-scale)))
       (or (exists (lambda (p) (string-prefix? p (symbol->string s)))
                   '("fill-" "stroke-" "draw-" "px-"))
           (and (memq s '(invert-box add-box pixmap-draw)) #t))))

;; What a form does that only a drawing procedure may: ((draws . name)
;; (color . key) ...).
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
                           "text-draw-" "transcript-draw-"))))
        (and (pair? form)
             (memq (car form) '(define-part theme-default! color-default!))
             #t))))

;; A file's forms, those a library runs as it loads (at-load) among them.
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
                          (remp (lambda (f) (equal? (file-folder f) "styles"))
                                (source-files))))))

(check "the REPL's docs read the folders too, parts and their built-ins"
       (for-all (lambda (name) (hashtable-contains? (name-docs) name))
                '("ui-button" "mac-draw-under" "px-bevel" "settings"
                  "ui-draw-button" "ui-draw-button*")))

;;; ------------------------------------------------------------------ apps in
;;; sandboxes A tree app that requests bundles runs in a sandbox, approved by
;;; the table in (schevana services grant): what it requests is that, so a new
;;; request is a reviewed change. Sketch is left to the person, to show how an
;;; app of theirs asks.

(define apps-the-person-approves '(sketch))

;; Names the world has for itself: Chez's, and what its own files define.
(define world-own-names
  (let ([t (make-eq-hashtable)])
    (for-each (lambda (s) (hashtable-set! t s #t))
              (environment-symbols (scheme-environment)))
    (for-each (lambda (f)
                (for-each (lambda (d) (hashtable-set! t (cdr d) #t))
                          (world-definitions f)))
              world-files)
    t))

(check "an app in a sandbox keeps its names there: the world holds only its \
        launcher"
       (none?
        (apply append
               (map (lambda (f)
                      (filter-map
                       (lambda (d)
                         (and (eq? (car d) 'name)
                              (memq (cdr d) world-symbols)
                              (not (hashtable-contains? world-own-names
                                                        (cdr d)))
                              (format "~a puts ~a in the world" f (cdr d))))
                       (definitions f)))
                    (filter sandboxed-file? world-files)))))

(check "every bundle names what the world has, each name in one bundle, \
        and every tree app that requests bundles requests what the table \
        approves, or is one the person approves"
       (none?
        (append
         (let loop ([ns (apply append (map grant-bundle-names
                                           (map car grant-bundles)))]
                    [acc '()])
           (cond [(null? ns) acc]
                 [(memq (car ns) (cdr ns))
                  (loop (cdr ns)
                        (cons (format "~a is in two bundles" (car ns)) acc))]
                 [else (loop (cdr ns) acc)]))
         (filter-map (lambda (n)
                       (and (not (memq n world-symbols))
                            (format "a bundle names ~a, not the world's" n)))
                     (apply append (map grant-bundle-names
                                        (map car grant-bundles))))
         (filter-map
          (lambda (f)
            (let ([app (string->symbol (file-stem f))]
                  [asks (grant-requests (source-path f))])
              (and asks
                   (not (if (memq app apps-the-person-approves)
                            (not (assq app grant-tree-apps))
                            (equal? asks (cdr (or (assq app grant-tree-apps)
                                                  '(#f . #f))))))
                   (format "~a requests ~a; the table approves ~a" f asks
                           (cdr (or (assq app grant-tree-apps)
                                    '(#f . none)))))))
          (filter (lambda (f) (equal? (file-folder f) "apps"))
                  (folder-files))))))

(check "the tests never load ~/.schevana.d"
       (and (not *user-folders?*) (not (exists path-absolute? (source-files)))))

;; This file run again with SCHEVANA_CHECK set, as the units' runner runs a
;; topic, so that a Mac's loader path reaches it: its exit status.
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
