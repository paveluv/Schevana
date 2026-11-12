;;; services/pacer-lab.ss — the pacer lab: while it's on, the pacer's
;;; choices are drawn at random each period, ten minutes of whatever the
;;; person is doing, and what each period saw is logged: frames judged,
;;; the late ones (the pacer's own and the compositor's), tick to screen.
;;; Each knob draws on its own, so over days a value's periods meet every
;;; other knob's values and every kind of work alike: pooled, they give
;;; its effect (a randomized factorial design). The trial is the pacer's
;;; (pacer-trial!), never the person's settings, so nothing of it is saved
;;; with the look. The log is plain data, a form a line, and says whether
;;; the lab is on, so a restart goes on where it was; world.ss loads it.

;; The knobs and the values each draws from.
(define pacer-lab-knobs
  '((pacer-margin-start 0 1/16 1/8 1/4)
    (pacer-margin-step 1/16 1/8 1/4)
    (pacer-miss-own 1/16 1/8 1/4)
    (pacer-lead-fade 1/4 1/2 1 2)
    (pacer-margin-fade 0 60)
    (frames-in-flight 2 3)))

(define pacer-lab-period-ms 600000)

(defvar *pacer-lab-log-path*
  (string-append user-directory "/pacer-lab.ss"))

;; Whether it's on; the periods logged, newest first, each a plist as the
;; log has it; this period; the second's timer that measures it.
(defvar *pacer-lab-on?* #f)
(defvar *pacer-lab-periods* '())
(defvar *pacer-lab-trial* #f)
(defvar *pacer-lab-timer* #f)

;; A period under way: when it began (ms, and the clock's seconds), the
;; knobs' values, the pacer's counts then, its tick-to-screen histogram,
;; and the frame ring's next row to measure.
(define-record-type pacer-lab-trial
  (fields began-ms began-s knobs counts hist (mutable measured)))

;;; ------------------------------------------------------------ histogram

;; Tick to screen, a bin a tenth of a ms to 100 ms; the last holds the rest.
(define pacer-lab-bins 1000)

(define (pacer-lab-hist) (make-fxvector pacer-lab-bins 0))

(define (pacer-lab-hist-add! h ms)
  (let ([k (min (- pacer-lab-bins 1) (max 0 (exact (floor (* ms 10)))))])
    (fxvector-set! h k (fx+ 1 (fxvector-ref h k)))))

;; The q quantile of h, ms; #f with nothing in it.
(define (pacer-lab-quantile h q)
  (let ([n (let loop ([k 0] [n 0])
             (if (= k pacer-lab-bins)
                 n
                 (loop (+ k 1) (+ n (fxvector-ref h k)))))])
    (and (> n 0)
         (let loop ([k 0] [seen 0])
           (let ([seen (+ seen (fxvector-ref h k))])
             (if (or (>= seen (* q n)) (= k (- pacer-lab-bins 1)))
                 (/ (+ k 0.5) 10)
                 (loop (+ k 1) seen)))))))

;;; ------------------------------------------------------------ the log

(define (pacer-lab-seconds) (time-second (current-time)))

(define (pacer-lab-log! form)
  (guard (c [#t (report-error! 'pacer-lab c)])
    (let ([dir (path-parent *pacer-lab-log-path*)])
      (unless (file-directory? dir) (mkdir dir)))
    (let ([p (open-file-output-port *pacer-lab-log-path*
                                    (file-options no-fail no-truncate append)
                                    (buffer-mode block)
                                    (native-transcoder))])
      ;; the newline first: a line a crash cut short ends before the next
      (newline p)
      (write form p)
      (close-port p))))

;; A period's form as the log has it: a plist after its tag.
(define (pacer-lab-period? x)
  (and (list? x) (pair? x) (eq? (car x) 'pacer-lab-period)
       (even? (length (cdr x)))
       (for-all (lambda (k) (number? (plist-ref (cdr x) k #f)))
                '(start seconds frames own theirs))
       (list? (plist-ref (cdr x) 'knobs #f))))

;; Reads the log (world.ss, at boot): its periods, and on if it last said
;; so, which starts a period. A line at a time, read as data, never
;; evaluated: one cut short by a crash is left out.
(define (pacer-lab-log-load!)
  (let ([periods '()] [on? #f])
    (when (file-exists? *pacer-lab-log-path*)
      (safely 'pacer-lab
        (lambda ()
          (call-with-input-file *pacer-lab-log-path*
            (lambda (p)
              (let loop ()
                (let ([line (get-line p)])
                  (unless (eof-object? line)
                    (let ([x (guard (c [#t #f])
                               (let ([s (open-input-string line)])
                                 (let ([x (read s)])
                                   (and (eof-object? (read s)) x))))])
                      (cond
                        [(pacer-lab-period? x)
                         (set! periods (cons (cdr x) periods))]
                        [(and (pair? x) (eq? (car x) 'pacer-lab-on))
                         (set! on? #t)]
                        [(and (pair? x) (eq? (car x) 'pacer-lab-off))
                         (set! on? #f)]))
                    (loop)))))))))
    (set! *pacer-lab-periods* periods)
    (set! *pacer-lab-on?* #f)
    (when on? (pacer-lab-on! #t))))

;;; ------------------------------------------------------------ a run

;; The lab on or off. On, a period begins and the log says so, with the
;; platform's row; off, the period so far is logged and the settings rule
;; the pacer again.
(define (pacer-lab-on! on?)
  (cond
    [(and on? (not *pacer-lab-on?*))
     (set! *pacer-lab-on?* #t)
     (pacer-lab-log! (list 'pacer-lab-on (pacer-lab-seconds)
                           (inspect-platform-row)))
     (pacer-lab-begin!)
     (pacer-lab-every-second!)]
    [(and (not on?) *pacer-lab-on?*)
     (pacer-lab-end!)
     (set! *pacer-lab-on?* #f)
     (set! *pacer-lab-trial* #f)
     (set! *pacer-lab-timer* #f)
     (pacer-trial! '())
     (pacer-lab-log! (list 'pacer-lab-off (pacer-lab-seconds)))]))

(define (pacer-lab-on?) *pacer-lab-on?*)

;; Each knob's value drawn, on its own: Chez's generator starts alike in
;; every run, so it's seeded from the clock once a run.
(defvar *pacer-lab-seeded?* #f)

(define (pacer-lab-draw)
  (unless *pacer-lab-seeded?*
    (random-seed (+ 1 (time-nanosecond (current-time))))
    (set! *pacer-lab-seeded?* #t))
  (map (lambda (k) (cons (car k) (list-ref (cdr k) (random (length (cdr k))))))
       pacer-lab-knobs))

;; A period begins: a trial drawn and handed to the pacer, which forgets
;; what it learned under the last.
(define (pacer-lab-begin!)
  (let ([knobs (pacer-lab-draw)])
    (pacer-trial! knobs)
    (set! *pacer-lab-trial*
      (make-pacer-lab-trial (now-ms) (pacer-lab-seconds) knobs
                            (fxvector->list *pacer-counts*) (pacer-lab-hist)
                            *frame-ring-n*))))

;; The period so far, measured and logged, if it judged any frame.
(define (pacer-lab-end!)
  (let ([t *pacer-lab-trial*])
    (when t
      (pacer-lab-measure!)
      (let* ([then (pacer-lab-trial-counts t)]
             [now (fxvector->list *pacer-counts*)]
             [h (pacer-lab-trial-hist t)]
             [period
              (list 'start (pacer-lab-trial-began-s t)
                    'seconds (quotient (- (now-ms) (pacer-lab-trial-began-ms t))
                                       1000)
                    'refresh-ns (host-frame-ns)
                    'knobs (pacer-lab-trial-knobs t)
                    'frames (- (car now) (car then))
                    'own (- (cadr now) (cadr then))
                    'theirs (- (caddr now) (caddr then))
                    'p50 (pacer-lab-quantile h 0.5)
                    'p90 (pacer-lab-quantile h 0.9)
                    'p99 (pacer-lab-quantile h 0.99))])
        (when (> (plist-ref period 'frames 0) 0)
          (set! *pacer-lab-periods* (cons period *pacer-lab-periods*))
          (pacer-lab-log! (cons 'pacer-lab-period period)))))))

;; Tick to screen of the frames the screen has reported on since, into
;; the period's histogram; the newest eight wait for their reports.
(define (pacer-lab-measure!)
  (let ([t *pacer-lab-trial*])
    (let loop ([i (max (pacer-lab-trial-measured t)
                       (- *frame-ring-n* frame-ring-rows -1))])
      (when (< i (- *frame-ring-n* 8))
        (let ([tick (inspect-frame-at i 'tick)]
              [shown (inspect-frame-at i 'shown)])
          (when (and tick shown)
            (pacer-lab-hist-add! (pacer-lab-trial-hist t)
                                 (/ (- shown tick) 1e6))))
        (pacer-lab-trial-measured-set! t (+ i 1))
        (loop (+ i 1))))))

;; Once a second while on: the frames measured, and the period ended and
;; the next begun once it's long enough. A timer of an earlier load or
;; run finds another in its place, and stops.
(define (pacer-lab-every-second!)
  (letrec ([timer (after 1000
                         (lambda ()
                           (when (eq? timer *pacer-lab-timer*)
                             (pacer-lab-second!)
                             (pacer-lab-every-second!))))])
    (set! *pacer-lab-timer* timer)))

(define (pacer-lab-second!)
  (pacer-lab-measure!)
  (when (>= (- (now-ms) (pacer-lab-trial-began-ms *pacer-lab-trial*))
            pacer-lab-period-ms)
    (pacer-lab-end!)
    (pacer-lab-begin!)))

;; This period: its knobs, seconds so far, frames judged and late so far;
;; #f while off.
(define (pacer-lab-now)
  (let ([t *pacer-lab-trial*])
    (and t
         (let ([then (pacer-lab-trial-counts t)]
               [now (fxvector->list *pacer-counts*)])
           (list 'knobs (pacer-lab-trial-knobs t)
                 'seconds (quotient (- (now-ms) (pacer-lab-trial-began-ms t))
                                    1000)
                 'frames (- (car now) (car then))
                 'late (- (+ (cadr now) (caddr now))
                          (+ (cadr then) (caddr then))))))))

(define (pacer-lab-periods) *pacer-lab-periods*)

;;; ------------------------------------------------------------ effects

;; A knob's value over the periods that held it: how many, their frames,
;; the late ones (the pacer's own and the compositor's together: which is
;; which hangs on the knobs), late per 10,000 frames and its standard
;; error, and tick to screen at the median and the 99th (the periods',
;; weighted by frames). The error is from the periods' spread about the
;; rate, as a ratio's: misses come in bursts, so a count's own (Poisson's)
;; would claim too much. #f for it with under two periods.
(define-record-type pacer-lab-effect
  (fields knob value periods frames own theirs rate error p50 p99
          (mutable verdict)))

(define (pacer-lab-effect-of knob value periods)
  (let* ([of (filter (lambda (p)
                       (equal? (cdr (or (assq knob (plist-ref p 'knobs '()))
                                        '(#f . #f)))
                               value))
                     periods)]
         [get (lambda (k p) (or (plist-ref p k #f) 0))]
         [sum (lambda (k) (apply + (map (lambda (p) (get k p)) of)))]
         [n (length of)] [f (sum 'frames)]
         [late (lambda (p) (+ (get 'own p) (get 'theirs p)))]
         [rate (and (> f 0) (/ (+ (sum 'own) (sum 'theirs)) f))]
         [mean (lambda (k)
                 (let ([w (filter (lambda (p) (plist-ref p k #f)) of)])
                   (and (pair? w)
                        (/ (apply + (map (lambda (p) (* (get 'frames p)
                                                        (get k p)))
                                         w))
                           (max 1 (apply + (map (lambda (p) (get 'frames p))
                                                w)))))))])
    (make-pacer-lab-effect
     knob value n f (sum 'own) (sum 'theirs)
     (and rate (* 10000. rate))
     (and rate (> n 1)
          (* 10000.
             (/ (sqrt (* (/ n (- n 1))
                         (apply + (map (lambda (p)
                                         (expt (- (late p)
                                                  (* rate (get 'frames p)))
                                               2))
                                       of))))
                f)))
     (mean 'p50) (mean 'p99) #f)))

;; Every knob's values, each with its verdict: best, the lowest rate;
;; tied, within two standard errors of it; worse; or #f, with too little
;; to tell.
(define (pacer-lab-effects . periods)
  (let ([periods (if (pair? periods) (car periods) *pacer-lab-periods*)])
    (apply append
           (map (lambda (k)
                  (let* ([es (map (lambda (v)
                                    (pacer-lab-effect-of (car k) v periods))
                                  (cdr k))]
                         [known (filter pacer-lab-effect-error es)]
                         [best (and (pair? known)
                                    (fold-left
                                     (lambda (b e)
                                       (if (< (pacer-lab-effect-rate e)
                                              (pacer-lab-effect-rate b))
                                           e
                                           b))
                                     (car known) (cdr known)))])
                    (for-each
                     (lambda (e)
                       (pacer-lab-effect-verdict-set!
                        e
                        (cond
                          [(not (pacer-lab-effect-error e)) #f]
                          [(eq? e best) 'best]
                          [(<= (- (pacer-lab-effect-rate e)
                                  (pacer-lab-effect-rate best))
                               (* 2 (sqrt (+ (expt (pacer-lab-effect-error e)
                                                   2)
                                             (expt (pacer-lab-effect-error
                                                    best)
                                                   2)))))
                           'tied]
                          [else 'worse])))
                     es)
                    es))
                pacer-lab-knobs))))
