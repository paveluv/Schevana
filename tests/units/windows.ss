;;; tests/units/windows.ss — the window manager's stacking: a window opened
;;; above its owner stays there, and the two move as one.

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
