;;; tests/units/pacer-lab.ss — the pacer lab: its tick-to-screen histogram,
;;; what it makes of the periods logged, a run (its log at a scratch path,
;;; its periods ended by hand), and its window.

(check "tick to screen goes in bins of a tenth of a ms; the median and the \
        99th come from them"
       (let ([h (pacer-lab-hist)])
         (do ([i 0 (+ i 1)]) ((= i 99)) (pacer-lab-hist-add! h 5.0))
         (pacer-lab-hist-add! h 30.0)
         (and (= (pacer-lab-quantile h 0.5) 5.05)
              (= (pacer-lab-quantile h 0.99) 5.05)
              (= (pacer-lab-quantile h 1.0) 30.05)
              (not (pacer-lab-quantile (pacer-lab-hist) 0.5)))))

;; A period as the log has it: margin-start at start, 10,000 frames, late
;; ones as the pacer's own, a 99th at p99.
(define (pacer-lab-test-period start late p99)
  (list 'start 0 'seconds 600 'refresh-ns 16666667
        'knobs (list (cons 'pacer-margin-start start))
        'frames 10000 'own late 'theirs 0 'p50 5.0 'p90 8.0 'p99 p99))

(let* ([ps (list (pacer-lab-test-period 0 0 10.0)
                 (pacer-lab-test-period 0 2 12.0)
                 (pacer-lab-test-period 1/8 3 10.0)
                 (pacer-lab-test-period 1/8 1 10.0)
                 (pacer-lab-test-period 1/4 40 20.0)
                 (pacer-lab-test-period 1/4 50 20.0)
                 (pacer-lab-test-period 1/16 9 20.0))]
       [es (filter (lambda (e)
                     (eq? (pacer-lab-effect-knob e) 'pacer-margin-start))
                   (pacer-lab-effects ps))]
       [of (lambda (v) (find (lambda (e) (equal? (pacer-lab-effect-value e) v))
                             es))])
  (check "a value's effect: its periods' late frames per 10,000, with an \
          error from their spread, and its tick to screen weighted by \
          frames"
         (let ([e (of 0)])
           (and (= (pacer-lab-effect-periods e) 2)
                (= (pacer-lab-effect-frames e) 20000)
                (= (pacer-lab-effect-rate e) 1.)
                ;; late 0 and 2, 1 off each: sqrt(2/1 · 2) / 20000
                (< (abs (- (pacer-lab-effect-error e) 1.)) 1e-9)
                (= (pacer-lab-effect-p99 e) 11.))))
  (check "the fewest late is best, one within two errors of it tied, the \
          rest worse, and a value of one period too few to tell"
         (and (eq? (pacer-lab-effect-verdict (of 0)) 'best)
              (eq? (pacer-lab-effect-verdict (of 1/8)) 'tied)
              (eq? (pacer-lab-effect-verdict (of 1/4)) 'worse)
              (not (pacer-lab-effect-verdict (of 1/16))))))

;; The log's forms, as read back.
(define (pacer-lab-test-log)
  (call-with-input-file *pacer-lab-log-path*
    (lambda (p)
      (let loop ([xs '()])
        (let ([x (read p)])
          (if (eof-object? x) (reverse xs) (loop (cons x xs))))))))

(fluid-let ([*pacer-lab-log-path* (string-append out-dir "/pacer-lab.ss")])
  (when (file-exists? *pacer-lab-log-path*)
    (delete-file *pacer-lab-log-path*))
  (let ([overrides (theme-overrides)] [counts *pacer-counts*])
    (pacer-lab-on! #t)
    (check "on, a trial of a value per knob holds the pacer, not the \
            settings, and the log says so with the platform's row"
           (and (pacer-lab-on?)
                (for-all (lambda (k)
                           (member (pacer-knob (car k)) (cdr k)))
                         pacer-lab-knobs)
                (equal? *pacer-trial* (plist-ref (pacer-lab-now) 'knobs #f))
                (equal? (theme-overrides) overrides)
                (not *pacer-margin*)
                (let ([x (car (pacer-lab-test-log))])
                  (and (eq? (car x) 'pacer-lab-on) (string? (caddr x))))))
    ;; a period's frames, faked: 500 judged, 3 late of the pacer's own
    (set! *pacer-counts* (fxvector 0 0 0))
    (pacer-lab-begin!)
    (set! *pacer-counts* (fxvector 500 3 1))
    (let ([before (length (pacer-lab-periods))]
          [trial *pacer-trial*])
      (fluid-let ([pacer-lab-period-ms 0]) (pacer-lab-second!))
      (check "a period long enough is logged, with its counts and trial, and \
              the next one begins"
             (let ([p (car (pacer-lab-periods))])
               (and (= (length (pacer-lab-periods)) (+ before 1))
                    (= (plist-ref p 'frames 0) 500)
                    (= (plist-ref p 'own 0) 3)
                    (= (plist-ref p 'theirs 0) 1)
                    (equal? (plist-ref p 'knobs #f) trial)
                    (pacer-lab-trial-knobs *pacer-lab-trial*)
                    (pacer-lab-period?
                     (find (lambda (x) (eq? (car x) 'pacer-lab-period))
                           (pacer-lab-test-log)))))))
    (pacer-lab-on! #f)
    (check "off, the settings rule the pacer again, and the log says so"
           (and (not (pacer-lab-on?))
                (null? *pacer-trial*)
                (not (pacer-lab-now))
                (eq? (car (list-ref (pacer-lab-test-log)
                                    (- (length (pacer-lab-test-log)) 1)))
                     'pacer-lab-off)))
    (let ([n (length (pacer-lab-periods))])
      ;; a line cut short, as a crash leaves it
      (call-with-port (open-file-output-port
                       *pacer-lab-log-path*
                       (file-options no-fail no-truncate append)
                       (buffer-mode block) (native-transcoder))
        (lambda (p) (display "\n(pacer-lab-period start 1" p)))
      (pacer-lab-log-load!)
      (check "the log read back: its periods, off as it last said, and a \
              line cut short ignored"
             (and (= (length (pacer-lab-periods)) n)
                  (not (pacer-lab-on?)))))
    (pacer-lab-on! #t)
    (pacer-lab-on! #f)
    (pacer-lab-log! '(pacer-lab-on 0 "elsewhere"))
    (pacer-lab-log-load!)
    (check "read back with on last, it goes on: a run restarted"
           (and (pacer-lab-on?) (pair? *pacer-trial*)))
    (pacer-lab-on! #f)
    (set! *pacer-counts* counts)))

(let ([w (pacer-lab)])
  (invalidate! w)
  (steps 3)
  (check "its window draws the switch and the table"
         (and (not (window-error w))
              (ui-find (window-ref w 'state) '(pacer-lab on))))
  (close-window! w))
