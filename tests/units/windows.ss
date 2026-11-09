;;; tests/units/windows.ss — the window manager's stacking: a window opened
;;; above its owner stays there, and the two move as one; the frames a
;;; window asks for.

(for-each close-window! (windows))

;; Open windows, front first, by title.
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

;; A window's 'frame comes once for each time it asks, at the next tick,
;; with when that frame shows; never unasked, nor while it's minimized.
(let* ([frames '()]
       [again? #f]
       [win (windows-open "Frames"
                          'frame (lambda (w t)
                                   (set! frames (cons t frames))
                                   (when again? (window-frame-soon! w))))])
  (steps 2)
  (check "a window that didn't ask gets no 'frame"
         (null? frames))
  (let ([before (now-ns)] [asked (window-ref win 'wm-asked 0)])
    (window-frame-soon! win)
    (check "asking for a frame doesn't draw the window again"
           (= asked (window-ref win 'wm-asked 0)))
    (steps 2)
    (check "one that asked gets one, its t when the frame shows (unpaced, \
            the tick's now, to the ms)"
           (and (= (length frames) 1)
                (<= (- before 1000000) (car frames) (now-ns)))))
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
