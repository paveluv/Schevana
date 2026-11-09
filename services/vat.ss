;;; services/vat.ss — vats: threads, each with a mailbox and a sandbox,
;;; that run jobs and hand their results back to the main thread.
;;;
;;;   (define v (vat-of (env-fork (env-root) 'thread 'name 'tally)))
;;;   (vat-eval! v '(define n 0) #f)       a form, run in v's sandbox
;;;   (vat-eval! v '(define (add! k) (set! n (+ n k)) n) #f)
;;;   (vat-send! v 'add! '(5) show)        v's add!; (show 5) on main
;;;   (vat-send! (vat-pool) step! (list grid) show)   a worklet, on the
;;;                                        pool's threads
;;;   (vat-repl! v forms 72 show-lines show-error)   forms as a REPL
;;;                                        takes them: values printed
;;;   (vat-job-pending? j)   (vat-job-kill! j)   (vat-drop! v)
;;;   (vat-of e)                           the vat whose sandbox e is
;;;   (vat-drop-env! e)                    e and its children dropped,
;;;                                        and their vats
;;;   (vat-threads-of v)   (vat-jobs-of v)   how many threads, which jobs
;;;
;;; A thread, the kind of environment (env-fork), is a sandbox and a vat
;;; started on it once it is shared what it is given.
;;;
;;; A vat is a thread, its mailbox and a sandbox (services/env.ss) that
;;; only its thread evaluates in, so the sandbox's globals are written by
;;; that thread alone (S4, by construction). Share names with the sandbox
;;; before the vat starts: after, the sandbox is the vat's.
;;;
;;; A message is a job: a worklet or the name of a procedure in the vat's
;;; sandbox, and its arguments; or a form, for vat-eval!. Its arguments
;;; hold no procedure but worklets (crew-stray), and so must its results.
;;; A vat runs its jobs one at a time, in the order sent. When one
;;; returns, (then v ...) runs on main at its next step, as a handler of
;;; the window it was sent from: (current-window) bound, under the
;;; watchdog, an error crashing the window. A job that raises crashes its
;;; window too (with no window, a red toast), unless it was sent with a
;;; fail, which is then given the condition as then is the results.
;;; vat-repl! prints the values on the vat's thread, where they live, so
;;; its then gets their texts, and its fail an error's.
;;;
;;; A job is pending until its then has run, or until it is killed: by
;;; vat-job-kill!, by its window's closing or crashing, or by its vat's
;;; dropping. Killed, it never starts, or, running, escapes within
;;; vat-fuel ticks of its own code (its thread's timer looks), and its
;;; then never runs: the kill is on main, as is the delivery, so the kill
;;; always wins.
;;;
;;; The pool, (vat-pool), is a vat on /worklets served by several threads,
;;; (vat-pool-size) of them, 4 until (vat-pool-size-set! n): for worklets
;;; only, run in no order.

(define vat-fuel 20000)           ; timer ticks between a thread's looks
(define vat-idle-ns 50000000)     ; an idle thread's wait, at most

;; A vat: its sandbox; its mailbox, a box of jobs, the oldest first, and
;; the lock and condition its idle threads wait on; its threads, each by
;; the box that stops it; whether it was dropped, a box.
(define-record-type vat
  (nongenerative schevana-vat-1)
  (fields env mailbox mutex wake (mutable threads) dropped))

(record-writer (record-type-descriptor vat)
  (lambda (v p wr) (fprintf p "#<vat ~a>" (env-path (vat-env v)))))

;; A job: its vat; its kind: call (proc, a worklet or a name in the
;; vat's sandbox, applied to args), eval (args a form) or show (args the
;; width and forms of vat-repl!); its then, window and fail (or #f);
;; whether it was killed, a box main sets and the vat's thread reads.
(define-record-type vat-job
  (nongenerative schevana-vat-job-2)
  (fields vat kind proc args then window fail killed))

(defvar *vat-jobs* '())     ; the pending jobs, on main
(defvar *vat-all* '())      ; the vats not dropped, the pool too
(defvar *vat-pool* #f)
(defvar *vat-pool-size* 4)
;; on a vat's thread: the job it runs and the way out of it, or #f
(defvar vat-current (make-thread-parameter #f))

;;; ------------------------------------------------------------------ vats

;; A vat on e, a sandbox on the core base, with one thread.
(define (vat-start! e)
  (unless (eq? (env-base e) 'core)
    (errorf 'vat-start! "a vat runs in a sandbox on the core base, not ~a"
            (env-path e)))
  (vat-new e 1))

(define (vat-new e n)
  (let ([v (make-vat e (box '()) (make-mutex) (make-condition) '()
                     (box #f))])
    (vat-resize! v n)
    (set! *vat-all* (cons v *vat-all*))
    v))

(define (vat-of e) (find (lambda (v) (eq? (vat-env v) e)) *vat-all*))

(define (vat-threads-of v) (length (vat-threads v)))

;; The kind e shows as: its own, or a bare one's by whether a vat runs on
;; it and by its base (a sandbox, or a namespace).
(define (vat-env-kind e)
  (cond [(env-kind e)]
        [(vat-of e) 'thread]
        [(memq (env-base e) '(confined core)) 'sandbox]
        [else 'namespace]))

;; v's pending jobs, the oldest first.
(define (vat-jobs-of v)
  (reverse (filter (lambda (j) (eq? (vat-job-vat j) v)) *vat-jobs*)))

;; Raises a flag v's threads read. box-cas! may fail on ARM with nothing in
;; its way (Chez's guide), so it's tried until the flag is up.
(define (vat-flag-up! b)
  (let loop () (unless (or (unbox b) (box-cas! b #f #t)) (loop))))

;; v's threads: more start, or those past n stop once done with their
;; turn.
(define (vat-resize! v n)
  (let ([stops (vat-threads v)])
    (if (< n (length stops))
        (begin
          (for-each vat-flag-up! (list-tail stops n))
          (vat-threads-set! v (list-head stops n))
          (vat-wake! v))
        (vat-threads-set! v (append stops
                                    (map (lambda (i) (vat-fork! v))
                                         (iota (- n (length stops)))))))))

(define (vat-pool)
  (unless (and *vat-pool* (not (unbox (vat-dropped *vat-pool*))))
    (set! *vat-pool* (vat-new (env-find "/worklets") *vat-pool-size*)))
  *vat-pool*)

(define (vat-pool-size) *vat-pool-size*)

(define (vat-pool-size-set! n)
  (unless (and (fixnum? n) (>= n 1))
    (errorf 'vat-pool-size-set! "the pool needs a thread or more, not ~s" n))
  (set! *vat-pool-size* n)
  (when (and *vat-pool* (not (unbox (vat-dropped *vat-pool*))))
    (vat-resize! *vat-pool* n)))

;; Ends v's threads, once each is done with its turn, and kills its jobs.
(define (vat-drop! v)
  (vat-flag-up! (vat-dropped v))
  (set! *vat-all* (remq v *vat-all*))
  (for-each (lambda (j) (when (eq? (vat-job-vat j) v) (vat-job-kill! j)))
            *vat-jobs*)
  (vat-wake! v))

;; Drops e and its children (env-drop!, which may refuse), and the vats
;; whose sandboxes they are.
(define (vat-drop-env! e)
  (env-drop! e)
  (let walk ([e e])
    (let ([v (vat-of e)]) (when v (vat-drop! v)))
    (for-each walk (env-children e))))

;; A thread of v: its own timer, then turns, each by name, so a reload
;; changes them, until v is dropped or the thread stopped. => the box
;; that stops it.
(define (vat-fork! v)
  (let ([stop (box #f)])
    (fork-thread
     (lambda ()
       (timer-interrupt-handler (lambda () (vat-timer!)))
       (let loop () (when (and (not (unbox stop)) (vat-step! v)) (loop)))))
    stop))

;; A turn: a job, or a wait for one. #f once v is dropped.
(define (vat-step! v)
  (and (not (unbox (vat-dropped v)))
       (let ([j (vat-take! v)])
         (if j
             (vat-run! j)
             (with-mutex (vat-mutex v)
               (when (and (null? (unbox (vat-mailbox v)))
                          (not (unbox (vat-dropped v))))
                 (condition-wait (vat-wake v) (vat-mutex v)
                                 (make-time 'time-duration vat-idle-ns 0)))))
         #t)))

;; Wakes v's idle threads. The lock is only tried, with interrupts off, so
;; an engine (a REPL's evaluation) never stops while holding it; if every
;; try fails, a thread wakes at its wait's end.
(define (vat-wake! v)
  (let try ([n 0])
    (unless (or (with-interrupts-disabled
                 (and (mutex-acquire (vat-mutex v) #f)
                      (begin (condition-broadcast (vat-wake v))
                             (mutex-release (vat-mutex v))
                             #t)))
                (= n 1000))
      (try (+ n 1)))))

;; The fences hand the vat's thread what main wrote before it sent the job,
;; as post-main! hands main a job's outcome.
(define (vat-put! v j)
  (memory-order-release)
  (let loop ()
    (let ([jobs (unbox (vat-mailbox v))])
      (unless (box-cas! (vat-mailbox v) jobs (append jobs (list j)))
        (loop)))))

(define (vat-take! v)
  (let loop ()
    (let ([jobs (unbox (vat-mailbox v))])
      (cond [(null? jobs) #f]
            [(box-cas! (vat-mailbox v) jobs (cdr jobs))
             (memory-order-acquire)
             (car jobs)]
            [else (loop)]))))

;;; ------------------------------------------------------------------ jobs

;; Sends v the job (proc arg ...): proc a worklet, or the name of a
;; procedure in v's sandbox; and, optionally, a fail. => the job.
(define (vat-send! v proc args then . fail)
  (when (and (symbol? proc) (eq? v *vat-pool*))
    (errorf 'vat-send! "the pool runs worklets only: ~s" proc))
  (vat-post! 'vat-send! v 'call proc args then fail))

;; Sends v a form to evaluate in its sandbox. => the job.
(define (vat-eval! v form then . fail)
  (vat-post! 'vat-eval! v 'eval #f form then fail))

;; Sends v forms to evaluate in turn, as a REPL does: (then texts), each
;; value but (void) printed width wide, or (fail text) for an error.
(define (vat-repl! v forms width then fail)
  (vat-post! 'vat-repl! v 'show #f (cons width forms) then (list fail)))

(define (vat-post! who v kind proc args then fail)
  (cond
    [(unbox (vat-dropped v)) (errorf who "~s was dropped" v)]
    [(and (eq? v *vat-pool*) (not (eq? kind 'call)))
     (errorf who "the pool runs worklets only, not forms")]
    [(crew-stray (cons proc args))
     => (lambda (p)
          (errorf who "a job carries no procedure but worklets: ~s" p))])
  (let ([j (make-vat-job v kind proc args then (current-window)
                         (and (pair? fail) (car fail)) (box #f))])
    (set! *vat-jobs* (cons j *vat-jobs*))
    (vat-put! v j)
    (vat-wake! v)
    j))

(define (vat-job-pending? j) (and (memq j *vat-jobs*) #t))

(define (vat-job-kill! j)
  (set! *vat-jobs* (remq j *vat-jobs*))
  (vat-flag-up! (vat-job-killed j)))

;; Kills the jobs sent from win, as it closes or crashes.
(define (vat-window-gone! win)
  (for-each (lambda (j) (when (eq? (vat-job-window j) win) (vat-job-kill! j)))
            *vat-jobs*))

(set! *window-gone* (lambda (win) (vat-window-gone! win)))

;; On j's vat's thread: runs j, its timer on, and posts the outcome to
;; main. The way out is let go before j's results leave the call/1cc, so
;; the timer never takes it once it is spent.
(define (vat-run! j)
  (unless (unbox (vat-job-killed j))
    (let ([r (call/1cc
              (lambda (k)
                (vat-current (cons j k))
                (set-timer vat-fuel)
                (let ([r (guard (c [#t (cons 'error
                                             (if (eq? (vat-job-kind j) 'show)
                                                 (vat-condition-text c)
                                                 c))])
                           (call-with-values (lambda () (vat-call j))
                             (lambda vals (cons 'ok vals))))])
                  (vat-current #f)
                  r)))])
      (set-timer 0)
      (when r   ; #f: killed, and out
        (post-main! (lambda () (vat-deliver! j (car r) (cdr r))))))))

(define (vat-call j)
  (let ([e (env-environment (vat-env (vat-job-vat j)))]
        [args (vat-job-args j)])
    (case (vat-job-kind j)
      [(eval) (eval args e)]
      [(show) (vat-show e (car args) (cdr args))]
      [else (let ([p (vat-job-proc j)])
              (apply (if (symbol? p) (top-level-value p e) p) args))])))

;; forms evaluated in e in turn, and their values but (void) printed width
;; wide, by Chez's printer, on the vat's thread: => the texts.
(define (vat-show e width forms)
  (parameterize ([pretty-line-length width])
    (let loop ([forms forms] [texts '()])
      (if (null? forms)
          (reverse texts)
          (call-with-values (lambda () (eval (car forms) e))
            (lambda vals
              (loop (cdr forms)
                    (fold-left (lambda (texts v)
                                 (if (eq? v (void))
                                     texts
                                     (cons (vat-text v) texts)))
                               texts vals))))))))

(define (vat-text v)
  (let ([s (with-output-to-string (lambda () (pretty-print v)))])
    (if (and (> (string-length s) 0)
             (char=? (string-ref s (- (string-length s) 1)) #\newline))
        (substring s 0 (- (string-length s) 1))
        s)))

(define (vat-condition-text c)
  (call-with-string-output-port
   (lambda (p)
     (if (condition? c)
         (display-condition c p)
         (fprintf p "non-condition raised: ~s" c)))))

;; A vat's thread's timer: out of its job once the job is killed.
(define (vat-timer!)
  (let ([now (vat-current)])
    (when now
      (if (unbox (vat-job-killed (car now)))
          (begin (vat-current #f) ((cdr now) #f))
          (set-timer vat-fuel)))))

;; On main: j's then, given its results, or its fail, given the error,
;; unless j was killed meanwhile. The results are walked here, on main,
;; where the worklets' table is.
(define (vat-deliver! j status value)
  (when (memq j *vat-jobs*)
    (set! *vat-jobs* (remq j *vat-jobs*))
    (let* ([w (vat-job-window j)]
           [crash (lambda (c) (if w (window-crash! w 'job c)
                                  (report-error! 'job c)))]
           [stray (and (eq? status 'ok) (crew-stray value))])
      (cond
        [(and (eq? status 'ok) (not stray))
         (when (vat-job-then j) (vat-handle w (vat-job-then j) value crash))]
        [else
         (let ([c (if stray
                      (guard (c [#t c])
                        (errorf 'vat-job "a job returns no procedure but \
                                          worklets: ~s" stray))
                      value)])
           (if (vat-job-fail j)
               (vat-handle w (vat-job-fail j) (list c) crash)
               (crash c)))]))))

;; (proc arg ...) on main, as a handler of win (or of none): its theme and
;; (current-window) bound, under the watchdog, an error going to crash.
(define (vat-handle win proc args crash)
  (safe-call 'job
             (lambda ()
               (if win
                   (parameterize ([current-window win])
                     (in-window-theme win (lambda () (apply proc args))))
                   (apply proc args)))
             crash)
  (when win (invalidate! win)))

(env-register-kind! 'thread
  'title "Thread"
  'base 'core
  'forks '()
  'doc "A sandbox in a vat of its own: its thread runs what is sent to it"
  'start (lambda (e) (vat-start! e)))
