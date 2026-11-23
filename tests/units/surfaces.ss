;;; tests/units/surfaces.ss — surfaces and strips.

;; Returns the status segments' strings as the top bar shows them.
(define (surfaces-test-shown) (filter string? (map cdr *status-shown*)))

;;; surfaces and strips

;; With no surface registered (no desktop layer), the world draws its
;; windows on black and maximizes them to the whole screen; a press or the
;; wheel where there is nothing goes nowhere, and a key goes to the window.
(let* ([ss *surfaces*] [strips *strips*] [keys 0]
       [w (open-window "Alone" 'size '(200 . 100) 'pos '(300 . 200)
                       'draw (lambda (win cw ch)
                               (fill-box 0 0 cw ch #x336699))
                       'key (lambda (win key mods) (set! keys (+ keys 1))))])
  (set! *surfaces* '())
  (set! *strips* '())
  (invalidate!)
  (steps 1)
  (let-values ([(cx cy cw ch) (content-rect w)])
    (let ([inside (canvas-pixel (+ cx 50) (+ cy 50))]
          [around (map (lambda (p) (canvas-pixel (car p) (cdr p)))
                       '((5 . 5) (640 . 790) (1270 . 400)))])
      (inject! '(mouse-move 20 400) '(mouse-down 20 400 left 1)
               '(mouse-up 20 400 left) '(wheel 0 1) '(key-down #\a ()))
      (steps 1)
      (maximize-window! w)
      (let ([whole (list (window-x w) (window-y w) (window-w w) (window-h w))]
            [hover *hover*])
        (set! *surfaces* ss)
        (set! *strips* strips)
        (close-window! w)
        (steps 1)
        (check (format "with no surface registered the windows are drawn on \
                        black (#x~x, ~s), maximize to the screen (~s), and \
                        input where nothing is goes nowhere (~s; keys \
                        to the window ~a)"
                       inside around whole hover keys)
               (and (= inside #xff336699)
                    (equal? around '(#xff000000 #xff000000 #xff000000))
                    (equal? whole (list 0 0 (screen-w) (screen-h)))
                    (not hover) (= keys 1)))))))

;; A surface of the test's own, with a strip on the left: it is drawn over
;; the windows and takes the presses and releases on it, and maximized
;; windows go beside it.
(let* ([pressed '()]
       [w (open-window "Beside" 'size '(200 . 100) 'pos '(300 . 200))])
  (define-surface dock 15
    'draw (lambda () (fill-box 0 0 64 (screen-h) #xcc3300))
    'box (lambda () (values 0 0 64 (screen-h)))
    'at (lambda (x y) (and (< x 64) 'dock))
    'mouse (lambda (kind what x y button clicks)
             (set! pressed (cons (list kind what button) pressed))))
  (define-strip dock 'left (lambda () 64))
  (maximize-window! w)
  (steps 1)
  (let-values ([(dx dy dw dh) (desktop-rect)])
    (let ([at (list (window-x w) (window-y w) (window-w w) (window-h w))]
          [px (canvas-pixel 30 400)])
      (inject! '(mouse-move 30 400) '(mouse-down 30 400 left 1)
               '(mouse-up 30 400 left))
      (steps 1)
      (let ([hover *hover*])
        (set! *surfaces* (remp (lambda (s) (eq? (surface-name s) 'dock))
                               *surfaces*))
        (set! *strips* (remp (lambda (s) (eq? (car s) 'dock)) *strips*))
        (wm-screen-resized!)
        (let ([back (window-x w)])
          (close-window! w)
          (steps 1)
          (check (format "a surface with a strip on the left: maximized \
                          windows beside it ~s, drawn over them (#x~x), \
                          its presses ~s, hovered ~s; gone, they fill the \
                          left again (~a)" at px pressed hover back)
                 (and (equal? at (list 64 (topbar-height) (- (screen-w) 64)
                                       (- (screen-h) (topbar-height)
                                          (taskbar-height))))
                      (equal? (list dx dy dw dh) at)
                      (= px #xffcc3300)
                      (equal? pressed '((up dock left) (down dock left)
                                        (move dock #f)))
                      (equal? hover '(surface dock dock))
                      (= back 0))))))))

(check "the top bar's memory is the heap's and the process's, or the heap's \
        alone where the system doesn't say"
       (let* ([process (platform-process-bytes)]
              [heap (bytes-allocated)]
              [number (lambda (s)
                        (string->number
                         (cadr (string-split s #\space))))]
              [heap-only (fluid-let ([platform-process-bytes (lambda () #f)])
                           (status-memory))]
              [whole (fluid-let ([platform-process-bytes
                                  (lambda () 1073741824)])
                       (status-memory))])
         (and (or (not process)       ; no /proc here
                  (> process (* 1/2 heap)))
              (assq 'memory *status-segments*)
              (string-suffix? " · process 1024.0 MB" whole)
              (< (abs (- (number heap-only) (/ heap 1048576.0))) 20))))

(check "the top bar takes its numbers once a second, however many frames \
        are drawn between, and a segment added at once"
       ;; with the test's clock held, the bar's once-a-second timer waits,
       ;; so the frames drawn ask for nothing (except for a second already
       ;; due); then showing the bar asks once
       (let ([asked 0])
         (add-status-segment! 'asked
                              (lambda ()
                                (set! asked (+ asked 1))
                                (format "asked ~a" asked)))
         (test-clock-hold!)
         (test-finally
          (lambda ()
            (let ([added asked])
              (do ([i 0 (+ i 1)]) ((= i 5))
                (request-frame!)
                (steps 1))
              (let ([between (- asked added)])
                (status-show!)
                (steps 1)
                (let ([shown (surfaces-test-shown)] [last asked])
                  (and (= added 1) (<= between 1)
                       (member (format "asked ~a" last) shown)
                       (= last (+ added between 1)))))))
          (lambda ()
            (test-clock-release!)
            (remove-status-segment! 'asked)))))

;;; frames

;; A surface's frame is called at each frame, before the surface is drawn,
;; so what it finds changed shows in that frame. It is given t, the time
;; that frame shows.
(let ([seen '()])
  (define-surface frame-probe 90
    'draw (lambda () (set! seen (cons 'draw seen)))
    'frame (lambda (t) (set! seen (cons (and (number? t) 'frame) seen))))
  (steps 1)
  (set! seen '())
  (request-frame!)
  (steps 1)
  (set! *surfaces* (remp (lambda (s) (eq? (surface-name s) 'frame-probe))
                         *surfaces*))
  (check "a surface's frame comes before the frame is drawn, with t"
         (equal? seen '(draw frame))))

(check "a surface that gives no frame has one that does nothing"
       (let ([errors 0])
         (define-surface frameless 91 'draw void)
         (fluid-let ([report-error!
                      (lambda (who c) (set! errors (+ errors 1)))])
           (steps 2))
         (set! *surfaces* (remp (lambda (s) (eq? (surface-name s) 'frameless))
                                *surfaces*))
         (= errors 0)))

;; The bell's flash ends by a timer, and the status clock keeps a timer of
;; its own.
(set-theme! 'bell 'screen)   ; this sets a timer of its own, to save
(let ([before (length *timers*)])
  (bell)
  (check "a ring sets a timer that ends its flash"
         (and *bell* (= (length *timers*) (+ before 1))))
  (fluid-let ([now-ms (let ([t (+ (now-ms) 100)]) (lambda () t))])
    (run-timers!))
  (reset-theme!)
  (check "and when it's due, the flash is gone"
         (not *bell*)))
(check "the status clock has a timer of its own"
       (exists (lambda (t) (<= (- (vector-ref t 0) (now-ms)) 1000))
               *timers*))
