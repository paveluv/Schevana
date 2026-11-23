;;; (schevana styles adwaita text) — a part of the Adwaita style
;;; ((schevana styles adwaita)): text set as GTK sets a label, its box the
;;; font's ascent and descent rounded out and placed at a whole pixel.

(library (schevana styles adwaita text)
  (export
    adwaita-center adwaita-lines adwaita-text adwaita-text-centered
    adwaita-text-height adwaita-text-in adwaita-text-top adwaita-text-y)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) draw-text font-ascent font-line-height
                text-width)
          (only (schevana kits text) text-face-extent))

  (library-layer looks)

  ;;; Text as GTK sets a label (gtk/gtklabel.c:1388-1405 at 4.18.6): its
  ;;; box is the font's ascent and descent, rounded out to whole pixels
  ;;; (pango_layout_get_pixel_extents), and placed at a whole pixel in the
  ;;; room the label is given, centered and floored; its baseline is the
  ;;; ascent below the box's top, unrounded, since GTK's own font rendering
  ;;; hints no metrics (gtk/gtkwidget.c, update_pango_context).

  ;; draw-text's y for text whose box's top is at top (the ui-text-y
  ;; part).
  (define (adwaita-text-y top font)
    (let-values ([(ascent descent) (text-face-extent font)])
      (+ top (- ascent (font-ascent font)))))

  ;; A label's height in font.
  (define (adwaita-text-height font)
    (let-values ([(ascent descent) (text-face-extent font)])
      (ceiling (+ ascent descent))))

  ;; The top of a label in font, centered vertically in the box y h.
  (define (adwaita-text-top y h font)
    (+ y (floor (/ (- h (adwaita-text-height font)) 2))))

  ;; Where something w2 wide starts, centered across x w.
  (define (adwaita-center x w w2) (+ x (floor (/ (- w w2) 2))))

  ;; Draws s with its box's top at top; returns what draw-text returns.
  (define (adwaita-text x top s ink font)
    (draw-text x (adwaita-text-y top font) s ink font))

  ;; Draws s at x, centered vertically in the box y h.
  (define (adwaita-text-in x y h s ink font)
    (adwaita-text x (adwaita-text-top y h font) s ink font))

  ;; Draws s centered in the box x y w h.
  (define (adwaita-text-centered x y w h s ink font)
    (adwaita-text-in (adwaita-center x w (text-width s font)) y h s ink font))

  ;; Draws a wrapped label's lines from top, each at x (at line), a line
  ;; apart (as the kit measures them). Returns the top after the last.
  (define (adwaita-lines at top lines ink font)
    (fold-left (lambda (top line)
                 (adwaita-text (at line) top line ink font)
                 (+ top (font-line-height font)))
               top lines)))
