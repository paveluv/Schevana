;;; (schevana desktop outline) — where a style drags an outline (drag-feedback
;;; outline), a move or resize shows the window's new place as one, over
;;; everything, until the release puts the window there: *drag-outline*, the
;;; window manager's.

(library (schevana desktop outline)
  (export
    draw-drag-outline draw-drag-outline* outline-draw outline-box )
  (import (chezscheme)
          (only (schevana base) at-load define-hook library-layer)
          (only (schevana core) *drag-outline* define-part define-surface
                stipple stroke-box))

  (library-layer desktop)

  ;; The outline, within its rectangle: a 1-pixel ring of a 50 % stipple of
  ;; the text and window colors.
  (define-part (draw-drag-outline x y w h)
    (stroke-box x y w h (stipple 'text 'bg-1 "#." ".#")))

  (define (outline-draw)
    (when *drag-outline* (apply draw-drag-outline *drag-outline*)))

  (define (outline-box)
    (if *drag-outline* (apply values *drag-outline*) (values 0 0 0 0)))

  (at-load
   (define-surface outline 50 'draw 'outline-draw 'box 'outline-box)))
