;;; tests/units/desktop.ss — the desktop's own behavior (desktop/): the
;;; launcher that F1 opens, as a menu or as the app grid, the desktop's
;;; right-click menu, F11, the app's icon, a taskbar button's window menu,
;;; the desktop entry, and the apps' icons in the launcher and the taskbar.

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

;; The desktop draws its wallpaper by name at "/": a define there, as a
;; REPL makes it, shows on the next frame.
(check "a draw-wallpaper defined at \"/\" is what the desktop draws"
       (let ([plain (eval 'draw-wallpaper world-env)])
         (for-each close-window! (windows))
         (eval '(define (draw-wallpaper w h) (fill-box 0 0 w h #x336699))
               world-env)
         (invalidate!)
         (steps 1)
         (let ([shown (pixel-at (screen-picture) (quotient *canvas-pw* 2)
                                (quotient *canvas-ph* 2))])
           (eval `(define draw-wallpaper ',plain) world-env)
           (invalidate!)
           (steps 1)
           (= shown (color->pixel #x336699)))))

;;; The app grid: the launcher of a style whose launcher-form is grid.

;; Presses the left button at (x, y) and lets it go.
(define (desktop-test-click! x y)
  (let ([x (exact (round x))] [y (exact (round y))])
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
             `(mouse-up ,x ,y left))
    (steps 1)))

;; The center of the area of what in areas.
(define (desktop-test-center what areas)
  (let ([a (assoc what areas)])
    (values (+ (cadr a) (/ (cadddr a) 2))
            (+ (caddr a) (/ (car (cddddr a)) 2)))))

;; The grid's areas as the pointer finds them.
(define (desktop-test-grid-areas)
  (app-grid-areas (length (app-grid-entries)) *app-grid-page*))

;; A grid of two entries a page, side by side, with a dot for each page:
;; places that no font or screen moves.
(define (desktop-test-grid-pages n page)
  (let ([pages (quotient (+ n 1) 2)])
    (append (list (list 'search 100 60 300 30))
            (if (> pages 1)
                (map (lambda (k) (list (cons 'page k) (+ 100 (* k 20)) 600
                                       20 20))
                     (iota pages))
                '())
            (map (lambda (j) (list (+ (* page 2) j) (+ 100 (* j 120)) 200
                                   100 100))
                 (iota (max 0 (min 2 (- n (* page 2)))))))))

;; Runs thunk in a style whose launcher is the grid, laid out by
;; desktop-test-grid-pages, and closes the grid after it.
(define (desktop-test-grid thunk)
  (with-test-styles
   (lambda ()
     (define-style test-grid "Test"
       'launcher-form 'grid
       'app-grid-areas 'desktop-test-grid-pages)
     (set-style! 'test-grid)
     (steps 1)
     (test-finally thunk (lambda () (close-app-grid!) (steps 1))))))

(check "where the style's launcher is the grid, F1 opens the app grid, not \
        a menu, with every app in the order of its title; F1 again closes \
        it, and in another style F1 opens the menu"
       (and (desktop-test-grid
             (lambda ()
               (test-press! 'f1)
               (steps 1)
               (let ([form (launcher-open?)] [menu? (test-menu-open?)]
                     [shown (map car (app-grid-entries))])
                 (test-press! 'f1)
                 (steps 1)
                 (and (eq? form 'grid) (not menu?)
                      (equal? shown (sort string<? (map app-title *apps*)))
                      (not (launcher-open?))))))
            (begin
              (test-press! 'f1)
              (steps 1)
              (let ([form (launcher-open?)])
                (close-menu!)
                (steps 1)
                (eq? form 'menu)))))

(check "typing narrows the grid to the apps whose titles hold the text, \
        finds the desktop's actions too, and Return opens the first entry \
        it shows, closing the grid"
       (desktop-test-grid
        (lambda ()
          (toggle-launcher!)
          (test-type! "quit")
          (steps 1)
          (let ([quit (map car (app-grid-entries))]
                [app? (cadr (car (app-grid-entries)))])
            (for-each (lambda (k) (test-press! 'backspace)) (iota 4))
            (test-type! "clock")
            (steps 1)
            (let ([clock (map car (app-grid-entries))])
              (test-press! 'return)
              (steps 2)
              (let ([c (find-window 'clock)])
                (when c (close-window! c))
                (and (member "Quit Schevana" quit)
                     (for-all (lambda (t) (string-contains-ci? t "quit")) quit)
                     (not app?)
                     (equal? (car clock) "Clock")
                     c (not (launcher-open?)) #t)))))))

(check "a click on an entry opens it, and a click where the grid shows \
        nothing, or Escape, closes the grid"
       (desktop-test-grid
        (lambda ()
          (toggle-launcher!)
          (test-type! "clock")
          (steps 1)
          (let-values ([(x y) (desktop-test-center
                               0 (desktop-test-grid-areas))])
            (desktop-test-click! x y))
          (let ([c (find-window 'clock)] [closed? (not (launcher-open?))])
            (when c (close-window! c))
            (toggle-launcher!)
            (steps 1)
            (desktop-test-click! 50 400)
            (let ([empty-closes? (not (launcher-open?))])
              (toggle-launcher!)
              (steps 1)
              (test-press! 'escape)
              (steps 1)
              (and c closed? empty-closes? (not (launcher-open?)) #t))))))

(check "the grid's pages: a click on a page's dot turns to it, Page Down \
        and Page Up turn one page, the arrows choose across pages \
        sideways but not up and down, and a press on a window in the \
        taskbar closes the grid"
       (desktop-test-grid
        (lambda ()
          (define (key! k) (test-press! k) (steps 1))
          (define (now) (list *app-grid-sel* *app-grid-page*))
          (let ([w (open-window "Under" 'size '(200 . 100) 'pos '(600 . 300))]
                [seen '()])
            (define (see!) (set! seen (cons (now) seen)))
            (toggle-launcher!)
            (steps 1)
            (let-values ([(x y) (desktop-test-center
                                 '(page . 1) (desktop-test-grid-areas))])
              (desktop-test-click! x y))
            (see!)
            (key! 'page-up)
            (see!)
            (key! 'page-down)
            (see!)
            (key! 'page-up)
            (key! 'right)   ; the page's first
            (see!)
            (key! 'right)
            (key! 'right)   ; the next page's first
            (see!)
            (key! 'down)    ; a row further on is another page
            (see!)
            (key! 'left)
            (see!)
            (let-values ([(x y) (desktop-test-center w (placed-taskbar-areas))])
              (desktop-test-click! x y))
            (let ([closed? (not (launcher-open?))])
              (close-window! w)
              (printf "  ~s\n" (reverse seen))
              (and (equal? (reverse seen)
                           '((#f 1) (#f 0) (#f 1) (0 0) (2 1) (2 1) (1 0)))
                   closed?))))))

;;; ------------------------------------------------------------------
;;; the apps' icons in the launcher and the taskbar

(define desktop-icon-seen '())
(define-app (desktop-iconed) "Iconed"
  'icon (lambda (x y s flags)
          (set! desktop-icon-seen (cons (list x y s flags) desktop-icon-seen)))
  (open-window "Iconed" 'size '(200 . 100) 'pos '(200 . 200)))

(check "the launcher's menu lists every app with its icon, which draws the \
        app's own"
       (let* ([es (filter pair? (launcher-items #f))]
              [e (find (lambda (e) (equal? (car e) "Iconed")) es)])
         (set! desktop-icon-seen '())
         ((menu-entry-icon e) 1 2 20 '())
         (and (= (length (filter menu-entry-icon es)) (length *apps*))
              (equal? desktop-icon-seen '((1 2 20 ()))))))

;; A window's taskbar button draws its icon 9 in, centered on the bar, at
;; the size of a line of text, dim while the window is minimized (when its
;; title bar, which may show the icon too, isn't drawn).
(let* ([win (desktop-iconed)]
       [drawn (lambda ()
                (set! desktop-icon-seen '())
                (invalidate!)
                (steps 1)
                desktop-icon-seen)])
  (steps 1)
  (let* ([a (cdr (assq win (placed-taskbar-areas)))]
         [s (taskbar-icon-size)]
         [at (lambda (flags)
               (list (+ (car a) 9) (+ (cadr a) (/ (- (cadddr a) s) 2)) s
                     flags))]
         [shown (drawn)])
    (minimize-window! win)
    (let ([minimized (drawn)])
      (close-window! win)
      (check "a taskbar button draws its window's icon, dim while the window \
              is minimized"
             (and (member (at '()) shown)
                  (equal? minimized (list (at '(dim)))))))))
(set! *apps* (remp (lambda (a) (eq? (app-name a) 'desktop-iconed)) *apps*))
