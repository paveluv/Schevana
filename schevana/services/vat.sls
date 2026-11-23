;;; (schevana services vat) — vats: threads, each with a mailbox and a
;;; sandbox, that run jobs and hand their results back to core1.
;;;
;;;   (define v (vat-of (env-fork (env-root) 'thread 'name 'tally)))
;;;   (vat-eval! v '(define n 0) #f)       runs a form in v's sandbox
;;;   (vat-eval! v '(define (add! k) (set! n (+ n k)) n) #f)
;;;   (vat-send! v 'add! '(5) show)        calls v's add!; (show 5) on core1
;;;   (vat-send! (vat-pool) step! (list grid) show)   runs a worklet on
;;;                                        the pool's threads
;;;   (vat-repl! v forms 72 show-lines show-error)   evaluates forms as a
;;;                                        REPL does, printing the values
;;;   (vat-job-kill! j)   (vat-drop! v)
;;;   (vat-of e)                           the vat whose sandbox is e
;;;   (vat-drop-env! e)                    drops e, its children and their
;;;                                        vats
;;;   (vat-threads-of v)   (vat-jobs-of v)   v's thread count, its jobs
;;;
;;; The environment kind thread (env-fork) is a sandbox with a vat of its
;;; own, which starts once the sandbox has been shared what it is given.
;;;
;;; A vat is a thread, its mailbox and a sandbox ((schevana services env))
;;; that only its thread evaluates in, so only that thread writes the
;;; sandbox's globals (rule S4, by construction). Share names with the
;;; sandbox before the vat starts; after that, the sandbox is the vat's.
;;;
;;; A message is a job: a worklet or the name of a procedure in the vat's
;;; sandbox, with its arguments; or a form, for vat-eval!. The arguments
;;; may hold no procedure but worklets (crew-stray), and neither may the
;;; results. A vat with one thread runs its jobs one at a time, in the
;;; order they were sent. When a job returns, (then v ...) runs on core1 at
;;; core1's next step, given the results, as a handler of the window the
;;; job was sent from: with (current-window) bound and under the watchdog,
;;; so an error in then crashes the window. A job that raises crashes its
;;; window too (with no window, it shows a red toast), unless it was sent
;;; with a fail, which is then given the condition as then is given the
;;; results. vat-repl! prints the values on the vat's thread, where they
;;; live, so its then gets their texts and its fail the error's text.
;;;
;;; A job is pending until core1 takes its outcome, or until it is killed:
;;; by vat-job-kill!, by its window closing or crashing, or by its vat
;;; being dropped. A killed job never starts, or, if it is running, it is
;;; stopped within vat-fuel timer ticks of its own code (its thread's timer
;;; checks), and its then never runs: the kill happens on core1, as the
;;; delivery does, so the kill always wins.
;;;
;;; The pool, (vat-pool), is a vat on /worklets served by (vat-pool-size)
;;; threads, 4 unless (vat-pool-size-set! n) says otherwise. It runs only
;;; worklets, in no particular order.

(library (schevana services vat)
  (export
    vat vat? vat-job? vat-job-kind vat-job-window vat-of vat-threads-of
    vat-env-kind vat-jobs-of vat-pool vat-pool-size vat-pool-size-set! vat-drop!
    vat-drop-env! vat-send! vat-eval! vat-repl! vat-job-kill!)
  (import (chezscheme)
          (only (schevana base) at-load define-state library-layer set-hook!)
          (only (schevana core) current-window in-window-theme invalidate!
                post-core1! proc report-error! safe-call window-crash!
                window-gone!)
          (only (schevana kits repl) repl-value->string)
          (only (schevana services crew) crew-stray)
          (only (schevana services env) env-register-kind! env-environment
                env-children env-drop! env-find env-kind env-base env-path))

  (library-layer services)

  (define vat-fuel 20000)           ; timer ticks between checks for a kill
  (define vat-idle-ns 50000000)     ; the longest an idle thread waits

  ;; A vat has its sandbox; its mailbox, a box of jobs with the oldest
  ;; first; the lock and the condition its idle threads wait on; its
  ;; threads, each kept as the box that stops it; and dropped, a box that
  ;; says whether it was dropped.
  (define-record-type vat
    (nongenerative schevana-vat-1)
    (fields env mailbox mutex wake (mutable threads) dropped))

  (at-load
   (record-writer (record-type-descriptor vat)
     (lambda (v p wr) (fprintf p "#<vat ~a>" (env-path (vat-env v))))))

  ;; A job has its vat; its kind, which is call (proc, a worklet or a name
  ;; in the vat's sandbox, applied to args), eval (args is a form) or show
  ;; (args is the width and the forms of vat-repl!); its then, window and
  ;; fail (each may be #f); and killed, a box that core1 sets and the vat's
  ;; thread reads.
  (define-record-type vat-job
    (nongenerative schevana-vat-job-2)
    (fields vat kind proc args then window fail killed))

  (define-state *vat-jobs* '())     ; the pending jobs, on core1
  (define-state *vat-all* '())      ; the vats not dropped, the pool too
  (define-state *vat-pool* #f)
  (define-state *vat-pool-size* 4)
  ;; on a vat's thread: the job it is running and the continuation that
  ;; escapes from it, or #f
  (define-state vat-current (make-thread-parameter #f))

  ;;; ---------------------------------------------------------------- vats

  ;; Starts a vat with one thread on e, which must be a sandbox on the core
  ;; base. Returns the vat.
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

  ;; The kind e is shown as: its own kind, or, for a bare environment,
  ;; thread when a vat runs on it, else sandbox or namespace by its base.
  (define (vat-env-kind e)
    (cond [(env-kind e)]
          [(vat-of e) 'thread]
          [(memq (env-base e) '(confined core)) 'sandbox]
          [else 'namespace]))

  ;; Returns v's pending jobs, the oldest first.
  (define (vat-jobs-of v)
    (reverse (filter (lambda (j) (eq? (vat-job-vat j) v)) *vat-jobs*)))

  ;; Raises b, a flag that another thread reads. box-cas! may fail on ARM
  ;; even when nothing else changed the box (Chez's guide), so it is tried
  ;; until the flag is up.
  (define (vat-flag-up! b)
    (let loop () (unless (or (unbox b) (box-cas! b #f #t)) (loop))))

  ;; Gives v n threads: more start, or those past the first n stop once
  ;; their current turn is done.
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

  ;; Ends v's threads, each once its current turn is done, and kills v's
  ;; jobs.
  (define (vat-drop! v)
    (vat-flag-up! (vat-dropped v))
    (set! *vat-all* (remq v *vat-all*))
    (for-each (lambda (j) (when (eq? (vat-job-vat j) v) (vat-job-kill! j)))
              *vat-jobs*)
    (vat-wake! v))

  ;; Drops e and its children (env-drop!, which may refuse), and the vats
  ;; that run on them.
  (define (vat-drop-env! e)
    (env-drop! e)
    (let walk ([e e])
      (let ([v (vat-of e)]) (when v (vat-drop! v)))
      (for-each walk (env-children e))))

  ;; Starts a thread for v: it sets its own timer handler, then takes turns
  ;; until v is dropped or the thread is stopped. It calls both by name, so
  ;; in the hacker edition a redefinition reaches a running thread. Returns
  ;; the box that stops the thread.
  (define (vat-fork! v)
    (let ([stop (box #f)])
      (fork-thread
       (lambda ()
         (timer-interrupt-handler (lambda () (vat-timer!)))
         (let loop () (when (and (not (unbox stop)) (vat-step! v)) (loop)))))
      stop))

  ;; One turn: runs a job, or waits for one. Returns #f once v is dropped,
  ;; else #t.
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
  ;; an engine (a REPL's evaluation) is never stopped while it holds the
  ;; lock; if every try fails, an idle thread wakes when its wait ends.
  (define (vat-wake! v)
    (let try ([n 0])
      (unless (or (with-interrupts-disabled
                   (and (mutex-acquire (vat-mutex v) #f)
                        (begin (condition-broadcast (vat-wake v))
                               (mutex-release (vat-mutex v))
                               #t)))
                  (= n 1000))
        (try (+ n 1)))))

  ;; Adds j to v's mailbox. The fences make what core1 wrote before it sent
  ;; the job visible to the vat's thread, as post-core1! does for core1
  ;; with a job's outcome.
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

  ;;; ---------------------------------------------------------------- jobs

  ;; Sends v the job (proc arg ...), where proc is a worklet or the name of
  ;; a procedure in v's sandbox, with then and, optionally, a fail. Returns
  ;; the job.
  (define (vat-send! v proc args then . fail)
    (when (and (symbol? proc) (eq? v *vat-pool*))
      (errorf 'vat-send! "the pool runs worklets only: ~s" proc))
    (vat-post! 'vat-send! v 'call proc args then fail))

  ;; Sends v a form to evaluate in its sandbox. Returns the job.
  (define (vat-eval! v form then . fail)
    (vat-post! 'vat-eval! v 'eval #f form then fail))

  ;; Sends v forms to evaluate in turn, as a REPL does. Calls (then texts),
  ;; with each value except (void) printed width characters wide, or (fail
  ;; text) for an error. Returns the job.
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

  (define (vat-job-kill! j)
    (set! *vat-jobs* (remq j *vat-jobs*))
    (vat-flag-up! (vat-job-killed j)))

  ;; Kills the jobs sent from win, as it closes or crashes.
  (define (vat-window-gone! win)
    (for-each (lambda (j) (when (eq? (vat-job-window j) win) (vat-job-kill! j)))
              *vat-jobs*))

  (set-hook! (window-gone! win) (vat-window-gone! win))

  ;; On j's vat's thread: runs j with the timer on, and posts the outcome
  ;; to core1. The escape (vat-current) is cleared before j's results leave
  ;; the call/1cc, so the timer never takes it once it is spent.
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
        (when r   ; #f: killed, and escaped
          (post-core1! (lambda () (vat-deliver! j (car r) (cdr r))))))))

  (define (vat-call j)
    (let ([e (env-environment (vat-env (vat-job-vat j)))]
          [args (vat-job-args j)])
      (case (vat-job-kind j)
        [(eval) (eval args e)]
        [(show) (vat-show e (car args) (cdr args))]
        [else (let ([p (vat-job-proc j)])
                (apply (if (symbol? p) (top-level-value p e) p) args))])))

  ;; Evaluates forms in e in turn, on the vat's thread, and prints each
  ;; value except (void) width characters wide with Chez's printer. Returns
  ;; the texts.
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
                                       (cons (repl-value->string v) texts)))
                                 texts vals))))))))

  (define (vat-condition-text c)
    (call-with-string-output-port
     (lambda (p)
       (if (condition? c)
           (display-condition c p)
           (fprintf p "non-condition raised: ~s" c)))))

  ;; The timer handler of a vat's thread: escapes from the job once it is
  ;; killed, and otherwise sets the timer again.
  (define (vat-timer!)
    (let ([now (vat-current)])
      (when now
        (if (unbox (vat-job-killed (car now)))
            (begin (vat-current #f) ((cdr now) #f))
            (set-timer vat-fuel)))))

  ;; On core1: calls j's then with its results, or its fail with the error,
  ;; unless j was killed in the meantime. The results are checked for
  ;; procedures here, on core1, where the worklets' table is.
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

  ;; Calls (proc arg ...) on core1 as a handler of win (or of no window):
  ;; with win's theme and (current-window) bound, under the watchdog, an
  ;; error going to crash. Then win draws again.
  (define (vat-handle win proc args crash)
    (safe-call 'job
               (lambda ()
                 (if win
                     (parameterize ([current-window win])
                       (in-window-theme win (lambda () (apply proc args))))
                     (apply proc args)))
               crash)
    (when win (invalidate! win)))

  (at-load
   (env-register-kind! 'thread
     'title "Thread"
     'base 'core
     'forks '()
     'doc "A sandbox in a vat of its own: its thread runs what is sent to it"
     'start (lambda (e) (vat-start! e)))))
