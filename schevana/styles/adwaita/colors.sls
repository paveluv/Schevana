;;; (schevana styles adwaita colors) — a part of the Adwaita style
;;; ((schevana styles adwaita)): GNOME's em, by which it sizes; a color's
;;; luma, which tells the dark style from the light; the value each style
;;; takes; and libadwaita's standalone colors, made with OKLab.

(library (schevana styles adwaita colors)
  (export
    adwaita-by-style adwaita-dark? adwaita-em adwaita-luma adwaita-standalone)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) color-rgba rgb theme))

  (library-layer looks)

  ;;; ------------------------------------------------------------------
  ;;; colors

  ;; GNOME gives its sizes for a text of 11 pt, 14⅔ pixels; ours is 15, a
  ;; whole number of pixels that Settings can show, so an em of GNOME's is
  ;; our text size less a 45th.
  (define (adwaita-em) (* (theme 'ui-font-size) 44/45))

  (define (adwaita-luma c)
    (let-values ([(r g b a) (color-rgba c)])
      (+ (* 0.2126 r) (* 0.7152 g) (* 0.0722 b))))

  (define (adwaita-dark?) (theme 'adwaita-dark))

  ;; One value in the light style, another in the dark.
  (define (adwaita-by-style light dark) (if (adwaita-dark?) dark light))

  ;; c as text or a mark on a plain surface, a "standalone" color: its
  ;; OKLab lightness at most 0.5 in the light style and at least 0.85 in the
  ;; dark, its hue kept, clipped to sRGB (_defaults.scss:25-37, 90-111;
  ;; adw-accent-color.c:144-146). OKLab is computed with Bjorn Ottosson's
  ;; published matrices.
  (define (adwaita-standalone c dark?)
    (define (lin v)
      (if (<= v 0.04045) (/ v 12.92) (expt (/ (+ v 0.055) 1.055) 2.4)))
    (define (gam v)
      (let ([v (max 0.0 (min 1.0 v))])
        (if (<= v 0.0031308)
            (* 12.92 v)
            (- (* 1.055 (expt v (/ 1 2.4))) 0.055))))
    (define (cbrt v) (if (< v 0) (- (expt (- v) 1/3)) (expt v 1/3)))
    (define (byte v) (exact (round (* 255 (gam v)))))
    (let*-values ([(r g b a) (color-rgba c)]
                  [(r g b) (values (lin r) (lin g) (lin b))]
                  [(l) (cbrt (+ (* 0.4122214708 r) (* 0.5363325363 g)
                                (* 0.0514459929 b)))]
                  [(m) (cbrt (+ (* 0.2119034982 r) (* 0.6806995451 g)
                                (* 0.1073969566 b)))]
                  [(s) (cbrt (+ (* 0.0883024619 r) (* 0.2817188376 g)
                                (* 0.6299787005 b)))]
                  [(L) (+ (* 0.2104542553 l) (* 0.7936177850 m)
                          (* -0.0040720468 s))]
                  [(A) (+ (* 1.9779984951 l) (* -2.4285922050 m)
                          (* 0.4505937099 s))]
                  [(B) (+ (* 0.0259040371 l) (* 0.7827717662 m)
                          (* -0.8086757660 s))]
                  [(L) (if dark? (max L 0.85) (min L 0.5))]
                  [(l) (expt (+ L (* 0.3963377774 A) (* 0.2158037573 B)) 3)]
                  [(m) (expt (+ L (* -0.1055613458 A) (* -0.0638541728 B)) 3)]
                  [(s) (expt (+ L (* -0.0894841775 A) (* -1.2914855480 B))
                             3)])
      (rgb (byte (+ (* 4.0767416621 l) (* -3.3077115913 m)
                    (* 0.2309699292 s)))
           (byte (+ (* -1.2684380046 l) (* 2.6097574011 m)
                    (* -0.3413193965 s)))
           (byte (+ (* -0.0041960863 l) (* -0.7034186147 m)
                    (* 1.7076147010 s)))))))
