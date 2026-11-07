;;; proc.ss — processes and the watchdog, built on Chez Scheme engines.
;;;
;;; Schevana is single-threaded. Long computations become *processes*:
;;; engines that get a slice of fuel every frame, so an infinite loop in the
;;; REPL never freezes the world and can be killed with Ctrl+C. A process
;;; reloading the sources is no exception, but while it loads it holds the
;;; world still (*reloading*, see system.ss): only it runs, and nothing draws.
;;;
;;; Every app handler (draw, key, tick, ...) also runs under a fuel budget via
;;; safe-call: if it loops forever or raises, only that window "crashes".
;;; System code reports its errors as notifications (report-error!).

;; defvar, not define: a reload must not swap out parameters that running
;; engines are still parameterizing. Thread parameters: another thread's
;; binding is never the main thread's.
(defvar in-engine? (make-thread-parameter #f))
(defvar current-proc (make-thread-parameter #f))

(define handler-fuel 50000000)   ; per handler call; roughly 0.1s of pure Scheme
(define slice-fuel 10000)        ; per process slice; roughly 15us

;; The profiler's hook: #f, or (begin . end), procedures that
;; services/profile.ss sets while on: (begin key part) opens a span of key
;; (a symbol, or a window's or a process's id) and part (a window
;; handler's kind, or #f; #t for a process's turn); (end outer?) closes
;; the span open innermost, or with outer? true (the step's end) the
;; outermost, and any a raise left open. Five places run their work in
;; with-profile-span: the step, safely, a window's handler (window-call)
;; and drawing (record-world!), and a process's turn (run-procs!).
;; Off, each costs a variable read and a branch; key and part are
;; computed only while the hook is set; nothing is allocated either way,
;; and nothing is kept across the work (a value live across an engine's
;; run costs Chez a copy of the frame).
(defvar *profile-span* #f)

(define-syntax with-profile-span
  (lambda (x)
    (syntax-case x ()
      [(_ key part body ...)
       (with-syntax ([outer? (equal? (syntax->datum #'key) ''step)])
         #'(let ([span *profile-span*])
             (if span
                 (begin
                   ((car span) key part)
                   (call-with-values (lambda () body ...)
                     (case-lambda
                       [(v) (let ([s *profile-span*]) (when s ((cdr s) outer?)))
                            v]
                       [vs (let ([s *profile-span*]) (when s ((cdr s) outer?)))
                           (apply values vs)])))
                 (begin body ...))))])))

(define (make-timeout-condition who)
  (condition (make-error) (make-who-condition who)
             (make-message-condition
              "exceeded its time budget (infinite loop?)")))

;; Calls thunk. If it raises or runs out of fuel, returns (on-error condition).
(define (safe-call who thunk on-error)
  (if (in-engine?)
      (guard (c [#t (on-error c)]) (thunk))
      (let ([r ((make-engine
                 (lambda ()
                   (parameterize ([in-engine? #t])
                     (guard (c [#t (cons 'error c)])
                       (call-with-values thunk
                         (lambda vals (cons 'ok vals)))))))
                handler-fuel
                (lambda (left r) r)
                (lambda (eng) (cons 'error (make-timeout-condition who))))])
        (if (eq? (car r) 'ok)
            (apply values (cdr r))
            (on-error (cdr r))))))

;; For trusted system code: errors are reported, but there is no fuel limit.
(define (safely who thunk)
  (with-profile-span who #f
    (guard (c [#t (report-error! who c)]) (thunk))))

;;; ------------------------------------------------------------------
;;; notifications
;;; The queue is the core's; how a toast looks is the desktop's.

(defvar *toasts* '())   ; (#(expires-at text color) ...)

(define notify
  (case-lambda
    [(msg) (notify msg 'accent)]
    [(msg color)
     (let ([text (list->string
                  (map (lambda (c) (if (char=? c #\newline) #\space c))
                       (string->list
                        (if (string? msg) msg (format "~a" msg)))))])
       (set! *toasts*
         (append *toasts* (list (vector (+ (now-ms) 5000) text color))))
       (when (> (length *toasts*) 5) (set! *toasts* (cdr *toasts*)))
       (request-frame!))]))

(define (expire-toasts!)
  (let ([now (now-ms)])
    (when (exists (lambda (t) (< (vector-ref t 0) now)) *toasts*)
      (set! *toasts* (filter (lambda (t) (>= (vector-ref t 0) now)) *toasts*))
      (request-frame!))))

(defvar *last-error* (cons "" 0))

;; System-level errors become a red notification (and a line on stderr).
(define (report-error! who c)
  (let ([msg (format "~a: ~a" who (condition->string c))])
    (unless (and (string=? msg (car *last-error*))
                 (< (- (now-ms) (cdr *last-error*)) 5000))
      (set! *last-error* (cons msg (now-ms)))
      (notify msg 'red)
      (fprintf (console-error-port) "schevana: ~a\n" msg))))

;;; ------------------------------------------------------------------ processes

(define-record-type proc
  (nongenerative schevana-proc)
  (fields id name (mutable engine) (mutable state) on-done
          (mutable ticks) started (mutable wake)))

(record-writer (record-type-descriptor proc)
  (lambda (p port wr)
    (fprintf port "#<proc ~a ~s ~a>" (proc-id p) (proc-name p) (proc-state p))))

(defvar *procs* '())
(defvar *next-pid* 1)
;; (proc . file) while that process loads the sources (system.ss)
(defvar *reloading* #f)

;; (spawn name thunk [on-done]) starts a process. on-done receives
;; (status value): 'ok and the list of results, 'error and a condition,
;; or 'killed and #f. Output goes wherever current-output-port pointed
;; when spawn was called (so processes started in a REPL print there).
(define spawn
  (case-lambda
    [(name thunk) (spawn name thunk (lambda (status value) (void)))]
    [(name thunk on-done)
     (let* ([out (current-output-port)]
            [p (make-proc *next-pid* name #f 'running on-done 0 (now-ms) 0)])
       (set! *next-pid* (+ *next-pid* 1))
       (proc-engine-set! p
         (make-engine
          (lambda ()
            (parameterize ([in-engine? #t] [current-proc p]
                           [current-output-port out] [current-error-port out])
              (guard (c [#t (cons 'error c)])
                (call-with-values thunk (lambda vals (cons 'ok vals))))))))
       (set! *procs* (append *procs* (list p)))
       p)]))

(define (procs) *procs*)

(define (find-proc p)
  (if (proc? p) p (find (lambda (q) (eqv? (proc-id q) p)) *procs*)))

(define (proc-finish! p state value)
  (when (memq p *procs*)
    (set! *procs* (remq p *procs*))
    (proc-state-set! p state)
    (safe-call 'on-done (lambda () ((proc-on-done p) state value))
               (lambda (c) (report-error! 'proc c)))
    (invalidate!)))

(define (kill! p)
  (let ([p (find-proc p)])
    (when p (proc-finish! p 'killed #f))))

(define (run-slice! p)
  (when (memq p *procs*)
    ((proc-engine p) slice-fuel
     (lambda (left r) (proc-finish! p (car r) (cdr r)))
     (lambda (eng)
       (proc-engine-set! p eng)
       (proc-ticks-set! p (+ (proc-ticks p) slice-fuel))))))

(define (proc-ready? p) (<= (proc-wake p) (now-ms)))

;; While one process reloads the sources only it runs: the others may
;; call half-loaded code.
(define (proc-may-run? p)
  (and (proc-ready? p) (or (not *reloading*) (eq? p (car *reloading*)))))

(define (procs-ready?) (exists proc-may-run? *procs*))

;; Run ready processes until budget-ms has elapsed, round-robin: in its
;; turn each runs slices for its share of the time left, while it may.
(define (run-procs! budget-ms)
  (let ([deadline (+ (now-ms) budget-ms)])
    (let loop ()
      (let ([ready (filter proc-may-run? *procs*)])
        (when (and (pair? ready) (< (now-ms) deadline))
          (for-each
           (lambda (p)
             ;; the clock read once: a ms turning between two reads would end
             ;; a lone process's turn a ms short, and give it a second
             (let* ([now (now-ms)]
                    [until (+ now (/ (- deadline now) (length ready)))])
               (with-profile-span (proc-id p) #t
                 (let turn ()
                   (when (and (memq p *procs*) (proc-may-run? p))
                     (run-slice! p)
                     (when (< (now-ms) until) (turn)))))))
           ready)
          (loop))))))

;; Give up the CPU for ms milliseconds (only inside a process).
(define (sleep-ms ms)
  (let ([p (current-proc)])
    (unless p (errorf 'sleep-ms "can only sleep inside a process (use spawn)"))
    (let ([until (+ (now-ms) ms)])
      (proc-wake-set! p until)
      (let loop ()
        (engine-block)
        (when (< (now-ms) until) (loop))))))

;; Give up the rest of this slice.
(define (yield) (when (current-proc) (engine-block)))

;;; ------------------------------------------------------------------ worklets
;;; What a worker thread runs. A worklet is a procedure compiled in the
;;; worklet environment, where only this is in reach: Scheme's pure core
;;; (no I/O, no eval), fixnums, flonums, bitwise operations, bytevectors,
;;; fxvectors, flvectors, boxes, raising and catching (but not reading a
;;; condition),
;;; the clock (now-ns), the thread's id and the worklets defined so far.
;;; SDL and the world's state are not: a worklet that names
;;; anything else is refused when it is defined, so all it touches is what
;;; it is handed. Of that, it can open only pairs, vectors and boxes. The
;;; clock and the worklets are there as forwarders to the world's own
;;; bindings, which refuse a worklet's set! of them; one that sets any
;;; other top-level name is refused too, since that name would be state
;;; that worker threads write at once.
;;;
;;;   (define-worklet (step! grid next lo hi) ...)
;;;   (worklet (x) (fx* x x))                       one without a name

;; A read-only forwarder to the identifier id's binding: a macro that,
;; installed in another environment, makes code there refer to that
;; binding itself (live, and at no cost a call). A set! of it is refused
;; as it expands, in the words Chez uses for an R6RS import's.
(define (forwarder-to id)
  (make-variable-transformer
   (lambda (x)
     (syntax-case x (set!)
       [(set! name . _)
        (syntax-error #'name "attempt to assign read-only variable")]
       [_ (identifier? x) id]
       [(_ . rest) #`(#,id . rest)]))))

(define (worklet-base-environment)
  (let ([e (copy-environment
            (environment '(rnrs base) '(rnrs control) '(rnrs lists)
                         '(rnrs arithmetic fixnums)
                         '(rnrs arithmetic flonums)
                         '(rnrs arithmetic bitwise) '(rnrs bytevectors)
                         '(rnrs exceptions)
                         '(only (chezscheme)
                                fx= fx< fx> fx<= fx>= fx+ fx- fx* fx1+ fx1-
                                fxquotient fxremainder fxmodulo fxabs fxmin
                                fxmax fxzero? fxlogand fxlogor fxlogxor
                                fxsll fxsrl fxsra
                                fl= fl< fl> fl<= fl>= fl+ fl- fl* fl/
                                fixnum->flonum flonum->fixnum
                                add1 sub1 iota void
                                box unbox set-box! box-cas!
                                make-fxvector fxvector fxvector-length
                                fxvector-ref fxvector-set!
                                make-flvector flvector flvector-length
                                flvector-ref flvector-set! flvector-fill!
                                get-thread-id))
            #t)])
    (define-top-level-syntax 'now-ns (forwarder-to #'now-ns) e)
    e))

(defvar *worklet-environment* (worklet-base-environment))
(defvar *worklets* (make-weak-eq-hashtable))   ; worklet: #t

(define (worklet? x) (hashtable-contains? *worklets* x))

;; What form refers to at the top level, as expand gives it: (ref . name)
;; or (set . name).
(define (worklet-free-names form env)
  (let walk ([x (expand form env)] [acc '()])
    (let ([op (and (pair? x) (pair? (car x)) (eq? (caar x) '$primitive)
                   (car (last-pair (car x))))])
      (cond
        [(not (pair? x)) acc]
        [(and (memq op '($top-level-value $set-top-level-value!))
              (pair? (cdr x)) (pair? (cadr x)) (eq? (caadr x) 'quote))
         (walk (cddr x)
               (cons (cons (if (eq? op '$top-level-value) 'ref 'set)
                           (string->symbol (symbol->string (cadadr x))))
                     acc))]
        [else (walk (cdr x) (walk (car x) acc))]))))

;; form, a lambda, compiled in env as the worklet who.
(define (worklet-compile who form env)
  (for-each (lambda (n)
              (cond [(eq? (car n) 'set)
                     (errorf who "a worklet sets no top-level name: ~s"
                             (cdr n))]
                    [(not (top-level-bound? (cdr n) env))
                     (errorf who "~s is out of a worklet's reach" (cdr n))]))
            (worklet-free-names form env))
  (let ([p (eval form env)])
    (hashtable-set! *worklets* p #t)
    p))

(define-syntax worklet
  (syntax-rules ()
    [(_ formals body ...)
     (worklet-compile 'worklet '(lambda formals body ...)
                      *worklet-environment*)]))

;; (define-worklet (name . formals) body ...): a worklet, defined where the
;; form is, and forwarded to from the worklet environment before it
;; compiles, so it may recur and the others see it redefined.
(define-syntax define-worklet
  (syntax-rules ()
    [(_ (name . formals) body ...)
     (begin
       (define-top-level-syntax 'name (forwarder-to #'name)
                                *worklet-environment*)
       (define name (worklet-compile 'name '(lambda formals body ...)
                                     *worklet-environment*)))]))
