;;; tests/build.ss — the tree's libraries as the tests build them, in the
;;; library edition, loaded by tests/boot.ss before the first library
;;; compiles. A library is written for what it does, never for its tests;
;;; what a test needs of it beyond that, this build gives it, as each of
;;; the tree's libraries is expanded (Chez's current-expand), as it
;;; compiles into the cache and as a reload evaluates it again:
;;;
;;; - A library of a sealed layer (core0's, the recorder's, the core's, and
;;;   the foundation they stand on), but a facade, exports every name it
;;;   defines, under test: (test:pacer-margin), which tests/reach.ss gives
;;;   the tests by the name itself. Under the prefix, no library of the
;;;   tree's finds a name another doesn't export.
;;; - A definition a test stands in for (test-stand-ins) is a hook, so that
;;;   a set!, a fluid-let's too, reaches every call to it: the definition
;;;   as it was, under a name of its own, which the hook holds.
;;;
;;; The objects go in a cache of their own, beside the launcher's, one for
;;; each text of this file. The hacker edition builds nothing: every name
;;; is at the top level there, to set as any other.

;; A form as it was read: its datum, without the reader's annotations.
(define (test-datum x)
  (cond [(annotation? x) (annotation-stripped x)]
        [(pair? x) (cons (test-datum (car x)) (test-datum (cdr x)))]
        [else x]))

;; A form one level down: the list of its parts, each as it was read.
(define (test-parts x) (if (annotation? x) (annotation-expression x) x))

;; The body forms of the library in file, a path from the tree's root.
(define (test-library-body file)
  (cddddr (call-with-input-file (string-append *schevana-root* "/" file)
            read)))

;; The calls a library binds to C, by their names: SDL's, which a test
;; stands in for when it runs core0 with no window (tests/units/sdl.ss).
(define (test-foreign-names file)
  (map cadr
       (filter (lambda (form)
                 (and (pair? form)
                      (memq (car form)
                            '(define-foreign define-foreign/collect-safe))))
               (test-library-body file))))

;; The definitions the tests stand in for, by library.
(define test-stand-ins
  `(((schevana apps pipeline) pipeline-pick-refresh! pipeline-river-target)
    ((schevana apps settings) *settings-style-directory*)
    ((schevana apps tasks) tasks-forest tasks-draw-node)
    ((schevana core draw) draw-text rec-present!)
    ((schevana core fonts) text-width)
    ((schevana core loop) collector-tick!)
    ((schevana core pacer)
     pacer-period pacer-start pacer-procs-ms render-frames-back!)
    ((schevana core platform) platform-process-bytes now-ns now-ms)
    ((schevana core processes) request-frame! notify report-error!)
    ((schevana core screen) screen-events)
    ((schevana core windows) invalidate! window-bleed)
    ((schevana core0 gpu)
     gpu-idle! gpu-present-modes gpu-claim-window! gpu-frame-waiting?)
    ((schevana core0 mail) core0-clock-ns core0-put! core0-world-wake!)
    ((schevana core0 platform)
     core0-platform-read! platform-clock-offset platform-reports-pump!)
    ((schevana core0 trace) core0-trace!)
    ((schevana core0 trace-file) core0-trace-write!)
    ((schevana core0 window)
     core0-hidden? core0-window-pump core0-facts-refresh!)
    ((schevana desktop bell) bell)
    ((schevana desktop main) desktop-usage)
    ((schevana desktop status) refresh-status!)
    ((schevana kits edit) edit-difference edit-layout-scan!)
    ((schevana kits inspect) inspect-list-flat! inspect-preview!)
    ((schevana kits ui) ui-tree-rows)
    ((schevana recorder bytes) rec-take! rec-loan-take!)
    ((schevana sdl gpu) sdl-set-swapchain-parameters)
    ((schevana sdl window)
     ,@(test-foreign-names "schevana/sdl/window.sls"))
    ((schevana services profile) profile-thread-cpu profile-tick-done!)
    ((schevana styles mac) draw-resize-grip)
    ((schevana tree) *schevana-root*)))

;; The names a body form of a library defines (a datum): a record type's
;; too, by R6RS's rules for the names it makes.
(define (test-defined-names form)
  (define (name+ . parts)
    (string->symbol
     (apply string-append
            (map (lambda (x) (if (symbol? x) (symbol->string x) x)) parts))))
  (define (record-names spec clauses)
    (let ([name (if (pair? spec) (car spec) spec)]
          [fields (let ([f (assq 'fields clauses)]) (if f (cdr f) '()))])
      (append
       (list name)
       (if (pair? spec) (cdr spec) (list (name+ "make-" name) (name+ name "?")))
       (apply append
              (map (lambda (f)
                     (cond [(symbol? f) (list (name+ name "-" f))]
                           [(pair? (cddr f)) (cddr f)]
                           [(eq? (car f) 'mutable)
                            (list (name+ name "-" (cadr f))
                                  (name+ name "-" (cadr f) "-set!"))]
                           [else (list (name+ name "-" (cadr f)))]))
                   fields)))))
  (if (not (pair? form))
      '()
      (case (car form)
        [(begin) (apply append (map test-defined-names (cdr form)))]
        [(define-record-type) (record-names (cadr form) (cddr form))]
        ;; (define-shader-layout name reader (field ...)): name-words, and
        ;; a name-field for each
        [(define-shader-layout)
         (cons (name+ (cadr form) "-words")
               (map (lambda (f) (name+ (cadr form) "-" f)) (cadddr form)))]
        [(define define-syntax define-state define-made define-hook
          define-view define-foreign define-foreign/collect-safe
          define-optional-foreign define-ftype define-worklet
          define-compute-shader define-vertex-shader define-gfx-fragment
          define-shader-constant define-paint define-app define-part
          define-wayland define-wayland-callback define-objc)
         (let ([n (let first ([x (cadr form)])
                    (if (pair? x) (first (car x)) x))])
           (if (eq? (car form) 'define-part)
               (list n (name+ n "*"))
               (list n)))]
        [else '()])))

;; The variables a library's body (a datum) defines and sets (set!): Chez
;; exports no variable that is assigned. A state and a hook are globals,
;; which it does.
(define (test-assigned body)
  (let ([plain (let walk ([forms body])
                 (apply append
                        (map (lambda (f)
                               (cond [(not (pair? f)) '()]
                                     [(eq? (car f) 'begin) (walk (cdr f))]
                                     [(eq? (car f) 'define)
                                      (test-defined-names f)]
                                     [else '()]))
                             forms)))])
    (let walk ([x body] [acc '()])
      (cond [(not (pair? x)) acc]
            [(and (eq? (car x) 'set!) (pair? (cdr x)) (symbol? (cadr x))
                  (memq (cadr x) plain))
             (walk (cddr x) (cons (cadr x) acc))]
            [else (walk (cdr x) (walk (car x) acc))]))))

;; The names an export clause (a datum) gives, as the library has them.
(define (test-exported clause)
  (apply append
         (map (lambda (spec)
                (cond [(symbol? spec) (list spec)]
                      [(and (pair? spec) (eq? (car spec) 'rename))
                       (map car (cdr spec))]
                      [else '()]))
              (cdr clause))))

(define (test-prefixed name)
  (string->symbol (string-append "test:" (symbol->string name))))

;; A name's own definition, under the name of the one a hook holds.
(define (test-bound name) (string->symbol (format "~a/bound" name)))

;; The hook for name: a global of Chez's own (as define-global, in
;; schevana/base.sls, makes one), named for it, read where name is, set by
;; set!; till it's set, at the body's end, the definition itself, as the
;; library loads. Each read names the definition, so Chez runs the
;; library for code that reads only the hook.
(define (test-hook name global)
  (let ([read `(if (($primitive $top-level-bound?) ',global)
                   (($primitive $top-level-value) ',global)
                   ,(test-bound name))])
    `(define-syntax ,name
       (make-variable-transformer
        (lambda (x)
          (syntax-case x (set!)
            [(set! _ v) #'(($primitive $set-top-level-value!) ',global v)]
            [id (identifier? #'id) #',read]
            [(_ . rest) #'(,read . rest)]))))))

;; A body form, each definition of names in it under the name of the one
;; its hook holds (test-bound), as it was otherwise, where it was: compiled
;; as the library has it, beside its hook. The hook is set at the body's
;; end (test-build-form), once every definition is made, as an export is.
;; found: each name and its global, for the end, and for the check that
;; each is.
(define (test-stand-in form names found)
  (let ([d (test-datum form)])
    (if (not (and (pair? d) (pair? (cdr d))))
        form
        (let ([n (let first ([x (cadr d)]) (if (pair? x) (first (car x)) x))]
              [parts (test-parts form)])
          (cond
            [(eq? (car d) 'begin)
             (cons (car parts)
                   (map (lambda (f) (test-stand-in f names found))
                        (cdr parts)))]
            [(not (memq n names)) form]
            [(memq (car d) '(define define-made define-foreign
                             define-foreign/collect-safe))
             (let ([head (test-parts (cadr parts))]
                   [global (gensym (symbol->string n))])
               (hashtable-set! found n global)
               `(begin
                  ,(cons* (car parts)
                          (if (pair? head)
                              (cons (test-bound n) (cdr head))
                              (test-bound n))
                          (cddr parts))
                  ,(test-hook n global)))]
            [else
             (errorf 'test-build "~s: no stand-in for a ~s" n (car d))])))))

;; The library form x as this build has it: one of the tree's, its
;; definitions stood in for and its names given; anything else as it is.
(define (test-build-form x)
  (let ([parts (test-parts x)])
    (if (not (and (list? parts) (>= (length parts) 4)
                  (eq? (test-datum (car parts)) 'library)
                  (let ([name (test-datum (cadr parts))])
                    (and (pair? name) (eq? (car name) 'schevana)))))
        x
        (let* ([name (test-datum (cadr parts))]
               [names (let ([e (assoc name test-stand-ins)])
                        (if e (cdr e) '()))]
               [found (make-eq-hashtable)]
               [body (map (lambda (f) (test-stand-in f names found))
                          (cddddr parts))]
               [data (test-datum (cddddr parts))]
               [layer (exists (lambda (f)
                                (and (pair? f) (eq? (car f) 'library-layer)
                                     (cdr f)))
                              data)]
               [given (if (and layer
                               (memq (car layer)
                                     '(foundation core0 recorder core))
                               (not (memq 'facade (cdr layer))))
                          (let ([exported (test-exported
                                           (test-datum (caddr parts)))]
                                [assigned (test-assigned data)])
                            (filter
                             (lambda (n)
                               (not (or (memq n exported)
                                        (memq n assigned))))
                             (apply append (map test-defined-names data))))
                          '())])
          (for-each (lambda (n)
                      (unless (hashtable-ref found n #f)
                        (errorf 'test-build "~s defines no ~s to stand in for"
                                name n)))
                    names)
          `(library ,(cadr parts)
             ,(if (null? given)
                  (caddr parts)
                  `(export ,@(cdr (test-parts (caddr parts)))
                           (rename ,@(map (lambda (n)
                                            (list n (test-prefixed n)))
                                          given))))
             ,(cadddr parts)
             ,@body
             ,@(map (lambda (n)
                      `(define ,(string->symbol (format "~a/set" n))
                         (($primitive $set-top-level-value!)
                          ',(hashtable-ref found n #f)
                          ,(test-bound n))))
                    names))))))

;; The build set up for root's libraries, after the launcher's
;; (schevana-libraries!): their objects in a cache of the build's own, and
;; each library expanded as the build has it.
(define (test-build! root)
  (let ([cache (format "~a-tests-~x" (schevana-cache-folder root)
                       (logand (equal-hash
                                (call-with-input-file
                                  (string-append root "/tests/build.ss")
                                  get-string-all))
                               #xffffffff))])
    (library-directories (cons (cons root cache)
                               (cdr (library-directories))))
    (let ([expand (current-expand)])
      (current-expand
       (lambda (x . rest) (apply expand (test-build-form x) rest))))))
