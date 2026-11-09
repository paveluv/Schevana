;;; tests/units/clock.ss — Clock: its face moves on by a timer at each
;;; second, and stops with its window.

(let* ([before (length *timers*)]
       [win (clock)]
       [handlers (window-handlers win)])
  (check "Clock has no tick: a timer for the next second draws it again"
         (and (not (hashtable-contains? handlers 'tick))
              (= (length *timers*) (+ before 1))
              (<= (- (vector-ref (car *timers*) 0) (now-ms)) 1000)))
  (let ([asked (window-ref win 'wm-asked 0)])
    (fluid-let ([now-ms (let ([t (+ (now-ms) 1000)]) (lambda () t))])
      (run-timers!))
    (check "at the second its face is drawn again, and the next one is set"
           (and (> (window-ref win 'wm-asked 0) asked)
                (= (length *timers*) (+ before 1)))))
  (close-window! win)
  (fluid-let ([now-ms (let ([t (+ (now-ms) 2000)]) (lambda () t))])
    (run-timers!))
  (check "once its window is closed, no timer is set again"
         (= (length *timers*) before)))
