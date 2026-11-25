;;; (demo widgets) — every widget of the kit ((schevana kits ui)) and every
;;; part it draws through, in all their states, to see what each style
;;; draws and where it has gaps. A list at the side chooses the page; the
;;; page scrolls, both ways when it is wide; the line at the bottom says
;;; what the last action did, and chooses the style everything is drawn in
;;; (as Settings does, or (set-style! 'genera) at a REPL). Each page is
;;; written as the calls a REPL user types, and the window keeps every
;;; value the widgets show (window-ref, window-set!).

(library (demo widgets)
  (export widgets)
  (import (chezscheme)
          (schevana core)
          (schevana kits text)
          (schevana kits ui)
          (demo widgets layout)
          (demo widgets controls)
          (demo widgets lists)
          (demo widgets charts)
          (demo widgets overlays)
          (demo widgets panes)
          (demo widgets boards)
          (demo widgets states))

  ;; The pages, in the order the list at the side shows them: each one's
  ;; value, its name and its glyph.
  (define widgets-pages
    '((controls "Controls" check)
      (text "Text" edit)
      (lists "Lists" file)
      (charts "Charts" chip)
      (overlays "Overlays" expand)
      (grids "Grids and panes" panel-left)
      (scrolling "Scrolling" chevron-down)
      (boards "Boards" folder)
      (states "Every state" search)))

  ;; Draws page from (x, y), w wide, and returns (values right bottom).
  (define (widgets-page ui win page x y w)
    (case page
      [(text) (widgets-text-page ui win x y w)]
      [(lists) (widgets-lists-page ui win x y w)]
      [(charts) (widgets-charts-page ui win x y w)]
      [(overlays) (widgets-overlays-page ui win x y w)]
      [(grids) (widgets-grids-page ui win x y w)]
      [(scrolling) (widgets-scrolling-page ui win x y w)]
      [(boards) (widgets-boards-page ui win x y w)]
      [(states) (widgets-states-page ui win x y w)]
      [else (widgets-controls-page ui win x y w)]))

  ;; The list's width: its widest name after a glyph.
  (define (widgets-nav-width)
    (+ 14 (ui-glyph-size) 8 (text-widest (map cadr widgets-pages) 'ui) 20))

  ;; The status line's height.
  (define (widgets-bar-height) (+ (ui-control-height) 10))

  ;; Draws everything in the next style after the current one, or the
  ;; style named.
  (define (widgets-style! win name)
    (let* ([names (styles)]
           [next (or name
                     (let ([tail (memq (current-style) names)])
                       (if (and tail (pair? (cdr tail)))
                           (cadr tail)
                           (car names))))])
      (set-style! next)
      (widgets-say! win (format "Drawn in ~a"
                                (style-title (find-style next))))))

  ;; Draws the status line x y w h: what the last action did, and the
  ;; style with a button to the next one.
  (define (widgets-draw-status ui win x y w h)
    (let*-values ([(gap ch) (values (ui-gap) (ui-control-height))]
                  [(cy) (+ y (quotient (- h ch) 2))]
                  [(choices) (map (lambda (name)
                                    (cons (style-title (find-style name))
                                          name))
                                  (styles))]
                  [(dw dh) (ui-dropdown-size (map car choices))]
                  [(nb) (widgets-width #f 'chevron-right)]
                  [(dx) (- (+ x w) gap nb 4 dw)])
      (ui-draw-surface x y w h '(footer))
      (ui-draw-label (+ x gap) y (max 0 (- dx x gap gap)) h '(dim)
                     (window-ref win 'said ""))
      (ui-dropdown ui 'widgets-style dx cy dw ch choices (current-style)
                   (lambda (name) (widgets-style! win name))
                   'tip "The style everything is drawn in")
      (ui-button ui 'widgets-next (- (+ x w) gap nb) cy nb ch #f
                 (lambda () (widgets-style! win #f))
                 'glyph 'chevron-right 'tip "The next style")))

  (define (widgets-draw win w h)
    (let* ([ui (window-ref win 'ui)] [page (window-ref win 'page 'controls)]
           [pad (ui-pad)] [nw (widgets-nav-width)] [bar (widgets-bar-height)]
           [vh (max 0 (- h bar))] [vw (max 0 (- w nw))]
           [pw (max 0 (- vw pad pad (ui-scrollbar-inset 'left)
                         (ui-scrollbar-inset 'right)))])
      (ui-begin! ui)
      (ui-draw-surface 0 0 nw vh '(nav))
      (ui-nav ui 'widgets-nav 6 pad (- nw 12)
              (map (lambda (p)
                     (list (car p) (cadr p)
                           (lambda (x y s flags)
                             (ui-draw-glyph x y s s flags (caddr p)))))
                   widgets-pages)
              page
              (lambda (new)
                (ui-forget! ui 'widgets-page)
                (window-set! win 'page new)
                (widgets-say! win (format "Showing ~a"
                                          (cadr (assq new widgets-pages))))))
      (ui-draw-surface nw 0 vw vh '(page))
      (ui-scroll-wide ui 'widgets-page nw 0 vw vh
        (lambda (left top)
          (let-values ([(right bottom)
                        (widgets-page ui win page
                                      (+ left pad (ui-scrollbar-inset 'left))
                                      (+ top pad) pw)])
            (values (+ right pad) (+ bottom pad)))))
      (widgets-draw-status ui win 0 vh w bar)
      (ui-end! ui w h)))

  ;; The app's icon: a button, a checkbox that is checked, and a slider.
  (define (widgets-draw-icon x y s flags)
    (define (ink c) (ui-icon-ink flags c))
    (ui-icon-grid (x y s)
      (fill-box 2 2.5 20 6 (ink 'accent) 2)
      (fill-box 2 11 6 6 (ink 'green) 1.5)
      (draw-polyline '((3.5 . 14) (4.75 . 15.5) (6.75 . 12.5)) (ink 'bg-0) 1.25)
      (fill-box 10 13 12 2 (ink 'text-dim) 1)
      (fill-box 2 20 20 2 (ink 'text-dim) 1)
      (fill-circle 15 21 2.5 (ink 'orange))))

  (define-app (widgets) "Widgets" 'icon widgets-draw-icon
    (apply open-window "Widgets"
      'size '(960 . 660)
      'min-size '(480 . 320)
      'page 'controls
      'said "Every widget of the kit, in the style chosen below"
      'stream (widgets-stream-new)
      'draw (lambda (win w h) (widgets-draw win w h))
      'close (lambda (win) (ui-stream-release! (window-ref win 'stream)))
      (ui-handlers (make-ui)))))
