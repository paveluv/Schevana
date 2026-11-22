;;; tests/units/desktop.ss — the desktop's own behavior (desktop/): the
;;; launcher that F1 opens, the desktop's right-click menu, F11, the app's
;;; icon, a taskbar button's window menu, and the desktop entry.

;; Life, whose window the launcher opens.
(test-demos! 'life)

(check "F1 opens the launcher; typing narrows it, and Return starts the \
        app it leaves"
       (begin
         (test-press! 'f1)
         (steps 1)
         (let ([open? (launcher-open?)])
           (test-type! "lif")
           (steps 1)
           (test-press! 'return)
           (steps 2)
           (let ([life (find-window 'life)])
             (when life (close-window! life))
             (and open? life (not (launcher-open?)) #t)))))

;; Right-clicks the desktop at (x, y) and chooses the menu's entry named
;; title.
(define (desktop-test-launch! x y title)
  (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1)
           `(mouse-up ,x ,y right))
  (steps 2)
  (when (launcher-open?)
    (menu-activate!
     (list-index (lambda (e) (and (pair? e) (string=? (car e) title)))
                 (menu-entries *menu*)))
    (steps 2)))

(check "an app picked from the desktop's right-click menu opens where the \
        click was, and near the screen's edge stays on it, above the \
        taskbar"
       (begin
         (desktop-test-launch! 700 400 "Clock")
         (let* ([c (find-window 'clock)]
                [there (and c (= (window-x c) 700) (= (window-y c) 400))])
           (when c (close-window! c))
           (desktop-test-launch! (- (screen-w) 30) (- (screen-h) 60) "Clock")
           (let* ([c (find-window 'clock)]
                  [inside (and c
                               (= (+ (window-x c) (window-w c)) (screen-w))
                               (= (+ (window-y c) (window-h c))
                                  (- (screen-h) (taskbar-height))))])
             (when c (close-window! c))
             (and there inside)))))

(check "F11 switches to full screen and back; the app's icon draws"
       (begin
         (test-press! 'f11)
         (steps 1)
         (let ([full (fullscreen?)])
           (test-press! 'f11)
           (steps 1)
           (and full (not (fullscreen?))
                (bytevector?
                 (drawing->bytes 64 64 1 (lambda () (draw-app-icon 64))))))))

(check "a window minimized from its taskbar button's menu leaves the focus \
        where it was"
       (let* ([a (open-window "Aaa" 'size '(260 . 120) 'pos '(100 . 100))]
              [b (open-window "Bbb" 'size '(260 . 120) 'pos '(500 . 100))])
         (steps 2)
         (let* ([it (cdr (assq a (placed-taskbar-areas)))]
                [x (exact (round (+ (car it) (/ (caddr it) 2))))]
                [y (- (screen-h) (quotient (taskbar-height) 2))])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1)
                    `(mouse-up ,x ,y right))
           (steps 2)
           (test-press! 'down)   ; from Bind, to Maximize, to Minimize
           (test-press! 'down)
           (steps 1)
           (test-press! 'return)
           (steps 2)
           (let ([ok (and (not (visible? a)) (eq? *focus* b))])
             (for-each close-window! (list a b))
             (steps 1)
             ok))))

;; Install into a scratch folder: XDG_DATA_HOME points into the output
;; folder.
(putenv "XDG_DATA_HOME" (string-append out-dir "/xdg"))
(check "the desktop entry names the window's app id and the icon, and \
        uninstalling removes its files"
       (let* ([files (install-desktop-entry!)]
              [text (call-with-input-file (car files) get-string-all)]
              [ok (and (member (string-append "StartupWMClass=" core0-app-id)
                               (string-split text #\newline))
                       (string-suffix?
                        (string-append "/" core0-app-id ".desktop")
                        (car files))
                       (string-contains-ci? text "Icon=schevana")
                       (file-exists? (cadr files)))])
         (uninstall-desktop-entry!)
         (and ok (not (exists file-exists? files)))))
