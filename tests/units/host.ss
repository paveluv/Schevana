;;; tests/units/host.ss — a host app's one window ((schevana kits host)):
;;; frameless, the whole of where windows go, its least size the screen's,
;;; and quitting when it closes; or, where the desktop draws no frames, in
;;; its style's frame, whose regions the desktop moves and resizes it by and
;;; whose actions are the OS window's; the host's look by the platform.

(for-each close-window! (windows))

(let* ([closed? #f]
       [win (open-window "Notes" 'size '(300 . 200) 'pos '(40 . 40)
                         'min-size '(240 . 160)
                         'close (lambda (w) (set! closed? #t)))]
       [keys *global-keys*])
  (fluid-let ([*screen-least* *screen-least*])
    (host-window! win)
    (let-values ([(cx cy cw ch) (content-rect win)]
                 [(dx dy dw dh) (desktop-rect)])
      (check (format "a host app's window is frameless and fills where \
                      windows go, its top its content's, and its least size \
                      the screen's ~s"
                     (list cx cy cw ch dx dy dw dh *screen-least*))
             (and (window-ref win 'frameless) (maximized? win)
                  (equal? (list cx cy cw ch) (list dx dy dw dh))
                  (equal? (call-with-values (lambda () (frame-insets win))
                            list)
                          '(0 0 0 0))
                  (null? (frame-regions win))
                  (eq? (window-region win (+ dx 10) (+ dy 2)) 'content)
                  (equal? *screen-least* '(240 . 160))))))
  (check "Ctrl+Q and Ctrl+W are bound to quit and to close it"
         (and (assoc '(ctrl #\q) *global-keys*)
              (assoc '(ctrl #\w) *global-keys*)))
  (set! *global-keys* keys)
  (close-window! win)
  (let ([quit? (not *running*)])
    (set! *running* #t)
    (check "closing it runs its own close, then quits"
           (and closed? quit?))))

(check (format "the host's look by the platform: ~s" (host-look))
       (eq? (host-look)
            (cond [(platform-mac?) 'mac]
                  [(platform-windows?) 'windows]
                  [else 'adwaita])))

;; Its own frame (GNOME under Wayland): the regions the desktop takes,
;; edges and corners first (none while maximized), the frame's buttons the
;; app's, the rest of the title bar a move; core0 finds what is at a point
;; by them, in window units.
(set-style! 'adwaita)
(let* ([win (open-window "Own" 'size '(300 . 200) 'pos '(0 . 0))]
       [regions (host-hit-regions win #f)]
       [maximized (host-hit-regions win #t)])
  (let-values ([(l t r b) (frame-insets win)])
    (check (format "an own frame's regions: edges and corners resize, its \
                    buttons are the app's, the rest of its title bar moves \
                    it; maximized, no edges ~s" regions)
           (and (equal? (car regions)
                        (list 'resize-tl 0 0 host-corner host-corner))
                (= (length (filter (lambda (r) (memq (car r) resize-kinds))
                                   regions))
                   8)
                (assq 'normal regions)
                (equal? (car (last-pair regions))
                        (list 'move 0 0 (window-w win) t))
                (not (exists (lambda (r) (memq (car r) resize-kinds))
                             maximized))
                (equal? (car (last-pair maximized))
                        (car (last-pair regions)))))
    (fluid-let ([*screen-hit-regions* '()])
      (screen-hit-regions! regions)
      (steps 1)
      (let* ([button (assq 'normal regions)]
             [bx (+ (cadr button) 2)] [by (+ (caddr button) 2)]
             [kinds (list (core0-hit 1 1) (core0-hit 2 (quotient t 2))
                          (core0-hit 60 (quotient t 2)) (core0-hit bx by)
                          (core0-hit 60 (+ t 20)))])
        (screen-hit-regions! '())
        (steps 1)
        (check (format "core0 finds them at a point: a corner, an edge, the \
                        title bar, a button, the content ~s" kinds)
               (equal? kinds '(2 9 1 0 0))))))
  ;; its frame's actions are the OS window's: the window itself stays
  (window-set! win 'on-action host-act!)
  (window-action! win 'minimize)
  (window-action! win 'maximize)
  (check "an own frame's minimize and maximize act on the OS window, not \
          on the window in it"
         (eq? (window-state win) 'normal))
  (close-window! win))
(set-style! 'mac)
