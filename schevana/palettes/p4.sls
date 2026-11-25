;;; (schevana palettes p4) — the P4 palette: a black-and-white monitor of the
;;; Lisp machines' day, as it looked then, on a monitor of today. Symbolics
;;; gave the consoles of its LM-2 (a CADR) and its 3600 "true white
;;; phosphor"; MIT's CADR typically had a CPT monitor (shwarm.lisp:1938), and
;;; CPT's screens were of P104, a blend like P4, which is the white whose
;;; numbers were published. The sources, and what isn't known, are in
;;; .work/style/research/crt.md.
;;;
;;; The tube's white is P4's, x 0.270 and y 0.300, at 30 foot-lamberts
;;; (102.8 cd/m²), as RCA measured it (Phosphors for Cathode-Ray Tubes,
;;; TPM-1508A, 1961, p. 17). Its black is a hundredth of that, an office
;;; CRT's (AAPM TG18, table 1). The room adds 4 cd/m² to both: 200 lux, white
;;; as D50 is (sRGB's typical room, W3C, 1996), on a tube that gives back
;;; 0.02 cd/m² a lux (TG18, 4.2.4.2.2). So the black is 5 cd/m², 5 % of the
;;; white, the flare that sRGB calls typical. The monitor of today is sRGB's
;;; D65 at 166 cd/m², the median that readers in an office chose (Applied
;;; Ergonomics, 2025). In a lit room the eye adapts 60 % to the monitor and
;;; 40 % to the room (Katoh, J. Electronic Imaging 7(4), 1998), so a color
;;; seen on the tube is matched by
;;;
;;;   R' = R (0.6 R[D65] + 0.4 R[D50]) / (0.6 R[P4] + 0.4 R[D50])
;;;
;;; and the same of G and B, in CAT02's cones. With XYZ as shares of 166:
;;;
;;;             on the tube               matched              sRGB, linear
;;;   paper   0.581 0.643 0.907   0.593 0.641 0.750   0.564 0.658 0.695
;;;   ink     0.029 0.030 0.029   0.030 0.030 0.024   0.039 0.029 0.021
;;;
;;; which sRGB writes #c6d4d9 and #372f27. A one-bit screen has no other
;;; color, so everything is one of the two: the panels paper, so that icons
;;; show on them, and the desktop's second color ink, for a wallpaper that
;;; mixes the two (Interlisp's shade). What is between them has the light of
;;; one of the CADR's grays (scrman.lisp:437-443): HES-GRAY's eighth of ink
;;; (bg-2), 25%-GRAY (bg-3), 75%-GRAY (faint text), and seven eighths,
;;; HES-GRAY with its ink and paper swapped (a default button under the
;;; pointer). A chart's series, which have no hues, are told apart by
;;; Genera's patterns of ink ((schevana styles genera)).

(library (schevana palettes p4)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette p4 "P4 white"
     '(bg-0 #xc6d4d9
       bg-1 #xc6d4d9
       bg-2 #xbbc8cd
       bg-3 #xb0bcc0
       text #x372f27
       text-dim #x372f27
       text-faint #x737778
       accent #x372f27
       accent-2 #x372f27
       accent-ink #xc6d4d9
       primary-hover #x5b5c5b
       red #x372f27
       orange #x372f27
       yellow #x372f27
       green #x372f27
       cyan #x372f27
       teal #x372f27
       magenta #x372f27
       desktop-top #xc6d4d9
       desktop-bottom #x372f27
       watermark #x372f27
       panel #xc6d4d9
       chart-1 (stipple text #f "#." "#.")
       chart-2 (stipple text #f "#.." "..." "...")
       chart-3 (stipple text #f "##" "..")
       chart-4 (stipple text #f "#.." ".#." "..#")
       chart-5 (stipple text #f "#." ".#")
       chart-6 (stipple text #f "#..." "...." "..#." "....")
       chart-7 (stipple text #f "##" ".#")
       chart-8 text))))
