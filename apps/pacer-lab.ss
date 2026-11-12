;;; apps/pacer-lab.ss — the pacer lab's face (services/pacer-lab.ss): the
;;; switch, the period under way, and what the periods logged say of each
;;; of the pacer's choices, a row a value. It tunes the world, so it runs
;;; there, asking for nothing.

;; A value as the table shows it, the setting in effect marked.
(define (pacer-lab-value-text knob value)
  (if (equal? value (theme knob))
      (format "~a (setting)" value)
      (format "~a" value)))

(define (pacer-lab-number x digits)
  (if x (format "~,vf" digits x) "–"))

(define (pacer-lab-verdict-text v)
  (case v
    [(best) "fewest late"]
    [(tied) "within noise"]
    [(worse) "worse"]
    [else "too few periods"]))

(define (pacer-lab-cell e key)
  (case key
    [(knob) (symbol->string (pacer-lab-effect-knob e))]
    [(value) (pacer-lab-value-text (pacer-lab-effect-knob e)
                                   (pacer-lab-effect-value e))]
    [(periods) (number->string (pacer-lab-effect-periods e))]
    [(frames) (number->string (pacer-lab-effect-frames e))]
    [(rate) (if (pacer-lab-effect-error e)
                (format "~a ± ~a"
                        (pacer-lab-number (pacer-lab-effect-rate e) 1)
                        (pacer-lab-number (pacer-lab-effect-error e) 1))
                (pacer-lab-number (pacer-lab-effect-rate e) 1))]
    [(own) (number->string (pacer-lab-effect-own e))]
    [(theirs) (number->string (pacer-lab-effect-theirs e))]
    [(p50) (pacer-lab-number (pacer-lab-effect-p50 e) 1)]
    [(p99) (pacer-lab-number (pacer-lab-effect-p99 e) 1)]
    [else (pacer-lab-verdict-text (pacer-lab-effect-verdict e))]))

;; The period under way, a line.
(define (pacer-lab-now-text)
  (let ([n (pacer-lab-now)])
    (if n
        (format "This period: ~a · ~a:~2,'0d of ~a min · ~a frames, ~a late"
                (string-join (map (lambda (k) (format "~a ~a" (car k) (cdr k)))
                                  (plist-ref n 'knobs '()))
                             ", ")
                (quotient (plist-ref n 'seconds 0) 60)
                (modulo (plist-ref n 'seconds 0) 60)
                (quotient pacer-lab-period-ms 60000)
                (plist-ref n 'frames 0) (plist-ref n 'late 0))
        "Off: the pacer follows the settings")))

(define (pacer-lab-log-text)
  (let ([ps (pacer-lab-periods)])
    (format "~a periods, ~,1f hours, ~a frames judged · ~a"
            (length ps)
            (/ (apply + (map (lambda (p) (plist-ref p 'seconds 0)) ps))
               3600.)
            (apply + (map (lambda (p) (plist-ref p 'frames 0)) ps))
            *pacer-lab-log-path*)))

;; The effects, worked out again only when a period has been logged.
(define (pacer-lab-effects-of ui)
  (let ([n (length (pacer-lab-periods))])
    (if (equal? (ui-memo ui '(pacer-lab count) #f) n)
        (ui-memo ui '(pacer-lab effects) '())
        (let ([es (pacer-lab-effects)])
          (ui-memo! ui '(pacer-lab count) n)
          (ui-memo! ui '(pacer-lab effects) es)
          es))))

(define (draw-pacer-lab ui w h)
  (let* ([pad (ui-pad)] [lh (font-line-height 'ui)] [ch (ui-control-height)]
         [y (+ pad ch pad lh lh pad)])
    (ui-begin! ui)
    (fill-box 0 0 w h 'bg-1)
    (ui-toggle ui '(pacer-lab on) pad pad (- w pad pad) ch
               "Try the pacer's choices at random, ten minutes each"
               (pacer-lab-on?) (lambda (on?) (pacer-lab-on! on?)))
    (ui-draw-label pad (+ pad ch pad) (- w pad pad) lh '()
                   (pacer-lab-now-text))
    (ui-draw-label pad (+ pad ch pad lh) (- w pad pad) lh '(dim)
                   (pacer-lab-log-text))
    (ui-table ui '(pacer-lab effects) pad y (- w pad pad) (- h y pad)
              (let ([w (ui-table-room (- w pad pad))])
                `((knob "Choice" ,(* w 0.17))
                  (value "Value" ,(* w 0.11))
                  (periods "Periods" ,(* w 0.07) right)
                  (frames "Frames" ,(* w 0.09) right)
                  (rate "Late /10k" ,(* w 0.12) right
                        "Late frames, the pacer's and the compositor's, per \
                         10,000 judged, ± a standard error from the \
                         periods' spread")
                  (own "Own" ,(* w 0.06) right)
                  (theirs "Theirs" ,(* w 0.07) right)
                  (p50 "p50 ms" ,(* w 0.07) right "Tick to screen, median")
                  (p99 "p99 ms" ,(* w 0.07) right "Tick to screen, 99th")
                  (verdict "Verdict" ,(* w 0.17))))
              (pacer-lab-effects-of ui) #f void
              (lambda (e key cx cy cw ch flags)
                (ui-draw-cell cx cy cw ch flags (pacer-lab-cell e key))))
    (ui-end! ui w h)))

(define-app (pacer-lab) "Pacer Lab"
  (let ([ui (make-ui)] [open? #t])
    ;; the period's progress, a second at a time, until the window closes
    (define (next-second! win)
      (after 1000 (lambda ()
                    (when open?
                      (invalidate! win)
                      (next-second! win)))))
    (apply open-window "Pacer Lab"
      'size '(900 . 520)
      'min-size '(480 . 300)
      'state ui
      'open next-second!
      'close (lambda (win) (set! open? #f))
      'draw (lambda (win w h) (draw-pacer-lab ui w h))
      (ui-handlers ui))))
