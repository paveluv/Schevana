;;; (schevana styles genera fonts) — Genera's fonts, in which the Genera
;;; style draws its text: CPTFONT (FIX.ROMAN.NORMAL, the code font),
;;; JESS13 and JESS14 (JESS.NORMAL and JESS.LARGE, the command and menu
;;; words), HL12 and HL14 (SWISS.NORMAL and SWISS.LARGE, the titles), and
;;; SWISS12-CCAPS, with their bold and italic strikes (JESS has no bold
;;; italic).
;;;
;;; Where they come from: the glyphs and their metrics were recovered from
;;; the resident FONT arrays of Genera 8.5's world (Genera-8-5.vlod) by the
;;; genera-fonts project, https://github.com/htayj/genera-fonts, at revision
;;; 809694a73ece7f840b6541b4781cd47152d1ea35, with its reviewed mapping of
;;; Genera's characters to Unicode. That project publishes them in the
;;; United States as typeface, which is not subject to copyright there
;;; ("typeface as typeface", 37 C.F.R. 202.1(e); the Copyright Office's
;;; Compendium, 313.3(D)). Its BSD license covers its own code, not these
;;; designs, and no license from Symbolics comes with them. Schevana takes
;;; the glyph shapes and their metrics alone: no Genera code, no part of
;;; its world but these arrays, no manual. Turning that project's records
;;; into this file was done apart from Schevana and is not shipped with
;;; it. Elsewhere, Genera's look is taken only from its manuals and
;;; screenshots.
;;;
;;; What the fonts lack and Schevana's own text uses was drawn for this
;;; file from each font's own glyphs and stem, in its manner: the ellipsis
;;; of three of its periods; the dashes of its hyphen; the minus of its
;;; plus; × as its x; µ of its u; °, ✓, ▶, ❚, ⚠, ⚙ and ↳ at its stem's
;;; width; the curly quotes as its straight ones; and the Latin-1 letters,
;;; each with its accent over the letter (CPTFONT's own accents, small
;;; marks in the others), a capital a row or two shorter where the cell
;;; has no room above it. A character none of this covers draws the slug,
;;; an outline as tall as a capital.

(library (schevana styles genera fonts)
  (export genera-fonts)
  (import (chezscheme)
          (only (schevana base) library-layer))

  (library-layer looks)

  ;; The fonts, each (name pixel-size ascent descent glyph ...), as
  ;; define-bitmap-font takes them: a glyph is (char advance left top width
  ;; row ...), its rows from the top, the leftmost pixel in a row's highest
  ;; bit; #f is the slug. A bold or italic strike is a font of its own.
  (define genera-fonts
    '(("Genera CPTFONT" 12 10 2
      ;; the slug, which a character the face lacks draws
      (#f 8 1 9 6 #x3f #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x3f)
      ;; space
      (32 8)
      ;; !
      (33 8 3 9 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x1)
      ;; "
      (34 8 2 10 3 #x5 #x5 #x5 #x5)
      ;; #
      (35 8 1 9 6 #x12 #x12 #x3f #x12 #x12 #x12 #x3f #x12 #x12)
      ;; $
      (36 8 1 10 5 #x4 #xe #x15 #x14 #x14 #xe #x5 #x5 #x15 #xe #x4)
      ;; %
      (37 8 1 9 6 #x1f #x31 #x31 #x2 #x4 #x8 #x10 #x23 #x23)
      ;; &
      (38 8 1 9 6 #x18 #x24 #x24 #x18 #x18 #x25 #x22 #x22 #x1d)
      ;; '
      (39 8 3 9 2 #x3 #x3 #x1 #x2)
      ;; (
      (40 8 2 10 3 #x1 #x2 #x2 #x4 #x4 #x4 #x4 #x4 #x2 #x2 #x1)
      ;; )
      (41 8 2 10 3 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4)
      ;; *
      (42 8 1 8 5 #x4 #x15 #xe #x4 #xe #x15 #x4)
      ;; +
      (43 8 1 7 5 #x4 #x4 #x1f #x4 #x4)
      ;; ,
      (44 8 1 2 3 #x3 #x3 #x1 #x6)
      ;; -
      (45 8 1 5 6 #x3f)
      ;; .
      (46 8 3 2 2 #x3 #x3)
      ;; /
      (47 8 1 8 6 #x1 #x3 #x6 #xc #x18 #x30 #x20)
      ;; 0
      (48 8 1 9 6 #x1e #x21 #x21 #x23 #x25 #x29 #x31 #x21 #x1e)
      ;; 1
      (49 8 1 9 5 #x4 #x1c #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; 2
      (50 8 1 9 6 #x1e #x21 #x21 #x1 #x2 #xc #x10 #x20 #x3f)
      ;; 3
      (51 8 1 9 6 #x1e #x21 #x21 #x1 #xe #x1 #x21 #x21 #x1e)
      ;; 4
      (52 8 1 9 6 #x2 #x6 #xa #x12 #x22 #x3f #x2 #x2 #x2)
      ;; 5
      (53 8 1 9 6 #x3f #x20 #x20 #x3e #x1 #x1 #x1 #x21 #x1e)
      ;; 6
      (54 8 1 9 6 #xe #x10 #x20 #x20 #x3e #x21 #x21 #x21 #x1e)
      ;; 7
      (55 8 1 9 6 #x3f #x1 #x3 #xe #xe #x8 #x18 #x10 #x10)
      ;; 8
      (56 8 1 9 6 #x1e #x21 #x21 #x21 #x1e #x21 #x21 #x21 #x1e)
      ;; 9
      (57 8 1 9 6 #x1e #x21 #x21 #x21 #x1f #x1 #x1 #x2 #x1c)
      ;; :
      (58 8 3 6 2 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; ;
      (59 8 1 6 3 #x3 #x3 #x0 #x0 #x3 #x3 #x1 #x6)
      ;; <
      (60 8 2 8 4 #x1 #x2 #x4 #x8 #x4 #x2 #x1)
      ;; =
      (61 8 1 6 6 #x3f #x0 #x0 #x3f)
      ;; >
      (62 8 2 8 4 #x8 #x4 #x2 #x1 #x2 #x4 #x8)
      ;; ?
      (63 8 1 9 6 #x1e #x21 #x21 #x2 #x4 #x8 #x8 #x0 #x8)
      ;; @
      (64 8 1 8 6 #x1e #x21 #x2f #x29 #x29 #x2f #x20 #x1e)
      ;; A
      (65 8 1 9 6 #x1e #x21 #x21 #x21 #x3f #x21 #x21 #x21 #x21)
      ;; B
      (66 8 1 9 6 #x3e #x21 #x21 #x21 #x3e #x21 #x21 #x21 #x3e)
      ;; C
      (67 8 1 9 6 #x1e #x21 #x21 #x20 #x20 #x20 #x21 #x21 #x1e)
      ;; D
      (68 8 1 9 6 #x3e #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x3e)
      ;; E
      (69 8 1 9 6 #x3f #x20 #x20 #x20 #x3e #x20 #x20 #x20 #x3f)
      ;; F
      (70 8 1 9 6 #x3f #x20 #x20 #x20 #x3e #x20 #x20 #x20 #x20)
      ;; G
      (71 8 1 9 6 #x1e #x21 #x21 #x20 #x20 #x27 #x21 #x21 #x1e)
      ;; H
      (72 8 1 9 6 #x21 #x21 #x21 #x21 #x3f #x21 #x21 #x21 #x21)
      ;; I
      (73 8 1 9 5 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; J
      (74 8 1 9 6 #x1 #x1 #x1 #x1 #x1 #x1 #x21 #x21 #x1e)
      ;; K
      (75 8 1 9 6 #x21 #x22 #x24 #x28 #x30 #x28 #x24 #x22 #x21)
      ;; L
      (76 8 1 9 6 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; M
      (77 8 1 9 6 #x21 #x33 #x2d #x2d #x21 #x21 #x21 #x21 #x21)
      ;; N
      (78 8 1 9 6 #x21 #x31 #x29 #x25 #x23 #x21 #x21 #x21 #x21)
      ;; O
      (79 8 1 9 6 #x1e #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; P
      (80 8 1 9 6 #x3e #x21 #x21 #x21 #x3e #x20 #x20 #x20 #x20)
      ;; Q
      (81 8 1 9 6 #x1e #x21 #x21 #x21 #x21 #x21 #x25 #x22 #x1d)
      ;; R
      (82 8 1 9 6 #x3e #x21 #x21 #x21 #x3e #x28 #x24 #x22 #x21)
      ;; S
      (83 8 1 9 6 #x1e #x21 #x20 #x20 #x1e #x1 #x21 #x21 #x1e)
      ;; T
      (84 8 1 9 5 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4)
      ;; U
      (85 8 1 9 6 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; V
      (86 8 1 9 6 #x21 #x21 #x21 #x21 #x21 #x12 #x12 #x12 #xc)
      ;; W
      (87 8 1 9 6 #x21 #x21 #x21 #x21 #x21 #x2d #x2d #x33 #x21)
      ;; X
      (88 8 1 9 6 #x21 #x21 #x21 #x12 #xc #x12 #x21 #x21 #x21)
      ;; Y
      (89 8 1 9 5 #x11 #x11 #x11 #xa #x4 #x4 #x4 #x4 #x4)
      ;; Z
      (90 8 1 9 6 #x3f #x1 #x2 #x4 #x1e #x8 #x10 #x20 #x3f)
      ;; [
      (91 8 3 10 4 #xf #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #xf)
      ;; \
      (92 8 1 8 6 #x20 #x30 #x18 #xc #x6 #x3 #x1)
      ;; ]
      (93 8 1 10 4 #xf #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #xf)
      ;; ^
      (94 8 1 10 6 #xc #x12 #x21)
      ;; _
      (95 8 1 -1 6 #x3f)
      ;; `
      (96 8 3 9 2 #x3 #x3 #x2 #x1)
      ;; a
      (97 8 1 6 6 #x1e #x1 #x1f #x21 #x21 #x1f)
      ;; b
      (98 8 1 9 6 #x20 #x20 #x20 #x3e #x21 #x21 #x21 #x21 #x3e)
      ;; c
      (99 8 1 6 6 #x1e #x21 #x20 #x20 #x21 #x1e)
      ;; d
      (100 8 1 9 6 #x1 #x1 #x1 #x1f #x21 #x21 #x21 #x21 #x1f)
      ;; e
      (101 8 1 6 6 #x1e #x21 #x3f #x20 #x20 #x1f)
      ;; f
      (102 8 1 9 6 #xe #x11 #x10 #x3c #x10 #x10 #x10 #x10 #x10)
      ;; g
      (103 8 1 6 6 #x1e #x21 #x21 #x21 #x1f #x1 #x21 #x1e)
      ;; h
      (104 8 1 9 6 #x20 #x20 #x20 #x3e #x21 #x21 #x21 #x21 #x21)
      ;; i
      (105 8 2 9 3 #x1 #x1 #x0 #x7 #x1 #x1 #x1 #x1 #x1)
      ;; j
      (106 8 1 9 5 #x1 #x1 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x11 #xe)
      ;; k
      (107 8 1 9 6 #x20 #x20 #x20 #x23 #x24 #x38 #x24 #x22 #x21)
      ;; l
      (108 8 2 9 3 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; m
      (109 8 1 6 6 #x36 #x2d #x29 #x21 #x21 #x21)
      ;; n
      (110 8 1 6 6 #x2e #x31 #x21 #x21 #x21 #x21)
      ;; o
      (111 8 1 6 6 #x1e #x21 #x21 #x21 #x21 #x1e)
      ;; p
      (112 8 1 6 6 #x3e #x21 #x21 #x21 #x21 #x3e #x20 #x20)
      ;; q
      (113 8 1 6 6 #x1f #x21 #x21 #x21 #x21 #x1f #x1 #x1)
      ;; r
      (114 8 1 6 6 #x2e #x31 #x20 #x20 #x20 #x20)
      ;; s
      (115 8 1 6 6 #x1f #x20 #x1e #x1 #x21 #x1e)
      ;; t
      (116 8 1 8 6 #x10 #x10 #x3e #x10 #x10 #x10 #x11 #xe)
      ;; u
      (117 8 1 6 6 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; v
      (118 8 1 6 6 #x21 #x21 #x21 #x12 #x12 #xc)
      ;; w
      (119 8 1 6 6 #x21 #x21 #x21 #x29 #x2d #x12)
      ;; x
      (120 8 1 6 6 #x21 #x12 #xc #x12 #x21 #x21)
      ;; y
      (121 8 1 6 6 #x21 #x21 #x21 #x12 #xc #x8 #x10 #x20)
      ;; z
      (122 8 1 6 6 #x3f #x2 #x1e #x8 #x10 #x3f)
      ;; {
      (123 8 2 10 4 #x3 #x4 #x4 #x4 #x4 #x8 #x4 #x4 #x4 #x4 #x3)
      ;; |
      (124 8 3 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; }
      (125 8 2 10 4 #xc #x2 #x2 #x2 #x2 #x1 #x2 #x2 #x2 #x2 #xc)
      ;; ~
      (126 8 1 9 6 #x19 #x26)
      ;; ¬
      (172 8 1 5 6 #x3f #x1 #x1)
      ;; °
      (176 8 2 9 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 8 1 7 5 #x4 #x4 #x1f #x4 #x4 #x1f)
      ;; µ
      (181 8 1 6 6 #x21 #x21 #x21 #x21 #x21 #x1e #x20 #x20)
      ;; ·
      (183 8 2 6 3 #x7 #x7 #x7)
      ;; À
      (192 8 1 10 6 #x18 #xc #x6 #x1e #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Á
      (193 8 1 10 6 #x6 #xc #x18 #x1e #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Â
      (194 8 1 10 6 #xc #x12 #x21 #x1e #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Ã
      (195 8 1 10 6 #x19 #x26 #x0 #x1e #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Ä
      (196 8 1 10 6 #x12 #x12 #x0 #x1e #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Å
      (197 8 1 10 6 #xc #x12 #x12 #xc #x1e #x21 #x3f #x21 #x21 #x21)
      ;; Ç
      (199 8 1 9 6 #x1e #x21 #x21 #x20 #x20 #x20 #x21 #x21 #x1e #xc #x1c)
      ;; È
      (200 8 1 10 6 #x18 #xc #x6 #x3f #x20 #x3e #x20 #x20 #x20 #x3f)
      ;; É
      (201 8 1 10 6 #x6 #xc #x18 #x3f #x20 #x3e #x20 #x20 #x20 #x3f)
      ;; Ê
      (202 8 1 10 6 #xc #x12 #x21 #x3f #x20 #x3e #x20 #x20 #x20 #x3f)
      ;; Ë
      (203 8 1 10 6 #x12 #x12 #x0 #x3f #x20 #x3e #x20 #x20 #x20 #x3f)
      ;; Ì
      (204 8 1 10 5 #x18 #xc #x6 #x1f #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Í
      (205 8 1 10 5 #x6 #xc #x18 #x1f #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Î
      (206 8 0 10 6 #xc #x12 #x21 #x1f #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Ï
      (207 8 1 10 5 #x12 #x12 #x0 #x1f #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Ñ
      (209 8 1 10 6 #x19 #x26 #x0 #x21 #x31 #x29 #x25 #x23 #x21 #x21)
      ;; Ò
      (210 8 1 10 6 #x18 #xc #x6 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ó
      (211 8 1 10 6 #x6 #xc #x18 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ô
      (212 8 1 10 6 #xc #x12 #x21 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Õ
      (213 8 1 10 6 #x19 #x26 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ö
      (214 8 1 10 6 #x12 #x12 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ×
      (215 8 1 6 6 #x21 #x12 #xc #x12 #x21 #x21)
      ;; Ù
      (217 8 1 10 6 #x18 #xc #x6 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ú
      (218 8 1 10 6 #x6 #xc #x18 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Û
      (219 8 1 10 6 #xc #x12 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ü
      (220 8 1 10 6 #x12 #x12 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ý
      (221 8 1 10 5 #x6 #xc #x18 #x11 #xa #x4 #x4 #x4 #x4 #x4)
      ;; à
      (224 8 1 10 6 #x18 #xc #x6 #x0 #x1e #x1 #x1f #x21 #x21 #x1f)
      ;; á
      (225 8 1 10 6 #x6 #xc #x18 #x0 #x1e #x1 #x1f #x21 #x21 #x1f)
      ;; â
      (226 8 1 10 6 #xc #x12 #x21 #x0 #x1e #x1 #x1f #x21 #x21 #x1f)
      ;; ã
      (227 8 1 9 6 #x19 #x26 #x0 #x1e #x1 #x1f #x21 #x21 #x1f)
      ;; ä
      (228 8 1 9 6 #x12 #x12 #x0 #x1e #x1 #x1f #x21 #x21 #x1f)
      ;; å
      (229 8 1 10 6 #xc #x12 #x12 #xc #x0 #x1e #x1 #x1f #x21 #x1f)
      ;; ç
      (231 8 1 6 6 #x1e #x21 #x20 #x20 #x21 #x1e #xc #x1c)
      ;; è
      (232 8 1 10 6 #x18 #xc #x6 #x0 #x1e #x21 #x3f #x20 #x20 #x1f)
      ;; é
      (233 8 1 10 6 #x6 #xc #x18 #x0 #x1e #x21 #x3f #x20 #x20 #x1f)
      ;; ê
      (234 8 1 10 6 #xc #x12 #x21 #x0 #x1e #x21 #x3f #x20 #x20 #x1f)
      ;; ë
      (235 8 1 9 6 #x12 #x12 #x0 #x1e #x21 #x3f #x20 #x20 #x1f)
      ;; ì
      (236 8 1 10 4 #xc #x6 #x3 #x0 #x7 #x1 #x1 #x1 #x1 #x1)
      ;; í
      (237 8 1 10 4 #x3 #x6 #xc #x0 #x7 #x1 #x1 #x1 #x1 #x1)
      ;; î
      (238 8 0 10 6 #xc #x12 #x21 #x0 #xe #x2 #x2 #x2 #x2 #x2)
      ;; ï
      (239 8 1 9 4 #x9 #x9 #x0 #x7 #x1 #x1 #x1 #x1 #x1)
      ;; ñ
      (241 8 1 9 6 #x19 #x26 #x0 #x2e #x31 #x21 #x21 #x21 #x21)
      ;; ò
      (242 8 1 10 6 #x18 #xc #x6 #x0 #x1e #x21 #x21 #x21 #x21 #x1e)
      ;; ó
      (243 8 1 10 6 #x6 #xc #x18 #x0 #x1e #x21 #x21 #x21 #x21 #x1e)
      ;; ô
      (244 8 1 10 6 #xc #x12 #x21 #x0 #x1e #x21 #x21 #x21 #x21 #x1e)
      ;; õ
      (245 8 1 9 6 #x19 #x26 #x0 #x1e #x21 #x21 #x21 #x21 #x1e)
      ;; ö
      (246 8 1 9 6 #x12 #x12 #x0 #x1e #x21 #x21 #x21 #x21 #x1e)
      ;; ù
      (249 8 1 10 6 #x18 #xc #x6 #x0 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ú
      (250 8 1 10 6 #x6 #xc #x18 #x0 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; û
      (251 8 1 10 6 #xc #x12 #x21 #x0 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ü
      (252 8 1 9 6 #x12 #x12 #x0 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ý
      (253 8 1 10 6 #x6 #xc #x18 #x0 #x21 #x21 #x21 #x12 #xc #x8 #x10 #x20)
      ;; ÿ
      (255 8 1 9 6 #x12 #x12 #x0 #x21 #x21 #x21 #x12 #xc #x8 #x10 #x20)
      ;; combining grave accent
      (768 0 1 10 4 #xc #x6 #x3)
      ;; combining acute accent
      (769 0 3 10 4 #x3 #x6 #xc)
      ;; combining circumflex accent
      (770 0 1 10 6 #xc #x12 #x21)
      ;; combining tilde
      (771 0 1 9 6 #x19 #x26)
      ;; combining macron
      (772 0 1 8 6 #x3f)
      ;; combining breve
      (774 0 1 9 6 #x21 #x1e)
      ;; combining dot above
      (775 0 3 9 2 #x3 #x3)
      ;; combining diaeresis
      (776 0 2 9 4 #x9 #x9)
      ;; combining ring above
      (778 0 2 10 4 #x6 #x9 #x9 #x6)
      ;; combining double acute accent
      (779 0 1 9 6 #x9 #x12 #x24)
      ;; combining caron
      (780 0 1 10 6 #x21 #x12 #xc)
      ;; combining cedilla
      (807 0 3 0 3 #x3 #x7)
      ;; combining ogonek
      (808 0 1 0 3 #x6 #x7)
      ;; combining low line
      (818 0 1 -1 6 #x3f)
      ;; α
      (945 8 1 6 6 #x1d #x22 #x22 #x22 #x22 #x1d)
      ;; β
      (946 8 1 8 6 #x1e #x21 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20)
      ;; γ
      (947 8 1 8 5 #x11 #xa #x4 #xa #x11 #x11 #x11 #xe)
      ;; δ
      (948 8 1 9 6 #xe #x10 #x10 #x8 #xc #x12 #x21 #x21 #x1e)
      ;; ε
      (949 8 1 6 5 #xf #x10 #x1c #x10 #x10 #xf)
      ;; λ
      (955 8 1 8 6 #x20 #x20 #x10 #x8 #xc #x12 #x21 #x21)
      ;; π
      (960 8 1 6 6 #x3f #x12 #x12 #x12 #x12 #x12)
      ;; –
      (8211 8 1 5 6 #x3f)
      ;; —
      (8212 8 0 5 8 #xff)
      ;; ‘
      (8216 8 3 9 2 #x3 #x3 #x1 #x2)
      ;; ’
      (8217 8 3 9 2 #x3 #x3 #x1 #x2)
      ;; “
      (8220 8 2 10 3 #x5 #x5 #x5 #x5)
      ;; ”
      (8221 8 2 10 3 #x5 #x5 #x5 #x5)
      ;; …
      (8230 8 0 2 8 #xdb #xdb)
      ;; ←
      (8592 8 1 7 6 #x8 #x10 #x3f #x10 #x8)
      ;; ↑
      (8593 8 1 8 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 8 1 7 6 #x4 #x2 #x3f #x2 #x4)
      ;; ↓
      (8595 8 1 8 5 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 8 1 8 6 #x4 #x2 #x3f #x2 #x4 #x8 #x10 #x3f #x10 #x8)
      ;; ↳
      (8627 8 1 9 6 #x20 #x20 #x24 #x22 #x3f #x2 #x4)
      ;; ∀
      (8704 8 1 9 6 #x21 #x21 #x21 #x21 #x3f #x21 #x12 #x12 #xc)
      ;; ∂
      (8706 8 1 9 5 #xc #x2 #x1 #x1 #xf #x11 #x11 #x11 #xe)
      ;; ∃
      (8707 8 1 9 6 #x3f #x1 #x1 #x1 #x1f #x1 #x1 #x1 #x3f)
      ;; −
      (8722 8 1 5 5 #x1f)
      ;; ∞
      (8734 8 0 6 7 #x36 #x49 #x49 #x49 #x36)
      ;; ∧
      (8743 8 1 6 6 #xc #x12 #x21)
      ;; ∨
      (8744 8 1 6 6 #x21 #x12 #xc)
      ;; ∩
      (8745 8 1 7 5 #xe #x11 #x11 #x11 #x11 #x11)
      ;; ∪
      (8746 8 1 7 5 #x11 #x11 #x11 #x11 #x11 #xe)
      ;; ∫
      (8747 8 2 9 5 #x2 #x5 #x5 #x4 #x4 #x4 #x4 #x4 #x14 #x14 #x8)
      ;; ≠
      (8800 8 1 8 6 #x1 #x2 #x3f #x4 #x8 #x3f #x10 #x20)
      ;; ≡
      (8801 8 1 7 6 #x3f #x0 #x3f #x0 #x3f)
      ;; ≤
      (8804 8 2 9 4 #x1 #x2 #x4 #x8 #x4 #x2 #x1 #x0 #xf)
      ;; ≥
      (8805 8 2 9 4 #x8 #x4 #x2 #x1 #x2 #x4 #x8 #x0 #xf)
      ;; ⊂
      (8834 8 1 7 6 #x1f #x20 #x20 #x20 #x1f)
      ;; ⊃
      (8835 8 1 7 6 #x3e #x1 #x1 #x1 #x3e)
      ;; ⊕
      (8853 8 0 7 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 8 0 7 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 8 2 6 3 #x7 #x7 #x7)
      ;; ▶
      (9654 8 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 8 1 8 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ◊
      (9674 8 1 8 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ⚙
      (9881 8 0 9 9 #x10 #xfe #xfe #xee #x1c7 #xee #xfe #xfe #x10)
      ;; ⚠
      (9888 8 0 10 7 #x8 #x8 #x14 #x14 #x1c #x2a #x2a #x22 #x49 #x7f)
      ;; ✓
      (10003 8 1 7 6 #x1 #x1 #x2 #x22 #x14 #x14 #x8)
      ;; ❚
      (10074 8 3 9 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera CPTFONT Bold" 12 10 2
      ;; the slug, which a character the face lacks draws
      (#f 8 1 9 6 #x3f #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x3f)
      ;; space
      (32 8)
      ;; !
      (33 8 3 9 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x0 #x3)
      ;; "
      (34 8 2 10 4 #xf #xf #xf #xf)
      ;; #
      (35 8 1 9 6 #x1e #x1e #x3f #x1e #x1e #x1e #x3f #x1e #x1e)
      ;; $
      (36 8 1 10 6 #xc #x1e #x3f #x3f #x3c #x1e #xf #x3f #x1e #xc)
      ;; %
      (37 8 1 9 6 #x1f #x3b #x3b #x6 #xc #xc #x18 #x37 #x37)
      ;; &
      (38 8 1 9 6 #x1c #x36 #x36 #x3c #x18 #x3c #x37 #x36 #x1f)
      ;; '
      (39 8 3 10 3 #x7 #x7 #x3 #x6)
      ;; (
      (40 8 2 10 4 #x3 #x6 #x6 #xc #xc #xc #xc #xc #x6 #x6 #x3)
      ;; )
      (41 8 2 10 4 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc)
      ;; *
      (42 8 1 8 6 #xc #x3f #x1e #xc #x1e #x3f #xc)
      ;; +
      (43 8 1 7 6 #xc #xc #x3f #xc #xc)
      ;; ,
      (44 8 1 2 4 #x7 #x7 #x3 #xe)
      ;; -
      (45 8 1 5 6 #x3f)
      ;; .
      (46 8 2 2 3 #x7 #x7)
      ;; /
      (47 8 1 7 6 #x3 #x7 #xe #x1c #x38 #x30)
      ;; 0
      (48 8 1 9 6 #x1e #x33 #x33 #x37 #x3f #x3f #x3b #x33 #x1e)
      ;; 1
      (49 8 2 9 4 #x6 #xe #x6 #x6 #x6 #x6 #x6 #x6 #xf)
      ;; 2
      (50 8 1 9 6 #x1e #x33 #x33 #x3 #x6 #xc #x18 #x30 #x3f)
      ;; 3
      (51 8 1 9 6 #x1e #x33 #x33 #x3 #xe #x3 #x33 #x33 #x1e)
      ;; 4
      (52 8 1 9 6 #x6 #xe #x1e #x1e #x36 #x3f #x6 #x6 #x6)
      ;; 5
      (53 8 1 9 6 #x3f #x30 #x30 #x3e #x3 #x3 #x3 #x33 #x1e)
      ;; 6
      (54 8 1 9 6 #xe #x18 #x30 #x30 #x3e #x33 #x33 #x33 #x1e)
      ;; 7
      (55 8 1 9 6 #x3f #x3 #x7 #x1e #xc #xc #x18 #x18 #x18)
      ;; 8
      (56 8 1 9 6 #x1e #x33 #x33 #x33 #x1e #x33 #x33 #x33 #x1e)
      ;; 9
      (57 8 1 9 6 #x1e #x33 #x33 #x33 #x1f #x3 #x3 #x6 #x1c)
      ;; :
      (58 8 2 6 3 #x7 #x7 #x0 #x0 #x7 #x7)
      ;; ;
      (59 8 1 6 4 #x7 #x7 #x0 #x0 #x7 #x7 #x3 #xe)
      ;; <
      (60 8 1 8 5 #x3 #x6 #xc #x18 #xc #x6 #x3)
      ;; =
      (61 8 1 6 6 #x3f #x0 #x0 #x3f)
      ;; >
      (62 8 2 8 5 #x18 #xc #x6 #x3 #x6 #xc #x18)
      ;; ?
      (63 8 1 9 6 #x1e #x33 #x33 #x6 #xc #x18 #x18 #x0 #x18)
      ;; @
      (64 8 1 8 6 #x1e #x33 #x3f #x3f #x3f #x3f #x30 #x1e)
      ;; A
      (65 8 1 9 6 #x1e #x33 #x33 #x33 #x3f #x33 #x33 #x33 #x33)
      ;; B
      (66 8 1 9 6 #x3e #x33 #x33 #x33 #x3e #x33 #x33 #x33 #x3e)
      ;; C
      (67 8 1 9 6 #x1e #x33 #x33 #x30 #x30 #x30 #x33 #x33 #x1e)
      ;; D
      (68 8 1 9 6 #x3e #x33 #x33 #x33 #x33 #x33 #x33 #x33 #x3e)
      ;; E
      (69 8 1 9 6 #x3f #x30 #x30 #x30 #x3e #x30 #x30 #x30 #x3f)
      ;; F
      (70 8 1 9 6 #x3f #x30 #x30 #x30 #x3e #x30 #x30 #x30 #x30)
      ;; G
      (71 8 1 9 6 #x1e #x33 #x33 #x30 #x30 #x37 #x33 #x33 #x1e)
      ;; H
      (72 8 1 9 6 #x33 #x33 #x33 #x33 #x3f #x33 #x33 #x33 #x33)
      ;; I
      (73 8 1 9 6 #x3f #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; J
      (74 8 1 9 6 #x3 #x3 #x3 #x3 #x3 #x3 #x33 #x33 #x1e)
      ;; K
      (75 8 1 9 7 #x66 #x6c #x78 #x70 #x70 #x78 #x6c #x66 #x63)
      ;; L
      (76 8 1 9 6 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x3f)
      ;; M
      (77 8 1 9 6 #x33 #x3f #x3f #x3f #x33 #x33 #x33 #x33 #x33)
      ;; N
      (78 8 1 9 6 #x33 #x33 #x3b #x3b #x37 #x37 #x33 #x33 #x33)
      ;; O
      (79 8 1 9 6 #x1e #x33 #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; P
      (80 8 1 9 6 #x3e #x33 #x33 #x33 #x3e #x30 #x30 #x30 #x30)
      ;; Q
      (81 8 1 9 6 #x1e #x33 #x33 #x33 #x33 #x33 #x3f #x36 #x1f)
      ;; R
      (82 8 1 9 6 #x3e #x33 #x33 #x33 #x3e #x3c #x36 #x33 #x33)
      ;; S
      (83 8 1 9 6 #x1e #x33 #x30 #x30 #x1e #x3 #x33 #x33 #x1e)
      ;; T
      (84 8 1 9 6 #x3f #xc #xc #xc #xc #xc #xc #xc #xc)
      ;; U
      (85 8 1 9 6 #x33 #x33 #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; V
      (86 8 1 9 6 #x33 #x33 #x33 #x33 #x33 #x1e #x1e #x1e #xc)
      ;; W
      (87 8 1 9 6 #x33 #x33 #x33 #x33 #x33 #x3f #x3f #x3f #x33)
      ;; X
      (88 8 1 9 6 #x33 #x33 #x33 #x1e #xc #x1e #x33 #x33 #x33)
      ;; Y
      (89 8 1 9 6 #x33 #x33 #x33 #x1e #xc #xc #xc #xc #xc)
      ;; Z
      (90 8 1 9 6 #x3f #x3 #x6 #x6 #x1e #x18 #x18 #x30 #x3f)
      ;; [
      (91 8 2 10 5 #x1f #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x1f)
      ;; \
      (92 8 1 8 6 #x30 #x38 #x1c #xe #x7 #x3)
      ;; ]
      (93 8 1 10 5 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x1f)
      ;; ^
      (94 8 1 10 6 #xc #x1e #x33)
      ;; _
      (95 8 1 -1 6 #x3f)
      ;; `
      (96 8 3 10 3 #x7 #x7 #x6 #x3)
      ;; a
      (97 8 1 6 6 #x1e #x3 #x1f #x33 #x33 #x1f)
      ;; b
      (98 8 1 9 6 #x30 #x30 #x30 #x3e #x33 #x33 #x33 #x33 #x3e)
      ;; c
      (99 8 1 6 6 #x1e #x33 #x30 #x30 #x33 #x1e)
      ;; d
      (100 8 1 9 6 #x3 #x3 #x3 #x1f #x33 #x33 #x33 #x33 #x1f)
      ;; e
      (101 8 1 6 6 #x1e #x33 #x3f #x30 #x30 #x1f)
      ;; f
      (102 8 1 9 6 #xf #x18 #x18 #x3e #x18 #x18 #x18 #x18 #x18)
      ;; g
      (103 8 1 6 6 #x1e #x33 #x33 #x33 #x1f #x3 #x33 #x1e)
      ;; h
      (104 8 1 9 6 #x30 #x30 #x30 #x3e #x33 #x33 #x33 #x33 #x33)
      ;; i
      (105 8 2 9 3 #x3 #x3 #x0 #x7 #x3 #x3 #x3 #x3 #x3)
      ;; j
      (106 8 1 9 5 #x3 #x3 #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x1b #xe)
      ;; k
      (107 8 1 9 6 #x30 #x30 #x30 #x37 #x3c #x38 #x3c #x36 #x33)
      ;; l
      (108 8 2 9 3 #x7 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; m
      (109 8 1 6 6 #x3b #x3f #x3f #x33 #x33 #x33)
      ;; n
      (110 8 1 6 6 #x2e #x3b #x33 #x33 #x33 #x33)
      ;; o
      (111 8 1 6 6 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; p
      (112 8 1 6 6 #x3e #x33 #x33 #x33 #x33 #x3e #x30 #x30)
      ;; q
      (113 8 1 6 6 #x1f #x33 #x33 #x33 #x33 #x1f #x3 #x3)
      ;; r
      (114 8 1 6 6 #x3e #x3b #x30 #x30 #x30 #x30)
      ;; s
      (115 8 1 6 6 #x1f #x30 #x1e #x3 #x3 #x3e)
      ;; t
      (116 8 1 8 6 #x18 #x18 #x3e #x18 #x18 #x18 #x1b #xe)
      ;; u
      (117 8 1 6 6 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; v
      (118 8 1 6 6 #x33 #x33 #x33 #x1e #x1e #xc)
      ;; w
      (119 8 1 6 6 #x33 #x33 #x33 #x3f #x3f #x33)
      ;; x
      (120 8 1 6 6 #x33 #x1e #xc #x1e #x33 #x33)
      ;; y
      (121 8 1 6 6 #x33 #x33 #x33 #x1e #xc #xc #x18 #x30)
      ;; z
      (122 8 1 6 6 #x3f #x6 #x1e #x18 #x30 #x3f)
      ;; {
      (123 8 2 10 5 #x7 #xc #xc #xc #xc #x18 #xc #xc #xc #xc #x7)
      ;; |
      (124 8 3 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; }
      (125 8 1 10 5 #x1c #x6 #x6 #x6 #x6 #x3 #x6 #x6 #x6 #x6 #x1c)
      ;; ~
      (126 8 1 10 7 #x3b #x6e)
      ;; ¬
      (172 8 1 5 6 #x3f #x3 #x3)
      ;; °
      (176 8 2 9 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 8 1 7 6 #xc #xc #x3f #xc #xc #x3f)
      ;; µ
      (181 8 1 6 6 #x33 #x33 #x33 #x33 #x33 #x1e #x30 #x30)
      ;; ·
      (183 8 2 6 4 #xf #xf #xf)
      ;; À
      (192 8 1 10 6 #x18 #xc #x0 #x1e #x33 #x3f #x33 #x33 #x33 #x33)
      ;; Á
      (193 8 1 10 6 #xc #x18 #x0 #x1e #x33 #x3f #x33 #x33 #x33 #x33)
      ;; Â
      (194 8 1 10 6 #xc #x1e #x0 #x1e #x33 #x3f #x33 #x33 #x33 #x33)
      ;; Ã
      (195 8 1 10 6 #x1e #x3c #x0 #x1e #x33 #x3f #x33 #x33 #x33 #x33)
      ;; Ä
      (196 8 1 10 6 #x1e #x0 #x1e #x33 #x33 #x3f #x33 #x33 #x33 #x33)
      ;; Å
      (197 8 1 10 6 #xc #x1e #xc #x1e #x33 #x3f #x33 #x33 #x33 #x33)
      ;; Ç
      (199 8 1 9 6 #x1e #x33 #x33 #x30 #x30 #x30 #x33 #x33 #x1e #xc #x18)
      ;; È
      (200 8 1 10 6 #x18 #xc #x0 #x3f #x30 #x3e #x30 #x30 #x30 #x3f)
      ;; É
      (201 8 1 10 6 #xc #x18 #x0 #x3f #x30 #x3e #x30 #x30 #x30 #x3f)
      ;; Ê
      (202 8 1 10 6 #xc #x1e #x0 #x3f #x30 #x3e #x30 #x30 #x30 #x3f)
      ;; Ë
      (203 8 1 10 6 #x1e #x0 #x3f #x30 #x30 #x3e #x30 #x30 #x30 #x3f)
      ;; Ì
      (204 8 1 10 6 #x18 #xc #x0 #x3f #xc #xc #xc #xc #xc #x3f)
      ;; Í
      (205 8 1 10 6 #xc #x18 #x0 #x3f #xc #xc #xc #xc #xc #x3f)
      ;; Î
      (206 8 1 10 6 #xc #x1e #x0 #x3f #xc #xc #xc #xc #xc #x3f)
      ;; Ï
      (207 8 1 10 6 #x1e #x0 #x3f #xc #xc #xc #xc #xc #xc #x3f)
      ;; Ñ
      (209 8 1 10 6 #x1e #x3c #x0 #x33 #x3b #x37 #x37 #x33 #x33 #x33)
      ;; Ò
      (210 8 1 10 6 #x18 #xc #x0 #x1e #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; Ó
      (211 8 1 10 6 #xc #x18 #x0 #x1e #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; Ô
      (212 8 1 10 6 #xc #x1e #x0 #x1e #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; Õ
      (213 8 1 10 6 #x1e #x3c #x0 #x1e #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; Ö
      (214 8 1 10 6 #x1e #x0 #x1e #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; ×
      (215 8 1 6 6 #x33 #x1e #xc #x1e #x33 #x33)
      ;; Ù
      (217 8 1 10 6 #x18 #xc #x0 #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; Ú
      (218 8 1 10 6 #xc #x18 #x0 #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; Û
      (219 8 1 10 6 #xc #x1e #x0 #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; Ü
      (220 8 1 10 6 #x1e #x0 #x33 #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; Ý
      (221 8 1 10 6 #xc #x18 #x0 #x33 #x1e #xc #xc #xc #xc #xc)
      ;; à
      (224 8 1 9 6 #x18 #xc #x0 #x1e #x3 #x1f #x33 #x33 #x1f)
      ;; á
      (225 8 1 9 6 #xc #x18 #x0 #x1e #x3 #x1f #x33 #x33 #x1f)
      ;; â
      (226 8 1 9 6 #xc #x1e #x0 #x1e #x3 #x1f #x33 #x33 #x1f)
      ;; ã
      (227 8 1 9 6 #x1e #x3c #x0 #x1e #x3 #x1f #x33 #x33 #x1f)
      ;; ä
      (228 8 1 8 6 #x1e #x0 #x1e #x3 #x1f #x33 #x33 #x1f)
      ;; å
      (229 8 1 10 6 #xc #x1e #xc #x0 #x1e #x3 #x1f #x33 #x33 #x1f)
      ;; ç
      (231 8 1 6 6 #x1e #x33 #x30 #x30 #x33 #x1e #xc #x18)
      ;; è
      (232 8 1 9 6 #x18 #xc #x0 #x1e #x33 #x3f #x30 #x30 #x1f)
      ;; é
      (233 8 1 9 6 #xc #x18 #x0 #x1e #x33 #x3f #x30 #x30 #x1f)
      ;; ê
      (234 8 1 9 6 #xc #x1e #x0 #x1e #x33 #x3f #x30 #x30 #x1f)
      ;; ë
      (235 8 1 8 6 #x1e #x0 #x1e #x33 #x3f #x30 #x30 #x1f)
      ;; ì
      (236 8 1 9 4 #xc #x6 #x0 #x7 #x3 #x3 #x3 #x3 #x3)
      ;; í
      (237 8 1 9 4 #x6 #xc #x0 #x7 #x3 #x3 #x3 #x3 #x3)
      ;; î
      (238 8 1 9 4 #x6 #xf #x0 #x7 #x3 #x3 #x3 #x3 #x3)
      ;; ï
      (239 8 1 8 4 #xf #x0 #x7 #x3 #x3 #x3 #x3 #x3)
      ;; ñ
      (241 8 1 9 6 #x1e #x3c #x0 #x2e #x3b #x33 #x33 #x33 #x33)
      ;; ò
      (242 8 1 9 6 #x18 #xc #x0 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; ó
      (243 8 1 9 6 #xc #x18 #x0 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; ô
      (244 8 1 9 6 #xc #x1e #x0 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; õ
      (245 8 1 9 6 #x1e #x3c #x0 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; ö
      (246 8 1 8 6 #x1e #x0 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; ù
      (249 8 1 9 6 #x18 #xc #x0 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; ú
      (250 8 1 9 6 #xc #x18 #x0 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; û
      (251 8 1 9 6 #xc #x1e #x0 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; ü
      (252 8 1 8 6 #x1e #x0 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; ý
      (253 8 1 9 6 #xc #x18 #x0 #x33 #x33 #x33 #x1e #xc #xc #x18 #x30)
      ;; ÿ
      (255 8 1 8 6 #x1e #x0 #x33 #x33 #x33 #x1e #xc #xc #x18 #x30)
      ;; α
      (945 8 1 6 6 #x1f #x36 #x36 #x36 #x36 #x1f)
      ;; β
      (946 8 1 8 6 #x1e #x33 #x33 #x3e #x33 #x33 #x33 #x3e #x30 #x30)
      ;; γ
      (947 8 1 8 6 #x33 #x1e #xc #x1e #x33 #x33 #x33 #x1e)
      ;; δ
      (948 8 1 9 6 #xe #x1b #x18 #x18 #xe #x1b #x33 #x33 #x1e)
      ;; ε
      (949 8 1 6 5 #xf #x18 #x1f #x18 #xf)
      ;; λ
      (955 8 1 8 6 #x30 #x30 #x18 #xc #xc #x1e #x33 #x33)
      ;; π
      (960 8 1 6 6 #x3f #x1e #x1e #x1e #x1e #x1e)
      ;; –
      (8211 8 1 5 6 #x3f)
      ;; —
      (8212 8 0 5 8 #xff)
      ;; ‘
      (8216 8 3 10 3 #x7 #x7 #x3 #x6)
      ;; ’
      (8217 8 3 10 3 #x7 #x7 #x3 #x6)
      ;; “
      (8220 8 2 10 4 #xf #xf #xf #xf)
      ;; ”
      (8221 8 2 10 4 #xf #xf #xf #xf)
      ;; …
      (8230 8 0 2 8 #xff #xff)
      ;; ←
      (8592 8 1 7 6 #xc #x18 #x3f #x18 #xc)
      ;; ↑
      (8593 8 1 8 6 #xc #x1e #x3f #xc #xc #xc #xc #xc)
      ;; →
      (8594 8 1 7 6 #xc #x6 #x3f #x6 #xc)
      ;; ↓
      (8595 8 1 8 6 #xc #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↔
      (8596 8 1 8 6 #xc #x6 #x3f #x6 #xc #xc #x18 #x3f #x18 #xc)
      ;; ↳
      (8627 8 1 9 6 #x30 #x30 #x3c #x36 #x3f #x6 #xc)
      ;; ∀
      (8704 8 1 9 6 #x33 #x33 #x33 #x33 #x3f #x33 #x1e #x1e #xc)
      ;; ∂
      (8706 8 1 9 6 #x1c #x6 #x3 #x3 #x1f #x33 #x33 #x33 #x1e)
      ;; ∃
      (8707 8 1 9 6 #x3f #x3 #x3 #x3 #x1f #x3 #x3 #x3 #x3f)
      ;; −
      (8722 8 1 5 6 #x3f)
      ;; ∞
      (8734 8 1 6 6 #x1e #x3f #x3f #x1e)
      ;; ∧
      (8743 8 1 6 6 #xc #x1e #x33)
      ;; ∨
      (8744 8 1 6 6 #x33 #x1e #xc)
      ;; ∩
      (8745 8 1 7 6 #x1e #x33 #x33 #x33 #x33)
      ;; ∪
      (8746 8 1 7 6 #x33 #x33 #x33 #x33 #x1e)
      ;; ∫
      (8747 8 1 9 6 #x7 #xf #xf #xc #xc #xc #xc #x3c #x3c #x38)
      ;; ≠
      (8800 8 1 8 6 #x3 #x6 #x3f #xc #xc #x3f #x18 #x30)
      ;; ≡
      (8801 8 1 7 6 #x3f #x0 #x3f #x0 #x3f)
      ;; ≤
      (8804 8 2 9 5 #x3 #x6 #xc #x18 #xc #x6 #x3 #x0 #x1f)
      ;; ≥
      (8805 8 2 9 5 #x18 #xc #x6 #x3 #x6 #xc #x18 #x0 #x1f)
      ;; ⊂
      (8834 8 1 7 6 #x1f #x30 #x30 #x30 #x1f)
      ;; ⊃
      (8835 8 1 7 6 #x3e #x3 #x3 #x3 #x3e)
      ;; ⊕
      (8853 8 1 7 6 #x1e #x3f #x3f #x3f #x1e)
      ;; ⊗
      (8855 8 1 7 6 #x1e #x3f #x3f #x3f #x1e)
      ;; ⋅
      (8901 8 2 6 4 #xf #xf #xf)
      ;; ▶
      (9654 8 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 8 1 8 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ◊
      (9674 8 1 8 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ⚙
      (9881 8 0 9 9 #x10 #xfe #xfe #xee #x1c7 #xee #xfe #xfe #x10)
      ;; ⚠
      (9888 8 0 10 7 #x8 #x8 #x14 #x14 #x1c #x2a #x2a #x22 #x49 #x7f)
      ;; ✓
      (10003 8 1 7 6 #x3 #x3 #x6 #x36 #x1e #x1c #xc)
      ;; ❚
      (10074 8 2 9 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("Genera CPTFONT Italic" 12 10 2
      ;; the slug, which a character the face lacks draws
      (#f 8 1 9 6 #x3f #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x3f)
      ;; space
      (32 8)
      ;; !
      (33 8 1 9 4 #x1 #x1 #x2 #x2 #x2 #x4 #x4 #x0 #xc)
      ;; "
      (34 8 2 10 5 #x9 #x9 #x12 #x12)
      ;; #
      (35 8 0 9 8 #x11 #x11 #x22 #x7f #x22 #x44 #xfe #x44 #x88 #x88)
      ;; $
      (36 8 0 10 8 #x4 #x1e #x25 #x48 #x48 #x3c #x12 #x92 #xa4 #x78 #x20)
      ;; %
      (37 8 0 9 8 #x1f #x31 #x62 #x4 #x8 #x10 #x20 #x46 #x8c)
      ;; &
      (38 8 0 9 7 #xe #x12 #x12 #xc #x18 #x25 #x42 #x46 #x39)
      ;; '
      (39 8 3 10 3 #x3 #x3 #x1 #x6)
      ;; (
      (40 8 2 10 4 #x1 #x2 #x4 #x4 #x8 #x8 #x8 #x8 #x8 #x4 #x2)
      ;; )
      (41 8 1 10 4 #x4 #x2 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4 #x8)
      ;; *
      (42 8 1 8 5 #x4 #x15 #xe #x4 #xe #x15 #x4)
      ;; +
      (43 8 1 7 5 #x2 #x4 #x1f #x4 #x8)
      ;; ,
      (44 8 0 2 4 #x3 #x3 #x2 #xc)
      ;; -
      (45 8 1 5 6 #x3f)
      ;; .
      (46 8 2 2 2 #x3 #x3)
      ;; /
      (47 8 0 9 8 #x1 #x3 #x6 #xc #x18 #x30 #x60 #xc0 #x80)
      ;; 0
      (48 8 0 9 8 #x1e #x21 #x21 #x4e #x52 #x62 #x84 #x84 #x78)
      ;; 1
      (49 8 0 9 6 #x1 #x7 #x2 #x2 #x4 #x4 #x8 #x8 #x3c)
      ;; 2
      (50 8 0 9 8 #x1e #x21 #x41 #x2 #xc #x30 #x40 #x80 #xfc)
      ;; 3
      (51 8 0 9 8 #x1e #x21 #x1 #x6 #x18 #x4 #x84 #x84 #x78)
      ;; 4
      (52 8 1 9 6 #x1 #x2 #x4 #xa #x12 #x3f #x4 #x8 #x8)
      ;; 5
      (53 8 0 9 8 #x1f #x20 #x40 #x7c #x2 #x2 #x4 #x84 #x78)
      ;; 6
      (54 8 0 9 8 #x7 #x18 #x20 #x40 #x7c #x82 #x82 #x84 #x78)
      ;; 7
      (55 8 0 9 8 #x3f #x1 #x2 #x4 #x8 #x10 #x20 #x40 #x80)
      ;; 8
      (56 8 0 9 8 #x1e #x21 #x41 #x42 #x3c #x42 #x82 #x84 #x78)
      ;; 9
      (57 8 0 9 8 #x1e #x21 #x41 #x41 #x3e #x2 #x4 #x88 #x70)
      ;; :
      (58 8 3 6 3 #x3 #x3 #x0 #x0 #x6 #x6)
      ;; ;
      (59 8 0 6 5 #x3 #x3 #x0 #x0 #x6 #x6 #x4 #x18)
      ;; <
      (60 8 1 8 5 #x1 #x2 #x4 #x8 #x10 #x8 #x4 #x2)
      ;; =
      (61 8 0 6 7 #x3f #x0 #x0 #x7e)
      ;; >
      (62 8 1 8 5 #x8 #x4 #x2 #x1 #x2 #x4 #x8 #x10)
      ;; ?
      (63 8 1 9 6 #xe #x11 #x11 #x2 #xc #x10 #x10 #x0 #x20 #x20)
      ;; @
      (64 8 0 8 7 #xf #x11 #x27 #x29 #x52 #x5c #x41 #x3e)
      ;; A
      (65 8 0 9 8 #x1e #x21 #x21 #x42 #x7e #x42 #x84 #x84 #x84)
      ;; B
      (66 8 0 9 8 #x3e #x21 #x21 #x42 #x7c #x42 #x84 #x84 #xf8)
      ;; C
      (67 8 0 9 8 #x1e #x21 #x21 #x40 #x40 #x40 #x84 #x84 #x78)
      ;; D
      (68 8 0 9 8 #x3e #x11 #x11 #x22 #x22 #x22 #x44 #x44 #xf8)
      ;; E
      (69 8 0 9 7 #x1f #x10 #x10 #x20 #x3e #x20 #x40 #x40 #x7c)
      ;; F
      (70 8 0 9 7 #x1f #x10 #x10 #x20 #x3e #x20 #x40 #x40 #x40)
      ;; G
      (71 8 0 9 8 #x1e #x21 #x21 #x40 #x40 #x4e #x84 #x84 #x78)
      ;; H
      (72 8 0 9 8 #x21 #x21 #x21 #x42 #x7e #x42 #x84 #x84 #x84)
      ;; I
      (73 8 0 9 7 #x1f #x4 #x4 #x8 #x8 #x8 #x10 #x10 #x7c)
      ;; J
      (74 8 0 9 8 #x1 #x1 #x1 #x2 #x2 #x2 #x84 #x84 #x78)
      ;; K
      (75 8 1 9 7 #x11 #x12 #x24 #x28 #x30 #x28 #x44 #x42 #x42)
      ;; L
      (76 8 1 9 5 #x4 #x4 #x4 #x8 #x8 #x8 #x10 #x10 #x1f)
      ;; M
      (77 8 0 9 8 #x21 #x33 #x2d #x4a #x42 #x42 #x84 #x84 #x84)
      ;; N
      (78 8 0 9 8 #x21 #x21 #x31 #x4a #x46 #x42 #x84 #x84 #x84)
      ;; O
      (79 8 0 9 8 #x1e #x21 #x21 #x42 #x42 #x42 #x84 #x84 #x78)
      ;; P
      (80 8 0 9 8 #x3e #x21 #x21 #x42 #x7c #x40 #x80 #x80 #x80)
      ;; Q
      (81 8 0 9 8 #x1e #x21 #x21 #x42 #x42 #x42 #x94 #x88 #x7c)
      ;; R
      (82 8 0 9 8 #x3e #x21 #x21 #x42 #x7c #x50 #x88 #x84 #x82)
      ;; S
      (83 8 0 9 8 #x1e #x21 #x40 #x40 #x3c #x2 #x82 #x84 #x78)
      ;; T
      (84 8 2 9 6 #x3f #x8 #x8 #x10 #x10 #x10 #x20 #x20 #x20)
      ;; U
      (85 8 0 9 8 #x21 #x21 #x21 #x42 #x42 #x42 #x84 #x84 #x78)
      ;; V
      (86 8 1 9 7 #x21 #x21 #x21 #x42 #x42 #x44 #x48 #x48 #x30)
      ;; W
      (87 8 0 9 8 #x21 #x21 #x21 #x42 #x42 #x52 #x94 #xec #x84)
      ;; X
      (88 8 0 9 8 #x21 #x21 #x22 #x14 #x18 #x28 #x44 #x84 #x84)
      ;; Y
      (89 8 2 9 6 #x21 #x21 #x22 #x24 #x18 #x8 #x10 #x10 #x10)
      ;; Z
      (90 8 0 9 8 #x3f #x1 #x2 #x4 #x3c #x20 #x40 #x80 #xfc)
      ;; [
      (91 8 1 10 7 #xf #x8 #x8 #x10 #x10 #x10 #x20 #x20 #x20 #x40 #x78)
      ;; \
      (92 8 1 8 6 #x20 #x30 #x18 #xc #x6 #x3 #x1)
      ;; ]
      (93 8 0 10 7 #xf #x1 #x1 #x2 #x2 #x2 #x4 #x4 #x4 #x8 #x78)
      ;; ^
      (94 8 1 10 6 #xc #x12 #x21)
      ;; _
      (95 8 1 -1 6 #x3f)
      ;; `
      (96 8 4 10 3 #x6 #x6 #x4 #x3)
      ;; a
      (97 8 0 6 7 #x1e #x1 #x3e #x42 #x44 #x3b)
      ;; b
      (98 8 0 9 7 #x10 #x10 #x20 #x3e #x21 #x21 #x42 #x42 #x7c)
      ;; c
      (99 8 1 6 6 #xe #x11 #x20 #x20 #x22 #x1c)
      ;; d
      (100 8 0 9 8 #x1 #x1 #x2 #x3a #x46 #x82 #x84 #x8c #x74)
      ;; e
      (101 8 1 6 6 #xe #x11 #x26 #x38 #x22 #x1c)
      ;; f
      (102 8 0 9 8 #x7 #x8 #x8 #x3e #x10 #x10 #x10 #x20 #x20 #x20 #xc0)
      ;; g
      (103 8 0 6 7 #xd #x13 #x21 #x21 #x22 #x1e #x4 #x78)
      ;; h
      (104 8 1 9 6 #x8 #x8 #x8 #x1e #x11 #x11 #x22 #x22 #x23)
      ;; i
      (105 8 2 9 4 #x1 #x1 #x0 #xe #x2 #x4 #x4 #x9 #xe)
      ;; j
      (106 8 0 9 6 #x1 #x1 #x0 #x3 #x1 #x2 #x2 #x2 #x22 #x24 #x18)
      ;; k
      (107 8 0 9 7 #x18 #x8 #x8 #x13 #x14 #x18 #x24 #x24 #x42)
      ;; l
      (108 8 2 9 4 #x7 #x1 #x2 #x2 #x4 #x4 #x8 #x8 #xe)
      ;; m
      (109 8 0 6 7 #x36 #x2d #x29 #x42 #x42 #x43)
      ;; n
      (110 8 1 6 6 #x16 #x19 #x11 #x21 #x22 #x23)
      ;; o
      (111 8 1 6 6 #xe #x11 #x21 #x21 #x22 #x1c)
      ;; p
      (112 8 0 6 7 #x1e #x11 #x21 #x21 #x32 #x2c #x40 #x40)
      ;; q
      (113 8 1 6 7 #x1f #x21 #x42 #x42 #x44 #x34 #x8 #x8)
      ;; r
      (114 8 1 6 6 #x13 #x1c #x10 #x10 #x20 #x20)
      ;; s
      (115 8 0 6 7 #x1e #x21 #x18 #x6 #x42 #x3c)
      ;; t
      (116 8 1 8 6 #x4 #x8 #x1f #x8 #x10 #x10 #x22 #x1c)
      ;; u
      (117 8 1 6 6 #x11 #x21 #x22 #x22 #x22 #x3d)
      ;; v
      (118 8 1 6 7 #x21 #x42 #x42 #x44 #x28 #x10)
      ;; w
      (119 8 1 6 7 #x21 #x21 #x42 #x52 #x54 #x68)
      ;; x
      (120 8 0 6 7 #x11 #x12 #xc #x18 #x24 #x44)
      ;; y
      (121 8 0 6 8 #x21 #x42 #x42 #x24 #x28 #x10 #x20 #xc0)
      ;; z
      (122 8 0 6 7 #x1f #x2 #xc #x10 #x20 #x7c)
      ;; {
      (123 8 1 10 6 #x3 #x4 #x4 #x8 #x8 #x38 #x8 #x8 #x8 #x8 #x6)
      ;; |
      (124 8 1 10 4 #x1 #x1 #x1 #x2 #x2 #x2 #x4 #x4 #x4 #x8 #x8 #x8)
      ;; }
      (125 8 2 10 6 #x18 #x4 #x4 #x4 #x4 #x7 #x4 #x4 #x8 #x8 #x30)
      ;; ~
      (126 8 1 10 6 #x19 #x26)
      ;; ¬
      (172 8 1 5 6 #x3f #x1 #x1)
      ;; °
      (176 8 2 9 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 8 0 7 6 #x2 #x4 #x1f #x4 #x8 #x3e)
      ;; µ
      (181 8 1 6 6 #x11 #x21 #x22 #x22 #x22 #x3d #x20 #x20)
      ;; ·
      (183 8 2 6 3 #x7 #x7 #x7)
      ;; À
      (192 8 0 10 8 #x30 #x18 #xc #x1e #x21 #x42 #x7e #x42 #x84 #x84)
      ;; Á
      (193 8 0 10 8 #xc #x18 #x30 #x1e #x21 #x42 #x7e #x42 #x84 #x84)
      ;; Â
      (194 8 0 10 8 #x18 #x24 #x42 #x1e #x21 #x42 #x7e #x42 #x84 #x84)
      ;; Ã
      (195 8 0 10 8 #x32 #x4c #x0 #x1e #x21 #x42 #x7e #x42 #x84 #x84)
      ;; Ä
      (196 8 0 10 8 #x24 #x24 #x0 #x1e #x21 #x42 #x7e #x42 #x84 #x84)
      ;; Å
      (197 8 0 10 7 #xc #x12 #x12 #xc #xf #x21 #x3f #x21 #x42 #x42)
      ;; Ç
      (199 8 0 9 8 #x1e #x21 #x21 #x40 #x40 #x40 #x84 #x84 #x78 #x18 #x38)
      ;; È
      (200 8 0 10 7 #x30 #x18 #xc #x1f #x10 #x20 #x3e #x20 #x40 #x7c)
      ;; É
      (201 8 0 10 7 #xc #x18 #x30 #x1f #x10 #x20 #x3e #x20 #x40 #x7c)
      ;; Ê
      (202 8 0 10 7 #x18 #x24 #x42 #x1f #x10 #x20 #x3e #x20 #x40 #x7c)
      ;; Ë
      (203 8 0 10 7 #x24 #x24 #x0 #x1f #x10 #x20 #x3e #x20 #x40 #x7c)
      ;; Ì
      (204 8 0 10 7 #x30 #x18 #xc #x1f #x4 #x8 #x8 #x10 #x10 #x7c)
      ;; Í
      (205 8 0 10 7 #xc #x18 #x30 #x1f #x4 #x8 #x8 #x10 #x10 #x7c)
      ;; Î
      (206 8 0 10 7 #x18 #x24 #x42 #x1f #x4 #x8 #x8 #x10 #x10 #x7c)
      ;; Ï
      (207 8 0 10 7 #x24 #x24 #x0 #x1f #x4 #x8 #x8 #x10 #x10 #x7c)
      ;; Ñ
      (209 8 0 10 8 #x32 #x4c #x0 #x21 #x31 #x4a #x46 #x42 #x84 #x84)
      ;; Ò
      (210 8 0 10 8 #x30 #x18 #xc #x1e #x21 #x42 #x42 #x84 #x84 #x78)
      ;; Ó
      (211 8 0 10 8 #xc #x18 #x30 #x1e #x21 #x42 #x42 #x84 #x84 #x78)
      ;; Ô
      (212 8 0 10 8 #x18 #x24 #x42 #x1e #x21 #x42 #x42 #x84 #x84 #x78)
      ;; Õ
      (213 8 0 10 8 #x32 #x4c #x0 #x1e #x21 #x42 #x42 #x84 #x84 #x78)
      ;; Ö
      (214 8 0 10 8 #x24 #x24 #x0 #x1e #x21 #x42 #x42 #x84 #x84 #x78)
      ;; ×
      (215 8 0 6 7 #x11 #x12 #xc #x18 #x24 #x44)
      ;; Ù
      (217 8 0 10 8 #x30 #x18 #xc #x21 #x21 #x42 #x42 #x84 #x84 #x78)
      ;; Ú
      (218 8 0 10 8 #xc #x18 #x30 #x21 #x21 #x42 #x42 #x84 #x84 #x78)
      ;; Û
      (219 8 0 10 8 #x18 #x24 #x42 #x21 #x21 #x42 #x42 #x84 #x84 #x78)
      ;; Ü
      (220 8 0 10 8 #x24 #x24 #x0 #x21 #x21 #x42 #x42 #x84 #x84 #x78)
      ;; Ý
      (221 8 2 10 6 #x6 #xc #x18 #x21 #x22 #x24 #x18 #x8 #x10 #x10)
      ;; à
      (224 8 0 10 7 #x30 #x18 #xc #x0 #x1e #x1 #x3e #x42 #x44 #x3b)
      ;; á
      (225 8 0 10 7 #xc #x18 #x30 #x0 #x1e #x1 #x3e #x42 #x44 #x3b)
      ;; â
      (226 8 0 10 7 #x18 #x24 #x42 #x0 #x1e #x1 #x3e #x42 #x44 #x3b)
      ;; ã
      (227 8 0 9 7 #x32 #x4c #x0 #x1e #x1 #x3e #x42 #x44 #x3b)
      ;; ä
      (228 8 0 9 7 #x24 #x24 #x0 #x1e #x1 #x3e #x42 #x44 #x3b)
      ;; å
      (229 8 0 10 7 #x18 #x24 #x24 #x18 #x0 #x1e #x3e #x42 #x44 #x3b)
      ;; ç
      (231 8 1 6 6 #xe #x11 #x20 #x20 #x22 #x1c #xc #x1c)
      ;; è
      (232 8 1 10 6 #x18 #xc #x6 #x0 #xe #x11 #x26 #x38 #x22 #x1c)
      ;; é
      (233 8 1 10 6 #x6 #xc #x18 #x0 #xe #x11 #x26 #x38 #x22 #x1c)
      ;; ê
      (234 8 1 10 6 #xc #x12 #x21 #x0 #xe #x11 #x26 #x38 #x22 #x1c)
      ;; ë
      (235 8 1 9 6 #x12 #x12 #x0 #xe #x11 #x26 #x38 #x22 #x1c)
      ;; ì
      (236 8 2 10 4 #xc #x6 #x3 #x0 #xe #x2 #x4 #x4 #x9 #xe)
      ;; í
      (237 8 2 10 4 #x3 #x6 #xc #x0 #xe #x2 #x4 #x4 #x9 #xe)
      ;; î
      (238 8 1 10 6 #xc #x12 #x21 #x0 #x1c #x4 #x8 #x8 #x12 #x1c)
      ;; ï
      (239 8 2 9 4 #x9 #x9 #x0 #xe #x2 #x4 #x4 #x9 #xe)
      ;; ñ
      (241 8 1 9 6 #x19 #x26 #x0 #x16 #x19 #x11 #x21 #x22 #x23)
      ;; ò
      (242 8 1 10 6 #x18 #xc #x6 #x0 #xe #x11 #x21 #x21 #x22 #x1c)
      ;; ó
      (243 8 1 10 6 #x6 #xc #x18 #x0 #xe #x11 #x21 #x21 #x22 #x1c)
      ;; ô
      (244 8 1 10 6 #xc #x12 #x21 #x0 #xe #x11 #x21 #x21 #x22 #x1c)
      ;; õ
      (245 8 1 9 6 #x19 #x26 #x0 #xe #x11 #x21 #x21 #x22 #x1c)
      ;; ö
      (246 8 1 9 6 #x12 #x12 #x0 #xe #x11 #x21 #x21 #x22 #x1c)
      ;; ù
      (249 8 1 10 6 #x18 #xc #x6 #x0 #x11 #x21 #x22 #x22 #x22 #x3d)
      ;; ú
      (250 8 1 10 6 #x6 #xc #x18 #x0 #x11 #x21 #x22 #x22 #x22 #x3d)
      ;; û
      (251 8 1 10 6 #xc #x12 #x21 #x0 #x11 #x21 #x22 #x22 #x22 #x3d)
      ;; ü
      (252 8 1 9 6 #x12 #x12 #x0 #x11 #x21 #x22 #x22 #x22 #x3d)
      ;; ý
      (253 8 0 10 8 #xc #x18 #x30 #x0 #x21 #x42 #x42 #x24 #x28 #x10 #x20 #xc0)
      ;; ÿ
      (255 8 0 9 8 #x24 #x24 #x0 #x21 #x42 #x42 #x24 #x28 #x10 #x20 #xc0)
      ;; combining grave accent
      (768 0 2 10 4 #xc #x6 #x3)
      ;; combining acute accent
      (769 0 4 10 4 #x3 #x6 #xc)
      ;; combining circumflex accent
      (770 0 2 10 6 #xc #x12 #x21)
      ;; combining tilde
      (771 0 2 9 6 #x19 #x26)
      ;; combining macron
      (772 0 2 8 6 #x3f)
      ;; combining breve
      (774 0 2 9 6 #x21 #x1e)
      ;; combining dot above
      (775 0 4 9 2 #x3 #x3)
      ;; combining diaeresis
      (776 0 3 9 4 #x9 #x9)
      ;; combining ring above
      (778 0 3 10 4 #x6 #x9 #x9 #x6)
      ;; combining double acute accent
      (779 0 2 9 6 #x9 #x12 #x24)
      ;; combining caron
      (780 0 2 10 6 #x21 #x12 #xc)
      ;; combining cedilla
      (807 0 3 0 3 #x3 #x7)
      ;; combining ogonek
      (808 0 1 0 3 #x6 #x7)
      ;; combining low line
      (818 0 1 -1 6 #x3f)
      ;; α
      (945 8 1 6 6 #x1d #x22 #x22 #x22 #x22 #x1d)
      ;; β
      (946 8 1 8 6 #x1e #x21 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20)
      ;; γ
      (947 8 1 8 5 #x11 #xa #x4 #xa #x11 #x11 #x11 #xe)
      ;; δ
      (948 8 1 9 6 #xe #x10 #x10 #x8 #xc #x12 #x21 #x21 #x1e)
      ;; ε
      (949 8 2 6 4 #x7 #x8 #xf #x8 #x7)
      ;; λ
      (955 8 1 8 6 #x20 #x20 #x10 #x8 #xc #x12 #x21 #x21)
      ;; π
      (960 8 0 6 7 #x3f #x52 #x12 #x24 #x24 #x24)
      ;; –
      (8211 8 1 5 6 #x3f)
      ;; —
      (8212 8 0 5 8 #xff)
      ;; ‘
      (8216 8 3 10 3 #x3 #x3 #x1 #x6)
      ;; ’
      (8217 8 3 10 3 #x3 #x3 #x1 #x6)
      ;; “
      (8220 8 2 10 5 #x9 #x9 #x12 #x12)
      ;; ”
      (8221 8 2 10 5 #x9 #x9 #x12 #x12)
      ;; …
      (8230 8 0 2 8 #xdb #xdb)
      ;; ←
      (8592 8 1 7 6 #x8 #x10 #x3f #x10 #x8)
      ;; ↑
      (8593 8 1 8 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 8 1 7 6 #x4 #x2 #x3f #x2 #x4)
      ;; ↓
      (8595 8 1 8 5 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 8 0 8 8 #x4 #x2 #x3f #x2 #xc #x30 #x40 #xfc #x40 #x20)
      ;; ↳
      (8627 8 1 9 6 #x20 #x20 #x24 #x22 #x3f #x2 #x4)
      ;; ∀
      (8704 8 1 9 6 #x21 #x21 #x21 #x22 #x3e #x22 #x24 #x28 #x30)
      ;; ∂
      (8706 8 0 9 8 #x1e #x21 #x1 #x2 #x3e #x44 #x84 #x88 #x70)
      ;; ∃
      (8707 8 0 9 7 #x1f #x1 #x1 #x2 #x3e #x2 #x4 #x4 #x7c)
      ;; −
      (8722 8 1 5 5 #x1f)
      ;; ∞
      (8734 8 0 6 7 #x36 #x49 #x49 #x36)
      ;; ∧
      (8743 8 1 6 6 #xc #x12 #x21)
      ;; ∨
      (8744 8 1 6 6 #x21 #x12 #xc)
      ;; ∩
      (8745 8 0 7 8 #x1e #x21 #x42 #x42 #x84 #x84)
      ;; ∪
      (8746 8 0 7 8 #x21 #x21 #x42 #x42 #x84 #x78)
      ;; ∫
      (8747 8 1 9 5 #x3 #x5 #x5 #x4 #x4 #x4 #x4 #x14 #x14 #x18)
      ;; ≠
      (8800 8 0 8 7 #x1 #x2 #x3f #x4 #x8 #x7e #x10 #x20)
      ;; ≡
      (8801 8 0 7 8 #x3f #x0 #x7e #x0 #xfc)
      ;; ≤
      (8804 8 2 9 4 #x1 #x2 #x4 #x8 #x4 #x2 #x1 #x0 #xf)
      ;; ≥
      (8805 8 2 9 4 #x8 #x4 #x2 #x1 #x2 #x4 #x8 #x0 #xf)
      ;; ⊂
      (8834 8 0 7 8 #x1f #x20 #x40 #x40 #x80 #x7c)
      ;; ⊃
      (8835 8 0 7 8 #x3e #x1 #x2 #x2 #x4 #xf8)
      ;; ⊕
      (8853 8 0 7 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 8 0 7 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 8 2 6 3 #x7 #x7 #x7)
      ;; ▶
      (9654 8 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 8 1 8 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ◊
      (9674 8 1 8 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ⚙
      (9881 8 0 9 9 #x10 #xfe #xfe #xee #x1c7 #xee #xfe #xfe #x10)
      ;; ⚠
      (9888 8 0 10 7 #x8 #x8 #x14 #x14 #x1c #x2a #x2a #x22 #x49 #x7f)
      ;; ✓
      (10003 8 1 7 6 #x1 #x1 #x2 #x22 #x14 #x14 #x8)
      ;; ❚
      (10074 8 3 9 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera CPTFONT Bold Italic" 12 10 2
      ;; the slug, which a character the face lacks draws
      (#f 9 1 9 7 #x7f #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x7f)
      ;; space
      (32 9)
      ;; !
      (33 9 1 9 5 #x3 #x3 #x6 #x6 #x6 #xc #xc #x0 #x18)
      ;; "
      (34 9 2 10 6 #x1b #x1b #x36 #x36)
      ;; #
      (35 9 0 9 9 #x33 #x33 #x66 #xff #x66 #xcc #x1fe #xcc #x198 #x198)
      ;; $
      (36 9 0 10 9 #xc #x3e #x6f #xd8 #xd8 #x7c #x36 #x1b6 #x1ec #xf8 #x60)
      ;; %
      (37 9 0 9 9 #x7f #xe3 #x1c6 #xc #x18 #x30 #x60 #xce #x19c)
      ;; &
      (38 9 1 9 7 #x38 #x6c #x6c #x38 #x38 #x6f #x66 #x66 #x3f)
      ;; '
      (39 9 1 10 4 #x7 #x7 #x3 #xe)
      ;; (
      (40 9 2 10 5 #x3 #x6 #xc #xc #x18 #x18 #x18 #x18 #x18 #xc #x6)
      ;; )
      (41 9 1 10 5 #xc #x6 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc #x18)
      ;; *
      (42 9 1 8 6 #xc #x3f #x1e #xc #x1e #x3f #xc)
      ;; +
      (43 9 1 7 6 #x6 #xc #x3f #xc #x18)
      ;; ,
      (44 9 0 2 5 #x7 #x7 #x6 #x1c)
      ;; -
      (45 9 1 5 7 #x7f)
      ;; .
      (46 9 3 2 3 #x7 #x7)
      ;; /
      (47 9 0 9 9 #x3 #x7 #xe #x1c #x38 #x70 #xe0 #x1c0 #x180)
      ;; 0
      (48 9 0 9 9 #x3e #x63 #x63 #xde #xf6 #xe6 #x18c #x18c #xf8)
      ;; 1
      (49 9 0 9 7 #x3 #xf #x6 #x6 #xc #xc #x18 #x18 #x7c)
      ;; 2
      (50 9 0 9 9 #x3e #x63 #xc3 #x6 #x1c #x70 #xc0 #x180 #x1fc)
      ;; 3
      (51 9 0 9 9 #x3e #x63 #x3 #xe #x38 #xc #x18c #x18c #xf8)
      ;; 4
      (52 9 1 9 7 #x3 #x6 #xc #x1e #x36 #x7f #xc #x18 #x18)
      ;; 5
      (53 9 0 9 9 #x3f #x60 #xc0 #xfc #x6 #x6 #xc #x18c #xf8)
      ;; 6
      (54 9 0 9 9 #xf #x38 #x60 #xc0 #xfc #x186 #x186 #x18c #xf8)
      ;; 7
      (55 9 0 9 9 #x7f #x3 #x6 #xc #x18 #x30 #x60 #xc0 #x180)
      ;; 8
      (56 9 0 9 9 #x3e #x63 #xc3 #xc6 #x7c #xc6 #x186 #x18c #xf8)
      ;; 9
      (57 9 0 9 9 #x3e #x63 #xc3 #xc3 #x7e #x6 #xc #x198 #xf0)
      ;; :
      (58 9 3 6 4 #x7 #x7 #x0 #x0 #xe #xe)
      ;; ;
      (59 9 0 6 6 #x7 #x7 #x0 #x0 #xe #xe #xc #x38)
      ;; <
      (60 9 2 8 5 #x3 #x6 #xc #x18 #xc #x6 #x3)
      ;; =
      (61 9 0 6 8 #x7f #x0 #x0 #xfe)
      ;; >
      (62 9 2 8 5 #x18 #xc #x6 #x3 #x6 #xc #x18)
      ;; ?
      (63 9 1 9 7 #x1e #x33 #x33 #x6 #x1c #x30 #x30 #x0 #x60 #x60)
      ;; @
      (64 9 1 8 7 #x3e #x63 #x7f #x7b #x7b #x7f #x60 #x3e)
      ;; A
      (65 9 0 9 9 #x3e #x63 #x63 #xc6 #xfe #xc6 #x18c #x18c #x18c)
      ;; B
      (66 9 0 9 9 #x7e #x63 #x63 #xc6 #xfc #xc6 #x18c #x18c #x1f8)
      ;; C
      (67 9 0 9 9 #x3e #x63 #x63 #xc0 #xc0 #xc0 #x18c #x18c #xf8)
      ;; D
      (68 9 0 9 9 #x7e #x33 #x33 #x66 #x66 #x66 #xcc #xcc #x1f8)
      ;; E
      (69 9 0 9 8 #x3f #x30 #x30 #x60 #x7e #x60 #xc0 #xc0 #xfc)
      ;; F
      (70 9 0 9 8 #x3f #x30 #x30 #x60 #x7e #x60 #xc0 #xc0 #xc0)
      ;; G
      (71 9 0 9 9 #x3e #x63 #x63 #xc0 #xc0 #xde #x18c #x18c #xf8)
      ;; H
      (72 9 0 9 9 #x63 #x63 #x63 #xc6 #xfe #xc6 #x18c #x18c #x18c)
      ;; I
      (73 9 0 9 8 #x3f #xc #xc #x18 #x18 #x18 #x30 #x30 #xfc)
      ;; J
      (74 9 0 9 9 #x3 #x3 #x3 #x6 #x6 #x6 #x18c #x18c #xf8)
      ;; K
      (75 9 1 9 8 #x33 #x36 #x6c #x78 #x70 #x78 #xd8 #xcc #xc6)
      ;; L
      (76 9 1 9 6 #xc #xc #xc #x18 #x18 #x18 #x30 #x30 #x3f)
      ;; M
      (77 9 0 9 9 #x63 #x77 #x7f #xde #xc6 #xc6 #x18c #x18c #x18c)
      ;; N
      (78 9 0 9 9 #x63 #x63 #x73 #xde #xce #xc6 #x18c #x18c #x18c)
      ;; O
      (79 9 0 9 9 #x3e #x63 #x63 #xc6 #xc6 #xc6 #x18c #x18c #xf8)
      ;; P
      (80 9 0 9 9 #x7e #x63 #x63 #xc6 #xfc #xc0 #x180 #x180 #x180)
      ;; Q
      (81 9 0 9 9 #x3e #x63 #x63 #xc6 #xc6 #xc6 #x1bc #x198 #xfc)
      ;; R
      (82 9 0 9 9 #x7e #x63 #x63 #xc6 #xfc #xf0 #x198 #x18c #x186)
      ;; S
      (83 9 0 9 9 #x3e #x63 #xc0 #xc0 #x7c #x6 #x186 #x18c #xf8)
      ;; T
      (84 9 2 9 7 #x7f #x18 #x18 #x30 #x30 #x30 #x60 #x60 #x60)
      ;; U
      (85 9 0 9 9 #x63 #x63 #x63 #xc6 #xc6 #xc6 #x18c #x18c #xf8)
      ;; V
      (86 9 1 9 8 #x63 #x63 #x63 #xc6 #xc6 #xcc #xd8 #xd8 #x70)
      ;; W
      (87 9 0 9 9 #x63 #x63 #x63 #xc6 #xc6 #xf6 #x1bc #x1fc #x18c)
      ;; X
      (88 9 0 9 9 #x63 #x63 #x66 #x3c #x38 #x78 #xcc #x18c #x18c)
      ;; Y
      (89 9 0 9 9 #x63 #x63 #x66 #x6c #x38 #x30 #x60 #xc0 #x180)
      ;; Z
      (90 9 0 9 9 #x7f #x3 #x6 #xc #x7c #x60 #xc0 #x180 #x1fc)
      ;; [
      (91 9 1 10 8 #x1f #x18 #x18 #x30 #x30 #x30 #x60 #x60 #x60 #xc0 #xf8)
      ;; \
      (92 9 1 8 7 #x60 #x70 #x38 #x1c #xe #x7 #x3)
      ;; ]
      (93 9 0 10 8 #x1f #x3 #x3 #x6 #x6 #x6 #xc #xc #xc #x18 #xf8)
      ;; ^
      (94 9 1 10 7 #x1c #x36 #x63)
      ;; _
      (95 9 1 -1 7 #x7f)
      ;; `
      (96 9 4 10 4 #xe #xe #xc #x7)
      ;; a
      (97 9 0 6 8 #x3e #x3 #x7e #xc6 #xcc #x7f)
      ;; b
      (98 9 0 9 8 #x30 #x30 #x60 #x7e #x63 #x63 #xc6 #xc6 #xfc)
      ;; c
      (99 9 1 6 7 #x1e #x33 #x60 #x60 #x66 #x3c)
      ;; d
      (100 9 0 9 9 #x3 #x3 #x6 #x7e #xce #x186 #x18c #x19c #xfc)
      ;; e
      (101 9 1 6 7 #x1e #x33 #x6e #x78 #x66 #x3c)
      ;; f
      (102 9 0 9 9 #xf #x18 #x18 #x7e #x30 #x30 #x30 #x60 #x60 #x60 #x1c0)
      ;; g
      (103 9 0 6 8 #x1f #x37 #x63 #x63 #x66 #x3e #x6 #xfc)
      ;; h
      (104 9 1 9 7 #x18 #x18 #x18 #x3e #x33 #x33 #x66 #x66 #x67)
      ;; i
      (105 9 2 9 5 #x3 #x3 #x0 #x1e #x6 #xc #xc #x1b #x1e)
      ;; j
      (106 9 0 9 7 #x3 #x3 #x0 #x7 #x3 #x6 #x6 #x6 #x66 #x6c #x38)
      ;; k
      (107 9 0 9 8 #x38 #x18 #x18 #x37 #x3c #x38 #x6c #x6c #xc6)
      ;; l
      (108 9 2 9 5 #xf #x3 #x6 #x6 #xc #xc #x18 #x18 #x1e)
      ;; m
      (109 9 0 6 8 #x7e #x7f #x7b #xc6 #xc6 #xc7)
      ;; n
      (110 9 1 6 7 #x3e #x3b #x33 #x63 #x66 #x67)
      ;; o
      (111 9 1 6 7 #x1e #x33 #x63 #x63 #x66 #x3c)
      ;; p
      (112 9 0 6 8 #x3e #x33 #x63 #x63 #x76 #x7c #xc0 #xc0)
      ;; q
      (113 9 1 6 8 #x3f #x63 #xc6 #xc6 #xcc #x7c #x18 #x18)
      ;; r
      (114 9 1 6 7 #x37 #x3c #x30 #x30 #x60 #x60)
      ;; s
      (115 9 0 6 8 #x3e #x63 #x38 #xe #xc6 #x7c)
      ;; t
      (116 9 1 8 7 #xc #x18 #x3f #x18 #x30 #x30 #x66 #x3c)
      ;; u
      (117 9 1 6 7 #x33 #x63 #x66 #x66 #x66 #x7f)
      ;; v
      (118 9 1 6 8 #x63 #xc6 #xc6 #xcc #x78 #x30)
      ;; w
      (119 9 1 6 8 #x63 #x63 #xc6 #xf6 #xfc #xf8)
      ;; x
      (120 9 0 6 8 #x33 #x36 #x1c #x38 #x6c #xcc)
      ;; y
      (121 9 0 6 9 #x63 #xc6 #xc6 #x6c #x78 #x30 #x60 #x1c0)
      ;; z
      (122 9 0 6 8 #x3f #x6 #x1c #x30 #x60 #xfc)
      ;; {
      (123 9 1 10 7 #x7 #xc #xc #x18 #x18 #x78 #x18 #x18 #x18 #x18 #xe)
      ;; |
      (124 9 1 10 5 #x3 #x3 #x3 #x6 #x6 #x6 #xc #xc #xc #x18 #x18 #x18)
      ;; }
      (125 9 2 10 7 #x38 #xc #xc #xc #xc #xf #xc #xc #x18 #x18 #x70)
      ;; ~
      (126 9 1 10 7 #x3b #x6e)
      ;; ¬
      (172 9 1 5 7 #x7f #x3 #x3)
      ;; °
      (176 9 2 9 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 0 7 7 #x6 #xc #x3f #xc #x18 #x7e)
      ;; µ
      (181 9 1 6 7 #x33 #x63 #x66 #x66 #x66 #x7f #x60 #x60)
      ;; ·
      (183 9 2 6 4 #xf #xf #xf)
      ;; À
      (192 9 0 10 9 #x60 #x30 #x0 #x3e #x63 #xc6 #xfe #xc6 #x18c #x18c)
      ;; Á
      (193 9 0 10 9 #x30 #x60 #x0 #x3e #x63 #xc6 #xfe #xc6 #x18c #x18c)
      ;; Â
      (194 9 0 10 9 #x30 #x78 #x0 #x3e #x63 #xc6 #xfe #xc6 #x18c #x18c)
      ;; Ã
      (195 9 0 10 9 #x78 #xf0 #x0 #x3e #x63 #xc6 #xfe #xc6 #x18c #x18c)
      ;; Ä
      (196 9 0 10 9 #x78 #x0 #x3e #x63 #xc6 #xfe #xc6 #x18c #x18c #x18c)
      ;; Å
      (197 9 0 10 9 #x30 #x78 #x30 #x3e #x63 #xc6 #xfe #xc6 #x18c #x18c)
      ;; Ç
      (199 9 0 9 9 #x3e #x63 #x63 #xc0 #xc0 #xc0 #x18c #x18c #xf8 #x30 #x60)
      ;; È
      (200 9 0 10 8 #x30 #x18 #x0 #x3f #x30 #x60 #x7e #x60 #xc0 #xfc)
      ;; É
      (201 9 0 10 8 #x18 #x30 #x0 #x3f #x30 #x60 #x7e #x60 #xc0 #xfc)
      ;; Ê
      (202 9 0 10 8 #x18 #x3c #x0 #x3f #x30 #x60 #x7e #x60 #xc0 #xfc)
      ;; Ë
      (203 9 0 10 8 #x3c #x0 #x3f #x30 #x60 #x7e #x60 #xc0 #xc0 #xfc)
      ;; Ì
      (204 9 0 10 8 #x30 #x18 #x0 #x3f #xc #x18 #x18 #x30 #x30 #xfc)
      ;; Í
      (205 9 0 10 8 #x18 #x30 #x0 #x3f #xc #x18 #x18 #x30 #x30 #xfc)
      ;; Î
      (206 9 0 10 8 #x18 #x3c #x0 #x3f #xc #x18 #x18 #x30 #x30 #xfc)
      ;; Ï
      (207 9 0 10 8 #x3c #x0 #x3f #xc #xc #x18 #x18 #x30 #x30 #xfc)
      ;; Ñ
      (209 9 0 10 9 #x78 #xf0 #x0 #x63 #x73 #xde #xce #xc6 #x18c #x18c)
      ;; Ò
      (210 9 0 10 9 #x60 #x30 #x0 #x3e #x63 #xc6 #xc6 #x18c #x18c #xf8)
      ;; Ó
      (211 9 0 10 9 #x30 #x60 #x0 #x3e #x63 #xc6 #xc6 #x18c #x18c #xf8)
      ;; Ô
      (212 9 0 10 9 #x30 #x78 #x0 #x3e #x63 #xc6 #xc6 #x18c #x18c #xf8)
      ;; Õ
      (213 9 0 10 9 #x78 #xf0 #x0 #x3e #x63 #xc6 #xc6 #x18c #x18c #xf8)
      ;; Ö
      (214 9 0 10 9 #x78 #x0 #x3e #x63 #x63 #xc6 #xc6 #x18c #x18c #xf8)
      ;; ×
      (215 9 0 6 8 #x33 #x36 #x1c #x38 #x6c #xcc)
      ;; Ù
      (217 9 0 10 9 #x60 #x30 #x0 #x63 #x63 #xc6 #xc6 #x18c #x18c #xf8)
      ;; Ú
      (218 9 0 10 9 #x30 #x60 #x0 #x63 #x63 #xc6 #xc6 #x18c #x18c #xf8)
      ;; Û
      (219 9 0 10 9 #x30 #x78 #x0 #x63 #x63 #xc6 #xc6 #x18c #x18c #xf8)
      ;; Ü
      (220 9 0 10 9 #x78 #x0 #x63 #x63 #x63 #xc6 #xc6 #x18c #x18c #xf8)
      ;; Ý
      (221 9 0 10 9 #x30 #x60 #x0 #x63 #x6c #x38 #x30 #x60 #xc0 #x180)
      ;; à
      (224 9 0 9 8 #x30 #x18 #x0 #x3e #x3 #x7e #xc6 #xcc #x7f)
      ;; á
      (225 9 0 9 8 #x18 #x30 #x0 #x3e #x3 #x7e #xc6 #xcc #x7f)
      ;; â
      (226 9 0 9 8 #x18 #x3c #x0 #x3e #x3 #x7e #xc6 #xcc #x7f)
      ;; ã
      (227 9 0 9 8 #x3c #x78 #x0 #x3e #x3 #x7e #xc6 #xcc #x7f)
      ;; ä
      (228 9 0 8 8 #x3c #x0 #x3e #x3 #x7e #xc6 #xcc #x7f)
      ;; å
      (229 9 0 10 8 #x18 #x3c #x18 #x0 #x3e #x3 #x7e #xc6 #xcc #x7f)
      ;; ç
      (231 9 1 6 7 #x1e #x33 #x60 #x60 #x66 #x3c #x18 #x30)
      ;; è
      (232 9 1 9 7 #x30 #x18 #x0 #x1e #x33 #x6e #x78 #x66 #x3c)
      ;; é
      (233 9 1 9 7 #x18 #x30 #x0 #x1e #x33 #x6e #x78 #x66 #x3c)
      ;; ê
      (234 9 1 9 7 #x18 #x3c #x0 #x1e #x33 #x6e #x78 #x66 #x3c)
      ;; ë
      (235 9 1 8 7 #x3c #x0 #x1e #x33 #x6e #x78 #x66 #x3c)
      ;; ì
      (236 9 2 9 5 #x18 #xc #x0 #x1e #x6 #xc #xc #x1b #x1e)
      ;; í
      (237 9 2 9 5 #xc #x18 #x0 #x1e #x6 #xc #xc #x1b #x1e)
      ;; î
      (238 9 2 9 5 #xc #x1e #x0 #x1e #x6 #xc #xc #x1b #x1e)
      ;; ï
      (239 9 2 8 5 #x1e #x0 #x1e #x6 #xc #xc #x1b #x1e)
      ;; ñ
      (241 9 1 9 7 #x3c #x78 #x0 #x3e #x3b #x33 #x63 #x66 #x67)
      ;; ò
      (242 9 1 9 7 #x30 #x18 #x0 #x1e #x33 #x63 #x63 #x66 #x3c)
      ;; ó
      (243 9 1 9 7 #x18 #x30 #x0 #x1e #x33 #x63 #x63 #x66 #x3c)
      ;; ô
      (244 9 1 9 7 #x18 #x3c #x0 #x1e #x33 #x63 #x63 #x66 #x3c)
      ;; õ
      (245 9 1 9 7 #x3c #x78 #x0 #x1e #x33 #x63 #x63 #x66 #x3c)
      ;; ö
      (246 9 1 8 7 #x3c #x0 #x1e #x33 #x63 #x63 #x66 #x3c)
      ;; ù
      (249 9 1 9 7 #x30 #x18 #x0 #x33 #x63 #x66 #x66 #x66 #x7f)
      ;; ú
      (250 9 1 9 7 #x18 #x30 #x0 #x33 #x63 #x66 #x66 #x66 #x7f)
      ;; û
      (251 9 1 9 7 #x18 #x3c #x0 #x33 #x63 #x66 #x66 #x66 #x7f)
      ;; ü
      (252 9 1 8 7 #x3c #x0 #x33 #x63 #x66 #x66 #x66 #x7f)
      ;; ý
      (253 9 0 9 9 #x30 #x60 #x0 #x63 #xc6 #xc6 #x6c #x78 #x30 #x60 #x1c0)
      ;; ÿ
      (255 9 0 8 9 #x78 #x0 #x63 #xc6 #xc6 #x6c #x78 #x30 #x60 #x1c0)
      ;; α
      (945 9 1 6 7 #x3f #x66 #x66 #x66 #x66 #x3f)
      ;; β
      (946 9 1 8 7 #x3e #x63 #x63 #x7e #x63 #x63 #x63 #x7e #x60 #x60)
      ;; γ
      (947 9 1 8 6 #x33 #x1e #xc #x1e #x33 #x33 #x33 #x1e)
      ;; δ
      (948 9 1 9 7 #x1e #x30 #x30 #x18 #x1c #x36 #x63 #x63 #x3e)
      ;; ε
      (949 9 2 6 5 #xf #x18 #x1f #x18 #xf)
      ;; λ
      (955 9 1 8 7 #x60 #x60 #x30 #x18 #x1c #x36 #x63 #x63)
      ;; π
      (960 9 0 6 8 #x7f #xf6 #x36 #x6c #x6c #x6c)
      ;; –
      (8211 9 1 5 7 #x7f)
      ;; —
      (8212 9 0 5 9 #x1ff)
      ;; ‘
      (8216 9 1 10 4 #x7 #x7 #x3 #xe)
      ;; ’
      (8217 9 1 10 4 #x7 #x7 #x3 #xe)
      ;; “
      (8220 9 2 10 6 #x1b #x1b #x36 #x36)
      ;; ”
      (8221 9 2 10 6 #x1b #x1b #x36 #x36)
      ;; …
      (8230 9 0 2 9 #x1ff #x1ff)
      ;; ←
      (8592 9 1 7 7 #x18 #x30 #x7f #x30 #x18)
      ;; ↑
      (8593 9 1 8 6 #xc #x1e #x3f #xc #xc #xc #xc #xc)
      ;; →
      (8594 9 1 7 7 #xc #x6 #x7f #x6 #xc)
      ;; ↓
      (8595 9 1 8 6 #xc #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↔
      (8596 9 0 8 9 #xc #x6 #x7f #x6 #x1c #x70 #xc0 #x1fc #xc0 #x60)
      ;; ↳
      (8627 9 1 9 7 #x60 #x60 #x6c #x66 #x7f #x6 #xc)
      ;; ∀
      (8704 9 1 9 7 #x63 #x63 #x63 #x66 #x7e #x66 #x6c #x78 #x70)
      ;; ∂
      (8706 9 0 9 9 #x3e #x63 #x3 #x6 #x7e #xcc #x18c #x198 #xf0)
      ;; ∃
      (8707 9 0 9 8 #x3f #x3 #x3 #x6 #x7e #x6 #xc #xc #xfc)
      ;; −
      (8722 9 1 5 6 #x3f)
      ;; ∞
      (8734 9 0 6 8 #x7e #xdb #xdb #x7e)
      ;; ∧
      (8743 9 1 6 7 #x1c #x36 #x63)
      ;; ∨
      (8744 9 1 6 7 #x63 #x36 #x1c)
      ;; ∩
      (8745 9 0 7 9 #x3e #x63 #xc6 #xc6 #x18c #x18c)
      ;; ∪
      (8746 9 0 7 9 #x63 #x63 #xc6 #xc6 #x18c #xf8)
      ;; ∫
      (8747 9 1 9 6 #x7 #xf #xf #xc #xc #xc #xc #x3c #x3c #x38)
      ;; ≠
      (8800 9 0 8 8 #x3 #x6 #x7f #xc #x18 #xfe #x30 #x60)
      ;; ≡
      (8801 9 0 7 9 #x7f #x0 #xfe #x0 #x1fc)
      ;; ≤
      (8804 9 2 9 5 #x3 #x6 #xc #x18 #xc #x6 #x3 #x0 #x1f)
      ;; ≥
      (8805 9 2 9 5 #x18 #xc #x6 #x3 #x6 #xc #x18 #x0 #x1f)
      ;; ⊂
      (8834 9 0 7 9 #x3f #x60 #xc0 #xc0 #x180 #xfc)
      ;; ⊃
      (8835 9 0 7 9 #x7e #x3 #x6 #x6 #xc #x1f8)
      ;; ⊕
      (8853 9 0 7 8 #x3c #x7e #xdb #xff #xdb #x7e #x3c)
      ;; ⊗
      (8855 9 0 7 8 #x3c #x66 #xff #xdb #xff #x66 #x3c)
      ;; ⋅
      (8901 9 2 6 4 #xf #xf #xf)
      ;; ▶
      (9654 9 2 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 9 1 8 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ◊
      (9674 9 1 8 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ⚙
      (9881 9 0 9 9 #x10 #xfe #xfe #xee #x1c7 #xee #xfe #xfe #x10)
      ;; ⚠
      (9888 9 0 10 9 #x10 #x10 #x28 #x28 #x54 #x54 #x92 #x82 #x111 #x1ff)
      ;; ✓
      (10003 9 1 7 7 #x3 #x3 #x6 #x66 #x3c #x3c #x18)
      ;; ❚
      (10074 9 2 9 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("Genera JESS13" 13 11 2
      ;; the slug, which a character the face lacks draws
      (#f 7 1 11 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x1f)
      ;; space
      (32 7)
      ;; !
      (33 6 2 11 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x0 #x1 #x1)
      ;; "
      (34 7 1 11 5 #x9 #x1b #x12 #x12)
      ;; #
      (35 9 1 10 8 #x12 #x12 #x12 #x7f #x24 #x24 #x24 #xfe #x48 #x48 #x48)
      ;; $
      (36 9 1 11 7 #x8 #x1e #x29 #x48 #x48 #x3e #x9 #x9 #x4a #x3c #x8)
      ;; %
      (37 9 0 11 8 #x63 #x9d #x92 #x64 #x4 #x8 #x10 #x16 #x29 #x49 #x46)
      ;; &
      (38 9 1 11 7 #x38 #x44 #x44 #x44 #x28 #x18 #x28 #x45 #x42 #x46 #x39)
      ;; '
      (39 4 1 11 2 #x3 #x3 #x1 #x2)
      ;; (
      (40 7 2 11 3 #x1 #x2 #x2 #x4 #x4 #x4 #x4 #x4 #x4 #x2 #x2 #x1)
      ;; )
      (41 7 1 11 3 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4)
      ;; *
      (42 9 1 8 7 #x8 #x49 #x2a #x1c #x1c #x2a #x49 #x8)
      ;; +
      (43 9 1 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8)
      ;; ,
      (44 6 0 2 3 #x3 #x3 #x2 #x4)
      ;; -
      (45 9 1 5 7 #x7f)
      ;; .
      (46 6 1 2 2 #x3 #x3)
      ;; /
      (47 9 2 11 6 #x1 #x3 #x2 #x6 #x4 #xc #x8 #x18 #x10 #x30 #x20 #x20)
      ;; 0
      (48 9 1 11 7 #x1e #x21 #x41 #x43 #x45 #x49 #x51 #x61 #x41 #x42 #x3c)
      ;; 1
      (49 9 2 11 5 #x4 #x4 #x1c #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; 2
      (50 9 1 11 7 #x1e #x21 #x41 #x1 #x2 #x4 #x18 #x20 #x40 #x40 #x7f)
      ;; 3
      (51 9 1 11 7 #x1e #x21 #x41 #x1 #x2 #x1e #x1 #x1 #x1 #x2 #x7c)
      ;; 4
      (52 9 1 11 7 #x2 #x6 #xa #x12 #x22 #x42 #x7f #x2 #x2 #x2 #x2)
      ;; 5
      (53 9 1 11 7 #x1f #x20 #x20 #x40 #x7e #x1 #x1 #x1 #x1 #x42 #x3c)
      ;; 6
      (54 9 1 11 7 #x1e #x20 #x40 #x40 #x5e #x61 #x41 #x41 #x41 #x42 #x3c)
      ;; 7
      (55 9 1 11 7 #x7f #x41 #x1 #x1 #x2 #x4 #x8 #x8 #x10 #x10 #x10)
      ;; 8
      (56 9 1 11 7 #x1e #x21 #x41 #x42 #x34 #x1e #x21 #x41 #x41 #x42 #x3c)
      ;; 9
      (57 9 1 11 7 #x1e #x21 #x41 #x41 #x41 #x43 #x3d #x1 #x1 #x2 #x3c)
      ;; :
      (58 7 2 6 2 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; ;
      (59 6 0 6 3 #x3 #x3 #x0 #x0 #x3 #x3 #x2 #x4)
      ;; <
      (60 9 1 9 7 #x1 #x6 #x8 #x30 #x40 #x30 #x8 #x6 #x1)
      ;; =
      (61 9 1 6 7 #x7f #x0 #x0 #x7f)
      ;; >
      (62 9 1 9 7 #x40 #x30 #x8 #x6 #x1 #x6 #x8 #x30 #x40)
      ;; ?
      (63 9 1 11 7 #x3e #x41 #x41 #x1 #x2 #x4 #x8 #x8 #x0 #x0 #x8)
      ;; @
      (64 9 1 8 7 #x1e #x21 #x5d #x55 #x55 #x5e #x40 #x3e)
      ;; A
      (65 9 1 11 7 #x4 #xc #x12 #x12 #x21 #x21 #x3f #x41 #x41 #x41 #x41)
      ;; B
      (66 9 1 11 7 #x7e #x41 #x41 #x41 #x42 #x7e #x41 #x41 #x41 #x42 #x7c)
      ;; C
      (67 8 1 11 6 #xe #x11 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x21 #x1e)
      ;; D
      (68 9 1 11 7 #x7e #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x7c)
      ;; E
      (69 8 1 11 6 #x3f #x20 #x20 #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x3f)
      ;; F
      (70 8 1 11 6 #x3f #x20 #x20 #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x20)
      ;; G
      (71 9 1 11 7 #x1e #x21 #x40 #x40 #x40 #x47 #x41 #x41 #x41 #x42 #x3c)
      ;; H
      (72 9 1 11 7 #x41 #x41 #x41 #x41 #x41 #x7f #x41 #x41 #x41 #x41 #x41)
      ;; I
      (73 7 1 11 5 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; J
      (74 9 1 11 6 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x21 #x21 #x1e)
      ;; K
      (75 9 1 11 7 #x41 #x42 #x44 #x48 #x50 #x60 #x50 #x48 #x44 #x42 #x41)
      ;; L
      (76 8 1 11 6 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; M
      (77 9 1 11 7 #x41 #x41 #x63 #x55 #x55 #x49 #x49 #x41 #x41 #x41 #x41)
      ;; N
      (78 9 1 11 7 #x41 #x61 #x51 #x51 #x49 #x49 #x45 #x45 #x43 #x41 #x41)
      ;; O
      (79 9 1 11 7 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x3c)
      ;; P
      (80 9 1 11 7 #x7e #x41 #x41 #x41 #x42 #x7c #x40 #x40 #x40 #x40 #x40)
      ;; Q
      (81 9 1 11 7 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x41 #x59 #x46 #x3e #x1)
      ;; R
      (82 9 1 11 7 #x7e #x41 #x41 #x41 #x42 #x7c #x50 #x48 #x44 #x42 #x41)
      ;; S
      (83 9 1 11 7 #x1e #x21 #x40 #x40 #x40 #x3e #x1 #x1 #x1 #x42 #x3c)
      ;; T
      (84 9 1 11 7 #x7f #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; U
      (85 9 1 11 7 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; V
      (86 9 1 11 7 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x22 #x24 #x18 #x10)
      ;; W
      (87 12 1 11 10 #x201 #x201 #x201 #x201 #x221 #x222 #x222 #x254 #x154
        #x198 #x110)
      ;; X
      (88 9 1 11 7 #x41 #x41 #x22 #x22 #x14 #x8 #x14 #x22 #x22 #x41 #x41)
      ;; Y
      (89 9 1 11 7 #x41 #x41 #x22 #x22 #x14 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; Z
      (90 9 1 11 7 #x7f #x2 #x2 #x4 #x4 #x8 #x10 #x10 #x20 #x20 #x7f)
      ;; [
      (91 7 3 11 3 #x7 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x7)
      ;; \
      (92 9 2 11 6 #x20 #x20 #x10 #x10 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ]
      (93 7 1 11 3 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x7)
      ;; ^
      (94 9 1 11 7 #x8 #x14 #x22 #x41)
      ;; _
      (95 9 1 -1 7 #x7f)
      ;; `
      (96 4 1 11 2 #x1 #x2 #x3 #x3)
      ;; a
      (97 8 1 7 6 #x1e #x21 #x3 #x1d #x21 #x23 #x1d)
      ;; b
      (98 8 1 11 6 #x20 #x20 #x20 #x20 #x2e #x31 #x21 #x21 #x21 #x22 #x3c)
      ;; c
      (99 8 1 7 6 #xe #x11 #x20 #x20 #x20 #x21 #x1e)
      ;; d
      (100 8 1 11 6 #x1 #x1 #x1 #x1 #xf #x11 #x21 #x21 #x21 #x23 #x1d)
      ;; e
      (101 8 1 7 6 #xe #x11 #x22 #x3c #x20 #x21 #x1e)
      ;; f
      (102 6 1 11 6 #x7 #x8 #x10 #x10 #x3e #x10 #x10 #x10 #x10 #x10 #x10)
      ;; g
      (103 8 1 7 6 #xe #x11 #x21 #x21 #x23 #x1d #x1 #x22 #x1c)
      ;; h
      (104 8 1 11 6 #x20 #x20 #x20 #x20 #x26 #x29 #x31 #x21 #x21 #x21 #x21)
      ;; i
      (105 5 1 11 2 #x1 #x1 #x0 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; j
      (106 6 0 11 4 #x1 #x1 #x0 #x0 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #xc)
      ;; k
      (107 8 1 11 6 #x20 #x20 #x20 #x20 #x21 #x22 #x2c #x38 #x24 #x22 #x21)
      ;; l
      (108 5 1 11 2 #x3 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; m
      (109 13 1 7 11 #x4c6 #x529 #x631 #x421 #x421 #x421 #x421)
      ;; n
      (110 8 1 7 6 #x26 #x29 #x31 #x21 #x21 #x21 #x21)
      ;; o
      (111 8 1 7 6 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; p
      (112 8 1 7 6 #x2e #x31 #x21 #x21 #x21 #x22 #x3c #x20 #x20)
      ;; q
      (113 8 1 7 6 #xf #x11 #x21 #x21 #x21 #x23 #x1d #x1 #x1)
      ;; r
      (114 7 1 7 6 #x26 #x29 #x30 #x20 #x20 #x20 #x20)
      ;; s
      (115 8 1 7 6 #xe #x11 #x20 #x1e #x1 #x22 #x1c)
      ;; t
      (116 7 1 9 6 #x10 #x10 #x3c #x10 #x10 #x10 #x11 #x12 #xc)
      ;; u
      (117 8 1 7 6 #x21 #x21 #x21 #x21 #x23 #x25 #x19)
      ;; v
      (118 9 1 7 7 #x41 #x41 #x42 #x22 #x24 #x18 #x10)
      ;; w
      (119 11 1 7 9 #x101 #x111 #x111 #x111 #xaa #xcc #x88)
      ;; x
      (120 8 0 7 7 #x31 #xa #xc #x8 #x14 #x24 #x43)
      ;; y
      (121 8 0 7 7 #x21 #x21 #x21 #x22 #x12 #xc #x8 #x10 #x60)
      ;; z
      (122 9 1 7 7 #x3f #x42 #x4 #x8 #x10 #x21 #x7e)
      ;; {
      (123 9 1 11 7 #x7 #x8 #x8 #x8 #x18 #x70 #x18 #x8 #x8 #x8 #x7)
      ;; |
      (124 9 4 11 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; }
      (125 9 1 11 7 #x70 #x8 #x8 #x8 #xc #x7 #xc #x8 #x8 #x8 #x70)
      ;; ~
      (126 9 1 10 6 #x19 #x26)
      ;; ¬
      (172 9 1 5 7 #x7f #x1 #x1)
      ;; °
      (176 6 1 11 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 1 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8 #x7f)
      ;; µ
      (181 8 1 7 6 #x21 #x21 #x21 #x21 #x23 #x25 #x19 #x20 #x20)
      ;; ·
      (183 8 2 6 4 #x6 #xf #xf #x6)
      ;; À
      (192 9 1 11 7 #x10 #x8 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41)
      ;; Á
      (193 9 1 11 7 #x8 #x10 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41)
      ;; Â
      (194 9 1 11 7 #x10 #x28 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41)
      ;; Ã
      (195 9 1 11 7 #x14 #x28 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41)
      ;; Ä
      (196 9 1 11 7 #x28 #x0 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41)
      ;; Å
      (197 9 1 11 7 #x10 #x28 #x10 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41)
      ;; Ç
      (199 8 1 11 6 #xe #x11 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x21 #x1e #x4
        #x8)
      ;; È
      (200 8 1 11 6 #x8 #x4 #x3f #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x3f)
      ;; É
      (201 8 1 11 6 #x4 #x8 #x3f #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x3f)
      ;; Ê
      (202 8 1 11 6 #x8 #x14 #x3f #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x3f)
      ;; Ë
      (203 8 1 11 6 #x14 #x0 #x3f #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x3f)
      ;; Ì
      (204 7 1 11 5 #x8 #x4 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Í
      (205 7 1 11 5 #x4 #x8 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Î
      (206 7 1 11 5 #x8 #x14 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Ï
      (207 7 1 11 5 #x14 #x0 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Ñ
      (209 9 1 11 7 #x14 #x28 #x41 #x61 #x51 #x49 #x45 #x45 #x43 #x41 #x41)
      ;; Ò
      (210 9 1 11 7 #x10 #x8 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x42 #x3c)
      ;; Ó
      (211 9 1 11 7 #x8 #x10 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x42 #x3c)
      ;; Ô
      (212 9 1 11 7 #x10 #x28 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x42 #x3c)
      ;; Õ
      (213 9 1 11 7 #x14 #x28 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x42 #x3c)
      ;; Ö
      (214 9 1 11 7 #x28 #x0 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x42 #x3c)
      ;; ×
      (215 8 0 7 7 #x31 #xa #xc #x8 #x14 #x24 #x43)
      ;; Ù
      (217 9 1 11 7 #x10 #x8 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ú
      (218 9 1 11 7 #x8 #x10 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Û
      (219 9 1 11 7 #x10 #x28 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ü
      (220 9 1 11 7 #x28 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ý
      (221 9 1 11 7 #x8 #x10 #x41 #x22 #x14 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; à
      (224 8 1 10 6 #x8 #x4 #x0 #x1e #x21 #x3 #x1d #x21 #x23 #x1d)
      ;; á
      (225 8 1 10 6 #x4 #x8 #x0 #x1e #x21 #x3 #x1d #x21 #x23 #x1d)
      ;; â
      (226 8 1 10 6 #x8 #x14 #x0 #x1e #x21 #x3 #x1d #x21 #x23 #x1d)
      ;; ã
      (227 8 1 10 6 #xa #x14 #x0 #x1e #x21 #x3 #x1d #x21 #x23 #x1d)
      ;; ä
      (228 8 1 9 6 #x14 #x0 #x1e #x21 #x3 #x1d #x21 #x23 #x1d)
      ;; å
      (229 8 1 11 6 #x8 #x14 #x8 #x0 #x1e #x21 #x3 #x1d #x21 #x23 #x1d)
      ;; ç
      (231 8 1 7 6 #xe #x11 #x20 #x20 #x20 #x21 #x1e #x4 #x8)
      ;; è
      (232 8 1 10 6 #x8 #x4 #x0 #xe #x11 #x22 #x3c #x20 #x21 #x1e)
      ;; é
      (233 8 1 10 6 #x4 #x8 #x0 #xe #x11 #x22 #x3c #x20 #x21 #x1e)
      ;; ê
      (234 8 1 10 6 #x8 #x14 #x0 #xe #x11 #x22 #x3c #x20 #x21 #x1e)
      ;; ë
      (235 8 1 9 6 #x14 #x0 #xe #x11 #x22 #x3c #x20 #x21 #x1e)
      ;; ì
      (236 5 1 10 2 #x2 #x1 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; í
      (237 5 1 10 2 #x1 #x2 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; î
      (238 5 0 10 3 #x2 #x5 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ï
      (239 5 0 9 3 #x5 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ñ
      (241 8 1 10 6 #xa #x14 #x0 #x26 #x29 #x31 #x21 #x21 #x21 #x21)
      ;; ò
      (242 8 1 10 6 #x8 #x4 #x0 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; ó
      (243 8 1 10 6 #x4 #x8 #x0 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; ô
      (244 8 1 10 6 #x8 #x14 #x0 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; õ
      (245 8 1 10 6 #xa #x14 #x0 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; ö
      (246 8 1 9 6 #x14 #x0 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; ù
      (249 8 1 10 6 #x8 #x4 #x0 #x21 #x21 #x21 #x21 #x23 #x25 #x19)
      ;; ú
      (250 8 1 10 6 #x4 #x8 #x0 #x21 #x21 #x21 #x21 #x23 #x25 #x19)
      ;; û
      (251 8 1 10 6 #x8 #x14 #x0 #x21 #x21 #x21 #x21 #x23 #x25 #x19)
      ;; ü
      (252 8 1 9 6 #x14 #x0 #x21 #x21 #x21 #x21 #x23 #x25 #x19)
      ;; ý
      (253 8 0 10 7 #x8 #x10 #x0 #x21 #x21 #x21 #x22 #x12 #xc #x8 #x10 #x60)
      ;; ÿ
      (255 8 0 9 7 #x28 #x0 #x21 #x21 #x21 #x22 #x12 #xc #x8 #x10 #x60)
      ;; α
      (945 9 1 7 8 #x2 #x62 #x94 #x88 #x88 #x94 #x63)
      ;; β
      (946 9 2 9 6 #xe #x11 #x11 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20)
      ;; γ
      (947 9 1 7 7 #x41 #x22 #x14 #x18 #x10 #x30 #x30 #x30 #x20)
      ;; δ
      (948 9 1 11 7 #x1c #x22 #x21 #x20 #x10 #xc #x12 #x21 #x41 #x41 #x3e)
      ;; ε
      (949 9 2 7 5 #x7 #x8 #x10 #x1f #x10 #x8 #x7)
      ;; λ
      (955 9 1 11 7 #x40 #x20 #x20 #x10 #x8 #x8 #x14 #x12 #x22 #x21 #x41)
      ;; π
      (960 9 1 7 7 #x7f #x22 #x22 #x22 #x22 #x22 #x22)
      ;; –
      (8211 8 0 5 7 #x7f)
      ;; —
      (8212 9 0 5 9 #x1ff)
      ;; ‘
      (8216 4 1 11 2 #x3 #x3 #x1 #x2)
      ;; ’
      (8217 4 1 11 2 #x3 #x3 #x1 #x2)
      ;; “
      (8220 7 1 11 5 #x9 #x1b #x12 #x12)
      ;; ”
      (8221 7 1 11 5 #x9 #x1b #x12 #x12)
      ;; …
      (8230 18 1 2 14 #x30c3 #x30c3)
      ;; ←
      (8592 9 1 7 7 #x10 #x20 #x7f #x20 #x10)
      ;; ↑
      (8593 9 2 9 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 9 1 7 7 #x4 #x2 #x7f #x2 #x4)
      ;; ↓
      (8595 9 2 10 5 #x4 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 9 1 8 6 #x4 #x2 #x3f #x2 #x4 #x8 #x10 #x3f #x10 #x8)
      ;; ↳
      (8627 9 1 11 7 #x40 #x40 #x40 #x40 #x44 #x42 #x7f #x2 #x4)
      ;; ∀
      (8704 9 1 11 7 #x41 #x41 #x41 #x3e #x22 #x22 #x14 #x14 #x14 #x8 #x8)
      ;; ∂
      (8706 9 2 10 6 #x1c #x22 #x1 #x1 #xf #x11 #x21 #x21 #x22 #x1c)
      ;; ∃
      (8707 9 1 11 7 #x7f #x1 #x1 #x1 #x1 #x1f #x1 #x1 #x1 #x1 #x7f)
      ;; −
      (8722 9 1 5 7 #x7f)
      ;; ∞
      (8734 11 1 7 9 #x6e #x91 #x111 #x111 #x112 #xec)
      ;; ∧
      (8743 9 1 6 7 #x8 #x14 #x22 #x41)
      ;; ∨
      (8744 9 1 6 7 #x41 #x22 #x14 #x8)
      ;; ∩
      (8745 8 1 8 6 #x1e #x21 #x21 #x21 #x21 #x21 #x21)
      ;; ∪
      (8746 8 1 8 6 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ∫
      (8747 9 1 11 7 #x6 #x9 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x48 #x30)
      ;; ≠
      (8800 9 1 9 7 #x2 #x2 #x4 #x7f #x8 #x10 #x7f #x20 #x40)
      ;; ≡
      (8801 9 1 7 7 #x7f #x0 #x7f #x0 #x7f)
      ;; ≤
      (8804 9 1 8 7 #x3 #xc #x30 #x40 #x30 #xc #x3 #x7f)
      ;; ≥
      (8805 9 1 8 7 #x60 #x18 #x6 #x1 #x6 #x18 #x60 #x7f)
      ;; ⊂
      (8834 9 1 7 7 #x3f #x40 #x40 #x40 #x40 #x3f)
      ;; ⊃
      (8835 9 1 7 7 #x7e #x1 #x1 #x1 #x1 #x7e)
      ;; ⊕
      (8853 9 1 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 9 1 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 8 2 6 4 #x6 #xf #xf #x6)
      ;; ▶
      (9654 8 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 9 1 9 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ◊
      (9674 9 1 9 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 15 1 12 13 #x40 #xa0 #xa0 #x110 #x150 #x248 #x248 #x444 #x444
        #x802 #x842 #x1fff)
      ;; ✓
      (10003 9 0 8 8 #x1 #x2 #x2 #x4 #x84 #x48 #x28 #x10)
      ;; ❚
      (10074 4 1 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera JESS13 Bold" 13 11 2
      ;; the slug, which a character the face lacks draws
      (#f 7 1 11 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x1f)
      ;; space
      (32 7)
      ;; !
      (33 6 1 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; "
      (34 8 0 11 7 #x33 #x77 #x66 #x66)
      ;; #
      (35 9 -1 10 10 #x66 #x66 #x66 #x1ff #xcc #xcc #xcc #x3fe #x198 #x198
        #x198)
      ;; $
      (36 9 0 11 8 #x18 #x3e #x5b #xd8 #xd8 #x7c #x1b #x1b #x99 #xde #x7c #x18)
      ;; %
      (37 10 0 11 8 #x63 #xdf #xd6 #x6c #xc #x18 #x30 #x36 #x6d #xcd #xc6)
      ;; &
      (38 9 0 11 8 #x78 #xcc #xcc #xcc #x50 #x30 #x59 #xce #xc4 #xce #x7b)
      ;; '
      (39 4 0 11 3 #x7 #x7 #x3 #x6)
      ;; (
      (40 7 1 11 4 #x3 #x6 #x6 #xc #xc #xc #xc #xc #xc #x6 #x6 #x3)
      ;; )
      (41 7 0 11 4 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc)
      ;; *
      (42 9 0 9 7 #x8 #x49 #x6b #x3e #x1c #x1c #x3e #x6b #x49 #x8)
      ;; +
      (43 9 0 8 8 #x18 #x18 #x18 #xff #xff #x18 #x18 #x18)
      ;; ,
      (44 6 -1 2 4 #x7 #x7 #x6 #xc)
      ;; -
      (45 9 0 5 7 #x7f #x7f)
      ;; .
      (46 6 0 2 3 #x7 #x7)
      ;; /
      (47 9 1 11 7 #x3 #x7 #x6 #xe #xc #x1c #x18 #x38 #x30 #x70 #x60 #x60)
      ;; 0
      (48 9 0 11 7 #x1e #x33 #x63 #x63 #x67 #x6b #x73 #x63 #x63 #x66 #x3c)
      ;; 1
      (49 9 1 11 6 #xc #x1c #x3c #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; 2
      (50 9 0 11 7 #x3e #x63 #x43 #x3 #x6 #xc #x18 #x30 #x60 #x60 #x7f)
      ;; 3
      (51 9 0 11 7 #x1e #x33 #x43 #x3 #x6 #x1e #x3 #x3 #x3 #x66 #x7c)
      ;; 4
      (52 9 0 11 8 #x6 #xe #x1e #x36 #x66 #xc6 #xff #x6 #x6 #x6 #x6)
      ;; 5
      (53 9 0 11 7 #x1f #x38 #x20 #x60 #x7e #x3 #x3 #x3 #x3 #x66 #x3c)
      ;; 6
      (54 9 0 11 7 #x1e #x30 #x60 #x60 #x7e #x63 #x63 #x63 #x63 #x66 #x3c)
      ;; 7
      (55 9 0 11 7 #x7f #x63 #x3 #x3 #x6 #xc #x18 #x18 #x30 #x30 #x30)
      ;; 8
      (56 9 0 11 8 #x3e #x63 #xc3 #xc6 #x6c #x3e #x63 #xc3 #xc3 #xc6 #x7c)
      ;; 9
      (57 9 0 11 7 #x1e #x33 #x63 #x63 #x63 #x63 #x3f #x3 #x3 #x6 #x3c)
      ;; :
      (58 7 1 6 2 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; ;
      (59 6 -1 6 3 #x3 #x3 #x0 #x0 #x3 #x3 #x2 #x4)
      ;; <
      (60 9 0 9 7 #x1 #x7 #xe #x38 #x60 #x38 #xe #x7 #x1)
      ;; =
      (61 9 0 6 7 #x7f #x7f #x0 #x7f #x7f)
      ;; >
      (62 9 1 9 7 #x40 #x70 #x38 #xe #x3 #xe #x38 #x70 #x40)
      ;; ?
      (63 9 0 11 7 #x3e #x63 #x63 #x3 #x6 #xc #x18 #x18 #x0 #x18 #x18)
      ;; @
      (64 9 0 8 7 #x1e #x21 #x5d #x55 #x55 #x5e #x40 #x3e)
      ;; A
      (65 10 0 11 8 #x8 #x1c #x36 #x62 #x63 #xc3 #xff #xc3 #xc3 #xc3 #xc3)
      ;; B
      (66 9 0 11 7 #x7e #x63 #x63 #x63 #x66 #x7e #x63 #x63 #x63 #x66 #x7c)
      ;; C
      (67 8 0 11 7 #x1e #x33 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x73 #x3e)
      ;; D
      (68 9 0 11 7 #x7e #x63 #x63 #x63 #x63 #x63 #x63 #x63 #x63 #x66 #x7c)
      ;; E
      (69 8 0 11 6 #x3f #x30 #x30 #x30 #x30 #x3e #x30 #x30 #x30 #x30 #x3f)
      ;; F
      (70 8 0 11 7 #x7f #x60 #x60 #x60 #x60 #x7e #x60 #x60 #x60 #x60 #x60)
      ;; G
      (71 9 0 11 7 #x1e #x33 #x60 #x60 #x60 #x67 #x63 #x63 #x63 #x67 #x3e)
      ;; H
      (72 10 0 11 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; I
      (73 7 0 11 6 #x3f #xc #xc #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; J
      (74 9 0 11 6 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x33 #x37 #x1e)
      ;; K
      (75 9 0 11 8 #xc3 #xc6 #xcc #xd8 #xf0 #xe0 #xf0 #xd8 #xcc #xc6 #xc3)
      ;; L
      (76 8 0 11 6 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x3f)
      ;; M
      (77 10 0 11 8 #xc3 #xc3 #xe7 #xef #xfb #xdb #xd3 #xc3 #xc3 #xc3 #xc3)
      ;; N
      (78 9 0 11 7 #x43 #x63 #x63 #x73 #x7b #x6b #x67 #x67 #x63 #x63 #x61)
      ;; O
      (79 9 0 11 7 #x1e #x37 #x63 #x63 #x63 #x63 #x63 #x63 #x63 #x76 #x3c)
      ;; P
      (80 9 0 11 7 #x7e #x63 #x63 #x63 #x66 #x7c #x60 #x60 #x60 #x60 #x60)
      ;; Q
      (81 9 0 11 7 #x1e #x33 #x63 #x63 #x63 #x63 #x63 #x63 #x6b #x6e #x3e #x3)
      ;; R
      (82 9 0 11 8 #xfc #xc6 #xc6 #xc6 #xcc #xf8 #xf0 #xd8 #xcc #xc6 #xc3)
      ;; S
      (83 9 0 11 7 #x1e #x33 #x60 #x60 #x70 #x3e #x7 #x3 #x3 #x66 #x3c)
      ;; T
      (84 9 0 11 8 #xff #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18)
      ;; U
      (85 10 0 11 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; V
      (86 10 0 11 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6 #x66 #x6c #x38 #x30)
      ;; W
      (87 12 0 11 11 #x603 #x603 #x603 #x603 #x663 #x666 #x666 #x6ac #x2ac
        #x3b8 #x330)
      ;; X
      (88 9 0 11 8 #xc3 #xc3 #x66 #x66 #x3c #x18 #x3c #x66 #x66 #xc3 #xc3)
      ;; Y
      (89 9 0 11 8 #xc3 #xc3 #x66 #x66 #x3c #x18 #x18 #x18 #x18 #x18 #x18)
      ;; Z
      (90 9 0 11 7 #x7f #x67 #x6 #xc #xc #x18 #x18 #x30 #x30 #x63 #x7f)
      ;; [
      (91 7 2 11 4 #xf #xc #xc #xc #xc #xc #xc #xc #xc #xc #xc #xf)
      ;; \
      (92 9 1 11 7 #x60 #x60 #x30 #x30 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ]
      (93 8 0 11 4 #xf #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #xf)
      ;; ^
      (94 9 0 11 7 #x8 #x1c #x36 #x63)
      ;; _
      (95 9 0 0 7 #x7f #x7f)
      ;; `
      (96 4 0 11 2 #x1 #x2 #x3 #x3)
      ;; a
      (97 9 0 7 8 #x7c #xe6 #xe #x76 #xc6 #xce #x77)
      ;; b
      (98 9 0 11 7 #x60 #x60 #x60 #x60 #x6e #x73 #x63 #x63 #x63 #x66 #x7c)
      ;; c
      (99 8 0 7 6 #xf #x1b #x30 #x30 #x30 #x3b #x1e)
      ;; d
      (100 9 0 11 7 #x3 #x3 #x3 #x3 #x1f #x33 #x63 #x63 #x63 #x77 #x3b)
      ;; e
      (101 9 0 7 7 #x1e #x33 #x63 #x7e #x60 #x73 #x3e)
      ;; f
      (102 7 0 11 7 #xe #x1b #x30 #x30 #x7c #x30 #x30 #x30 #x30 #x30 #x30)
      ;; g
      (103 9 0 7 7 #x1e #x33 #x63 #x63 #x77 #x3b #x3 #x76 #x3c)
      ;; h
      (104 9 0 11 7 #x60 #x60 #x60 #x60 #x66 #x6f #x73 #x63 #x63 #x63 #x63)
      ;; i
      (105 5 0 11 3 #x3 #x3 #x0 #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; j
      (106 7 -1 11 6 #x3 #x3 #x0 #x0 #xf #x3 #x3 #x3 #x3 #x3 #x3 #x36 #x1c)
      ;; k
      (107 9 0 11 7 #x60 #x60 #x60 #x60 #x63 #x66 #x7c #x78 #x6c #x66 #x63)
      ;; l
      (108 5 0 11 3 #x7 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; m
      (109 14 0 7 12 #xd9e #xf7b #xc63 #xc63 #xc63 #xc63 #xc63)
      ;; n
      (110 9 0 7 7 #x6e #x7b #x63 #x63 #x63 #x63 #x63)
      ;; o
      (111 9 0 7 7 #x1e #x33 #x63 #x63 #x63 #x66 #x3c)
      ;; p
      (112 9 0 7 7 #x6e #x73 #x63 #x63 #x63 #x66 #x7c #x60 #x60)
      ;; q
      (113 9 0 7 7 #x1f #x33 #x63 #x63 #x63 #x77 #x3b #x3 #x3)
      ;; r
      (114 8 0 7 7 #x66 #x6f #x70 #x60 #x60 #x60 #x60)
      ;; s
      (115 7 0 7 6 #x1f #x33 #x38 #x1e #x7 #x33 #x3e)
      ;; t
      (116 7 0 9 7 #x30 #x30 #x7c #x30 #x30 #x30 #x33 #x36 #x1c)
      ;; u
      (117 9 0 7 7 #x63 #x63 #x63 #x63 #x67 #x6b #x33)
      ;; v
      (118 9 0 7 8 #xc3 #xc3 #xc6 #x66 #x6c #x38 #x30)
      ;; w
      (119 13 0 7 11 #x603 #x633 #x633 #x633 #x376 #x39c #x318)
      ;; x
      (120 8 -1 7 8 #x63 #x66 #x3c #x18 #x3c #x66 #xc6)
      ;; y
      (121 9 0 7 7 #x63 #x63 #x63 #x63 #x36 #x1c #x18 #x70 #x60)
      ;; z
      (122 9 1 7 6 #x3f #x33 #x6 #xc #x18 #x31 #x3f)
      ;; {
      (123 8 0 11 6 #x7 #xc #xc #xc #x1c #x38 #x1c #xc #xc #xc #xc #x7)
      ;; |
      (124 9 3 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; }
      (125 8 0 11 6 #x38 #xc #xc #xc #xe #x7 #xe #xc #xc #xc #x38)
      ;; ~
      (126 9 0 10 8 #x33 #x7e #xcc)
      ;; ¬
      (172 9 0 5 7 #x7f #x7f #x1 #x1)
      ;; °
      (176 6 1 11 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 0 8 8 #x18 #x18 #x18 #xff #xff #x18 #x18 #xff #xff)
      ;; µ
      (181 9 0 7 7 #x63 #x63 #x63 #x63 #x67 #x6b #x33 #x60 #x60)
      ;; ·
      (183 8 1 6 5 #xe #x1f #x1f #xe)
      ;; À
      (192 10 0 11 8 #x30 #x18 #x8 #x1c #x36 #x62 #x63 #xc3 #xff #xc3 #xc3)
      ;; Á
      (193 10 0 11 8 #x18 #x30 #x8 #x1c #x36 #x62 #x63 #xc3 #xff #xc3 #xc3)
      ;; Â
      (194 10 0 11 8 #x18 #x3c #x8 #x1c #x36 #x62 #x63 #xc3 #xff #xc3 #xc3)
      ;; Ã
      (195 10 0 11 8 #x3c #x78 #x8 #x1c #x36 #x62 #x63 #xc3 #xff #xc3 #xc3)
      ;; Ä
      (196 10 0 11 8 #x3c #x0 #x8 #x1c #x36 #x62 #x63 #xc3 #xff #xc3 #xc3)
      ;; Å
      (197 10 0 11 8 #x18 #x3c #x18 #x8 #x36 #x62 #x63 #xc3 #xff #xc3 #xc3)
      ;; Ç
      (199 8 0 11 7 #x1e #x33 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x73 #x3e
        #x18 #x30)
      ;; È
      (200 8 0 11 6 #x18 #xc #x3f #x30 #x30 #x3e #x30 #x30 #x30 #x30 #x3f)
      ;; É
      (201 8 0 11 6 #xc #x18 #x3f #x30 #x30 #x3e #x30 #x30 #x30 #x30 #x3f)
      ;; Ê
      (202 8 0 11 6 #xc #x1e #x3f #x30 #x30 #x3e #x30 #x30 #x30 #x30 #x3f)
      ;; Ë
      (203 8 0 11 6 #x1e #x0 #x3f #x30 #x30 #x3e #x30 #x30 #x30 #x30 #x3f)
      ;; Ì
      (204 7 0 11 6 #x18 #xc #x3f #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Í
      (205 7 0 11 6 #xc #x18 #x3f #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Î
      (206 7 0 11 6 #xc #x1e #x3f #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Ï
      (207 7 0 11 6 #x1e #x0 #x3f #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Ñ
      (209 9 0 11 7 #x3c #x78 #x43 #x63 #x73 #x7b #x6b #x67 #x63 #x63 #x61)
      ;; Ò
      (210 9 0 11 7 #x30 #x18 #x1e #x37 #x63 #x63 #x63 #x63 #x63 #x76 #x3c)
      ;; Ó
      (211 9 0 11 7 #x18 #x30 #x1e #x37 #x63 #x63 #x63 #x63 #x63 #x76 #x3c)
      ;; Ô
      (212 9 0 11 7 #x18 #x3c #x1e #x37 #x63 #x63 #x63 #x63 #x63 #x76 #x3c)
      ;; Õ
      (213 9 0 11 7 #x3c #x78 #x1e #x37 #x63 #x63 #x63 #x63 #x63 #x76 #x3c)
      ;; Ö
      (214 9 0 11 7 #x3c #x0 #x1e #x37 #x63 #x63 #x63 #x63 #x63 #x76 #x3c)
      ;; ×
      (215 8 -1 7 8 #x63 #x66 #x3c #x18 #x3c #x66 #xc6)
      ;; Ù
      (217 10 0 11 8 #x30 #x18 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ú
      (218 10 0 11 8 #x18 #x30 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Û
      (219 10 0 11 8 #x18 #x3c #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ü
      (220 10 0 11 8 #x3c #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ý
      (221 9 0 11 8 #x18 #x30 #xc3 #x66 #x3c #x18 #x18 #x18 #x18 #x18 #x18)
      ;; à
      (224 9 0 10 8 #x30 #x18 #x0 #x7c #xe6 #xe #x76 #xc6 #xce #x77)
      ;; á
      (225 9 0 10 8 #x18 #x30 #x0 #x7c #xe6 #xe #x76 #xc6 #xce #x77)
      ;; â
      (226 9 0 10 8 #x18 #x3c #x0 #x7c #xe6 #xe #x76 #xc6 #xce #x77)
      ;; ã
      (227 9 0 10 8 #x3c #x78 #x0 #x7c #xe6 #xe #x76 #xc6 #xce #x77)
      ;; ä
      (228 9 0 9 8 #x3c #x0 #x7c #xe6 #xe #x76 #xc6 #xce #x77)
      ;; å
      (229 9 0 11 8 #x18 #x3c #x18 #x0 #x7c #xe6 #xe #x76 #xc6 #xce #x77)
      ;; ç
      (231 8 0 7 6 #xf #x1b #x30 #x30 #x30 #x3b #x1e #xc #x18)
      ;; è
      (232 9 0 10 7 #x30 #x18 #x0 #x1e #x33 #x63 #x7e #x60 #x73 #x3e)
      ;; é
      (233 9 0 10 7 #x18 #x30 #x0 #x1e #x33 #x63 #x7e #x60 #x73 #x3e)
      ;; ê
      (234 9 0 10 7 #x18 #x3c #x0 #x1e #x33 #x63 #x7e #x60 #x73 #x3e)
      ;; ë
      (235 9 0 9 7 #x3c #x0 #x1e #x33 #x63 #x7e #x60 #x73 #x3e)
      ;; ì
      (236 5 -1 10 4 #xc #x6 #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; í
      (237 5 -1 10 4 #x6 #xc #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; î
      (238 5 -1 10 4 #x6 #xf #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; ï
      (239 5 -1 9 4 #xf #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; ñ
      (241 9 0 10 7 #x3c #x78 #x0 #x6e #x7b #x63 #x63 #x63 #x63 #x63)
      ;; ò
      (242 9 0 10 7 #x30 #x18 #x0 #x1e #x33 #x63 #x63 #x63 #x66 #x3c)
      ;; ó
      (243 9 0 10 7 #x18 #x30 #x0 #x1e #x33 #x63 #x63 #x63 #x66 #x3c)
      ;; ô
      (244 9 0 10 7 #x18 #x3c #x0 #x1e #x33 #x63 #x63 #x63 #x66 #x3c)
      ;; õ
      (245 9 0 10 7 #x3c #x78 #x0 #x1e #x33 #x63 #x63 #x63 #x66 #x3c)
      ;; ö
      (246 9 0 9 7 #x3c #x0 #x1e #x33 #x63 #x63 #x63 #x66 #x3c)
      ;; ù
      (249 9 0 10 7 #x30 #x18 #x0 #x63 #x63 #x63 #x63 #x67 #x6b #x33)
      ;; ú
      (250 9 0 10 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x67 #x6b #x33)
      ;; û
      (251 9 0 10 7 #x18 #x3c #x0 #x63 #x63 #x63 #x63 #x67 #x6b #x33)
      ;; ü
      (252 9 0 9 7 #x3c #x0 #x63 #x63 #x63 #x63 #x67 #x6b #x33)
      ;; ý
      (253 9 0 10 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x36 #x1c #x18 #x70 #x60)
      ;; ÿ
      (255 9 0 9 7 #x3c #x0 #x63 #x63 #x63 #x63 #x36 #x1c #x18 #x70 #x60)
      ;; α
      (945 9 0 7 8 #x2 #x62 #xd6 #xcc #xcc #xd6 #x63)
      ;; β
      (946 9 1 9 7 #x1e #x33 #x33 #x62 #x7e #x63 #x63 #x63 #x7e #x60 #x60)
      ;; γ
      (947 9 0 7 7 #x41 #x22 #x14 #x18 #x10 #x30 #x30 #x30 #x20)
      ;; δ
      (948 9 0 11 7 #x1e #x33 #x31 #x30 #x18 #xc #x1e #x33 #x61 #x67 #x3e)
      ;; ε
      (949 9 1 7 5 #x7 #xe #x18 #x1f #x18 #xe #x7)
      ;; λ
      (955 9 0 11 8 #xc0 #x60 #x60 #x30 #x18 #x18 #x3c #x36 #x66 #x63 #xc3)
      ;; π
      (960 9 0 7 8 #xff #x66 #x66 #x66 #x66 #x66 #x66)
      ;; –
      (8211 9 0 5 8 #xff #xff)
      ;; —
      (8212 10 0 5 10 #x3ff #x3ff)
      ;; ‘
      (8216 4 0 11 3 #x7 #x7 #x3 #x6)
      ;; ’
      (8217 4 0 11 3 #x7 #x7 #x3 #x6)
      ;; “
      (8220 8 0 11 7 #x33 #x77 #x66 #x66)
      ;; ”
      (8221 8 0 11 7 #x33 #x77 #x66 #x66)
      ;; …
      (8230 18 0 2 15 #x71c7 #x71c7)
      ;; ←
      (8592 9 0 7 7 #x10 #x30 #x7f #x7f #x30 #x10)
      ;; ↑
      (8593 9 1 9 6 #xc #x1e #x3f #xc #xc #xc #xc #xc #xc)
      ;; →
      (8594 9 0 7 7 #x4 #x6 #x7f #x7f #x6 #x4)
      ;; ↓
      (8595 9 1 10 6 #xc #xc #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↔
      (8596 9 0 9 6 #x4 #x6 #x3f #x3f #x6 #xc #x18 #x3f #x3f #x18 #x8)
      ;; ↳
      (8627 9 0 11 7 #x60 #x60 #x60 #x60 #x64 #x66 #x7f #x7f #x6 #x4)
      ;; ∀
      (8704 10 0 11 8 #xc3 #xc3 #xc3 #x7e #x66 #x66 #x2c #x2c #x3c #x18 #x18)
      ;; ∂
      (8706 9 1 10 6 #x1c #x3a #x3 #x3 #xf #x1b #x33 #x33 #x32 #x1c)
      ;; ∃
      (8707 9 0 11 7 #x7f #x7f #x3 #x3 #x3 #x1f #x1f #x3 #x3 #x7f #x7f)
      ;; −
      (8722 9 0 5 8 #xff #xff)
      ;; ∞
      (8734 11 0 7 10 #x1ce #x333 #x333 #x333 #x333 #x1ce)
      ;; ∧
      (8743 9 0 6 7 #x8 #x1c #x36 #x63)
      ;; ∨
      (8744 9 0 6 7 #x63 #x36 #x1c #x8)
      ;; ∩
      (8745 8 0 8 6 #x1e #x33 #x33 #x33 #x33 #x33 #x33)
      ;; ∪
      (8746 8 0 8 6 #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; ∫
      (8747 9 0 11 8 #xe #x1b #x18 #x18 #x18 #x18 #x18 #x18 #x18 #xd8 #x70)
      ;; ≠
      (8800 9 -1 9 8 #x3 #x3 #x6 #x7f #x7f #x18 #x7f #x7f #x60 #xc0)
      ;; ≡
      (8801 9 0 7 7 #x7f #x7f #x0 #x7f #x7f #x0 #x7f #x7f)
      ;; ≤
      (8804 9 0 8 7 #x3 #xf #x3c #x60 #x3c #xf #x1 #x7f #x7f)
      ;; ≥
      (8805 9 0 8 7 #x60 #x78 #x1e #x3 #x1e #x78 #x40 #x7f #x7f)
      ;; ⊂
      (8834 9 0 7 7 #x3f #x7f #x40 #x40 #x7f #x3f)
      ;; ⊃
      (8835 9 0 7 7 #x7e #x7f #x1 #x1 #x7f #x7e)
      ;; ⊕
      (8853 9 0 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 9 0 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 8 1 6 5 #xe #x1f #x1f #xe)
      ;; ▶
      (9654 8 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 9 0 9 8 #x18 #x18 #x34 #x66 #xc3 #x66 #x2c #x18 #x18)
      ;; ◊
      (9674 9 0 9 8 #x18 #x18 #x34 #x66 #xc3 #x66 #x2c #x18 #x18)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 15 1 12 13 #x40 #xa0 #xa0 #x110 #x150 #x248 #x248 #x444 #x444
        #x802 #x842 #x1fff)
      ;; ✓
      (10003 9 0 8 8 #x3 #x3 #x6 #x6 #xcc #x6c #x38 #x18)
      ;; ❚
      (10074 6 1 11 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("Genera JESS13 Italic" 13 11 2
      ;; the slug, which a character the face lacks draws
      (#f 7 1 11 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x1f)
      ;; space
      (32 7)
      ;; !
      (33 6 1 11 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x0 #x1 #x1)
      ;; "
      (34 7 1 11 5 #x9 #x1b #x12 #x12)
      ;; #
      (35 9 0 10 8 #x12 #x12 #x12 #x7f #x24 #x24 #x24 #xfe #x48 #x48 #x48)
      ;; $
      (36 9 0 11 7 #x8 #x1e #x29 #x48 #x48 #x3e #x9 #x9 #x4a #x3c #x8)
      ;; %
      (37 9 -1 11 8 #x63 #x9d #x92 #x64 #x4 #x8 #x10 #x16 #x29 #x49 #x46)
      ;; &
      (38 9 0 11 7 #x38 #x44 #x44 #x44 #x28 #x18 #x28 #x45 #x42 #x46 #x39)
      ;; '
      (39 4 1 11 2 #x3 #x3 #x1 #x2)
      ;; (
      (40 7 2 11 5 #x1 #x2 #x4 #x4 #x8 #x8 #x10 #x10 #x10 #x10 #x10 #x8 #x8)
      ;; )
      (41 6 -1 11 5 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4 #x8 #x10)
      ;; *
      (42 9 0 8 7 #x8 #x49 #x2a #x1c #x1c #x2a #x49 #x8)
      ;; +
      (43 9 0 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8)
      ;; ,
      (44 6 -1 2 3 #x3 #x3 #x2 #x4)
      ;; -
      (45 9 0 5 7 #x7f)
      ;; .
      (46 6 0 2 2 #x3 #x3)
      ;; /
      (47 9 1 11 6 #x1 #x3 #x2 #x6 #x4 #xc #x8 #x18 #x10 #x30 #x20 #x20)
      ;; 0
      (48 9 0 11 9 #x1e #x21 #x43 #x45 #x8a #x92 #xa2 #xc2 #x104 #x108 #xf0)
      ;; 1
      (49 9 1 11 5 #x1 #x1 #x7 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x1f)
      ;; 2
      (50 9 0 11 9 #x1e #x21 #x41 #x1 #x2 #x4 #x78 #x80 #x100 #x100 #x1fc)
      ;; 3
      (51 9 0 11 9 #x1e #x21 #x41 #x1 #x2 #x3c #x2 #x4 #x4 #x8 #x1f0)
      ;; 4
      (52 9 0 11 7 #x3 #x5 #x9 #x11 #x22 #x42 #x7f #x2 #x4 #x4 #x4)
      ;; 5
      (53 9 0 11 9 #x1f #x20 #x20 #x40 #xfc #x2 #x2 #x2 #x4 #x108 #xf0)
      ;; 6
      (54 9 0 11 8 #xf #x10 #x20 #x20 #x5e #x61 #x41 #x81 #x82 #x84 #x78)
      ;; 7
      (55 9 2 11 7 #x7f #x41 #x1 #x1 #x2 #x4 #x8 #x10 #x20 #x40 #x40)
      ;; 8
      (56 9 0 11 9 #x1e #x21 #x41 #x42 #x24 #x7c #x84 #x104 #x104 #x108 #xf0)
      ;; 9
      (57 9 0 11 8 #x1e #x21 #x41 #x41 #x41 #x46 #x3a #x2 #x4 #x8 #xf0)
      ;; :
      (58 7 1 6 3 #x3 #x3 #x0 #x0 #x6 #x6)
      ;; ;
      (59 6 -1 6 4 #x3 #x3 #x0 #x0 #x6 #x6 #x4 #x8)
      ;; <
      (60 9 0 9 7 #x1 #x6 #x8 #x30 #x40 #x30 #x8 #x6 #x1)
      ;; =
      (61 9 0 6 7 #x7f #x0 #x0 #x7f)
      ;; >
      (62 9 0 9 7 #x40 #x30 #x8 #x6 #x1 #x6 #x8 #x30 #x40)
      ;; ?
      (63 9 0 11 7 #x3e #x41 #x41 #x1 #x2 #x4 #x8 #x8 #x0 #x0 #x8)
      ;; @
      (64 9 0 8 7 #x1e #x21 #x5d #x55 #x55 #x5e #x40 #x3e)
      ;; A
      (65 9 0 11 8 #x6 #xa #x11 #x11 #x21 #x21 #x7f #x41 #x81 #x81 #x81)
      ;; B
      (66 9 0 11 9 #x7e #x41 #x41 #x41 #x82 #xfc #x82 #x82 #x104 #x104 #x1f8)
      ;; C
      (67 8 0 11 8 #xe #x11 #x20 #x20 #x40 #x40 #x40 #x80 #x80 #x84 #x78)
      ;; D
      (68 9 0 11 9 #x7e #x41 #x41 #x41 #x82 #x82 #x82 #x82 #x104 #x108 #x1f0)
      ;; E
      (69 8 0 11 9 #x7f #x40 #x40 #x80 #x80 #xf0 #x80 #x80 #x100 #x100 #x1fc)
      ;; F
      (70 8 0 11 8 #x3f #x20 #x20 #x20 #x40 #x78 #x40 #x40 #x80 #x80 #x80)
      ;; G
      (71 9 0 11 9 #x1e #x21 #x40 #x40 #x80 #x8e #x82 #x102 #x104 #x108 #xf0)
      ;; H
      (72 9 0 11 9 #x41 #x41 #x41 #x41 #x82 #xfe #x82 #x82 #x104 #x104 #x104)
      ;; I
      (73 7 0 11 7 #x1f #x4 #x4 #x4 #x8 #x8 #x8 #x8 #x10 #x10 #x7c)
      ;; J
      (74 8 -1 11 8 #x1 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x84 #x84 #x78)
      ;; K
      (75 9 0 11 8 #x21 #x22 #x24 #x28 #x50 #x60 #x60 #x50 #x88 #x84 #x82)
      ;; L
      (76 8 0 11 6 #x8 #x8 #x8 #x8 #x10 #x10 #x10 #x10 #x20 #x20 #x3f)
      ;; M
      (77 10 0 11 10 #x81 #x83 #xc5 #xa9 #x12a #x132 #x122 #x102 #x204 #x204
        #x204)
      ;; N
      (78 9 0 11 9 #x41 #x41 #x61 #x51 #x92 #x92 #x8a #x8a #x104 #x104 #x104)
      ;; O
      (79 9 0 11 9 #x1e #x21 #x41 #x41 #x41 #x82 #x82 #x102 #x104 #x108 #xf0)
      ;; P
      (80 9 0 11 8 #x3e #x21 #x21 #x21 #x42 #x7c #x40 #x40 #x80 #x80 #x80)
      ;; Q
      (81 9 0 11 9 #x1e #x21 #x41 #x41 #x82 #x82 #x82 #x102 #x164 #x118 #xf8
        #x4)
      ;; R
      (82 10 1 11 9 #x7e #x41 #x41 #x81 #x82 #xfc #xa0 #x90 #x108 #x104 #x102)
      ;; S
      (83 8 -1 11 9 #x1e #x21 #x40 #x40 #x40 #x38 #x4 #x4 #x4 #x108 #xf0)
      ;; T
      (84 8 1 11 7 #x7f #x8 #x8 #x8 #x10 #x10 #x10 #x10 #x20 #x20 #x20)
      ;; U
      (85 9 0 11 9 #x41 #x41 #x41 #x81 #x82 #x82 #x102 #x102 #x104 #x88 #x70)
      ;; V
      (86 9 1 11 7 #x41 #x41 #x41 #x41 #x41 #x42 #x44 #x48 #x50 #x60 #x40)
      ;; W
      (87 13 1 11 11 #x401 #x401 #x401 #x401 #x421 #x422 #x462 #x4a4 #x528
        #x630 #x420)
      ;; X
      (88 10 0 11 9 #x41 #x41 #x42 #x24 #x28 #x10 #x28 #x48 #x84 #x104 #x104)
      ;; Y
      (89 9 1 11 7 #x41 #x41 #x42 #x44 #x28 #x10 #x10 #x10 #x20 #x20 #x20)
      ;; Z
      (90 9 0 11 9 #x3f #x1 #x2 #x4 #x8 #x10 #x20 #x40 #x80 #x100 #x1fc)
      ;; [
      (91 7 2 11 3 #x7 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x7)
      ;; \
      (92 9 1 11 6 #x20 #x20 #x10 #x10 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ]
      (93 7 0 11 3 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x7)
      ;; ^
      (94 9 0 11 7 #x8 #x14 #x22 #x41)
      ;; _
      (95 9 0 -1 7 #x7f)
      ;; `
      (96 4 0 11 2 #x1 #x2 #x3 #x3)
      ;; a
      (97 8 0 7 7 #x1e #x21 #x7 #x39 #x42 #x46 #x3a)
      ;; b
      (98 8 0 11 7 #x10 #x10 #x10 #x10 #x3e #x21 #x21 #x21 #x42 #x42 #x7c)
      ;; c
      (99 8 0 7 7 #xe #x11 #x20 #x20 #x40 #x44 #x38)
      ;; d
      (100 9 0 11 9 #x1 #x2 #x2 #x2 #x3c #x44 #x84 #x84 #x108 #x118 #xe8)
      ;; e
      (101 8 0 7 7 #xe #x11 #x22 #x3c #x40 #x42 #x3c)
      ;; f
      (102 7 1 11 8 #xe #x11 #x20 #x20 #xf8 #x40 #x40 #x40 #x80 #x80 #x80)
      ;; g
      (103 8 -1 7 8 #xe #x11 #x21 #x41 #x46 #x3a #x2 #x8c #x70)
      ;; h
      (104 8 0 11 7 #x10 #x10 #x10 #x10 #x27 #x29 #x31 #x21 #x42 #x42 #x42)
      ;; i
      (105 5 1 10 3 #x1 #x1 #x0 #x6 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; j
      (106 7 -2 10 8 #x1 #x1 #x0 #xe #x2 #x2 #x2 #x4 #x4 #x4 #x88 #x70)
      ;; k
      (107 8 0 11 7 #x10 #x10 #x10 #x10 #x21 #x22 #x2c #x30 #x48 #x44 #x42)
      ;; l
      (108 5 1 11 3 #x3 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; m
      (109 13 0 7 12 #x4c6 #x529 #x631 #x421 #x842 #x842 #x842)
      ;; n
      (110 8 0 7 7 #x26 #x29 #x31 #x21 #x42 #x42 #x42)
      ;; o
      (111 7 0 7 6 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; p
      (112 8 -1 7 8 #x2e #x31 #x21 #x22 #x42 #x44 #x78 #x80 #x80)
      ;; q
      (113 7 0 7 6 #xf #x11 #x21 #x21 #x22 #x22 #x1c #x4 #x4)
      ;; r
      (114 7 0 7 7 #x26 #x29 #x30 #x20 #x40 #x40 #x40)
      ;; s
      (115 8 0 7 7 #xe #x11 #x20 #x1c #x2 #x44 #x38)
      ;; t
      (116 7 1 9 5 #x4 #x4 #x1f #x8 #x8 #x10 #x11 #x12 #xc)
      ;; u
      (117 8 0 7 7 #x21 #x21 #x21 #x42 #x46 #x4a #x32)
      ;; v
      (118 8 1 7 6 #x21 #x21 #x21 #x22 #x24 #x28 #x30)
      ;; w
      (119 12 1 7 9 #x101 #x111 #x111 #x111 #xaa #xcc #x88)
      ;; x
      (120 9 0 7 7 #x31 #xa #xc #x8 #x14 #x24 #x43)
      ;; y
      (121 8 -1 7 8 #x21 #x21 #x21 #x22 #x24 #x18 #x10 #x20 #xc0)
      ;; z
      (122 9 0 7 8 #x3f #x42 #x4 #x18 #x20 #x42 #xfc)
      ;; {
      (123 9 0 11 7 #x7 #x8 #x8 #x8 #x18 #x70 #x18 #x8 #x8 #x8 #x7)
      ;; |
      (124 9 3 11 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; }
      (125 9 0 11 7 #x70 #x8 #x8 #x8 #xc #x7 #xc #x8 #x8 #x8 #x70)
      ;; ~
      (126 9 0 10 6 #x19 #x26)
      ;; ¬
      (172 9 0 5 7 #x7f #x1 #x1)
      ;; °
      (176 6 1 11 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 0 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8 #x7f)
      ;; µ
      (181 8 0 7 7 #x21 #x21 #x21 #x42 #x46 #x4a #x32 #x40 #x40)
      ;; ·
      (183 8 1 6 4 #x6 #xf #xf #x6)
      ;; À
      (192 9 0 11 8 #x10 #x8 #x6 #xa #x11 #x21 #x7f #x41 #x81 #x81 #x81)
      ;; Á
      (193 9 0 11 8 #x8 #x10 #x6 #xa #x11 #x21 #x7f #x41 #x81 #x81 #x81)
      ;; Â
      (194 9 0 11 8 #x10 #x28 #x6 #xa #x11 #x21 #x7f #x41 #x81 #x81 #x81)
      ;; Ã
      (195 9 0 11 8 #x14 #x28 #x6 #xa #x11 #x21 #x7f #x41 #x81 #x81 #x81)
      ;; Ä
      (196 9 0 11 8 #x28 #x0 #x6 #xa #x11 #x21 #x7f #x41 #x81 #x81 #x81)
      ;; Å
      (197 9 0 11 8 #x10 #x28 #x10 #x6 #xa #x11 #x21 #x7f #x41 #x81 #x81)
      ;; Ç
      (199 8 0 11 8 #xe #x11 #x20 #x20 #x40 #x40 #x40 #x80 #x80 #x84 #x78 #x8
        #x10)
      ;; È
      (200 8 0 11 9 #x20 #x10 #x7f #x40 #x80 #xf0 #x80 #x80 #x100 #x100 #x1fc)
      ;; É
      (201 8 0 11 9 #x10 #x20 #x7f #x40 #x80 #xf0 #x80 #x80 #x100 #x100 #x1fc)
      ;; Ê
      (202 8 0 11 9 #x20 #x50 #x7f #x40 #x80 #xf0 #x80 #x80 #x100 #x100 #x1fc)
      ;; Ë
      (203 8 0 11 9 #x50 #x0 #x7f #x40 #x80 #xf0 #x80 #x80 #x100 #x100 #x1fc)
      ;; Ì
      (204 7 0 11 7 #x10 #x8 #x1f #x4 #x4 #x8 #x8 #x8 #x10 #x10 #x7c)
      ;; Í
      (205 7 0 11 7 #x8 #x10 #x1f #x4 #x4 #x8 #x8 #x8 #x10 #x10 #x7c)
      ;; Î
      (206 7 0 11 7 #x10 #x28 #x1f #x4 #x4 #x8 #x8 #x8 #x10 #x10 #x7c)
      ;; Ï
      (207 7 0 11 7 #x28 #x0 #x1f #x4 #x4 #x8 #x8 #x8 #x10 #x10 #x7c)
      ;; Ñ
      (209 9 0 11 9 #x28 #x50 #x41 #x61 #x51 #x92 #x8a #x8a #x104 #x104 #x104)
      ;; Ò
      (210 9 0 11 9 #x20 #x10 #x1e #x21 #x41 #x82 #x82 #x102 #x104 #x108 #xf0)
      ;; Ó
      (211 9 0 11 9 #x10 #x20 #x1e #x21 #x41 #x82 #x82 #x102 #x104 #x108 #xf0)
      ;; Ô
      (212 9 0 11 9 #x20 #x50 #x1e #x21 #x41 #x82 #x82 #x102 #x104 #x108 #xf0)
      ;; Õ
      (213 9 0 11 9 #x28 #x50 #x1e #x21 #x41 #x82 #x82 #x102 #x104 #x108 #xf0)
      ;; Ö
      (214 9 0 11 9 #x50 #x0 #x1e #x21 #x41 #x82 #x82 #x102 #x104 #x108 #xf0)
      ;; ×
      (215 9 0 7 7 #x31 #xa #xc #x8 #x14 #x24 #x43)
      ;; Ù
      (217 9 0 11 9 #x20 #x10 #x41 #x41 #x81 #x82 #x102 #x102 #x104 #x88 #x70)
      ;; Ú
      (218 9 0 11 9 #x10 #x20 #x41 #x41 #x81 #x82 #x102 #x102 #x104 #x88 #x70)
      ;; Û
      (219 9 0 11 9 #x20 #x50 #x41 #x41 #x81 #x82 #x102 #x102 #x104 #x88 #x70)
      ;; Ü
      (220 9 0 11 9 #x50 #x0 #x41 #x41 #x81 #x82 #x102 #x102 #x104 #x88 #x70)
      ;; Ý
      (221 9 1 11 7 #x8 #x10 #x41 #x42 #x44 #x28 #x10 #x10 #x20 #x20 #x20)
      ;; à
      (224 8 0 10 7 #x10 #x8 #x0 #x1e #x21 #x7 #x39 #x42 #x46 #x3a)
      ;; á
      (225 8 0 10 7 #x8 #x10 #x0 #x1e #x21 #x7 #x39 #x42 #x46 #x3a)
      ;; â
      (226 8 0 10 7 #x10 #x28 #x0 #x1e #x21 #x7 #x39 #x42 #x46 #x3a)
      ;; ã
      (227 8 0 10 7 #x14 #x28 #x0 #x1e #x21 #x7 #x39 #x42 #x46 #x3a)
      ;; ä
      (228 8 0 9 7 #x28 #x0 #x1e #x21 #x7 #x39 #x42 #x46 #x3a)
      ;; å
      (229 8 0 11 7 #x10 #x28 #x10 #x0 #x1e #x21 #x7 #x39 #x42 #x46 #x3a)
      ;; ç
      (231 8 0 7 7 #xe #x11 #x20 #x20 #x40 #x44 #x38 #x8 #x10)
      ;; è
      (232 8 0 10 7 #x10 #x8 #x0 #xe #x11 #x22 #x3c #x40 #x42 #x3c)
      ;; é
      (233 8 0 10 7 #x8 #x10 #x0 #xe #x11 #x22 #x3c #x40 #x42 #x3c)
      ;; ê
      (234 8 0 10 7 #x10 #x28 #x0 #xe #x11 #x22 #x3c #x40 #x42 #x3c)
      ;; ë
      (235 8 0 9 7 #x28 #x0 #xe #x11 #x22 #x3c #x40 #x42 #x3c)
      ;; ì
      (236 5 1 10 2 #x2 #x1 #x0 #x3 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; í
      (237 5 1 10 2 #x1 #x2 #x0 #x3 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; î
      (238 5 0 10 3 #x2 #x5 #x0 #x3 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; ï
      (239 5 0 9 3 #x5 #x0 #x3 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; ñ
      (241 8 0 10 7 #x14 #x28 #x0 #x26 #x29 #x31 #x21 #x42 #x42 #x42)
      ;; ò
      (242 7 0 10 6 #x8 #x4 #x0 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; ó
      (243 7 0 10 6 #x4 #x8 #x0 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; ô
      (244 7 0 10 6 #x8 #x14 #x0 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; õ
      (245 7 0 10 6 #xa #x14 #x0 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; ö
      (246 7 0 9 6 #x14 #x0 #xe #x11 #x21 #x21 #x21 #x22 #x1c)
      ;; ù
      (249 8 0 10 7 #x10 #x8 #x0 #x21 #x21 #x21 #x42 #x46 #x4a #x32)
      ;; ú
      (250 8 0 10 7 #x8 #x10 #x0 #x21 #x21 #x21 #x42 #x46 #x4a #x32)
      ;; û
      (251 8 0 10 7 #x10 #x28 #x0 #x21 #x21 #x21 #x42 #x46 #x4a #x32)
      ;; ü
      (252 8 0 9 7 #x28 #x0 #x21 #x21 #x21 #x42 #x46 #x4a #x32)
      ;; ý
      (253 8 -1 10 8 #x8 #x10 #x0 #x21 #x21 #x21 #x22 #x24 #x18 #x10 #x20 #xc0)
      ;; ÿ
      (255 8 -1 9 8 #x28 #x0 #x21 #x21 #x21 #x22 #x24 #x18 #x10 #x20 #xc0)
      ;; α
      (945 9 0 7 8 #x2 #x62 #x94 #x88 #x88 #x94 #x63)
      ;; β
      (946 9 1 9 6 #xe #x11 #x11 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20)
      ;; γ
      (947 9 0 7 7 #x41 #x22 #x14 #x18 #x10 #x30 #x30 #x30 #x20)
      ;; δ
      (948 9 0 11 7 #x1c #x22 #x21 #x20 #x10 #xc #x12 #x21 #x41 #x41 #x3e)
      ;; ε
      (949 9 1 7 5 #x7 #x8 #x10 #x1f #x10 #x8 #x7)
      ;; λ
      (955 9 0 11 7 #x40 #x20 #x20 #x10 #x8 #x8 #x14 #x12 #x22 #x21 #x41)
      ;; π
      (960 9 0 7 7 #x7f #x22 #x22 #x22 #x22 #x22 #x22)
      ;; –
      (8211 8 0 5 7 #x7f)
      ;; —
      (8212 10 0 5 10 #x3ff)
      ;; ‘
      (8216 4 1 11 2 #x3 #x3 #x1 #x2)
      ;; ’
      (8217 4 1 11 2 #x3 #x3 #x1 #x2)
      ;; “
      (8220 7 1 11 5 #x9 #x1b #x12 #x12)
      ;; ”
      (8221 7 1 11 5 #x9 #x1b #x12 #x12)
      ;; …
      (8230 18 0 2 14 #x30c3 #x30c3)
      ;; ←
      (8592 9 0 7 7 #x10 #x20 #x7f #x20 #x10)
      ;; ↑
      (8593 9 1 9 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 9 0 7 7 #x4 #x2 #x7f #x2 #x4)
      ;; ↓
      (8595 9 1 10 5 #x4 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 9 0 8 6 #x4 #x2 #x3f #x2 #x4 #x8 #x10 #x3f #x10 #x8)
      ;; ↳
      (8627 9 0 11 7 #x40 #x40 #x40 #x40 #x44 #x42 #x7f #x2 #x4)
      ;; ∀
      (8704 9 0 11 7 #x41 #x41 #x41 #x3e #x22 #x22 #x14 #x14 #x14 #x8 #x8)
      ;; ∂
      (8706 9 1 10 6 #x1c #x22 #x1 #x1 #xf #x11 #x21 #x21 #x22 #x1c)
      ;; ∃
      (8707 9 0 11 7 #x7f #x1 #x1 #x1 #x1 #x1f #x1 #x1 #x1 #x1 #x7f)
      ;; −
      (8722 9 0 5 7 #x7f)
      ;; ∞
      (8734 11 0 7 9 #x6e #x91 #x111 #x111 #x112 #xec)
      ;; ∧
      (8743 9 0 6 7 #x8 #x14 #x22 #x41)
      ;; ∨
      (8744 9 0 6 7 #x41 #x22 #x14 #x8)
      ;; ∩
      (8745 8 0 8 6 #x1e #x21 #x21 #x21 #x21 #x21 #x21)
      ;; ∪
      (8746 8 0 8 6 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ∫
      (8747 9 0 11 7 #x6 #x9 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x48 #x30)
      ;; ≠
      (8800 9 0 9 7 #x2 #x2 #x4 #x7f #x8 #x10 #x7f #x20 #x40)
      ;; ≡
      (8801 9 0 7 7 #x7f #x0 #x7f #x0 #x7f)
      ;; ≤
      (8804 9 0 8 7 #x3 #xc #x30 #x40 #x30 #xc #x3 #x7f)
      ;; ≥
      (8805 9 0 8 7 #x60 #x18 #x6 #x1 #x6 #x18 #x60 #x7f)
      ;; ⊂
      (8834 9 0 7 7 #x3f #x40 #x40 #x40 #x40 #x3f)
      ;; ⊃
      (8835 9 0 7 7 #x7e #x1 #x1 #x1 #x1 #x7e)
      ;; ⊕
      (8853 9 0 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 9 0 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 8 1 6 4 #x6 #xf #xf #x6)
      ;; ▶
      (9654 8 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 9 0 9 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ◊
      (9674 9 0 9 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 15 1 12 13 #x40 #xa0 #xa0 #x110 #x150 #x248 #x248 #x444 #x444
        #x802 #x842 #x1fff)
      ;; ✓
      (10003 8 0 8 7 #x1 #x2 #x2 #x4 #x44 #x28 #x28 #x10)
      ;; ❚
      (10074 4 1 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera JESS14" 14 12 2
      ;; the slug, which a character the face lacks draws
      (#f 7 1 12 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x1f)
      ;; space
      (32 7)
      ;; !
      (33 5 1 12 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x0 #x1 #x1)
      ;; "
      (34 7 0 11 5 #x9 #x1b #x12 #x12)
      ;; #
      (35 9 0 11 8 #x12 #x12 #x12 #x7f #x24 #x24 #x24 #xfe #x48 #x48 #x48)
      ;; $
      (36 9 0 11 7 #x8 #x1e #x29 #x48 #x48 #x3e #x9 #x9 #x4a #x3c #x8)
      ;; %
      (37 9 0 11 8 #x63 #x9d #x92 #x64 #x4 #x8 #x10 #x16 #x29 #x49 #x46)
      ;; &
      (38 9 0 11 7 #x38 #x44 #x44 #x44 #x28 #x18 #x28 #x45 #x42 #x46 #x39)
      ;; '
      (39 4 0 12 2 #x3 #x3 #x1 #x2)
      ;; (
      (40 7 1 12 3 #x1 #x2 #x2 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x2 #x2 #x1)
      ;; )
      (41 7 0 12 3 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4)
      ;; *
      (42 9 0 9 7 #x8 #x49 #x2a #x1c #x1c #x2a #x49 #x8)
      ;; +
      (43 9 0 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8)
      ;; ,
      (44 5 -1 2 3 #x3 #x3 #x2 #x4)
      ;; -
      (45 9 0 5 7 #x7f)
      ;; .
      (46 6 0 2 2 #x3 #x3)
      ;; /
      (47 9 1 12 6 #x1 #x3 #x2 #x6 #x4 #xc #x8 #x18 #x10 #x30 #x20 #x20)
      ;; 0
      (48 9 0 12 7 #x1e #x21 #x41 #x43 #x45 #x49 #x51 #x61 #x41 #x41 #x42 #x3c)
      ;; 1
      (49 9 1 12 5 #x4 #x4 #x1c #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; 2
      (50 9 0 12 7 #x1e #x21 #x41 #x1 #x2 #x4 #x8 #x10 #x20 #x40 #x40 #x7f)
      ;; 3
      (51 9 0 12 7 #x1e #x21 #x41 #x1 #x2 #x1e #x1 #x1 #x1 #x1 #x2 #x7c)
      ;; 4
      (52 9 0 12 7 #x2 #x6 #xa #x12 #x22 #x42 #x7f #x2 #x2 #x2 #x2 #x2)
      ;; 5
      (53 9 0 12 7 #x1f #x20 #x20 #x40 #x7e #x1 #x1 #x1 #x1 #x1 #x42 #x3c)
      ;; 6
      (54 9 0 12 7 #x1e #x20 #x40 #x40 #x40 #x5e #x61 #x41 #x41 #x41 #x42 #x3c)
      ;; 7
      (55 9 0 12 7 #x7f #x41 #x1 #x1 #x2 #x4 #x4 #x8 #x8 #x10 #x10 #x10)
      ;; 8
      (56 9 0 12 7 #x1e #x21 #x41 #x41 #x42 #x34 #x1e #x21 #x41 #x41 #x42 #x3c)
      ;; 9
      (57 9 0 12 7 #x1e #x21 #x41 #x41 #x41 #x43 #x3d #x1 #x1 #x1 #x2 #x3c)
      ;; :
      (58 6 1 6 2 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; ;
      (59 5 -1 6 3 #x3 #x3 #x0 #x0 #x3 #x3 #x2 #x4)
      ;; <
      (60 9 0 9 7 #x1 #x6 #x8 #x30 #x40 #x30 #x8 #x6 #x1)
      ;; =
      (61 9 0 6 7 #x7f #x0 #x0 #x7f)
      ;; >
      (62 9 0 9 7 #x40 #x30 #x8 #x6 #x1 #x6 #x8 #x30 #x40)
      ;; ?
      (63 9 0 12 7 #x3e #x41 #x41 #x1 #x2 #x4 #x8 #x8 #x0 #x0 #x8 #x8)
      ;; @
      (64 9 0 9 7 #x1e #x21 #x5d #x55 #x55 #x55 #x5e #x40 #x3e)
      ;; A
      (65 9 0 12 7 #x4 #xc #x12 #x12 #x21 #x21 #x3f #x41 #x41 #x41 #x41 #x41)
      ;; B
      (66 9 0 12 7 #x7e #x41 #x41 #x41 #x42 #x7e #x41 #x41 #x41 #x41 #x42 #x7c)
      ;; C
      (67 8 0 12 6 #xe #x11 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x21 #x1e)
      ;; D
      (68 9 0 12 7 #x7e #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x7c)
      ;; E
      (69 8 0 12 6 #x3f #x20 #x20 #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; F
      (70 8 0 12 6 #x3f #x20 #x20 #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x20 #x20)
      ;; G
      (71 9 0 12 7 #x1e #x21 #x40 #x40 #x40 #x40 #x47 #x41 #x41 #x41 #x42 #x3c)
      ;; H
      (72 9 0 12 7 #x41 #x41 #x41 #x41 #x41 #x7f #x41 #x41 #x41 #x41 #x41 #x41)
      ;; I
      (73 7 0 12 5 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; J
      (74 9 0 12 6 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x21 #x21 #x1e)
      ;; K
      (75 9 0 12 8 #x82 #x84 #x88 #x90 #xa0 #xc0 #xa0 #x90 #x88 #x84 #x82 #x81)
      ;; L
      (76 8 0 12 6 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; M
      (77 10 0 12 8 #x81 #x81 #xc3 #xa5 #xa5 #x99 #x89 #x89 #x81 #x81 #x81
        #x81)
      ;; N
      (78 9 0 12 7 #x41 #x41 #x61 #x51 #x51 #x49 #x49 #x45 #x45 #x43 #x41 #x41)
      ;; O
      (79 9 0 12 7 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x3c)
      ;; P
      (80 9 0 12 7 #x7e #x41 #x41 #x41 #x41 #x42 #x7c #x40 #x40 #x40 #x40 #x40)
      ;; Q
      (81 9 0 12 7 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x59 #x46 #x3e
        #x1)
      ;; R
      (82 9 0 12 7 #x7e #x41 #x41 #x41 #x41 #x42 #x7c #x50 #x48 #x44 #x42 #x41)
      ;; S
      (83 9 0 12 7 #x1e #x21 #x40 #x40 #x40 #x3e #x1 #x1 #x1 #x1 #x42 #x3c)
      ;; T
      (84 9 0 12 7 #x7f #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; U
      (85 9 0 12 7 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; V
      (86 9 0 12 7 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x22 #x24 #x24 #x18 #x10)
      ;; W
      (87 13 0 12 11 #x401 #x401 #x401 #x421 #x422 #x422 #x462 #x4a4 #x4a4
        #x294 #x318 #x210)
      ;; X
      (88 9 -1 12 9 #x81 #x42 #x44 #x24 #x28 #x10 #x10 #x28 #x48 #x44 #x84
        #x102)
      ;; Y
      (89 9 0 12 7 #x41 #x41 #x22 #x22 #x14 #x8 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; Z
      (90 9 0 12 7 #x7f #x2 #x2 #x4 #x4 #x8 #x8 #x10 #x10 #x20 #x20 #x7f)
      ;; [
      (91 7 2 12 3 #x7 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x7)
      ;; \
      (92 9 1 12 6 #x20 #x20 #x10 #x10 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ]
      (93 7 0 12 3 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x7)
      ;; ^
      (94 9 0 12 7 #x8 #x14 #x22 #x41)
      ;; _
      (95 9 0 0 7 #x7f)
      ;; `
      (96 4 0 12 2 #x1 #x2 #x3 #x3)
      ;; a
      (97 8 0 8 6 #x1e #x21 #x1 #x1f #x21 #x21 #x23 #x1d)
      ;; b
      (98 8 0 12 6 #x20 #x20 #x20 #x20 #x2e #x31 #x21 #x21 #x21 #x21 #x22 #x3c)
      ;; c
      (99 8 0 8 6 #xe #x11 #x20 #x20 #x20 #x20 #x21 #x1e)
      ;; d
      (100 9 0 12 6 #x1 #x1 #x1 #x1 #xf #x11 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; e
      (101 8 0 8 6 #xe #x11 #x22 #x3c #x20 #x20 #x21 #x1e)
      ;; f
      (102 7 0 12 6 #x7 #x8 #x10 #x10 #x3e #x10 #x10 #x10 #x10 #x10 #x10 #x10)
      ;; g
      (103 8 0 8 6 #xe #x11 #x21 #x21 #x21 #x23 #x1d #x1 #x22 #x1c)
      ;; h
      (104 8 0 12 6 #x20 #x20 #x20 #x20 #x26 #x29 #x31 #x21 #x21 #x21 #x21
        #x21)
      ;; i
      (105 5 0 12 2 #x1 #x1 #x0 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; j
      (106 5 -2 12 5 #x1 #x1 #x0 #x0 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x12 #xc)
      ;; k
      (107 8 0 12 6 #x20 #x20 #x20 #x20 #x21 #x22 #x24 #x38 #x28 #x24 #x22
        #x21)
      ;; l
      (108 5 0 12 2 #x3 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; m
      (109 13 0 8 11 #x4c6 #x529 #x631 #x421 #x421 #x421 #x421 #x421)
      ;; n
      (110 8 0 8 6 #x26 #x29 #x31 #x21 #x21 #x21 #x21 #x21)
      ;; o
      (111 8 0 8 6 #xe #x11 #x21 #x21 #x21 #x21 #x22 #x1c)
      ;; p
      (112 8 0 8 6 #x2e #x31 #x21 #x21 #x21 #x21 #x22 #x3c #x20 #x20)
      ;; q
      (113 8 0 8 6 #xf #x11 #x21 #x21 #x21 #x21 #x23 #x1d #x1 #x1)
      ;; r
      (114 7 0 8 6 #x26 #x29 #x30 #x20 #x20 #x20 #x20 #x20)
      ;; s
      (115 8 0 8 6 #xe #x11 #x20 #x1e #x1 #x1 #x22 #x1c)
      ;; t
      (116 7 0 10 6 #x10 #x10 #x3c #x10 #x10 #x10 #x10 #x11 #x12 #xc)
      ;; u
      (117 8 0 8 6 #x21 #x21 #x21 #x21 #x21 #x23 #x25 #x19)
      ;; v
      (118 9 0 8 7 #x41 #x41 #x42 #x22 #x24 #x24 #x18 #x10)
      ;; w
      (119 11 0 8 9 #x101 #x101 #x111 #x111 #x112 #xaa #xcc #x88)
      ;; x
      (120 9 0 8 7 #x21 #x22 #x14 #x8 #x8 #x14 #x22 #x42)
      ;; y
      (121 8 -1 8 7 #x21 #x21 #x21 #x22 #x12 #x14 #x8 #x8 #x10 #x60)
      ;; z
      (122 8 0 8 6 #x1f #x21 #x2 #x4 #x8 #x10 #x21 #x3e)
      ;; {
      (123 9 0 11 7 #x7 #x8 #x8 #x8 #x18 #x70 #x18 #x8 #x8 #x8 #x7)
      ;; |
      (124 9 3 12 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; }
      (125 9 0 11 7 #x70 #x8 #x8 #x8 #xc #x7 #xc #x8 #x8 #x8 #x70)
      ;; ~
      (126 9 0 9 6 #x19 #x26)
      ;; ¬
      (172 9 0 5 7 #x7f #x1 #x1)
      ;; °
      (176 6 1 12 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 0 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8 #x7f)
      ;; µ
      (181 8 0 8 6 #x21 #x21 #x21 #x21 #x21 #x23 #x25 #x19 #x20 #x20)
      ;; ·
      (183 8 1 6 4 #x6 #xf #xf #x6)
      ;; À
      (192 9 0 12 7 #x10 #x8 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41 #x41)
      ;; Á
      (193 9 0 12 7 #x8 #x10 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41 #x41)
      ;; Â
      (194 9 0 12 7 #x10 #x28 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41 #x41)
      ;; Ã
      (195 9 0 12 7 #x14 #x28 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41 #x41)
      ;; Ä
      (196 9 0 12 7 #x28 #x0 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41 #x41)
      ;; Å
      (197 9 0 12 7 #x10 #x28 #x10 #x4 #xc #x12 #x21 #x3f #x41 #x41 #x41 #x41)
      ;; Ç
      (199 8 0 12 6 #xe #x11 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x21 #x1e
        #x4 #x8)
      ;; È
      (200 8 0 12 6 #x8 #x4 #x3f #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; É
      (201 8 0 12 6 #x4 #x8 #x3f #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; Ê
      (202 8 0 12 6 #x8 #x14 #x3f #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; Ë
      (203 8 0 12 6 #x14 #x0 #x3f #x20 #x20 #x3c #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; Ì
      (204 7 0 12 5 #x8 #x4 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Í
      (205 7 0 12 5 #x4 #x8 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Î
      (206 7 0 12 5 #x8 #x14 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Ï
      (207 7 0 12 5 #x14 #x0 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Ñ
      (209 9 0 12 7 #x14 #x28 #x41 #x41 #x61 #x51 #x49 #x45 #x45 #x43 #x41
        #x41)
      ;; Ò
      (210 9 0 12 7 #x10 #x8 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x3c)
      ;; Ó
      (211 9 0 12 7 #x8 #x10 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x3c)
      ;; Ô
      (212 9 0 12 7 #x10 #x28 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x41 #x42
        #x3c)
      ;; Õ
      (213 9 0 12 7 #x14 #x28 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x41 #x42
        #x3c)
      ;; Ö
      (214 9 0 12 7 #x28 #x0 #x1e #x21 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x3c)
      ;; ×
      (215 9 0 8 7 #x21 #x22 #x14 #x8 #x8 #x14 #x22 #x42)
      ;; Ù
      (217 9 0 12 7 #x10 #x8 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ú
      (218 9 0 12 7 #x8 #x10 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Û
      (219 9 0 12 7 #x10 #x28 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22
        #x1c)
      ;; Ü
      (220 9 0 12 7 #x28 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ý
      (221 9 0 12 7 #x8 #x10 #x41 #x41 #x22 #x14 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; à
      (224 8 0 11 6 #x8 #x4 #x0 #x1e #x21 #x1 #x1f #x21 #x21 #x23 #x1d)
      ;; á
      (225 8 0 11 6 #x4 #x8 #x0 #x1e #x21 #x1 #x1f #x21 #x21 #x23 #x1d)
      ;; â
      (226 8 0 11 6 #x8 #x14 #x0 #x1e #x21 #x1 #x1f #x21 #x21 #x23 #x1d)
      ;; ã
      (227 8 0 11 6 #xa #x14 #x0 #x1e #x21 #x1 #x1f #x21 #x21 #x23 #x1d)
      ;; ä
      (228 8 0 10 6 #x14 #x0 #x1e #x21 #x1 #x1f #x21 #x21 #x23 #x1d)
      ;; å
      (229 8 0 12 6 #x8 #x14 #x8 #x0 #x1e #x21 #x1 #x1f #x21 #x21 #x23 #x1d)
      ;; ç
      (231 8 0 8 6 #xe #x11 #x20 #x20 #x20 #x20 #x21 #x1e #x4 #x8)
      ;; è
      (232 8 0 11 6 #x8 #x4 #x0 #xe #x11 #x22 #x3c #x20 #x20 #x21 #x1e)
      ;; é
      (233 8 0 11 6 #x4 #x8 #x0 #xe #x11 #x22 #x3c #x20 #x20 #x21 #x1e)
      ;; ê
      (234 8 0 11 6 #x8 #x14 #x0 #xe #x11 #x22 #x3c #x20 #x20 #x21 #x1e)
      ;; ë
      (235 8 0 10 6 #x14 #x0 #xe #x11 #x22 #x3c #x20 #x20 #x21 #x1e)
      ;; ì
      (236 5 0 11 2 #x2 #x1 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; í
      (237 5 0 11 2 #x1 #x2 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; î
      (238 5 -1 11 3 #x2 #x5 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ï
      (239 5 -1 10 3 #x5 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ñ
      (241 8 0 11 6 #xa #x14 #x0 #x26 #x29 #x31 #x21 #x21 #x21 #x21 #x21)
      ;; ò
      (242 8 0 11 6 #x8 #x4 #x0 #xe #x11 #x21 #x21 #x21 #x21 #x22 #x1c)
      ;; ó
      (243 8 0 11 6 #x4 #x8 #x0 #xe #x11 #x21 #x21 #x21 #x21 #x22 #x1c)
      ;; ô
      (244 8 0 11 6 #x8 #x14 #x0 #xe #x11 #x21 #x21 #x21 #x21 #x22 #x1c)
      ;; õ
      (245 8 0 11 6 #xa #x14 #x0 #xe #x11 #x21 #x21 #x21 #x21 #x22 #x1c)
      ;; ö
      (246 8 0 10 6 #x14 #x0 #xe #x11 #x21 #x21 #x21 #x21 #x22 #x1c)
      ;; ù
      (249 8 0 11 6 #x8 #x4 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x25 #x19)
      ;; ú
      (250 8 0 11 6 #x4 #x8 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x25 #x19)
      ;; û
      (251 8 0 11 6 #x8 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x25 #x19)
      ;; ü
      (252 8 0 10 6 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x25 #x19)
      ;; ý
      (253 8 -1 11 7 #x8 #x10 #x0 #x21 #x21 #x21 #x22 #x12 #x14 #x8 #x8 #x10
        #x60)
      ;; ÿ
      (255 8 -1 10 7 #x28 #x0 #x21 #x21 #x21 #x22 #x12 #x14 #x8 #x8 #x10 #x60)
      ;; α
      (945 9 0 7 8 #x2 #x62 #x94 #x88 #x88 #x94 #x63)
      ;; β
      (946 9 1 9 6 #xe #x11 #x11 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20)
      ;; γ
      (947 9 0 7 7 #x41 #x22 #x14 #x18 #x10 #x30 #x30 #x30 #x20)
      ;; δ
      (948 9 0 11 7 #x1c #x22 #x21 #x20 #x10 #xc #x12 #x21 #x41 #x41 #x3e)
      ;; ε
      (949 9 1 7 5 #x7 #x8 #x10 #x1f #x10 #x8 #x7)
      ;; λ
      (955 9 0 11 7 #x40 #x20 #x20 #x10 #x8 #x8 #x14 #x12 #x22 #x21 #x41)
      ;; π
      (960 9 0 7 7 #x7f #x22 #x22 #x22 #x22 #x22 #x22)
      ;; –
      (8211 8 0 5 7 #x7f)
      ;; —
      (8212 10 0 5 10 #x3ff)
      ;; ‘
      (8216 4 0 12 2 #x3 #x3 #x1 #x2)
      ;; ’
      (8217 4 0 12 2 #x3 #x3 #x1 #x2)
      ;; “
      (8220 7 0 11 5 #x9 #x1b #x12 #x12)
      ;; ”
      (8221 7 0 11 5 #x9 #x1b #x12 #x12)
      ;; …
      (8230 18 0 2 14 #x30c3 #x30c3)
      ;; ←
      (8592 9 0 7 7 #x10 #x20 #x7f #x20 #x10)
      ;; ↑
      (8593 9 1 9 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 9 0 7 7 #x4 #x2 #x7f #x2 #x4)
      ;; ↓
      (8595 9 1 10 5 #x4 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 9 0 8 6 #x4 #x2 #x3f #x2 #x4 #x8 #x10 #x3f #x10 #x8)
      ;; ↳
      (8627 9 0 12 7 #x40 #x40 #x40 #x40 #x40 #x44 #x42 #x7f #x2 #x4)
      ;; ∀
      (8704 9 0 11 7 #x41 #x41 #x41 #x3e #x22 #x22 #x14 #x14 #x14 #x8 #x8)
      ;; ∂
      (8706 9 1 10 6 #x1c #x22 #x1 #x1 #xf #x11 #x21 #x21 #x22 #x1c)
      ;; ∃
      (8707 9 0 11 7 #x7f #x1 #x1 #x1 #x1 #x1f #x1 #x1 #x1 #x1 #x7f)
      ;; −
      (8722 9 0 5 7 #x7f)
      ;; ∞
      (8734 11 0 7 9 #xee #x111 #x111 #x111 #x111 #xee)
      ;; ∧
      (8743 9 0 6 7 #x8 #x14 #x22 #x41)
      ;; ∨
      (8744 9 0 6 7 #x41 #x22 #x14 #x8)
      ;; ∩
      (8745 8 0 8 6 #x1e #x21 #x21 #x21 #x21 #x21 #x21)
      ;; ∪
      (8746 8 0 8 6 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ∫
      (8747 9 0 11 7 #x6 #x9 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x48 #x30)
      ;; ≠
      (8800 9 0 9 7 #x2 #x2 #x4 #x7f #x8 #x10 #x7f #x20 #x40)
      ;; ≡
      (8801 9 0 7 7 #x7f #x0 #x7f #x0 #x7f)
      ;; ≤
      (8804 9 0 8 7 #x3 #xc #x30 #x40 #x30 #xc #x3 #x7f)
      ;; ≥
      (8805 9 0 8 7 #x60 #x18 #x6 #x1 #x6 #x18 #x60 #x7f)
      ;; ⊂
      (8834 9 0 7 7 #x3f #x40 #x40 #x40 #x40 #x3f)
      ;; ⊃
      (8835 9 0 7 7 #x7e #x1 #x1 #x1 #x1 #x7e)
      ;; ⊕
      (8853 9 0 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 9 0 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 8 1 6 4 #x6 #xf #xf #x6)
      ;; ▶
      (9654 8 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 9 0 9 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ◊
      (9674 9 0 9 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ⚙
      (9881 15 1 13 13 #xe0 #x4e4 #xffe #x7fc #x7fc #x1f1f #x1f1f #x1f1f #x7fc
        #x7fc #xffe #x4e4 #xe0)
      ;; ⚠
      (9888 15 1 13 13 #x40 #x40 #xa0 #x110 #x110 #x150 #x248 #x444 #x444
        #x444 #x802 #x1041 #x1fff)
      ;; ✓
      (10003 9 0 9 8 #x1 #x1 #x2 #x2 #x84 #x44 #x28 #x28 #x10)
      ;; ❚
      (10074 4 1 12 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera JESS14 Bold" 14 12 2
      ;; the slug, which a character the face lacks draws
      (#f 7 1 12 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x1f)
      ;; space
      (32 7)
      ;; !
      (33 5 1 12 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; "
      (34 9 1 11 7 #x33 #x77 #x66 #x66)
      ;; #
      (35 10 0 11 10 #x66 #x66 #x66 #x1ff #xcc #xcc #xcc #x3fe #x198 #x198
        #x198)
      ;; $
      (36 9 0 11 8 #x18 #x7e #xdb #x98 #xd8 #x7e #x1b #x1b #xde #x7c #x18)
      ;; %
      (37 10 1 11 9 #xe6 #x1ba #x1b6 #xec #xc #x18 #x30 #x2e #x7b #xdb #xce)
      ;; &
      (38 11 1 11 9 #xf0 #x198 #x198 #x198 #xd0 #x70 #xd8 #x19b #x18c #x19e
        #xf3)
      ;; '
      (39 5 1 12 3 #x7 #x7 #x3 #x6 #x4)
      ;; (
      (40 6 1 12 4 #x3 #x6 #x6 #xc #xc #xc #xc #xc #xc #xc #x6 #x6 #x3)
      ;; )
      (41 6 1 12 4 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc)
      ;; *
      (42 9 0 9 8 #x18 #x99 #x5a #x3c #x3c #x5a #x99 #x18)
      ;; +
      (43 10 1 8 8 #x18 #x18 #x18 #xff #xff #x18 #x18 #x18)
      ;; ,
      (44 6 0 2 4 #x7 #x7 #x6 #xc)
      ;; -
      (45 9 1 5 7 #x7f #x7f)
      ;; .
      (46 6 1 2 3 #x7 #x7)
      ;; /
      (47 9 1 12 7 #x3 #x7 #x6 #xe #xc #x1c #x18 #x38 #x30 #x70 #x60 #x60)
      ;; 0
      (48 9 1 12 7 #x1e #x33 #x63 #x63 #x67 #x6b #x73 #x63 #x63 #x63 #x66 #x3c)
      ;; 1
      (49 9 2 12 6 #xc #x1c #x3c #xc #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; 2
      (50 9 1 12 7 #x3e #x63 #x43 #x3 #x3 #x6 #xc #x18 #x30 #x60 #x60 #x7f)
      ;; 3
      (51 9 1 12 7 #x3e #x63 #x43 #x3 #x3 #x1e #x3 #x3 #x3 #x3 #x6 #x7c)
      ;; 4
      (52 10 1 12 8 #x6 #xe #x16 #x36 #x66 #xc6 #xff #x6 #x6 #x6 #x6 #x6)
      ;; 5
      (53 9 0 12 8 #x3f #x60 #x60 #xc0 #xfe #x7 #x3 #x3 #x3 #x3 #xc6 #x7c)
      ;; 6
      (54 9 1 12 7 #x1e #x30 #x60 #x60 #x60 #x6e #x73 #x63 #x63 #x63 #x66 #x3c)
      ;; 7
      (55 9 1 12 7 #x7f #x43 #x3 #x3 #x6 #xc #xc #x18 #x18 #x30 #x30 #x30)
      ;; 8
      (56 9 1 12 7 #x1e #x33 #x63 #x63 #x62 #x34 #x1e #x23 #x63 #x63 #x62 #x3c)
      ;; 9
      (57 9 1 12 7 #x1e #x33 #x63 #x63 #x63 #x67 #x3b #x3 #x3 #x3 #x6 #x3c)
      ;; :
      (58 6 1 6 3 #x7 #x7 #x0 #x0 #x7 #x7)
      ;; ;
      (59 6 0 6 4 #x7 #x7 #x0 #x0 #x7 #x7 #x6 #xc)
      ;; <
      (60 9 1 9 7 #x1 #x7 #xe #x38 #x60 #x38 #xe #x7 #x1)
      ;; =
      (61 9 1 6 7 #x7f #x7f #x0 #x7f #x7f)
      ;; >
      (62 9 1 9 7 #x40 #x70 #x38 #xe #x3 #xe #x38 #x70 #x40)
      ;; ?
      (63 9 1 12 7 #x3e #x63 #x43 #x3 #x6 #xc #x18 #x18 #x0 #x0 #x18 #x18)
      ;; @
      (64 13 1 10 11 #xf8 #x18c #x376 #x653 #x6db #x6db #x656 #x37c #x180 #xfe)
      ;; A
      (65 10 1 12 8 #x8 #x1c #x36 #x36 #x63 #x63 #x7f #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; B
      (66 11 1 12 8 #xfe #xc3 #xc3 #xc3 #xc6 #xfe #xc3 #xc3 #xc3 #xc3 #xc6
        #xfc)
      ;; C
      (67 9 1 12 7 #x1e #x33 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x63 #x3e)
      ;; D
      (68 10 1 12 8 #xfe #xc7 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6
        #xfc)
      ;; E
      (69 9 1 12 7 #x7f #x60 #x60 #x60 #x60 #x7c #x60 #x60 #x60 #x60 #x60 #x7f)
      ;; F
      (70 9 1 12 7 #x7f #x60 #x60 #x60 #x60 #x7c #x60 #x60 #x60 #x60 #x60 #x60)
      ;; G
      (71 10 1 12 8 #x3e #x63 #xc0 #xc0 #xc0 #xc0 #xcf #xc3 #xc3 #xc3 #xe6
        #x7c)
      ;; H
      (72 10 1 12 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3
        #xc3)
      ;; I
      (73 8 1 12 6 #x3f #xc #xc #xc #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; J
      (74 9 1 12 7 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x63 #x63 #x3e)
      ;; K
      (75 11 1 12 10 #x306 #x30c #x318 #x330 #x360 #x3c0 #x360 #x330 #x318
        #x30c #x306 #x303)
      ;; L
      (76 9 1 12 7 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x7f)
      ;; M
      (77 12 1 12 10 #x303 #x303 #x387 #x3cb #x34b #x373 #x333 #x323 #x303
        #x303 #x303 #x303)
      ;; N
      (78 11 1 12 9 #x183 #x183 #x1c3 #x1e3 #x1a3 #x1b3 #x193 #x19b #x18b
        #x18f #x187 #x183)
      ;; O
      (79 10 1 12 8 #x3e #x63 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6
        #x7c)
      ;; P
      (80 10 1 12 8 #xfe #xc7 #xc3 #xc3 #xc3 #xc6 #xfc #xc0 #xc0 #xc0 #xc0
        #xc0)
      ;; Q
      (81 10 1 12 8 #x3e #x63 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xdb #xce
        #x7e #x3)
      ;; R
      (82 10 1 12 8 #xfe #xc3 #xc3 #xc3 #xc3 #xc6 #xfc #xd8 #xcc #xc6 #xc3
        #xc3)
      ;; S
      (83 10 1 12 8 #x3e #x67 #xc0 #xc0 #xc0 #x7e #x7 #x3 #x3 #x3 #xe6 #x7c)
      ;; T
      (84 10 1 12 8 #xff #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18
        #x18)
      ;; U
      (85 10 1 12 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66
        #x3c)
      ;; V
      (86 10 1 12 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6 #x66 #x6c #x6c #x38
        #x10)
      ;; W
      (87 14 1 12 12 #xc03 #xc03 #xc03 #xc63 #xc66 #xc66 #xce6 #xd6c #xd2c
        #x728 #x638 #x630)
      ;; X
      (88 10 0 12 10 #x183 #xc6 #xc4 #x6c #x78 #x30 #x30 #x78 #xc8 #xcc #x18c
        #x306)
      ;; Y
      (89 11 1 12 9 #x183 #x183 #xc6 #xc6 #x4c #x78 #x30 #x30 #x30 #x30 #x30
        #x30)
      ;; Z
      (90 10 0 12 9 #xff #x1c3 #x6 #xc #xc #x18 #x18 #x30 #x60 #x60 #xc7 #x1fe)
      ;; [
      (91 7 2 12 4 #xf #xc #xc #xc #xc #xc #xc #xc #xc #xc #xc #xf)
      ;; \
      (92 9 1 12 7 #x60 #x60 #x30 #x30 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ]
      (93 7 1 12 4 #xf #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #xf)
      ;; ^
      (94 9 0 12 7 #x8 #x1c #x36 #x63)
      ;; _
      (95 9 0 0 8 #xff #xff)
      ;; `
      (96 5 1 12 3 #x1 #x2 #x6 #x7 #x7)
      ;; a
      (97 9 1 8 7 #x3e #x63 #x3 #x3f #x63 #x63 #x67 #x3b)
      ;; b
      (98 9 1 12 7 #x60 #x60 #x60 #x60 #x7c #x63 #x63 #x63 #x63 #x63 #x66 #x7c)
      ;; c
      (99 8 1 8 6 #xe #x1b #x30 #x30 #x30 #x30 #x33 #x1e)
      ;; d
      (100 9 1 12 7 #x3 #x3 #x3 #x3 #x1f #x33 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; e
      (101 9 1 8 7 #x1e #x33 #x63 #x7e #x60 #x60 #x63 #x3e)
      ;; f
      (102 7 1 12 6 #x7 #xc #x18 #x18 #x3e #x18 #x18 #x18 #x18 #x18 #x18 #x18)
      ;; g
      (103 9 1 8 7 #x1e #x33 #x63 #x63 #x63 #x67 #x3b #x3 #x66 #x3c)
      ;; h
      (104 10 1 12 7 #x60 #x60 #x60 #x60 #x66 #x6f #x73 #x63 #x63 #x63 #x63
        #x63)
      ;; i
      (105 6 1 12 3 #x3 #x3 #x0 #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; j
      (106 6 -2 12 6 #x3 #x3 #x0 #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x36 #x1c)
      ;; k
      (107 9 1 12 7 #x60 #x60 #x60 #x60 #x63 #x66 #x6c #x78 #x78 #x6c #x66
        #x63)
      ;; l
      (108 6 1 12 3 #x7 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; m
      (109 14 1 8 12 #xcc6 #xdef #xe73 #xc63 #xc63 #xc63 #xc63 #xc63)
      ;; n
      (110 9 1 8 7 #x66 #x6f #x73 #x63 #x63 #x63 #x63 #x63)
      ;; o
      (111 9 1 8 7 #x1e #x33 #x63 #x63 #x63 #x63 #x66 #x3c)
      ;; p
      (112 9 1 8 7 #x6e #x73 #x63 #x63 #x63 #x63 #x66 #x7c #x60 #x60)
      ;; q
      (113 9 1 8 7 #x1f #x33 #x63 #x63 #x63 #x63 #x67 #x3b #x3 #x3)
      ;; r
      (114 8 1 8 7 #x66 #x6f #x78 #x60 #x60 #x60 #x60 #x60)
      ;; s
      (115 9 1 8 7 #x1e #x33 #x60 #x3e #x7 #x3 #x66 #x3c)
      ;; t
      (116 8 1 10 7 #x30 #x30 #x7c #x30 #x30 #x30 #x30 #x33 #x36 #x1c)
      ;; u
      (117 9 1 8 7 #x63 #x63 #x63 #x63 #x63 #x67 #x7b #x33)
      ;; v
      (118 10 1 8 8 #xc3 #xc3 #xc6 #x66 #x6c #x6c #x38 #x10)
      ;; w
      (119 12 1 8 10 #x303 #x303 #x333 #x333 #x333 #x1aa #x1cc #x18c)
      ;; x
      (120 9 0 8 8 #x63 #x66 #x3c #x18 #x18 #x3c #x66 #xc6)
      ;; y
      (121 9 0 8 8 #x63 #x63 #x63 #x66 #x26 #x3c #x18 #x18 #x30 #xe0)
      ;; z
      (122 9 1 8 7 #x3f #x63 #x6 #xc #x18 #x30 #x63 #x7e)
      ;; {
      (123 9 1 11 7 #x7 #xc #xc #xc #x18 #x70 #x70 #x18 #xc #xc #xc #x7)
      ;; |
      (124 9 3 12 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; }
      (125 9 0 11 7 #x70 #x18 #x18 #x18 #x1c #x7 #x7 #x1c #x18 #x18 #x18 #x70)
      ;; ~
      (126 9 0 10 6 #x19 #x3f #x26)
      ;; ¬
      (172 9 0 5 7 #x7f #x1 #x1)
      ;; °
      (176 6 1 12 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 0 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8 #x7f)
      ;; µ
      (181 9 1 8 7 #x63 #x63 #x63 #x63 #x63 #x67 #x7b #x33 #x60 #x60)
      ;; ·
      (183 8 1 6 5 #xe #x1f #x1f #xe)
      ;; À
      (192 10 1 12 8 #x30 #x18 #x8 #x1c #x36 #x63 #x7f #xc3 #xc3 #xc3 #xc3
        #xc3)
      ;; Á
      (193 10 1 12 8 #x18 #x30 #x8 #x1c #x36 #x63 #x7f #xc3 #xc3 #xc3 #xc3
        #xc3)
      ;; Â
      (194 10 1 12 8 #x18 #x3c #x8 #x1c #x36 #x63 #x7f #xc3 #xc3 #xc3 #xc3
        #xc3)
      ;; Ã
      (195 10 1 12 8 #x3c #x78 #x8 #x1c #x36 #x63 #x7f #xc3 #xc3 #xc3 #xc3
        #xc3)
      ;; Ä
      (196 10 1 12 8 #x3c #x0 #x8 #x1c #x36 #x63 #x7f #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; Å
      (197 10 1 12 8 #x18 #x3c #x18 #x8 #x1c #x36 #x63 #x7f #xc3 #xc3 #xc3
        #xc3)
      ;; Ç
      (199 9 1 12 7 #x1e #x33 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x63
        #x3e #x18 #x30)
      ;; È
      (200 9 1 12 7 #x30 #x18 #x7f #x60 #x60 #x7c #x60 #x60 #x60 #x60 #x60
        #x7f)
      ;; É
      (201 9 1 12 7 #x18 #x30 #x7f #x60 #x60 #x7c #x60 #x60 #x60 #x60 #x60
        #x7f)
      ;; Ê
      (202 9 1 12 7 #x18 #x3c #x7f #x60 #x60 #x7c #x60 #x60 #x60 #x60 #x60
        #x7f)
      ;; Ë
      (203 9 1 12 7 #x3c #x0 #x7f #x60 #x60 #x7c #x60 #x60 #x60 #x60 #x60 #x7f)
      ;; Ì
      (204 8 1 12 6 #x18 #xc #x3f #xc #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Í
      (205 8 1 12 6 #xc #x18 #x3f #xc #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Î
      (206 8 1 12 6 #xc #x1e #x3f #xc #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Ï
      (207 8 1 12 6 #x1e #x0 #x3f #xc #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Ñ
      (209 11 1 12 9 #x78 #xf0 #x183 #x1e3 #x1a3 #x1b3 #x193 #x19b #x18b #x18f
        #x187 #x183)
      ;; Ò
      (210 10 1 12 8 #x30 #x18 #x3e #x63 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6
        #x7c)
      ;; Ó
      (211 10 1 12 8 #x18 #x30 #x3e #x63 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6
        #x7c)
      ;; Ô
      (212 10 1 12 8 #x18 #x3c #x3e #x63 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6
        #x7c)
      ;; Õ
      (213 10 1 12 8 #x3c #x78 #x3e #x63 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6
        #x7c)
      ;; Ö
      (214 10 1 12 8 #x3c #x0 #x3e #x63 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6
        #x7c)
      ;; ×
      (215 9 0 8 8 #x63 #x66 #x3c #x18 #x18 #x3c #x66 #xc6)
      ;; Ù
      (217 10 1 12 8 #x30 #x18 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66
        #x3c)
      ;; Ú
      (218 10 1 12 8 #x18 #x30 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66
        #x3c)
      ;; Û
      (219 10 1 12 8 #x18 #x3c #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66
        #x3c)
      ;; Ü
      (220 10 1 12 8 #x3c #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66
        #x3c)
      ;; Ý
      (221 11 1 12 9 #x30 #x60 #x183 #xc6 #x4c #x78 #x30 #x30 #x30 #x30 #x30
        #x30)
      ;; à
      (224 9 1 11 7 #x30 #x18 #x0 #x3e #x63 #x3 #x3f #x63 #x63 #x67 #x3b)
      ;; á
      (225 9 1 11 7 #x18 #x30 #x0 #x3e #x63 #x3 #x3f #x63 #x63 #x67 #x3b)
      ;; â
      (226 9 1 11 7 #x18 #x3c #x0 #x3e #x63 #x3 #x3f #x63 #x63 #x67 #x3b)
      ;; ã
      (227 9 1 11 7 #x3c #x78 #x0 #x3e #x63 #x3 #x3f #x63 #x63 #x67 #x3b)
      ;; ä
      (228 9 1 10 7 #x3c #x0 #x3e #x63 #x3 #x3f #x63 #x63 #x67 #x3b)
      ;; å
      (229 9 1 12 7 #x18 #x3c #x18 #x0 #x3e #x63 #x3 #x3f #x63 #x63 #x67 #x3b)
      ;; ç
      (231 8 1 8 6 #xe #x1b #x30 #x30 #x30 #x30 #x33 #x1e #xc #x18)
      ;; è
      (232 9 1 11 7 #x30 #x18 #x0 #x1e #x33 #x63 #x7e #x60 #x60 #x63 #x3e)
      ;; é
      (233 9 1 11 7 #x18 #x30 #x0 #x1e #x33 #x63 #x7e #x60 #x60 #x63 #x3e)
      ;; ê
      (234 9 1 11 7 #x18 #x3c #x0 #x1e #x33 #x63 #x7e #x60 #x60 #x63 #x3e)
      ;; ë
      (235 9 1 10 7 #x3c #x0 #x1e #x33 #x63 #x7e #x60 #x60 #x63 #x3e)
      ;; ì
      (236 6 0 11 4 #xc #x6 #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; í
      (237 6 0 11 4 #x6 #xc #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; î
      (238 6 0 11 4 #x6 #xf #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; ï
      (239 6 0 10 4 #xf #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; ñ
      (241 9 1 11 7 #x3c #x78 #x0 #x66 #x6f #x73 #x63 #x63 #x63 #x63 #x63)
      ;; ò
      (242 9 1 11 7 #x30 #x18 #x0 #x1e #x33 #x63 #x63 #x63 #x63 #x66 #x3c)
      ;; ó
      (243 9 1 11 7 #x18 #x30 #x0 #x1e #x33 #x63 #x63 #x63 #x63 #x66 #x3c)
      ;; ô
      (244 9 1 11 7 #x18 #x3c #x0 #x1e #x33 #x63 #x63 #x63 #x63 #x66 #x3c)
      ;; õ
      (245 9 1 11 7 #x3c #x78 #x0 #x1e #x33 #x63 #x63 #x63 #x63 #x66 #x3c)
      ;; ö
      (246 9 1 10 7 #x3c #x0 #x1e #x33 #x63 #x63 #x63 #x63 #x66 #x3c)
      ;; ù
      (249 9 1 11 7 #x30 #x18 #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x7b #x33)
      ;; ú
      (250 9 1 11 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x7b #x33)
      ;; û
      (251 9 1 11 7 #x18 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x7b #x33)
      ;; ü
      (252 9 1 10 7 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x7b #x33)
      ;; ý
      (253 9 0 11 8 #x18 #x30 #x0 #x63 #x63 #x63 #x66 #x26 #x3c #x18 #x18 #x30
        #xe0)
      ;; ÿ
      (255 9 0 10 8 #x3c #x0 #x63 #x63 #x63 #x66 #x26 #x3c #x18 #x18 #x30 #xe0)
      ;; α
      (945 9 0 7 8 #x2 #x62 #x94 #x88 #x88 #x94 #x63)
      ;; β
      (946 9 1 9 6 #xe #x11 #x11 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20)
      ;; γ
      (947 9 0 7 7 #x41 #x22 #x14 #x18 #x10 #x30 #x30 #x30 #x20)
      ;; δ
      (948 9 0 11 7 #x1c #x22 #x21 #x20 #x10 #xc #x12 #x21 #x41 #x41 #x3e)
      ;; ε
      (949 9 1 7 5 #x7 #x8 #x10 #x1f #x10 #x8 #x7)
      ;; λ
      (955 9 0 11 7 #x40 #x20 #x20 #x10 #x8 #x8 #x14 #x12 #x22 #x21 #x41)
      ;; π
      (960 9 0 7 7 #x7f #x22 #x22 #x22 #x22 #x22 #x22)
      ;; –
      (8211 9 0 5 8 #xff #xff)
      ;; —
      (8212 12 0 5 12 #xfff #xfff)
      ;; ‘
      (8216 5 1 12 3 #x7 #x7 #x3 #x6 #x4)
      ;; ’
      (8217 5 1 12 3 #x7 #x7 #x3 #x6 #x4)
      ;; “
      (8220 9 1 11 7 #x33 #x77 #x66 #x66)
      ;; ”
      (8221 9 1 11 7 #x33 #x77 #x66 #x66)
      ;; …
      (8230 18 1 2 15 #x71c7 #x71c7)
      ;; ←
      (8592 9 0 7 7 #x10 #x20 #x7f #x20 #x10)
      ;; ↑
      (8593 9 1 9 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 9 0 7 7 #x4 #x2 #x7f #x2 #x4)
      ;; ↓
      (8595 9 1 10 5 #x4 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 9 0 8 6 #x4 #x2 #x3f #x2 #x4 #x8 #x10 #x3f #x10 #x8)
      ;; ↳
      (8627 9 0 12 7 #x60 #x60 #x60 #x60 #x60 #x64 #x62 #x7f #x2 #x4)
      ;; ∀
      (8704 9 0 11 7 #x41 #x41 #x41 #x3e #x22 #x22 #x14 #x14 #x14 #x8 #x8)
      ;; ∂
      (8706 9 1 10 6 #x1c #x22 #x1 #x1 #xf #x11 #x21 #x21 #x22 #x1c)
      ;; ∃
      (8707 9 0 11 7 #x7f #x1 #x1 #x1 #x1 #x1f #x1 #x1 #x1 #x1 #x7f)
      ;; −
      (8722 10 1 5 8 #xff #xff)
      ;; ∞
      (8734 11 0 7 9 #xee #x111 #x111 #x111 #x111 #xee)
      ;; ∧
      (8743 9 0 6 7 #x8 #x14 #x22 #x41)
      ;; ∨
      (8744 9 0 6 7 #x41 #x22 #x14 #x8)
      ;; ∩
      (8745 8 0 8 6 #x1e #x21 #x21 #x21 #x21 #x21 #x21)
      ;; ∪
      (8746 8 0 8 6 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ∫
      (8747 10 1 11 8 #xe #x1b #x19 #x18 #x18 #x18 #x18 #x18 #x98 #xd8 #x60)
      ;; ≠
      (8800 9 0 9 7 #x2 #x2 #x4 #x7f #x8 #x10 #x7f #x20 #x40)
      ;; ≡
      (8801 9 0 7 7 #x7f #x0 #x7f #x0 #x7f)
      ;; ≤
      (8804 9 0 8 7 #x3 #xc #x30 #x40 #x30 #xc #x3 #x7f)
      ;; ≥
      (8805 9 0 8 7 #x60 #x18 #x6 #x1 #x6 #x18 #x60 #x7f)
      ;; ⊂
      (8834 9 0 7 7 #x3f #x40 #x40 #x40 #x40 #x3f)
      ;; ⊃
      (8835 9 0 7 7 #x7e #x1 #x1 #x1 #x1 #x7e)
      ;; ⊕
      (8853 9 0 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 9 0 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 8 1 6 5 #xe #x1f #x1f #xe)
      ;; ▶
      (9654 8 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 9 0 9 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ◊
      (9674 9 0 9 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ⚙
      (9881 15 1 13 13 #xe0 #x4e4 #xffe #x7fc #x7fc #x1f1f #x1f1f #x1f1f #x7fc
        #x7fc #xffe #x4e4 #xe0)
      ;; ⚠
      (9888 15 1 13 13 #x40 #x40 #xa0 #x110 #x110 #x150 #x248 #x444 #x444
        #x444 #x802 #x1041 #x1fff)
      ;; ✓
      (10003 10 0 9 9 #x3 #x3 #x6 #x6 #x18c #xcc #x78 #x78 #x30)
      ;; ❚
      (10074 6 1 12 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("Genera JESS14 Italic" 14 12 2
      ;; the slug, which a character the face lacks draws
      (#f 8 1 12 6 #x3f #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x3f)
      ;; space
      (32 8)
      ;; !
      (33 6 1 12 4 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x0 #x0 #x8 #x8)
      ;; "
      (34 8 2 11 5 #x9 #x1b #x12 #x12)
      ;; #
      (35 10 1 11 9 #x12 #x12 #x12 #x7f #x48 #x48 #x48 #x1fc #x120 #x120 #x120)
      ;; $
      (36 10 0 11 9 #x8 #x1e #x29 #x48 #x90 #x7c #x12 #x12 #x128 #xf0 #x20)
      ;; %
      (37 10 1 11 9 #x63 #x9d #x92 #x64 #x8 #x10 #x20 #x2c #xa4 #x124 #x118)
      ;; &
      (38 10 0 11 8 #x1c #x22 #x22 #x22 #x28 #x18 #x28 #x45 #x84 #x8c #x72)
      ;; '
      (39 5 2 12 3 #x3 #x6 #x2 #x4)
      ;; (
      (40 8 1 12 6 #x1 #x4 #x4 #x8 #x8 #x10 #x10 #x10 #x10 #x20 #x10 #x10 #x8)
      ;; )
      (41 8 0 12 5 #x2 #x2 #x2 #x1 #x1 #x2 #x2 #x2 #x2 #x4 #x8 #x8 #x10)
      ;; *
      (42 10 0 9 9 #x8 #x49 #x54 #x38 #x38 #x54 #x124 #x20)
      ;; +
      (43 10 1 8 7 #x4 #x8 #x8 #x7f #x8 #x10 #x10)
      ;; ,
      (44 6 -2 2 4 #x3 #x3 #x2 #x8)
      ;; -
      (45 10 1 5 7 #x7f)
      ;; .
      (46 7 0 2 2 #x3 #x3)
      ;; /
      (47 10 1 12 9 #x1 #x6 #x4 #xc #x8 #x30 #x20 #x60 #x40 #x180 #x100 #x100)
      ;; 0
      (48 10 0 12 9 #xf #x21 #x41 #x43 #x45 #x92 #xa2 #xc2 #x82 #x104 #x108
        #xf0)
      ;; 1
      (49 10 1 12 6 #x1 #x2 #xe #x2 #x2 #x4 #x4 #x4 #x4 #x8 #x8 #x3e)
      ;; 2
      (50 10 0 12 9 #xf #x21 #x41 #x1 #x2 #x8 #x10 #x20 #x40 #x100 #x100 #x1fc)
      ;; 3
      (51 10 0 12 9 #xf #x21 #x41 #x1 #x2 #x3c #x2 #x2 #x2 #x4 #x8 #x1f0)
      ;; 4
      (52 10 1 12 8 #x1 #x6 #xa #x12 #x22 #x84 #xfe #x4 #x4 #x8 #x8 #x8)
      ;; 5
      (53 10 0 12 10 #x1f #x40 #x40 #x80 #xfc #x4 #x4 #x4 #x4 #x8 #x210 #x1e0)
      ;; 6
      (54 10 0 12 9 #xf #x20 #x40 #x40 #x40 #xbc #xc2 #x82 #x82 #x104 #x108
        #xf0)
      ;; 7
      (55 10 2 12 8 #x7f #x82 #x2 #x2 #x4 #x10 #x10 #x20 #x20 #x80 #x80 #x80)
      ;; 8
      (56 10 0 12 9 #xf #x21 #x41 #x41 #x42 #x68 #x3c #x42 #x82 #x104 #x108
        #xf0)
      ;; 9
      (57 10 1 12 8 #xf #x21 #x41 #x41 #x41 #x86 #x7a #x2 #x2 #x4 #x8 #xf0)
      ;; :
      (58 7 1 6 3 #x3 #x3 #x0 #x0 #x6 #x6)
      ;; ;
      (59 6 -2 6 5 #x3 #x3 #x0 #x0 #x6 #x6 #x4 #x10)
      ;; <
      (60 10 1 9 8 #x1 #x6 #x10 #x60 #x80 #x60 #x20 #x18 #x4)
      ;; =
      (61 10 0 6 8 #x7f #x0 #x0 #xfe)
      ;; >
      (62 10 0 9 8 #x20 #x18 #x8 #x6 #x1 #x6 #x10 #x60 #x80)
      ;; ?
      (63 10 2 12 7 #x1f #x41 #x41 #x1 #x2 #x8 #x10 #x10 #x0 #x0 #x20 #x20)
      ;; @
      (64 10 0 9 9 #x3e #x41 #x99 #xaa #xaa #x12a #x13c #x100 #xf8)
      ;; A
      (65 10 0 12 9 #x2 #xc #x12 #x12 #x21 #x42 #x7e #x82 #x82 #x104 #x104
        #x104)
      ;; B
      (66 10 0 12 9 #x3f #x41 #x41 #x41 #x42 #xfc #x82 #x82 #x82 #x104 #x108
        #x1f0)
      ;; C
      (67 9 0 12 8 #x7 #x11 #x20 #x20 #x20 #x40 #x40 #x40 #x40 #x80 #x84 #x78)
      ;; D
      (68 10 0 12 9 #x3f #x41 #x41 #x41 #x41 #x82 #x82 #x82 #x82 #x104 #x108
        #x1f0)
      ;; E
      (69 9 0 12 9 #x3f #x40 #x40 #x40 #x40 #xf0 #x80 #x80 #x80 #x100 #x100
        #x1f8)
      ;; F
      (70 9 0 12 9 #x3f #x40 #x40 #x40 #x40 #xf0 #x80 #x80 #x80 #x100 #x100
        #x100)
      ;; G
      (71 10 0 12 9 #xf #x21 #x40 #x40 #x40 #x80 #x8e #x82 #x82 #x104 #x108
        #xf0)
      ;; H
      (72 10 0 12 10 #x41 #x82 #x82 #x82 #x82 #x1fc #x104 #x104 #x104 #x208
        #x208 #x208)
      ;; I
      (73 8 0 12 8 #x1f #x8 #x8 #x8 #x8 #x10 #x10 #x10 #x10 #x20 #x20 #xf8)
      ;; J
      (74 10 0 12 9 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x4 #x108 #x108 #xf0)
      ;; K
      (75 10 0 12 10 #x41 #x84 #x88 #x90 #xa0 #x180 #x140 #x120 #x110 #x210
        #x208 #x204)
      ;; L
      (76 9 0 12 6 #x4 #x8 #x8 #x8 #x8 #x10 #x10 #x10 #x10 #x20 #x20 #x3f)
      ;; M
      (77 11 0 12 11 #x81 #x102 #x186 #x14a #x14a #x264 #x224 #x224 #x204
        #x408 #x408 #x408)
      ;; N
      (78 10 0 12 10 #x41 #x82 #xc2 #xa2 #xa2 #x124 #x124 #x114 #x114 #x218
        #x208 #x208)
      ;; O
      (79 10 0 12 9 #xf #x21 #x41 #x41 #x41 #x82 #x82 #x82 #x82 #x104 #x108
        #xf0)
      ;; P
      (80 10 0 12 9 #x3f #x41 #x41 #x41 #x41 #x84 #xf8 #x80 #x80 #x100 #x100
        #x100)
      ;; Q
      (81 10 0 12 9 #xf #x21 #x41 #x41 #x41 #x82 #x82 #x82 #x82 #x164 #x118
        #xf8 #x4)
      ;; R
      (82 10 0 12 9 #x3f #x41 #x41 #x41 #x41 #x84 #xf8 #xa0 #x90 #x110 #x108
        #x104)
      ;; S
      (83 10 0 12 9 #xf #x21 #x40 #x40 #x40 #x7c #x2 #x2 #x2 #x4 #x108 #xf0)
      ;; T
      (84 10 3 12 7 #x7f #x10 #x10 #x10 #x10 #x20 #x20 #x20 #x20 #x40 #x40
        #x40)
      ;; U
      (85 10 0 12 10 #x41 #x82 #x82 #x82 #x82 #x104 #x104 #x104 #x104 #x208
        #x110 #xe0)
      ;; V
      (86 10 1 12 9 #x41 #x82 #x82 #x82 #x82 #x104 #x108 #x88 #x90 #x120 #xc0
        #x80)
      ;; W
      (87 14 1 12 13 #x401 #x802 #x802 #x842 #x844 #x1088 #x1188 #x1290 #x1290
        #x14a0 #x18c0 #x1080)
      ;; X
      (88 10 -1 12 12 #x81 #x84 #x88 #x48 #x50 #x40 #x40 #xa0 #x120 #x220
        #x420 #x810)
      ;; Y
      (89 10 2 12 8 #x41 #x82 #x44 #x44 #x28 #x20 #x20 #x20 #x20 #x40 #x40
        #x40)
      ;; Z
      (90 10 0 12 10 #x7f #x4 #x4 #x8 #x8 #x20 #x20 #x40 #x40 #x100 #x100
        #x3f8)
      ;; [
      (91 8 2 12 6 #x7 #x8 #x8 #x8 #x8 #x10 #x10 #x10 #x10 #x20 #x20 #x38)
      ;; \
      (92 10 3 12 4 #x4 #x8 #x4 #x4 #x2 #x4 #x2 #x2 #x1 #x2 #x1 #x1)
      ;; ]
      (93 8 0 12 6 #x7 #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x4 #x8 #x8 #x38)
      ;; ^
      (94 10 2 12 7 #x4 #x14 #x22 #x41)
      ;; _
      (95 10 0 0 7 #x7f)
      ;; `
      (96 5 2 12 3 #x1 #x4 #x6 #x6)
      ;; a
      (97 9 0 8 7 #xf #x11 #x1 #x1f #x21 #x42 #x46 #x3a)
      ;; b
      (98 9 0 12 7 #x8 #x10 #x10 #x10 #x17 #x39 #x21 #x21 #x21 #x42 #x44 #x78)
      ;; c
      (99 9 0 8 7 #xf #x11 #x20 #x20 #x20 #x40 #x42 #x3c)
      ;; d
      (100 10 0 12 9 #x1 #x2 #x2 #x2 #x3e #x44 #x84 #x84 #x84 #x108 #x118 #xe8)
      ;; e
      (101 9 0 8 7 #xf #x11 #x22 #x3c #x20 #x40 #x42 #x3c)
      ;; f
      (102 8 1 12 8 #xf #x10 #x20 #x20 #xfc #x40 #x40 #x40 #x40 #x80 #x80 #x80)
      ;; g
      (103 9 0 8 7 #xf #x11 #x21 #x21 #x21 #x46 #x3a #x2 #x44 #x78)
      ;; h
      (104 9 0 12 7 #x8 #x10 #x10 #x10 #x17 #x29 #x31 #x21 #x21 #x42 #x42 #x42)
      ;; i
      (105 6 1 12 4 #x1 #x2 #x0 #x0 #x6 #x4 #x4 #x4 #x4 #x8 #x8 #x8)
      ;; j
      (106 6 -2 12 8 #x1 #x2 #x0 #x0 #xe #x4 #x4 #x4 #x4 #x8 #x8 #x8 #x90 #xc0)
      ;; k
      (107 9 0 12 8 #x10 #x20 #x20 #x20 #x23 #x44 #x48 #x70 #x50 #x90 #x88
        #x84)
      ;; l
      (108 6 1 12 4 #x3 #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x4 #x8 #x8 #x8)
      ;; m
      (109 14 0 8 12 #x4e7 #x529 #x631 #x421 #x421 #x842 #x842 #x842)
      ;; n
      (110 9 0 8 7 #x27 #x29 #x31 #x21 #x21 #x42 #x42 #x42)
      ;; o
      (111 9 0 8 7 #xf #x11 #x21 #x21 #x21 #x42 #x44 #x38)
      ;; p
      (112 9 -1 8 8 #x1f #x31 #x21 #x21 #x21 #x42 #x44 #x78 #x40 #x80)
      ;; q
      (113 9 0 8 8 #x1f #x22 #x42 #x42 #x42 #x84 #x8c #x74 #x4 #x8)
      ;; r
      (114 8 0 8 7 #x27 #x29 #x30 #x20 #x20 #x40 #x40 #x40)
      ;; s
      (115 9 0 8 7 #xf #x11 #x20 #x1e #x1 #x2 #x44 #x38)
      ;; t
      (116 8 1 10 5 #x4 #x4 #x1f #x8 #x8 #x8 #x8 #x11 #x12 #xc)
      ;; u
      (117 9 0 8 8 #x21 #x42 #x42 #x42 #x42 #x8c #x94 #x64)
      ;; v
      (118 10 1 8 8 #x41 #x82 #x84 #x44 #x48 #x90 #x60 #x40)
      ;; w
      (119 12 1 8 10 #x101 #x202 #x222 #x222 #x224 #x2a8 #x330 #x220)
      ;; x
      (120 10 0 8 8 #x11 #x22 #x14 #x8 #x18 #x28 #x44 #x84)
      ;; y
      (121 9 -2 8 10 #x21 #x42 #x42 #x44 #x48 #x50 #x20 #x20 #x40 #x380)
      ;; z
      (122 9 0 8 8 #x3f #x42 #x4 #x8 #x30 #x40 #x84 #xf8)
      ;; {
      (123 10 1 11 8 #x7 #x8 #x8 #x8 #x30 #xe0 #x30 #x10 #x20 #x20 #x1c)
      ;; |
      (124 10 2 12 5 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x4 #x8 #x8 #x8 #x8 #x10)
      ;; }
      (125 10 0 11 8 #x38 #x4 #x4 #x4 #xc #x7 #xc #x8 #x10 #x10 #xe0)
      ;; ~
      (126 10 2 9 6 #x19 #x26)
      ;; ¬
      (172 10 1 5 7 #x7f #x1 #x2)
      ;; °
      (176 6 1 12 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 10 0 8 8 #x4 #x8 #x8 #x7f #x8 #x10 #x10 #xfe)
      ;; µ
      (181 9 0 8 8 #x21 #x42 #x42 #x42 #x42 #x8c #x94 #x64 #x80 #x80)
      ;; ·
      (183 9 2 6 4 #x6 #xf #xf #xc)
      ;; À
      (192 10 0 12 9 #x20 #x10 #x2 #xc #x12 #x21 #x42 #x7e #x82 #x104 #x104
        #x104)
      ;; Á
      (193 10 0 12 9 #x10 #x20 #x2 #xc #x12 #x21 #x42 #x7e #x82 #x104 #x104
        #x104)
      ;; Â
      (194 10 0 12 9 #x20 #x50 #x2 #xc #x12 #x21 #x42 #x7e #x82 #x104 #x104
        #x104)
      ;; Ã
      (195 10 0 12 9 #x28 #x50 #x2 #xc #x12 #x21 #x42 #x7e #x82 #x104 #x104
        #x104)
      ;; Ä
      (196 10 0 12 9 #x50 #x0 #x2 #xc #x12 #x21 #x42 #x7e #x82 #x104 #x104
        #x104)
      ;; Å
      (197 10 0 12 9 #x20 #x50 #x20 #x2 #xc #x12 #x21 #x42 #x7e #x82 #x104
        #x104)
      ;; Ç
      (199 9 0 12 8 #x7 #x11 #x20 #x20 #x20 #x40 #x40 #x40 #x40 #x80 #x84 #x78
        #x8 #x10)
      ;; È
      (200 9 0 12 9 #x20 #x10 #x3f #x40 #x40 #xf0 #x80 #x80 #x80 #x100 #x100
        #x1f8)
      ;; É
      (201 9 0 12 9 #x10 #x20 #x3f #x40 #x40 #xf0 #x80 #x80 #x80 #x100 #x100
        #x1f8)
      ;; Ê
      (202 9 0 12 9 #x20 #x50 #x3f #x40 #x40 #xf0 #x80 #x80 #x80 #x100 #x100
        #x1f8)
      ;; Ë
      (203 9 0 12 9 #x50 #x0 #x3f #x40 #x40 #xf0 #x80 #x80 #x80 #x100 #x100
        #x1f8)
      ;; Ì
      (204 8 0 12 8 #x10 #x8 #x1f #x8 #x8 #x8 #x10 #x10 #x10 #x20 #x20 #xf8)
      ;; Í
      (205 8 0 12 8 #x8 #x10 #x1f #x8 #x8 #x8 #x10 #x10 #x10 #x20 #x20 #xf8)
      ;; Î
      (206 8 0 12 8 #x10 #x28 #x1f #x8 #x8 #x8 #x10 #x10 #x10 #x20 #x20 #xf8)
      ;; Ï
      (207 8 0 12 8 #x28 #x0 #x1f #x8 #x8 #x8 #x10 #x10 #x10 #x20 #x20 #xf8)
      ;; Ñ
      (209 10 0 12 10 #x28 #x50 #x41 #x82 #xc2 #xa2 #x124 #x114 #x114 #x218
        #x208 #x208)
      ;; Ò
      (210 10 0 12 9 #x20 #x10 #xf #x21 #x41 #x41 #x82 #x82 #x82 #x104 #x108
        #xf0)
      ;; Ó
      (211 10 0 12 9 #x10 #x20 #xf #x21 #x41 #x41 #x82 #x82 #x82 #x104 #x108
        #xf0)
      ;; Ô
      (212 10 0 12 9 #x20 #x50 #xf #x21 #x41 #x41 #x82 #x82 #x82 #x104 #x108
        #xf0)
      ;; Õ
      (213 10 0 12 9 #x28 #x50 #xf #x21 #x41 #x41 #x82 #x82 #x82 #x104 #x108
        #xf0)
      ;; Ö
      (214 10 0 12 9 #x50 #x0 #xf #x21 #x41 #x41 #x82 #x82 #x82 #x104 #x108
        #xf0)
      ;; ×
      (215 10 0 8 8 #x11 #x22 #x14 #x8 #x18 #x28 #x44 #x84)
      ;; Ù
      (217 10 0 12 10 #x20 #x10 #x41 #x82 #x82 #x82 #x104 #x104 #x104 #x208
        #x110 #xe0)
      ;; Ú
      (218 10 0 12 10 #x10 #x20 #x41 #x82 #x82 #x82 #x104 #x104 #x104 #x208
        #x110 #xe0)
      ;; Û
      (219 10 0 12 10 #x20 #x50 #x41 #x82 #x82 #x82 #x104 #x104 #x104 #x208
        #x110 #xe0)
      ;; Ü
      (220 10 0 12 10 #x50 #x0 #x41 #x82 #x82 #x82 #x104 #x104 #x104 #x208
        #x110 #xe0)
      ;; Ý
      (221 10 2 12 8 #x8 #x10 #x41 #x82 #x44 #x28 #x20 #x20 #x20 #x40 #x40
        #x40)
      ;; à
      (224 9 0 11 7 #x10 #x8 #x0 #xf #x11 #x1 #x1f #x21 #x42 #x46 #x3a)
      ;; á
      (225 9 0 11 7 #x8 #x10 #x0 #xf #x11 #x1 #x1f #x21 #x42 #x46 #x3a)
      ;; â
      (226 9 0 11 7 #x10 #x28 #x0 #xf #x11 #x1 #x1f #x21 #x42 #x46 #x3a)
      ;; ã
      (227 9 0 11 7 #x14 #x28 #x0 #xf #x11 #x1 #x1f #x21 #x42 #x46 #x3a)
      ;; ä
      (228 9 0 10 7 #x28 #x0 #xf #x11 #x1 #x1f #x21 #x42 #x46 #x3a)
      ;; å
      (229 9 0 12 7 #x10 #x28 #x10 #x0 #xf #x11 #x1 #x1f #x21 #x42 #x46 #x3a)
      ;; ç
      (231 9 0 8 7 #xf #x11 #x20 #x20 #x20 #x40 #x42 #x3c #x8 #x10)
      ;; è
      (232 9 0 11 7 #x10 #x8 #x0 #xf #x11 #x22 #x3c #x20 #x40 #x42 #x3c)
      ;; é
      (233 9 0 11 7 #x8 #x10 #x0 #xf #x11 #x22 #x3c #x20 #x40 #x42 #x3c)
      ;; ê
      (234 9 0 11 7 #x10 #x28 #x0 #xf #x11 #x22 #x3c #x20 #x40 #x42 #x3c)
      ;; ë
      (235 9 0 10 7 #x28 #x0 #xf #x11 #x22 #x3c #x20 #x40 #x42 #x3c)
      ;; ì
      (236 6 1 11 3 #x4 #x2 #x0 #x3 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; í
      (237 6 1 11 3 #x2 #x4 #x0 #x3 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; î
      (238 6 0 11 4 #x4 #xa #x0 #x3 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; ï
      (239 6 0 10 4 #xa #x0 #x3 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; ñ
      (241 9 0 11 7 #x14 #x28 #x0 #x27 #x29 #x31 #x21 #x21 #x42 #x42 #x42)
      ;; ò
      (242 9 0 11 7 #x10 #x8 #x0 #xf #x11 #x21 #x21 #x21 #x42 #x44 #x38)
      ;; ó
      (243 9 0 11 7 #x8 #x10 #x0 #xf #x11 #x21 #x21 #x21 #x42 #x44 #x38)
      ;; ô
      (244 9 0 11 7 #x10 #x28 #x0 #xf #x11 #x21 #x21 #x21 #x42 #x44 #x38)
      ;; õ
      (245 9 0 11 7 #x14 #x28 #x0 #xf #x11 #x21 #x21 #x21 #x42 #x44 #x38)
      ;; ö
      (246 9 0 10 7 #x28 #x0 #xf #x11 #x21 #x21 #x21 #x42 #x44 #x38)
      ;; ù
      (249 9 0 11 8 #x10 #x8 #x0 #x21 #x42 #x42 #x42 #x42 #x8c #x94 #x64)
      ;; ú
      (250 9 0 11 8 #x8 #x10 #x0 #x21 #x42 #x42 #x42 #x42 #x8c #x94 #x64)
      ;; û
      (251 9 0 11 8 #x10 #x28 #x0 #x21 #x42 #x42 #x42 #x42 #x8c #x94 #x64)
      ;; ü
      (252 9 0 10 8 #x28 #x0 #x21 #x42 #x42 #x42 #x42 #x8c #x94 #x64)
      ;; ý
      (253 9 -2 11 10 #x10 #x20 #x0 #x21 #x42 #x42 #x44 #x48 #x50 #x20 #x20
        #x40 #x380)
      ;; ÿ
      (255 9 -2 10 10 #x50 #x0 #x21 #x42 #x42 #x44 #x48 #x50 #x20 #x20 #x40
        #x380)
      ;; α
      (945 10 0 7 8 #x1 #x31 #x4a #x44 #x88 #x94 #x63)
      ;; β
      (946 10 0 9 9 #xe #x11 #x22 #x42 #x7c #x42 #x84 #x84 #xf8 #x80 #x100)
      ;; γ
      (947 10 0 7 8 #x41 #x22 #x14 #x18 #x20 #x60 #x60 #x60 #x80)
      ;; δ
      (948 10 0 11 9 #x1c #x22 #x21 #x20 #x20 #x18 #x24 #x42 #x104 #x104 #xf8)
      ;; ε
      (949 10 1 7 6 #x7 #x8 #x10 #x1f #x20 #x10 #xe)
      ;; λ
      (955 10 0 11 7 #x10 #x8 #x8 #x4 #x4 #x4 #xa #x9 #x22 #x21 #x41)
      ;; π
      (960 10 1 7 7 #x7f #x22 #x22 #x22 #x44 #x44 #x44)
      ;; –
      (8211 9 0 5 8 #xff)
      ;; —
      (8212 11 0 5 11 #x7ff)
      ;; ‘
      (8216 5 2 12 3 #x3 #x6 #x2 #x4)
      ;; ’
      (8217 5 2 12 3 #x3 #x6 #x2 #x4)
      ;; “
      (8220 8 2 11 5 #x9 #x1b #x12 #x12)
      ;; ”
      (8221 8 2 11 5 #x9 #x1b #x12 #x12)
      ;; …
      (8230 21 0 2 16 #xc183 #xc183)
      ;; ←
      (8592 10 1 7 7 #x10 #x20 #x7f #x20 #x20)
      ;; ↑
      (8593 10 2 9 5 #x2 #x7 #x15 #x4 #x4 #x4 #x8 #x8 #x8)
      ;; →
      (8594 10 1 7 7 #x4 #x2 #x7f #x2 #x8)
      ;; ↓
      (8595 10 2 10 5 #x2 #x2 #x2 #x4 #x4 #x4 #x15 #x1c #x8)
      ;; ↔
      (8596 10 0 8 7 #x2 #x2 #x3f #x2 #x4 #x10 #x20 #x7e #x20 #x20)
      ;; ↳
      (8627 10 1 12 7 #x40 #x40 #x40 #x40 #x40 #x44 #x42 #x7f #x2 #x8)
      ;; ∀
      (8704 10 2 11 7 #x41 #x41 #x41 #x3e #x44 #x44 #x28 #x28 #x50 #x20 #x20)
      ;; ∂
      (8706 10 1 10 8 #x1c #x22 #x1 #x2 #x1e #x22 #x42 #x84 #x88 #x70)
      ;; ∃
      (8707 10 0 11 9 #x7f #x1 #x1 #x1 #x2 #x3e #x2 #x2 #x4 #x4 #x1fc)
      ;; −
      (8722 10 1 5 7 #x7f)
      ;; ∞
      (8734 12 0 7 10 #xee #x111 #x111 #x111 #x222 #x1dc)
      ;; ∧
      (8743 10 0 6 7 #x4 #xa #x11 #x41)
      ;; ∨
      (8744 10 1 6 7 #x41 #x22 #x14 #x10)
      ;; ∩
      (8745 9 0 8 7 #xf #x21 #x21 #x21 #x21 #x42 #x42)
      ;; ∪
      (8746 9 0 8 8 #x21 #x42 #x42 #x42 #x42 #x84 #x78)
      ;; ∫
      (8747 10 0 11 9 #x6 #x9 #x8 #x8 #x10 #x10 #x10 #x10 #x20 #x120 #xc0)
      ;; ≠
      (8800 10 0 9 8 #x1 #x1 #x4 #x7f #x8 #x10 #xfe #x40 #x80)
      ;; ≡
      (8801 10 0 7 8 #x7f #x0 #x7f #x0 #xfe)
      ;; ≤
      (8804 10 0 8 9 #x3 #x18 #x60 #x80 #x60 #x30 #xc #x1fc)
      ;; ≥
      (8805 10 0 8 8 #x30 #x18 #x6 #x1 #x6 #x30 #xc0 #xfe)
      ;; ⊂
      (8834 10 0 7 8 #x3f #x40 #x40 #x40 #x80 #x7e)
      ;; ⊃
      (8835 10 0 7 8 #x7e #x1 #x1 #x1 #x2 #xfc)
      ;; ⊕
      (8853 10 1 8 7 #xe #x2a #x49 #x7f #x49 #x54 #x38)
      ;; ⊗
      (8855 10 1 8 7 #xe #x22 #x55 #x49 #x55 #x44 #x38)
      ;; ⋅
      (8901 9 2 6 4 #x6 #xf #xf #xc)
      ;; ▶
      (9654 8 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 10 1 9 7 #x4 #x4 #x14 #x22 #x41 #x22 #x28 #x10 #x10)
      ;; ◊
      (9674 10 1 9 7 #x4 #x4 #x14 #x22 #x41 #x22 #x28 #x10 #x10)
      ;; ⚙
      (9881 15 1 13 13 #xe0 #x4e4 #xffe #x7fc #x7fc #x1f1f #x1f1f #x1f1f #x7fc
        #x7fc #xffe #x4e4 #xe0)
      ;; ⚠
      (9888 15 1 13 13 #x40 #x40 #xa0 #x110 #x110 #x150 #x248 #x444 #x444
        #x444 #x802 #x1041 #x1fff)
      ;; ✓
      (10003 10 0 9 9 #x1 #x2 #x2 #x4 #x104 #x88 #x50 #x50 #x20)
      ;; ❚
      (10074 4 1 12 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera HL12" 14 11 3
      ;; the slug, which a character the face lacks draws
      (#f 6 1 10 4 #xf #x9 #x9 #x9 #x9 #x9 #x9 #x9 #x9 #xf)
      ;; space
      (32 6)
      ;; !
      (33 4 1 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x1 #x1)
      ;; "
      (34 5 1 10 3 #x5 #x5 #x5 #x5)
      ;; #
      (35 11 1 10 9 #x12 #x12 #x24 #xff #x24 #x48 #x1fe #x48 #x90 #x90)
      ;; $
      (36 9 1 11 7 #x8 #x3e #x49 #x48 #x48 #x3e #x9 #x9 #x49 #x49 #x3e #x8)
      ;; %
      (37 11 1 10 9 #xc4 #x124 #x128 #xc8 #x10 #x10 #x26 #x29 #x49 #x46)
      ;; &
      (38 10 1 10 8 #x38 #x44 #x44 #x28 #x30 #x52 #x8a #x84 #x86 #x79)
      ;; '
      (39 3 1 10 2 #x3 #x1 #x1 #x2)
      ;; (
      (40 5 1 10 3 #x1 #x2 #x2 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x2 #x2 #x1)
      ;; )
      (41 5 1 10 3 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4)
      ;; *
      (42 7 1 10 5 #x4 #x15 #xe #x15 #x4)
      ;; +
      (43 9 1 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8)
      ;; ,
      (44 6 2 2 2 #x3 #x3 #x1 #x2)
      ;; -
      (45 8 1 5 6 #x3f)
      ;; .
      (46 6 2 2 2 #x3 #x3)
      ;; /
      (47 5 0 10 5 #x1 #x1 #x2 #x2 #x4 #x4 #x8 #x8 #x10 #x10)
      ;; 0
      (48 9 1 10 7 #x1c #x22 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; 1
      (49 9 1 10 4 #x1 #x3 #xd #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; 2
      (50 9 1 10 7 #x3e #x41 #x41 #x1 #x2 #xc #x30 #x40 #x40 #x7f)
      ;; 3
      (51 9 1 10 7 #x3e #x41 #x41 #x2 #x1c #x3 #x1 #x41 #x41 #x3e)
      ;; 4
      (52 9 1 10 7 #x6 #xa #x12 #x12 #x22 #x42 #x7f #x2 #x2 #x2)
      ;; 5
      (53 9 1 10 7 #x3f #x20 #x40 #x7c #x42 #x1 #x1 #x1 #x42 #x3c)
      ;; 6
      (54 9 1 10 7 #x1e #x21 #x40 #x5c #x62 #x41 #x41 #x41 #x22 #x1c)
      ;; 7
      (55 9 1 10 7 #x7f #x1 #x1 #x2 #x4 #x8 #x8 #x10 #x10 #x10)
      ;; 8
      (56 9 1 10 7 #x1c #x22 #x41 #x22 #x1c #x22 #x41 #x41 #x22 #x1c)
      ;; 9
      (57 9 1 10 7 #x1c #x22 #x41 #x41 #x41 #x23 #x1d #x1 #x42 #x3c)
      ;; :
      (58 6 2 7 2 #x3 #x3 #x0 #x0 #x0 #x3 #x3)
      ;; ;
      (59 6 2 7 2 #x3 #x3 #x0 #x0 #x0 #x3 #x3 #x1 #x2)
      ;; <
      (60 7 1 10 5 #x1 #x2 #x4 #x8 #x10 #x10 #x8 #x4 #x2 #x1)
      ;; =
      (61 8 1 6 6 #x3f #x0 #x0 #x3f)
      ;; >
      (62 7 1 10 5 #x10 #x8 #x4 #x2 #x1 #x1 #x2 #x4 #x8 #x10)
      ;; ?
      (63 8 1 10 6 #x1e #x21 #x21 #x1 #x2 #x4 #x4 #x0 #x4 #x4)
      ;; @
      (64 12 1 10 10 #x78 #x186 #x132 #x249 #x249 #x249 #x24a #x134 #x180 #x7e)
      ;; A
      (65 11 1 10 9 #x10 #x28 #x28 #x44 #x44 #x82 #xfe #x82 #x101 #x101)
      ;; B
      (66 9 1 10 7 #x7e #x41 #x41 #x41 #x7e #x41 #x41 #x41 #x41 #x7e)
      ;; C
      (67 10 1 10 8 #x3c #x42 #x81 #x80 #x80 #x80 #x80 #x81 #x42 #x3c)
      ;; D
      (68 9 1 10 7 #x7c #x42 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x7c)
      ;; E
      (69 9 1 10 7 #x7f #x40 #x40 #x40 #x7e #x40 #x40 #x40 #x40 #x7f)
      ;; F
      (70 9 1 10 7 #x7f #x40 #x40 #x40 #x7e #x40 #x40 #x40 #x40 #x40)
      ;; G
      (71 10 1 10 8 #x3e #x41 #x81 #x80 #x80 #x8f #x81 #x81 #x43 #x3d)
      ;; H
      (72 10 1 10 8 #x81 #x81 #x81 #x81 #xff #x81 #x81 #x81 #x81 #x81)
      ;; I
      (73 5 2 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; J
      (74 8 1 10 6 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x21 #x21 #x1e)
      ;; K
      (75 9 1 10 8 #x82 #x84 #x88 #x90 #xa0 #xd0 #x88 #x84 #x82 #x81)
      ;; L
      (76 8 1 10 7 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x7f)
      ;; M
      (77 11 1 10 9 #x101 #x183 #x183 #x145 #x145 #x145 #x129 #x129 #x111
        #x111)
      ;; N
      (78 10 1 10 8 #xc1 #xa1 #xa1 #x91 #x91 #x89 #x89 #x85 #x85 #x83)
      ;; O
      (79 10 1 10 8 #x3c #x42 #x81 #x81 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; P
      (80 9 1 10 7 #x7e #x41 #x41 #x41 #x7e #x40 #x40 #x40 #x40 #x40)
      ;; Q
      (81 10 1 10 8 #x3c #x42 #x81 #x81 #x81 #x81 #x81 #x89 #x46 #x3e #x1)
      ;; R
      (82 9 1 10 7 #x7e #x41 #x41 #x41 #x7e #x42 #x41 #x41 #x41 #x41)
      ;; S
      (83 9 1 10 7 #x3e #x41 #x41 #x40 #x38 #x6 #x1 #x41 #x41 #x3e)
      ;; T
      (84 9 1 10 7 #x7f #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; U
      (85 10 1 10 8 #x81 #x81 #x81 #x81 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; V
      (86 11 1 10 9 #x101 #x101 #x82 #x82 #x82 #x44 #x44 #x28 #x28 #x10)
      ;; W
      (87 15 1 10 13 #x1041 #x1041 #x10a1 #x8a2 #x8a2 #x912 #x514 #x208 #x208
        #x208)
      ;; X
      (88 11 1 10 9 #x101 #x82 #x44 #x28 #x10 #x10 #x28 #x44 #x82 #x101)
      ;; Y
      (89 11 1 10 9 #x101 #x101 #x82 #x44 #x28 #x10 #x10 #x10 #x10 #x10)
      ;; Z
      (90 10 1 10 8 #xff #x1 #x2 #x4 #x8 #x10 #x20 #x40 #x80 #xff)
      ;; [
      (91 6 1 10 4 #xf #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #xf)
      ;; \
      (92 7 1 10 5 #x10 #x10 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ]
      (93 6 1 10 4 #xf #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #xf)
      ;; ^
      (94 8 1 10 6 #xc #x12 #x21)
      ;; _
      (95 10 0 -2 10 #x3ff)
      ;; `
      (96 3 0 10 2 #x1 #x2 #x2 #x3)
      ;; a
      (97 9 1 7 7 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; b
      (98 9 1 10 7 #x40 #x40 #x40 #x5c #x62 #x41 #x41 #x41 #x62 #x5c)
      ;; c
      (99 8 1 7 6 #xe #x11 #x20 #x20 #x20 #x11 #xe)
      ;; d
      (100 9 1 10 7 #x1 #x1 #x1 #x1d #x23 #x41 #x41 #x41 #x23 #x1d)
      ;; e
      (101 9 1 7 7 #x1c #x22 #x41 #x7f #x40 #x21 #x1e)
      ;; f
      (102 6 1 10 4 #x3 #x4 #x4 #xf #x4 #x4 #x4 #x4 #x4 #x4)
      ;; g
      (103 9 1 7 7 #x1d #x23 #x41 #x41 #x41 #x23 #x1d #x1 #x42 #x3c)
      ;; h
      (104 8 1 10 6 #x20 #x20 #x20 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; i
      (105 5 2 10 1 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; j
      (106 5 0 10 3 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x6)
      ;; k
      (107 8 1 10 7 #x40 #x40 #x40 #x42 #x44 #x48 #x78 #x44 #x42 #x41)
      ;; l
      (108 5 2 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; m
      (109 13 1 7 11 #x5ce #x631 #x421 #x421 #x421 #x421 #x421)
      ;; n
      (110 8 1 7 6 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; o
      (111 9 1 7 7 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; p
      (112 9 1 7 7 #x5c #x62 #x41 #x41 #x41 #x62 #x5c #x40 #x40 #x40)
      ;; q
      (113 9 1 7 7 #x1d #x23 #x41 #x41 #x41 #x23 #x1d #x1 #x1 #x1)
      ;; r
      (114 6 1 7 4 #xb #xc #x8 #x8 #x8 #x8 #x8)
      ;; s
      (115 8 1 7 6 #x1e #x21 #x20 #x1e #x1 #x21 #x1e)
      ;; t
      (116 6 1 9 4 #x4 #x4 #xf #x4 #x4 #x4 #x4 #x4 #x3)
      ;; u
      (117 8 1 7 6 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; v
      (118 9 1 7 7 #x41 #x41 #x22 #x22 #x14 #x14 #x8)
      ;; w
      (119 11 1 7 9 #x111 #x111 #x92 #xaa #xaa #x44 #x44)
      ;; x
      (120 9 1 7 7 #x41 #x22 #x14 #x8 #x14 #x22 #x41)
      ;; y
      (121 9 1 7 7 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x10 #x60)
      ;; z
      (122 7 1 7 5 #x1f #x1 #x2 #x4 #x8 #x10 #x1f)
      ;; {
      (123 8 1 10 6 #x7 #x8 #x8 #x8 #x8 #x8 #x30 #x8 #x8 #x8 #x8 #x8 #x7)
      ;; |
      (124 4 2 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; }
      (125 8 1 10 6 #x38 #x4 #x4 #x4 #x4 #x4 #x3 #x4 #x4 #x4 #x4 #x4 #x38)
      ;; ~
      (126 8 1 6 6 #x19 #x26)
      ;; ¬
      (172 8 1 6 6 #x3f #x1 #x1)
      ;; °
      (176 6 1 10 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 8 1 7 5 #x4 #x4 #x1f #x4 #x4 #x1f)
      ;; µ
      (181 8 1 7 6 #x21 #x21 #x21 #x21 #x21 #x23 #x1d #x20 #x20 #x20)
      ;; ·
      (183 7 2 7 3 #x7 #x7 #x7)
      ;; À
      (192 11 1 11 9 #x20 #x10 #x0 #x10 #x28 #x44 #x82 #xfe #x82 #x101 #x101)
      ;; Á
      (193 11 1 11 9 #x10 #x20 #x0 #x10 #x28 #x44 #x82 #xfe #x82 #x101 #x101)
      ;; Â
      (194 11 1 11 9 #x20 #x50 #x0 #x10 #x28 #x44 #x82 #xfe #x82 #x101 #x101)
      ;; Ã
      (195 11 1 11 9 #x28 #x50 #x0 #x10 #x28 #x44 #x82 #xfe #x82 #x101 #x101)
      ;; Ä
      (196 11 1 11 9 #x50 #x0 #x10 #x28 #x28 #x44 #x82 #xfe #x82 #x101 #x101)
      ;; Å
      (197 11 1 11 9 #x20 #x50 #x20 #x10 #x28 #x44 #x82 #xfe #x82 #x101 #x101)
      ;; Ç
      (199 10 1 10 8 #x3c #x42 #x81 #x80 #x80 #x80 #x80 #x81 #x42 #x3c #x8
        #x10)
      ;; È
      (200 9 1 11 7 #x10 #x8 #x0 #x7f #x40 #x7e #x40 #x40 #x40 #x40 #x7f)
      ;; É
      (201 9 1 11 7 #x8 #x10 #x0 #x7f #x40 #x7e #x40 #x40 #x40 #x40 #x7f)
      ;; Ê
      (202 9 1 11 7 #x10 #x28 #x0 #x7f #x40 #x7e #x40 #x40 #x40 #x40 #x7f)
      ;; Ë
      (203 9 1 11 7 #x28 #x0 #x7f #x40 #x40 #x7e #x40 #x40 #x40 #x40 #x7f)
      ;; Ì
      (204 5 1 11 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Í
      (205 5 1 11 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Î
      (206 5 0 11 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Ï
      (207 5 0 11 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Ñ
      (209 10 1 11 8 #x14 #x28 #x0 #xc1 #xa1 #x91 #x89 #x89 #x85 #x85 #x83)
      ;; Ò
      (210 10 1 11 8 #x10 #x8 #x0 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; Ó
      (211 10 1 11 8 #x8 #x10 #x0 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; Ô
      (212 10 1 11 8 #x10 #x28 #x0 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; Õ
      (213 10 1 11 8 #x14 #x28 #x0 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; Ö
      (214 10 1 11 8 #x28 #x0 #x3c #x42 #x81 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; ×
      (215 9 1 7 7 #x41 #x22 #x14 #x8 #x14 #x22 #x41)
      ;; Ù
      (217 10 1 11 8 #x10 #x8 #x0 #x81 #x81 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; Ú
      (218 10 1 11 8 #x8 #x10 #x0 #x81 #x81 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; Û
      (219 10 1 11 8 #x10 #x28 #x0 #x81 #x81 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; Ü
      (220 10 1 11 8 #x28 #x0 #x81 #x81 #x81 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; Ý
      (221 11 1 11 9 #x10 #x20 #x0 #x101 #x82 #x44 #x28 #x10 #x10 #x10 #x10)
      ;; à
      (224 9 1 10 7 #x10 #x8 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; á
      (225 9 1 10 7 #x8 #x10 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; â
      (226 9 1 10 7 #x10 #x28 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; ã
      (227 9 1 10 7 #x14 #x28 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; ä
      (228 9 1 9 7 #x28 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; å
      (229 9 1 11 7 #x10 #x28 #x10 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; ç
      (231 8 1 7 6 #xe #x11 #x20 #x20 #x20 #x11 #xe #x4 #x8)
      ;; è
      (232 9 1 10 7 #x10 #x8 #x0 #x1c #x22 #x41 #x7f #x40 #x21 #x1e)
      ;; é
      (233 9 1 10 7 #x8 #x10 #x0 #x1c #x22 #x41 #x7f #x40 #x21 #x1e)
      ;; ê
      (234 9 1 10 7 #x10 #x28 #x0 #x1c #x22 #x41 #x7f #x40 #x21 #x1e)
      ;; ë
      (235 9 1 9 7 #x28 #x0 #x1c #x22 #x41 #x7f #x40 #x21 #x1e)
      ;; ì
      (236 5 1 10 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; í
      (237 5 1 10 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; î
      (238 5 0 10 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ï
      (239 5 0 9 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ñ
      (241 8 1 10 6 #xa #x14 #x0 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; ò
      (242 9 1 10 7 #x10 #x8 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; ó
      (243 9 1 10 7 #x8 #x10 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; ô
      (244 9 1 10 7 #x10 #x28 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; õ
      (245 9 1 10 7 #x14 #x28 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; ö
      (246 9 1 9 7 #x28 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; ù
      (249 8 1 10 6 #x8 #x4 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; ú
      (250 8 1 10 6 #x4 #x8 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; û
      (251 8 1 10 6 #x8 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; ü
      (252 8 1 9 6 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; ý
      (253 9 1 10 7 #x8 #x10 #x0 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x10
        #x60)
      ;; ÿ
      (255 9 1 9 7 #x28 #x0 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x10 #x60)
      ;; α
      (945 8 1 6 6 #x1d #x22 #x22 #x22 #x22 #x1d)
      ;; β
      (946 8 1 8 6 #x1e #x21 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20)
      ;; γ
      (947 7 1 8 5 #x11 #xa #x4 #xa #x11 #x11 #x11 #xe)
      ;; δ
      (948 8 1 9 6 #xe #x10 #x10 #x8 #xc #x12 #x21 #x21 #x1e)
      ;; ε
      (949 7 1 6 5 #x7 #x8 #x1e #x10 #x8 #x7)
      ;; λ
      (955 8 1 8 6 #x20 #x20 #x10 #x8 #xc #x12 #x21 #x21)
      ;; π
      (960 8 1 6 6 #x3f #x12 #x12 #x12 #x12 #x12)
      ;; –
      (8211 8 0 5 7 #x7f)
      ;; —
      (8212 11 0 5 11 #x7ff)
      ;; ‘
      (8216 3 1 10 2 #x3 #x1 #x1 #x2)
      ;; ’
      (8217 3 1 10 2 #x3 #x1 #x1 #x2)
      ;; “
      (8220 5 1 10 3 #x5 #x5 #x5 #x5)
      ;; ”
      (8221 5 1 10 3 #x5 #x5 #x5 #x5)
      ;; …
      (8230 18 2 2 14 #x30c3 #x30c3)
      ;; ←
      (8592 10 2 7 7 #x10 #x20 #x7f #x20 #x10)
      ;; ↑
      (8593 7 1 7 5 #x4 #xe #x15 #x4 #x4 #x4 #x4)
      ;; →
      (8594 8 1 7 6 #x4 #x2 #x3f #x2 #x4)
      ;; ↓
      (8595 7 1 7 5 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 8 1 9 6 #x4 #x2 #x3f #x2 #x4 #x8 #x10 #x3f #x10 #x8)
      ;; ↳
      (8627 8 1 10 6 #x20 #x20 #x20 #x24 #x22 #x3f #x2 #x4)
      ;; ∀
      (8704 8 1 9 6 #x21 #x21 #x21 #x21 #x3f #x21 #x12 #x12 #xc)
      ;; ∂
      (8706 7 1 9 5 #xc #x2 #x1 #x1 #xf #x11 #x11 #x11 #xe)
      ;; ∃
      (8707 8 1 9 6 #x3f #x1 #x1 #x1 #x1f #x1 #x1 #x1 #x3f)
      ;; −
      (8722 9 1 5 7 #x7f)
      ;; ∞
      (8734 9 1 6 7 #x36 #x49 #x49 #x49 #x36)
      ;; ∧
      (8743 8 1 7 6 #xc #x12 #x21)
      ;; ∨
      (8744 8 1 6 6 #x21 #x12 #xc)
      ;; ∩
      (8745 7 1 7 5 #xe #x11 #x11 #x11 #x11 #x11)
      ;; ∪
      (8746 7 1 7 5 #x11 #x11 #x11 #x11 #x11 #xe)
      ;; ∫
      (8747 7 1 10 5 #x3 #x5 #x5 #x4 #x4 #x4 #x4 #x4 #x14 #x14 #x18)
      ;; ≠
      (8800 8 1 7 6 #x1 #x2 #x3f #x4 #x8 #x3f #x10 #x20)
      ;; ≡
      (8801 9 2 5 5 #x1f #x0 #x1f #x0 #x1f)
      ;; ≤
      (8804 8 2 9 4 #x1 #x2 #x4 #x8 #x4 #x2 #x1 #x0 #xf)
      ;; ≥
      (8805 8 2 9 4 #x8 #x4 #x2 #x1 #x2 #x4 #x8 #x0 #xf)
      ;; ⊂
      (8834 9 1 6 6 #x1f #x20 #x20 #x20 #x1f)
      ;; ⊃
      (8835 8 1 6 6 #x3e #x1 #x1 #x1 #x3e)
      ;; ⊕
      (8853 9 1 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 9 1 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 7 2 7 3 #x7 #x7 #x7)
      ;; ▶
      (9654 7 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 7 1 9 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ◊
      (9674 7 1 9 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 13 1 11 11 #x20 #x20 #x50 #x88 #xa8 #xa8 #x124 #x222 #x202 #x222
        #x7ff)
      ;; ✓
      (10003 9 0 8 8 #x1 #x2 #x2 #x4 #x84 #x48 #x28 #x10)
      ;; ❚
      (10074 4 1 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera HL12 Bold" 14 11 3
      ;; the slug, which a character the face lacks draws
      (#f 7 1 10 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x1f)
      ;; space
      (32 7)
      ;; !
      (33 5 1 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x0 #x3 #x3)
      ;; "
      (34 7 1 10 5 #x1b #x1b #x1b #x1b)
      ;; #
      (35 12 1 10 10 #x36 #x36 #x6c #x1ff #x6c #xd8 #x3fe #xd8 #x1b0 #x1b0)
      ;; $
      (36 10 1 11 8 #x18 #x7e #xdb #xd8 #xd8 #x7e #x1b #x1b #xdb #xdb #x7e
        #x18)
      ;; %
      (37 12 1 10 10 #x1cc #x36c #x378 #x1d8 #x30 #x30 #x6e #x7b #xdb #xce)
      ;; &
      (38 11 1 10 9 #x78 #xcc #xcc #x78 #x70 #xf6 #x19e #x18c #x18e #xfb)
      ;; '
      (39 4 1 10 3 #x7 #x3 #x3 #x6)
      ;; (
      (40 6 1 10 4 #x3 #x6 #x6 #xc #xc #xc #xc #xc #xc #xc #x6 #x6 #x3)
      ;; )
      (41 6 1 10 4 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc)
      ;; *
      (42 8 1 10 6 #xc #x3f #x1e #x3f #xc)
      ;; +
      (43 10 1 8 8 #x18 #x18 #x18 #xff #xff #x18 #x18 #x18)
      ;; ,
      (44 7 2 2 3 #x7 #x7 #x3 #x6)
      ;; -
      (45 9 1 5 7 #x7f #x7f)
      ;; .
      (46 7 2 2 3 #x7 #x7)
      ;; /
      (47 6 0 10 6 #x3 #x3 #x6 #x6 #xc #xc #x18 #x18 #x30 #x30)
      ;; 0
      (48 10 1 10 8 #x3c #x66 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; 1
      (49 9 1 10 5 #x3 #x7 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; 2
      (50 10 1 10 8 #x7e #xc3 #xc3 #x3 #x6 #x1c #x70 #xc0 #xc0 #xff)
      ;; 3
      (51 10 1 10 8 #x7e #xc3 #xc3 #x6 #x3c #x7 #x3 #xc3 #xc3 #x7e)
      ;; 4
      (52 10 1 10 8 #xe #x1e #x36 #x36 #x66 #xc6 #xff #x6 #x6 #x6)
      ;; 5
      (53 10 1 10 8 #x7f #x60 #xc0 #xfc #xc6 #x3 #x3 #x3 #xc6 #x7c)
      ;; 6
      (54 10 1 10 8 #x3e #x63 #xc0 #xfc #xe6 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; 7
      (55 10 1 10 8 #xff #x3 #x3 #x6 #xc #x18 #x18 #x30 #x30 #x30)
      ;; 8
      (56 10 1 10 8 #x3c #x66 #xc3 #x66 #x3c #x66 #xc3 #xc3 #x66 #x3c)
      ;; 9
      (57 10 1 10 8 #x3c #x66 #xc3 #xc3 #xc7 #x7f #x3 #x3 #xc6 #x7c)
      ;; :
      (58 7 2 7 3 #x7 #x7 #x0 #x0 #x0 #x7 #x7)
      ;; ;
      (59 7 2 7 3 #x7 #x7 #x0 #x0 #x0 #x7 #x7 #x3 #x6)
      ;; <
      (60 8 1 10 6 #x3 #x6 #xc #x18 #x30 #x30 #x18 #xc #x6 #x3)
      ;; =
      (61 8 1 6 6 #x3f #x3f #x0 #x3f #x3f)
      ;; >
      (62 8 1 10 6 #x30 #x18 #xc #x6 #x3 #x3 #x6 #xc #x18 #x30)
      ;; ?
      (63 9 1 10 7 #x3e #x63 #x63 #x3 #x6 #xc #xc #x0 #xc #xc)
      ;; @
      (64 13 1 10 11 #xf8 #x38e #x376 #x653 #x6db #x6db #x656 #x37c #x380 #xfe)
      ;; A
      (65 11 1 10 9 #x10 #x38 #x28 #x6c #x44 #xc6 #xfe #xc6 #x183 #x183)
      ;; B
      (66 10 1 10 8 #xfe #xc3 #xc3 #xc3 #xfe #xc3 #xc3 #xc3 #xc3 #xfe)
      ;; C
      (67 11 1 10 9 #x7c #xc6 #x183 #x180 #x180 #x180 #x180 #x183 #xc6 #x7c)
      ;; D
      (68 11 1 10 9 #x1fc #x186 #x183 #x183 #x183 #x183 #x183 #x183 #x186
        #x1fc)
      ;; E
      (69 10 1 10 8 #xff #xc0 #xc0 #xc0 #xfe #xc0 #xc0 #xc0 #xc0 #xff)
      ;; F
      (70 10 1 10 8 #xff #xc0 #xc0 #xc0 #xfe #xc0 #xc0 #xc0 #xc0 #xc0)
      ;; G
      (71 11 1 10 9 #x7e #xc3 #x183 #x180 #x180 #x18f #x183 #x183 #xc7 #x7d)
      ;; H
      (72 11 1 10 9 #x183 #x183 #x183 #x183 #x1ff #x183 #x183 #x183 #x183
        #x183)
      ;; I
      (73 6 2 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; J
      (74 9 1 10 7 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x63 #x63 #x3e)
      ;; K
      (75 10 1 10 9 #x186 #x18c #x198 #x1b0 #x1e0 #x1f0 #x198 #x18c #x186
        #x183)
      ;; L
      (76 9 1 10 7 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x7f)
      ;; M
      (77 13 1 10 11 #x603 #x603 #x707 #x78f #x68b #x6db #x653 #x673 #x623
        #x623)
      ;; N
      (78 11 1 10 9 #x183 #x1c3 #x1a3 #x1a3 #x1b3 #x19b #x18b #x18b #x187
        #x183)
      ;; O
      (79 11 1 10 9 #x7c #xc6 #x183 #x183 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; P
      (80 10 1 10 8 #xfe #xc3 #xc3 #xc3 #xfe #xc0 #xc0 #xc0 #xc0 #xc0)
      ;; Q
      (81 11 1 10 9 #x7c #xc6 #x183 #x183 #x183 #x183 #x183 #x19b #xce #x7e
        #x3)
      ;; R
      (82 10 1 10 8 #xfe #xc3 #xc3 #xc3 #xfe #xc6 #xc3 #xc3 #xc3 #xc3)
      ;; S
      (83 10 1 10 8 #x7e #xc3 #xc1 #xc0 #x78 #xe #x3 #xc3 #xc3 #x7e)
      ;; T
      (84 10 1 10 8 #xff #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18)
      ;; U
      (85 11 1 10 9 #x183 #x183 #x183 #x183 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; V
      (86 11 1 10 9 #x183 #x183 #xc6 #xc6 #xc6 #x6c #x6c #x38 #x38 #x10)
      ;; W
      (87 14 1 10 12 #xc63 #xc63 #xc63 #xc63 #x6f6 #x696 #x79e #x30c #x30c
        #x30c)
      ;; X
      (88 10 1 10 8 #xc3 #xc3 #x66 #x3c #x18 #x3c #x66 #x42 #xc3 #xc3)
      ;; Y
      (89 10 1 10 8 #xc3 #xc3 #xc3 #x66 #x3c #x18 #x18 #x18 #x18 #x18)
      ;; Z
      (90 11 1 10 8 #xff #x3 #x6 #xc #x18 #x30 #x20 #x60 #xc0 #xff)
      ;; [
      (91 7 1 10 5 #x1f #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18
        #x1f)
      ;; \
      (92 8 1 10 6 #x30 #x30 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ]
      (93 7 1 10 5 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x1f)
      ;; ^
      (94 9 1 10 7 #x1c #x36 #x63)
      ;; _
      (95 11 0 -2 11 #x7ff)
      ;; `
      (96 4 0 10 3 #x3 #x6 #x6 #x7)
      ;; a
      (97 10 1 7 8 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; b
      (98 10 1 10 8 #xc0 #xc0 #xc0 #xdc #xe6 #xc3 #xc3 #xc3 #xe6 #xdc)
      ;; c
      (99 9 1 7 7 #x1e #x33 #x60 #x60 #x60 #x33 #x1e)
      ;; d
      (100 10 1 10 8 #x3 #x3 #x3 #x3b #x67 #xc3 #xc3 #xc3 #x67 #x3b)
      ;; e
      (101 10 1 7 8 #x3c #x66 #xc3 #xff #xc0 #xc3 #x7e)
      ;; f
      (102 8 1 10 7 #x1e #x33 #x30 #x7c #x30 #x30 #x30 #x30 #x30 #x30)
      ;; g
      (103 10 1 7 8 #x3b #x67 #xc3 #xc3 #xc3 #x67 #x3b #x3 #xc3 #x7e)
      ;; h
      (104 9 1 10 7 #x60 #x60 #x60 #x6e #x73 #x63 #x63 #x63 #x63 #x63)
      ;; i
      (105 6 2 10 2 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; j
      (106 7 0 10 5 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x1b #xe)
      ;; k
      (107 9 1 10 8 #xc0 #xc0 #xc0 #xc6 #xcc #xd8 #xf8 #xcc #xc6 #xc3)
      ;; l
      (108 6 2 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; m
      (109 14 1 7 12 #xdde #xe73 #xc63 #xc63 #xc63 #xc63 #xc63)
      ;; n
      (110 9 1 7 7 #x5e #x73 #x63 #x63 #x63 #x63 #x63)
      ;; o
      (111 10 1 7 8 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; p
      (112 10 1 7 8 #xdc #xe6 #xc3 #xc3 #xc3 #xe6 #xdc #xc0 #xc0 #xc0)
      ;; q
      (113 10 1 7 8 #x3b #x67 #xc3 #xc3 #xc3 #x67 #x3b #x3 #x3 #x3)
      ;; r
      (114 8 1 7 7 #x6e #x73 #x60 #x60 #x60 #x60 #x60)
      ;; s
      (115 9 1 7 7 #x3e #x63 #x60 #x3e #x3 #x63 #x3e)
      ;; t
      (116 8 1 9 6 #x18 #x18 #x3f #x18 #x18 #x18 #x18 #x1b #xe)
      ;; u
      (117 9 1 7 7 #x63 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; v
      (118 10 1 7 8 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18)
      ;; w
      (119 13 1 7 11 #x603 #x623 #x376 #x376 #x1dc #x18c #x88)
      ;; x
      (120 10 1 7 8 #xc3 #x66 #x3c #x18 #x3c #x66 #xc3)
      ;; y
      (121 10 1 7 8 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18 #x18 #xf0 #x60)
      ;; z
      (122 8 1 7 6 #x3f #x3 #x6 #xc #x18 #x30 #x3f)
      ;; {
      (123 9 1 10 7 #xf #x18 #x18 #x18 #x18 #x18 #x70 #x18 #x18 #x18 #x18 #x18
        #xf)
      ;; |
      (124 5 2 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; }
      (125 9 1 10 7 #x78 #xc #xc #xc #xc #xc #x7 #xc #xc #xc #xc #xc #x78)
      ;; ~
      (126 9 1 6 7 #x3b #x6e)
      ;; ¬
      (172 9 1 6 7 #x7f #x3 #x3)
      ;; °
      (176 6 1 10 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 1 7 6 #xc #xc #x3f #x3f #xc #x0 #x3f #x3f)
      ;; µ
      (181 9 1 7 7 #x63 #x63 #x63 #x63 #x63 #x67 #x3b #x60 #x60 #x60)
      ;; ·
      (183 8 2 6 4 #x6 #xf #xf #x6)
      ;; À
      (192 11 1 11 9 #x60 #x30 #x0 #x10 #x6c #x44 #xc6 #xfe #xc6 #x183 #x183)
      ;; Á
      (193 11 1 11 9 #x30 #x60 #x0 #x10 #x6c #x44 #xc6 #xfe #xc6 #x183 #x183)
      ;; Â
      (194 11 1 11 9 #x30 #x78 #x0 #x10 #x6c #x44 #xc6 #xfe #xc6 #x183 #x183)
      ;; Ã
      (195 11 1 11 9 #x78 #xf0 #x0 #x10 #x6c #x44 #xc6 #xfe #xc6 #x183 #x183)
      ;; Ä
      (196 11 1 11 9 #x78 #x0 #x10 #x28 #x6c #x44 #xc6 #xfe #xc6 #x183 #x183)
      ;; Å
      (197 11 1 11 9 #x30 #x78 #x30 #x10 #x6c #x44 #xc6 #xfe #xc6 #x183 #x183)
      ;; Ç
      (199 11 1 10 9 #x7c #xc6 #x183 #x180 #x180 #x180 #x180 #x183 #xc6 #x7c
        #x30 #x60)
      ;; È
      (200 10 1 11 8 #x30 #x18 #x0 #xff #xc0 #xfe #xc0 #xc0 #xc0 #xc0 #xff)
      ;; É
      (201 10 1 11 8 #x18 #x30 #x0 #xff #xc0 #xfe #xc0 #xc0 #xc0 #xc0 #xff)
      ;; Ê
      (202 10 1 11 8 #x18 #x3c #x0 #xff #xc0 #xfe #xc0 #xc0 #xc0 #xc0 #xff)
      ;; Ë
      (203 10 1 11 8 #x3c #x0 #xff #xc0 #xc0 #xfe #xc0 #xc0 #xc0 #xc0 #xff)
      ;; Ì
      (204 6 1 11 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; Í
      (205 6 1 11 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; Î
      (206 6 1 11 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; Ï
      (207 6 1 11 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; Ñ
      (209 11 1 11 9 #x78 #xf0 #x0 #x183 #x1c3 #x1a3 #x1b3 #x19b #x18b #x187
        #x183)
      ;; Ò
      (210 11 1 11 9 #x60 #x30 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; Ó
      (211 11 1 11 9 #x30 #x60 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; Ô
      (212 11 1 11 9 #x30 #x78 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; Õ
      (213 11 1 11 9 #x78 #xf0 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; Ö
      (214 11 1 11 9 #x78 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #x183 #xc6
        #x7c)
      ;; ×
      (215 10 1 7 8 #xc3 #x66 #x3c #x18 #x3c #x66 #xc3)
      ;; Ù
      (217 11 1 11 9 #x60 #x30 #x0 #x183 #x183 #x183 #x183 #x183 #x183 #xc6
        #x7c)
      ;; Ú
      (218 11 1 11 9 #x30 #x60 #x0 #x183 #x183 #x183 #x183 #x183 #x183 #xc6
        #x7c)
      ;; Û
      (219 11 1 11 9 #x30 #x78 #x0 #x183 #x183 #x183 #x183 #x183 #x183 #xc6
        #x7c)
      ;; Ü
      (220 11 1 11 9 #x78 #x0 #x183 #x183 #x183 #x183 #x183 #x183 #x183 #xc6
        #x7c)
      ;; Ý
      (221 10 1 11 8 #x18 #x30 #x0 #xc3 #x66 #x3c #x18 #x18 #x18 #x18 #x18)
      ;; à
      (224 10 1 10 8 #x30 #x18 #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; á
      (225 10 1 10 8 #x18 #x30 #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; â
      (226 10 1 10 8 #x18 #x3c #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; ã
      (227 10 1 10 8 #x3c #x78 #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; ä
      (228 10 1 9 8 #x3c #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; å
      (229 10 1 11 8 #x18 #x3c #x18 #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; ç
      (231 9 1 7 7 #x1e #x33 #x60 #x60 #x60 #x33 #x1e #x18 #x30)
      ;; è
      (232 10 1 10 8 #x30 #x18 #x0 #x3c #x66 #xc3 #xff #xc0 #xc3 #x7e)
      ;; é
      (233 10 1 10 8 #x18 #x30 #x0 #x3c #x66 #xc3 #xff #xc0 #xc3 #x7e)
      ;; ê
      (234 10 1 10 8 #x18 #x3c #x0 #x3c #x66 #xc3 #xff #xc0 #xc3 #x7e)
      ;; ë
      (235 10 1 9 8 #x3c #x0 #x3c #x66 #xc3 #xff #xc0 #xc3 #x7e)
      ;; ì
      (236 6 1 10 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; í
      (237 6 1 10 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; î
      (238 6 1 10 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ï
      (239 6 1 9 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ñ
      (241 9 1 10 7 #x3c #x78 #x0 #x5e #x73 #x63 #x63 #x63 #x63 #x63)
      ;; ò
      (242 10 1 10 8 #x30 #x18 #x0 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; ó
      (243 10 1 10 8 #x18 #x30 #x0 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; ô
      (244 10 1 10 8 #x18 #x3c #x0 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; õ
      (245 10 1 10 8 #x3c #x78 #x0 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; ö
      (246 10 1 9 8 #x3c #x0 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; ù
      (249 9 1 10 7 #x30 #x18 #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; ú
      (250 9 1 10 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; û
      (251 9 1 10 7 #x18 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; ü
      (252 9 1 9 7 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; ý
      (253 10 1 10 8 #x18 #x30 #x0 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18 #x18
        #xf0 #x60)
      ;; ÿ
      (255 10 1 9 8 #x3c #x0 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18 #x18 #xf0 #x60)
      ;; α
      (945 9 1 6 7 #x3f #x66 #x66 #x66 #x66 #x3f)
      ;; β
      (946 9 1 8 7 #x3e #x63 #x63 #x7e #x63 #x63 #x63 #x7e #x60 #x60)
      ;; γ
      (947 8 1 8 6 #x33 #x1e #xc #x1e #x33 #x33 #x33 #x1e)
      ;; δ
      (948 9 1 9 7 #x1e #x30 #x30 #x18 #x1c #x36 #x63 #x63 #x3e)
      ;; ε
      (949 8 1 6 6 #xf #x18 #x3e #x30 #x18 #xf)
      ;; λ
      (955 9 1 8 7 #x60 #x60 #x30 #x18 #x1c #x36 #x63 #x63)
      ;; π
      (960 9 1 6 7 #x7f #x36 #x36 #x36 #x36 #x36)
      ;; –
      (8211 9 0 5 8 #xff #xff)
      ;; —
      (8212 13 0 5 13 #x1fff #x1fff)
      ;; ‘
      (8216 4 1 10 3 #x7 #x3 #x3 #x6)
      ;; ’
      (8217 4 1 10 3 #x7 #x3 #x3 #x6)
      ;; “
      (8220 7 1 10 5 #x1b #x1b #x1b #x1b)
      ;; ”
      (8221 7 1 10 5 #x1b #x1b #x1b #x1b)
      ;; …
      (8230 21 2 2 17 #x1c387 #x1c387)
      ;; ←
      (8592 11 2 7 8 #x30 #x60 #xff #x60 #x30)
      ;; ↑
      (8593 8 1 7 6 #xc #x1e #x3f #xc #xc #xc #xc)
      ;; →
      (8594 9 1 7 7 #xc #x6 #x7f #x6 #xc)
      ;; ↓
      (8595 8 1 7 6 #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↔
      (8596 9 1 9 7 #xc #x6 #x7f #x6 #xc #x18 #x30 #x7f #x30 #x18)
      ;; ↳
      (8627 9 1 10 7 #x60 #x60 #x60 #x6c #x66 #x7f #x6 #xc)
      ;; ∀
      (8704 9 1 9 7 #x63 #x63 #x63 #x63 #x7f #x63 #x36 #x36 #x1c)
      ;; ∂
      (8706 8 1 9 6 #x1c #x6 #x3 #x3 #x1f #x33 #x33 #x33 #x1e)
      ;; ∃
      (8707 9 1 9 7 #x7f #x3 #x3 #x3 #x3f #x3 #x3 #x3 #x7f)
      ;; −
      (8722 10 1 5 8 #xff #xff)
      ;; ∞
      (8734 10 1 6 8 #x7e #xdb #xdb #xdb #x7e)
      ;; ∧
      (8743 9 1 7 7 #x1c #x36 #x63)
      ;; ∨
      (8744 9 1 6 7 #x63 #x36 #x1c)
      ;; ∩
      (8745 8 1 7 6 #x1e #x33 #x33 #x33 #x33 #x33)
      ;; ∪
      (8746 8 1 7 6 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; ∫
      (8747 8 1 10 6 #x7 #xf #xf #xc #xc #xc #xc #xc #x3c #x3c #x38)
      ;; ≠
      (8800 9 1 7 7 #x3 #x6 #x7f #xc #x18 #x7f #x30 #x60)
      ;; ≡
      (8801 10 2 5 6 #x3f #x0 #x3f #x0 #x3f)
      ;; ≤
      (8804 9 2 9 5 #x3 #x6 #xc #x18 #xc #x6 #x3 #x0 #x1f)
      ;; ≥
      (8805 9 2 9 5 #x18 #xc #x6 #x3 #x6 #xc #x18 #x0 #x1f)
      ;; ⊂
      (8834 10 1 6 7 #x3f #x60 #x60 #x60 #x3f)
      ;; ⊃
      (8835 9 1 6 7 #x7e #x3 #x3 #x3 #x7e)
      ;; ⊕
      (8853 10 1 8 8 #x3c #x7e #xdb #xff #xdb #x7e #x3c)
      ;; ⊗
      (8855 10 1 8 8 #x3c #x66 #xff #xdb #xff #x66 #x3c)
      ;; ⋅
      (8901 8 2 6 4 #x6 #xf #xf #x6)
      ;; ▶
      (9654 7 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 8 1 9 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ◊
      (9674 8 1 9 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 13 1 11 11 #x20 #x20 #x50 #x88 #xa8 #xa8 #x124 #x222 #x202 #x222
        #x7ff)
      ;; ✓
      (10003 10 0 8 9 #x3 #x6 #x6 #xc #x18c #xd8 #x78 #x30)
      ;; ❚
      (10074 6 1 10 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("Genera HL12 Italic" 14 11 3
      ;; the slug, which a character the face lacks draws
      (#f 6 1 10 4 #xf #x9 #x9 #x9 #x9 #x9 #x9 #x9 #x9 #xf)
      ;; space
      (32 6)
      ;; !
      (33 5 2 10 3 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x0 #x4 #x4)
      ;; "
      (34 7 2 10 5 #x9 #x9 #x12 #x12)
      ;; #
      (35 10 2 10 8 #x9 #x9 #x12 #x7f #x24 #x24 #xfe #x48 #x90 #x90)
      ;; $
      (36 11 2 11 9 #x8 #x3e #x49 #x89 #x90 #x78 #x14 #x12 #x122 #x124 #xf8
        #x20)
      ;; %
      (37 14 2 10 12 #x384 #x448 #x850 #x890 #x720 #x4e #x91 #xa1 #x122 #x21c)
      ;; &
      (38 11 2 10 9 #x38 #x44 #x44 #x28 #x70 #x92 #x10c #x104 #x10a #xf1)
      ;; '
      (39 5 2 10 2 #x3 #x1 #x1 #x2)
      ;; (
      (40 7 3 10 5 #x1 #x2 #x4 #x8 #x8 #x10 #x10 #x10 #x10 #x10 #x10 #x8 #x8)
      ;; )
      (41 7 0 10 5 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4 #x8 #x10)
      ;; *
      (42 7 2 10 5 #x4 #x15 #xe #x15 #x4)
      ;; +
      (43 8 2 7 6 #x4 #x4 #x4 #x3f #x8 #x8 #x8)
      ;; ,
      (44 4 0 2 3 #x3 #x1 #x1 #x6)
      ;; -
      (45 7 2 5 5 #x1f)
      ;; .
      (46 6 2 2 2 #x3 #x3)
      ;; /
      (47 5 0 10 7 #x1 #x2 #x2 #x4 #x8 #x8 #x10 #x20 #x20 #x40)
      ;; 0
      (48 8 1 10 7 #xc #x32 #x21 #x41 #x41 #x41 #x41 #x42 #x26 #x18)
      ;; 1
      (49 7 2 10 5 #x3 #x5 #x9 #x12 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; 2
      (50 8 1 10 7 #xe #x11 #x21 #x21 #x2 #xc #x10 #x20 #x40 #x7f)
      ;; 3
      (51 8 1 10 7 #xe #x11 #x21 #x2 #x1c #x2 #x2 #x42 #x44 #x38)
      ;; 4
      (52 8 1 10 7 #x1 #x3 #x5 #x9 #x12 #x22 #x42 #x7f #x4 #x4)
      ;; 5
      (53 8 1 10 7 #x1f #x10 #x20 #x3c #x42 #x2 #x2 #x42 #x44 #x38)
      ;; 6
      (54 8 1 10 7 #xe #x11 #x20 #x2e #x71 #x41 #x41 #x41 #x22 #x1c)
      ;; 7
      (55 8 2 10 6 #x3f #x1 #x2 #x4 #x8 #x8 #x10 #x10 #x20 #x20)
      ;; 8
      (56 8 1 10 7 #xe #x11 #x11 #x11 #x1e #x21 #x41 #x41 #x42 #x3c)
      ;; 9
      (57 8 1 10 7 #x1c #x22 #x41 #x41 #x41 #x21 #x1f #x2 #x42 #x3c)
      ;; :
      (58 5 1 7 3 #x3 #x3 #x0 #x0 #x0 #x6 #x6)
      ;; ;
      (59 6 1 7 4 #x3 #x3 #x0 #x0 #x0 #x6 #x6 #x2 #xc)
      ;; <
      (60 8 2 10 6 #x1 #x2 #x4 #x8 #x10 #x20 #x20 #x10 #x8 #x4)
      ;; =
      (61 8 2 5 6 #x1f #x0 #x3e)
      ;; >
      (62 8 2 10 6 #x8 #x4 #x2 #x1 #x1 #x2 #x4 #x8 #x10 #x20)
      ;; ?
      (63 8 2 10 6 #xe #x11 #x21 #x1 #x6 #x8 #x8 #x0 #x10 #x10)
      ;; @
      (64 14 2 10 12 #xfc #x302 #x469 #x499 #x911 #x911 #x932 #x8dc #x400
        #x3fc)
      ;; A
      (65 8 0 10 7 #x3 #x5 #x5 #x9 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; B
      (66 9 1 10 8 #x3e #x21 #x21 #x41 #x7e #x41 #x41 #x81 #x82 #xfc)
      ;; C
      (67 9 1 10 8 #xe #x31 #x41 #x40 #x80 #x80 #x80 #x81 #x42 #x3c)
      ;; D
      (68 10 1 10 9 #x7c #x42 #x41 #x81 #x81 #x81 #x82 #x102 #x10c #x1f0)
      ;; E
      (69 9 1 10 9 #x7f #x40 #x40 #x80 #xfc #x80 #x80 #x100 #x100 #x1fc)
      ;; F
      (70 8 1 10 8 #x3f #x20 #x20 #x40 #x7c #x40 #x40 #x80 #x80 #x80)
      ;; G
      (71 11 1 10 9 #x1e #x61 #x81 #x80 #x100 #x10f #x101 #x101 #x86 #x7a)
      ;; H
      (72 10 1 10 9 #x41 #x41 #x41 #x82 #xfe #x82 #x82 #x104 #x104 #x104)
      ;; I
      (73 4 1 10 3 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; J
      (74 8 1 10 7 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x44 #x44 #x38)
      ;; K
      (75 8 1 10 8 #x21 #x22 #x24 #x48 #x70 #x50 #x48 #x88 #x84 #x84)
      ;; L
      (76 8 1 10 7 #x10 #x10 #x10 #x20 #x20 #x20 #x20 #x40 #x40 #x7f)
      ;; M
      (77 13 1 10 12 #x201 #x203 #x305 #x50a #x50a #x512 #x4a2 #x8a4 #x8c4
        #x884)
      ;; N
      (78 11 1 10 10 #xc1 #xc1 #xa1 #x122 #x122 #x112 #x112 #x214 #x20c #x20c)
      ;; O
      (79 10 1 10 9 #x3c #xc2 #x81 #x101 #x101 #x101 #x101 #x102 #x86 #x78)
      ;; P
      (80 9 1 10 8 #x3e #x21 #x21 #x41 #x42 #x7c #x40 #x80 #x80 #x80)
      ;; Q
      (81 10 1 10 9 #x3c #xc2 #x81 #x101 #x101 #x101 #x101 #x112 #x8e #x7c #x2)
      ;; R
      (82 10 1 10 9 #x7e #x41 #x41 #x82 #xfc #x82 #x82 #x104 #x104 #x104)
      ;; S
      (83 10 1 10 8 #x1e #x21 #x41 #x40 #x3c #x2 #x1 #x81 #x82 #x7c)
      ;; T
      (84 10 2 10 9 #x1ff #x10 #x10 #x20 #x20 #x20 #x20 #x40 #x40 #x40)
      ;; U
      (85 10 1 10 9 #x41 #x41 #x41 #x82 #x82 #x82 #x102 #x104 #x104 #xf8)
      ;; V
      (86 9 2 10 8 #x81 #x81 #x82 #x84 #x84 #x88 #x90 #x90 #xa0 #xc0)
      ;; W
      (87 13 2 10 12 #x821 #x861 #x8a2 #x8a2 #x924 #x924 #xa28 #xa28 #xc30
        #xc30)
      ;; X
      (88 8 0 10 9 #x41 #x42 #x24 #x28 #x10 #x10 #x28 #x48 #x84 #x104)
      ;; Y
      (89 9 2 10 9 #x101 #x102 #x84 #x88 #x50 #x60 #x40 #x40 #x80 #x80)
      ;; Z
      (90 9 1 10 8 #x7f #x1 #x2 #x4 #x8 #x10 #x20 #x40 #x80 #xfe)
      ;; [
      (91 9 2 10 7 #xf #x8 #x8 #x10 #x10 #x10 #x20 #x20 #x20 #x20 #x40 #x40
        #x78)
      ;; \
      (92 7 2 10 5 #x10 #x10 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ]
      (93 9 2 10 7 #xf #x1 #x1 #x2 #x2 #x2 #x4 #x4 #x4 #x4 #x8 #x8 #x78)
      ;; ^
      (94 7 2 11 6 #xc #x12 #x21)
      ;; _
      (95 12 1 -1 11 #x7ff)
      ;; `
      (96 4 2 10 2 #x1 #x2 #x2 #x3)
      ;; a
      (97 9 1 7 7 #x1e #x21 #x1 #x3e #x42 #x42 #x3d)
      ;; b
      (98 8 1 10 7 #x10 #x10 #x10 #x3e #x21 #x21 #x41 #x41 #x42 #x7c)
      ;; c
      (99 8 1 7 7 #x1e #x21 #x40 #x40 #x40 #x42 #x3c)
      ;; d
      (100 8 1 10 8 #x1 #x1 #x1 #x3e #x42 #x82 #x82 #x84 #x84 #x7c)
      ;; e
      (101 8 1 7 7 #x1e #x21 #x41 #x7e #x40 #x40 #x3e)
      ;; f
      (102 7 2 10 6 #x7 #x8 #x8 #x3e #x10 #x10 #x10 #x20 #x20 #x20)
      ;; g
      (103 8 0 7 8 #x1d #x23 #x41 #x42 #x42 #x42 #x3e #x4 #xc4 #x78)
      ;; h
      (104 8 1 10 7 #x10 #x10 #x10 #x3e #x21 #x21 #x21 #x42 #x42 #x42)
      ;; i
      (105 5 2 10 3 #x1 #x1 #x0 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; j
      (106 5 0 10 5 #x1 #x1 #x0 #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x4 #x18)
      ;; k
      (107 7 1 10 6 #x8 #x8 #x8 #x11 #x12 #x14 #x1a #x22 #x21 #x21)
      ;; l
      (108 5 2 10 3 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; m
      (109 11 1 7 10 #x176 #x199 #x111 #x111 #x222 #x222 #x222)
      ;; n
      (110 8 1 7 7 #x2e #x31 #x21 #x21 #x42 #x42 #x42)
      ;; o
      (111 8 1 7 7 #x1e #x21 #x41 #x41 #x41 #x42 #x3c)
      ;; p
      (112 8 0 7 8 #x2e #x31 #x21 #x41 #x41 #x42 #x7c #x80 #x80 #x80)
      ;; q
      (113 8 1 7 7 #x1f #x21 #x41 #x41 #x42 #x42 #x3e #x2 #x4 #x4)
      ;; r
      (114 6 1 7 6 #x17 #x18 #x10 #x10 #x20 #x20 #x20)
      ;; s
      (115 8 1 7 6 #xe #x11 #x10 #xe #x21 #x21 #x1e)
      ;; t
      (116 7 2 9 5 #x4 #x4 #x1f #x8 #x8 #x8 #x10 #x10 #xe)
      ;; u
      (117 8 1 7 7 #x21 #x21 #x21 #x42 #x42 #x46 #x3a)
      ;; v
      (118 7 2 7 5 #x11 #x11 #x12 #x12 #x14 #x14 #x18)
      ;; w
      (119 12 2 7 10 #x211 #x231 #x252 #x252 #x294 #x294 #x318)
      ;; x
      (120 8 1 7 7 #x21 #x22 #x14 #x8 #x14 #x22 #x42)
      ;; y
      (121 9 0 7 9 #x41 #x41 #x42 #x22 #x24 #x28 #x10 #x10 #x120 #xc0)
      ;; z
      (122 8 1 7 7 #x3f #x2 #x4 #x8 #x10 #x20 #x7e)
      ;; {
      (123 9 2 10 7 #x3 #x4 #x8 #x8 #x8 #x10 #x60 #x10 #x10 #x20 #x20 #x20
        #x18)
      ;; |
      (124 5 2 10 3 #x1 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x4)
      ;; }
      (125 9 2 10 7 #xc #x2 #x2 #x2 #x4 #x4 #x3 #x4 #x8 #x8 #x8 #x10 #x60)
      ;; ~
      (126 9 2 7 7 #x31 #x49 #x46)
      ;; ¬
      (172 9 1 6 6 #x3f #x1 #x1)
      ;; °
      (176 6 1 10 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 7 1 7 5 #x4 #x4 #x1f #x4 #x4 #x1f)
      ;; µ
      (181 8 1 7 7 #x21 #x21 #x21 #x42 #x42 #x46 #x3a #x40 #x40 #x40)
      ;; ·
      (183 7 2 7 3 #x7 #x7 #x7)
      ;; À
      (192 8 0 11 7 #x10 #x8 #x0 #x3 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Á
      (193 8 0 11 7 #x8 #x10 #x0 #x3 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Â
      (194 8 0 11 7 #x10 #x28 #x0 #x3 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Ã
      (195 8 0 11 7 #x14 #x28 #x0 #x3 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Ä
      (196 8 0 11 7 #x28 #x0 #x3 #x5 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Å
      (197 8 0 11 7 #x10 #x28 #x10 #x3 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Ç
      (199 9 1 10 8 #xe #x31 #x41 #x40 #x80 #x80 #x80 #x81 #x42 #x3c #x8 #x10)
      ;; È
      (200 9 1 11 9 #x20 #x10 #x0 #x7f #x40 #x80 #xfc #x80 #x100 #x100 #x1fc)
      ;; É
      (201 9 1 11 9 #x10 #x20 #x0 #x7f #x40 #x80 #xfc #x80 #x100 #x100 #x1fc)
      ;; Ê
      (202 9 1 11 9 #x20 #x50 #x0 #x7f #x40 #x80 #xfc #x80 #x100 #x100 #x1fc)
      ;; Ë
      (203 9 1 11 9 #x50 #x0 #x7f #x40 #x80 #xfc #x80 #x80 #x100 #x100 #x1fc)
      ;; Ì
      (204 4 1 11 3 #x4 #x2 #x0 #x1 #x1 #x1 #x2 #x2 #x4 #x4 #x4)
      ;; Í
      (205 4 1 11 3 #x2 #x4 #x0 #x1 #x1 #x1 #x2 #x2 #x4 #x4 #x4)
      ;; Î
      (206 4 0 11 4 #x4 #xa #x0 #x1 #x1 #x1 #x2 #x2 #x4 #x4 #x4)
      ;; Ï
      (207 4 0 11 4 #xa #x0 #x1 #x1 #x1 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; Ñ
      (209 11 1 11 10 #x28 #x50 #x0 #xc1 #xa1 #x122 #x112 #x112 #x214 #x20c
        #x20c)
      ;; Ò
      (210 10 1 11 9 #x20 #x10 #x0 #x3c #xc2 #x81 #x101 #x101 #x102 #x86 #x78)
      ;; Ó
      (211 10 1 11 9 #x10 #x20 #x0 #x3c #xc2 #x81 #x101 #x101 #x102 #x86 #x78)
      ;; Ô
      (212 10 1 11 9 #x20 #x50 #x0 #x3c #xc2 #x81 #x101 #x101 #x102 #x86 #x78)
      ;; Õ
      (213 10 1 11 9 #x28 #x50 #x0 #x3c #xc2 #x81 #x101 #x101 #x102 #x86 #x78)
      ;; Ö
      (214 10 1 11 9 #x50 #x0 #x3c #xc2 #x81 #x101 #x101 #x101 #x102 #x86 #x78)
      ;; ×
      (215 8 1 7 7 #x21 #x22 #x14 #x8 #x14 #x22 #x42)
      ;; Ù
      (217 10 1 11 9 #x20 #x10 #x0 #x41 #x41 #x41 #x82 #x102 #x104 #x104 #xf8)
      ;; Ú
      (218 10 1 11 9 #x10 #x20 #x0 #x41 #x41 #x41 #x82 #x102 #x104 #x104 #xf8)
      ;; Û
      (219 10 1 11 9 #x20 #x50 #x0 #x41 #x41 #x41 #x82 #x102 #x104 #x104 #xf8)
      ;; Ü
      (220 10 1 11 9 #x50 #x0 #x41 #x41 #x41 #x82 #x82 #x102 #x104 #x104 #xf8)
      ;; Ý
      (221 9 2 11 9 #x10 #x20 #x0 #x101 #x84 #x88 #x50 #x60 #x40 #x80 #x80)
      ;; à
      (224 9 1 10 7 #x10 #x8 #x0 #x1e #x21 #x1 #x3e #x42 #x42 #x3d)
      ;; á
      (225 9 1 10 7 #x8 #x10 #x0 #x1e #x21 #x1 #x3e #x42 #x42 #x3d)
      ;; â
      (226 9 1 10 7 #x10 #x28 #x0 #x1e #x21 #x1 #x3e #x42 #x42 #x3d)
      ;; ã
      (227 9 1 10 7 #x14 #x28 #x0 #x1e #x21 #x1 #x3e #x42 #x42 #x3d)
      ;; ä
      (228 9 1 9 7 #x28 #x0 #x1e #x21 #x1 #x3e #x42 #x42 #x3d)
      ;; å
      (229 9 1 11 7 #x10 #x28 #x10 #x0 #x1e #x21 #x1 #x3e #x42 #x42 #x3d)
      ;; ç
      (231 8 1 7 7 #x1e #x21 #x40 #x40 #x40 #x42 #x3c #x8 #x10)
      ;; è
      (232 8 1 10 7 #x10 #x8 #x0 #x1e #x21 #x41 #x7e #x40 #x40 #x3e)
      ;; é
      (233 8 1 10 7 #x8 #x10 #x0 #x1e #x21 #x41 #x7e #x40 #x40 #x3e)
      ;; ê
      (234 8 1 10 7 #x10 #x28 #x0 #x1e #x21 #x41 #x7e #x40 #x40 #x3e)
      ;; ë
      (235 8 1 9 7 #x28 #x0 #x1e #x21 #x41 #x7e #x40 #x40 #x3e)
      ;; ì
      (236 5 2 10 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; í
      (237 5 2 10 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; î
      (238 5 1 10 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; ï
      (239 5 1 9 3 #x5 #x0 #x1 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; ñ
      (241 8 1 10 7 #x14 #x28 #x0 #x2e #x31 #x21 #x21 #x42 #x42 #x42)
      ;; ò
      (242 8 1 10 7 #x10 #x8 #x0 #x1e #x21 #x41 #x41 #x41 #x42 #x3c)
      ;; ó
      (243 8 1 10 7 #x8 #x10 #x0 #x1e #x21 #x41 #x41 #x41 #x42 #x3c)
      ;; ô
      (244 8 1 10 7 #x10 #x28 #x0 #x1e #x21 #x41 #x41 #x41 #x42 #x3c)
      ;; õ
      (245 8 1 10 7 #x14 #x28 #x0 #x1e #x21 #x41 #x41 #x41 #x42 #x3c)
      ;; ö
      (246 8 1 9 7 #x28 #x0 #x1e #x21 #x41 #x41 #x41 #x42 #x3c)
      ;; ù
      (249 8 1 10 7 #x10 #x8 #x0 #x21 #x21 #x21 #x42 #x42 #x46 #x3a)
      ;; ú
      (250 8 1 10 7 #x8 #x10 #x0 #x21 #x21 #x21 #x42 #x42 #x46 #x3a)
      ;; û
      (251 8 1 10 7 #x10 #x28 #x0 #x21 #x21 #x21 #x42 #x42 #x46 #x3a)
      ;; ü
      (252 8 1 9 7 #x28 #x0 #x21 #x21 #x21 #x42 #x42 #x46 #x3a)
      ;; ý
      (253 9 0 10 9 #x10 #x20 #x0 #x41 #x41 #x42 #x22 #x24 #x28 #x10 #x10
        #x120 #xc0)
      ;; ÿ
      (255 9 0 9 9 #x50 #x0 #x41 #x41 #x42 #x22 #x24 #x28 #x10 #x10 #x120 #xc0)
      ;; α
      (945 8 2 6 6 #x1d #x22 #x22 #x22 #x22 #x1d)
      ;; β
      (946 9 2 8 6 #x1e #x21 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20)
      ;; γ
      (947 7 1 8 5 #x11 #xa #x4 #xa #x11 #x11 #x11 #xe)
      ;; δ
      (948 8 1 9 6 #xe #x10 #x10 #x8 #xc #x12 #x21 #x21 #x1e)
      ;; ε
      (949 8 2 6 5 #x7 #x8 #x1e #x10 #x8 #x7)
      ;; λ
      (955 8 1 8 6 #x20 #x20 #x10 #x8 #xc #x12 #x21 #x21)
      ;; π
      (960 8 1 6 6 #x3f #x12 #x12 #x12 #x12 #x12)
      ;; –
      (8211 8 0 5 7 #x7f)
      ;; —
      (8212 13 0 5 13 #x1fff)
      ;; ‘
      (8216 5 2 10 2 #x3 #x1 #x1 #x2)
      ;; ’
      (8217 5 2 10 2 #x3 #x1 #x1 #x2)
      ;; “
      (8220 7 2 10 5 #x9 #x9 #x12 #x12)
      ;; ”
      (8221 7 2 10 5 #x9 #x9 #x12 #x12)
      ;; …
      (8230 18 2 2 14 #x30c3 #x30c3)
      ;; ←
      (8592 10 2 7 7 #x8 #x10 #x7f #x20 #x10)
      ;; ↑
      (8593 8 2 8 5 #x4 #xe #x15 #x4 #x8 #x8 #x8)
      ;; →
      (8594 10 2 7 7 #x4 #x2 #x7f #x4 #x8)
      ;; ↓
      (8595 8 2 7 5 #x2 #x2 #x2 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 8 1 9 6 #x4 #x2 #x3f #x2 #x4 #x8 #x10 #x3f #x10 #x8)
      ;; ↳
      (8627 10 2 10 7 #x40 #x40 #x40 #x44 #x42 #x7f #x4 #x8)
      ;; ∀
      (8704 10 2 10 7 #x41 #x41 #x7e #x42 #x44 #x48 #x48 #x50 #x50 #x60)
      ;; ∂
      (8706 7 1 9 5 #xc #x2 #x1 #x1 #xf #x11 #x11 #x11 #xe)
      ;; ∃
      (8707 9 0 10 9 #x7f #x1 #x1 #x2 #x2 #x7e #x2 #x4 #x4 #x1fc)
      ;; −
      (8722 8 2 4 6 #x3f)
      ;; ∞
      (8734 9 1 6 7 #x36 #x49 #x49 #x49 #x36)
      ;; ∧
      (8743 8 1 7 6 #xc #x12 #x21)
      ;; ∨
      (8744 8 1 7 6 #xc #x12 #x21)
      ;; ∩
      (8745 8 2 7 5 #xe #x11 #x11 #x11 #x11 #x11)
      ;; ∪
      (8746 8 2 7 5 #x11 #x11 #x11 #x11 #x11 #xe)
      ;; ∫
      (8747 9 1 10 7 #x6 #x9 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x48 #x30)
      ;; ≠
      (8800 8 1 7 6 #x1 #x2 #x3f #x4 #x8 #x3f #x10 #x20)
      ;; ≡
      (8801 8 2 5 5 #x1f #x0 #x1f #x0 #x1f)
      ;; ≤
      (8804 8 2 9 4 #x1 #x2 #x4 #x8 #x4 #x2 #x1 #x0 #xf)
      ;; ≥
      (8805 8 2 9 4 #x8 #x4 #x2 #x1 #x2 #x4 #x8 #x0 #xf)
      ;; ⊂
      (8834 8 1 6 6 #x1f #x20 #x20 #x20 #x1f)
      ;; ⊃
      (8835 8 1 6 6 #x3e #x1 #x1 #x1 #x3e)
      ;; ⊕
      (8853 9 1 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 9 1 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 7 2 7 3 #x7 #x7 #x7)
      ;; ▶
      (9654 7 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 7 1 9 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ◊
      (9674 7 1 9 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 13 1 11 11 #x20 #x20 #x50 #x88 #xa8 #xa8 #x124 #x222 #x202 #x222
        #x7ff)
      ;; ✓
      (10003 7 0 8 6 #x1 #x1 #x2 #x2 #x24 #x14 #x18 #x8)
      ;; ❚
      (10074 4 1 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera HL12 Bold Italic" 14 11 3
      ;; the slug, which a character the face lacks draws
      (#f 7 1 10 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x1f)
      ;; space
      (32 7)
      ;; !
      (33 6 2 10 4 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #x0 #xc #xc)
      ;; "
      (34 8 2 10 6 #x1b #x1b #x36 #x36)
      ;; #
      (35 11 2 10 9 #x1b #x1b #x36 #xff #x6c #x6c #x1fe #xd8 #x1b0 #x1b0)
      ;; $
      (36 12 2 11 10 #x18 #x7e #xdb #x19b #x1b0 #xf8 #x3c #x36 #x366 #x36c
        #x1f8 #x60)
      ;; %
      (37 15 2 10 13 #x78c #xcd8 #x18f0 #x19b0 #xf60 #xde #x1b3 #x1e3 #x366
        #x63c)
      ;; &
      (38 12 2 10 10 #x78 #xcc #xcc #x78 #xf0 #x1b6 #x31c #x30c #x31e #x1f3)
      ;; '
      (39 5 2 10 3 #x3 #x3 #x6 #x6)
      ;; (
      (40 8 2 10 6 #x3 #x6 #xc #x18 #x18 #x30 #x30 #x30 #x30 #x30 #x30 #x18
        #x18)
      ;; )
      (41 8 2 10 6 #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc #x18 #x30)
      ;; *
      (42 8 2 10 6 #xc #x3f #x1e #x3f #xc)
      ;; +
      (43 9 2 7 7 #xc #xc #xc #x7f #x18 #x18 #x18)
      ;; ,
      (44 5 1 2 4 #x7 #x3 #x3 #xe)
      ;; -
      (45 8 2 5 6 #x3f)
      ;; .
      (46 6 2 2 2 #x3 #x3)
      ;; /
      (47 10 2 10 8 #x3 #x6 #x6 #xc #x18 #x18 #x30 #x60 #x60 #xc0)
      ;; 0
      (48 10 2 10 8 #x1c #x76 #x63 #xc3 #xc3 #xc3 #xc3 #xc6 #x6e #x38)
      ;; 1
      (49 10 3 10 6 #x7 #xf #x1b #x36 #x6 #x6 #x6 #xc #xc #xc)
      ;; 2
      (50 10 2 10 8 #x1e #x33 #x63 #x63 #x6 #x1c #x30 #x60 #xc0 #xff)
      ;; 3
      (51 10 2 10 8 #x1e #x33 #x63 #x6 #x3c #x6 #x6 #xc6 #xcc #x78)
      ;; 4
      (52 10 2 10 8 #x7 #x7 #xf #x1b #x36 #x66 #xc6 #xff #xc #xc)
      ;; 5
      (53 10 2 10 8 #x3f #x30 #x60 #x7c #xc6 #xc6 #x6 #xc6 #xcc #x78)
      ;; 6
      (54 10 2 10 8 #x1e #x33 #x60 #x7e #xf3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; 7
      (55 10 3 10 7 #x7f #x3 #x6 #xc #x18 #x18 #x30 #x30 #x60 #x60)
      ;; 8
      (56 10 2 10 8 #x1e #x33 #x33 #x32 #x3e #x63 #xc3 #xc3 #xc6 #x7c)
      ;; 9
      (57 10 2 10 8 #x3c #x66 #xc3 #xc3 #xc3 #x63 #x3f #x6 #xc6 #x7c)
      ;; :
      (58 6 2 7 3 #x3 #x3 #x0 #x0 #x0 #x6 #x6)
      ;; ;
      (59 6 1 7 5 #x3 #x3 #x0 #x0 #x0 #xe #x6 #x6 #x1c)
      ;; <
      (60 9 2 10 7 #x3 #x6 #xc #x18 #x30 #x60 #x60 #x30 #x18 #xc)
      ;; =
      (61 9 2 5 7 #x3f #x0 #x7e)
      ;; >
      (62 9 2 10 7 #x18 #xc #x6 #x3 #x3 #x6 #xc #x18 #x30 #x60)
      ;; ?
      (63 9 2 10 7 #x1e #x33 #x63 #x3 #xe #x18 #x18 #x0 #x30 #x30)
      ;; @
      (64 15 2 10 13 #x1fc #x706 #xcfb #xdbb #x1b33 #x1b33 #x1b76 #x19fc #xc00
        #x7fc)
      ;; A
      (65 9 0 10 8 #x7 #xf #xb #x1b #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; B
      (66 10 1 10 9 #x7e #x63 #x63 #xc3 #xfe #xc3 #xc3 #x183 #x186 #x1fc)
      ;; C
      (67 10 1 10 9 #x1e #x73 #xc3 #xc0 #x180 #x180 #x183 #x183 #xc6 #x7c)
      ;; D
      (68 11 1 10 10 #xfc #xc6 #xc3 #x183 #x183 #x183 #x186 #x306 #x31c #x3f0)
      ;; E
      (69 10 1 10 10 #xff #xc0 #xc0 #x180 #x1fc #x180 #x180 #x300 #x300 #x3fc)
      ;; F
      (70 9 1 10 9 #x7f #x60 #x60 #xc0 #xfc #xc0 #xc0 #x180 #x180 #x180)
      ;; G
      (71 11 1 10 10 #x3e #xe3 #x183 #x180 #x300 #x31f #x303 #x303 #x18e #xfa)
      ;; H
      (72 11 1 10 10 #xc3 #xc3 #xc3 #x186 #x1fe #x186 #x186 #x30c #x30c #x30c)
      ;; I
      (73 5 1 10 4 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xc #xc #xc)
      ;; J
      (74 8 0 10 8 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xcc #xcc #x78)
      ;; K
      (75 9 1 10 9 #x63 #x66 #x6c #xd8 #xf0 #xf0 #xd8 #x198 #x18c #x18c)
      ;; L
      (76 9 1 10 8 #x30 #x30 #x30 #x60 #x60 #x60 #x60 #xc0 #xc0 #xff)
      ;; M
      (77 14 1 10 13 #x603 #x707 #x70f #xf1e #xd16 #xdb6 #xde6 #x18cc #x18cc
        #x18cc)
      ;; N
      (78 12 1 10 11 #x1c3 #x1c3 #x1e3 #x366 #x366 #x336 #x336 #x63c #x61c
        #x61c)
      ;; O
      (79 11 1 10 10 #x7c #xc6 #x183 #x183 #x303 #x303 #x306 #x306 #x18c #xf8)
      ;; P
      (80 10 1 10 9 #x7e #x63 #x63 #xc3 #xc6 #xfc #xc0 #x180 #x180 #x180)
      ;; Q
      (81 11 1 10 10 #x7c #x1c6 #x183 #x303 #x303 #x303 #x303 #x336 #x19e #xfc
        #x6)
      ;; R
      (82 11 1 10 10 #xfe #xc3 #xc3 #x186 #x1fc #x186 #x186 #x30c #x30c #x30c)
      ;; S
      (83 10 1 10 9 #x3e #x63 #xc3 #xc0 #x7c #x6 #x3 #x183 #x186 #xfc)
      ;; T
      (84 11 2 10 10 #x3ff #x30 #x30 #x60 #x60 #x60 #x60 #xc0 #xc0 #xc0)
      ;; U
      (85 11 1 10 10 #xc3 #xc3 #xc3 #x186 #x186 #x186 #x306 #x30c #x30c #x1f8)
      ;; V
      (86 10 2 10 9 #x183 #x183 #x186 #x18c #x18c #x198 #x1b0 #x1b0 #x1e0
        #x1c0)
      ;; W
      (87 14 2 10 13 #x1863 #x18e3 #x18e6 #x19a6 #x1b6c #x1b6c #x1e58 #x1c70
        #x1c70 #x1860)
      ;; X
      (88 9 0 10 10 #xc3 #xc6 #x6c #x78 #x30 #x30 #x78 #xd8 #x18c #x30c)
      ;; Y
      (89 9 1 10 10 #x303 #x306 #x18c #x198 #xf0 #xe0 #xc0 #xc0 #x180 #x180)
      ;; Z
      (90 10 1 10 9 #xff #x3 #x6 #xc #x18 #x30 #x60 #xc0 #x180 #x1fe)
      ;; [
      (91 10 2 10 8 #x1f #x18 #x18 #x30 #x30 #x30 #x60 #x60 #x60 #x60 #xc0
        #xc0 #xf8)
      ;; \
      (92 8 2 10 6 #x30 #x30 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ]
      (93 10 2 10 8 #x1f #x3 #x3 #x6 #x6 #x6 #xc #xc #xc #xc #x18 #x18 #xf8)
      ;; ^
      (94 8 2 8 6 #xc #x1e #x33)
      ;; _
      (95 10 0 -1 10 #x3ff)
      ;; `
      (96 4 0 10 3 #x3 #x6 #x6 #x7)
      ;; a
      (97 9 1 7 8 #x3e #x63 #x3 #x7f #xc6 #xc6 #x7f)
      ;; b
      (98 9 1 10 8 #x30 #x30 #x30 #x7e #x63 #x63 #x63 #xc3 #xe6 #xfc)
      ;; c
      (99 9 1 7 8 #x3e #x63 #xc0 #xc0 #xc3 #xc6 #x7c)
      ;; d
      (100 9 1 10 9 #x3 #x3 #x3 #x3e #xe6 #xc6 #x186 #x18c #x19c #xfc)
      ;; e
      (101 9 1 7 8 #x1e #x73 #x63 #xff #xc0 #xc6 #x7c)
      ;; f
      (102 6 1 10 7 #xf #x18 #x18 #x7e #x30 #x30 #x30 #x60 #x60 #x60)
      ;; g
      (103 9 0 7 9 #x3f #x67 #xc3 #xc6 #xc6 #xc6 #x7e #xc #x1cc #xf8)
      ;; h
      (104 9 1 10 8 #x30 #x30 #x30 #x7e #x63 #x63 #x63 #xc3 #xc6 #xc6)
      ;; i
      (105 6 2 10 4 #x3 #x3 #x0 #x6 #x6 #x6 #x6 #xc #xc #xc)
      ;; j
      (106 6 0 10 6 #x3 #x3 #x0 #x6 #x6 #x6 #x6 #xc #xc #xc #xc #x38)
      ;; k
      (107 8 1 10 7 #x18 #x18 #x18 #x33 #x36 #x2c #x3c #x66 #x63 #x63)
      ;; l
      (108 6 2 10 4 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xc #xc #xc)
      ;; m
      (109 12 1 7 11 #x3fe #x3bb #x333 #x333 #x633 #x666 #x666)
      ;; n
      (110 9 1 7 8 #x7e #x73 #x63 #x63 #xc3 #xc6 #xc6)
      ;; o
      (111 9 1 7 8 #x3e #x63 #xc3 #xc3 #xc3 #xc6 #x7c)
      ;; p
      (112 9 0 7 9 #x7e #x73 #x63 #xc3 #xc3 #xc6 #xfc #x180 #x180 #x180)
      ;; q
      (113 9 1 7 8 #x3f #x67 #xc3 #xc6 #xc6 #xc6 #x7e #xc #xc #xc)
      ;; r
      (114 7 1 7 7 #x3f #x38 #x30 #x30 #x60 #x60 #x60)
      ;; s
      (115 8 1 7 7 #x1e #x33 #x38 #xe #x63 #x63 #x3e)
      ;; t
      (116 7 2 9 6 #xc #xc #x3f #x18 #x18 #x18 #x30 #x30 #x1e)
      ;; u
      (117 9 1 7 8 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e)
      ;; v
      (118 8 2 7 6 #x33 #x33 #x36 #x36 #x34 #x3c #x38)
      ;; w
      (119 12 2 7 10 #x333 #x333 #x376 #x356 #x2d4 #x39c #x318)
      ;; x
      (120 9 1 7 8 #x63 #x66 #x3c #x18 #x3c #x66 #xc6)
      ;; y
      (121 9 0 7 9 #x63 #x63 #x66 #x66 #x2c #x38 #x18 #x30 #x1e0 #x1c0)
      ;; z
      (122 9 1 7 8 #x7f #x6 #xc #x18 #x30 #x60 #xfe)
      ;; {
      (123 10 2 10 8 #x7 #xc #x18 #x18 #x18 #x30 #xe0 #x30 #x30 #x60 #x60 #x60
        #x38)
      ;; |
      (124 6 2 10 4 #x3 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xc #xc #xc #xc)
      ;; }
      (125 10 2 10 8 #x1c #x6 #x6 #x6 #xc #xc #x7 #xc #x18 #x18 #x18 #x30 #xe0)
      ;; ~
      (126 10 2 7 8 #x73 #xdb #xce)
      ;; ¬
      (172 9 1 6 7 #x7f #x3 #x3)
      ;; °
      (176 6 1 10 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 1 7 6 #xc #xc #x3f #x3f #xc #x0 #x3f #x3f)
      ;; µ
      (181 9 1 7 8 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e #xc0 #xc0 #xc0)
      ;; ·
      (183 8 2 6 4 #x6 #xf #xf #x6)
      ;; À
      (192 9 0 11 8 #x30 #x18 #x0 #x7 #xb #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Á
      (193 9 0 11 8 #x18 #x30 #x0 #x7 #xb #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Â
      (194 9 0 11 8 #x18 #x3c #x0 #x7 #xb #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Ã
      (195 9 0 11 8 #x3c #x78 #x0 #x7 #xb #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Ä
      (196 9 0 11 8 #x24 #x24 #x0 #x7 #xb #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Å
      (197 9 0 11 8 #x18 #x3c #x18 #x7 #xb #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Ç
      (199 10 1 10 9 #x1e #x73 #xc3 #xc0 #x180 #x180 #x183 #x183 #xc6 #x7c
        #x30 #x60)
      ;; È
      (200 10 1 11 10 #x60 #x30 #x0 #xff #xc0 #x180 #x1fc #x180 #x300 #x300
        #x3fc)
      ;; É
      (201 10 1 11 10 #x30 #x60 #x0 #xff #xc0 #x180 #x1fc #x180 #x300 #x300
        #x3fc)
      ;; Ê
      (202 10 1 11 10 #x30 #x78 #x0 #xff #xc0 #x180 #x1fc #x180 #x300 #x300
        #x3fc)
      ;; Ë
      (203 10 1 11 10 #x48 #x48 #x0 #xff #xc0 #x180 #x1fc #x180 #x300 #x300
        #x3fc)
      ;; Ì
      (204 5 1 11 4 #xc #x6 #x0 #x3 #x3 #x3 #x6 #x6 #xc #xc #xc)
      ;; Í
      (205 5 1 11 4 #x6 #xc #x0 #x3 #x3 #x3 #x6 #x6 #xc #xc #xc)
      ;; Î
      (206 5 1 11 4 #x6 #xf #x0 #x3 #x3 #x3 #x6 #x6 #xc #xc #xc)
      ;; Ï
      (207 5 1 11 4 #x9 #x9 #x0 #x3 #x3 #x3 #x6 #x6 #xc #xc #xc)
      ;; Ñ
      (209 12 1 11 11 #xf0 #x1e0 #x0 #x1c3 #x1e3 #x366 #x336 #x336 #x63c #x61c
        #x61c)
      ;; Ò
      (210 11 1 11 10 #x60 #x30 #x0 #x7c #xc6 #x183 #x303 #x306 #x306 #x18c
        #xf8)
      ;; Ó
      (211 11 1 11 10 #x30 #x60 #x0 #x7c #xc6 #x183 #x303 #x306 #x306 #x18c
        #xf8)
      ;; Ô
      (212 11 1 11 10 #x30 #x78 #x0 #x7c #xc6 #x183 #x303 #x306 #x306 #x18c
        #xf8)
      ;; Õ
      (213 11 1 11 10 #x78 #xf0 #x0 #x7c #xc6 #x183 #x303 #x306 #x306 #x18c
        #xf8)
      ;; Ö
      (214 11 1 11 10 #x48 #x48 #x0 #x7c #xc6 #x183 #x303 #x306 #x306 #x18c
        #xf8)
      ;; ×
      (215 9 1 7 8 #x63 #x66 #x3c #x18 #x3c #x66 #xc6)
      ;; Ù
      (217 11 1 11 10 #x60 #x30 #x0 #xc3 #xc3 #xc3 #x186 #x306 #x30c #x30c
        #x1f8)
      ;; Ú
      (218 11 1 11 10 #x30 #x60 #x0 #xc3 #xc3 #xc3 #x186 #x306 #x30c #x30c
        #x1f8)
      ;; Û
      (219 11 1 11 10 #x30 #x78 #x0 #xc3 #xc3 #xc3 #x186 #x306 #x30c #x30c
        #x1f8)
      ;; Ü
      (220 11 1 11 10 #x48 #x48 #x0 #xc3 #xc3 #xc3 #x186 #x306 #x30c #x30c
        #x1f8)
      ;; Ý
      (221 9 1 11 10 #x30 #x60 #x0 #x303 #x18c #x198 #xf0 #xe0 #xc0 #x180
        #x180)
      ;; à
      (224 9 1 10 8 #x30 #x18 #x0 #x3e #x63 #x3 #x7f #xc6 #xc6 #x7f)
      ;; á
      (225 9 1 10 8 #x18 #x30 #x0 #x3e #x63 #x3 #x7f #xc6 #xc6 #x7f)
      ;; â
      (226 9 1 10 8 #x18 #x3c #x0 #x3e #x63 #x3 #x7f #xc6 #xc6 #x7f)
      ;; ã
      (227 9 1 10 8 #x3c #x78 #x0 #x3e #x63 #x3 #x7f #xc6 #xc6 #x7f)
      ;; ä
      (228 9 1 10 8 #x24 #x24 #x0 #x3e #x63 #x3 #x7f #xc6 #xc6 #x7f)
      ;; å
      (229 9 1 11 8 #x18 #x3c #x18 #x0 #x3e #x63 #x3 #x7f #xc6 #xc6 #x7f)
      ;; ç
      (231 9 1 7 8 #x3e #x63 #xc0 #xc0 #xc3 #xc6 #x7c #x18 #x30)
      ;; è
      (232 9 1 10 8 #x30 #x18 #x0 #x1e #x73 #x63 #xff #xc0 #xc6 #x7c)
      ;; é
      (233 9 1 10 8 #x18 #x30 #x0 #x1e #x73 #x63 #xff #xc0 #xc6 #x7c)
      ;; ê
      (234 9 1 10 8 #x18 #x3c #x0 #x1e #x73 #x63 #xff #xc0 #xc6 #x7c)
      ;; ë
      (235 9 1 10 8 #x24 #x24 #x0 #x1e #x73 #x63 #xff #xc0 #xc6 #x7c)
      ;; ì
      (236 6 1 10 4 #xc #x6 #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6)
      ;; í
      (237 6 1 10 4 #x6 #xc #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6)
      ;; î
      (238 6 1 10 4 #x6 #xf #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6)
      ;; ï
      (239 6 1 10 4 #x9 #x9 #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6)
      ;; ñ
      (241 9 1 10 8 #x3c #x78 #x0 #x7e #x73 #x63 #x63 #xc3 #xc6 #xc6)
      ;; ò
      (242 9 1 10 8 #x30 #x18 #x0 #x3e #x63 #xc3 #xc3 #xc3 #xc6 #x7c)
      ;; ó
      (243 9 1 10 8 #x18 #x30 #x0 #x3e #x63 #xc3 #xc3 #xc3 #xc6 #x7c)
      ;; ô
      (244 9 1 10 8 #x18 #x3c #x0 #x3e #x63 #xc3 #xc3 #xc3 #xc6 #x7c)
      ;; õ
      (245 9 1 10 8 #x3c #x78 #x0 #x3e #x63 #xc3 #xc3 #xc3 #xc6 #x7c)
      ;; ö
      (246 9 1 10 8 #x24 #x24 #x0 #x3e #x63 #xc3 #xc3 #xc3 #xc6 #x7c)
      ;; ù
      (249 9 1 10 8 #x30 #x18 #x0 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e)
      ;; ú
      (250 9 1 10 8 #x18 #x30 #x0 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e)
      ;; û
      (251 9 1 10 8 #x18 #x3c #x0 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e)
      ;; ü
      (252 9 1 10 8 #x24 #x24 #x0 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e)
      ;; ý
      (253 9 0 10 9 #x30 #x60 #x0 #x63 #x63 #x66 #x66 #x2c #x38 #x18 #x30
        #x1e0 #x1c0)
      ;; ÿ
      (255 9 0 10 9 #x48 #x48 #x0 #x63 #x63 #x66 #x66 #x2c #x38 #x18 #x30
        #x1e0 #x1c0)
      ;; combining diaeresis
      (776 0 4 10 4 #x9 #x9)
      ;; α
      (945 9 1 6 7 #x3f #x66 #x66 #x66 #x66 #x3f)
      ;; β
      (946 9 1 8 7 #x3e #x63 #x63 #x7e #x63 #x63 #x63 #x7e #x60 #x60)
      ;; γ
      (947 8 1 8 6 #x33 #x1e #xc #x1e #x33 #x33 #x33 #x1e)
      ;; δ
      (948 9 1 9 7 #x1e #x30 #x30 #x18 #x1c #x36 #x63 #x63 #x3e)
      ;; ε
      (949 8 1 6 6 #xf #x18 #x3e #x30 #x18 #xf)
      ;; λ
      (955 9 1 8 7 #x60 #x60 #x30 #x18 #x1c #x36 #x63 #x63)
      ;; π
      (960 9 1 6 7 #x7f #x36 #x36 #x36 #x36 #x36)
      ;; –
      (8211 9 0 5 8 #xff)
      ;; —
      (8212 14 0 5 14 #x3fff)
      ;; ‘
      (8216 5 2 10 3 #x3 #x3 #x6 #x6)
      ;; ’
      (8217 5 2 10 3 #x3 #x3 #x6 #x6)
      ;; “
      (8220 8 2 10 6 #x1b #x1b #x36 #x36)
      ;; ”
      (8221 8 2 10 6 #x1b #x1b #x36 #x36)
      ;; …
      (8230 18 2 2 14 #x30c3 #x30c3)
      ;; ←
      (8592 10 2 7 8 #x18 #x30 #xff #x60 #x30)
      ;; ↑
      (8593 8 2 8 6 #xc #x1e #x3f #xc #x18 #x18 #x18)
      ;; →
      (8594 9 1 7 7 #xc #x6 #x7f #x6 #xc)
      ;; ↓
      (8595 8 1 7 6 #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↔
      (8596 9 1 9 7 #xc #x6 #x7f #x6 #xc #x18 #x30 #x7f #x30 #x18)
      ;; ↳
      (8627 9 1 10 7 #x60 #x60 #x60 #x6c #x66 #x7f #x6 #xc)
      ;; ∀
      (8704 9 1 9 7 #x63 #x63 #x63 #x63 #x7f #x63 #x36 #x36 #x1c)
      ;; ∂
      (8706 8 1 9 6 #x1c #x6 #x3 #x3 #x1f #x33 #x33 #x33 #x1e)
      ;; ∃
      (8707 9 1 9 7 #x7f #x3 #x3 #x3 #x3f #x3 #x3 #x3 #x7f)
      ;; −
      (8722 9 2 4 7 #x7f)
      ;; ∞
      (8734 10 1 6 8 #x7e #xdb #xdb #xdb #x7e)
      ;; ∧
      (8743 9 1 7 7 #x1c #x36 #x63)
      ;; ∨
      (8744 9 1 6 7 #x63 #x36 #x1c)
      ;; ∩
      (8745 8 1 7 6 #x1e #x33 #x33 #x33 #x33 #x33)
      ;; ∪
      (8746 8 1 7 6 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; ∫
      (8747 8 1 10 6 #x7 #xf #xf #xc #xc #xc #xc #xc #x3c #x3c #x38)
      ;; ≠
      (8800 9 1 7 7 #x3 #x6 #x7f #xc #x18 #x7f #x30 #x60)
      ;; ≡
      (8801 10 2 5 6 #x3f #x0 #x3f #x0 #x3f)
      ;; ≤
      (8804 9 2 9 5 #x3 #x6 #xc #x18 #xc #x6 #x3 #x0 #x1f)
      ;; ≥
      (8805 9 2 9 5 #x18 #xc #x6 #x3 #x6 #xc #x18 #x0 #x1f)
      ;; ⊂
      (8834 10 1 6 7 #x3f #x60 #x60 #x60 #x3f)
      ;; ⊃
      (8835 9 1 6 7 #x7e #x3 #x3 #x3 #x7e)
      ;; ⊕
      (8853 10 1 8 8 #x3c #x7e #xdb #xff #xdb #x7e #x3c)
      ;; ⊗
      (8855 10 1 8 8 #x3c #x66 #xff #xdb #xff #x66 #x3c)
      ;; ⋅
      (8901 8 2 6 4 #x6 #xf #xf #x6)
      ;; ▶
      (9654 7 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 8 1 9 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ◊
      (9674 8 1 9 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 13 1 11 11 #x20 #x20 #x50 #x88 #xa8 #xa8 #x124 #x222 #x202 #x222
        #x7ff)
      ;; ✓
      (10003 8 0 8 7 #x3 #x3 #x6 #x6 #x6c #x3c #x38 #x18)
      ;; ❚
      (10074 6 1 10 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("Genera HL14" 15 12 3
      ;; the slug, which a character the face lacks draws
      (#f 7 1 11 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x1f)
      ;; space
      (32 7)
      ;; !
      (33 4 2 11 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x1 #x1)
      ;; "
      (34 6 1 11 4 #x9 #x9 #x9 #x9)
      ;; #
      (35 12 1 11 10 #x12 #x12 #x24 #x1ff #x48 #x48 #x48 #x3fe #x90 #x120
        #x120)
      ;; $
      (36 10 1 12 8 #x8 #x3e #x49 #x49 #x48 #x28 #x1c #xa #x9 #x89 #x49 #x3e
        #x8)
      ;; %
      (37 13 1 11 11 #x308 #x488 #x490 #x490 #x320 #x20 #x26 #x49 #x49 #x89
        #x86)
      ;; &
      (38 11 1 11 9 #x70 #x88 #x88 #x88 #x50 #xb0 #x109 #x106 #x104 #x86 #x79)
      ;; '
      (39 5 1 11 2 #x3 #x3 #x1 #x2)
      ;; (
      (40 7 2 11 4 #x1 #x2 #x4 #x4 #x8 #x8 #x8 #x8 #x8 #x4 #x4 #x2 #x1)
      ;; )
      (41 7 1 11 4 #x8 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4 #x8)
      ;; *
      (42 9 1 11 7 #x8 #x49 #x2a #x1c #x2a #x49 #x8)
      ;; +
      (43 9 1 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8)
      ;; ,
      (44 6 1 2 3 #x7 #x3 #x2 #x4)
      ;; -
      (45 8 1 6 6 #x3f)
      ;; .
      (46 6 2 2 2 #x3 #x3)
      ;; /
      (47 8 1 11 6 #x1 #x1 #x2 #x2 #x4 #x4 #x8 #x8 #x10 #x10 #x20 #x20)
      ;; 0
      (48 10 1 11 8 #x3c #x42 #x81 #x81 #x81 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; 1
      (49 10 3 11 4 #x1 #x3 #xd #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; 2
      (50 10 1 11 8 #x3c #x42 #x81 #x81 #x2 #x4 #x18 #x20 #x40 #x80 #xff)
      ;; 3
      (51 10 1 11 8 #x3c #x42 #x81 #x81 #x2 #x1c #x2 #x81 #x81 #x42 #x3c)
      ;; 4
      (52 10 1 11 8 #x6 #xa #x12 #x12 #x22 #x42 #x82 #xff #x2 #x2 #x2)
      ;; 5
      (53 10 1 11 8 #x3f #x20 #x20 #x40 #x5c #x62 #x1 #x1 #x81 #x42 #x3c)
      ;; 6
      (54 10 1 11 8 #x3c #x42 #x80 #x80 #xbc #xc2 #x81 #x81 #x81 #x42 #x3c)
      ;; 7
      (55 10 1 11 8 #xff #x1 #x2 #x4 #x8 #x8 #x10 #x10 #x20 #x20 #x20)
      ;; 8
      (56 10 1 11 8 #x3c #x42 #x42 #x42 #x3c #x42 #x81 #x81 #x81 #x42 #x3c)
      ;; 9
      (57 10 1 11 8 #x3c #x42 #x81 #x81 #x81 #x43 #x3d #x1 #x1 #x42 #x3c)
      ;; :
      (58 6 2 8 2 #x3 #x3 #x0 #x0 #x0 #x0 #x3 #x3)
      ;; ;
      (59 6 1 8 3 #x3 #x3 #x0 #x0 #x0 #x0 #x3 #x3 #x2 #x4)
      ;; <
      (60 8 1 11 6 #x1 #x2 #x4 #x8 #x10 #x20 #x10 #x8 #x4 #x2 #x1)
      ;; =
      (61 8 1 6 6 #x3f #x0 #x0 #x3f)
      ;; >
      (62 8 1 11 6 #x20 #x10 #x8 #x4 #x2 #x1 #x2 #x4 #x8 #x10 #x20)
      ;; ?
      (63 8 1 11 6 #x1e #x21 #x21 #x1 #x2 #x4 #x8 #x8 #x0 #x8 #x8)
      ;; @
      (64 14 1 11 12 #x1fc #x602 #x469 #x899 #x909 #x909 #x911 #x932 #x4cc
        #x601 #x1fe)
      ;; A
      (65 11 1 11 9 #x38 #x28 #x28 #x44 #x44 #x44 #x82 #xfe #x82 #x101 #x101)
      ;; B
      (66 11 1 11 9 #x1fc #x102 #x102 #x102 #x102 #x1fe #x101 #x101 #x101
        #x101 #x1fe)
      ;; C
      (67 12 1 11 10 #x7c #x182 #x101 #x201 #x200 #x200 #x200 #x201 #x101
        #x182 #x7c)
      ;; D
      (68 11 1 11 9 #x1f8 #x106 #x102 #x101 #x101 #x101 #x101 #x101 #x102
        #x106 #x1f8)
      ;; E
      (69 10 1 11 8 #xff #x80 #x80 #x80 #x80 #xfe #x80 #x80 #x80 #x80 #xff)
      ;; F
      (70 10 1 11 8 #xff #x80 #x80 #x80 #x80 #xfe #x80 #x80 #x80 #x80 #x80)
      ;; G
      (71 12 1 11 10 #x7c #x182 #x101 #x201 #x200 #x21f #x201 #x201 #x101
        #x183 #x7d)
      ;; H
      (72 11 1 11 9 #x101 #x101 #x101 #x101 #x101 #x1ff #x101 #x101 #x101
        #x101 #x101)
      ;; I
      (73 5 2 11 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; J
      (74 9 1 11 7 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x41 #x41 #x22 #x1c)
      ;; K
      (75 10 1 11 8 #x81 #x82 #x84 #x88 #x98 #xa4 #xc4 #x82 #x82 #x81 #x81)
      ;; L
      (76 9 1 11 7 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x7f)
      ;; M
      (77 14 1 11 12 #xc03 #xc03 #xa05 #xa05 #x909 #x909 #x891 #x891 #x891
        #x861 #x861)
      ;; N
      (78 11 1 11 9 #x181 #x181 #x141 #x121 #x121 #x111 #x109 #x109 #x105
        #x103 #x103)
      ;; O
      (79 13 1 11 11 #xf8 #x306 #x202 #x401 #x401 #x401 #x401 #x401 #x202
        #x306 #xf8)
      ;; P
      (80 10 1 11 8 #xfc #x82 #x81 #x81 #x81 #x82 #xfc #x80 #x80 #x80 #x80)
      ;; Q
      (81 13 1 11 11 #xf8 #x306 #x202 #x401 #x401 #x401 #x401 #x401 #x212
        #x30e #xfc #x2 #x1)
      ;; R
      (82 11 1 11 9 #x1fc #x102 #x101 #x101 #x102 #x1fc #x102 #x102 #x101
        #x101 #x101)
      ;; S
      (83 11 1 11 9 #x7c #x82 #x101 #x101 #xe0 #x1c #x2 #x101 #x101 #x82 #x7c)
      ;; T
      (84 11 1 11 9 #x1ff #x10 #x10 #x10 #x10 #x10 #x10 #x10 #x10 #x10 #x10)
      ;; U
      (85 11 1 11 9 #x101 #x101 #x101 #x101 #x101 #x101 #x101 #x101 #x101 #x82
        #x7c)
      ;; V
      (86 11 1 11 9 #x101 #x101 #x82 #x82 #x82 #x44 #x44 #x44 #x28 #x28 #x10)
      ;; W
      (87 15 1 11 13 #x1041 #x1041 #x1041 #x8a2 #x8a2 #x8a2 #x514 #x514 #x514
        #x208 #x208)
      ;; X
      (88 11 1 11 9 #x101 #x82 #x44 #x44 #x28 #x10 #x28 #x44 #x44 #x82 #x101)
      ;; Y
      (89 11 1 11 9 #x101 #x101 #x82 #x44 #x44 #x28 #x10 #x10 #x10 #x10 #x10)
      ;; Z
      (90 10 1 11 8 #xff #x1 #x2 #x4 #x8 #x8 #x10 #x20 #x40 #x80 #xff)
      ;; [
      (91 7 2 12 4 #xf #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #xf)
      ;; \
      (92 8 1 11 6 #x20 #x20 #x10 #x10 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ]
      (93 7 1 12 4 #xf #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #xf)
      ;; ^
      (94 9 1 11 7 #x8 #x14 #x22 #x41)
      ;; _
      (95 11 0 -1 9 #x1ff)
      ;; `
      (96 5 2 11 2 #x1 #x2 #x3 #x3)
      ;; a
      (97 10 1 8 8 #x3c #x42 #x2 #x7e #x82 #x82 #x86 #x7b)
      ;; b
      (98 9 1 11 7 #x40 #x40 #x40 #x5c #x62 #x41 #x41 #x41 #x41 #x62 #x5c)
      ;; c
      (99 9 1 8 7 #x1e #x21 #x40 #x40 #x40 #x40 #x21 #x1e)
      ;; d
      (100 9 1 11 7 #x1 #x1 #x1 #x1d #x23 #x41 #x41 #x41 #x41 #x23 #x1d)
      ;; e
      (101 9 1 8 7 #x1c #x22 #x41 #x7f #x40 #x40 #x21 #x1e)
      ;; f
      (102 6 1 11 5 #x7 #x8 #x8 #x1e #x8 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; g
      (103 9 1 8 7 #x1d #x23 #x41 #x41 #x41 #x41 #x23 #x1d #x1 #x42 #x3c)
      ;; h
      (104 9 1 11 7 #x40 #x40 #x40 #x5e #x61 #x41 #x41 #x41 #x41 #x41 #x41)
      ;; i
      (105 5 2 11 1 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; j
      (106 6 1 11 3 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x6)
      ;; k
      (107 8 1 11 6 #x20 #x20 #x20 #x21 #x22 #x24 #x2c #x32 #x22 #x21 #x21)
      ;; l
      (108 5 2 11 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; m
      (109 13 1 8 11 #x5ce #x631 #x421 #x421 #x421 #x421 #x421 #x421)
      ;; n
      (110 9 1 8 7 #x5e #x61 #x41 #x41 #x41 #x41 #x41 #x41)
      ;; o
      (111 10 1 8 8 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; p
      (112 9 1 8 7 #x5c #x62 #x41 #x41 #x41 #x41 #x62 #x5c #x40 #x40 #x40)
      ;; q
      (113 9 1 8 7 #x1d #x23 #x41 #x41 #x41 #x41 #x23 #x1d #x1 #x1 #x1)
      ;; r
      (114 6 1 8 4 #xb #xc #x8 #x8 #x8 #x8 #x8 #x8)
      ;; s
      (115 8 1 8 6 #x1e #x21 #x20 #x18 #x6 #x21 #x21 #x1e)
      ;; t
      (116 6 1 10 4 #x4 #x4 #xf #x4 #x4 #x4 #x4 #x4 #x4 #x3)
      ;; u
      (117 9 1 8 7 #x41 #x41 #x41 #x41 #x41 #x41 #x43 #x3d)
      ;; v
      (118 9 1 8 7 #x41 #x41 #x22 #x22 #x22 #x14 #x14 #x8)
      ;; w
      (119 13 1 8 11 #x421 #x421 #x451 #x252 #x28a #x28a #x104 #x104)
      ;; x
      (120 9 1 8 7 #x22 #x22 #x14 #x8 #x14 #x22 #x41 #x41)
      ;; y
      (121 9 1 8 7 #x41 #x41 #x21 #x22 #x22 #x14 #x14 #x8 #x8 #x50 #x20)
      ;; z
      (122 8 1 8 6 #x3f #x1 #x2 #x4 #x8 #x10 #x20 #x3f)
      ;; {
      (123 8 1 12 5 #x3 #x4 #x4 #x4 #x4 #x4 #x4 #x18 #x4 #x4 #x4 #x4 #x4 #x4
        #x3)
      ;; |
      (124 3 1 11 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; }
      (125 8 2 12 5 #x18 #x4 #x4 #x4 #x4 #x4 #x4 #x3 #x4 #x4 #x4 #x4 #x4 #x4
        #x18)
      ;; ~
      (126 11 1 7 9 #x61 #x92 #x10c)
      ;; ¬
      (172 9 1 6 7 #x7f #x1 #x1)
      ;; °
      (176 6 1 11 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 1 9 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8 #x0 #x7f)
      ;; µ
      (181 9 1 8 7 #x41 #x41 #x41 #x41 #x41 #x41 #x43 #x3d #x40 #x40 #x40)
      ;; ·
      (183 9 3 7 4 #x6 #xf #xf #x6)
      ;; À
      (192 11 1 12 9 #x20 #x10 #x0 #x38 #x28 #x28 #x44 #x82 #xfe #x82 #x101
        #x101)
      ;; Á
      (193 11 1 12 9 #x10 #x20 #x0 #x38 #x28 #x28 #x44 #x82 #xfe #x82 #x101
        #x101)
      ;; Â
      (194 11 1 12 9 #x20 #x50 #x0 #x38 #x28 #x28 #x44 #x82 #xfe #x82 #x101
        #x101)
      ;; Ã
      (195 11 1 12 9 #x28 #x50 #x0 #x38 #x28 #x28 #x44 #x82 #xfe #x82 #x101
        #x101)
      ;; Ä
      (196 11 1 12 9 #x50 #x0 #x38 #x28 #x28 #x44 #x44 #x82 #xfe #x82 #x101
        #x101)
      ;; Å
      (197 11 1 12 9 #x20 #x50 #x20 #x38 #x28 #x28 #x44 #x82 #xfe #x82 #x101
        #x101)
      ;; Ç
      (199 12 1 11 10 #x7c #x182 #x101 #x201 #x200 #x200 #x200 #x201 #x101
        #x182 #x7c #x10 #x20)
      ;; È
      (200 10 1 12 8 #x10 #x8 #x0 #xff #x80 #x80 #xfe #x80 #x80 #x80 #x80 #xff)
      ;; É
      (201 10 1 12 8 #x8 #x10 #x0 #xff #x80 #x80 #xfe #x80 #x80 #x80 #x80 #xff)
      ;; Ê
      (202 10 1 12 8 #x10 #x28 #x0 #xff #x80 #x80 #xfe #x80 #x80 #x80 #x80
        #xff)
      ;; Ë
      (203 10 1 12 8 #x28 #x0 #xff #x80 #x80 #x80 #xfe #x80 #x80 #x80 #x80
        #xff)
      ;; Ì
      (204 5 1 12 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Í
      (205 5 1 12 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Î
      (206 5 0 12 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Ï
      (207 5 0 12 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Ñ
      (209 11 1 12 9 #x28 #x50 #x0 #x181 #x141 #x121 #x111 #x109 #x109 #x105
        #x103 #x103)
      ;; Ò
      (210 13 1 12 11 #x40 #x20 #x0 #xf8 #x306 #x202 #x401 #x401 #x401 #x202
        #x306 #xf8)
      ;; Ó
      (211 13 1 12 11 #x20 #x40 #x0 #xf8 #x306 #x202 #x401 #x401 #x401 #x202
        #x306 #xf8)
      ;; Ô
      (212 13 1 12 11 #x40 #xa0 #x0 #xf8 #x306 #x202 #x401 #x401 #x401 #x202
        #x306 #xf8)
      ;; Õ
      (213 13 1 12 11 #x50 #xa0 #x0 #xf8 #x306 #x202 #x401 #x401 #x401 #x202
        #x306 #xf8)
      ;; Ö
      (214 13 1 12 11 #xa0 #x0 #xf8 #x306 #x202 #x401 #x401 #x401 #x401 #x202
        #x306 #xf8)
      ;; ×
      (215 9 1 8 7 #x22 #x22 #x14 #x8 #x14 #x22 #x41 #x41)
      ;; Ù
      (217 11 1 12 9 #x20 #x10 #x0 #x101 #x101 #x101 #x101 #x101 #x101 #x101
        #x82 #x7c)
      ;; Ú
      (218 11 1 12 9 #x10 #x20 #x0 #x101 #x101 #x101 #x101 #x101 #x101 #x101
        #x82 #x7c)
      ;; Û
      (219 11 1 12 9 #x20 #x50 #x0 #x101 #x101 #x101 #x101 #x101 #x101 #x101
        #x82 #x7c)
      ;; Ü
      (220 11 1 12 9 #x50 #x0 #x101 #x101 #x101 #x101 #x101 #x101 #x101 #x101
        #x82 #x7c)
      ;; Ý
      (221 11 1 12 9 #x10 #x20 #x0 #x101 #x82 #x44 #x28 #x10 #x10 #x10 #x10
        #x10)
      ;; à
      (224 10 1 11 8 #x10 #x8 #x0 #x3c #x42 #x2 #x7e #x82 #x82 #x86 #x7b)
      ;; á
      (225 10 1 11 8 #x8 #x10 #x0 #x3c #x42 #x2 #x7e #x82 #x82 #x86 #x7b)
      ;; â
      (226 10 1 11 8 #x10 #x28 #x0 #x3c #x42 #x2 #x7e #x82 #x82 #x86 #x7b)
      ;; ã
      (227 10 1 11 8 #x14 #x28 #x0 #x3c #x42 #x2 #x7e #x82 #x82 #x86 #x7b)
      ;; ä
      (228 10 1 10 8 #x28 #x0 #x3c #x42 #x2 #x7e #x82 #x82 #x86 #x7b)
      ;; å
      (229 10 1 12 8 #x10 #x28 #x10 #x0 #x3c #x42 #x2 #x7e #x82 #x82 #x86 #x7b)
      ;; ç
      (231 9 1 8 7 #x1e #x21 #x40 #x40 #x40 #x40 #x21 #x1e #x8 #x10)
      ;; è
      (232 9 1 11 7 #x10 #x8 #x0 #x1c #x22 #x41 #x7f #x40 #x40 #x21 #x1e)
      ;; é
      (233 9 1 11 7 #x8 #x10 #x0 #x1c #x22 #x41 #x7f #x40 #x40 #x21 #x1e)
      ;; ê
      (234 9 1 11 7 #x10 #x28 #x0 #x1c #x22 #x41 #x7f #x40 #x40 #x21 #x1e)
      ;; ë
      (235 9 1 10 7 #x28 #x0 #x1c #x22 #x41 #x7f #x40 #x40 #x21 #x1e)
      ;; ì
      (236 5 1 11 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; í
      (237 5 1 11 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; î
      (238 5 0 11 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ï
      (239 5 0 10 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ñ
      (241 9 1 11 7 #x14 #x28 #x0 #x5e #x61 #x41 #x41 #x41 #x41 #x41 #x41)
      ;; ò
      (242 10 1 11 8 #x10 #x8 #x0 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; ó
      (243 10 1 11 8 #x8 #x10 #x0 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; ô
      (244 10 1 11 8 #x10 #x28 #x0 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; õ
      (245 10 1 11 8 #x14 #x28 #x0 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; ö
      (246 10 1 10 8 #x28 #x0 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; ù
      (249 9 1 11 7 #x10 #x8 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x43 #x3d)
      ;; ú
      (250 9 1 11 7 #x8 #x10 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x43 #x3d)
      ;; û
      (251 9 1 11 7 #x10 #x28 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x43 #x3d)
      ;; ü
      (252 9 1 10 7 #x28 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x43 #x3d)
      ;; ý
      (253 9 1 11 7 #x8 #x10 #x0 #x41 #x41 #x21 #x22 #x22 #x14 #x14 #x8 #x8
        #x50 #x20)
      ;; ÿ
      (255 9 1 10 7 #x28 #x0 #x41 #x41 #x21 #x22 #x22 #x14 #x14 #x8 #x8 #x50
        #x20)
      ;; α
      (945 9 1 9 8 #x2 #x62 #x94 #x88 #x88 #x94 #x63)
      ;; β
      (946 9 2 11 6 #xe #x11 #x11 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20 #x20)
      ;; γ
      (947 9 1 9 7 #x31 #x49 #x6 #x4 #xc #xc #x14 #x14 #x14 #x8)
      ;; δ
      (948 9 1 12 7 #x1c #x22 #x21 #x20 #x10 #xc #x12 #x21 #x41 #x41 #x3e)
      ;; ε
      (949 9 2 8 5 #x7 #x8 #x10 #x1f #x10 #x8 #x7)
      ;; λ
      (955 9 1 11 7 #x60 #x10 #x10 #x8 #x18 #x14 #x24 #x22 #x42 #x41)
      ;; π
      (960 9 1 8 7 #x7f #x22 #x22 #x22 #x22 #x22 #x22)
      ;; –
      (8211 9 0 6 8 #xff)
      ;; —
      (8212 14 0 6 14 #x3fff)
      ;; ‘
      (8216 5 1 11 2 #x3 #x3 #x1 #x2)
      ;; ’
      (8217 5 1 11 2 #x3 #x3 #x1 #x2)
      ;; “
      (8220 6 1 11 4 #x9 #x9 #x9 #x9)
      ;; ”
      (8221 6 1 11 4 #x9 #x9 #x9 #x9)
      ;; …
      (8230 18 2 2 14 #x30c3 #x30c3)
      ;; ←
      (8592 11 1 9 9 #x20 #x40 #x80 #x1ff #x80 #x40 #x20)
      ;; ↑
      (8593 9 1 9 7 #x8 #x1c #x2a #x49 #x8 #x8 #x8 #x8)
      ;; →
      (8594 11 1 9 9 #x8 #x4 #x2 #x1ff #x2 #x4 #x8)
      ;; ↓
      (8595 9 2 11 5 #x4 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 9 1 10 6 #x4 #x2 #x3f #x2 #x4 #x8 #x10 #x3f #x10 #x8)
      ;; ↳
      (8627 11 1 11 9 #x100 #x100 #x108 #x104 #x102 #x1ff #x2 #x4 #x8)
      ;; ∀
      (8704 9 1 12 7 #x41 #x41 #x41 #x3e #x22 #x22 #x14 #x14 #x14 #x8 #x8)
      ;; ∂
      (8706 9 2 12 6 #xc #x12 #x1 #x1 #x1 #xf #x11 #x21 #x21 #x12 #xc)
      ;; ∃
      (8707 9 1 12 7 #x7f #x1 #x1 #x1 #x1 #x3f #x1 #x1 #x1 #x1 #x7f)
      ;; −
      (8722 9 1 5 7 #x7f)
      ;; ∞
      (8734 9 1 8 7 #x36 #x49 #x49 #x49 #x49 #x36)
      ;; ∧
      (8743 9 1 7 7 #x8 #x14 #x22 #x41)
      ;; ∨
      (8744 9 1 7 7 #x41 #x22 #x14 #x8)
      ;; ∩
      (8745 9 2 9 6 #x1e #x21 #x21 #x21 #x21 #x21 #x21)
      ;; ∪
      (8746 9 2 9 6 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ∫
      (8747 9 2 12 7 #x6 #x9 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x48 #x30)
      ;; ≠
      (8800 9 1 10 7 #x2 #x2 #x4 #x7f #x8 #x10 #x7f #x20 #x40)
      ;; ≡
      (8801 9 1 8 7 #x7f #x0 #x7f #x0 #x7f)
      ;; ≤
      (8804 9 1 9 7 #x3 #xc #x30 #x40 #x30 #xc #x3 #x7f)
      ;; ≥
      (8805 9 1 9 7 #x60 #x18 #x6 #x1 #x6 #x18 #x60 #x7f)
      ;; ⊂
      (8834 9 1 8 7 #x3f #x40 #x40 #x40 #x40 #x3f)
      ;; ⊃
      (8835 9 1 8 7 #x7e #x1 #x1 #x1 #x1 #x7e)
      ;; ⊕
      (8853 9 1 9 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 9 1 9 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 9 3 7 4 #x6 #xf #xf #x6)
      ;; ▶
      (9654 8 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 9 1 11 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ◊
      (9674 9 1 11 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 15 1 12 13 #x40 #xa0 #xa0 #x110 #x150 #x248 #x248 #x444 #x444
        #x802 #x842 #x1fff)
      ;; ✓
      (10003 9 0 9 8 #x1 #x1 #x2 #x2 #x84 #x44 #x28 #x28 #x10)
      ;; ❚
      (10074 4 1 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera HL14 Bold" 15 12 3
      ;; the slug, which a character the face lacks draws
      (#f 8 1 11 6 #x3f #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x3f)
      ;; space
      (32 8)
      ;; !
      (33 5 2 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x0 #x3 #x3)
      ;; "
      (34 7 1 11 5 #x1b #x1b #x1b #x1b)
      ;; #
      (35 13 1 11 11 #x36 #x36 #x6c #x3ff #xd8 #xd8 #xd8 #x7fe #x1b0 #x360
        #x360)
      ;; $
      (36 11 1 12 9 #x18 #x7e #xdb #xdb #xd8 #x78 #x3c #x1e #x1b #x19b #xdb
        #x7e #x18)
      ;; %
      (37 14 1 11 12 #x718 #xd98 #xdb0 #xdb0 #x760 #x60 #x6e #xdb #xdb #x19b
        #x18e)
      ;; &
      (38 12 1 11 10 #xf0 #x198 #x198 #x198 #xf0 #x1f0 #x31b #x30e #x30c #x18e
        #xfb)
      ;; '
      (39 4 1 11 2 #x3 #x3 #x3 #x3)
      ;; (
      (40 7 1 11 5 #x3 #x6 #xc #xc #x18 #x18 #x18 #x18 #x18 #x18 #xc #xc #x6
        #x3)
      ;; )
      (41 7 1 11 5 #x18 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc #x18)
      ;; *
      (42 10 1 12 8 #x18 #xdb #x7e #x3c #x7e #xdb #x18)
      ;; +
      (43 10 1 8 8 #x18 #x18 #x18 #xff #x18 #x18 #x18)
      ;; ,
      (44 5 1 2 3 #x7 #x3 #x3 #x6)
      ;; -
      (45 9 1 6 7 #x7f)
      ;; .
      (46 4 1 2 2 #x3 #x3)
      ;; /
      (47 9 1 11 7 #x3 #x3 #x6 #x6 #xc #xc #x18 #x18 #x30 #x30 #x60 #x60)
      ;; 0
      (48 11 1 11 9 #x7c #xc6 #x183 #x183 #x183 #x183 #x183 #x183 #x183 #xc6
        #x7c)
      ;; 1
      (49 11 3 11 5 #x3 #x7 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; 2
      (50 11 1 11 9 #x7c #xc6 #x183 #x183 #x6 #xc #x38 #x60 #xc0 #x180 #x1ff)
      ;; 3
      (51 11 1 11 9 #x7c #xc6 #x183 #x183 #x6 #x3c #x6 #x183 #x183 #xc6 #x7c)
      ;; 4
      (52 11 1 11 9 #xe #x1e #x36 #x36 #x66 #xc6 #x186 #x1ff #x6 #x6 #x6)
      ;; 5
      (53 11 1 11 9 #x7f #x60 #x60 #xc0 #xfc #xe6 #x3 #x3 #x183 #xc6 #x7c)
      ;; 6
      (54 11 1 11 9 #x7c #xc6 #x180 #x180 #x1fc #x1c6 #x183 #x183 #x183 #xc6
        #x7c)
      ;; 7
      (55 11 1 11 9 #x1ff #x3 #x6 #xc #x18 #x18 #x30 #x30 #x60 #x60 #x60)
      ;; 8
      (56 11 1 11 9 #x7c #xc6 #xc6 #xc6 #x7c #xc6 #x183 #x183 #x183 #xc6 #x7c)
      ;; 9
      (57 11 1 11 9 #x7c #xc6 #x183 #x183 #x183 #xc7 #x7f #x3 #x3 #xc6 #x7c)
      ;; :
      (58 4 1 8 2 #x3 #x3 #x0 #x0 #x0 #x0 #x3 #x3)
      ;; ;
      (59 5 1 8 3 #x3 #x3 #x0 #x0 #x0 #x0 #x7 #x3 #x3 #x6)
      ;; <
      (60 9 1 11 7 #x3 #x6 #xc #x18 #x30 #x60 #x30 #x18 #xc #x6 #x3)
      ;; =
      (61 9 1 6 7 #x7f #x0 #x0 #x7f)
      ;; >
      (62 9 1 11 7 #x60 #x30 #x18 #xc #x6 #x3 #x6 #xc #x18 #x30 #x60)
      ;; ?
      (63 9 1 11 7 #x3e #x63 #x63 #x3 #x6 #xc #x18 #x18 #x0 #x18 #x18)
      ;; @
      (64 15 1 11 13 #x3fc #xe06 #xcfb #x19bb #x1b1b #x1b1b #x1b33 #x1b76
        #xddc #xe03 #x3fe)
      ;; A
      (65 12 1 11 10 #x78 #x78 #x78 #xcc #xcc #xcc #x186 #x1fe #x186 #x303
        #x303)
      ;; B
      (66 12 1 11 10 #x3fc #x306 #x306 #x306 #x306 #x3fe #x303 #x303 #x303
        #x303 #x3fe)
      ;; C
      (67 13 1 11 11 #xfc #x386 #x303 #x603 #x600 #x600 #x600 #x603 #x303
        #x386 #xfc)
      ;; D
      (68 12 1 11 10 #x3f8 #x30e #x306 #x303 #x303 #x303 #x303 #x303 #x306
        #x30e #x3f8)
      ;; E
      (69 11 1 11 9 #x1ff #x180 #x180 #x180 #x180 #x1fe #x180 #x180 #x180
        #x180 #x1ff)
      ;; F
      (70 11 1 11 9 #x1ff #x180 #x180 #x180 #x180 #x1fe #x180 #x180 #x180
        #x180 #x180)
      ;; G
      (71 13 1 11 11 #xfc #x386 #x303 #x603 #x600 #x63f #x603 #x603 #x303
        #x387 #xff)
      ;; H
      (72 12 1 11 10 #x303 #x303 #x303 #x303 #x303 #x3ff #x303 #x303 #x303
        #x303 #x303)
      ;; I
      (73 4 1 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; J
      (74 10 1 11 8 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #xc3 #xc3 #x66 #x3c)
      ;; K
      (75 11 1 11 9 #x183 #x186 #x18c #x198 #x1b8 #x1ec #x1cc #x186 #x186
        #x183 #x183)
      ;; L
      (76 10 1 11 8 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xff)
      ;; M
      (77 15 1 11 13 #x1c07 #x1c07 #x1e0f #x1e0f #x1b1b #x1b1b #x19b3 #x19b3
        #x19b3 #x18e3 #x18e3)
      ;; N
      (78 12 1 11 10 #x383 #x383 #x3c3 #x363 #x363 #x333 #x31b #x31b #x30f
        #x307 #x307)
      ;; O
      (79 14 1 11 12 #x1f8 #x70e #x606 #xc03 #xc03 #xc03 #xc03 #xc03 #x606
        #x70e #x1f8)
      ;; P
      (80 11 1 11 9 #x1fc #x186 #x183 #x183 #x183 #x186 #x1fc #x180 #x180
        #x180 #x180)
      ;; Q
      (81 14 1 11 12 #x1f8 #x70e #x606 #xc03 #xc03 #xc03 #xc03 #xc03 #x636
        #x71e #x1fc #x6 #x3)
      ;; R
      (82 12 1 11 10 #x3fc #x306 #x303 #x303 #x306 #x3fc #x306 #x306 #x303
        #x303 #x303)
      ;; S
      (83 12 1 11 10 #xfc #x186 #x303 #x303 #x1e0 #x3c #x6 #x303 #x303 #x186
        #xfc)
      ;; T
      (84 12 1 11 10 #x3ff #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30)
      ;; U
      (85 12 1 11 10 #x303 #x303 #x303 #x303 #x303 #x303 #x303 #x303 #x303
        #x186 #xfc)
      ;; V
      (86 12 1 11 10 #x303 #x303 #x186 #x186 #x186 #xcc #xcc #xcc #x78 #x78
        #x30)
      ;; W
      (87 17 1 11 15 #x61c3 #x61c3 #x61c3 #x3366 #x3366 #x3366 #x1e3c #x1e3c
        #x1e3c #xc18 #xc18)
      ;; X
      (88 12 1 11 10 #x303 #x186 #xcc #xcc #x78 #x30 #x78 #xcc #xcc #x186
        #x303)
      ;; Y
      (89 12 1 11 10 #x303 #x303 #x186 #xcc #xcc #x78 #x30 #x30 #x30 #x30 #x30)
      ;; Z
      (90 11 1 11 9 #x1ff #x3 #x6 #xc #x18 #x18 #x30 #x60 #xc0 #x180 #x1ff)
      ;; [
      (91 8 1 12 6 #x3f #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30
        #x30 #x3f)
      ;; \
      (92 9 1 11 7 #x60 #x60 #x30 #x30 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ]
      (93 8 1 12 6 #x3f #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3f)
      ;; ^
      (94 10 1 12 8 #x18 #x3c #x66 #xc3)
      ;; _
      (95 12 0 0 10 #x3ff #x3ff)
      ;; `
      (96 10 2 12 4 #xe #xe #xc #x7)
      ;; a
      (97 11 1 8 9 #x7c #xc6 #x6 #xfe #x186 #x186 #x18e #xff)
      ;; b
      (98 10 1 11 8 #xc0 #xc0 #xc0 #xfc #xe6 #xc3 #xc3 #xc3 #xc3 #xe6 #xfc)
      ;; c
      (99 10 1 8 8 #x3e #x63 #xc3 #xc0 #xc0 #xc3 #x63 #x3e)
      ;; d
      (100 10 1 11 8 #x3 #x3 #x3 #x3f #x67 #xc3 #xc3 #xc3 #xc3 #x67 #x3f)
      ;; e
      (101 10 1 8 8 #x3c #x66 #xc3 #xff #xc0 #xc0 #x63 #x3e)
      ;; f
      (102 7 1 11 6 #xf #x18 #x18 #x3e #x18 #x18 #x18 #x18 #x18 #x18 #x18)
      ;; g
      (103 10 1 8 8 #x3f #x67 #xc3 #xc3 #xc3 #xc3 #x67 #x3f #xc3 #xc3 #x7e)
      ;; h
      (104 10 1 11 8 #xc0 #xc0 #xc0 #xfe #xe3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; i
      (105 4 1 11 2 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; j
      (106 6 1 11 4 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #xe)
      ;; k
      (107 9 1 11 7 #x60 #x60 #x60 #x63 #x66 #x6c #x7c #x76 #x66 #x63 #x63)
      ;; l
      (108 4 1 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; m
      (109 14 1 8 12 #xffe #xe63 #xc63 #xc63 #xc63 #xc63 #xc63 #xc63)
      ;; n
      (110 10 1 8 8 #xfe #xe3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; o
      (111 11 1 8 9 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; p
      (112 10 1 8 8 #xfc #xe6 #xc3 #xc3 #xc3 #xc3 #xe6 #xfc #xc0 #xc0 #xc0)
      ;; q
      (113 10 1 8 8 #x3f #x67 #xc3 #xc3 #xc3 #xc3 #x67 #x3f #x3 #x3 #x3)
      ;; r
      (114 7 1 8 5 #x1f #x1c #x18 #x18 #x18 #x18 #x18 #x18)
      ;; s
      (115 9 1 8 7 #x3e #x63 #x60 #x38 #xe #x63 #x63 #x3e)
      ;; t
      (116 7 1 10 5 #xc #xc #x1f #xc #xc #xc #xc #xc #xc #x7)
      ;; u
      (117 10 1 8 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc7 #x7f)
      ;; v
      (118 10 1 8 8 #xc3 #xc3 #x66 #x66 #x66 #x3c #x3c #x18)
      ;; w
      (119 14 1 8 12 #xc63 #xc63 #xcf3 #x6f6 #x79e #x79e #x30c #x30c)
      ;; x
      (120 10 1 8 8 #x66 #x66 #x3c #x18 #x3c #x66 #xc3 #xc3)
      ;; y
      (121 10 1 8 8 #xc3 #xc3 #x63 #x66 #x66 #x3c #x3c #x18 #x18 #xd8 #x70)
      ;; z
      (122 9 1 8 7 #x7f #x3 #x6 #xc #x18 #x30 #x60 #x7f)
      ;; {
      (123 8 1 12 6 #x7 #xc #xc #xc #xc #xc #xc #x38 #xc #xc #xc #xc #xc #xc
        #x7)
      ;; |
      (124 4 1 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; }
      (125 8 1 12 6 #x38 #xc #xc #xc #xc #xc #xc #x7 #xc #xc #xc #xc #xc #xc
        #x38)
      ;; ~
      (126 12 1 7 10 #xe3 #x1b6 #x31c)
      ;; ¬
      (172 10 1 6 8 #xff #x3 #x3)
      ;; °
      (176 6 1 11 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 10 1 9 8 #x18 #x18 #x18 #xff #x18 #x18 #x18 #x0 #xff)
      ;; µ
      (181 10 1 8 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc7 #x7f #xc0 #xc0 #xc0)
      ;; ·
      (183 10 3 7 5 #xe #x1f #x1f #xe)
      ;; À
      (192 12 1 12 10 #x60 #x30 #x0 #x78 #x78 #x78 #xcc #x186 #x1fe #x186
        #x303 #x303)
      ;; Á
      (193 12 1 12 10 #x30 #x60 #x0 #x78 #x78 #x78 #xcc #x186 #x1fe #x186
        #x303 #x303)
      ;; Â
      (194 12 1 12 10 #x30 #x78 #x0 #x78 #x78 #x78 #xcc #x186 #x1fe #x186
        #x303 #x303)
      ;; Ã
      (195 12 1 12 10 #x78 #xf0 #x0 #x78 #x78 #x78 #xcc #x186 #x1fe #x186
        #x303 #x303)
      ;; Ä
      (196 12 1 12 10 #x78 #x0 #x78 #x78 #x78 #xcc #xcc #x186 #x1fe #x186
        #x303 #x303)
      ;; Å
      (197 12 1 12 10 #x30 #x78 #x30 #x78 #x78 #x78 #xcc #x186 #x1fe #x186
        #x303 #x303)
      ;; Ç
      (199 13 1 11 11 #xfc #x386 #x303 #x603 #x600 #x600 #x600 #x603 #x303
        #x386 #xfc #x60 #xc0)
      ;; È
      (200 11 1 12 9 #x60 #x30 #x0 #x1ff #x180 #x180 #x1fe #x180 #x180 #x180
        #x180 #x1ff)
      ;; É
      (201 11 1 12 9 #x30 #x60 #x0 #x1ff #x180 #x180 #x1fe #x180 #x180 #x180
        #x180 #x1ff)
      ;; Ê
      (202 11 1 12 9 #x30 #x78 #x0 #x1ff #x180 #x180 #x1fe #x180 #x180 #x180
        #x180 #x1ff)
      ;; Ë
      (203 11 1 12 9 #x78 #x0 #x1ff #x180 #x180 #x180 #x1fe #x180 #x180 #x180
        #x180 #x1ff)
      ;; Ì
      (204 4 0 12 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; Í
      (205 4 0 12 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; Î
      (206 4 0 12 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; Ï
      (207 4 0 12 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; Ñ
      (209 12 1 12 10 #x78 #xf0 #x0 #x383 #x3c3 #x363 #x333 #x31b #x31b #x30f
        #x307 #x307)
      ;; Ò
      (210 14 1 12 12 #xc0 #x60 #x0 #x1f8 #x70e #x606 #xc03 #xc03 #xc03 #x606
        #x70e #x1f8)
      ;; Ó
      (211 14 1 12 12 #x60 #xc0 #x0 #x1f8 #x70e #x606 #xc03 #xc03 #xc03 #x606
        #x70e #x1f8)
      ;; Ô
      (212 14 1 12 12 #x60 #xf0 #x0 #x1f8 #x70e #x606 #xc03 #xc03 #xc03 #x606
        #x70e #x1f8)
      ;; Õ
      (213 14 1 12 12 #xf0 #x1e0 #x0 #x1f8 #x70e #x606 #xc03 #xc03 #xc03 #x606
        #x70e #x1f8)
      ;; Ö
      (214 14 1 12 12 #xf0 #x0 #x1f8 #x70e #x606 #xc03 #xc03 #xc03 #xc03 #x606
        #x70e #x1f8)
      ;; ×
      (215 10 1 8 8 #x66 #x66 #x3c #x18 #x3c #x66 #xc3 #xc3)
      ;; Ù
      (217 12 1 12 10 #x60 #x30 #x0 #x303 #x303 #x303 #x303 #x303 #x303 #x303
        #x186 #xfc)
      ;; Ú
      (218 12 1 12 10 #x30 #x60 #x0 #x303 #x303 #x303 #x303 #x303 #x303 #x303
        #x186 #xfc)
      ;; Û
      (219 12 1 12 10 #x30 #x78 #x0 #x303 #x303 #x303 #x303 #x303 #x303 #x303
        #x186 #xfc)
      ;; Ü
      (220 12 1 12 10 #x78 #x0 #x303 #x303 #x303 #x303 #x303 #x303 #x303 #x303
        #x186 #xfc)
      ;; Ý
      (221 12 1 12 10 #x30 #x60 #x0 #x303 #x186 #xcc #x78 #x30 #x30 #x30 #x30
        #x30)
      ;; à
      (224 11 1 11 9 #x60 #x30 #x0 #x7c #xc6 #x6 #xfe #x186 #x186 #x18e #xff)
      ;; á
      (225 11 1 11 9 #x30 #x60 #x0 #x7c #xc6 #x6 #xfe #x186 #x186 #x18e #xff)
      ;; â
      (226 11 1 11 9 #x30 #x78 #x0 #x7c #xc6 #x6 #xfe #x186 #x186 #x18e #xff)
      ;; ã
      (227 11 1 11 9 #x78 #xf0 #x0 #x7c #xc6 #x6 #xfe #x186 #x186 #x18e #xff)
      ;; ä
      (228 11 1 10 9 #x78 #x0 #x7c #xc6 #x6 #xfe #x186 #x186 #x18e #xff)
      ;; å
      (229 11 1 12 9 #x30 #x78 #x30 #x0 #x7c #xc6 #x6 #xfe #x186 #x186 #x18e
        #xff)
      ;; ç
      (231 10 1 8 8 #x3e #x63 #xc3 #xc0 #xc0 #xc3 #x63 #x3e #x18 #x30)
      ;; è
      (232 10 1 11 8 #x30 #x18 #x0 #x3c #x66 #xc3 #xff #xc0 #xc0 #x63 #x3e)
      ;; é
      (233 10 1 11 8 #x18 #x30 #x0 #x3c #x66 #xc3 #xff #xc0 #xc0 #x63 #x3e)
      ;; ê
      (234 10 1 11 8 #x18 #x3c #x0 #x3c #x66 #xc3 #xff #xc0 #xc0 #x63 #x3e)
      ;; ë
      (235 10 1 10 8 #x3c #x0 #x3c #x66 #xc3 #xff #xc0 #xc0 #x63 #x3e)
      ;; ì
      (236 4 0 11 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; í
      (237 4 0 11 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; î
      (238 4 0 11 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ï
      (239 4 0 10 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ñ
      (241 10 1 11 8 #x3c #x78 #x0 #xfe #xe3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; ò
      (242 11 1 11 9 #x60 #x30 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; ó
      (243 11 1 11 9 #x30 #x60 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; ô
      (244 11 1 11 9 #x30 #x78 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; õ
      (245 11 1 11 9 #x78 #xf0 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; ö
      (246 11 1 10 9 #x78 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; ù
      (249 10 1 11 8 #x30 #x18 #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc7 #x7f)
      ;; ú
      (250 10 1 11 8 #x18 #x30 #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc7 #x7f)
      ;; û
      (251 10 1 11 8 #x18 #x3c #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc7 #x7f)
      ;; ü
      (252 10 1 10 8 #x3c #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc7 #x7f)
      ;; ý
      (253 10 1 11 8 #x18 #x30 #x0 #xc3 #xc3 #x63 #x66 #x66 #x3c #x3c #x18
        #x18 #xd8 #x70)
      ;; ÿ
      (255 10 1 10 8 #x3c #x0 #xc3 #xc3 #x63 #x66 #x66 #x3c #x3c #x18 #x18
        #xd8 #x70)
      ;; α
      (945 10 1 9 9 #x6 #xe6 #x1bc #x198 #x198 #x1bc #xe7)
      ;; β
      (946 10 2 11 7 #x1e #x33 #x33 #x63 #x7e #x63 #x63 #x63 #x7e #x60 #x60
        #x60)
      ;; γ
      (947 10 1 9 8 #x73 #xdb #xe #xc #x1c #x1c #x3c #x3c #x3c #x18)
      ;; δ
      (948 10 1 12 8 #x3c #x66 #x63 #x60 #x30 #x1c #x36 #x63 #xc3 #xc3 #x7e)
      ;; ε
      (949 10 2 8 6 #xf #x18 #x30 #x3f #x30 #x18 #xf)
      ;; λ
      (955 10 1 11 8 #xe0 #x30 #x30 #x18 #x38 #x3c #x6c #x66 #xc6 #xc3)
      ;; π
      (960 10 1 8 8 #xff #x66 #x66 #x66 #x66 #x66 #x66)
      ;; –
      (8211 10 0 6 9 #x1ff)
      ;; —
      (8212 15 0 6 15 #x7fff)
      ;; ‘
      (8216 4 1 11 2 #x3 #x3 #x3 #x3)
      ;; ’
      (8217 4 1 11 2 #x3 #x3 #x3 #x3)
      ;; “
      (8220 7 1 11 5 #x1b #x1b #x1b #x1b)
      ;; ”
      (8221 7 1 11 5 #x1b #x1b #x1b #x1b)
      ;; …
      (8230 12 1 2 10 #x333 #x333)
      ;; ←
      (8592 10 1 8 8 #x30 #x60 #xff #x60 #x30)
      ;; ↑
      (8593 10 2 11 6 #xc #x1e #x3f #xc #xc #xc #xc #xc #xc)
      ;; →
      (8594 10 1 8 8 #xc #x6 #xff #x6 #xc)
      ;; ↓
      (8595 10 2 11 6 #xc #xc #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↔
      (8596 10 1 10 7 #xc #x6 #x7f #x6 #xc #x18 #x30 #x7f #x30 #x18)
      ;; ↳
      (8627 10 1 11 8 #xc0 #xc0 #xc0 #xcc #xc6 #xff #x6 #xc)
      ;; ∀
      (8704 10 1 12 8 #xc3 #xc3 #xc3 #x7e #x66 #x66 #x3c #x3c #x3c #x18 #x18)
      ;; ∂
      (8706 10 2 12 7 #x1c #x36 #x3 #x3 #x3 #x1f #x33 #x63 #x63 #x36 #x1c)
      ;; ∃
      (8707 10 1 12 8 #xff #x3 #x3 #x3 #x3 #x7f #x3 #x3 #x3 #x3 #xff)
      ;; −
      (8722 10 1 5 8 #xff)
      ;; ∞
      (8734 10 1 8 8 #x7e #xdb #xdb #xdb #xdb #x7e)
      ;; ∧
      (8743 10 1 7 8 #x18 #x3c #x66 #xc3)
      ;; ∨
      (8744 10 1 7 8 #xc3 #x66 #x3c #x18)
      ;; ∩
      (8745 10 2 9 7 #x3e #x63 #x63 #x63 #x63 #x63 #x63)
      ;; ∪
      (8746 10 2 9 7 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ∫
      (8747 9 1 11 8 #xe #x1b #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #xd8
        #x70)
      ;; ≠
      (8800 10 1 10 8 #x6 #x6 #xc #xff #x18 #x30 #xff #x60 #xc0)
      ;; ≡
      (8801 10 1 8 8 #xff #x0 #xff #x0 #xff)
      ;; ≤
      (8804 10 1 9 8 #x7 #x1c #x70 #xc0 #x70 #x1c #x7 #xff)
      ;; ≥
      (8805 10 1 9 8 #xe0 #x38 #xe #x3 #xe #x38 #xe0 #xff)
      ;; ⊂
      (8834 10 1 8 8 #x7f #xc0 #xc0 #xc0 #xc0 #x7f)
      ;; ⊃
      (8835 10 1 8 8 #xfe #x3 #x3 #x3 #x3 #xfe)
      ;; ⊕
      (8853 10 1 9 8 #x3c #x7e #xdb #xff #xdb #x7e #x3c)
      ;; ⊗
      (8855 10 1 9 8 #x3c #x66 #xff #xdb #xff #x66 #x3c)
      ;; ⋅
      (8901 10 3 7 5 #xe #x1f #x1f #xe)
      ;; ▶
      (9654 8 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 10 1 11 8 #x18 #x18 #x3c #x66 #xc3 #x66 #x3c #x18 #x18)
      ;; ◊
      (9674 10 1 11 8 #x18 #x18 #x3c #x66 #xc3 #x66 #x3c #x18 #x18)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 15 1 12 13 #x40 #xa0 #xa0 #x110 #x150 #x248 #x248 #x444 #x444
        #x802 #x842 #x1fff)
      ;; ✓
      (10003 10 0 9 9 #x3 #x3 #x6 #x6 #x18c #xcc #x78 #x78 #x30)
      ;; ❚
      (10074 6 1 11 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("Genera HL14 Italic" 15 12 3
      ;; the slug, which a character the face lacks draws
      (#f 8 1 11 6 #x3f #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x3f)
      ;; space
      (32 8)
      ;; !
      (33 5 2 11 3 #x1 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x0 #x4 #x4)
      ;; "
      (34 7 3 11 4 #x9 #x9 #x9 #x9)
      ;; #
      (35 13 2 11 11 #x12 #x12 #x24 #x1ff #x90 #x90 #x90 #x7fc #x240 #x480
        #x480)
      ;; $
      (36 11 1 12 10 #x4 #x3e #x49 #x49 #x48 #x50 #x38 #x14 #x12 #x224 #x124
        #xf8 #x20)
      ;; %
      (37 14 3 11 10 #x184 #x244 #x248 #x248 #x320 #x20 #x26 #x49 #x92 #x112
        #x10c)
      ;; &
      (38 12 1 11 10 #x38 #x44 #x44 #x44 #x50 #xb0 #x109 #x106 #x208 #x10c
        #xf2)
      ;; '
      (39 6 2 11 2 #x3 #x3 #x1 #x2)
      ;; (
      (40 7 1 11 6 #x1 #x2 #x4 #x4 #x10 #x10 #x10 #x10 #x20 #x20 #x10 #x10
        #x10 #x8)
      ;; )
      (41 7 0 11 6 #x4 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4 #x4 #x10 #x20)
      ;; *
      (42 10 2 12 8 #x4 #x49 #x2a #x1c #x2a #x92 #x10)
      ;; +
      (43 10 2 8 7 #x4 #x8 #x8 #x7f #x8 #x10 #x10)
      ;; ,
      (44 5 0 2 3 #x3 #x1 #x1 #x6)
      ;; -
      (45 9 2 6 6 #x3f)
      ;; .
      (46 4 1 2 1 #x1 #x1)
      ;; /
      (47 9 1 11 8 #x1 #x1 #x2 #x2 #x8 #x8 #x10 #x10 #x40 #x40 #x80 #x80)
      ;; 0
      (48 11 1 11 10 #x3c #x42 #x81 #x81 #x102 #x102 #x102 #x102 #x204 #x108
        #xf0)
      ;; 1
      (49 11 5 11 4 #x1 #x3 #xd #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; 2
      (50 11 1 11 10 #x3c #x42 #x81 #x81 #x4 #x8 #x30 #x40 #x100 #x200 #x3fc)
      ;; 3
      (51 11 1 11 10 #x3c #x42 #x81 #x81 #x4 #x38 #x4 #x102 #x204 #x108 #xf0)
      ;; 4
      (52 11 2 11 8 #x3 #x5 #x9 #x9 #x22 #x42 #x82 #xff #x4 #x4 #x4)
      ;; 5
      (53 11 1 11 10 #x3f #x20 #x20 #x40 #xb8 #xc4 #x2 #x2 #x204 #x108 #xf0)
      ;; 6
      (54 11 1 11 9 #x1e #x21 #x40 #x40 #xbc #xc2 #x81 #x81 #x102 #x84 #x78)
      ;; 7
      (55 11 3 11 8 #xff #x1 #x2 #x4 #x10 #x10 #x20 #x20 #x80 #x80 #x80)
      ;; 8
      (56 11 1 11 9 #x1e #x21 #x21 #x21 #x3c #x42 #x81 #x81 #x102 #x84 #x78)
      ;; 9
      (57 11 2 11 9 #x3c #x42 #x81 #x81 #x102 #x86 #x7a #x2 #x4 #x108 #xf0)
      ;; :
      (58 4 1 8 3 #x1 #x2 #x0 #x0 #x0 #x0 #x4 #x4)
      ;; ;
      (59 5 0 8 4 #x1 #x1 #x0 #x0 #x0 #x0 #x6 #x2 #x2 #xc)
      ;; <
      (60 9 2 11 7 #x1 #x2 #x4 #x8 #x20 #x40 #x20 #x10 #x10 #x8 #x4)
      ;; =
      (61 9 1 6 7 #x3f #x0 #x0 #x7e)
      ;; >
      (62 9 1 11 7 #x10 #x8 #x4 #x2 #x2 #x1 #x2 #x4 #x10 #x20 #x40)
      ;; ?
      (63 9 3 11 6 #x1e #x21 #x21 #x1 #x4 #x8 #x10 #x10 #x0 #x20 #x20)
      ;; @
      (64 15 2 11 13 #x1fc #x602 #x469 #x899 #x1212 #x1212 #x1222 #x1264
        #x1330 #x1804 #x7f8)
      ;; A
      (65 12 1 11 9 #xe #xa #xa #x11 #x22 #x22 #x41 #x7f #x82 #x101 #x101)
      ;; B
      (66 12 1 11 10 #xfe #x81 #x81 #x81 #x102 #x1fe #x101 #x101 #x202 #x202
        #x3fc)
      ;; C
      (67 13 2 11 11 #x7c #x182 #x101 #x201 #x400 #x400 #x400 #x402 #x404
        #x608 #x1f0)
      ;; D
      (68 12 1 11 11 #x1f8 #x106 #x102 #x101 #x202 #x202 #x202 #x202 #x408
        #x418 #x7e0)
      ;; E
      (69 11 1 11 10 #xff #x80 #x80 #x80 #x100 #x1fc #x100 #x100 #x200 #x200
        #x3fc)
      ;; F
      (70 11 1 11 10 #xff #x80 #x80 #x80 #x100 #x1fc #x100 #x100 #x200 #x200
        #x200)
      ;; G
      (71 13 2 11 11 #x7c #x182 #x101 #x201 #x400 #x43e #x402 #x402 #x404
        #x60c #x1f4)
      ;; H
      (72 12 1 11 11 #x101 #x101 #x101 #x101 #x202 #x3fe #x202 #x202 #x404
        #x404 #x404)
      ;; I
      (73 4 1 11 3 #x1 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; J
      (74 10 1 11 9 #x1 #x1 #x1 #x1 #x2 #x2 #x2 #x82 #x104 #x88 #x70)
      ;; K
      (75 11 1 11 10 #x81 #x82 #x84 #x88 #x130 #x148 #x188 #x104 #x208 #x204
        #x204)
      ;; L
      (76 10 1 11 7 #x10 #x10 #x10 #x10 #x20 #x20 #x20 #x20 #x40 #x40 #x7f)
      ;; M
      (77 15 1 11 14 #xc03 #xc03 #xa05 #xa05 #x1212 #x1212 #x1122 #x1122
        #x2244 #x2184 #x2184)
      ;; N
      (78 12 1 11 11 #x181 #x181 #x141 #x121 #x242 #x222 #x212 #x212 #x414
        #x40c #x40c)
      ;; O
      (79 14 2 11 12 #xf8 #x306 #x202 #x401 #x802 #x802 #x802 #x802 #x808
        #xc18 #x3e0)
      ;; P
      (80 11 1 11 10 #xfc #x82 #x81 #x81 #x102 #x104 #x1f8 #x100 #x200 #x200
        #x200)
      ;; Q
      (81 14 2 11 12 #xf8 #x306 #x202 #x401 #x802 #x802 #x802 #x802 #x848
        #xc38 #x3f0 #x8 #x8)
      ;; R
      (82 12 1 11 11 #x1fc #x102 #x101 #x101 #x204 #x3f8 #x204 #x204 #x404
        #x404 #x404)
      ;; S
      (83 12 1 11 11 #x7c #x82 #x101 #x101 #x1c0 #x38 #x4 #x202 #x404 #x208
        #x1f0)
      ;; T
      (84 12 3 11 9 #x1ff #x10 #x10 #x10 #x20 #x20 #x20 #x20 #x40 #x40 #x40)
      ;; U
      (85 12 1 11 11 #x101 #x101 #x101 #x101 #x202 #x202 #x202 #x202 #x404
        #x208 #x1f0)
      ;; V
      (86 12 3 11 9 #x101 #x101 #x82 #x82 #x104 #x88 #x88 #x88 #xa0 #xa0 #x40)
      ;; W
      (87 17 3 11 14 #x20c1 #x20c1 #x20c1 #x1122 #x2244 #x2244 #x1428 #x1428
        #x2850 #x1020 #x1020)
      ;; X
      (88 12 1 11 11 #x101 #x82 #x44 #x44 #x50 #x20 #x50 #x88 #x110 #x208
        #x404)
      ;; Y
      (89 12 3 11 9 #x101 #x101 #x82 #x44 #x88 #x50 #x20 #x20 #x40 #x40 #x40)
      ;; Z
      (90 11 1 11 10 #xff #x1 #x2 #x4 #x10 #x10 #x20 #x40 #x100 #x200 #x3fc)
      ;; [
      (91 8 0 12 9 #x1f #x20 #x20 #x20 #x20 #x40 #x40 #x40 #x40 #x80 #x80 #x80
        #x80 #x1f0)
      ;; \
      (92 9 3 11 4 #x8 #x8 #x4 #x4 #x4 #x4 #x2 #x2 #x2 #x2 #x1 #x1)
      ;; ]
      (93 8 0 12 9 #x1f #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x4 #x8 #x8 #x8 #x8 #x1f0)
      ;; ^
      (94 10 3 12 7 #x4 #xe #x32 #x41)
      ;; _
      (95 12 0 -1 10 #x3ff)
      ;; `
      (96 10 4 12 3 #x6 #x6 #x4 #x3)
      ;; a
      (97 11 1 8 8 #x1e #x21 #x1 #x3f #x41 #x82 #x86 #x7b)
      ;; b
      (98 10 1 11 8 #x20 #x20 #x20 #x3e #x62 #x41 #x41 #x41 #x82 #xc4 #xb8)
      ;; c
      (99 10 1 8 8 #x1e #x21 #x41 #x40 #x80 #x82 #x42 #x3c)
      ;; d
      (100 10 1 11 9 #x1 #x1 #x1 #x3d #x46 #x82 #x82 #x82 #x104 #x8c #x74)
      ;; e
      (101 10 1 8 8 #x1e #x22 #x41 #x7f #x40 #x80 #x42 #x3c)
      ;; f
      (102 7 2 11 6 #x7 #x8 #x8 #x3e #x10 #x10 #x10 #x10 #x20 #x20 #x20)
      ;; g
      (103 10 0 8 10 #x3d #x46 #x82 #x82 #x82 #x104 #x8c #x74 #x4 #x208 #x1f0)
      ;; h
      (104 10 1 11 8 #x20 #x20 #x20 #x3f #x61 #x41 #x41 #x41 #x82 #x82 #x82)
      ;; i
      (105 4 1 11 3 #x1 #x1 #x0 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; j
      (106 6 0 11 6 #x1 #x1 #x0 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x4 #x38)
      ;; k
      (107 9 1 11 8 #x20 #x20 #x20 #x23 #x44 #x48 #x58 #x64 #x84 #x84 #x84)
      ;; l
      (108 4 1 11 3 #x1 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; m
      (109 14 1 8 12 #x2ef #x731 #x421 #x421 #x421 #x842 #x842 #x842)
      ;; n
      (110 10 1 8 8 #x2f #x71 #x41 #x41 #x41 #x82 #x82 #x82)
      ;; o
      (111 11 1 8 9 #x3e #x41 #x81 #x81 #x101 #x102 #x84 #x78)
      ;; p
      (112 10 0 8 9 #x3e #x61 #x41 #x41 #x41 #x82 #xc4 #xb8 #x80 #x100 #x100)
      ;; q
      (113 10 1 8 9 #x3d #x46 #x82 #x82 #x82 #x104 #x8c #x74 #x4 #x8 #x8)
      ;; r
      (114 7 1 8 6 #x1f #x18 #x10 #x10 #x10 #x20 #x20 #x20)
      ;; s
      (115 9 1 8 7 #x1f #x21 #x20 #x18 #x6 #x42 #x42 #x3c)
      ;; t
      (116 7 2 10 5 #x4 #x4 #x1f #x8 #x8 #x8 #x8 #x10 #x10 #xc)
      ;; u
      (117 10 1 8 9 #x41 #x82 #x82 #x82 #x82 #x104 #x10c #xf4)
      ;; v
      (118 10 2 8 8 #x41 #x82 #x44 #x44 #x48 #x50 #x50 #x20)
      ;; w
      (119 14 2 8 12 #x421 #x842 #x8a2 #x8a4 #x924 #x618 #x410 #x410)
      ;; x
      (120 10 1 8 8 #x11 #x22 #x14 #x8 #x34 #x44 #x82 #x82)
      ;; y
      (121 10 0 8 10 #x41 #x82 #x42 #x44 #x44 #x48 #x50 #x20 #x20 #x240 #x180)
      ;; z
      (122 9 1 8 8 #x3f #x2 #x4 #x18 #x20 #x40 #x80 #xfc)
      ;; {
      (123 8 2 12 7 #x3 #x8 #x8 #x8 #x8 #x10 #x10 #x60 #x10 #x20 #x20 #x20
        #x20 #x40 #x30)
      ;; |
      (124 4 0 11 4 #x1 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x4 #x8)
      ;; }
      (125 8 0 12 7 #x6 #x2 #x2 #x2 #x2 #x4 #x4 #x3 #x4 #x8 #x8 #x8 #x8 #x10
        #x60)
      ;; ~
      (126 12 2 7 9 #x61 #x92 #x10c)
      ;; ¬
      (172 10 2 6 7 #x7f #x1 #x2)
      ;; °
      (176 6 1 11 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 10 1 9 8 #x4 #x8 #x8 #x7f #x8 #x10 #x10 #x0 #xfe)
      ;; µ
      (181 10 1 8 9 #x41 #x82 #x82 #x82 #x82 #x104 #x10c #xf4 #x100 #x100
        #x100)
      ;; ·
      (183 10 4 7 4 #x6 #xf #xf #xc)
      ;; À
      (192 12 1 12 9 #x20 #x10 #x0 #xe #xa #x11 #x22 #x41 #x7f #x82 #x101
        #x101)
      ;; Á
      (193 12 1 12 9 #x10 #x20 #x0 #xe #xa #x11 #x22 #x41 #x7f #x82 #x101
        #x101)
      ;; Â
      (194 12 1 12 9 #x20 #x50 #x0 #xe #xa #x11 #x22 #x41 #x7f #x82 #x101
        #x101)
      ;; Ã
      (195 12 1 12 9 #x28 #x50 #x0 #xe #xa #x11 #x22 #x41 #x7f #x82 #x101
        #x101)
      ;; Ä
      (196 12 1 12 9 #x50 #x0 #xe #xa #xa #x11 #x22 #x41 #x7f #x82 #x101 #x101)
      ;; Å
      (197 12 1 12 9 #x20 #x50 #x20 #xe #xa #x11 #x22 #x41 #x7f #x82 #x101
        #x101)
      ;; Ç
      (199 13 2 11 11 #x7c #x182 #x101 #x201 #x400 #x400 #x400 #x402 #x404
        #x608 #x1f0 #x20 #x40)
      ;; È
      (200 11 1 12 10 #x20 #x10 #x0 #xff #x80 #x100 #x1fc #x100 #x100 #x200
        #x200 #x3fc)
      ;; É
      (201 11 1 12 10 #x10 #x20 #x0 #xff #x80 #x100 #x1fc #x100 #x100 #x200
        #x200 #x3fc)
      ;; Ê
      (202 11 1 12 10 #x20 #x50 #x0 #xff #x80 #x100 #x1fc #x100 #x100 #x200
        #x200 #x3fc)
      ;; Ë
      (203 11 1 12 10 #x50 #x0 #xff #x80 #x80 #x100 #x1fc #x100 #x100 #x200
        #x200 #x3fc)
      ;; Ì
      (204 4 1 12 3 #x4 #x2 #x0 #x1 #x1 #x1 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; Í
      (205 4 1 12 3 #x2 #x4 #x0 #x1 #x1 #x1 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; Î
      (206 4 0 12 4 #x4 #xa #x0 #x1 #x1 #x1 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; Ï
      (207 4 0 12 4 #xa #x0 #x1 #x1 #x1 #x1 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; Ñ
      (209 12 1 12 11 #x50 #xa0 #x0 #x181 #x141 #x121 #x242 #x222 #x212 #x414
        #x40c #x40c)
      ;; Ò
      (210 14 2 12 12 #x40 #x20 #x0 #xf8 #x306 #x202 #x401 #x802 #x802 #x808
        #xc18 #x3e0)
      ;; Ó
      (211 14 2 12 12 #x20 #x40 #x0 #xf8 #x306 #x202 #x401 #x802 #x802 #x808
        #xc18 #x3e0)
      ;; Ô
      (212 14 2 12 12 #x40 #xa0 #x0 #xf8 #x306 #x202 #x401 #x802 #x802 #x808
        #xc18 #x3e0)
      ;; Õ
      (213 14 2 12 12 #x50 #xa0 #x0 #xf8 #x306 #x202 #x401 #x802 #x802 #x808
        #xc18 #x3e0)
      ;; Ö
      (214 14 2 12 12 #xa0 #x0 #xf8 #x306 #x202 #x401 #x802 #x802 #x802 #x808
        #xc18 #x3e0)
      ;; ×
      (215 10 1 8 8 #x11 #x22 #x14 #x8 #x34 #x44 #x82 #x82)
      ;; Ù
      (217 12 1 12 11 #x40 #x20 #x0 #x101 #x101 #x101 #x202 #x202 #x202 #x404
        #x208 #x1f0)
      ;; Ú
      (218 12 1 12 11 #x20 #x40 #x0 #x101 #x101 #x101 #x202 #x202 #x202 #x404
        #x208 #x1f0)
      ;; Û
      (219 12 1 12 11 #x40 #xa0 #x0 #x101 #x101 #x101 #x202 #x202 #x202 #x404
        #x208 #x1f0)
      ;; Ü
      (220 12 1 12 11 #xa0 #x0 #x101 #x101 #x101 #x101 #x202 #x202 #x202 #x404
        #x208 #x1f0)
      ;; Ý
      (221 12 3 12 9 #x10 #x20 #x0 #x101 #x82 #x44 #x88 #x50 #x20 #x40 #x40
        #x40)
      ;; à
      (224 11 1 11 8 #x10 #x8 #x0 #x1e #x21 #x1 #x3f #x41 #x82 #x86 #x7b)
      ;; á
      (225 11 1 11 8 #x8 #x10 #x0 #x1e #x21 #x1 #x3f #x41 #x82 #x86 #x7b)
      ;; â
      (226 11 1 11 8 #x10 #x28 #x0 #x1e #x21 #x1 #x3f #x41 #x82 #x86 #x7b)
      ;; ã
      (227 11 1 11 8 #x14 #x28 #x0 #x1e #x21 #x1 #x3f #x41 #x82 #x86 #x7b)
      ;; ä
      (228 11 1 10 8 #x28 #x0 #x1e #x21 #x1 #x3f #x41 #x82 #x86 #x7b)
      ;; å
      (229 11 1 12 8 #x10 #x28 #x10 #x0 #x1e #x21 #x1 #x3f #x41 #x82 #x86 #x7b)
      ;; ç
      (231 10 1 8 8 #x1e #x21 #x41 #x40 #x80 #x82 #x42 #x3c #x8 #x10)
      ;; è
      (232 10 1 11 8 #x10 #x8 #x0 #x1e #x22 #x41 #x7f #x40 #x80 #x42 #x3c)
      ;; é
      (233 10 1 11 8 #x8 #x10 #x0 #x1e #x22 #x41 #x7f #x40 #x80 #x42 #x3c)
      ;; ê
      (234 10 1 11 8 #x10 #x28 #x0 #x1e #x22 #x41 #x7f #x40 #x80 #x42 #x3c)
      ;; ë
      (235 10 1 10 8 #x28 #x0 #x1e #x22 #x41 #x7f #x40 #x80 #x42 #x3c)
      ;; ì
      (236 4 1 11 3 #x4 #x2 #x0 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; í
      (237 4 1 11 3 #x2 #x4 #x0 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; î
      (238 4 0 11 4 #x4 #xa #x0 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; ï
      (239 4 0 10 4 #xa #x0 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; ñ
      (241 10 1 11 8 #x14 #x28 #x0 #x2f #x71 #x41 #x41 #x41 #x82 #x82 #x82)
      ;; ò
      (242 11 1 11 9 #x20 #x10 #x0 #x3e #x41 #x81 #x81 #x101 #x102 #x84 #x78)
      ;; ó
      (243 11 1 11 9 #x10 #x20 #x0 #x3e #x41 #x81 #x81 #x101 #x102 #x84 #x78)
      ;; ô
      (244 11 1 11 9 #x20 #x50 #x0 #x3e #x41 #x81 #x81 #x101 #x102 #x84 #x78)
      ;; õ
      (245 11 1 11 9 #x28 #x50 #x0 #x3e #x41 #x81 #x81 #x101 #x102 #x84 #x78)
      ;; ö
      (246 11 1 10 9 #x50 #x0 #x3e #x41 #x81 #x81 #x101 #x102 #x84 #x78)
      ;; ù
      (249 10 1 11 9 #x20 #x10 #x0 #x41 #x82 #x82 #x82 #x82 #x104 #x10c #xf4)
      ;; ú
      (250 10 1 11 9 #x10 #x20 #x0 #x41 #x82 #x82 #x82 #x82 #x104 #x10c #xf4)
      ;; û
      (251 10 1 11 9 #x20 #x50 #x0 #x41 #x82 #x82 #x82 #x82 #x104 #x10c #xf4)
      ;; ü
      (252 10 1 10 9 #x50 #x0 #x41 #x82 #x82 #x82 #x82 #x104 #x10c #xf4)
      ;; ý
      (253 10 0 11 10 #x10 #x20 #x0 #x41 #x82 #x42 #x44 #x44 #x48 #x50 #x20
        #x20 #x240 #x180)
      ;; ÿ
      (255 10 0 10 10 #x50 #x0 #x41 #x82 #x42 #x44 #x44 #x48 #x50 #x20 #x20
        #x240 #x180)
      ;; α
      (945 10 1 8 9 #x1 #x62 #x94 #x88 #x88 #x118 #xe6)
      ;; β
      (946 10 1 11 9 #xe #x11 #x11 #x42 #x7c #x42 #x42 #x84 #xf8 #x80 #x80
        #x100)
      ;; γ
      (947 10 2 9 8 #x31 #x92 #xc #x8 #x18 #x30 #x50 #x50 #x50 #x40)
      ;; δ
      (948 10 1 12 9 #x1c #x22 #x21 #x20 #x20 #x18 #x24 #x42 #x104 #x104 #xf8)
      ;; ε
      (949 10 2 8 6 #x7 #x8 #x10 #x1f #x20 #x10 #xe)
      ;; λ
      (955 10 1 11 7 #x18 #x4 #x4 #x4 #xc #xa #x12 #x22 #x42 #x41)
      ;; π
      (960 10 2 8 7 #x7f #x22 #x22 #x22 #x44 #x44 #x44)
      ;; –
      (8211 10 0 6 9 #x1ff)
      ;; —
      (8212 15 0 6 15 #x7fff)
      ;; ‘
      (8216 6 2 11 2 #x3 #x3 #x1 #x2)
      ;; ’
      (8217 6 2 11 2 #x3 #x3 #x1 #x2)
      ;; “
      (8220 7 3 11 4 #x9 #x9 #x9 #x9)
      ;; ”
      (8221 7 3 11 4 #x9 #x9 #x9 #x9)
      ;; …
      (8230 12 1 2 9 #x111 #x111)
      ;; ←
      (8592 10 2 8 7 #x10 #x20 #x7f #x20 #x20)
      ;; ↑
      (8593 10 4 11 5 #x4 #xe #x15 #x8 #x8 #x8 #x8 #x10 #x10)
      ;; →
      (8594 10 2 8 7 #x4 #x2 #x7f #x2 #x8)
      ;; ↓
      (8595 10 3 10 5 #x2 #x2 #x2 #x4 #x4 #x4 #x15 #x1e #x8)
      ;; ↔
      (8596 10 1 10 7 #x2 #x1 #x3f #x2 #x4 #x8 #x20 #x7e #x20 #x10)
      ;; ↳
      (8627 10 2 11 7 #x40 #x40 #x40 #x44 #x42 #x7f #x2 #x8)
      ;; ∀
      (8704 10 3 12 7 #x41 #x41 #x41 #x3e #x44 #x44 #x28 #x28 #x50 #x20 #x20)
      ;; ∂
      (8706 10 2 12 8 #xc #x12 #x1 #x1 #x2 #x1e #x22 #x42 #x84 #x48 #x30)
      ;; ∃
      (8707 10 1 12 9 #x7f #x1 #x1 #x1 #x2 #x7e #x2 #x2 #x4 #x4 #x1fc)
      ;; −
      (8722 10 2 5 7 #x7f)
      ;; ∞
      (8734 10 1 8 8 #x36 #x49 #x49 #x49 #x92 #x6c)
      ;; ∧
      (8743 10 1 7 7 #x4 #xa #x11 #x41)
      ;; ∨
      (8744 10 2 7 7 #x41 #x22 #x14 #x10)
      ;; ∩
      (8745 10 2 9 7 #xf #x21 #x21 #x21 #x21 #x42 #x42)
      ;; ∪
      (8746 10 2 9 8 #x21 #x42 #x42 #x42 #x42 #x84 #x78)
      ;; ∫
      (8747 10 2 12 9 #x6 #x9 #x8 #x8 #x10 #x10 #x10 #x10 #x20 #x120 #xc0)
      ;; ≠
      (8800 10 1 10 8 #x1 #x1 #x4 #x7f #x8 #x10 #xfe #x40 #x80)
      ;; ≡
      (8801 10 1 8 8 #x7f #x0 #x7f #x0 #xfe)
      ;; ≤
      (8804 10 1 9 9 #x3 #x18 #x60 #x80 #x60 #x30 #xc #x1fc)
      ;; ≥
      (8805 10 1 9 8 #x30 #x18 #x6 #x1 #x6 #x30 #xc0 #xfe)
      ;; ⊂
      (8834 10 1 8 8 #x3f #x40 #x40 #x40 #x80 #x7e)
      ;; ⊃
      (8835 10 1 8 8 #x7e #x1 #x1 #x1 #x2 #xfc)
      ;; ⊕
      (8853 10 2 9 7 #xe #x2a #x49 #x7f #x49 #x54 #x38)
      ;; ⊗
      (8855 10 2 9 7 #xe #x22 #x55 #x49 #x55 #x44 #x38)
      ;; ⋅
      (8901 10 4 7 4 #x6 #xf #xf #xc)
      ;; ▶
      (9654 8 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 10 2 11 7 #x4 #x4 #xa #x22 #x41 #x22 #x14 #x10 #x10)
      ;; ◊
      (9674 10 2 11 7 #x4 #x4 #xa #x22 #x41 #x22 #x14 #x10 #x10)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 15 1 12 13 #x40 #xa0 #xa0 #x110 #x150 #x248 #x248 #x444 #x444
        #x802 #x842 #x1fff)
      ;; ✓
      (10003 10 0 9 9 #x1 #x2 #x2 #x4 #x104 #x88 #x50 #x50 #x20)
      ;; ❚
      (10074 4 1 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera HL14 Bold Italic" 15 12 3
      ;; the slug, which a character the face lacks draws
      (#f 9 1 11 7 #x7f #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x7f)
      ;; space
      (32 9)
      ;; !
      (33 6 2 11 4 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xc #x0 #xc #xc)
      ;; "
      (34 8 2 11 6 #x1b #x1b #x1b #x36)
      ;; #
      (35 14 1 11 12 #x1b #x1b #x36 #x3ff #xd8 #xd8 #xd8 #xffc #x360 #x6c0
        #x6c0)
      ;; $
      (36 12 1 12 11 #x18 #x7e #xdb #xdb #x1b0 #xf0 #x78 #x3c #x6c #x66c #x36c
        #x1f8 #xc0)
      ;; %
      (37 15 2 11 11 #x1c6 #x366 #x36c #x6d8 #x3b0 #x30 #x37 #xdb #xdb #x19b
        #x18e)
      ;; &
      (38 13 1 11 11 #x78 #xcc #xcc #x198 #xf0 #x1f0 #x31b #x61c #x618 #x31c
        #x1f6)
      ;; '
      (39 5 2 11 3 #x3 #x3 #x3 #x6)
      ;; (
      (40 8 1 11 7 #x3 #x6 #xc #x18 #x30 #x30 #x30 #x60 #x60 #x60 #x30 #x60
        #x30 #x18)
      ;; )
      (41 8 0 11 7 #xc #x6 #x3 #x6 #x3 #x3 #x3 #x6 #x6 #x6 #xc #x18 #x30 #x60)
      ;; *
      (42 11 2 12 9 #x18 #xdb #x7e #x3c #xfc #x1b6 #x30)
      ;; +
      (43 11 2 8 8 #x18 #x18 #x18 #xff #x30 #x30 #x30)
      ;; ,
      (44 6 0 2 4 #x7 #x3 #x6 #xc)
      ;; -
      (45 10 2 6 7 #x7f)
      ;; .
      (46 5 1 2 2 #x3 #x3)
      ;; /
      (47 10 0 11 10 #x3 #x3 #x6 #xc #x18 #x18 #x30 #x60 #xc0 #xc0 #x180 #x300)
      ;; 0
      (48 12 1 11 11 #x7c #xc6 #x183 #x306 #x306 #x306 #x306 #x60c #x60c #x318
        #x1f0)
      ;; 1
      (49 12 5 11 5 #x3 #x7 #x1f #x6 #x6 #x6 #x6 #xc #xc #xc #xc)
      ;; 2
      (50 12 1 11 11 #x7c #xc6 #x183 #x306 #xc #x18 #x70 #x180 #x300 #x600
        #x7fc)
      ;; 3
      (51 12 1 11 11 #x7c #xc6 #x183 #x306 #xc #x78 #xc #x60c #x60c #x318
        #x1f0)
      ;; 4
      (52 12 1 11 10 #x7 #xf #x1b #x36 #x66 #xc6 #x186 #x3fe #xc #xc #xc)
      ;; 5
      (53 12 1 11 11 #x7f #x60 #x60 #x180 #x1f8 #x1cc #x6 #xc #x60c #x318
        #x1f0)
      ;; 6
      (54 12 1 11 10 #x3e #x63 #xc0 #x180 #x1fc #x1c6 #x183 #x306 #x306 #x18c
        #xf8)
      ;; 7
      (55 12 3 11 9 #x1ff #x3 #x6 #x18 #x30 #x30 #x60 #xc0 #x180 #x180 #x180)
      ;; 8
      (56 12 1 11 10 #x3e #x63 #x63 #xc6 #x7c #xc6 #x183 #x306 #x306 #x18c
        #xf8)
      ;; 9
      (57 12 2 11 10 #x7c #xc6 #x183 #x306 #x306 #x18e #xfe #xc #xc #x318
        #x1f0)
      ;; :
      (58 5 1 8 3 #x3 #x3 #x0 #x0 #x0 #x0 #x6 #x6)
      ;; ;
      (59 6 0 8 5 #x3 #x3 #x0 #x0 #x0 #x0 #xe #x6 #xc #x18)
      ;; <
      (60 10 2 11 8 #x3 #x6 #xc #x30 #x60 #xc0 #x60 #x60 #x30 #x18 #xc)
      ;; =
      (61 10 1 6 8 #x7f #x0 #x0 #xfe)
      ;; >
      (62 10 1 11 8 #x30 #x18 #xc #xc #x6 #x3 #x6 #x18 #x30 #x60 #xc0)
      ;; ?
      (63 10 3 11 7 #x3e #x63 #x63 #x6 #xc #x18 #x30 #x60 #x0 #x60 #x60)
      ;; @
      (64 16 1 11 15 #x3fc #xe06 #xcfb #x3376 #x3636 #x3636 #x3666 #x6dd8
        #x3770 #x380c #xff8)
      ;; A
      (65 13 1 11 10 #x1e #x1e #x1e #x66 #x66 #x66 #xc3 #x1fe #x186 #x303
        #x303)
      ;; B
      (66 13 1 11 11 #x1fe #x183 #x183 #x306 #x306 #x3fe #x303 #x606 #x606
        #x606 #x7fc)
      ;; C
      (67 14 1 11 13 #xfc #x386 #x303 #xc06 #xc00 #xc00 #xc00 #x180c #xc0c
        #xe18 #x3f0)
      ;; D
      (68 13 1 11 11 #x1fc #x187 #x183 #x303 #x303 #x303 #x303 #x606 #x60c
        #x61c #x7f0)
      ;; E
      (69 12 1 11 11 #x1ff #x180 #x180 #x300 #x300 #x3fc #x300 #x600 #x600
        #x600 #x7fc)
      ;; F
      (70 12 1 11 11 #x1ff #x180 #x180 #x300 #x300 #x3fc #x300 #x600 #x600
        #x600 #x600)
      ;; G
      (71 14 1 11 13 #xfc #x386 #x303 #xc06 #xc00 #xc7e #xc06 #x180c #xc0c
        #xe1c #x3fc)
      ;; H
      (72 13 1 11 12 #x303 #x303 #x303 #x606 #x606 #x7fe #x606 #xc0c #xc0c
        #xc0c #xc0c)
      ;; I
      (73 5 1 11 4 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xc #xc #xc #xc)
      ;; J
      (74 11 1 11 10 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #x30c #x30c #x198 #xf0)
      ;; K
      (75 12 1 11 11 #x183 #x186 #x18c #x330 #x370 #x3d8 #x398 #x618 #x618
        #x60c #x60c)
      ;; L
      (76 11 1 11 8 #x30 #x30 #x30 #x60 #x60 #x60 #x60 #xc0 #xc0 #xc0 #xff)
      ;; M
      (77 16 1 11 15 #x1c07 #x1c07 #x1e0f #x3c1e #x3636 #x3636 #x3366 #x66cc
        #x66cc #x638c #x638c)
      ;; N
      (78 13 1 11 12 #x383 #x383 #x3c3 #x6c6 #x6c6 #x666 #x636 #xc6c #xc3c
        #xc1c #xc1c)
      ;; O
      (79 15 1 11 13 #xfc #x387 #x303 #xc03 #xc03 #xc03 #xc03 #x1806 #xc0c
        #xe1c #x3f0)
      ;; P
      (80 12 1 11 11 #x1fc #x186 #x183 #x306 #x306 #x30c #x3f8 #x600 #x600
        #x600 #x600)
      ;; Q
      (81 15 1 11 13 #xfc #x387 #x303 #xc03 #xc03 #xc03 #xc03 #x1806 #xc6c
        #xe3c #x3f8 #x18 #xc)
      ;; R
      (82 13 1 11 12 #x3fc #x306 #x303 #x606 #x60c #x7f8 #x60c #xc18 #xc0c
        #xc0c #xc0c)
      ;; S
      (83 13 1 11 12 #xfc #x186 #x303 #x606 #x3c0 #x78 #xc #xc0c #xc0c #x618
        #x3f0)
      ;; T
      (84 13 3 11 10 #x3ff #x30 #x30 #x60 #x60 #x60 #x60 #xc0 #xc0 #xc0 #xc0)
      ;; U
      (85 13 1 11 12 #x303 #x303 #x303 #x606 #x606 #x606 #x606 #xc0c #xc0c
        #x618 #x3f0)
      ;; V
      (86 13 3 11 10 #x303 #x303 #x186 #x30c #x30c #x198 #x198 #x330 #x1e0
        #x1e0 #xc0)
      ;; W
      (87 18 3 11 15 #x61c3 #x61c3 #x61c3 #x66cc #x66cc #x66cc #x3c78 #x78f0
        #x78f0 #x3060 #x3060)
      ;; X
      (88 13 1 11 12 #x303 #x186 #xcc #x198 #xf0 #x60 #xf0 #x330 #x330 #x618
        #xc0c)
      ;; Y
      (89 13 3 11 10 #x303 #x303 #x186 #x198 #x198 #xf0 #x60 #xc0 #xc0 #xc0
        #xc0)
      ;; Z
      (90 12 1 11 11 #x1ff #x3 #x6 #x18 #x30 #x30 #x60 #x180 #x300 #x600 #x7fc)
      ;; [
      (91 9 0 12 9 #x3f #x30 #x30 #x30 #x60 #x60 #x60 #x60 #xc0 #xc0 #xc0 #xc0
        #x180 #x1f8)
      ;; \
      (92 10 3 11 5 #x18 #x18 #xc #x18 #xc #xc #x6 #xc #x6 #x6 #x3 #x6)
      ;; ]
      (93 9 0 12 9 #x3f #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xc #xc #xc #xc #x18 #x1f8)
      ;; ^
      (94 11 2 11 8 #xc #x3c #x66 #xc3)
      ;; _
      (95 13 0 0 11 #x7ff #x7ff)
      ;; `
      (96 11 4 12 4 #xe #xe #xc #x7)
      ;; a
      (97 12 1 8 9 #x3e #x63 #x3 #x7f #x186 #x186 #x18e #xff)
      ;; b
      (98 11 1 11 9 #x60 #x60 #x60 #xfc #xe6 #xc3 #xc3 #x186 #x186 #x1cc #x1f8)
      ;; c
      (99 11 1 8 9 #x3e #x63 #xc3 #xc0 #x180 #x186 #xc6 #x7c)
      ;; d
      (100 11 1 11 10 #x3 #x3 #x3 #x7e #xce #x186 #x186 #x30c #x30c #x19c #xfc)
      ;; e
      (101 11 1 8 9 #x3c #x66 #xc3 #xff #x180 #x180 #xc6 #x7c)
      ;; f
      (102 8 2 11 7 #xf #x18 #x18 #x7c #x30 #x30 #x30 #x60 #x60 #x60 #x60)
      ;; g
      (103 11 0 8 10 #x3f #x67 #xc3 #xc3 #x186 #x186 #xce #x7e #x30c #x30c
        #x1f8)
      ;; h
      (104 11 1 11 9 #x60 #x60 #x60 #xfe #xe3 #xc3 #xc3 #x186 #x186 #x186
        #x186)
      ;; i
      (105 5 1 11 4 #x3 #x3 #x0 #x6 #x6 #x6 #x6 #xc #xc #xc #xc)
      ;; j
      (106 7 0 11 7 #x3 #x3 #x0 #x6 #x6 #x6 #x6 #xc #xc #xc #xc #x18 #x70)
      ;; k
      (107 10 1 11 8 #x30 #x30 #x30 #x63 #x66 #x6c #x7c #xec #xcc #xc6 #xc6)
      ;; l
      (108 5 1 11 4 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xc #xc #xc #xc)
      ;; m
      (109 15 1 8 13 #xffe #xe63 #xc63 #xc63 #x18c6 #x18c6 #x18c6 #x18c6)
      ;; n
      (110 11 1 8 9 #xfe #xe3 #xc3 #xc3 #x186 #x186 #x186 #x186)
      ;; o
      (111 12 1 8 10 #x7c #xc6 #x183 #x183 #x306 #x306 #x18c #xf8)
      ;; p
      (112 11 0 8 10 #xfc #xe6 #xc3 #xc3 #x186 #x186 #x1cc #x1f8 #x300 #x300
        #x300)
      ;; q
      (113 11 1 8 9 #x3f #x67 #xc3 #xc3 #x186 #x186 #xce #x7e #xc #xc #xc)
      ;; r
      (114 8 1 8 6 #x1f #x1c #x18 #x18 #x30 #x30 #x30 #x30)
      ;; s
      (115 10 1 8 8 #x3e #x63 #x60 #x38 #x1c #xc6 #xc6 #x7c)
      ;; t
      (116 8 2 10 5 #x6 #x6 #x1f #xc #xc #xc #x18 #x18 #x18 #xe)
      ;; u
      (117 11 1 8 9 #xc3 #xc3 #xc3 #xc3 #x186 #x186 #x18e #xfe)
      ;; v
      (118 11 2 8 8 #xc3 #xc3 #x66 #x66 #xcc #x78 #x78 #x30)
      ;; w
      (119 15 2 8 12 #xc63 #xc63 #xcf3 #x6f6 #xf3c #xf3c #x618 #x618)
      ;; x
      (120 11 1 8 8 #x33 #x33 #x1e #xc #x3c #x66 #xc3 #xc3)
      ;; y
      (121 11 0 8 10 #xc3 #xc3 #x63 #x66 #xcc #x78 #x78 #x30 #x60 #x360 #x1c0)
      ;; z
      (122 10 1 8 8 #x7f #x3 #x6 #xc #x30 #x60 #xc0 #xfe)
      ;; {
      (123 9 2 12 7 #x7 #xc #xc #xc #x18 #x18 #x18 #x70 #x30 #x30 #x30 #x30
        #x60 #x60 #x38)
      ;; |
      (124 5 0 11 5 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xc #xc #xc #xc #x18 #x18)
      ;; }
      (125 9 0 12 8 #x1c #x6 #x6 #x6 #xc #xc #xc #x7 #x18 #x18 #x18 #x18 #x30
        #x30 #xe0)
      ;; ~
      (126 13 2 7 10 #xe3 #x1b6 #x31c)
      ;; ¬
      (172 11 2 6 8 #xff #x3 #x6)
      ;; °
      (176 6 1 11 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 11 1 9 9 #xc #x18 #x18 #xff #x18 #x30 #x30 #x0 #x1fe)
      ;; µ
      (181 11 1 8 9 #xc3 #xc3 #xc3 #xc3 #x186 #x186 #x18e #xfe #x180 #x180
        #x180)
      ;; ·
      (183 11 4 7 5 #xe #x1f #x1f #x1c)
      ;; À
      (192 13 1 12 10 #x60 #x30 #x0 #x1e #x1e #x1e #x66 #xc3 #x1fe #x186 #x303
        #x303)
      ;; Á
      (193 13 1 12 10 #x30 #x60 #x0 #x1e #x1e #x1e #x66 #xc3 #x1fe #x186 #x303
        #x303)
      ;; Â
      (194 13 1 12 10 #x30 #x78 #x0 #x1e #x1e #x1e #x66 #xc3 #x1fe #x186 #x303
        #x303)
      ;; Ã
      (195 13 1 12 10 #x78 #xf0 #x0 #x1e #x1e #x1e #x66 #xc3 #x1fe #x186 #x303
        #x303)
      ;; Ä
      (196 13 1 12 10 #x78 #x0 #x1e #x1e #x1e #x66 #x66 #xc3 #x1fe #x186 #x303
        #x303)
      ;; Å
      (197 13 1 12 10 #x30 #x78 #x30 #x1e #x1e #x1e #x66 #xc3 #x1fe #x186
        #x303 #x303)
      ;; Ç
      (199 14 1 11 13 #xfc #x386 #x303 #xc06 #xc00 #xc00 #xc00 #x180c #xc0c
        #xe18 #x3f0 #xc0 #x180)
      ;; È
      (200 12 1 12 11 #xc0 #x60 #x0 #x1ff #x180 #x300 #x3fc #x300 #x600 #x600
        #x600 #x7fc)
      ;; É
      (201 12 1 12 11 #x60 #xc0 #x0 #x1ff #x180 #x300 #x3fc #x300 #x600 #x600
        #x600 #x7fc)
      ;; Ê
      (202 12 1 12 11 #x60 #xf0 #x0 #x1ff #x180 #x300 #x3fc #x300 #x600 #x600
        #x600 #x7fc)
      ;; Ë
      (203 12 1 12 11 #xf0 #x0 #x1ff #x180 #x180 #x300 #x3fc #x300 #x600 #x600
        #x600 #x7fc)
      ;; Ì
      (204 5 1 12 4 #xc #x6 #x0 #x3 #x3 #x3 #x6 #x6 #xc #xc #xc #xc)
      ;; Í
      (205 5 1 12 4 #x6 #xc #x0 #x3 #x3 #x3 #x6 #x6 #xc #xc #xc #xc)
      ;; Î
      (206 5 1 12 4 #x6 #xf #x0 #x3 #x3 #x3 #x6 #x6 #xc #xc #xc #xc)
      ;; Ï
      (207 5 1 12 4 #xf #x0 #x3 #x3 #x3 #x6 #x6 #x6 #xc #xc #xc #xc)
      ;; Ñ
      (209 13 1 12 12 #xf0 #x1e0 #x0 #x383 #x3c3 #x6c6 #x666 #x636 #xc6c #xc3c
        #xc1c #xc1c)
      ;; Ò
      (210 15 1 12 13 #x180 #xc0 #x0 #xfc #x387 #x303 #xc03 #xc03 #x1806 #xc0c
        #xe1c #x3f0)
      ;; Ó
      (211 15 1 12 13 #xc0 #x180 #x0 #xfc #x387 #x303 #xc03 #xc03 #x1806 #xc0c
        #xe1c #x3f0)
      ;; Ô
      (212 15 1 12 13 #xc0 #x1e0 #x0 #xfc #x387 #x303 #xc03 #xc03 #x1806 #xc0c
        #xe1c #x3f0)
      ;; Õ
      (213 15 1 12 13 #x1e0 #x3c0 #x0 #xfc #x387 #x303 #xc03 #xc03 #x1806
        #xc0c #xe1c #x3f0)
      ;; Ö
      (214 15 1 12 13 #x1e0 #x0 #xfc #x387 #x303 #xc03 #xc03 #xc03 #x1806
        #xc0c #xe1c #x3f0)
      ;; ×
      (215 11 1 8 8 #x33 #x33 #x1e #xc #x3c #x66 #xc3 #xc3)
      ;; Ù
      (217 13 1 12 12 #xc0 #x60 #x0 #x303 #x303 #x303 #x606 #x606 #xc0c #xc0c
        #x618 #x3f0)
      ;; Ú
      (218 13 1 12 12 #x60 #xc0 #x0 #x303 #x303 #x303 #x606 #x606 #xc0c #xc0c
        #x618 #x3f0)
      ;; Û
      (219 13 1 12 12 #x60 #xf0 #x0 #x303 #x303 #x303 #x606 #x606 #xc0c #xc0c
        #x618 #x3f0)
      ;; Ü
      (220 13 1 12 12 #xf0 #x0 #x303 #x303 #x303 #x606 #x606 #x606 #xc0c #xc0c
        #x618 #x3f0)
      ;; Ý
      (221 13 3 12 10 #x30 #x60 #x0 #x303 #x186 #x198 #xf0 #x60 #xc0 #xc0 #xc0
        #xc0)
      ;; à
      (224 12 1 11 9 #x60 #x30 #x0 #x3e #x63 #x3 #x7f #x186 #x186 #x18e #xff)
      ;; á
      (225 12 1 11 9 #x30 #x60 #x0 #x3e #x63 #x3 #x7f #x186 #x186 #x18e #xff)
      ;; â
      (226 12 1 11 9 #x30 #x78 #x0 #x3e #x63 #x3 #x7f #x186 #x186 #x18e #xff)
      ;; ã
      (227 12 1 11 9 #x78 #xf0 #x0 #x3e #x63 #x3 #x7f #x186 #x186 #x18e #xff)
      ;; ä
      (228 12 1 10 9 #x78 #x0 #x3e #x63 #x3 #x7f #x186 #x186 #x18e #xff)
      ;; å
      (229 12 1 12 9 #x30 #x78 #x30 #x0 #x3e #x63 #x3 #x7f #x186 #x186 #x18e
        #xff)
      ;; ç
      (231 11 1 8 9 #x3e #x63 #xc3 #xc0 #x180 #x186 #xc6 #x7c #x30 #x60)
      ;; è
      (232 11 1 11 9 #x60 #x30 #x0 #x3c #x66 #xc3 #xff #x180 #x180 #xc6 #x7c)
      ;; é
      (233 11 1 11 9 #x30 #x60 #x0 #x3c #x66 #xc3 #xff #x180 #x180 #xc6 #x7c)
      ;; ê
      (234 11 1 11 9 #x30 #x78 #x0 #x3c #x66 #xc3 #xff #x180 #x180 #xc6 #x7c)
      ;; ë
      (235 11 1 10 9 #x78 #x0 #x3c #x66 #xc3 #xff #x180 #x180 #xc6 #x7c)
      ;; ì
      (236 5 0 11 4 #xc #x6 #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6 #x6)
      ;; í
      (237 5 0 11 4 #x6 #xc #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6 #x6)
      ;; î
      (238 5 0 11 4 #x6 #xf #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6 #x6)
      ;; ï
      (239 5 0 10 4 #xf #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6 #x6)
      ;; ñ
      (241 11 1 11 9 #x78 #xf0 #x0 #xfe #xe3 #xc3 #xc3 #x186 #x186 #x186 #x186)
      ;; ò
      (242 12 1 11 10 #x60 #x30 #x0 #x7c #xc6 #x183 #x183 #x306 #x306 #x18c
        #xf8)
      ;; ó
      (243 12 1 11 10 #x30 #x60 #x0 #x7c #xc6 #x183 #x183 #x306 #x306 #x18c
        #xf8)
      ;; ô
      (244 12 1 11 10 #x30 #x78 #x0 #x7c #xc6 #x183 #x183 #x306 #x306 #x18c
        #xf8)
      ;; õ
      (245 12 1 11 10 #x78 #xf0 #x0 #x7c #xc6 #x183 #x183 #x306 #x306 #x18c
        #xf8)
      ;; ö
      (246 12 1 10 10 #x78 #x0 #x7c #xc6 #x183 #x183 #x306 #x306 #x18c #xf8)
      ;; ù
      (249 11 1 11 9 #x60 #x30 #x0 #xc3 #xc3 #xc3 #xc3 #x186 #x186 #x18e #xfe)
      ;; ú
      (250 11 1 11 9 #x30 #x60 #x0 #xc3 #xc3 #xc3 #xc3 #x186 #x186 #x18e #xfe)
      ;; û
      (251 11 1 11 9 #x30 #x78 #x0 #xc3 #xc3 #xc3 #xc3 #x186 #x186 #x18e #xfe)
      ;; ü
      (252 11 1 10 9 #x78 #x0 #xc3 #xc3 #xc3 #xc3 #x186 #x186 #x18e #xfe)
      ;; ý
      (253 11 0 11 10 #x30 #x60 #x0 #xc3 #xc3 #x63 #x66 #xcc #x78 #x78 #x30
        #x60 #x360 #x1c0)
      ;; ÿ
      (255 11 0 10 10 #x78 #x0 #xc3 #xc3 #x63 #x66 #xcc #x78 #x78 #x30 #x60
        #x360 #x1c0)
      ;; α
      (945 11 1 9 10 #x3 #xe6 #x1bc #x198 #x198 #x378 #x1ce)
      ;; β
      (946 11 1 11 10 #x1e #x33 #x33 #xc6 #xfc #xc6 #xc6 #x18c #x1f8 #x180
        #x180 #x300)
      ;; γ
      (947 11 2 9 9 #x73 #x1b6 #x1c #x18 #x38 #x70 #xf0 #xf0 #xf0 #xc0)
      ;; δ
      (948 11 1 12 10 #x3c #x66 #x63 #x60 #x60 #x38 #x6c #xc6 #x30c #x30c
        #x1f8)
      ;; ε
      (949 11 2 8 7 #xf #x18 #x30 #x3f #x60 #x30 #x1e)
      ;; λ
      (955 11 1 11 8 #x38 #xc #xc #xc #x1c #x1e #x36 #x66 #xc6 #xc3)
      ;; π
      (960 11 2 8 8 #xff #x66 #x66 #x66 #xcc #xcc #xcc)
      ;; –
      (8211 11 0 6 10 #x3ff)
      ;; —
      (8212 16 0 6 16 #xffff)
      ;; ‘
      (8216 5 2 11 3 #x3 #x3 #x3 #x6)
      ;; ’
      (8217 5 2 11 3 #x3 #x3 #x3 #x6)
      ;; “
      (8220 8 2 11 6 #x1b #x1b #x1b #x36)
      ;; ”
      (8221 8 2 11 6 #x1b #x1b #x1b #x36)
      ;; …
      (8230 15 1 2 12 #xc63 #xc63)
      ;; ←
      (8592 11 2 8 8 #x30 #x60 #xff #x60 #x60)
      ;; ↑
      (8593 11 4 11 6 #xc #x1e #x3f #x18 #x18 #x18 #x18 #x30 #x30)
      ;; →
      (8594 11 2 8 8 #xc #x6 #xff #x6 #x18)
      ;; ↓
      (8595 11 3 11 6 #x6 #x6 #x6 #xc #xc #xc #x3f #x3c #x18)
      ;; ↔
      (8596 11 1 10 8 #x6 #x3 #x7f #x6 #xc #x18 #x60 #xfe #x60 #x30)
      ;; ↳
      (8627 11 2 11 8 #xc0 #xc0 #xc0 #xcc #xc6 #xff #x6 #x18)
      ;; ∀
      (8704 11 3 12 8 #xc3 #xc3 #xc3 #x7e #xcc #xcc #x78 #x78 #xf0 #x60 #x60)
      ;; ∂
      (8706 11 2 12 9 #x1c #x36 #x3 #x3 #x6 #x3e #x66 #xc6 #x18c #xd8 #x70)
      ;; ∃
      (8707 11 1 12 10 #xff #x3 #x3 #x3 #x6 #xfe #x6 #x6 #xc #xc #x3fc)
      ;; −
      (8722 11 2 5 8 #xff)
      ;; ∞
      (8734 11 1 8 9 #x7e #xdb #xdb #xdb #x1b6 #xfc)
      ;; ∧
      (8743 11 1 7 8 #xc #x1e #x33 #xc3)
      ;; ∨
      (8744 11 2 7 8 #xc3 #x66 #x3c #x30)
      ;; ∩
      (8745 11 2 9 8 #x1f #x63 #x63 #x63 #x63 #xc6 #xc6)
      ;; ∪
      (8746 11 2 9 9 #x63 #xc6 #xc6 #xc6 #xc6 #x18c #xf8)
      ;; ∫
      (8747 11 2 12 10 #xe #x1b #x18 #x18 #x30 #x30 #x30 #x30 #x60 #x360 #x1c0)
      ;; ≠
      (8800 11 1 10 9 #x3 #x3 #xc #xff #x18 #x30 #x1fe #xc0 #x180)
      ;; ≡
      (8801 11 1 8 9 #xff #x0 #xff #x0 #x1fe)
      ;; ≤
      (8804 11 1 9 10 #x7 #x38 #xe0 #x180 #xe0 #x70 #x1c #x3fc)
      ;; ≥
      (8805 11 1 9 9 #x70 #x38 #xe #x3 #xe #x70 #x1c0 #x1fe)
      ;; ⊂
      (8834 11 1 8 9 #x7f #xc0 #xc0 #xc0 #x180 #xfe)
      ;; ⊃
      (8835 11 1 8 9 #xfe #x3 #x3 #x3 #x6 #x1fc)
      ;; ⊕
      (8853 11 2 9 8 #x1e #x7e #xdb #xff #xdb #xfc #x78)
      ;; ⊗
      (8855 11 2 9 8 #x1e #x66 #xff #xdb #xff #xcc #x78)
      ;; ⋅
      (8901 11 4 7 5 #xe #x1f #x1f #x1c)
      ;; ▶
      (9654 8 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 11 2 11 8 #xc #xc #x1e #x66 #xc3 #x66 #x3c #x30 #x30)
      ;; ◊
      (9674 11 2 11 8 #xc #xc #x1e #x66 #xc3 #x66 #x3c #x30 #x30)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 15 1 12 13 #x40 #xa0 #xa0 #x110 #x150 #x248 #x248 #x444 #x444
        #x802 #x842 #x1fff)
      ;; ✓
      (10003 11 0 9 10 #x3 #x6 #x6 #xc #x30c #x198 #xf0 #xf0 #x60)
      ;; ❚
      (10074 6 1 11 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("Genera SWISS12-CCAPS" 14 11 3
      ;; the slug, which a character the face lacks draws
      (#f 6 1 10 4 #xf #x9 #x9 #x9 #x9 #x9 #x9 #x9 #x9 #xf)
      ;; space
      (32 6)
      ;; !
      (33 4 1 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x1 #x1)
      ;; "
      (34 5 1 10 3 #x5 #x5 #x5 #x5)
      ;; #
      (35 11 1 10 9 #x12 #x12 #x24 #xff #x24 #x48 #x1fe #x48 #x90 #x90)
      ;; $
      (36 9 1 11 7 #x8 #x3e #x49 #x48 #x48 #x3e #x9 #x9 #x49 #x49 #x3e #x8)
      ;; %
      (37 11 1 10 9 #xc4 #x124 #x128 #xc8 #x10 #x10 #x26 #x29 #x49 #x46)
      ;; &
      (38 10 1 10 8 #x38 #x44 #x44 #x28 #x30 #x52 #x8a #x84 #x86 #x79)
      ;; '
      (39 4 1 10 2 #x3 #x1 #x1 #x2)
      ;; (
      (40 5 1 10 3 #x1 #x2 #x2 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x2 #x2 #x1)
      ;; )
      (41 5 1 10 3 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4)
      ;; *
      (42 7 1 10 5 #x4 #x15 #xe #x15 #x4)
      ;; +
      (43 9 1 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8)
      ;; ,
      (44 6 2 2 2 #x3 #x3 #x1 #x2)
      ;; -
      (45 8 1 5 6 #x3f)
      ;; .
      (46 6 2 2 2 #x3 #x3)
      ;; /
      (47 5 0 10 5 #x1 #x1 #x2 #x2 #x4 #x4 #x8 #x8 #x10 #x10)
      ;; 0
      (48 9 1 10 7 #x1c #x22 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; 1
      (49 9 1 10 4 #x1 #x3 #xd #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; 2
      (50 9 1 10 7 #x3e #x41 #x41 #x1 #x2 #xc #x30 #x40 #x40 #x7f)
      ;; 3
      (51 9 1 10 7 #x3e #x41 #x41 #x2 #x1c #x3 #x1 #x41 #x41 #x3e)
      ;; 4
      (52 9 1 10 7 #x6 #xa #x12 #x12 #x22 #x42 #x7f #x2 #x2 #x2)
      ;; 5
      (53 9 1 10 7 #x3f #x20 #x40 #x7c #x42 #x1 #x1 #x1 #x42 #x3c)
      ;; 6
      (54 9 1 10 7 #x1e #x21 #x40 #x5c #x62 #x41 #x41 #x41 #x22 #x1c)
      ;; 7
      (55 9 1 10 7 #x7f #x1 #x1 #x2 #x4 #x8 #x8 #x10 #x10 #x10)
      ;; 8
      (56 9 1 10 7 #x1c #x22 #x41 #x22 #x1c #x22 #x41 #x41 #x22 #x1c)
      ;; 9
      (57 9 1 10 7 #x1c #x22 #x41 #x41 #x41 #x23 #x1d #x1 #x42 #x3c)
      ;; :
      (58 6 2 7 2 #x3 #x3 #x0 #x0 #x0 #x3 #x3)
      ;; ;
      (59 6 2 7 2 #x3 #x3 #x0 #x0 #x0 #x3 #x3 #x1 #x2)
      ;; <
      (60 7 1 10 5 #x1 #x2 #x4 #x8 #x10 #x10 #x8 #x4 #x2 #x1)
      ;; =
      (61 8 1 6 6 #x3f #x0 #x0 #x3f)
      ;; >
      (62 7 1 10 5 #x10 #x8 #x4 #x2 #x1 #x1 #x2 #x4 #x8 #x10)
      ;; ?
      (63 8 1 10 6 #x1e #x21 #x21 #x1 #x2 #x4 #x4 #x0 #x4 #x4)
      ;; @
      (64 12 1 10 10 #x78 #x186 #x132 #x249 #x249 #x249 #x24a #x134 #x180 #x7e)
      ;; A
      (65 10 1 10 8 #x18 #x18 #x24 #x24 #x24 #x42 #x7e #x42 #x81 #x81)
      ;; B
      (66 8 1 10 6 #x3e #x21 #x21 #x21 #x3e #x21 #x21 #x21 #x21 #x3e)
      ;; C
      (67 9 1 10 7 #x1c #x22 #x41 #x40 #x40 #x40 #x40 #x41 #x22 #x1c)
      ;; D
      (68 8 1 10 6 #x3c #x22 #x21 #x21 #x21 #x21 #x21 #x21 #x22 #x3c)
      ;; E
      (69 8 1 10 6 #x3f #x20 #x20 #x20 #x3e #x20 #x20 #x20 #x20 #x3f)
      ;; F
      (70 8 1 10 6 #x3f #x20 #x20 #x20 #x3e #x20 #x20 #x20 #x20 #x20)
      ;; G
      (71 9 1 10 7 #x1e #x21 #x41 #x40 #x40 #x47 #x41 #x41 #x23 #x1d)
      ;; H
      (72 9 1 10 7 #x41 #x41 #x41 #x41 #x7f #x41 #x41 #x41 #x41 #x41)
      ;; I
      (73 5 2 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; J
      (74 7 1 10 5 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x11 #x11 #xe)
      ;; K
      (75 8 1 10 6 #x21 #x22 #x24 #x28 #x30 #x30 #x28 #x24 #x22 #x21)
      ;; L
      (76 7 1 10 6 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; M
      (77 9 1 10 7 #x41 #x41 #x63 #x55 #x55 #x49 #x49 #x41 #x41 #x41)
      ;; N
      (78 9 1 10 7 #x41 #x61 #x51 #x51 #x49 #x49 #x45 #x45 #x43 #x41)
      ;; O
      (79 9 1 10 7 #x1c #x22 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; P
      (80 8 1 10 6 #x3e #x21 #x21 #x21 #x3e #x20 #x20 #x20 #x20 #x20)
      ;; Q
      (81 9 1 10 7 #x1c #x22 #x41 #x41 #x41 #x41 #x41 #x49 #x26 #x1e #x1)
      ;; R
      (82 8 1 10 6 #x3e #x21 #x21 #x21 #x3e #x22 #x21 #x21 #x21 #x21)
      ;; S
      (83 8 1 10 6 #x1e #x21 #x21 #x20 #x18 #x6 #x1 #x21 #x21 #x1e)
      ;; T
      (84 7 1 10 5 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4)
      ;; U
      (85 9 1 10 7 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; V
      (86 9 1 10 7 #x41 #x41 #x41 #x41 #x41 #x22 #x22 #x14 #x14 #x8)
      ;; W
      (87 11 1 10 9 #x101 #x101 #x111 #x111 #x111 #xaa #xaa #xc6 #x82 #x82)
      ;; X
      (88 9 1 10 7 #x41 #x41 #x22 #x14 #x8 #x8 #x14 #x22 #x41 #x41)
      ;; Y
      (89 9 1 10 7 #x41 #x41 #x41 #x22 #x14 #x8 #x8 #x8 #x8 #x8)
      ;; Z
      (90 8 1 10 6 #x3f #x1 #x1 #x2 #x4 #x8 #x10 #x20 #x20 #x3f)
      ;; [
      (91 6 1 10 4 #xf #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #xf)
      ;; \
      (92 7 1 10 5 #x10 #x10 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ]
      (93 6 1 10 4 #xf #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #xf)
      ;; ^
      (94 8 1 10 6 #xc #x12 #x21)
      ;; _
      (95 10 0 -2 10 #x3ff)
      ;; `
      (96 3 0 10 2 #x1 #x2 #x2 #x3)
      ;; a
      (97 9 1 7 7 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; b
      (98 9 1 10 7 #x40 #x40 #x40 #x5c #x62 #x41 #x41 #x41 #x62 #x5c)
      ;; c
      (99 8 1 7 6 #xe #x11 #x20 #x20 #x20 #x11 #xe)
      ;; d
      (100 9 1 10 7 #x1 #x1 #x1 #x1d #x23 #x41 #x41 #x41 #x23 #x1d)
      ;; e
      (101 9 1 7 7 #x1c #x22 #x41 #x7f #x40 #x21 #x1e)
      ;; f
      (102 6 1 10 4 #x3 #x4 #x4 #xf #x4 #x4 #x4 #x4 #x4 #x4)
      ;; g
      (103 9 1 7 7 #x1d #x23 #x41 #x41 #x41 #x23 #x1d #x1 #x42 #x3c)
      ;; h
      (104 8 1 10 6 #x20 #x20 #x20 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; i
      (105 5 2 10 1 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; j
      (106 5 0 10 3 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x6)
      ;; k
      (107 8 1 10 7 #x40 #x40 #x40 #x42 #x44 #x48 #x78 #x44 #x42 #x41)
      ;; l
      (108 5 2 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; m
      (109 13 1 7 11 #x5ce #x631 #x421 #x421 #x421 #x421 #x421)
      ;; n
      (110 8 1 7 6 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; o
      (111 9 1 7 7 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; p
      (112 9 1 7 7 #x5c #x62 #x41 #x41 #x41 #x62 #x5c #x40 #x40 #x40)
      ;; q
      (113 9 1 7 7 #x1d #x23 #x41 #x41 #x41 #x23 #x1d #x1 #x1 #x1)
      ;; r
      (114 6 1 7 4 #xb #xc #x8 #x8 #x8 #x8 #x8)
      ;; s
      (115 8 1 7 6 #x1e #x21 #x20 #x1e #x1 #x21 #x1e)
      ;; t
      (116 6 1 9 4 #x4 #x4 #xf #x4 #x4 #x4 #x4 #x4 #x3)
      ;; u
      (117 8 1 7 6 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; v
      (118 9 1 7 7 #x41 #x41 #x22 #x22 #x14 #x14 #x8)
      ;; w
      (119 11 1 7 9 #x111 #x111 #x92 #xaa #xaa #x44 #x44)
      ;; x
      (120 9 1 7 7 #x41 #x22 #x14 #x8 #x14 #x22 #x41)
      ;; y
      (121 9 1 7 7 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x10 #x60)
      ;; z
      (122 7 1 7 5 #x1f #x1 #x2 #x4 #x8 #x10 #x1f)
      ;; {
      (123 8 1 10 6 #x7 #x8 #x8 #x8 #x8 #x8 #x30 #x8 #x8 #x8 #x8 #x8 #x7)
      ;; |
      (124 4 2 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; }
      (125 8 1 10 6 #x38 #x4 #x4 #x4 #x4 #x4 #x3 #x4 #x4 #x4 #x4 #x4 #x38)
      ;; ~
      (126 8 1 6 6 #x19 #x26)
      ;; ¬
      (172 8 1 6 6 #x3f #x1 #x1)
      ;; °
      (176 6 1 10 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 8 1 7 5 #x4 #x4 #x1f #x4 #x4 #x1f)
      ;; µ
      (181 8 1 7 6 #x21 #x21 #x21 #x21 #x21 #x23 #x1d #x20 #x20 #x20)
      ;; ·
      (183 7 2 7 3 #x7 #x7 #x7)
      ;; À
      (192 10 1 11 8 #x10 #x8 #x0 #x18 #x18 #x24 #x42 #x7e #x42 #x81 #x81)
      ;; Á
      (193 10 1 11 8 #x8 #x10 #x0 #x18 #x18 #x24 #x42 #x7e #x42 #x81 #x81)
      ;; Â
      (194 10 1 11 8 #x10 #x28 #x0 #x18 #x18 #x24 #x42 #x7e #x42 #x81 #x81)
      ;; Ã
      (195 10 1 11 8 #x14 #x28 #x0 #x18 #x18 #x24 #x42 #x7e #x42 #x81 #x81)
      ;; Ä
      (196 10 1 11 8 #x28 #x0 #x18 #x18 #x24 #x24 #x42 #x7e #x42 #x81 #x81)
      ;; Å
      (197 10 1 11 8 #x10 #x28 #x10 #x18 #x18 #x24 #x42 #x7e #x42 #x81 #x81)
      ;; Ç
      (199 9 1 10 7 #x1c #x22 #x41 #x40 #x40 #x40 #x40 #x41 #x22 #x1c #x8 #x10)
      ;; È
      (200 8 1 11 6 #x8 #x4 #x0 #x3f #x20 #x3e #x20 #x20 #x20 #x20 #x3f)
      ;; É
      (201 8 1 11 6 #x4 #x8 #x0 #x3f #x20 #x3e #x20 #x20 #x20 #x20 #x3f)
      ;; Ê
      (202 8 1 11 6 #x8 #x14 #x0 #x3f #x20 #x3e #x20 #x20 #x20 #x20 #x3f)
      ;; Ë
      (203 8 1 11 6 #x14 #x0 #x3f #x20 #x20 #x3e #x20 #x20 #x20 #x20 #x3f)
      ;; Ì
      (204 5 1 11 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Í
      (205 5 1 11 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Î
      (206 5 0 11 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Ï
      (207 5 0 11 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Ñ
      (209 9 1 11 7 #x14 #x28 #x0 #x41 #x61 #x51 #x49 #x45 #x45 #x43 #x41)
      ;; Ò
      (210 9 1 11 7 #x10 #x8 #x0 #x1c #x22 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ó
      (211 9 1 11 7 #x8 #x10 #x0 #x1c #x22 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ô
      (212 9 1 11 7 #x10 #x28 #x0 #x1c #x22 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Õ
      (213 9 1 11 7 #x14 #x28 #x0 #x1c #x22 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ö
      (214 9 1 11 7 #x28 #x0 #x1c #x22 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; ×
      (215 9 1 7 7 #x41 #x22 #x14 #x8 #x14 #x22 #x41)
      ;; Ù
      (217 9 1 11 7 #x10 #x8 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ú
      (218 9 1 11 7 #x8 #x10 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Û
      (219 9 1 11 7 #x10 #x28 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ü
      (220 9 1 11 7 #x28 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; Ý
      (221 9 1 11 7 #x8 #x10 #x0 #x41 #x22 #x14 #x8 #x8 #x8 #x8 #x8)
      ;; à
      (224 9 1 10 7 #x10 #x8 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; á
      (225 9 1 10 7 #x8 #x10 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; â
      (226 9 1 10 7 #x10 #x28 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; ã
      (227 9 1 10 7 #x14 #x28 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; ä
      (228 9 1 9 7 #x28 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; å
      (229 9 1 11 7 #x10 #x28 #x10 #x0 #x3c #x42 #x6 #x3a #x42 #x42 #x3d)
      ;; ç
      (231 8 1 7 6 #xe #x11 #x20 #x20 #x20 #x11 #xe #x4 #x8)
      ;; è
      (232 9 1 10 7 #x10 #x8 #x0 #x1c #x22 #x41 #x7f #x40 #x21 #x1e)
      ;; é
      (233 9 1 10 7 #x8 #x10 #x0 #x1c #x22 #x41 #x7f #x40 #x21 #x1e)
      ;; ê
      (234 9 1 10 7 #x10 #x28 #x0 #x1c #x22 #x41 #x7f #x40 #x21 #x1e)
      ;; ë
      (235 9 1 9 7 #x28 #x0 #x1c #x22 #x41 #x7f #x40 #x21 #x1e)
      ;; ì
      (236 5 1 10 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; í
      (237 5 1 10 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; î
      (238 5 0 10 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ï
      (239 5 0 9 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ñ
      (241 8 1 10 6 #xa #x14 #x0 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; ò
      (242 9 1 10 7 #x10 #x8 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; ó
      (243 9 1 10 7 #x8 #x10 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; ô
      (244 9 1 10 7 #x10 #x28 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; õ
      (245 9 1 10 7 #x14 #x28 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; ö
      (246 9 1 9 7 #x28 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; ù
      (249 8 1 10 6 #x8 #x4 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; ú
      (250 8 1 10 6 #x4 #x8 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; û
      (251 8 1 10 6 #x8 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; ü
      (252 8 1 9 6 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; ý
      (253 9 1 10 7 #x8 #x10 #x0 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x10
        #x60)
      ;; ÿ
      (255 9 1 9 7 #x28 #x0 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x10 #x60)
      ;; α
      (945 8 1 6 6 #x1d #x22 #x22 #x22 #x22 #x1d)
      ;; β
      (946 8 1 8 6 #x1e #x21 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20)
      ;; γ
      (947 7 1 8 5 #x11 #xa #x4 #xa #x11 #x11 #x11 #xe)
      ;; δ
      (948 8 1 9 6 #xe #x10 #x10 #x8 #xc #x12 #x21 #x21 #x1e)
      ;; ε
      (949 7 1 6 5 #x7 #x8 #x1e #x10 #x8 #x7)
      ;; λ
      (955 8 1 8 6 #x20 #x20 #x10 #x8 #xc #x12 #x21 #x21)
      ;; π
      (960 8 1 6 6 #x3f #x12 #x12 #x12 #x12 #x12)
      ;; –
      (8211 8 0 5 7 #x7f)
      ;; —
      (8212 9 0 5 9 #x1ff)
      ;; ‘
      (8216 4 1 10 2 #x3 #x1 #x1 #x2)
      ;; ’
      (8217 4 1 10 2 #x3 #x1 #x1 #x2)
      ;; “
      (8220 5 1 10 3 #x5 #x5 #x5 #x5)
      ;; ”
      (8221 5 1 10 3 #x5 #x5 #x5 #x5)
      ;; …
      (8230 18 2 2 14 #x30c3 #x30c3)
      ;; ←
      (8592 10 2 7 7 #x10 #x20 #x7f #x20 #x10)
      ;; ↑
      (8593 7 1 7 5 #x4 #xe #x15 #x4 #x4 #x4 #x4)
      ;; →
      (8594 8 1 7 6 #x4 #x2 #x3f #x2 #x4)
      ;; ↓
      (8595 7 1 7 5 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 8 1 9 6 #x4 #x2 #x3f #x2 #x4 #x8 #x10 #x3f #x10 #x8)
      ;; ↳
      (8627 8 1 10 6 #x20 #x20 #x20 #x24 #x22 #x3f #x2 #x4)
      ;; ∀
      (8704 8 1 9 6 #x21 #x21 #x21 #x21 #x3f #x21 #x12 #x12 #xc)
      ;; ∂
      (8706 7 1 9 5 #xc #x2 #x1 #x1 #xf #x11 #x11 #x11 #xe)
      ;; ∃
      (8707 8 1 9 6 #x3f #x1 #x1 #x1 #x1f #x1 #x1 #x1 #x3f)
      ;; −
      (8722 9 1 5 7 #x7f)
      ;; ∞
      (8734 9 1 6 7 #x36 #x49 #x49 #x49 #x36)
      ;; ∧
      (8743 8 1 7 6 #xc #x12 #x21)
      ;; ∨
      (8744 8 1 6 6 #x21 #x12 #xc)
      ;; ∩
      (8745 7 1 7 5 #xe #x11 #x11 #x11 #x11 #x11)
      ;; ∪
      (8746 7 1 7 5 #x11 #x11 #x11 #x11 #x11 #xe)
      ;; ∫
      (8747 7 1 10 5 #x3 #x5 #x5 #x4 #x4 #x4 #x4 #x4 #x14 #x14 #x18)
      ;; ≠
      (8800 8 1 7 6 #x1 #x2 #x3f #x4 #x8 #x3f #x10 #x20)
      ;; ≡
      (8801 9 2 5 5 #x1f #x0 #x1f #x0 #x1f)
      ;; ≤
      (8804 8 2 9 4 #x1 #x2 #x4 #x8 #x4 #x2 #x1 #x0 #xf)
      ;; ≥
      (8805 8 2 9 4 #x8 #x4 #x2 #x1 #x2 #x4 #x8 #x0 #xf)
      ;; ⊂
      (8834 9 1 6 6 #x1f #x20 #x20 #x20 #x1f)
      ;; ⊃
      (8835 8 1 6 6 #x3e #x1 #x1 #x1 #x3e)
      ;; ⊕
      (8853 9 1 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 9 1 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 7 2 7 3 #x7 #x7 #x7)
      ;; ▶
      (9654 7 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 7 1 9 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ◊
      (9674 7 1 9 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 13 1 11 11 #x20 #x20 #x50 #x88 #xa8 #xa8 #x124 #x222 #x202 #x222
        #x7ff)
      ;; ✓
      (10003 9 0 8 8 #x1 #x2 #x2 #x4 #x84 #x48 #x28 #x10)
      ;; ❚
      (10074 4 1 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("Genera SWISS12-CCAPS Bold" 14 11 3
      ;; the slug, which a character the face lacks draws
      (#f 7 1 10 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x1f)
      ;; space
      (32 7)
      ;; !
      (33 5 1 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x0 #x3 #x3)
      ;; "
      (34 7 1 10 5 #x1b #x1b #x1b #x1b)
      ;; #
      (35 12 1 10 10 #x36 #x36 #x6c #x1ff #x6c #xd8 #x3fe #xd8 #x1b0 #x1b0)
      ;; $
      (36 10 1 11 8 #x18 #x7e #xdb #xd8 #xd8 #x7e #x1b #x1b #xdb #xdb #x7e
        #x18)
      ;; %
      (37 12 1 10 10 #x1cc #x36c #x378 #x1d8 #x30 #x30 #x6e #x7b #xdb #xce)
      ;; &
      (38 11 1 10 9 #x78 #xcc #xcc #x78 #x70 #xf6 #x19e #x18c #x18e #xfb)
      ;; '
      (39 4 1 10 3 #x7 #x3 #x3 #x6)
      ;; (
      (40 6 1 10 4 #x3 #x6 #x6 #xc #xc #xc #xc #xc #xc #x6 #x6 #x3)
      ;; )
      (41 6 1 10 4 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc)
      ;; *
      (42 8 1 10 6 #xc #x3f #x1e #x3f #xc)
      ;; +
      (43 10 1 8 8 #x18 #x18 #x18 #xff #xff #x18 #x18 #x18)
      ;; ,
      (44 7 2 2 3 #x7 #x7 #x3 #x6)
      ;; -
      (45 8 1 6 6 #x3f #x3f)
      ;; .
      (46 7 2 2 3 #x7 #x7)
      ;; /
      (47 6 0 10 6 #x3 #x3 #x6 #x6 #xc #xc #x18 #x18 #x30 #x30)
      ;; 0
      (48 10 1 10 8 #x3c #x66 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; 1
      (49 9 1 10 5 #x3 #x7 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; 2
      (50 10 1 10 8 #x7e #xc3 #xc3 #x3 #x6 #x1c #x70 #xc0 #xc0 #xff)
      ;; 3
      (51 10 1 10 8 #x7e #xc3 #xc3 #x6 #x3c #x7 #x3 #xc3 #xc3 #x7e)
      ;; 4
      (52 10 1 10 8 #xe #x1e #x36 #x36 #x66 #xc6 #xff #x6 #x6 #x6)
      ;; 5
      (53 10 1 10 8 #x7f #x60 #xc0 #xfc #xc6 #x3 #x3 #x3 #xc6 #x7c)
      ;; 6
      (54 10 1 10 8 #x3e #x63 #xc0 #xfc #xe6 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; 7
      (55 10 1 10 8 #xff #x3 #x3 #x6 #xc #x18 #x18 #x30 #x30 #x30)
      ;; 8
      (56 10 1 10 8 #x3c #x66 #xc3 #x66 #x3c #x66 #xc3 #xc3 #x66 #x3c)
      ;; 9
      (57 10 1 10 8 #x3c #x66 #xc3 #xc3 #xc7 #x7f #x3 #x3 #xc6 #x7c)
      ;; :
      (58 7 2 7 3 #x7 #x7 #x0 #x0 #x0 #x7 #x7)
      ;; ;
      (59 7 2 7 3 #x7 #x7 #x0 #x0 #x0 #x7 #x7 #x3 #x6)
      ;; <
      (60 8 1 10 6 #x3 #x6 #xc #x18 #x30 #x30 #x18 #xc #x6 #x3)
      ;; =
      (61 8 1 5 6 #x3f #x0 #x3f)
      ;; >
      (62 8 1 10 6 #x30 #x18 #xc #x6 #x3 #x3 #x6 #xc #x18 #x30)
      ;; ?
      (63 9 1 10 7 #x3e #x63 #x63 #x3 #x6 #xc #xc #x0 #xc #xc)
      ;; @
      (64 13 1 10 11 #xf8 #x38e #x376 #x653 #x6db #x6db #x656 #x37c #x380 #xfe)
      ;; A
      (65 10 1 10 8 #x18 #x18 #x3c #x24 #x66 #x66 #x7e #xc3 #xc3 #xc3)
      ;; B
      (66 9 1 10 7 #x7e #x63 #x63 #x63 #x7e #x63 #x63 #x63 #x63 #x7e)
      ;; C
      (67 10 1 10 8 #x3c #x66 #xc3 #xc0 #xc0 #xc0 #xc0 #xc3 #x66 #x3c)
      ;; D
      (68 10 1 10 8 #xfc #xc6 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6 #xfc)
      ;; E
      (69 9 1 10 7 #x7f #x60 #x60 #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; F
      (70 9 1 10 7 #x7f #x60 #x60 #x60 #x7e #x60 #x60 #x60 #x60 #x60)
      ;; G
      (71 10 1 10 8 #x3e #x63 #xc3 #xc0 #xc0 #xcf #xc3 #xc3 #x67 #x3d)
      ;; H
      (72 10 1 10 8 #xc3 #xc3 #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; I
      (73 6 2 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; J
      (74 7 0 10 6 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x33 #x33 #x1e)
      ;; K
      (75 9 1 10 8 #xc6 #xcc #xd8 #xf0 #xe0 #xf0 #xd8 #xcc #xc6 #xc3)
      ;; L
      (76 8 1 10 6 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x3f)
      ;; M
      (77 11 1 10 9 #x183 #x183 #x1c7 #x1c7 #x1ab #x1bb #x193 #x193 #x183
        #x183)
      ;; N
      (78 10 1 10 8 #xc3 #xe3 #xe3 #xd3 #xdb #xcb #xcb #xc7 #xc7 #xc3)
      ;; O
      (79 10 1 10 8 #x3c #x66 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; P
      (80 9 1 10 7 #x7e #x63 #x63 #x63 #x7e #x60 #x60 #x60 #x60 #x60)
      ;; Q
      (81 10 1 10 8 #x3c #x66 #xc3 #xc3 #xc3 #xc3 #xc3 #xcb #x6e #x3e #x3)
      ;; R
      (82 9 1 10 7 #x7e #x63 #x63 #x63 #x7e #x66 #x63 #x63 #x63 #x63)
      ;; S
      (83 9 1 10 7 #x3e #x63 #x61 #x60 #x3c #x3 #x3 #x63 #x63 #x3e)
      ;; T
      (84 8 0 10 8 #xff #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18)
      ;; U
      (85 10 1 10 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; V
      (86 9 1 10 7 #x63 #x63 #x63 #x63 #x63 #x22 #x36 #x36 #x1c #x8)
      ;; W
      (87 12 1 10 10 #x303 #x303 #x333 #x333 #x333 #x17a #x1ce #x1ce #x186
        #x186)
      ;; X
      (88 9 1 10 7 #x63 #x63 #x36 #x1c #x8 #x1c #x36 #x22 #x63 #x63)
      ;; Y
      (89 10 1 10 8 #xc3 #xc3 #x66 #x66 #x3c #x18 #x18 #x18 #x18 #x18)
      ;; Z
      (90 9 1 10 7 #x7f #x3 #x3 #x6 #xc #x18 #x30 #x60 #x60 #x7f)
      ;; [
      (91 7 1 10 5 #x1f #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18
        #x1f)
      ;; \
      (92 8 1 10 6 #x30 #x30 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ]
      (93 7 1 10 5 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x1f)
      ;; ^
      (94 9 1 10 7 #x1c #x36 #x63)
      ;; _
      (95 11 0 -2 11 #x7ff)
      ;; `
      (96 4 0 10 3 #x3 #x6 #x6 #x7)
      ;; a
      (97 9 1 7 8 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; b
      (98 10 1 10 8 #xc0 #xc0 #xc0 #xdc #xe6 #xc3 #xc3 #xc3 #xe6 #xdc)
      ;; c
      (99 9 1 7 7 #x1e #x33 #x60 #x60 #x60 #x33 #x1e)
      ;; d
      (100 10 1 10 8 #x3 #x3 #x3 #x3b #x67 #xc3 #xc3 #xc3 #x67 #x3b)
      ;; e
      (101 10 1 7 8 #x3c #x66 #xc3 #xff #xc0 #x63 #x3e)
      ;; f
      (102 8 1 10 7 #x1e #x33 #x30 #x7c #x30 #x30 #x30 #x30 #x30 #x30)
      ;; g
      (103 10 1 7 8 #x3b #x67 #xc3 #xc3 #xc3 #x67 #x3b #x3 #xc6 #x7c)
      ;; h
      (104 9 1 10 7 #x60 #x60 #x60 #x6e #x73 #x63 #x63 #x63 #x63 #x63)
      ;; i
      (105 6 2 10 2 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; j
      (106 7 0 10 5 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x1b #xe)
      ;; k
      (107 9 1 10 8 #xc0 #xc0 #xc0 #xc6 #xcc #xd8 #xf8 #xcc #xc6 #xc3)
      ;; l
      (108 6 2 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; m
      (109 14 1 7 12 #xdde #xe73 #xc63 #xc63 #xc63 #xc63 #xc63)
      ;; n
      (110 9 1 7 7 #x5e #x73 #x63 #x63 #x63 #x63 #x63)
      ;; o
      (111 10 1 7 8 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; p
      (112 10 1 7 8 #xdc #xe6 #xc3 #xc3 #xc3 #xe6 #xdc #xc0 #xc0 #xc0)
      ;; q
      (113 10 1 7 8 #x3b #x67 #xc3 #xc3 #xc3 #x67 #x3b #x3 #x3 #x3)
      ;; r
      (114 8 1 7 7 #x6e #x73 #x60 #x60 #x60 #x60 #x60)
      ;; s
      (115 9 1 7 7 #x3e #x63 #x60 #x3e #x3 #x63 #x3e)
      ;; t
      (116 8 1 9 6 #x18 #x18 #x3f #x18 #x18 #x18 #x18 #x1b #xe)
      ;; u
      (117 9 1 7 7 #x63 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; v
      (118 10 1 7 8 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18)
      ;; w
      (119 11 1 7 9 #x183 #x183 #x193 #x1bb #xee #xc6 #xc6)
      ;; x
      (120 10 1 7 8 #xc3 #x66 #x3c #x18 #x3c #x66 #xc3)
      ;; y
      (121 10 1 7 8 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18 #x18 #xf0 #x60)
      ;; z
      (122 8 1 7 6 #x3f #x3 #x6 #xc #x18 #x30 #x3f)
      ;; {
      (123 9 1 10 7 #xf #x18 #x18 #x18 #x18 #x18 #x70 #x18 #x18 #x18 #x18 #x18
        #xf)
      ;; |
      (124 5 2 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; }
      (125 9 1 10 7 #x78 #xc #xc #xc #xc #xc #x7 #xc #xc #xc #xc #xc #x78)
      ;; ~
      (126 9 1 6 7 #x3b #x6e)
      ;; ¬
      (172 9 1 6 7 #x7f #x3 #x3)
      ;; °
      (176 6 1 10 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 1 7 6 #xc #xc #x3f #x3f #xc #x0 #x3f #x3f)
      ;; µ
      (181 9 1 7 7 #x63 #x63 #x63 #x63 #x63 #x67 #x3b #x60 #x60 #x60)
      ;; ·
      (183 8 2 6 4 #x6 #xf #xf #x6)
      ;; À
      (192 10 1 11 8 #x30 #x18 #x0 #x18 #x3c #x24 #x66 #x7e #xc3 #xc3 #xc3)
      ;; Á
      (193 10 1 11 8 #x18 #x30 #x0 #x18 #x3c #x24 #x66 #x7e #xc3 #xc3 #xc3)
      ;; Â
      (194 10 1 11 8 #x18 #x3c #x0 #x18 #x3c #x24 #x66 #x7e #xc3 #xc3 #xc3)
      ;; Ã
      (195 10 1 11 8 #x3c #x78 #x0 #x18 #x3c #x24 #x66 #x7e #xc3 #xc3 #xc3)
      ;; Ä
      (196 10 1 11 8 #x3c #x0 #x18 #x3c #x24 #x66 #x66 #x7e #xc3 #xc3 #xc3)
      ;; Å
      (197 10 1 11 8 #x18 #x3c #x18 #x18 #x3c #x24 #x66 #x7e #xc3 #xc3 #xc3)
      ;; Ç
      (199 10 1 10 8 #x3c #x66 #xc3 #xc0 #xc0 #xc0 #xc0 #xc3 #x66 #x3c #x18
        #x30)
      ;; È
      (200 9 1 11 7 #x30 #x18 #x0 #x7f #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; É
      (201 9 1 11 7 #x18 #x30 #x0 #x7f #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; Ê
      (202 9 1 11 7 #x18 #x3c #x0 #x7f #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; Ë
      (203 9 1 11 7 #x3c #x0 #x7f #x60 #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; Ì
      (204 6 1 11 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; Í
      (205 6 1 11 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; Î
      (206 6 1 11 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; Ï
      (207 6 1 11 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; Ñ
      (209 10 1 11 8 #x3c #x78 #x0 #xc3 #xe3 #xd3 #xdb #xcb #xc7 #xc7 #xc3)
      ;; Ò
      (210 10 1 11 8 #x30 #x18 #x0 #x3c #x66 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ó
      (211 10 1 11 8 #x18 #x30 #x0 #x3c #x66 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ô
      (212 10 1 11 8 #x18 #x3c #x0 #x3c #x66 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Õ
      (213 10 1 11 8 #x3c #x78 #x0 #x3c #x66 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ö
      (214 10 1 11 8 #x3c #x0 #x3c #x66 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; ×
      (215 10 1 7 8 #xc3 #x66 #x3c #x18 #x3c #x66 #xc3)
      ;; Ù
      (217 10 1 11 8 #x30 #x18 #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ú
      (218 10 1 11 8 #x18 #x30 #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Û
      (219 10 1 11 8 #x18 #x3c #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ü
      (220 10 1 11 8 #x3c #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ý
      (221 10 1 11 8 #x18 #x30 #x0 #xc3 #x66 #x3c #x18 #x18 #x18 #x18 #x18)
      ;; à
      (224 9 1 10 8 #x30 #x18 #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; á
      (225 9 1 10 8 #x18 #x30 #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; â
      (226 9 1 10 8 #x18 #x3c #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; ã
      (227 9 1 10 8 #x3c #x78 #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; ä
      (228 9 1 9 8 #x3c #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; å
      (229 9 1 11 8 #x18 #x3c #x18 #x0 #x7c #xc6 #x6 #x7e #xc6 #xc6 #x7f)
      ;; ç
      (231 9 1 7 7 #x1e #x33 #x60 #x60 #x60 #x33 #x1e #x18 #x30)
      ;; è
      (232 10 1 10 8 #x30 #x18 #x0 #x3c #x66 #xc3 #xff #xc0 #x63 #x3e)
      ;; é
      (233 10 1 10 8 #x18 #x30 #x0 #x3c #x66 #xc3 #xff #xc0 #x63 #x3e)
      ;; ê
      (234 10 1 10 8 #x18 #x3c #x0 #x3c #x66 #xc3 #xff #xc0 #x63 #x3e)
      ;; ë
      (235 10 1 9 8 #x3c #x0 #x3c #x66 #xc3 #xff #xc0 #x63 #x3e)
      ;; ì
      (236 6 1 10 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; í
      (237 6 1 10 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; î
      (238 6 1 10 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ï
      (239 6 1 9 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ñ
      (241 9 1 10 7 #x3c #x78 #x0 #x5e #x73 #x63 #x63 #x63 #x63 #x63)
      ;; ò
      (242 10 1 10 8 #x30 #x18 #x0 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; ó
      (243 10 1 10 8 #x18 #x30 #x0 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; ô
      (244 10 1 10 8 #x18 #x3c #x0 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; õ
      (245 10 1 10 8 #x3c #x78 #x0 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; ö
      (246 10 1 9 8 #x3c #x0 #x3c #x66 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; ù
      (249 9 1 10 7 #x30 #x18 #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; ú
      (250 9 1 10 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; û
      (251 9 1 10 7 #x18 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; ü
      (252 9 1 9 7 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x67 #x3b)
      ;; ý
      (253 10 1 10 8 #x18 #x30 #x0 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18 #x18
        #xf0 #x60)
      ;; ÿ
      (255 10 1 9 8 #x3c #x0 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18 #x18 #xf0 #x60)
      ;; α
      (945 9 1 6 7 #x3f #x66 #x66 #x66 #x66 #x3f)
      ;; β
      (946 9 1 8 7 #x3e #x63 #x63 #x7e #x63 #x63 #x63 #x7e #x60 #x60)
      ;; γ
      (947 8 1 8 6 #x33 #x1e #xc #x1e #x33 #x33 #x33 #x1e)
      ;; δ
      (948 9 1 9 7 #x1e #x30 #x30 #x18 #x1c #x36 #x63 #x63 #x3e)
      ;; ε
      (949 8 1 6 6 #xf #x18 #x3e #x30 #x18 #xf)
      ;; λ
      (955 9 1 8 7 #x60 #x60 #x30 #x18 #x1c #x36 #x63 #x63)
      ;; π
      (960 9 1 6 7 #x7f #x36 #x36 #x36 #x36 #x36)
      ;; –
      (8211 9 0 6 8 #xff #xff)
      ;; —
      (8212 11 0 6 11 #x7ff #x7ff)
      ;; ‘
      (8216 4 1 10 3 #x7 #x3 #x3 #x6)
      ;; ’
      (8217 4 1 10 3 #x7 #x3 #x3 #x6)
      ;; “
      (8220 7 1 10 5 #x1b #x1b #x1b #x1b)
      ;; ”
      (8221 7 1 10 5 #x1b #x1b #x1b #x1b)
      ;; …
      (8230 21 2 2 17 #x1c387 #x1c387)
      ;; ←
      (8592 11 2 7 8 #x30 #x60 #xff #x60 #x30)
      ;; ↑
      (8593 8 1 7 6 #xc #x1e #x3f #xc #xc #xc #xc)
      ;; →
      (8594 9 1 7 7 #xc #x6 #x7f #x6 #xc)
      ;; ↓
      (8595 8 1 7 6 #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↔
      (8596 9 1 9 7 #xc #x6 #x7f #x6 #xc #x18 #x30 #x7f #x30 #x18)
      ;; ↳
      (8627 9 1 10 7 #x60 #x60 #x60 #x6c #x66 #x7f #x6 #xc)
      ;; ∀
      (8704 9 1 9 7 #x63 #x63 #x63 #x63 #x7f #x63 #x36 #x36 #x1c)
      ;; ∂
      (8706 8 1 9 6 #x1c #x6 #x3 #x3 #x1f #x33 #x33 #x33 #x1e)
      ;; ∃
      (8707 9 1 9 7 #x7f #x3 #x3 #x3 #x3f #x3 #x3 #x3 #x7f)
      ;; −
      (8722 10 1 5 8 #xff #xff)
      ;; ∞
      (8734 10 1 6 8 #x7e #xdb #xdb #xdb #x7e)
      ;; ∧
      (8743 9 1 7 7 #x1c #x36 #x63)
      ;; ∨
      (8744 9 1 6 7 #x63 #x36 #x1c)
      ;; ∩
      (8745 8 1 7 6 #x1e #x33 #x33 #x33 #x33 #x33)
      ;; ∪
      (8746 8 1 7 6 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; ∫
      (8747 8 1 10 6 #x7 #xf #xf #xc #xc #xc #xc #xc #x3c #x3c #x38)
      ;; ≠
      (8800 9 1 7 7 #x3 #x6 #x7f #xc #x18 #x7f #x30 #x60)
      ;; ≡
      (8801 10 2 5 6 #x3f #x0 #x3f #x0 #x3f)
      ;; ≤
      (8804 9 2 9 5 #x3 #x6 #xc #x18 #xc #x6 #x3 #x0 #x1f)
      ;; ≥
      (8805 9 2 9 5 #x18 #xc #x6 #x3 #x6 #xc #x18 #x0 #x1f)
      ;; ⊂
      (8834 10 1 6 7 #x3f #x60 #x60 #x60 #x3f)
      ;; ⊃
      (8835 9 1 6 7 #x7e #x3 #x3 #x3 #x7e)
      ;; ⊕
      (8853 10 1 8 8 #x3c #x7e #xdb #xff #xdb #x7e #x3c)
      ;; ⊗
      (8855 10 1 8 8 #x3c #x66 #xff #xdb #xff #x66 #x3c)
      ;; ⋅
      (8901 8 2 6 4 #x6 #xf #xf #x6)
      ;; ▶
      (9654 7 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 8 1 9 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ◊
      (9674 8 1 9 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 13 1 11 11 #x20 #x20 #x50 #x88 #xa8 #xa8 #x124 #x222 #x202 #x222
        #x7ff)
      ;; ✓
      (10003 10 0 8 9 #x3 #x6 #x6 #xc #x18c #xd8 #x78 #x30)
      ;; ❚
      (10074 6 1 10 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf)))))
