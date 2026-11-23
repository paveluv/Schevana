;;; tests/units/windows.ss — the window manager's stacking (a window opened
;;; above its owner stays there, and the two move as one), the frames a
;;; window asks for, and the apps' icons as the registry holds them.

(for-each close-window! (windows))

;; The titles of the visible windows, front first.
(define (windows-titles)
  (map window-title (filter visible? (windows))))

(define (windows-open title . opts)
  (apply open-window title 'size '(200 . 100) 'pos '(100 . 100)
         'app 'windows-test opts))

(let* ([owner (windows-open "Owner")]
       [closed '()]
       [above (windows-open "Above" 'above owner
                            'close (lambda (w)
                                     (set! closed (cons "Above" closed))))]
       [other (windows-open "Other")])
  (check "a window opened above another is its owner's"
         (and (eq? (window-owner above) owner)
              (equal? (window-owned owner) (list above))
              (eq? (window-root above) owner)
              (not (window-owner owner))))
  (focus-window! owner)
  (check "its owner takes the keyboard, and it stays above the owner"
         (and (eq? (focused-window) owner)
              (equal? (windows-titles) '("Above" "Owner" "Other"))))
  (focus-window! other)
  (focus-window! above)
  (check "focused itself, it takes the keyboard, and its owner stays below it"
         (and (eq? (focused-window) above)
              (equal? (windows-titles) '("Above" "Other" "Owner"))))
  (focus-window! owner)
  (depth-window! owner)
  (check "sent behind, the owner takes it along, still above it"
         (equal? (windows-titles) '("Other" "Above" "Owner")))
  (minimize-window! owner)
  (check "minimized with its owner"
         (and (not (visible? owner)) (not (visible? above))))
  (focus-window! owner)
  (check "and brought back with it, above it"
         (and (visible? owner) (visible? above)
              (equal? (list-head (windows-titles) 2) '("Above" "Owner"))))
  (check "found by its app's name, the owner comes first"
         (eq? (find-window (window-app owner)) owner))
  (close-window! owner)
  (check "closed with its owner, its close handler run"
         (and (not (memq above (windows))) (equal? closed '("Above"))))
  (close-window! other))

(let* ([owner (windows-open "Owner")]
       [first (windows-open "First" 'above owner)]
       [second (windows-open "Second" 'above owner)]
       [nested (windows-open "Nested" 'above first)])
  (focus-window! owner)
  (check "several above one owner keep their order, and one above them above \
          its own"
         (equal? (windows-titles) '("Second" "Nested" "First" "Owner")))
  (close-window! owner)
  (check "and all go with the owner"
         (null? (windows))))

;; A window's 'frame is called once for each time it asks, at the next
;; tick, with the time that frame shows. It is never called unasked, nor
;; while the window is minimized (it waits until the window is seen again).
(let* ([frames '()]
       [again? #f]
       [win (windows-open "Frames"
                          'frame (lambda (w t)
                                   (set! frames (cons t frames))
                                   (when again? (window-frame-soon! w))))])
  (steps 2)
  (check "a window that didn't ask gets no 'frame"
         (null? frames))
  (let ([asked (window-ref win 'wm-asked 0)])
    (window-frame-soon! win)
    (check "asking for a frame doesn't draw the window again"
           (= asked (window-ref win 'wm-asked 0)))
    (steps 1)
    (check "one that asked gets one at the next tick, its t when that \
            tick's frame shows, the pacer's, not before the tick"
           (and (= (length frames) 1)
                (= (car frames) (pacer-frame-ns))
                (>= (car frames) *pacer-began*)))
    (steps 1)
    (check "and no more"
           (= (length frames) 1)))
  (set! again? #t)
  (window-frame-soon! win)
  (steps 3)
  (check "asking again from its 'frame gets the next tick's too"
         (= (length frames) 4))
  (set! again? #f)
  (steps 2)
  (set! frames '())
  (window-frame-soon! win)
  (minimize-window! win)
  (steps 2)
  (let ([while-minimized (length frames)])
    (focus-window! win)
    (steps 1)
    (check "a minimized window's frame waits until it's seen again"
           (and (= while-minimized 0) (= (length frames) 1))))
  (close-window! win))

;; A window that rides frames (asking for the next one from each 'frame),
;; whose draw raises once: its frames wait while the error shows, and go on
;; once a press clears the error.
(let* ([frames 0]
       [raise? #f]
       [win (windows-open "Rides"
                          'frame (lambda (w t)
                                   (set! frames (+ frames 1))
                                   (window-frame-soon! w))
                          'draw (lambda (w width height)
                                  (when raise?
                                    (set! raise? #f)
                                    (error 'windows-test
                                           "a draw that raises"))))]
       [x (+ (window-x win) 100)]
       [y (+ (window-y win) (window-h win) -20)])
  (window-frame-soon! win)
  (steps 2)
  (set! raise? #t)
  (invalidate! win)
  (steps 2)
  (let ([crashed (window-error win)] [at frames])
    (steps 3)
    (let ([while-crashed (- frames at)] [content (window-region win x y)])
      (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
               `(mouse-up ,x ,y left))
      (steps 3)
      (check "a window that rides frames waits while its draw's error shows, \
              and rides on once a press clears it"
             (and crashed (eq? content 'content) (= while-crashed 0)
                  (not (window-error win)) (>= (- frames at) 2)))))
  (close-window! win))

(check "a closed window drawn again asks for no frame: a timer it left \
        behind draws nothing"
       (let ([w (windows-open "Gone")])
         (close-window! w)
         (steps 1)
         (fluid-let ([*dirty* #f])
           (invalidate! w)
           (not *dirty*))))

(check "a minimized window drawn again asks for no frame; brought back, it's \
        drawn as it was asked"
       (let ([w (windows-open "Hidden")])
         (minimize-window! w)
         (steps 1)
         (let ([asked (window-ref w 'wm-asked 0)])
           (fluid-let ([*dirty* #f])
             (invalidate! w)
             (let ([quiet (not *dirty*)])
               (focus-window! w)
               (close-window! w)
               (and quiet (> (window-ref w 'wm-asked 0) asked)))))))

;;; Frames: whenever something asks for a frame, one is drawn; when nothing
;;; does, none is. The test's clock is held, so the top bar's update each
;;; second, which asks for a frame of its own, comes only when the test
;;; says so.

(for-each close-window! (windows))
(set! *toasts* '())
(steps 2)

;; Whether one step drew a frame.
(define (windows-step-drew?)
  (let ([n *frames-drawn*])
    (test-step!)
    (> *frames-drawn* n)))

;; Counts win's draws from now on, and returns a thunk that gives the
;; count.
(define (windows-count-draws! win)
  (let ([n 0]
        [draw (hashtable-ref (window-handlers win) 'draw
                             (lambda args (void)))])
    (window-on! win 'draw (lambda (w cw ch) (set! n (+ n 1)) (draw w cw ch)))
    (lambda () n)))

;; Input asks for a frame by itself, so what a handler that only changes
;; its state does is shown.
(let* ([seen #f] [state 0]
       [bump (lambda (win . args) (set! state (+ state 1)))]
       [w (windows-open "Quiet"
                        'draw (lambda (win cw ch) (set! seen state))
                        'key bump 'text bump 'wheel bump 'mouse-up bump)])
  (steps 2)
  (let-values ([(cx cy cw ch) (content-rect w)])
    (define (shown-after kind . evs)
      (apply inject! evs)
      (steps 2)
      (cons kind (eqv? seen state)))
    (let* ([x (+ cx 50)] [y (+ cy 50)]
           [key (shown-after 'key '(key-down #\a ()))]
           [text (shown-after 'text '(text "x"))]
           [wheel (shown-after 'wheel `(mouse-move ,x ,y) '(wheel 0 1))]
           ;; (no 'mouse-down handler)
           [up (shown-after 'mouse-up `(mouse-down ,x ,y left 1)
                            `(mouse-up ,x ,y left))]
           [shown (list key text wheel up)])
      (check (format "input reaches windows that never invalidate ~s" shown)
             (and (= state 4) (for-all cdr shown)))))
  (close-window! w))

;; A window that changes by itself says so, and the next frame shows it.
(let* ([count 0]
       [w (windows-open "Ticker"
                        'open window-frame-soon!
                        'frame (lambda (win at)
                                 (window-frame-soon! win)
                                 (set! count (+ count 1))
                                 (invalidate! win))
                        'draw (lambda (win cw ch)
                                (fill-box 0 0 cw ch (if (even? count)
                                                        #xff0000
                                                        #x0000ff))))])
  (let-values ([(x y cw ch) (content-rect w)])
    (define (red?)
      (= (canvas-pixel (+ x (quotient cw 2)) (+ y (quotient ch 2)))
         #xffff0000))
    (steps 2)
    (let* ([a (red?)] [b (begin (steps 1) (red?))]
           [c (begin (steps 1) (red?))])
      (check (format "a window that invalidates itself as it ticks shows \
                      each tick on the next frame ~s" (list a b c))
             (and (not (eq? a b)) (not (eq? b c))))))
  (close-window! w))

;; Steps for which nothing asked a frame draw nothing. A frame the top bar
;; asks for (each second) draws no window, and each window keeps what it
;; drew; (invalidate!) draws every window once; an expose draws a frame
;; again, since what the OS window showed may be gone.
(test-clock-hold!)
(let* ([a (windows-open "One")] [b (windows-open "Two" 'pos '(420 . 160))]
       [na (windows-count-draws! a)] [nb (windows-count-draws! b)])
  (steps 2)
  (let ([a0 (na)] [b0 (nb)])
    (let ([idle (let loop ([n 0] [drew 0])
                  (if (= n 20)
                      drew
                      (loop (+ n 1) (if (windows-step-drew?) (+ drew 1)
                                        drew))))])
      (status-show!)   ; as the clock does each second
      (let ([bar (windows-step-drew?)])
        (check (format "idle steps draw nothing (~a of 20 drew); a frame \
                        the top bar asks for draws no window" idle)
               (and (= idle 0) bar (= (na) a0) (= (nb) b0))))))
  (test-with-quiet-status
   (lambda ()
     (invalidate!)
     (steps 1)   ; draws the quiet top bar
     (let ([a0 (na)] [b0 (nb)])
       (invalidate!)
       (steps 1)
       (check "(invalidate!) draws every window again"
              (and (= (na) (+ a0 1)) (= (nb) (+ b0 1))))
       (let ([frames *frames-drawn*])
         (inject! '(expose))
         (steps 1)
         (check "an expose draws a frame"
                (= *frames-drawn* (+ frames 1)))))))
  (close-window! a)
  (close-window! b))
(test-clock-release!)

;;; ------------------------------------------------------------------
;;; apps' icons

;; Returns the icon the registry holds for the app named name, or #f.
(define (windows-app-icon name)
  (let ([a (find (lambda (a) (eq? (app-name a) name)) *apps*)])
    (and a (app-icon a))))

(define windows-icon-seen #f)
(define (windows-test-icon x y s flags) (set! windows-icon-seen 'first))
(define-app (windows-iconed) "Iconed" 'icon windows-test-icon
  (open-window "Iconed" 'size '(200 . 100)))
(define-app (windows-plain) "Plain"
  (open-window "Plain" 'size '(200 . 100)))

(check "an app's icon is the procedure define-app gives after 'icon, called \
        by name, so that a redefinition draws at the next call; an app that \
        gives none has none"
       (let ([icon (windows-app-icon 'windows-iconed)])
         (icon 0 0 24 '())
         (let ([first windows-icon-seen])
           (set! windows-test-icon
             (lambda (x y s flags)
               (set! windows-icon-seen (list x y s flags))))
           (icon 1 2 24 '(dim))
           (and (eq? first 'first)
                (equal? windows-icon-seen '(1 2 24 (dim)))
                (not (windows-app-icon 'windows-plain))))))

(set! *apps* (remp (lambda (a) (memq (app-name a)
                                     '(windows-iconed windows-plain)))
                   *apps*))
