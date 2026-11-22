;;; (schevana kits host) — a program whose one window is an app of the host's
;;; desktop, as GNOME's own apps or a Mac's are. The window fills the screen,
;;; its title is the one the desktop shows, its least size is the screen's,
;;; it has an app id of its own, and its look is the host's (Adwaita on
;;; Linux, Mac on a Mac, Windows on Windows), light or dark as the desktop
;;; prefers when the look has a dark palette; or, when the command line asks
;;; for one (--style NAME), any of Schevana's styles. Only that look's
;;; libraries load (look-load!). The title bar is the host's, and the window
;;; has no frame of Schevana's; or, where the desktop draws none (GNOME under
;;; Wayland), the title bar is the style's, as GNOME's own apps draw their
;;; header bars: the desktop moves and resizes the window by the regions the
;;; core is told (screen-hit-regions!), and the frame's buttons and menu act
;;; on it. Closing the window, Ctrl+Q or Ctrl+W quits.
;;;
;;;   (host-main "org.example.Notes" 360 480 (command-line-arguments)
;;;     (lambda () (open-window "Notes" ...)))
;;;
;;; On the Schevana desktop the same window opens as any other: only
;;; host-main makes it the host's.

(library (schevana kits host)
  (export
    host-main host-look host-window! host-hit-regions host-edge host-corner
    host-act!)
  (import (chezscheme)
          (only (schevana base) filter-map library-layer platform-mac?
                platform-windows?)
          (only (schevana core) *mouse-x* *mouse-y* bind-key! close-window!
                frame-insets frame-regions look-load! maximized? quit!
                resize-kinds schevana-main screen-hit-regions! screen-maximized?
                screen-own-frame! screen-own-frame? screen-set-app-id!
                screen-set-least! screen-set-title! screen-window-action!
                set-style! toggle-maximize! window-h window-handlers
                window-min-h window-min-w window-set! window-title window-w
                window-x window-y))

  (library-layer kits)

  ;; Returns the look of this host's own apps, found by the platform's
  ;; predicates: Adwaita (GNOME's) where no other is known to be the
  ;; desktop's.
  (define (host-look)
    (cond [(platform-mac?) 'mac]
          [(platform-windows?) 'windows]
          [else 'adwaita]))

  ;; Makes win the host's app. It fills the screen: frameless where the host
  ;; draws its title bar, or else in its style's frame, which acts on the OS
  ;; window and moves and resizes it. Its title and least size (its
  ;; content's, 'min-size) become the screen's, and closing it quits.
  (define (host-window! win)
    (let ([own? (screen-own-frame?)] [hs (window-handlers win)])
      (unless own? (window-set! win 'frameless #t))
      (unless (maximized? win) (toggle-maximize! win))
      (screen-set-title! (window-title win))
      (screen-set-least! (window-min-w win) (window-min-h win))
      (let ([close (hashtable-ref hs 'close #f)])
        (hashtable-set! hs 'close
                        (lambda (w) (when close (close w)) (quit!))))
      (when own?
        (window-set! win 'on-action host-act!)
        ;; tell the regions again whenever the frame may have changed: the
        ;; window's size (the screen's), the style, maximized or not
        (let ([resize (hashtable-ref hs 'resize #f)])
          (hashtable-set! hs 'resize
                          (lambda (w cw ch)
                            (screen-hit-regions!
                             (host-hit-regions w (screen-maximized?)))
                            (when resize (resize w cw ch)))))
        (screen-hit-regions! (host-hit-regions win (screen-maximized?))))
      (bind-key! '(ctrl #\q) quit!)
      (bind-key! '(ctrl #\w) (lambda () (close-window! win)))
      win))

  ;; Does a frame's actions on the OS window: maximize (or restore),
  ;; minimize, and the desktop's own window menu at the pointer; close works
  ;; as for any window. A drag of the title never moves the window within
  ;; the screen: the desktop moves the OS window instead.
  (define (host-act! win action)
    (case action
      [(maximize)
       (screen-window-action! (if (screen-maximized?) 'restore 'maximize))
       #t]
      [(minimize) (screen-window-action! 'minimize) #t]
      [(menu) (screen-window-action! 'menu *mouse-x* *mouse-y*) #t]
      [(shade depth move) #t]
      [else #f]))

  ;; How far in from the window's edge a press resizes it, and how far from
  ;; a corner both ways, in logical pixels. Both are inside the window:
  ;; SDL's window has no margin outside it, where GNOME's own apps have
  ;; theirs.
  (define host-edge 5)
  (define host-corner 14)

  ;; Returns the regions of win, a host app with its own frame, as the
  ;; desktop takes them (screen-hit-regions!). Its edges and corners resize
  ;; it unless maximized?; its frame's title areas move it, wherever the
  ;; style puts them (Genera's label at the bottom), and its buttons are its
  ;; own. The rest of its top moves it too, as in any window.
  (define (host-hit-regions win maximized?)
    (let-values ([(l t r b) (frame-insets win)])
      (let ([x (window-x win)] [y (window-y win)]
            [w (window-w win)] [h (window-h win)]
            [e host-edge] [c host-corner])
        (append
         (if maximized?
             '()
             (list (list 'resize-tl x y c c)
                   (list 'resize-tr (+ x w (- c)) y c c)
                   (list 'resize-bl x (+ y h (- c)) c c)
                   (list 'resize-br (+ x w (- c)) (+ y h (- c)) c c)
                   (list 'resize-t x y w e)
                   (list 'resize-b x (+ y h (- e)) w e)
                   (list 'resize-l x y e h)
                   (list 'resize-r (+ x w (- e)) y e h)))
         (filter-map (lambda (reg)
                       (and (not (memq (car reg) resize-kinds))
                            (list (if (eq? (car reg) 'title) 'move 'normal)
                                  (+ x (cadr reg)) (+ y (caddr reg))
                                  (cadddr reg) (car (cddddr reg)))))
                     (frame-regions win))
         (list (list 'move x y w t))))))

  ;; Runs a host app, given its app id (the desktop matches it to a desktop
  ;; entry; by custom it is reverse-DNS), a screen of w × h logical pixels,
  ;; and open, a thunk that opens the app's window and returns it. args are
  ;; the command line's: --headless for no window; --fork for the screen's
  ;; thread apart from the world's, even headless; --style NAME for a style
  ;; of Schevana's in place of the host's look.
  (define (host-main app-id w h args open)
    (let* ([headless? (member "--headless" args)]
           [style (let ([s (member "--style" args)])
                    (and s (pair? (cdr s)) (string->symbol (cadr s))))]
           [look (look-load! (or style (host-look)))])
      (when (and style (not look))
        (errorf 'host-main "the tree has no style ~s (schevana/styles/)"
                style))
      (unless headless?
        (screen-set-app-id! app-id)
        (screen-own-frame! #t))
      ;; no least size of Schevana's own until the window gives its own
      (screen-set-least! 0 0)
      (schevana-main (if headless? 'headless 'sdl) w h #f
        (lambda ()
          (when look (set-style! look))
          (host-window! (open)))
        (and (member "--fork" args) #t)))))
