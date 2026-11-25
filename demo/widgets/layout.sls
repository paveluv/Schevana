;;; (demo widgets layout) — what the Widgets demo's pages share: the line
;;; that says what the last action did, the values the window keeps, and
;;; the rows a page lays its widgets out in.

(library (demo widgets layout)
  (export widgets-say! widgets-said widgets-keep widgets-flow widgets-heading
          widgets-note widgets-width widgets-frame)
  (import (chezscheme)
          (schevana core)
          (schevana kits ui))

  ;; Says in the window's status line what the last action did.
  (define (widgets-say! win text)
    (window-set! win 'said text))

  ;; Returns a thunk that says text: what a button does here.
  (define (widgets-said win text)
    (lambda () (widgets-say! win text)))

  ;; Returns a procedure that keeps a widget's new value in the window,
  ;; under key, and says so. The window draws again with the value.
  (define (widgets-keep win key)
    (lambda (v)
      (window-set! win key v)
      (widgets-say! win (format "~a is now ~s" key v))))

  ;; Draws items left to right from (x, y), a gap apart, in rows that wrap
  ;; at w, each row's items centered on its tallest. Each item is (w h
  ;; draw), draw a (lambda (x y w h) ...) that draws it in its place.
  ;; Returns the y below the rows, and a gap.
  (define (widgets-flow x y w . items)
    (let-values ([(places height)
                  (ui-flow x y w (ui-gap)
                           (map (lambda (i) (cons (car i) (cadr i))) items))])
      (for-each (lambda (i p) ((caddr i) (car p) (cdr p) (car i) (cadr i)))
                items places)
      (+ y height (ui-gap))))

  ;; Draws a section's heading from y, a gap below what is above it, and
  ;; returns the y under it.
  (define (widgets-heading x y w title)
    (let-values ([(lw lh) (ui-label-size '(section) title w)])
      (ui-draw-label x (+ y (ui-gap)) w lh '(section) title)
      (+ y (ui-gap) lh 6)))

  ;; Draws a line of words on what a section shows, wrapped at w, and
  ;; returns the y under it.
  (define (widgets-note x y w text)
    (let-values ([(lw lh) (ui-label-size '(hint wrap) text w)])
      (ui-draw-label x y w lh '(hint wrap) text)
      (+ y lh 6)))

  ;; Returns how wide a button with label (and glyph, if given) is.
  (define (widgets-width label . glyph)
    (let-values ([(w h) (ui-button-size label
                                        (and (pair? glyph) (car glyph)))])
      w))

  ;; Draws the box a sample sits in: a well, so that what the sample draws
  ;; shows against it.
  (define (widgets-frame x y w h)
    (ui-draw-surface x y w h '(well))))
