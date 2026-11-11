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

(load (string-append *schevana-root* "/load.ss"))
(load (string-append *schevana-root* "/tests/core0.ss"))

(define failures 0)

(define-syntax check
  (syntax-rules ()
    [(_ name expr)
     (let ([ok (guard (c [#t (printf "  error: ~a\n" (condition->string c))
                             #f])
                 expr)])
       (unless ok (set! failures (+ failures 1)))
       (printf "~a ~a\n" (if ok "ok  " "FAIL") name))]))

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

(define (file-forms f)
  (call-with-input-file (source-path f)
    (lambda (p)
      (let loop ([acc '()])
        (let ([x (read p)])
          (if (eof-object? x) (reverse acc) (loop (cons x acc))))))))

;; "styles/mac.ss" -> "styles", "mac"
(define (file-folder f) (path-first f))
(define (file-stem f) (path-root (path-last f)))

;;; ------------------------------------------------------------------
;;; 80 columns

;; The sources directly in folder.
(define (test-files folder)
  (map (lambda (f) (string-append folder "/" f))
       (filter (lambda (f) (string=? (path-extension f) "ss"))
               (sort string<? (directory-list (source-path folder))))))

;; Core0's own files, src/host/: load.ss lists them for core0 alone, and
;; (source-files) is the world's.
(define core0-files
  (remp (lambda (f) (member f *schevana-sources*)) *schevana-core0-sources*))

;; "/recorder"'s own files, src/recorder/, sealed between core0 and the
;; world.
(define recorder-files
  (remp (lambda (f) (member f *schevana-sources*))
        *schevana-recorder-sources*))

(define line-files
  (append core0-files recorder-files
          (source-files)
          (test-files "tests")
          (test-files "tests/units")
          (test-files "tests/fork")
          '("load.ss" "main.ss" "world.ss" "schevana")))

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
                              (if (and (pair? fd) (eq? (car fd) 'mutable))
                                  (list (sym s "-" f) (sym s "-" f "-set!"))
                                  (list (sym s "-" f)))))
                          fields)))))
  (define (names kind xs) (map (lambda (x) (cons kind x)) xs))
  (if (and (pair? form) (pair? (cdr form)))
      (let ([head (cadr form)])
        (case (car form)
          [(begin) (apply append (map defined (cdr form)))]
          [(define defvar define-syntax define-foreign
            define-foreign/collect-safe define-worklet)
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
(define defined-twice '())

(define world-files
  (append core0-files recorder-files (source-files) '("load.ss")))

;; An app in a sandbox (services/grant.ss): what its file defines is the
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
;; run; everything else belongs in a folder.
(define src-budget 33996)

;; The tokens of a datum as read; a list's end is none.
(define (tokens x)
  (cond [(pair? x) (+ (tokens (car x))
                      (if (null? (cdr x)) 0 (tokens (cdr x))))]
        [(vector? x) (apply + (map tokens (vector->list x)))]
        [else 1]))

(let* ([counts (map (lambda (f) (cons f (apply + (map tokens (file-forms f)))))
                    (append core0-files recorder-files
                            (filter (lambda (f) (string-prefix? "src/" f))
                                    *schevana-sources*)))]
       [n (apply + (map cdr counts))])
  (check (format "src/ is ~a tokens, within its budget of ~a (to grow the \
                  core, raise src-budget in tests/sources.ss on purpose)"
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

(define core-hooks
  '(*profile-span* *theme-saver* *window-gone* *app-loader*
    *host-event-seen* *worklet-spread*))

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
;;; no file names a binding of src/ffi.ss, a foreign-… procedure, an
;;; ftype form or load-shared-object. The tests may: they inspect what is
;;; drawn and stand in for the host.

(define ffi-names
  (map cdr (append (definitions "src/ffi.ss") (definitions "src/host/sdl.ss"))))

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
  (remp (lambda (f) (equal? (file-folder f) "src"))
        (append world-files '("main.ss" "world.ss"))))

;; The GPU layer speaks the world's terms: above it, in the core too, nothing
;; names SDL's windowless half, Vulkan, SPIR-V, Metal or MSL, so that another
;; back end, or raw Vulkan, is the GPU layer's business alone. Core0 keeps
;; SDL's window; the clock and the CPU count are SDL's, which any thread may
;; call. What the host is, its GPU's API among it, is named only where it's
;; said, src/platform.ss.
(define above-gpu-files
  (remp (lambda (f)
          (member f '("src/ffi.ss" "src/shader.ss" "src/host/sdl.ss"
                      "src/host/platform.ss" "src/host/gpu.ss"
                      "src/host/present.ss" "src/host/window.ss"
                      "src/font.ss" "src/platform.ss")))
        (append world-files '("main.ss" "world.ss"))))

(define (names-a-back-end? s)
  (let ([name (symbol->string s)])
    (and (not (memq s '(sdl-get-ticks-ns sdl-get-num-logical-cpu-cores)))
         (or (string-prefix? "sdl-" name)
             (string-contains-ci? name "spirv")
             (string-contains-ci? name "vulkan")
             (string-contains-ci? name "msl")
             (string-contains-ci? name "metal")))))

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
                src/ffi.ss (~a), no foreign-… or ftype form"
               (length outside-src) (length ffi-names))
       (none? (apply append
                     (map (lambda (f)
                            (map (lambda (s) (format "~a names ~a" f s))
                                 (reverse (filter reaches-c?
                                                  (symbols-in
                                                   (file-forms f))))))
                          outside-src))))

;;; ------------------------------------------------------------------
;;; what the host is, said in one place
;;; Which OS, windowing system or desktop this is, and where the system
;;; keeps what it says of itself, are read only in the platform files
;;; (AGENTS.md); the rest asks their predicates and facts. Monitor's
;;; Platform tab shows Chez's machine type as it is.

;; and src/host/sdl.ss, which binds SDL's video driver for core0's to read
(define platform-files
  '("src/base.ss" "src/platform.ss" "src/host/sdl.ss" "src/host/platform.ss"
    "kits/inspect.ss"))

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
                                (append world-files
                                        '("main.ss" "world.ss")))))))

;;; ------------------------------------------------------------------
;;; core0 below the core
;;; The host's code, src/host/, is core0 (.work/gpu-design.md 9.5): it
;;; loads right after the C bindings and the basics, names nothing of the
;;; core above it, and is the only code that names SDL. What it still
;;; names above it, and the SDL the core above still calls, are listed
;;; here, and the lists only shrink.

(define above-core0-files
  (append recorder-files
          (remp (lambda (f)
                  (member f (append core0-files '("src/ffi.ss" "src/base.ss"))))
                (filter (lambda (f) (string-prefix? "src/" f))
                        *schevana-sources*))))

;; What core0 names of the core above it: only the recorder's interface,
;; which it reads by name as it makes "/" and shares it there.
(define core0-reaches-up '(recorder-interface))

(check "core0 names nothing of the core above it but what's listed, on its \
        way out"
       (let ([above (map cdr (apply append (map definitions
                                                 above-core0-files)))])
         (none? (apply append
                       (map (lambda (f)
                              (map (lambda (s) (format "~a names ~a" f s))
                                   (filter (lambda (s)
                                             (and (memq s above)
                                                  (not (memq
                                                        s core0-reaches-up))))
                                           (reverse (symbols-in
                                                     (file-forms f))))))
                            core0-files)))))

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

;; Of core0's names, the world names only those core0 shares with it, its
;; interface (host-interface in src/host/boot.ss). The scripts that load the
;; tree call core0 to make "/", or to fork the world into it, and to enter
;; it.
(check "the world names nothing of core0's but its interface"
       (let ([own (remp (lambda (n)
                          (memq n (append host-interface
                                          '(host-boot! host-fork!
                                            host-enter-world!))))
                        (map cdr (apply append
                                        (map definitions core0-files))))])
         (none? (apply append
                       (map (lambda (f)
                              (map (lambda (s) (format "~a names ~a" f s))
                                   (filter (lambda (s) (memq s own))
                                           (reverse (code-symbols-in
                                                     (file-forms f))))))
                            (remp (lambda (f) (or (member f core0-files)
                                                  (member f recorder-files)))
                                  (append world-files
                                          '("main.ss" "world.ss"))))))))

;; "/recorder" is given core0's interface and, alone, recordings and what
;; holds them (host-recorder-share in src/host/boot.ss).
(check "the recorder names nothing of core0's but its interface and its share"
       (let ([own (remp (lambda (n)
                          (memq n (append host-interface host-recorder-share)))
                        (map cdr (apply append
                                        (map definitions core0-files))))])
         (none? (apply append
                       (map (lambda (f)
                              (map (lambda (s) (format "~a names ~a" f s))
                                   (filter (lambda (s) (memq s own))
                                           (reverse (code-symbols-in
                                                     (file-forms f))))))
                            recorder-files)))))

;; "/recorder" is sealed (.work/gpu-design.md 9.14): of its names the world
;; names only its interface (recorder-interface in src/recorder/bytes.ss),
;; so nothing the world does can write a byte it hands core0.
(check "the world names nothing of the recorder's but its interface"
       (let ([own (remp (lambda (n) (memq n recorder-interface))
                        (map cdr (apply append
                                        (map definitions recorder-files))))])
         (none? (apply append
                       (map (lambda (f)
                              (map (lambda (s) (format "~a names ~a" f s))
                                   (filter (lambda (s) (memq s own))
                                           (reverse (code-symbols-in
                                                     (file-forms f))))))
                            (remp (lambda (f) (member f recorder-files))
                                  (append world-files
                                          '("main.ss" "world.ss"))))))))

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
       (let ([forms (file-forms "src/host/sdl.ss")])
         (none? (filter-map
                 (lambda (c)
                   (let ([f (find (lambda (x)
                                    (and (pair? x) (pair? (cdr x))
                                         (pair? (cddr x))
                                         (equal? (caddr x) c)))
                                  forms)])
                     (cond [(not f) (format "not bound: ~a" c)]
                           [(eq? (car f) 'define-foreign/collect-safe) #f]
                           [else (format "not collect-safe: ~a" c)])))
                 sdl-blocking))))

(check "only core0 names SDL's bindings, but what's listed, on its way out"
       (let ([sdl (map cdr (definitions "src/host/sdl.ss"))])
         (none? (apply append
                       (map (lambda (f)
                              (map (lambda (s) (format "~a names ~a" f s))
                                   (filter (lambda (s)
                                             (and (memq s sdl)
                                                  (not (memq s core-sdl-left))))
                                           (reverse (symbols-in
                                                     (file-forms f))))))
                            (remp (lambda (f) (member f core0-files))
                                  (append world-files
                                          '("main.ss" "world.ss"))))))))

;;; ------------------------------------------------------------------
;;; sharing the whole world
;;; Code shares a list of names with an environment it makes; every name
;;; of the world's, followed, is a world namespace's, which a person asks
;;; for on purpose (a REPL's, the Environments app's fork). So only the
;;; kind does (services/env.ss).

(check "only a world namespace shares the whole world with an environment"
       (none? (filter-map
               (lambda (f)
                 (and (not (member f '("services/env.ss")))
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
  '((post-main! memory-order-release)
    (run-main-mail! memory-order-acquire)
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
    (host-put! memory-order-release)
    (host-take! memory-order-acquire)
    (gpu-publish! memory-order-release)
    (gpu-present-published! memory-order-acquire)
    (gpu-send-writes! memory-order-release)
    (gpu-present! memory-order-release)
    (host-frame-report memory-order-acquire)
    (present-sent! memory-order-release)
    (present-reported! memory-order-release)
    (host-trace! memory-order-release)
    (host-trace-rows-of memory-order-acquire)
    (host-input-came!)
    (host-input-ns-take!)
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
                                (append world-files '("main.ss" "world.ss"))))])
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
;; app whose file defines it (services/grant.ss).
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

(define (folder-problems f)
  (let* ([ds (definitions f)]
         [stem (string->symbol (file-stem f))]
         [kind (cdr (or (assoc (file-folder f) folder-kinds) '(#f . #f)))]
         [own (filter (lambda (d) (eq? (car d) kind)) ds)]
         [box (and (eq? kind 'app) (grant-env stem))])
    (append
     (map (lambda (d)
            (format "~a: ~a ~a is not registered" f (car d) (cdr d)))
          (remp (lambda (d) (registered? d box)) ds))
     (cond
       [(equal? (file-folder f) "desktop") '()]
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
       (none? (apply append (map folder-problems (folder-files)))))

;; What the files define, in load order, of one kind.
(define (defined-in-files kind)
  (map cdr (filter (lambda (d) (eq? (car d) kind))
                   (apply append (map definitions (folder-files))))))

(check "styles, palettes, wallpapers and apps are listed in file-name order"
       (and (equal? (styles) (defined-in-files 'style))
            (equal? (palettes) (defined-in-files 'palette))
            (equal? (wallpapers) (defined-in-files 'wallpaper))
            (equal? (apps) (defined-in-files 'app))))

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
  (append (filter (lambda (f) (member (file-folder f)
                                            '("kits" "services" "desktop")))
                  (folder-files))
          '("apps/tasks.ss" "apps/settings.ss" "apps/envs.ss"
            "apps/pipeline.ss")))

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
  (and (pair? form) (memq (car form) '(define defvar)) (pair? (cdr form))
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
              (file-forms f))))

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

;;; ------------------------------------------------------------------
;;; apps in sandboxes
;;; A tree app that requests bundles runs in a sandbox, approved by the
;;; table in services/grant.ss: what it requests is that, so a new request
;;; is a reviewed change. Sketch is left to the person, to show how an app
;;; of theirs asks.

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

(if (zero? failures)
    (printf "all checks passed\n")
    (printf "~a check(s) FAILED\n" failures))
(exit ;; Chez reads a script a form at a time, so a run has to end by exiting:
;; world.ss may have been edited during it, and what's read next would be
;; nonsense.
(let ()
  (define (run-then-exit? x)
    (and (pair? x)
         (or (and (equal? (car x) '(schevana-run!))
                  (pair? (cdr x))
                  (equal? (cadr x) '(schevana-end!)))
             (run-then-exit? (car x))
             (run-then-exit? (cdr x)))))
  (check "world.ss ends the process when its run ends, reading no more of \
          itself"
         (exists run-then-exit? (file-forms "world.ss"))))

(if (zero? failures) 0 1))
