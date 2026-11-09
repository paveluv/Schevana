;;; tests/units/profile.ss — the profiler (services/profile.ss).

;;; the profiler (services/profile.ss)

(for-each close-window! (windows))
(steps 2)

;; Busy for ms of the profiler's clock.
(define (profile-test-busy ms)
  (let ([t0 (now-ns)])
    (let loop ()
      (when (< (- (now-ns) t0) (* ms 1000000)) (loop)))))

;; thunk's result, on a clock that moves ns a read: what a span holds is what it
;; reads, whatever else the machine is doing. The real one catches up after it,
;; so that ticks stay in order. Set and put back, not fluid-let: an engine keeps
;; the dynamic context of its first run, so a process first run inside would
;; wind this clock back in at each of its turns after.
(define (profile-test-on-clock ns thunk)
  (let* ([real now-ns] [real-ms now-ms] [t (real)]
         [put-back! (lambda () (set! now-ns real) (set! now-ms real-ms))])
    (set! now-ns (lambda () (set! t (+ t ns)) t))
    (set! now-ms (lambda () (set! t (+ t ns)) (quotient t 1000000)))
    (let ([result (guard (c [#t (put-back!) (raise c)]) (thunk))])
      (put-back!)
      (let catch-up () (when (< (real) t) (catch-up)))
      result)))

;; A tick's uses of x: a window's or a process's subject, or a key.
(define (profile-test-uses tick x)
  (filter (lambda (u) (equal? (profile-use-subject u) (profile-subject-of x)))
          (profile-tick-uses tick)))

(define (profile-test-near? a b) (< (abs (- a b)) 1e-6))

;; A tick's phases' ms, all of them.
(define (profile-test-phases tick)
  (map (lambda (p) (profile-tick-phase-ms tick p))
       (vector->list profile-phase-names)))

;; Bytes allocated by thunk, (statistics) aside.
(define (profile-test-bytes thunk)
  (let ([b0 (sstats-bytes (statistics))])
    (thunk)
    (- (sstats-bytes (statistics)) b0)))

(check "profiling is on at boot: the hooks are the profiler's, the collect \
        handler its own, and ticks are kept"
       (and (profile-on?) (pair? *profile-span*)
            (eq? (car *profile-span*) profile-begin!)
            (eq? (collect-request-handler) profile-collect)
            (pair? (profile-ticks))))

(check "off, the hook is #f: no tick is kept, the clock is read only for the \
        pacer's busy time and a frame's own, Chez's own collect handler is \
        back; on again, ticks are kept"
       (let ([reads 0] [clock now-ns] [before (profile-ticks)]
             [frames *frames-drawn*])
         (profile-on! #f)
         (set! now-ns
           (lambda () (set! reads (+ reads 1)) (clock)))
         (steps 5)
         (set! now-ns clock)
         (let ([off (and (not (profile-on?)) (not *profile-span*)
                         (equal? before (profile-ticks))
                         ;; a step's, only the pacer's, and a frame drawn
                         ;; (the top bar's clock asks for one each second)
                         ;; times itself for the frame ring
                         (<= reads (+ (* 5 4)
                                      (* 2 (- *frames-drawn* frames))))
                         (eq? (collect-request-handler)
                              *profile-plain-collect*))])
           (profile-on! #t)
           (and off (= 3 (length (profile-test-ticks (lambda () (steps 3)))))
                *profile-span*))))

(check "a span allocates nothing, on or off: neither its hook's site nor \
        the profiler's books (a step's: its one guard)"
       (let* ([spans (lambda ()
                       (with-profile-span 'step #f
                         (with-profile-span 'render #f
                           (do ([i 0 (+ i 1)]) ((= i 10000))
                             (with-profile-span (+ 1000000 (mod i 30)) 'draw
                               (with-profile-span 'profile-test-x #f
                                 i))))))]
              ;; each measured right after a collection, so that none of
              ;; the world's falls in it
              [settled (lambda (thunk)
                         (collector-pass! 0 1)
                         (profile-test-bytes thunk))]
              [none (settled void)]   ; (statistics)'s own
              [on (begin (spans) (- (settled spans) none))]
              [off (begin (profile-on! #f)
                          (- (settled spans) none))])
         (profile-on! #t)
         (printf "  ~a bytes on, ~a off, for 20,000 spans and a step\n" on off)
         (and (< on 1000) (= off 0))))

(check "spans nest: each keeps its self time, the phases and the uses add \
        up to the step, idle is the step's own"
       (let* ([s (car (profile-test-on-clock
                       1000
                       (lambda ()
                         (profile-test-ticks
                          (lambda ()
                            (with-profile-span 'step #f
                              (profile-test-busy 1)
                              (with-profile-span 'render #f
                                (profile-test-busy 2)
                                (with-profile-span 'profile-test-inner #f
                                  (profile-test-busy 3)))))))))]
              [use (lambda (k) (profile-use-ms
                                (car (profile-test-uses s k))))])
         (and (< 0.5 (profile-tick-phase-ms s 'input-wait) 1.5)
              (< 1.5 (use 'render) 2.5)
              (< 2.5 (use 'profile-test-inner) 3.5)
              (eq? (profile-use-phase (car (profile-test-uses
                                            s 'profile-test-inner)))
                   'render)
              (profile-test-near?
               (+ (profile-tick-phase-ms s 'render)
                  (profile-tick-phase-ms s 'gc))
               (apply + (map profile-use-ms (profile-tick-uses s))))
              (profile-test-near? (apply + (profile-test-phases s))
                                  (profile-tick-ms s)))))

(check "a span already over, told after, counts as if it had been open: \
        its length to its phase, inside the span open around it (core0's \
        waits for the screen)"
       (let* ([s (car (profile-test-on-clock
                       1000
                       (lambda ()
                         (profile-test-ticks
                          (lambda ()
                            (with-profile-span 'step #f
                              (with-profile-span 'render #f
                                (let ([t (now-ns)])
                                  (profile-test-busy 3)
                                  (profile-span-past! 'vsync-wait 'acquire
                                                      t (+ t 2000000))))))))))]
              [use (lambda (k) (profile-use-ms
                                (car (profile-test-uses s k))))])
         (and (profile-test-near? (profile-tick-phase-ms s 'vsync-wait) 2.0)
              (< 0.5 (use 'render) 1.5)
              (profile-test-near? (apply + (profile-test-phases s))
                                  (profile-tick-ms s)))))

(let ([life-win (life)])
  (move-window! life-win 600 300)
  (check "every step of the world adds up: its phases to its time, its uses \
          and its input-wait too, no part below 0"
         (let ([ss (profile-test-ticks (lambda () (steps 20)))])
           (close-window! life-win)
           (and (= (length ss) 20)
                (for-all
                 (lambda (s)
                   (let ([uses (profile-tick-uses s)])
                     (and (profile-test-near? (apply + (profile-test-phases s))
                                              (profile-tick-ms s))
                          (profile-test-near?
                           (+ (profile-tick-phase-ms s 'input-wait)
                              (apply + (map profile-use-ms uses)))
                           (profile-tick-ms s))
                          (for-all (lambda (u) (>= (profile-use-ms u) 0))
                                   uses)
                          (for-all (lambda (ms) (>= ms 0))
                                   (profile-test-phases s)))))
                 ss)))))

(let ([slow (open-window "Slow"
              'size '(200 . 100)
              'tick (lambda (win) (invalidate! win))
              'draw (lambda (win w h) (profile-test-busy 3)))]
      [life-win (life)])
  (check "a window whose draw is made slow comes first among Monitor's \
          consumers, its draw the most of its parts"
         (let* ([ss (profile-test-ticks (lambda () (steps 10)))]
                [ts (filter (lambda (t)
                              (monitor-subject? (profile-total-what t)))
                            (profile-totals ss #t))])
           (close-window! slow)
           (close-window! life-win)
           (and (pair? ts)
                (equal? (profile-total-what (car ts))
                        (profile-subject-of slow))
                (equal? (profile-total-what
                         (car (profile-total-parts (car ts))))
                        '(draw . render))
                (= (profile-total-ticks (car ts)) 10)
                (>= (/ (profile-total-ms (car ts)) 10) 3)))))

(let ([p (spawn "profile-test-busy" (lambda () (let loop () (loop))))])
  (check "a busy process shows its share: most of the processes' phase, in \
          one turn a step, wherever in its ms the step begins"
         ;; the shares on a clock of their own, as a machine's other work would
         ;; shift them, 100 µs a read, each step a read further into its ms
         ;; than the last: in one of them the ms turns between any two reads.
         ;; 20 ms a step, of which run-procs!'s and the collector's own reads
         ;; are a small part, as on a real clock. The real steps only have to
         ;; run it.
         (let* ([ss (profile-test-on-clock
                     100000
                     (lambda ()
                       (profile-test-ticks
                        (lambda ()
                          (do ([i 0 (+ i 1)]) ((= i 10))
                            (let ([ms (now-ms)])
                              (let wait () (when (= (now-ms) ms) (wait))))
                            (do ([j 0 (+ j 1)]) ((= j i)) (now-ns))
                            (with-profile-span 'step #f
                              (with-profile-span 'procs #f
                                (run-procs! 20))))))))]
                [real (profile-test-ticks (lambda () (steps 10)))])
           (kill! p)
           (and (= (length ss) 10)
                (for-all
                 (lambda (s)
                   (let ([u (profile-test-uses s p)])
                     (and (= (length u) 1)
                          (= (profile-use-calls (car u)) 1)
                          (> (profile-use-ms (car u))
                             (* 0.8 (profile-tick-phase-ms s 'procs))))))
                 ss)
                (exists (lambda (s) (pair? (profile-test-uses s p))) real)))))

(check "a (collect) shows in the memory numbers, and so does the heap; a \
        collection requested on the main loop is a span of its own, gc"
       (let* ([timer (profile-test-ticks
                      (lambda () (after 0 (lambda () (collect))) (steps 2)))]
              [g0 (collections)]
              [requested
               (car (profile-test-ticks
                     (lambda ()
                       (with-profile-span 'step #f
                         (with-profile-span 'event #f
                           (let loop ([keep '()])
                             (when (= (collections) g0)
                               (loop (cons (make-vector 100)
                                           (if (> (length keep) 50)
                                               '()
                                               keep))))))))))])
         (and (exists (lambda (s) (>= (profile-tick-ref s 'gcs) 1)) timer)
              (for-all (lambda (s) (> (profile-tick-ref s 'heap) 0)) timer)
              (>= (profile-tick-ref requested 'gcs) 1)
              (> (profile-tick-ref requested 'allocated) 0)
              (pair? (profile-test-uses requested 'gc))
              (eq? (profile-use-phase (car (profile-test-uses requested 'gc)))
                   'event)
              (> (profile-tick-phase-ms requested 'gc) 0)
              (> (profile-tick-ref requested 'gc-ms) 0))))

(let* ([w (open-window "Inner"
            'size '(200 . 100)
            'tick (lambda (win)
                    (safely 'profile-test-handler
                            (lambda () (profile-test-busy 1)))))]
       [p (spawn "inner"
                 (lambda ()
                   (let loop ()
                     (safely 'profile-test-process (lambda () (yield)))
                     (loop))))])
  (check "a span inside an engine (a handler, a process) is not timed: its \
          time is its handler's or its process's"
         (let ([ss (profile-test-ticks (lambda () (steps 5)))])
           (close-window! w)
           (kill! p)
           (for-all
            (lambda (s)
              (and (null? (profile-test-uses s 'profile-test-handler))
                   (null? (profile-test-uses s 'profile-test-process))
                   (exists (lambda (u)
                             (and (eq? (profile-use-part u) 'tick)
                                  (>= (profile-use-ms u) 1)))
                           (profile-test-uses s w))
                   (pair? (profile-test-uses s p))))
            ss))))

(check "a span on a thread other than the one profile-on! saw is untimed, \
        and so is one deeper than the stack: no step is lost, nothing \
        overflows"
       (let* ([thread *profile-thread*]
              [others (profile-test-ticks
                       (lambda ()
                         (set! *profile-thread* (+ thread 1))
                         (steps 3)
                         (set! *profile-thread* thread)))]
              [deep (profile-test-ticks
                     (lambda ()
                       (with-profile-span 'step #f
                         (let nest ([n 100])
                           (if (= n 0)
                               (profile-test-busy 1)
                               (with-profile-span 'render #f
                                 (nest (- n 1))))))))])
         (and (null? others) (= (length deep) 1)
              (profile-test-near? (apply + (profile-test-phases (car deep)))
                                  (profile-tick-ms (car deep)))
              (>= (profile-tick-phase-ms (car deep) 'render) 1))))

(check "a raise out of a span, caught in its parent, leaves it open: the \
        ends after it close a span each, the innermost, the step's end the \
        rest, and the step's phases still add up to it"
       (let ([s (car (profile-test-on-clock
                      1000
                      (lambda ()
                        (profile-test-ticks
                         (lambda ()
                           (with-profile-span 'step #f
                             (with-profile-span 'render #f
                               (guard (e [#t 'caught])
                                 (with-profile-span 'profile-test-raiser #f
                                   (profile-test-busy 2)
                                   (raise 'oops)))
                               (with-profile-span 'profile-test-after #f
                                 (profile-test-busy 3)))))))))]
             [ms (lambda (s k)
                   (apply + (map profile-use-ms (profile-test-uses s k))))])
         (and (profile-test-near? (apply + (profile-test-phases s))
                                  (profile-tick-ms s))
              (< 1.5 (ms s 'profile-test-raiser) 2.5)
              (< 2.5 (ms s 'profile-test-after) 3.5)
              (< (ms s 'render) 0.5)
              (eq? (profile-use-phase
                    (car (profile-test-uses s 'profile-test-after)))
                   'render))))

(check "a collector that raises turns itself off, says so once, and the \
        world goes on drawing"
       (let ([done profile-tick-done!] [errors 0] [report report-error!])
         (set! report-error! (lambda (who c)
                               (set! errors (+ errors 1))
                               (report who c)))
         (set! profile-tick-done! (lambda (now ns) (car '())))
         (steps 3)
         (set! profile-tick-done! done)
         (set! report-error! report)
         (let ([off (not (profile-on?))] [drawn *frames-drawn*])
           (invalidate!)
           (steps 2)
           (profile-on! #t)
           (set! *toasts* '())
           (and off (= errors 1) (> *frames-drawn* drawn)))))

(check "the history keeps no closed window and no ended process alive: \
        each is a subject, its id, and its title or name when first seen"
       (let* ([w (open-window "Kept?" 'size '(200 . 100)
                              'tick (lambda (win) (invalidate! win)))]
              [p (spawn "kept?" (lambda () (let loop () (yield) (loop))))]
              [w-ptr (weak-cons w #f)] [p-ptr (weak-cons p #f)])
         (steps 5)
         (let ([subjects (list (profile-subject-of w) (profile-subject-of p))]
               [ids (list (window-id w) (proc-id p))])
           (close-window! w)
           (kill! p)
           (set! w #f)
           (set! p #f)
           (steps 5)
           (collect (collect-maximum-generation))
           (and (bwp-object? (car w-ptr)) (bwp-object? (car p-ptr))
                (exists (lambda (s)
                          (member (car subjects)
                                  (map profile-use-subject
                                       (profile-tick-uses s))))
                        (profile-ticks))
                (equal? (map car subjects) '(window process))
                (equal? (map cdr subjects) ids)
                (equal? (map profile-subject-name subjects)
                        '("Kept?" "kept?"))))))

(let* ([a (open-window "Twin" 'size '(100 . 60))]
       [b (open-window "Twin" 'size '(100 . 60))]
       [c (open-window "Single" 'size '(100 . 60))]
       [seen (steps 1)]   ; the profiler takes their titles
       [subjects (map profile-subject-of (list a b c))]
       [labels (monitor-labels subjects)])
  (close-window! a)
  (check "two windows of one title get their ids in Monitor's labels, a \
          closed one says so, and a title of its own stays plain"
         (equal? (map cdr labels)
                 (list (format "Twin (window ~a)" (window-id a))
                       (format "Twin (window ~a)" (window-id b))
                       "Single")))
  (check "and once one of them is closed"
         (equal? (map cdr (monitor-labels subjects))
                 (list (format "Twin (window ~a, closed)" (window-id a))
                       (format "Twin (window ~a)" (window-id b))
                       "Single")))
  (for-each close-window! (list b c)))

(check "the history keeps the ticks of the last seconds (at most 100 a \
        second of them) and the seconds of the last minutes asked for \
        (profile-history!), by the clock"
       (let ([clock now-ns] [fake (expt 10 15)])
         (define (run! seconds)   ; 100 ms a step
           (do ([i 0 (+ i 1)]) ((= i (* 10 seconds)))
             (set! fake (+ fake (expt 10 8)))
             (schevana-step! 0)))
         (define (within? seconds)   ; the ticks kept span that, a second more
           (let ([ss (profile-ticks)])
             (and (pair? ss)
                  (> (profile-tick-end (car (last-pair ss)))
                     (- (profile-tick-end (car ss)) (* 1000 (+ seconds 1))))
                  (< (profile-tick-end (car (last-pair ss)))
                     (- (profile-tick-end (car ss)) (* 1000 (- seconds 1)))))))
         (set! now-ns (lambda () fake))
         (profile-clear!)
         (profile-history! 30 1)
         (run! 90)
         (let ([long (and (within? 30) (= (length (profile-seconds)) 60))])
           (profile-history! 5 2)
           (let ([now (within? 5)])
             (run! 150)
             (let ([later (and (within? 5)
                               (= (length (profile-seconds)) 120))])
               (set! now-ns clock)
               ;; back to back, thousands a second: at most 100 a second
               ;; of it
               (profile-history! 2 10)
               (steps 2000)
               (let ([most (= (length (profile-ticks)) 200)])
                 (profile-history! 30 10)
                 (profile-clear!)
                 (and long now later most)))))))

(check "Monitor's Consumers fit their columns to the tree's room: the last \
        (the minute's lines) ends clear of a scroll bar always shown"
       (let* ([m (monitor)] [ui (window-ref m 'ui)])
         (steps 3)
         (let-values ([(cx cy cw ch) (content-rect m)])   ; its Ticks
           (let* ([r (ui-find ui '(tab ticks))]
                  [x (exact (round (+ cx (ui-region-x r)
                                      (/ (ui-region-w r) 2))))]
                  [y (exact (round (+ cy (ui-region-y r)
                                      (/ (ui-region-h r) 2))))])
             (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))))
         (steps 3)
         (let-values ([(cx cy cw ch) (content-rect m)])
           (let* ([r (ui-find ui '(consumers header spark))]
                  [end (and r (+ (ui-region-x r) (ui-region-w r)))]
                  [room (- cw (ui-pad) (ui-scrollbar-inset 'right))])
             (close-window! m)
             (steps 1)
             (printf "  ~s ~s\n" end room)
             (and end (> (ui-scrollbar-inset 'right) 0) (<= end room))))))

(check "Monitor's Consumers say each row's type, list a row for the minute \
        since it last ran, and a row opened stays open as its parts go \
        quiet: a window not asked to draw shows its list, and only that"
       (let* ([fake (expt 10 15)]
              [busy? #t]
              [q (open-window "Quiet"
                              'size '(100 . 60)
                              'tick (lambda (win)
                                      (set! fake (+ fake 1000000))
                                      (when busy? (invalidate! win)))
                              'draw (lambda (win w h)
                                      (set! fake (+ fake 1000000))))]
              [m (monitor)] [ui (window-ref m 'ui)]
              [subject (profile-subject-of q)]
              [draw-part (list subject 'draw 'render)])
         (define (run! seconds)   ; 500 ms a step
           (do ([i 0 (+ i 1)]) ((= i (* 2 seconds)))
             (set! fake (+ fake 500000000))
             (schevana-step! 0)))
         (define (rows)
           (map ui-tree-row-node
                (vector->list (ui-memo ui '(consumers rows) '#()))))
         (fluid-let ([now-ns (lambda () fake)]
                     [now-ms (lambda () (quotient fake 1000000))])
           (profile-clear!)
           (steps 3)
           (let-values ([(cx cy cw ch) (content-rect m)])   ; its Ticks
             (let* ([r (ui-find ui '(tab ticks))]
                    [x (exact (round (+ cx (ui-region-x r)
                                        (/ (ui-region-w r) 2))))]
                    [y (exact (round (+ cy (ui-region-y r)
                                        (/ (ui-region-h r) 2))))])
               (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))))
           (run! 4)
           (hashtable-set! (ui-tree-states ui 'consumers) subject #t)
           (run! 4)
           (let ([working (member draw-part (rows))]
                 [column (ui-find ui '(consumers header type))])
             (set! busy? #f)
             (run! 10)   ; out of the 5 s the columns sum
             (let ([quiet (member draw-part (rows))])
               (run! 70)   ; out of the minute: only its frame ran in it
               (let ([kept (and (member (list subject #f 'render) (rows))
                                (not (member draw-part (rows)))
                                (hashtable-ref (ui-tree-states ui 'consumers)
                                               subject #f))])
                 (close-window! q)
                 (run! 10)
                 (let ([closed (member subject (rows))])
                   (run! 70)
                   (let ([gone (not (member subject (rows)))])
                     (close-window! m)
                     (steps 1)
                     (printf "  ~s\n"
                             (list (and working #t) (and column #t)
                                   (and quiet #t) (and kept #t)
                                   (and closed #t) gone))
                     (and working column quiet kept closed gone
                          (equal? (map monitor-node-type
                                       (list subject draw-part
                                             (list subject #f 'render)
                                             '(process . 3) 'gc 'wallpaper
                                             '(gc #f tick)))
                                  '("window" "handler" "frame" "process"
                                    "collector" "surface" "phase")))))))))))

;;; Flags: a late tick kept with what explains it.

;; Ticks by hand on a clock only pass! moves (ms), a period 16 ms; thunk's
;; value, the flags kept from a clean history.
(define profile-test-t (* 5000 1000000000))
(define (profile-test-pass! ms)
  (set! profile-test-t (+ profile-test-t (* ms 1000000))))
(define (profile-test-calm!)   ; a tick as it should be
  (with-profile-span 'step #f (profile-test-pass! 16)))
(define (profile-test-flags thunk)
  (fluid-let ([now-ns (lambda () profile-test-t)]
              [pacer-period (lambda () 16000000)])
    (profile-clear!)
    (profile-test-calm!)
    (thunk)
    (do ([i 0 (+ i 1)]) ((= i 3)) (profile-test-calm!))
    (profile-flags)))

(check "a late tick stays as a flag, with the ticks about it, what each \
        swapchain call held main for and when its frame went; the ticks in \
        time don't"
       (let* ([sent #f]
              [flags (profile-test-flags
                      (lambda ()
                        (profile-test-calm!)
                        (profile-test-calm!)
                        (with-profile-span 'step #f
                          (with-profile-span 'vsync-wait 'acquire
                            (profile-test-pass! 2))
                          (with-profile-span 'render #f (profile-test-pass! 1))
                          (set! sent profile-test-t)
                          (with-profile-span 'vsync-wait 'submit
                            (profile-test-pass! 30)))))]
              [f (car flags)]
              [lines (profile-flag-lines f)])
         (for-each (lambda (l) (printf "  ~a\n" l)) lines)
         (and (= (length flags) 1)
              (= (profile-flag-count) 1)
              (equal? (profile-flag-why f) '(submit 30000000))
              (= (profile-flag-ns f) 33000000)
              (= (profile-flag-acquire f) 2000000)
              (= (profile-flag-submit f) 30000000)
              (equal? (map cadr (profile-flag-beside f))
                      '(16000000 16000000 16000000 33000000 16000000 16000000
                        16000000))
              (equal? (caddr (list-ref (profile-flag-beside f) 3)) sent)
              (equal? (profile-flag-ticks-text f)
                      "16.0 16.0 16.0 [33.0] 16.0 16.0 16.0")
              (equal? (cadr lines)
                      "the screen held main 30.0 ms, taking the frame")
              (equal? (profile-flag-summary) "1 flag: 1 submit")
              (let-values ([(port get) (open-string-output-port)])
                (profile-flag-report port)
                (let* ([out (get)]
                       [want (format "1 flag: 1 submit\n\n~a\n"
                                     (string-join lines "\n"))]
                       [from (- (string-length out) (string-length want))])
                  (and (> from 0)
                       (string=? (substring out from (string-length out))
                                 want)))))))

(check "a flag's why is the biggest thing in the tick that could have made it \
        late: a call of the screen's, a sleep past its period, the collector \
        or someone's work, not the sleep that was only its tick's wait"
       (let* ([win (open-window "Slow" 'size '(120 . 80) 'pos '(600 . 400))]
              [why (lambda (thunk)
                     (let ([flags (profile-test-flags
                                   (lambda ()
                                     (with-profile-span 'step #f (thunk))))])
                       (and (= (length flags) 1)
                            (let ([w (profile-flag-why (car flags))])
                              (printf "  ~a\n" (profile-why-text w))
                              w))))]
              [acquire (why (lambda ()
                              (with-profile-span 'vsync-wait 'acquire
                                (profile-test-pass! 30))))]
              [unclaimed (why (lambda ()
                                (with-profile-span 'vsync-wait #f
                                  (profile-test-pass! 30))))]
              [asleep (why (lambda () (profile-test-pass! 40)))]
              [gc (why (lambda ()
                         (with-profile-span 'gc #f (profile-test-pass! 30))))]
              [work (why (lambda ()
                           (profile-test-pass! 15)   ; its tick's wait
                           (with-profile-span 'render #f
                             (with-profile-span (window-id win) 'draw
                               (profile-test-pass! 12)))))])
         (close-window! win)
         (and (equal? acquire '(acquire 30000000))
              (equal? unclaimed '(screen 30000000))
              (equal? asleep '(asleep 24000000))
              (equal? gc '(gc 30000000))
              (eq? (car work) 'work)
              (equal? (profile-why-text work) "Slow's draw took 12.0 ms"))))

(check "a flag outlives the ticks' ring and says how long the window had \
        been showing; the flags kept are the newest, the count all of them; \
        clearing the history clears them"
       (let* ([hidden? #t]
              [flags (fluid-let ([host-hidden? (lambda () hidden?)])
                       (profile-test-flags
                        (lambda ()
                          (set! hidden? #f)
                          (profile-test-pass! 2000)   ; shown for 2 s and more
                          (with-profile-span 'step #f
                            (with-profile-span 'vsync-wait 'submit
                              (profile-test-pass! 30))))))]
              [f (car flags)]
              [seq (profile-flag-seq f)]
              [gone (fluid-let ([now-ns (lambda () profile-test-t)]
                                [pacer-period (lambda () 16000000)])
                      (profile-test-pass! (* 1000 (+ 1 *profile-tick-seconds*)))
                      (profile-test-calm!)
                      (not (profile-tick-kept? seq)))]
              [still (equal? (car (profile-flags)) f)]
              [many (profile-test-flags
                     (lambda ()
                       (do ([i 0 (+ i 1)]) ((= i (+ profile-flags-kept 6)))
                         (with-profile-span 'step #f
                           (with-profile-span 'vsync-wait 'submit
                             (profile-test-pass! 30))))))]
              [count (profile-flag-count)]
              [summary (profile-flag-summary)])
         (profile-clear!)
         (printf "  shown for ~a, gone ~a, still ~a, ~a kept of ~a\n"
                 (profile-flag-shown-for f) gone still (length many) count)
         (and (= (profile-flag-shown-for f) (+ 2000000000 30000000))
              gone still
              (= (length many) profile-flags-kept)
              (= count (+ profile-flags-kept 6))
              (equal? summary "1030 flags, the last 1024: 1024 submit")
              (> (profile-flag-seq (car many))
                 (profile-flag-seq (cadr many)))
              (null? (profile-flags)))))

(check "a tick keeps what main itself ran, by its CPU clock"
       (let ([spent (lambda ()
                      (with-profile-span 'step #f
                        (let loop ([i 0]) (when (< i 3000000) (loop (+ i 1)))))
                      (profile-tick-ns (profile-newest-tick) 'cpu))])
         (spent)
         (> (spent) 0)))

(check "a flag says what the host said about then, the mouse's motion only \
        counted; what the tick drew on, its window and its memory, and how \
        the ticks about it went, in the report and in its log"
       (let* ([path (string-append out-dir "/flags.log")]
              [flags (begin
                       (when (file-exists? path) (delete-file path))
                       (profile-flag-log! path)
                       (profile-test-flags
                        (lambda ()
                          (profile-test-calm!)
                          (*host-event-seen* #x20E)   ; focus-gained
                          (profile-test-pass! 5)
                          (*host-event-seen* #x400)   ; motion: counted
                          (with-profile-span 'step #f
                            (with-profile-span 'vsync-wait 'acquire
                              (profile-test-pass! 30))))))]
              [more (begin
                      (profile-flag-log! #f)
                      (call-with-input-file path get-string-all))]
              [f (car flags)]
              [lines (profile-flag-lines f)]
              [has? (lambda (text s)
                      (let ([n (string-length text)])
                        (let loop ([i 0])
                          (and (<= (+ i n) (string-length s))
                               (or (string=? text (substring s i (+ i n)))
                                   (loop (+ i 1)))))))]
              [line? (lambda (text) (exists (lambda (l) (has? text l)) lines))])
         (for-each (lambda (l) (printf "  ~a\n" l)) lines)
         (delete-file path)
         (and (equal? (car (profile-flag-events f))
                      (cons 'focus-gained -35000000))
              (= 1 (length (profile-flag-events f)))
              (equal? (profile-flag-before-text f) "focus-gained, 35.0 ms ago")
              (line? "the host said: focus-gained -35.0 ms")
              (line? "next image: 0.0 0.0 [30.0] 0.0 0.0 0.0")
              (line? "host events: 0 0 [2] 0 0 0")
              (line? "memory: heap")
              (line? "records: ")
              (line? "the host window:")
              (has? "; the GPU" (cadr lines))
              (has? "=== a run" more)
              (has? "presenting by vsync, present modes offered" more)
              (line? "presenting by vsync")
              (has? "the host said: focus-gained" more))))

(check "main past its time in the wait for events: asleep if it ran little \
        of that, running if it ran most"
       (let* ([cpu 0]
              [why (lambda (ran-ms)
                     (fluid-let ([profile-thread-cpu (lambda () cpu)])
                       (let ([flags (profile-test-flags
                                     (lambda ()
                                       (set! cpu (+ cpu (* ran-ms 1000000)))
                                       (with-profile-span 'step #f
                                         (profile-test-pass! 40))))])
                         (profile-flag-why (car flags)))))])
         (and (eq? (car (why 0)) 'asleep)
              (eq? (car (why 30)) 'pump))))

