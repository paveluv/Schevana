;;; (schevana desktop icons) — icons for minimized windows, while the setting
;;; minimize-to is icons (taskbar, the default, leaves them to the taskbar).
;;; An icon is a small window of the desktop's, with no frame, opened for
;;; each minimized window that no other window owns ('above), and closed
;;; once that window is back or gone. A left drag moves it; a double click
;;; opens its window, or a press of the middle button where the setting
;;; desk-icon-expand says middle (Medley's); the right button opens the
;;; icon's window menu (the open-window-menu part, given the icon). Closing
;;; the icon closes its window too, as Medley's does (CLOSEMAINWINDOW). The
;;; style sizes, places and draws an icon, as parts that are handed the
;;; window it stands for: desk-icon-size, desk-icon-place and draw-desk-icon.
;;; The settings and the parts are the window's style's, which its icon takes
;;; too ('window-style), where the window has a style of its own.
;;; An icon that was moved comes back where it was put, the next time its
;;; window is minimized (Medley's \NOTENEWICONPOSITION): the window keeps
;;; the place ('desk-icon-at).

(library (schevana desktop icons)
  (export
    desk-icon-size desk-icon-size* desk-icon-place desk-icon-place*
    draw-desk-icon draw-desk-icon* desk-icons-frame)
  (import (chezscheme)
          (only (schevana base) at-load define-hook library-layer)
          (only (schevana core) *focus* *mouse-x* *mouse-y* *windows*
                close-window! define-part define-surface desktop-rect
                draw-text fill-box focus-window! font-line-height
                in-window-theme open-window stroke-box text-width theme-default!
                window-drag-move! window-h window-ref window-set! window-setting
                window-state window-title window-w window-x window-y)
          (only (schevana kits text) text-fit)
          (only (schevana kits ui) ui-draw-window-icon)
          (only (schevana desktop menu) open-window-menu))

  (library-layer desktop)

  (at-load
   (theme-default! 'minimize-to 'taskbar)
   (theme-default! 'desk-icon-expand 'double-click))

  ;; Returns the size of win's icon, as (values w h): the app's icon over
  ;; the title.
  (define-part (desk-icon-size win)
    (values 88 (+ 52 (exact (ceiling (font-line-height 'ui-small))))))

  ;; Returns where a new icon w × h goes, as (values x y): along the
  ;; desktop's bottom, from the left, at the first place no icon takes.
  (define-part (desk-icon-place win w h)
    (let-values ([(dx dy dw dh) (desktop-rect)])
      (let ([y (- (+ dy dh) h 8)])
        (let loop ([x (+ dx 8)])
          (if (and (< (+ x w w 8) (+ dx dw))
                   (exists (lambda (i)
                             (and (window-ref i 'icon-for)
                                  (< (window-x i) (+ x w 8))
                                  (< x (+ (window-x i) (window-w i) 8))
                                  (< (window-y i) (+ y h))
                                  (< y (+ (window-y i) (window-h i)))))
                           *windows*))
              (loop (+ x w 8))
              (values x y))))))

  ;; Draws win's icon in a box w × h: the app's icon over the title.
  (define-part (draw-desk-icon win w h flags)
    (fill-box 0 0 w h 'window-bg)
    (stroke-box 0 0 w h (if (memq 'focused flags) 'accent 'window-border))
    (ui-draw-window-icon win (quotient (- w 32) 2) 8 32 '())
    (let ([title (text-fit (window-title win) (- w 8) 'ui-small)])
      (draw-text (/ (- w (text-width title 'ui-small)) 2) 46 title 'text
                 'ui-small)))

  ;; Before each frame: an icon for each minimized window that has none,
  ;; where its minimize-to says icons; an icon whose window is back or gone,
  ;; or whose setting changed, closes. (A window that is neither minimized
  ;; nor an icon is passed over first, so that a frame of a desktop with no
  ;; icons allocates nothing here.)
  (define (desk-icons-frame t)
    (for-each
     (lambda (w)
       (let ([main (window-ref w 'icon-for)])
         (cond
           [main (unless (and (memq main *windows*)
                              (eq? (window-state main) 'minimized)
                              (desk-icons? main))
                   (desk-icon-close! w))]
           [(and (eq? (window-state w) 'minimized)
                 (not (window-ref w 'above))
                 (not (let ([i (window-ref w 'desk-icon)])
                        (and i (memq i *windows*))))
                 (desk-icons? w))
            (desk-icon-open! w)])))
     *windows*))

  (define (desk-icons? win) (eq? (window-setting win 'minimize-to) 'icons))

  ;; Opens main's icon where it was put last, or where the style places it,
  ;; leaving the keyboard where it was.
  (define (desk-icon-open! main)
    (let*-values ([(w h x y)
                   (in-window-theme main
                     (lambda ()
                       (let*-values ([(w h) (desk-icon-size main)]
                                     [(at) (window-ref main 'desk-icon-at)]
                                     [(x y) (if at
                                                (values (car at) (cdr at))
                                                (desk-icon-place main w h))])
                         (values w h x y))))]
                  [(focus) *focus*]
                  [(style) (window-ref main 'window-style)]
                  [(icon)
                   (apply open-window (window-title main)
                          'size (cons w h)
                          'min-size '(1 . 1)
                          'pos (cons x y)
                          'frameless #t
                          'icon-for main
                          'mouse-doc (if (desk-icon-middle? main)
                                         '((L . "Move") (M . "Expand")
                                           (R . "Menu"))
                                         '((L . "Move") (L2 . "Open")
                                           (R . "Menu")))
                          'draw (lambda (win w h)
                                  (draw-desk-icon (window-ref win 'icon-for) w
                                                  h
                                                  (if (eq? win *focus*)
                                                      '(focused)
                                                      '())))
                          'mouse-down (lambda (win x y button clicks)
                                        (desk-icon-press! win button clicks))
                          'close (lambda (win) (desk-icon-closed! win))
                          (if style (list 'window-style style) '()))])
      (window-set! icon 'desk-icon-placed
                   (cons (window-x icon) (window-y icon)))
      (window-set! main 'desk-icon icon)
      (when (and focus (memq focus *windows*))
        (focus-window! focus #f))))

  ;; A press on an icon: it opens its window (a double click, or the middle
  ;; button), moves (the left button), or opens its window menu (the right).
  (define (desk-icon-press! icon button clicks)
    (let* ([main (window-ref icon 'icon-for)]
           [middle? (desk-icon-middle? main)])
      (cond
        [(if middle?
             (eq? button 'middle)
             (and (eq? button 'left) (>= clicks 2)))
         (when (memq main *windows*)
           (focus-window! main)
           (desk-icon-close! icon))]
        [(eq? button 'left) (window-drag-move! icon)]
        [(eq? button 'right) (open-window-menu icon *mouse-x* *mouse-y*)])))

  ;; Does main's style expand an icon with the middle button (Medley's), not
  ;; with a double click?
  (define (desk-icon-middle? main)
    (eq? (window-setting main 'desk-icon-expand) 'middle))

  ;; Closes an icon whose window is back or gone; its window keeps where it
  ;; was put, when it was moved.
  (define (desk-icon-close! icon)
    (let ([main (window-ref icon 'icon-for)]
          [placed (window-ref icon 'desk-icon-placed)])
      (window-set! icon 'desk-icon-done #t)
      (when (memq main *windows*)
        (unless (and placed (= (car placed) (window-x icon))
                     (= (cdr placed) (window-y icon)))
          (window-set! main 'desk-icon-at
                       (cons (window-x icon) (window-y icon))))
        (window-set! main 'desk-icon #f))
      (close-window! icon)))

  ;; An icon closed by other means (its menu's Close, a key) closes its
  ;; window too.
  (define (desk-icon-closed! icon)
    (unless (window-ref icon 'desk-icon-done)
      (let ([main (window-ref icon 'icon-for)])
        (when (memq main *windows*)
          (window-set! main 'desk-icon #f)
          (close-window! main)))))

  ;; A surface that draws nothing: its frame keeps the icons up to date.
  (at-load
   (define-surface desk-icons -5 'frame 'desk-icons-frame)))
