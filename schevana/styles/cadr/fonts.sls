;;; (schevana styles cadr fonts) — the MIT CADR's fonts, in which the CADR
;;; style draws its text: CPTFONT (the code font, 8 by 12), MEDFNT (the
;;; menus'), HL10 and HL12 (the choices' and the windows'), and TR10I (the
;;; small italic of "More above"), with the bold and italic strikes System
;;; 99 has (HL12 has all four; CPTFONT, MEDFNT and HL10 a bold; TR10 only
;;; its italic). They are MIT's, decoded from MIT System 99's fonts/*.qfasl
;;; (cptfont, cptfontb, medfnt, medfnb, hl10, hl10b, hl12, hl12b, hl12i,
;;; hl12bi, tr10i), the same archive as the 5X5 font's ((schevana styles
;;; genera font-5x5)), and are used under this license:
;;;
;;;   Copyright (c) 1980, Massachusetts Institute of Technology. All rights
;;;   reserved. Redistribution and use in source and binary forms, with or
;;;   without modification, are permitted provided that the following
;;;   conditions are met: Redistributions of source code must retain the above
;;;   copyright notice, this list of conditions and the following disclaimer.
;;;   Redistributions in binary form must reproduce the above copyright
;;;   notice, this list of conditions and the following disclaimer in the
;;;   documentation and/or other materials provided with the distribution.
;;;   Neither the names of the Massachusetts Institute of Technology nor the
;;;   names of its contributors may be used to endorse or promote products
;;;   derived from this software without specific prior written permission.
;;;
;;;   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
;;;   IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
;;;   THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
;;;   PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
;;;   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
;;;   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
;;;   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
;;;   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
;;;   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;;   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;;   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;;
;;; Their glyphs are the Lisp machine's characters as Unicode: ASCII, the
;;; Greek letters, arrows and logic signs of codes 0 to 31, and the
;;; integral of 127. What the fonts lack and Schevana's own text uses was
;;; drawn for this file from each font's own glyphs and stem, in its
;;; manner: the middle dot, lambda and the arrows in HL10 and TR10I, which
;;; have none of the Lisp machine's symbols; the ellipsis of three of its
;;; periods; the dashes of its hyphen; the minus of its plus; × as its
;;; x; µ of its u; °, ✓, ▶, ❚, ⚠, ⚙ and ↳ at its stem's width; the curly
;;; quotes as its straight ones; and the Latin-1 letters, each with its
;;; accent over the letter, a capital a row or two shorter where the cell
;;; has no room above it. A character none of this covers draws the slug,
;;; an outline as tall as a capital.

(library (schevana styles cadr fonts)
  (export cadr-fonts)
  (import (chezscheme)
          (only (schevana base) library-layer))

  (library-layer looks)

  ;; The fonts, each (name pixel-size ascent descent glyph ...), as
  ;; define-bitmap-font takes them: a glyph is (char advance left top width
  ;; row ...), its rows from the top, the leftmost pixel in a row's highest
  ;; bit; #f is the slug. A bold or italic strike is a font of its own.
  (define cadr-fonts
    '(("CADR CPTFONT" 12 10 2
      ;; the slug, which a character the face lacks draws
      (#f 8 1 9 6 #x3f #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x3f)
      ;; space
      (32 8)
      ;; !
      (33 8 4 9 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x1)
      ;; "
      (34 8 3 10 3 #x5 #x5 #x5 #x5)
      ;; #
      (35 8 1 9 6 #x12 #x12 #x3f #x12 #x12 #x3f #x12 #x12 #x12)
      ;; $
      (36 8 2 10 5 #x4 #xe #x15 #x14 #xe #x5 #x15 #x15 #xe #x4)
      ;; %
      (37 8 1 9 6 #x1f #x31 #x31 #x2 #x4 #x8 #x10 #x23 #x23)
      ;; &
      (38 8 1 9 6 #x18 #x24 #x24 #x28 #x10 #x29 #x26 #x24 #x1b)
      ;; '
      (39 8 2 10 3 #x3 #x3 #x3 #x6)
      ;; (
      (40 8 3 10 3 #x1 #x2 #x2 #x4 #x4 #x4 #x4 #x4 #x2 #x2 #x1)
      ;; )
      (41 8 3 10 3 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4)
      ;; *
      (42 8 2 8 5 #x4 #x15 #xe #x1f #xe #x15 #x4)
      ;; +
      (43 8 2 7 5 #x4 #x4 #x1f #x4 #x4)
      ;; ,
      (44 8 1 2 3 #x3 #x3 #x3 #x6)
      ;; -
      (45 8 1 5 6 #x3f)
      ;; .
      (46 8 3 2 2 #x3 #x3)
      ;; /
      (47 8 1 8 6 #x1 #x3 #x6 #xc #x18 #x30 #x20)
      ;; 0
      (48 8 1 9 6 #x1e #x21 #x21 #x23 #x25 #x29 #x31 #x21 #x1e)
      ;; 1
      (49 8 2 9 3 #x2 #x6 #x2 #x2 #x2 #x2 #x2 #x2 #x7)
      ;; 2
      (50 8 1 9 6 #x1e #x21 #x21 #x1 #xe #x10 #x20 #x20 #x3f)
      ;; 3
      (51 8 1 9 6 #x1e #x21 #x21 #x1 #xe #x1 #x21 #x21 #x1e)
      ;; 4
      (52 8 1 9 6 #x6 #xa #x12 #x22 #x22 #x3f #x2 #x2 #x2)
      ;; 5
      (53 8 1 9 6 #x3f #x20 #x20 #x3e #x1 #x1 #x1 #x21 #x1e)
      ;; 6
      (54 8 1 9 6 #x1e #x20 #x20 #x3e #x21 #x21 #x21 #x21 #x1e)
      ;; 7
      (55 8 1 9 6 #x3f #x1 #x1 #x2 #xe #x4 #x8 #x8 #x8)
      ;; 8
      (56 8 1 9 6 #x1e #x21 #x21 #x21 #x1e #x21 #x21 #x21 #x1e)
      ;; 9
      (57 8 1 9 6 #x1e #x21 #x21 #x21 #x1f #x1 #x1 #x2 #x1c)
      ;; :
      (58 8 3 6 2 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; ;
      (59 8 2 6 3 #x3 #x3 #x0 #x0 #x3 #x3 #x3 #x6)
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
      (71 8 1 9 6 #x1e #x21 #x21 #x20 #x27 #x21 #x21 #x21 #x1e)
      ;; H
      (72 8 1 9 6 #x21 #x21 #x21 #x21 #x3f #x21 #x21 #x21 #x21)
      ;; I
      (73 8 2 9 3 #x7 #x2 #x2 #x2 #x2 #x2 #x2 #x2 #x7)
      ;; J
      (74 8 1 9 5 #x1 #x1 #x1 #x1 #x1 #x1 #x11 #x11 #xe)
      ;; K
      (75 8 1 9 6 #x21 #x22 #x24 #x38 #x24 #x22 #x21 #x21 #x21)
      ;; L
      (76 8 1 9 6 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; M
      (77 8 1 9 6 #x21 #x33 #x2d #x2d #x21 #x21 #x21 #x21 #x21)
      ;; N
      (78 8 1 9 6 #x21 #x21 #x31 #x29 #x25 #x23 #x21 #x21 #x21)
      ;; O
      (79 8 1 9 6 #x1e #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; P
      (80 8 1 9 6 #x3e #x21 #x21 #x21 #x3e #x20 #x20 #x20 #x20)
      ;; Q
      (81 8 1 9 6 #x1e #x21 #x21 #x21 #x21 #x21 #x25 #x22 #x1d)
      ;; R
      (82 8 1 9 6 #x3e #x21 #x21 #x21 #x3e #x24 #x22 #x21 #x21)
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
      (96 8 4 10 3 #x6 #x6 #x6 #x3)
      ;; a
      (97 8 1 7 7 #x3c #x2 #x3e #x42 #x42 #x46 #x3b)
      ;; b
      (98 8 1 9 6 #x20 #x20 #x2e #x31 #x21 #x21 #x21 #x21 #x3e)
      ;; c
      (99 8 1 7 6 #x1e #x21 #x20 #x20 #x20 #x21 #x1e)
      ;; d
      (100 8 1 9 6 #x1 #x1 #x1d #x23 #x21 #x21 #x21 #x21 #x1f)
      ;; e
      (101 8 1 7 6 #x1e #x21 #x21 #x3e #x20 #x21 #x1e)
      ;; f
      (102 8 1 9 5 #x7 #x8 #x8 #x1e #x8 #x8 #x8 #x8 #x8)
      ;; g
      (103 8 1 7 6 #x1d #x23 #x21 #x21 #x21 #x1f #x1 #x21 #x1e)
      ;; h
      (104 8 1 9 6 #x20 #x20 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; i
      (105 8 2 9 5 #x4 #x0 #x1c #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; j
      (106 8 1 9 5 #x1 #x0 #x3 #x1 #x1 #x1 #x1 #x1 #x11 #x11 #xe)
      ;; k
      (107 8 1 9 6 #x20 #x20 #x21 #x22 #x24 #x38 #x24 #x22 #x21)
      ;; l
      (108 8 2 9 3 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; m
      (109 8 1 7 6 #x36 #x2d #x2d #x29 #x21 #x21 #x21)
      ;; n
      (110 8 1 7 6 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; o
      (111 8 1 7 6 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; p
      (112 8 1 7 6 #x2e #x31 #x21 #x21 #x21 #x21 #x3e #x20 #x20)
      ;; q
      (113 8 1 7 6 #x1d #x23 #x21 #x21 #x21 #x21 #x1f #x1 #x1)
      ;; r
      (114 8 1 7 6 #x2e #x31 #x20 #x20 #x20 #x20 #x20)
      ;; s
      (115 8 1 7 6 #x1e #x21 #x20 #x1e #x1 #x21 #x1e)
      ;; t
      (116 8 1 9 6 #x10 #x10 #x3e #x10 #x10 #x10 #x10 #x11 #xe)
      ;; u
      (117 8 1 7 6 #x21 #x21 #x21 #x21 #x21 #x21 #x1f)
      ;; v
      (118 8 1 7 6 #x21 #x21 #x21 #x21 #x12 #x12 #xc)
      ;; w
      (119 8 1 7 6 #x21 #x21 #x21 #x21 #x2d #x2d #x1a)
      ;; x
      (120 8 1 7 6 #x21 #x21 #x12 #xc #x12 #x21 #x21)
      ;; y
      (121 8 1 7 6 #x21 #x21 #x21 #x21 #x23 #x1d #x1 #x21 #x1e)
      ;; z
      (122 8 1 7 6 #x3f #x1 #x2 #x1e #x10 #x20 #x3f)
      ;; {
      (123 8 2 10 4 #x3 #x4 #x4 #x4 #x4 #x8 #x4 #x4 #x4 #x4 #x3)
      ;; |
      (124 8 4 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; }
      (125 8 2 10 4 #xc #x2 #x2 #x2 #x2 #x1 #x2 #x2 #x2 #x2 #xc)
      ;; ~
      (126 8 1 10 6 #x19 #x26)
      ;; ¬
      (172 8 1 5 6 #x3f #x1 #x1)
      ;; °
      (176 8 2 9 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 8 2 7 5 #x4 #x4 #x1f #x4 #x4 #x1f)
      ;; µ
      (181 8 1 7 6 #x21 #x21 #x21 #x21 #x21 #x21 #x1f #x20 #x20)
      ;; ·
      (183 8 3 6 3 #x7 #x7 #x7)
      ;; À
      (192 8 1 10 6 #x8 #x4 #x0 #x1e #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Á
      (193 8 1 10 6 #x4 #x8 #x0 #x1e #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Â
      (194 8 1 10 6 #x8 #x14 #x0 #x1e #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Ã
      (195 8 1 10 6 #xa #x14 #x0 #x1e #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Ä
      (196 8 1 10 6 #x14 #x0 #x1e #x21 #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Å
      (197 8 1 10 6 #x8 #x14 #x8 #x1e #x21 #x3f #x21 #x21 #x21 #x21)
      ;; Ç
      (199 8 1 9 6 #x1e #x21 #x21 #x20 #x20 #x20 #x21 #x21 #x1e #x4 #x8)
      ;; È
      (200 8 1 10 6 #x8 #x4 #x0 #x3f #x20 #x3e #x20 #x20 #x20 #x3f)
      ;; É
      (201 8 1 10 6 #x4 #x8 #x0 #x3f #x20 #x3e #x20 #x20 #x20 #x3f)
      ;; Ê
      (202 8 1 10 6 #x8 #x14 #x0 #x3f #x20 #x3e #x20 #x20 #x20 #x3f)
      ;; Ë
      (203 8 1 10 6 #x14 #x0 #x3f #x20 #x20 #x3e #x20 #x20 #x20 #x3f)
      ;; Ì
      (204 8 2 10 3 #x4 #x2 #x0 #x7 #x2 #x2 #x2 #x2 #x2 #x7)
      ;; Í
      (205 8 2 10 3 #x2 #x4 #x0 #x7 #x2 #x2 #x2 #x2 #x2 #x7)
      ;; Î
      (206 8 1 10 4 #x4 #xa #x0 #x7 #x2 #x2 #x2 #x2 #x2 #x7)
      ;; Ï
      (207 8 1 10 4 #xa #x0 #x7 #x2 #x2 #x2 #x2 #x2 #x2 #x7)
      ;; Ñ
      (209 8 1 10 6 #xa #x14 #x0 #x21 #x31 #x29 #x25 #x23 #x21 #x21)
      ;; Ò
      (210 8 1 10 6 #x8 #x4 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ó
      (211 8 1 10 6 #x4 #x8 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ô
      (212 8 1 10 6 #x8 #x14 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Õ
      (213 8 1 10 6 #xa #x14 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ö
      (214 8 1 10 6 #x14 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ×
      (215 8 1 7 6 #x21 #x21 #x12 #xc #x12 #x21 #x21)
      ;; Ù
      (217 8 1 10 6 #x8 #x4 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ú
      (218 8 1 10 6 #x4 #x8 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Û
      (219 8 1 10 6 #x8 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ü
      (220 8 1 10 6 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ý
      (221 8 1 10 5 #x4 #x8 #x0 #x11 #xa #x4 #x4 #x4 #x4 #x4)
      ;; à
      (224 8 1 10 7 #x10 #x8 #x0 #x3c #x2 #x3e #x42 #x42 #x46 #x3b)
      ;; á
      (225 8 1 10 7 #x8 #x10 #x0 #x3c #x2 #x3e #x42 #x42 #x46 #x3b)
      ;; â
      (226 8 1 10 7 #x10 #x28 #x0 #x3c #x2 #x3e #x42 #x42 #x46 #x3b)
      ;; ã
      (227 8 1 10 7 #x14 #x28 #x0 #x3c #x2 #x3e #x42 #x42 #x46 #x3b)
      ;; ä
      (228 8 1 9 7 #x28 #x0 #x3c #x2 #x3e #x42 #x42 #x46 #x3b)
      ;; å
      (229 8 1 10 7 #x10 #x28 #x10 #x0 #x3c #x2 #x3e #x42 #x46 #x3b)
      ;; ç
      (231 8 1 7 6 #x1e #x21 #x20 #x20 #x20 #x21 #x1e #x4 #x8)
      ;; è
      (232 8 1 10 6 #x8 #x4 #x0 #x1e #x21 #x21 #x3e #x20 #x21 #x1e)
      ;; é
      (233 8 1 10 6 #x4 #x8 #x0 #x1e #x21 #x21 #x3e #x20 #x21 #x1e)
      ;; ê
      (234 8 1 10 6 #x8 #x14 #x0 #x1e #x21 #x21 #x3e #x20 #x21 #x1e)
      ;; ë
      (235 8 1 9 6 #x14 #x0 #x1e #x21 #x21 #x3e #x20 #x21 #x1e)
      ;; ì
      (236 8 2 10 5 #x8 #x4 #x0 #x1c #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; í
      (237 8 2 10 5 #x4 #x8 #x0 #x1c #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; î
      (238 8 2 10 5 #x8 #x14 #x0 #x1c #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; ï
      (239 8 2 9 5 #x14 #x0 #x1c #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; ñ
      (241 8 1 10 6 #xa #x14 #x0 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; ò
      (242 8 1 10 6 #x8 #x4 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ó
      (243 8 1 10 6 #x4 #x8 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ô
      (244 8 1 10 6 #x8 #x14 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; õ
      (245 8 1 10 6 #xa #x14 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ö
      (246 8 1 9 6 #x14 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ù
      (249 8 1 10 6 #x8 #x4 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1f)
      ;; ú
      (250 8 1 10 6 #x4 #x8 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1f)
      ;; û
      (251 8 1 10 6 #x8 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1f)
      ;; ü
      (252 8 1 9 6 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1f)
      ;; ý
      (253 8 1 10 6 #x4 #x8 #x0 #x21 #x21 #x21 #x21 #x23 #x1d #x1 #x21 #x1e)
      ;; ÿ
      (255 8 1 9 6 #x14 #x0 #x21 #x21 #x21 #x21 #x23 #x1d #x1 #x21 #x1e)
      ;; α
      (945 8 1 6 6 #x1d #x22 #x22 #x22 #x22 #x1d)
      ;; β
      (946 8 0 8 7 #x1e #x21 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x40)
      ;; γ
      (947 8 2 8 5 #x11 #xa #x4 #xa #x11 #x11 #x11 #xe)
      ;; δ
      (948 8 2 9 5 #x6 #x9 #x8 #x4 #x6 #x9 #x11 #x11 #xe)
      ;; ε
      (949 8 2 6 4 #x7 #x8 #xf #x8 #x7)
      ;; λ
      (955 8 1 9 6 #x10 #x10 #x8 #x8 #x4 #xa #x12 #x21 #x21)
      ;; π
      (960 8 1 6 6 #x3f #x12 #x12 #x12 #x12 #x12)
      ;; –
      (8211 8 1 5 6 #x3f)
      ;; —
      (8212 8 0 5 8 #xff)
      ;; ‘
      (8216 8 2 10 3 #x3 #x3 #x3 #x6)
      ;; ’
      (8217 8 2 10 3 #x3 #x3 #x3 #x6)
      ;; “
      (8220 8 3 10 3 #x5 #x5 #x5 #x5)
      ;; ”
      (8221 8 3 10 3 #x5 #x5 #x5 #x5)
      ;; …
      (8230 8 0 2 8 #xdb #xdb)
      ;; ←
      (8592 8 1 7 6 #x8 #x10 #x3f #x10 #x8)
      ;; ↑
      (8593 8 2 8 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 8 1 7 6 #x4 #x2 #x3f #x2 #x4)
      ;; ↓
      (8595 8 2 8 5 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 8 1 9 6 #x4 #x2 #x3f #x2 #x4 #x8 #x10 #x3f #x10 #x8)
      ;; ↳
      (8627 8 1 9 6 #x20 #x20 #x24 #x22 #x3f #x2 #x4)
      ;; ∀
      (8704 8 1 9 6 #x21 #x21 #x21 #x21 #x3f #x21 #x12 #x12 #xc)
      ;; ∂
      (8706 8 2 9 5 #xc #x2 #x1 #x1 #xf #x11 #x11 #x11 #xe)
      ;; ∃
      (8707 8 1 9 6 #x3f #x1 #x1 #x1 #x1f #x1 #x1 #x1 #x3f)
      ;; −
      (8722 8 2 5 5 #x1f)
      ;; ∞
      (8734 8 1 7 7 #x36 #x49 #x49 #x49 #x36)
      ;; ∧
      (8743 8 1 6 6 #xc #x12 #x21)
      ;; ∨
      (8744 8 1 6 6 #x21 #x12 #xc)
      ;; ∩
      (8745 8 2 7 5 #xe #x11 #x11 #x11 #x11)
      ;; ∪
      (8746 8 2 7 5 #x11 #x11 #x11 #x11 #xe)
      ;; ∫
      (8747 8 2 9 5 #x3 #x5 #x5 #x4 #x4 #x4 #x4 #x14 #x14 #x18)
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
      (8853 8 1 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 8 1 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 8 3 6 3 #x7 #x7 #x7)
      ;; ▶
      (9654 8 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 8 2 8 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ◊
      (9674 8 2 8 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ⚙
      (9881 8 0 9 9 #x10 #xfe #xfe #xee #x1c7 #xee #xfe #xfe #x10)
      ;; ⚠
      (9888 8 0 10 7 #x8 #x8 #x14 #x14 #x1c #x2a #x2a #x22 #x49 #x7f)
      ;; ✓
      (10003 8 1 8 6 #x1 #x1 #x2 #x2 #x24 #x14 #x18 #x8)
      ;; ❚
      (10074 8 3 9 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("CADR CPTFONT Bold" 12 10 2
      ;; the slug, which a character the face lacks draws
      (#f 9 1 9 7 #x7f #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x7f)
      ;; space
      (32 9)
      ;; !
      (33 9 4 9 2 #x3 #x3 #x3 #x3 #x3 #x3 #x0 #x3 #x3)
      ;; "
      (34 9 2 10 5 #x1b #x1b #x1b #x1b)
      ;; #
      (35 9 1 9 7 #x36 #x36 #x7f #x36 #x36 #x7f #x36 #x36 #x36)
      ;; $
      (36 9 2 10 6 #xc #x1e #x3f #x3c #x1e #xf #x3f #x3f #x1e #xc)
      ;; %
      (37 9 1 9 7 #x3f #x73 #x73 #x6 #xc #x18 #x30 #x67 #x67)
      ;; &
      (38 9 1 9 7 #x38 #x6c #x6c #x78 #x31 #x7b #x6e #x6e #x3b)
      ;; '
      (39 9 3 10 3 #x7 #x7 #x3 #x6)
      ;; (
      (40 9 3 10 4 #x3 #x6 #x6 #xc #xc #xc #xc #xc #x6 #x6 #x3)
      ;; )
      (41 9 3 10 4 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc)
      ;; *
      (42 9 1 8 8 #x18 #x5a #x3c #xff #x3c #x5a #x18)
      ;; +
      (43 9 2 7 6 #xc #xc #x3f #xc #xc)
      ;; ,
      (44 9 3 2 3 #x7 #x7 #x3 #x6)
      ;; -
      (45 9 1 5 7 #x7f #x7f)
      ;; .
      (46 9 3 2 3 #x7 #x7)
      ;; /
      (47 9 1 8 7 #x3 #x7 #xe #x1c #x38 #x70 #x60)
      ;; 0
      (48 9 1 9 7 #x3e #x63 #x63 #x67 #x6f #x7b #x73 #x63 #x3e)
      ;; 1
      (49 9 2 9 4 #x6 #xe #x6 #x6 #x6 #x6 #x6 #x6 #xf)
      ;; 2
      (50 9 1 9 7 #x3e #x63 #x63 #x3 #x1e #x30 #x60 #x60 #x7f)
      ;; 3
      (51 9 1 9 7 #x3e #x63 #x63 #x3 #x1e #x3 #x63 #x63 #x3e)
      ;; 4
      (52 9 1 9 7 #xe #x1e #x36 #x66 #x66 #x7f #x6 #x6 #x6)
      ;; 5
      (53 9 1 9 7 #x7f #x60 #x60 #x7e #x3 #x3 #x3 #x63 #x3e)
      ;; 6
      (54 9 1 9 7 #x3e #x60 #x60 #x7e #x63 #x63 #x63 #x63 #x3e)
      ;; 7
      (55 9 1 9 7 #x7f #x3 #x3 #x6 #xe #xc #x18 #x18 #x18)
      ;; 8
      (56 9 1 9 7 #x3e #x63 #x63 #x63 #x3e #x63 #x63 #x63 #x3e)
      ;; 9
      (57 9 1 9 7 #x3e #x63 #x63 #x63 #x3f #x3 #x3 #x6 #x3c)
      ;; :
      (58 9 3 6 3 #x7 #x7 #x0 #x0 #x7 #x7)
      ;; ;
      (59 9 3 6 3 #x7 #x7 #x0 #x0 #x7 #x7 #x3 #x6)
      ;; <
      (60 9 2 8 5 #x3 #x6 #xc #x18 #xc #x6 #x3)
      ;; =
      (61 9 1 6 7 #x7f #x7f #x0 #x7f #x7f)
      ;; >
      (62 9 2 8 5 #x18 #xc #x6 #x3 #x6 #xc #x18)
      ;; ?
      (63 9 1 9 7 #x3e #x63 #x63 #xe #x1c #x18 #x0 #x18 #x18)
      ;; @
      (64 9 1 8 7 #x1e #x33 #x6f #x7b #x7b #x6e #x31 #x1e)
      ;; A
      (65 9 1 9 7 #x3e #x63 #x63 #x63 #x7f #x63 #x63 #x63 #x63)
      ;; B
      (66 9 1 9 7 #x7e #x63 #x63 #x63 #x7e #x63 #x63 #x63 #x7e)
      ;; C
      (67 9 1 9 7 #x3e #x63 #x63 #x60 #x60 #x60 #x63 #x63 #x3e)
      ;; D
      (68 9 1 9 7 #x7e #x33 #x33 #x33 #x33 #x33 #x33 #x33 #x7e)
      ;; E
      (69 9 1 9 7 #x7f #x60 #x60 #x60 #x7e #x60 #x60 #x60 #x7f)
      ;; F
      (70 9 1 9 7 #x7f #x60 #x60 #x60 #x7e #x60 #x60 #x60 #x60)
      ;; G
      (71 9 1 9 7 #x3e #x63 #x63 #x60 #x6f #x63 #x63 #x63 #x3e)
      ;; H
      (72 9 1 9 7 #x63 #x63 #x63 #x63 #x7f #x63 #x63 #x63 #x63)
      ;; I
      (73 9 3 9 4 #xf #x6 #x6 #x6 #x6 #x6 #x6 #x6 #xf)
      ;; J
      (74 9 1 9 6 #x3 #x3 #x3 #x3 #x3 #x3 #x33 #x33 #x1e)
      ;; K
      (75 9 1 9 7 #x63 #x66 #x6c #x78 #x6c #x66 #x63 #x63 #x63)
      ;; L
      (76 9 1 9 7 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x60 #x7f)
      ;; M
      (77 9 1 9 7 #x63 #x77 #x7f #x7f #x63 #x63 #x63 #x63 #x63)
      ;; N
      (78 9 1 9 7 #x63 #x63 #x73 #x7b #x6f #x67 #x63 #x63 #x63)
      ;; O
      (79 9 1 9 7 #x3e #x63 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; P
      (80 9 1 9 7 #x7e #x63 #x63 #x63 #x7e #x60 #x60 #x60 #x60)
      ;; Q
      (81 9 1 9 7 #x3e #x63 #x63 #x63 #x63 #x63 #x6f #x66 #x3f)
      ;; R
      (82 9 1 9 7 #x7e #x63 #x63 #x63 #x7e #x6c #x66 #x63 #x63)
      ;; S
      (83 9 1 9 7 #x3e #x63 #x60 #x60 #x3e #x3 #x63 #x63 #x3e)
      ;; T
      (84 9 1 9 6 #x3f #xc #xc #xc #xc #xc #xc #xc #xc)
      ;; U
      (85 9 1 9 7 #x63 #x63 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; V
      (86 9 1 9 7 #x63 #x63 #x63 #x63 #x63 #x36 #x36 #x36 #x1c)
      ;; W
      (87 9 1 9 7 #x63 #x63 #x63 #x63 #x63 #x6f #x7f #x77 #x63)
      ;; X
      (88 9 1 9 7 #x63 #x63 #x63 #x36 #x1c #x36 #x63 #x63 #x63)
      ;; Y
      (89 9 1 9 6 #x33 #x33 #x33 #x1e #xc #xc #xc #xc #xc)
      ;; Z
      (90 9 1 9 7 #x7f #x3 #x6 #xc #x3e #x18 #x30 #x60 #x7f)
      ;; [
      (91 9 3 10 5 #x1f #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x1f)
      ;; \
      (92 9 1 8 7 #x60 #x70 #x38 #x1c #xe #x7 #x3)
      ;; ]
      (93 9 1 10 5 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x1f)
      ;; ^
      (94 9 1 10 7 #x1c #x36 #x63)
      ;; _
      (95 9 1 0 7 #x7f #x7f)
      ;; `
      (96 9 3 10 3 #x7 #x7 #x6 #x3)
      ;; a
      (97 9 1 7 8 #x7c #x6 #x7e #xc6 #xc6 #xce #x7b)
      ;; b
      (98 9 1 9 7 #x60 #x60 #x7e #x73 #x63 #x63 #x63 #x63 #x7e)
      ;; c
      (99 9 1 7 7 #x3e #x63 #x60 #x60 #x60 #x63 #x3e)
      ;; d
      (100 9 1 9 7 #x3 #x3 #x3f #x67 #x63 #x63 #x63 #x63 #x3f)
      ;; e
      (101 9 1 7 7 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; f
      (102 9 1 9 7 #xf #x18 #x18 #x7e #x18 #x18 #x18 #x18 #x18)
      ;; g
      (103 9 1 7 7 #x3f #x67 #x63 #x63 #x63 #x3f #x3 #x63 #x3e)
      ;; h
      (104 9 1 9 7 #x60 #x60 #x7e #x73 #x63 #x63 #x63 #x63 #x63)
      ;; i
      (105 9 2 9 6 #xc #x0 #x3c #xc #xc #xc #xc #xc #x3f)
      ;; j
      (106 9 1 9 6 #x3 #x0 #x7 #x3 #x3 #x3 #x3 #x3 #x33 #x33 #x1e)
      ;; k
      (107 9 1 9 7 #x60 #x60 #x63 #x66 #x6c #x78 #x6c #x66 #x63)
      ;; l
      (108 9 2 9 4 #xf #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; m
      (109 9 1 7 7 #x7e #x7f #x7f #x6b #x63 #x63 #x63)
      ;; n
      (110 9 1 7 7 #x7e #x73 #x63 #x63 #x63 #x63 #x63)
      ;; o
      (111 9 1 7 7 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; p
      (112 9 1 7 7 #x7e #x73 #x63 #x63 #x63 #x63 #x7e #x60 #x60)
      ;; q
      (113 9 1 7 7 #x3f #x67 #x63 #x63 #x63 #x63 #x3f #x3 #x3)
      ;; r
      (114 9 1 7 7 #x7e #x73 #x60 #x60 #x60 #x60 #x60)
      ;; s
      (115 9 1 7 7 #x3e #x63 #x60 #x3e #x3 #x63 #x3e)
      ;; t
      (116 9 1 9 7 #x30 #x30 #x7e #x30 #x30 #x30 #x30 #x33 #x1e)
      ;; u
      (117 9 1 7 7 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; v
      (118 9 1 7 7 #x63 #x63 #x63 #x63 #x36 #x36 #x1c)
      ;; w
      (119 9 1 7 7 #x63 #x63 #x63 #x63 #x6b #x7f #x3e)
      ;; x
      (120 9 1 7 7 #x63 #x63 #x36 #x1c #x36 #x63 #x63)
      ;; y
      (121 9 1 7 7 #x63 #x63 #x63 #x63 #x67 #x3f #x3 #x63 #x3e)
      ;; z
      (122 9 1 7 7 #x7f #x3 #x6 #x3e #x30 #x60 #x7f)
      ;; {
      (123 9 2 10 5 #x7 #xc #xc #xc #xc #x18 #xc #xc #xc #xc #x7)
      ;; |
      (124 9 4 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; }
      (125 9 2 10 5 #x1c #x6 #x6 #x6 #x6 #x3 #x6 #x6 #x6 #x6 #x1c)
      ;; ~
      (126 9 1 10 7 #x3b #x6e)
      ;; ¬
      (172 9 1 5 7 #x7f #x3 #x3)
      ;; °
      (176 9 2 9 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 2 7 6 #xc #xc #x3f #xc #xc #x3f)
      ;; µ
      (181 9 1 7 7 #x63 #x63 #x63 #x63 #x63 #x63 #x3f #x60 #x60)
      ;; ·
      (183 9 3 6 4 #xf #xf #xf)
      ;; À
      (192 9 1 10 7 #x30 #x18 #x0 #x3e #x63 #x7f #x63 #x63 #x63 #x63)
      ;; Á
      (193 9 1 10 7 #x18 #x30 #x0 #x3e #x63 #x7f #x63 #x63 #x63 #x63)
      ;; Â
      (194 9 1 10 7 #x18 #x3c #x0 #x3e #x63 #x7f #x63 #x63 #x63 #x63)
      ;; Ã
      (195 9 1 10 7 #x3c #x78 #x0 #x3e #x63 #x7f #x63 #x63 #x63 #x63)
      ;; Ä
      (196 9 1 10 7 #x3c #x0 #x3e #x63 #x63 #x7f #x63 #x63 #x63 #x63)
      ;; Å
      (197 9 1 10 7 #x18 #x3c #x18 #x3e #x63 #x7f #x63 #x63 #x63 #x63)
      ;; Ç
      (199 9 1 9 7 #x3e #x63 #x63 #x60 #x60 #x60 #x63 #x63 #x3e #x18 #x30)
      ;; È
      (200 9 1 10 7 #x30 #x18 #x0 #x7f #x60 #x7e #x60 #x60 #x60 #x7f)
      ;; É
      (201 9 1 10 7 #x18 #x30 #x0 #x7f #x60 #x7e #x60 #x60 #x60 #x7f)
      ;; Ê
      (202 9 1 10 7 #x18 #x3c #x0 #x7f #x60 #x7e #x60 #x60 #x60 #x7f)
      ;; Ë
      (203 9 1 10 7 #x3c #x0 #x7f #x60 #x60 #x7e #x60 #x60 #x60 #x7f)
      ;; Ì
      (204 9 3 10 4 #xc #x6 #x0 #xf #x6 #x6 #x6 #x6 #x6 #xf)
      ;; Í
      (205 9 3 10 4 #x6 #xc #x0 #xf #x6 #x6 #x6 #x6 #x6 #xf)
      ;; Î
      (206 9 3 10 4 #x6 #xf #x0 #xf #x6 #x6 #x6 #x6 #x6 #xf)
      ;; Ï
      (207 9 3 10 4 #xf #x0 #xf #x6 #x6 #x6 #x6 #x6 #x6 #xf)
      ;; Ñ
      (209 9 1 10 7 #x3c #x78 #x0 #x63 #x73 #x7b #x6f #x67 #x63 #x63)
      ;; Ò
      (210 9 1 10 7 #x30 #x18 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Ó
      (211 9 1 10 7 #x18 #x30 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Ô
      (212 9 1 10 7 #x18 #x3c #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Õ
      (213 9 1 10 7 #x3c #x78 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Ö
      (214 9 1 10 7 #x3c #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ×
      (215 9 1 7 7 #x63 #x63 #x36 #x1c #x36 #x63 #x63)
      ;; Ù
      (217 9 1 10 7 #x30 #x18 #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Ú
      (218 9 1 10 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Û
      (219 9 1 10 7 #x18 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Ü
      (220 9 1 10 7 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Ý
      (221 9 1 10 6 #xc #x18 #x0 #x33 #x1e #xc #xc #xc #xc #xc)
      ;; à
      (224 9 1 10 8 #x30 #x18 #x0 #x7c #x6 #x7e #xc6 #xc6 #xce #x7b)
      ;; á
      (225 9 1 10 8 #x18 #x30 #x0 #x7c #x6 #x7e #xc6 #xc6 #xce #x7b)
      ;; â
      (226 9 1 10 8 #x18 #x3c #x0 #x7c #x6 #x7e #xc6 #xc6 #xce #x7b)
      ;; ã
      (227 9 1 10 8 #x3c #x78 #x0 #x7c #x6 #x7e #xc6 #xc6 #xce #x7b)
      ;; ä
      (228 9 1 9 8 #x3c #x0 #x7c #x6 #x7e #xc6 #xc6 #xce #x7b)
      ;; å
      (229 9 1 10 8 #x18 #x3c #x18 #x0 #x7c #x6 #x7e #xc6 #xce #x7b)
      ;; ç
      (231 9 1 7 7 #x3e #x63 #x60 #x60 #x60 #x63 #x3e #x18 #x30)
      ;; è
      (232 9 1 10 7 #x30 #x18 #x0 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; é
      (233 9 1 10 7 #x18 #x30 #x0 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; ê
      (234 9 1 10 7 #x18 #x3c #x0 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; ë
      (235 9 1 9 7 #x3c #x0 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; ì
      (236 9 2 10 6 #x18 #xc #x0 #x3c #xc #xc #xc #xc #xc #x3f)
      ;; í
      (237 9 2 10 6 #xc #x18 #x0 #x3c #xc #xc #xc #xc #xc #x3f)
      ;; î
      (238 9 2 10 6 #xc #x1e #x0 #x3c #xc #xc #xc #xc #xc #x3f)
      ;; ï
      (239 9 2 9 6 #x1e #x0 #x3c #xc #xc #xc #xc #xc #x3f)
      ;; ñ
      (241 9 1 10 7 #x3c #x78 #x0 #x7e #x73 #x63 #x63 #x63 #x63 #x63)
      ;; ò
      (242 9 1 10 7 #x30 #x18 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ó
      (243 9 1 10 7 #x18 #x30 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ô
      (244 9 1 10 7 #x18 #x3c #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; õ
      (245 9 1 10 7 #x3c #x78 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ö
      (246 9 1 9 7 #x3c #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ù
      (249 9 1 10 7 #x30 #x18 #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; ú
      (250 9 1 10 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; û
      (251 9 1 10 7 #x18 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; ü
      (252 9 1 9 7 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; ý
      (253 9 1 10 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x67 #x3f #x3 #x63 #x3e)
      ;; ÿ
      (255 9 1 9 7 #x3c #x0 #x63 #x63 #x63 #x63 #x67 #x3f #x3 #x63 #x3e)
      ;; α
      (945 9 1 6 7 #x3f #x66 #x66 #x66 #x66 #x3f)
      ;; β
      (946 9 0 8 8 #x3e #x63 #x63 #x7e #x63 #x63 #x63 #x7e #x60 #xc0)
      ;; γ
      (947 9 2 8 6 #x33 #x1e #xc #x1e #x33 #x33 #x33 #x1e)
      ;; δ
      (948 9 2 9 6 #xe #x1b #x18 #xc #xe #x1b #x33 #x33 #x1e)
      ;; ε
      (949 9 2 6 5 #xf #x18 #x1f #x18 #xf)
      ;; λ
      (955 9 1 9 7 #x30 #x30 #x18 #x18 #xc #x1e #x36 #x63 #x63)
      ;; π
      (960 9 1 6 7 #x7f #x36 #x36 #x36 #x36 #x36)
      ;; –
      (8211 9 1 5 7 #x7f #x7f)
      ;; —
      (8212 9 0 5 9 #x1ff #x1ff)
      ;; ‘
      (8216 9 3 10 3 #x7 #x7 #x3 #x6)
      ;; ’
      (8217 9 3 10 3 #x7 #x7 #x3 #x6)
      ;; “
      (8220 9 2 10 5 #x1b #x1b #x1b #x1b)
      ;; ”
      (8221 9 2 10 5 #x1b #x1b #x1b #x1b)
      ;; …
      (8230 9 0 2 9 #x1ff #x1ff)
      ;; ←
      (8592 9 1 7 7 #x18 #x30 #x7f #x30 #x18)
      ;; ↑
      (8593 9 2 8 6 #xc #x1e #x3f #xc #xc #xc #xc #xc)
      ;; →
      (8594 9 1 7 7 #xc #x6 #x7f #x6 #xc)
      ;; ↓
      (8595 9 2 8 6 #xc #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↔
      (8596 9 1 9 7 #xc #x6 #x7f #x6 #xc #x18 #x30 #x7f #x30 #x18)
      ;; ↳
      (8627 9 1 9 7 #x60 #x60 #x6c #x66 #x7f #x6 #xc)
      ;; ∀
      (8704 9 1 9 7 #x63 #x63 #x63 #x63 #x7f #x63 #x36 #x36 #x1c)
      ;; ∂
      (8706 9 2 9 6 #x1c #x6 #x3 #x3 #x1f #x33 #x33 #x33 #x1e)
      ;; ∃
      (8707 9 1 9 7 #x7f #x3 #x3 #x3 #x3f #x3 #x3 #x3 #x7f)
      ;; −
      (8722 9 2 5 6 #x3f)
      ;; ∞
      (8734 9 1 7 8 #x7e #xdb #xdb #xdb #x7e)
      ;; ∧
      (8743 9 1 6 7 #x1c #x36 #x63)
      ;; ∨
      (8744 9 1 6 7 #x63 #x36 #x1c)
      ;; ∩
      (8745 9 2 7 6 #x1e #x33 #x33 #x33 #x33)
      ;; ∪
      (8746 9 2 7 6 #x33 #x33 #x33 #x33 #x1e)
      ;; ∫
      (8747 9 2 9 6 #x6 #xf #xd #xc #xc #xc #xc #x2c #x3c #x18)
      ;; ≠
      (8800 9 1 8 7 #x3 #x6 #x7f #xc #x18 #x7f #x30 #x60)
      ;; ≡
      (8801 9 1 7 7 #x7f #x0 #x7f #x0 #x7f)
      ;; ≤
      (8804 9 2 9 5 #x3 #x6 #xc #x18 #xc #x6 #x3 #x0 #x1f)
      ;; ≥
      (8805 9 2 9 5 #x18 #xc #x6 #x3 #x6 #xc #x18 #x0 #x1f)
      ;; ⊂
      (8834 9 1 7 7 #x3f #x60 #x60 #x60 #x3f)
      ;; ⊃
      (8835 9 1 7 7 #x7e #x3 #x3 #x3 #x7e)
      ;; ⊕
      (8853 9 1 8 8 #x3c #x7e #xdb #xff #xdb #x7e #x3c)
      ;; ⊗
      (8855 9 1 8 8 #x3c #x66 #xff #xdb #xff #x66 #x3c)
      ;; ⋅
      (8901 9 3 6 4 #xf #xf #xf)
      ;; ▶
      (9654 9 2 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 9 2 8 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ◊
      (9674 9 2 8 6 #xc #xc #x1e #x33 #x1e #xc #xc)
      ;; ⚙
      (9881 9 0 9 9 #x10 #xfe #xfe #xee #x1c7 #xee #xfe #xfe #x10)
      ;; ⚠
      (9888 9 0 10 9 #x10 #x10 #x28 #x28 #x54 #x54 #x92 #x82 #x111 #x1ff)
      ;; ✓
      (10003 9 1 8 7 #x3 #x3 #x6 #x6 #x6c #x3c #x38 #x18)
      ;; ❚
      (10074 9 2 9 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("CADR MEDFNT" 13 11 2
      ;; the slug, which a character the face lacks draws
      (#f 9 1 11 7 #x7f #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x7f)
      ;; space
      (32 9)
      ;; !
      (33 9 3 11 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x0 #x1 #x1)
      ;; "
      (34 9 2 11 4 #x9 #x9 #x9 #x9)
      ;; #
      (35 9 0 9 7 #x22 #x22 #x7f #x22 #x22 #x7f #x22 #x22)
      ;; $
      (36 9 0 11 7 #x8 #x3e #x6b #x48 #x68 #x3e #xb #x9 #x6b #x3e #x8)
      ;; %
      (37 9 0 11 7 #x30 #x48 #x49 #x32 #x4 #x8 #x10 #x26 #x49 #x9 #x6)
      ;; &
      (38 9 0 11 7 #x18 #x24 #x44 #x44 #x48 #x30 #x30 #x48 #x45 #x42 #x3d)
      ;; '
      (39 9 2 11 4 #x3 #x6 #xc)
      ;; (
      (40 9 2 11 3 #x1 #x2 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x2 #x1)
      ;; )
      (41 9 2 11 3 #x4 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x4)
      ;; *
      (42 9 0 8 7 #x8 #x2a #x14 #x7f #x14 #x2a #x8)
      ;; +
      (43 9 0 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8)
      ;; ,
      (44 9 2 2 3 #x3 #x3 #x2 #x4)
      ;; -
      (45 9 0 5 7 #x7f)
      ;; .
      (46 9 3 2 2 #x3 #x3)
      ;; /
      (47 9 1 11 6 #x1 #x1 #x2 #x2 #x4 #x4 #x8 #x8 #x10 #x10 #x20 #x20)
      ;; 0
      (48 9 0 11 7 #x1c #x22 #x41 #x43 #x45 #x49 #x51 #x61 #x41 #x22 #x1c)
      ;; 1
      (49 9 1 11 5 #x4 #xc #x14 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; 2
      (50 9 0 11 7 #x3e #x41 #x1 #x1 #x2 #x1c #x20 #x40 #x40 #x40 #x7f)
      ;; 3
      (51 9 0 11 7 #x3e #x41 #x1 #x1 #x1 #x3e #x1 #x1 #x1 #x41 #x3e)
      ;; 4
      (52 9 0 11 7 #x4 #xc #x14 #x24 #x44 #x7f #x4 #x4 #x4 #x4 #x4)
      ;; 5
      (53 9 0 11 7 #x7f #x40 #x40 #x40 #x40 #x7e #x1 #x1 #x1 #x41 #x3e)
      ;; 6
      (54 9 0 11 7 #x1e #x20 #x40 #x40 #x40 #x7e #x41 #x41 #x41 #x41 #x3e)
      ;; 7
      (55 9 0 11 7 #x7f #x1 #x1 #x1 #x2 #x3f #x8 #x10 #x10 #x10 #x10)
      ;; 8
      (56 9 0 11 7 #x3e #x41 #x41 #x41 #x41 #x3e #x41 #x41 #x41 #x41 #x3e)
      ;; 9
      (57 9 0 11 7 #x3e #x41 #x41 #x41 #x41 #x3f #x1 #x1 #x1 #x2 #x1c)
      ;; :
      (58 9 3 6 2 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; ;
      (59 9 2 6 3 #x3 #x3 #x0 #x0 #x3 #x3 #x2 #x4)
      ;; <
      (60 9 0 9 7 #x1 #x6 #x8 #x30 #x40 #x30 #x8 #x6 #x1)
      ;; =
      (61 9 0 6 7 #x7f #x0 #x0 #x7f)
      ;; >
      (62 9 0 9 7 #x40 #x30 #x8 #x6 #x1 #x6 #x8 #x30 #x40)
      ;; ?
      (63 9 0 11 7 #x3e #x41 #x41 #x1 #x2 #x4 #x8 #x8 #x0 #x0 #x8)
      ;; @
      (64 9 0 8 7 #x3f #x41 #x5d #x55 #x5d #x47 #x40 #x3f)
      ;; A
      (65 9 0 11 7 #x3e #x41 #x41 #x41 #x41 #x7f #x41 #x41 #x41 #x41 #x41)
      ;; B
      (66 9 0 11 7 #x7e #x41 #x41 #x41 #x41 #x7e #x41 #x41 #x41 #x41 #x7e)
      ;; C
      (67 9 0 11 7 #x3e #x41 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x41 #x3e)
      ;; D
      (68 9 0 11 7 #x7c #x42 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x42 #x7c)
      ;; E
      (69 9 0 11 7 #x7f #x40 #x40 #x40 #x40 #x7c #x40 #x40 #x40 #x40 #x7f)
      ;; F
      (70 9 0 11 7 #x7f #x40 #x40 #x40 #x40 #x7c #x40 #x40 #x40 #x40 #x40)
      ;; G
      (71 9 0 11 7 #x3e #x41 #x40 #x40 #x40 #x40 #x47 #x41 #x41 #x41 #x3e)
      ;; H
      (72 9 0 11 7 #x41 #x41 #x41 #x41 #x41 #x7f #x41 #x41 #x41 #x41 #x41)
      ;; I
      (73 9 1 11 5 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; J
      (74 9 0 11 6 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x21 #x21 #x1e)
      ;; K
      (75 9 0 11 7 #x41 #x42 #x44 #x48 #x50 #x60 #x50 #x48 #x44 #x42 #x41)
      ;; L
      (76 9 0 11 7 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x7f)
      ;; M
      (77 9 0 11 7 #x41 #x63 #x55 #x49 #x49 #x49 #x41 #x41 #x41 #x41 #x41)
      ;; N
      (78 9 0 11 7 #x41 #x61 #x51 #x49 #x45 #x43 #x41 #x41 #x41 #x41 #x41)
      ;; O
      (79 9 0 11 7 #x3e #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; P
      (80 9 0 11 7 #x7e #x41 #x41 #x41 #x41 #x7e #x40 #x40 #x40 #x40 #x40)
      ;; Q
      (81 9 0 11 7 #x3e #x41 #x41 #x41 #x41 #x41 #x41 #x49 #x45 #x42 #x3d)
      ;; R
      (82 9 0 11 7 #x7e #x41 #x41 #x41 #x41 #x7e #x50 #x48 #x44 #x42 #x41)
      ;; S
      (83 9 0 11 7 #x3e #x41 #x40 #x40 #x40 #x3e #x1 #x1 #x1 #x41 #x3e)
      ;; T
      (84 9 0 11 7 #x7f #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; U
      (85 9 0 11 7 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; V
      (86 9 0 11 7 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x22 #x14 #x14 #x8)
      ;; W
      (87 9 0 11 7 #x41 #x41 #x41 #x41 #x41 #x49 #x49 #x55 #x55 #x63 #x41)
      ;; X
      (88 9 0 11 7 #x41 #x22 #x22 #x14 #x14 #x8 #x14 #x14 #x22 #x22 #x41)
      ;; Y
      (89 9 0 11 7 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; Z
      (90 9 0 11 7 #x7f #x1 #x1 #x2 #x4 #x3e #x10 #x20 #x40 #x40 #x7f)
      ;; [
      (91 9 2 11 3 #x7 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x7)
      ;; \
      (92 9 1 11 6 #x20 #x20 #x10 #x10 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ]
      (93 9 2 11 3 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x7)
      ;; ^
      (94 9 0 11 7 #x8 #x14 #x22 #x41)
      ;; _
      (95 9 0 -1 7 #x7f)
      ;; `
      (96 9 2 11 4 #xc #x6 #x3)
      ;; a
      (97 9 0 7 7 #x3e #x41 #x1 #x3f #x41 #x41 #x3f)
      ;; b
      (98 9 0 11 7 #x40 #x40 #x40 #x40 #x7e #x41 #x41 #x41 #x41 #x41 #x7e)
      ;; c
      (99 9 0 7 7 #x3e #x41 #x40 #x40 #x40 #x41 #x3e)
      ;; d
      (100 9 0 11 7 #x1 #x1 #x1 #x1 #x3f #x41 #x41 #x41 #x41 #x41 #x3f)
      ;; e
      (101 9 0 7 7 #x3e #x41 #x41 #x7e #x40 #x40 #x3f)
      ;; f
      (102 9 0 11 7 #xe #x11 #x10 #x10 #x7c #x10 #x10 #x10 #x10 #x10 #x10)
      ;; g
      (103 9 0 7 7 #x3e #x41 #x41 #x41 #x3f #x1 #x1 #x41 #x3e)
      ;; h
      (104 9 0 11 7 #x40 #x40 #x40 #x40 #x7e #x41 #x41 #x41 #x41 #x41 #x41)
      ;; i
      (105 9 3 10 1 #x1 #x0 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; j
      (106 9 1 10 4 #x1 #x0 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x9 #x6)
      ;; k
      (107 9 0 11 6 #x20 #x20 #x20 #x20 #x21 #x22 #x24 #x28 #x34 #x22 #x21)
      ;; l
      (108 9 1 11 5 #x1c #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; m
      (109 9 0 7 7 #x76 #x49 #x49 #x49 #x49 #x49 #x49)
      ;; n
      (110 9 0 7 6 #x3e #x21 #x21 #x21 #x21 #x21 #x21)
      ;; o
      (111 9 0 7 6 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; p
      (112 9 0 7 7 #x7e #x41 #x41 #x41 #x41 #x41 #x7e #x40 #x40)
      ;; q
      (113 9 0 7 7 #x3f #x41 #x41 #x41 #x41 #x41 #x3f #x1 #x1)
      ;; r
      (114 9 0 7 6 #x2f #x30 #x20 #x20 #x20 #x20 #x20)
      ;; s
      (115 9 0 7 7 #x3f #x40 #x40 #x3e #x1 #x1 #x7e)
      ;; t
      (116 9 0 10 6 #x8 #x8 #x8 #x3e #x8 #x8 #x8 #x8 #x9 #x6)
      ;; u
      (117 9 0 7 6 #x21 #x21 #x21 #x21 #x21 #x21 #x1f)
      ;; v
      (118 9 0 7 7 #x41 #x41 #x22 #x22 #x14 #x1c #x8)
      ;; w
      (119 9 0 7 7 #x41 #x41 #x41 #x49 #x55 #x63 #x41)
      ;; x
      (120 9 0 7 7 #x41 #x22 #x14 #x8 #x14 #x22 #x41)
      ;; y
      (121 9 0 7 7 #x41 #x41 #x41 #x22 #x14 #x8 #x10 #x20 #x40)
      ;; z
      (122 9 0 7 7 #x7f #x2 #x4 #x8 #x10 #x20 #x7f)
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
      (176 9 2 11 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 0 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x7f)
      ;; µ
      (181 9 0 7 6 #x21 #x21 #x21 #x21 #x21 #x21 #x1f #x20 #x20)
      ;; ·
      (183 9 2 6 4 #x6 #xf #xf #x6)
      ;; À
      (192 9 0 11 7 #x10 #x8 #x3e #x41 #x41 #x7f #x41 #x41 #x41 #x41 #x41)
      ;; Á
      (193 9 0 11 7 #x8 #x10 #x3e #x41 #x41 #x7f #x41 #x41 #x41 #x41 #x41)
      ;; Â
      (194 9 0 11 7 #x10 #x28 #x3e #x41 #x41 #x7f #x41 #x41 #x41 #x41 #x41)
      ;; Ã
      (195 9 0 11 7 #x14 #x28 #x3e #x41 #x41 #x7f #x41 #x41 #x41 #x41 #x41)
      ;; Ä
      (196 9 0 11 7 #x28 #x0 #x3e #x41 #x41 #x7f #x41 #x41 #x41 #x41 #x41)
      ;; Å
      (197 9 0 11 7 #x10 #x28 #x10 #x3e #x41 #x7f #x41 #x41 #x41 #x41 #x41)
      ;; Ç
      (199 9 0 11 7 #x3e #x41 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x41 #x3e #x8
        #x10)
      ;; È
      (200 9 0 11 7 #x10 #x8 #x7f #x40 #x40 #x7c #x40 #x40 #x40 #x40 #x7f)
      ;; É
      (201 9 0 11 7 #x8 #x10 #x7f #x40 #x40 #x7c #x40 #x40 #x40 #x40 #x7f)
      ;; Ê
      (202 9 0 11 7 #x10 #x28 #x7f #x40 #x40 #x7c #x40 #x40 #x40 #x40 #x7f)
      ;; Ë
      (203 9 0 11 7 #x28 #x0 #x7f #x40 #x40 #x7c #x40 #x40 #x40 #x40 #x7f)
      ;; Ì
      (204 9 1 11 5 #x8 #x4 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Í
      (205 9 1 11 5 #x4 #x8 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Î
      (206 9 1 11 5 #x8 #x14 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Ï
      (207 9 1 11 5 #x14 #x0 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x1f)
      ;; Ñ
      (209 9 0 11 7 #x14 #x28 #x41 #x61 #x51 #x49 #x45 #x43 #x41 #x41 #x41)
      ;; Ò
      (210 9 0 11 7 #x10 #x8 #x3e #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; Ó
      (211 9 0 11 7 #x8 #x10 #x3e #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; Ô
      (212 9 0 11 7 #x10 #x28 #x3e #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; Õ
      (213 9 0 11 7 #x14 #x28 #x3e #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; Ö
      (214 9 0 11 7 #x28 #x0 #x3e #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; ×
      (215 9 0 7 7 #x41 #x22 #x14 #x8 #x14 #x22 #x41)
      ;; Ù
      (217 9 0 11 7 #x10 #x8 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; Ú
      (218 9 0 11 7 #x8 #x10 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; Û
      (219 9 0 11 7 #x10 #x28 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; Ü
      (220 9 0 11 7 #x28 #x0 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; Ý
      (221 9 0 11 7 #x8 #x10 #x41 #x22 #x14 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; à
      (224 9 0 10 7 #x10 #x8 #x0 #x3e #x41 #x1 #x3f #x41 #x41 #x3f)
      ;; á
      (225 9 0 10 7 #x8 #x10 #x0 #x3e #x41 #x1 #x3f #x41 #x41 #x3f)
      ;; â
      (226 9 0 10 7 #x10 #x28 #x0 #x3e #x41 #x1 #x3f #x41 #x41 #x3f)
      ;; ã
      (227 9 0 10 7 #x14 #x28 #x0 #x3e #x41 #x1 #x3f #x41 #x41 #x3f)
      ;; ä
      (228 9 0 9 7 #x28 #x0 #x3e #x41 #x1 #x3f #x41 #x41 #x3f)
      ;; å
      (229 9 0 11 7 #x10 #x28 #x10 #x0 #x3e #x41 #x1 #x3f #x41 #x41 #x3f)
      ;; ç
      (231 9 0 7 7 #x3e #x41 #x40 #x40 #x40 #x41 #x3e #x8 #x10)
      ;; è
      (232 9 0 10 7 #x10 #x8 #x0 #x3e #x41 #x41 #x7e #x40 #x40 #x3f)
      ;; é
      (233 9 0 10 7 #x8 #x10 #x0 #x3e #x41 #x41 #x7e #x40 #x40 #x3f)
      ;; ê
      (234 9 0 10 7 #x10 #x28 #x0 #x3e #x41 #x41 #x7e #x40 #x40 #x3f)
      ;; ë
      (235 9 0 9 7 #x28 #x0 #x3e #x41 #x41 #x7e #x40 #x40 #x3f)
      ;; ì
      (236 9 2 10 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; í
      (237 9 2 10 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; î
      (238 9 1 10 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ï
      (239 9 1 9 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ñ
      (241 9 0 10 6 #xa #x14 #x0 #x3e #x21 #x21 #x21 #x21 #x21 #x21)
      ;; ò
      (242 9 0 10 6 #x8 #x4 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ó
      (243 9 0 10 6 #x4 #x8 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ô
      (244 9 0 10 6 #x8 #x14 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; õ
      (245 9 0 10 6 #xa #x14 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ö
      (246 9 0 9 6 #x14 #x0 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ù
      (249 9 0 10 6 #x8 #x4 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1f)
      ;; ú
      (250 9 0 10 6 #x4 #x8 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1f)
      ;; û
      (251 9 0 10 6 #x8 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1f)
      ;; ü
      (252 9 0 9 6 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1f)
      ;; ý
      (253 9 0 10 7 #x8 #x10 #x0 #x41 #x41 #x41 #x22 #x14 #x8 #x10 #x20 #x40)
      ;; ÿ
      (255 9 0 9 7 #x28 #x0 #x41 #x41 #x41 #x22 #x14 #x8 #x10 #x20 #x40)
      ;; α
      (945 9 0 8 8 #x2 #x62 #x94 #x88 #x88 #x94 #x63)
      ;; β
      (946 9 1 10 6 #xe #x11 #x11 #x21 #x3e #x21 #x21 #x21 #x3e #x20 #x20 #x20)
      ;; γ
      (947 9 0 10 8 #x1 #x2 #x74 #x88 #x14 #x24 #x44 #x44 #x48 #x30)
      ;; δ
      (948 9 0 11 7 #x1e #x20 #x20 #x20 #x10 #x8 #x14 #x22 #x41 #x41 #x3e)
      ;; ε
      (949 9 1 7 5 #x7 #x8 #x10 #x1f #x10 #x8 #x7)
      ;; λ
      (955 9 0 11 7 #x40 #x20 #x20 #x10 #x8 #x8 #x14 #x12 #x22 #x21 #x41)
      ;; π
      (960 9 0 7 7 #x7f #x22 #x22 #x22 #x22 #x22 #x22)
      ;; –
      (8211 9 1 5 7 #x7f)
      ;; —
      (8212 9 0 5 9 #x1ff)
      ;; ‘
      (8216 9 2 11 4 #x3 #x6 #xc)
      ;; ’
      (8217 9 2 11 4 #x3 #x6 #xc)
      ;; “
      (8220 9 2 11 4 #x9 #x9 #x9 #x9)
      ;; ”
      (8221 9 2 11 4 #x9 #x9 #x9 #x9)
      ;; …
      (8230 9 0 2 8 #xcf #xcf)
      ;; ←
      (8592 9 0 7 7 #x10 #x20 #x7f #x20 #x10)
      ;; ↑
      (8593 9 1 10 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 9 0 7 7 #x4 #x2 #x7f #x2 #x4)
      ;; ↓
      (8595 9 1 10 5 #x4 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 9 0 7 8 #x24 #x42 #xff #x42 #x24)
      ;; ↳
      (8627 9 0 11 7 #x40 #x40 #x40 #x40 #x44 #x42 #x7f #x2 #x4)
      ;; ∀
      (8704 9 0 11 7 #x41 #x41 #x41 #x3e #x22 #x22 #x14 #x14 #x14 #x8 #x8)
      ;; ∂
      (8706 9 1 11 6 #xc #x12 #x1 #x1 #x1 #xf #x11 #x21 #x21 #x12 #xc)
      ;; ∃
      (8707 9 0 11 7 #x7f #x1 #x1 #x1 #x1 #x3f #x1 #x1 #x1 #x1 #x7f)
      ;; −
      (8722 9 0 5 7 #x7f)
      ;; ∞
      (8734 9 0 7 7 #x36 #x49 #x49 #x49 #x49 #x36)
      ;; ∧
      (8743 9 0 6 7 #x8 #x14 #x22 #x41)
      ;; ∨
      (8744 9 0 6 7 #x41 #x22 #x14 #x8)
      ;; ∩
      (8745 9 1 8 6 #x1e #x21 #x21 #x21 #x21 #x21 #x21)
      ;; ∪
      (8746 9 1 8 6 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; ∫
      (8747 9 1 11 7 #x6 #x9 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x48 #x30)
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
      (8901 9 2 6 4 #x6 #xf #xf #x6)
      ;; ▶
      (9654 9 1 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 9 0 10 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ◊
      (9674 9 0 10 7 #x8 #x8 #x14 #x22 #x41 #x22 #x14 #x8 #x8)
      ;; ⚙
      (9881 9 0 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 9 0 12 9 #x10 #x10 #x28 #x28 #x38 #x54 #x54 #x92 #x92 #x82 #x111
        #x1ff)
      ;; ✓
      (10003 9 1 8 7 #x1 #x2 #x2 #x4 #x44 #x28 #x28 #x10)
      ;; ❚
      (10074 9 3 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("CADR MEDFNT Bold" 13 11 2
      ;; the slug, which a character the face lacks draws
      (#f 10 1 11 8 #xff #x81 #x81 #x81 #x81 #x81 #x81 #x81 #x81 #x81 #xff)
      ;; space
      (32 10)
      ;; !
      (33 10 3 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; "
      (34 10 2 11 5 #x1b #x1b #x1b #x1b)
      ;; #
      (35 10 0 9 8 #x66 #x66 #xff #x66 #x66 #xff #x66 #x66)
      ;; $
      (36 10 0 11 8 #x18 #x7e #xff #xd8 #xf8 #x7e #x1f #x1b #xff #x7e #x18)
      ;; %
      (37 10 0 11 8 #x70 #xd8 #xdb #x76 #xc #x18 #x30 #x6e #xdb #x1b #xe)
      ;; &
      (38 10 0 11 8 #x38 #x6c #xcc #xcc #xd8 #x70 #x70 #xd8 #xcd #xc6 #x7d)
      ;; '
      (39 10 2 11 5 #x7 #xe #x1c)
      ;; (
      (40 10 2 11 4 #x3 #x6 #xc #xc #xc #xc #xc #xc #xc #x6 #x3)
      ;; )
      (41 10 2 11 4 #xc #x6 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x6 #xc)
      ;; *
      (42 10 0 8 8 #x66 #x66 #x3c #xff #x3c #x66 #x66)
      ;; +
      (43 10 0 8 8 #x18 #x18 #x18 #xff #x18 #x18 #x18)
      ;; ,
      (44 10 2 2 4 #x7 #x7 #x6 #xc)
      ;; -
      (45 10 0 5 8 #xff)
      ;; .
      (46 10 3 2 3 #x7 #x7)
      ;; /
      (47 10 1 11 7 #x3 #x3 #x6 #x6 #xc #xc #x18 #x18 #x30 #x30 #x60 #x60)
      ;; 0
      (48 10 0 11 8 #x3c #x66 #xc3 #xc7 #xcf #xdb #xf3 #xe3 #xc3 #x66 #x3c)
      ;; 1
      (49 10 1 11 6 #xc #x1c #x3c #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; 2
      (50 10 0 11 8 #x7e #xc3 #x3 #x3 #x6 #x3c #x60 #xc0 #xc0 #xc0 #xff)
      ;; 3
      (51 10 0 11 8 #x7e #xc3 #x3 #x3 #x3 #x7e #x3 #x3 #x3 #xc3 #x7e)
      ;; 4
      (52 10 0 11 8 #xc #x1c #x3c #x6c #xcc #xff #xc #xc #xc #xc #xc)
      ;; 5
      (53 10 0 11 8 #xff #xc0 #xc0 #xc0 #xc0 #xfe #x3 #x3 #x3 #xc3 #x7e)
      ;; 6
      (54 10 0 11 8 #x3e #x60 #xc0 #xc0 #xc0 #xfe #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; 7
      (55 10 0 11 8 #xff #x3 #x3 #x3 #x6 #x7f #x18 #x30 #x30 #x30 #x30)
      ;; 8
      (56 10 0 11 8 #x7e #xc3 #xc3 #xc3 #xc3 #x7e #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; 9
      (57 10 0 11 8 #x7e #xc3 #xc3 #xc3 #xc3 #x7f #x3 #x3 #x3 #x6 #x3c)
      ;; :
      (58 10 3 6 3 #x7 #x7 #x0 #x0 #x7 #x7)
      ;; ;
      (59 10 2 6 4 #x7 #x7 #x0 #x0 #x7 #x7 #x6 #xc)
      ;; <
      (60 10 0 9 8 #x3 #xe #x18 #x70 #xc0 #x70 #x18 #xe #x3)
      ;; =
      (61 10 0 6 8 #xff #x0 #x0 #xff)
      ;; >
      (62 10 0 9 8 #xc0 #x70 #x18 #xe #x3 #xe #x18 #x70 #xc0)
      ;; ?
      (63 10 0 11 8 #x7e #xc3 #xc3 #x3 #x6 #xc #x18 #x18 #x0 #x0 #x18)
      ;; @
      (64 10 0 8 8 #x7e #xc3 #xdf #xd3 #xd3 #xdf #xc0 #x7f)
      ;; A
      (65 10 0 11 8 #x7e #xc3 #xc3 #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; B
      (66 10 0 11 8 #xfe #xc3 #xc3 #xc3 #xc3 #xfe #xc3 #xc3 #xc3 #xc3 #xfe)
      ;; C
      (67 10 0 11 8 #x7e #xc3 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc3 #x7e)
      ;; D
      (68 10 0 11 8 #xfc #xc6 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6 #xfc)
      ;; E
      (69 10 0 11 8 #xff #xc0 #xc0 #xc0 #xc0 #xfc #xc0 #xc0 #xc0 #xc0 #xff)
      ;; F
      (70 10 0 11 8 #xff #xc0 #xc0 #xc0 #xc0 #xfc #xc0 #xc0 #xc0 #xc0 #xc0)
      ;; G
      (71 10 0 11 8 #x7e #xc3 #xc0 #xc0 #xc0 #xc0 #xcf #xc3 #xc3 #xc3 #x7e)
      ;; H
      (72 10 0 11 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; I
      (73 10 1 11 6 #x3f #xc #xc #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; J
      (74 10 0 11 7 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x63 #x63 #x3e)
      ;; K
      (75 10 0 11 8 #xc3 #xc6 #xcc #xd8 #xf0 #xe0 #xf0 #xd8 #xcc #xc6 #xc3)
      ;; L
      (76 10 0 11 8 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xff)
      ;; M
      (77 10 0 11 8 #xc3 #xe7 #xff #xdb #xdb #xdb #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; N
      (78 10 0 11 8 #xc3 #xe3 #xf3 #xdb #xcf #xc7 #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; O
      (79 10 0 11 8 #x7e #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; P
      (80 10 0 11 8 #xfe #xc3 #xc3 #xc3 #xc3 #xfe #xc0 #xc0 #xc0 #xc0 #xc0)
      ;; Q
      (81 10 0 11 8 #x7e #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xdb #xcf #xc6 #x7f)
      ;; R
      (82 10 0 11 8 #xfe #xc3 #xc3 #xc3 #xc3 #xfe #xf0 #xd8 #xcc #xc6 #xc3)
      ;; S
      (83 10 0 11 8 #x7e #xc3 #xc0 #xc0 #xc0 #x7e #x3 #x3 #x3 #xc3 #x7e)
      ;; T
      (84 10 0 11 8 #xff #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18)
      ;; U
      (85 10 0 11 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; V
      (86 10 0 11 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x66 #x3c #x3c #x18)
      ;; W
      (87 10 0 11 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xdb #xdb #xff #xff #xe7 #xc3)
      ;; X
      (88 10 0 11 8 #xc3 #x66 #x66 #x3c #x3c #x18 #x3c #x3c #x66 #x66 #xc3)
      ;; Y
      (89 10 0 11 8 #xc3 #x66 #x66 #x3c #x3c #x18 #x18 #x18 #x18 #x18 #x18)
      ;; Z
      (90 10 0 11 8 #xff #x3 #x3 #x6 #xc #x7e #x30 #x60 #xc0 #xc0 #xff)
      ;; [
      (91 10 2 11 4 #xf #xc #xc #xc #xc #xc #xc #xc #xc #xc #xf)
      ;; \
      (92 10 1 11 7 #x60 #x60 #x30 #x30 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ]
      (93 10 2 11 4 #xf #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #xf)
      ;; ^
      (94 10 0 11 8 #x18 #x3c #x66 #xc3)
      ;; _
      (95 10 0 -1 8 #xff)
      ;; `
      (96 10 2 11 5 #x1c #xe #x7)
      ;; a
      (97 10 0 7 8 #x7e #xc3 #x3 #x7f #xc3 #xc3 #x7f)
      ;; b
      (98 10 0 11 8 #xc0 #xc0 #xc0 #xc0 #xfe #xc3 #xc3 #xc3 #xc3 #xc3 #xfe)
      ;; c
      (99 10 0 7 8 #x7e #xc3 #xc0 #xc0 #xc0 #xc3 #x7e)
      ;; d
      (100 10 0 11 8 #x3 #x3 #x3 #x3 #x7f #xc3 #xc3 #xc3 #xc3 #xc3 #x7f)
      ;; e
      (101 10 0 7 8 #x7e #xc3 #xc3 #xfe #xc0 #xc0 #x7f)
      ;; f
      (102 10 0 11 8 #x1e #x33 #x30 #x30 #xfc #x30 #x30 #x30 #x30 #x30 #x30)
      ;; g
      (103 10 0 7 8 #x7e #xc3 #xc3 #xc3 #x7f #x3 #x3 #xc3 #x7e)
      ;; h
      (104 10 0 11 8 #xc0 #xc0 #xc0 #xc0 #xfe #xc3 #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; i
      (105 10 3 10 2 #x3 #x0 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; j
      (106 10 1 10 5 #x3 #x0 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x1b #xe)
      ;; k
      (107 10 0 11 7 #x60 #x60 #x60 #x60 #x63 #x66 #x6c #x78 #x7c #x66 #x63)
      ;; l
      (108 10 1 11 6 #x3c #xc #xc #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; m
      (109 10 0 7 8 #xfe #xdb #xdb #xdb #xdb #xdb #xdb)
      ;; n
      (110 10 0 7 7 #x7e #x63 #x63 #x63 #x63 #x63 #x63)
      ;; o
      (111 10 0 7 7 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; p
      (112 10 0 7 8 #xfe #xc3 #xc3 #xc3 #xc3 #xc3 #xfe #xc0 #xc0)
      ;; q
      (113 10 0 7 8 #x7f #xc3 #xc3 #xc3 #xc3 #xc3 #x7f #x3 #x3)
      ;; r
      (114 10 0 7 7 #x7f #x70 #x60 #x60 #x60 #x60 #x60)
      ;; s
      (115 10 0 7 8 #x7f #xc0 #xc0 #x7e #x3 #x3 #xfe)
      ;; t
      (116 10 0 10 7 #x18 #x18 #x18 #x7e #x18 #x18 #x18 #x18 #x1b #xe)
      ;; u
      (117 10 0 7 7 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; v
      (118 10 0 7 8 #xc3 #xc3 #x66 #x66 #x3c #x3c #x18)
      ;; w
      (119 10 0 7 8 #xc3 #xc3 #xc3 #xdb #xff #xe7 #xc3)
      ;; x
      (120 10 0 7 8 #xc3 #x66 #x3c #x18 #x3c #x66 #xc3)
      ;; y
      (121 10 0 7 8 #xc3 #xc3 #xc3 #x66 #x3c #x18 #x30 #x60 #xc0)
      ;; z
      (122 10 0 7 8 #xff #x6 #xc #x18 #x30 #x60 #xff)
      ;; {
      (123 10 0 11 8 #xf #x18 #x18 #x18 #x38 #xf0 #x38 #x18 #x18 #x18 #xf)
      ;; |
      (124 10 3 11 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; }
      (125 10 0 11 8 #xf0 #x18 #x18 #x18 #x1c #xf #x1c #x18 #x18 #x18 #xf0)
      ;; ~
      (126 10 0 10 7 #x3b #x6e)
      ;; ¬
      (172 10 0 5 8 #xff #x3 #x3)
      ;; °
      (176 10 3 11 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 10 0 8 8 #x18 #x18 #x18 #xff #x18 #x18 #xff)
      ;; µ
      (181 10 0 7 7 #x63 #x63 #x63 #x63 #x63 #x63 #x3f #x60 #x60)
      ;; ·
      (183 10 2 6 5 #xe #x1f #x1f #xe)
      ;; À
      (192 10 0 11 8 #x30 #x18 #x7e #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; Á
      (193 10 0 11 8 #x18 #x30 #x7e #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; Â
      (194 10 0 11 8 #x18 #x3c #x7e #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; Ã
      (195 10 0 11 8 #x3c #x78 #x7e #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; Ä
      (196 10 0 11 8 #x3c #x0 #x7e #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; Å
      (197 10 0 11 8 #x18 #x3c #x18 #x7e #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; Ç
      (199 10 0 11 8 #x7e #xc3 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc0 #xc3 #x7e
        #x18 #x30)
      ;; È
      (200 10 0 11 8 #x30 #x18 #xff #xc0 #xc0 #xfc #xc0 #xc0 #xc0 #xc0 #xff)
      ;; É
      (201 10 0 11 8 #x18 #x30 #xff #xc0 #xc0 #xfc #xc0 #xc0 #xc0 #xc0 #xff)
      ;; Ê
      (202 10 0 11 8 #x18 #x3c #xff #xc0 #xc0 #xfc #xc0 #xc0 #xc0 #xc0 #xff)
      ;; Ë
      (203 10 0 11 8 #x3c #x0 #xff #xc0 #xc0 #xfc #xc0 #xc0 #xc0 #xc0 #xff)
      ;; Ì
      (204 10 1 11 6 #x18 #xc #x3f #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Í
      (205 10 1 11 6 #xc #x18 #x3f #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Î
      (206 10 1 11 6 #xc #x1e #x3f #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Ï
      (207 10 1 11 6 #x1e #x0 #x3f #xc #xc #xc #xc #xc #xc #xc #x3f)
      ;; Ñ
      (209 10 0 11 8 #x3c #x78 #xc3 #xe3 #xf3 #xdb #xcf #xc7 #xc3 #xc3 #xc3)
      ;; Ò
      (210 10 0 11 8 #x30 #x18 #x7e #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; Ó
      (211 10 0 11 8 #x18 #x30 #x7e #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; Ô
      (212 10 0 11 8 #x18 #x3c #x7e #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; Õ
      (213 10 0 11 8 #x3c #x78 #x7e #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; Ö
      (214 10 0 11 8 #x3c #x0 #x7e #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; ×
      (215 10 0 7 8 #xc3 #x66 #x3c #x18 #x3c #x66 #xc3)
      ;; Ù
      (217 10 0 11 8 #x30 #x18 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; Ú
      (218 10 0 11 8 #x18 #x30 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; Û
      (219 10 0 11 8 #x18 #x3c #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; Ü
      (220 10 0 11 8 #x3c #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x7e)
      ;; Ý
      (221 10 0 11 8 #x18 #x30 #xc3 #x66 #x3c #x18 #x18 #x18 #x18 #x18 #x18)
      ;; à
      (224 10 0 10 8 #x30 #x18 #x0 #x7e #xc3 #x3 #x7f #xc3 #xc3 #x7f)
      ;; á
      (225 10 0 10 8 #x18 #x30 #x0 #x7e #xc3 #x3 #x7f #xc3 #xc3 #x7f)
      ;; â
      (226 10 0 10 8 #x18 #x3c #x0 #x7e #xc3 #x3 #x7f #xc3 #xc3 #x7f)
      ;; ã
      (227 10 0 10 8 #x3c #x78 #x0 #x7e #xc3 #x3 #x7f #xc3 #xc3 #x7f)
      ;; ä
      (228 10 0 9 8 #x3c #x0 #x7e #xc3 #x3 #x7f #xc3 #xc3 #x7f)
      ;; å
      (229 10 0 11 8 #x18 #x3c #x18 #x0 #x7e #xc3 #x3 #x7f #xc3 #xc3 #x7f)
      ;; ç
      (231 10 0 7 8 #x7e #xc3 #xc0 #xc0 #xc0 #xc3 #x7e #x18 #x30)
      ;; è
      (232 10 0 10 8 #x30 #x18 #x0 #x7e #xc3 #xc3 #xfe #xc0 #xc0 #x7f)
      ;; é
      (233 10 0 10 8 #x18 #x30 #x0 #x7e #xc3 #xc3 #xfe #xc0 #xc0 #x7f)
      ;; ê
      (234 10 0 10 8 #x18 #x3c #x0 #x7e #xc3 #xc3 #xfe #xc0 #xc0 #x7f)
      ;; ë
      (235 10 0 9 8 #x3c #x0 #x7e #xc3 #xc3 #xfe #xc0 #xc0 #x7f)
      ;; ì
      (236 10 2 10 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; í
      (237 10 2 10 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; î
      (238 10 2 10 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ï
      (239 10 2 9 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ñ
      (241 10 0 10 7 #x3c #x78 #x0 #x7e #x63 #x63 #x63 #x63 #x63 #x63)
      ;; ò
      (242 10 0 10 7 #x30 #x18 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ó
      (243 10 0 10 7 #x18 #x30 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ô
      (244 10 0 10 7 #x18 #x3c #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; õ
      (245 10 0 10 7 #x3c #x78 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ö
      (246 10 0 9 7 #x3c #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ù
      (249 10 0 10 7 #x30 #x18 #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; ú
      (250 10 0 10 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; û
      (251 10 0 10 7 #x18 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; ü
      (252 10 0 9 7 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; ý
      (253 10 0 10 8 #x18 #x30 #x0 #xc3 #xc3 #xc3 #x66 #x3c #x18 #x30 #x60
        #xc0)
      ;; ÿ
      (255 10 0 9 8 #x3c #x0 #xc3 #xc3 #xc3 #x66 #x3c #x18 #x30 #x60 #xc0)
      ;; α
      (945 10 0 8 9 #x6 #xe6 #x1bc #x198 #x198 #x1bc #xe7)
      ;; β
      (946 10 1 10 7 #x1e #x33 #x33 #x63 #x7e #x63 #x63 #x63 #x7e #x60 #x60
        #x60)
      ;; γ
      (947 10 0 10 9 #x3 #x6 #xfc #x198 #x3c #x6c #xcc #xcc #xd8 #x70)
      ;; δ
      (948 10 0 11 8 #x3e #x60 #x60 #x60 #x30 #x18 #x3c #x66 #xc3 #xc3 #x7e)
      ;; ε
      (949 10 1 7 6 #xf #x18 #x30 #x3f #x30 #x18 #xf)
      ;; λ
      (955 10 0 11 8 #xc0 #x60 #x60 #x30 #x18 #x18 #x3c #x36 #x66 #x63 #xc3)
      ;; π
      (960 10 0 7 8 #xff #x66 #x66 #x66 #x66 #x66 #x66)
      ;; –
      (8211 10 1 5 8 #xff)
      ;; —
      (8212 10 0 5 10 #x3ff)
      ;; ‘
      (8216 10 2 11 5 #x7 #xe #x1c)
      ;; ’
      (8217 10 2 11 5 #x7 #xe #x1c)
      ;; “
      (8220 10 2 11 5 #x1b #x1b #x1b #x1b)
      ;; ”
      (8221 10 2 11 5 #x1b #x1b #x1b #x1b)
      ;; …
      (8230 10 0 2 10 #x3bf #x3bf)
      ;; ←
      (8592 10 0 7 8 #x30 #x60 #xff #x60 #x30)
      ;; ↑
      (8593 10 1 10 6 #xc #x1e #x3f #xc #xc #xc #xc #xc #xc)
      ;; →
      (8594 10 0 7 8 #xc #x6 #xff #x6 #xc)
      ;; ↓
      (8595 10 1 10 6 #xc #xc #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↔
      (8596 10 0 7 9 #x6c #xc6 #x1ff #xc6 #x6c)
      ;; ↳
      (8627 10 0 11 8 #xc0 #xc0 #xc0 #xc0 #xcc #xc6 #xff #x6 #xc)
      ;; ∀
      (8704 10 0 11 8 #xc3 #xc3 #xc3 #x7e #x66 #x66 #x3c #x3c #x3c #x18 #x18)
      ;; ∂
      (8706 10 1 11 7 #x1c #x36 #x3 #x3 #x3 #x1f #x33 #x63 #x63 #x36 #x1c)
      ;; ∃
      (8707 10 0 11 8 #xff #x3 #x3 #x3 #x3 #x7f #x3 #x3 #x3 #x3 #xff)
      ;; −
      (8722 10 0 5 8 #xff)
      ;; ∞
      (8734 10 0 7 8 #x66 #xdb #xdb #xdb #xdb #x66)
      ;; ∧
      (8743 10 0 6 8 #x18 #x3c #x66 #xc3)
      ;; ∨
      (8744 10 0 6 8 #xc3 #x66 #x3c #x18)
      ;; ∩
      (8745 10 1 8 7 #x3e #x63 #x63 #x63 #x63 #x63 #x63)
      ;; ∪
      (8746 10 1 8 7 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ∫
      (8747 10 1 11 8 #xe #x1b #x18 #x18 #x18 #x18 #x18 #x18 #x18 #xd8 #x70)
      ;; ≠
      (8800 10 0 9 8 #x6 #x6 #xc #xff #x18 #x30 #xff #x60 #xc0)
      ;; ≡
      (8801 10 0 7 8 #xff #x0 #xff #x0 #xff)
      ;; ≤
      (8804 10 0 8 8 #x7 #x1c #x70 #xc0 #x70 #x1c #x7 #xff)
      ;; ≥
      (8805 10 0 8 8 #xe0 #x38 #xe #x3 #xe #x38 #xe0 #xff)
      ;; ⊂
      (8834 10 0 7 8 #x7f #xc0 #xc0 #xc0 #xc0 #x7f)
      ;; ⊃
      (8835 10 0 7 8 #xfe #x3 #x3 #x3 #x3 #xfe)
      ;; ⊕
      (8853 10 0 8 8 #x3c #x7e #xdb #xff #xdb #x7e #x3c)
      ;; ⊗
      (8855 10 0 8 8 #x3c #x66 #xff #xdb #xff #x66 #x3c)
      ;; ⋅
      (8901 10 2 6 5 #xe #x1f #x1f #xe)
      ;; ▶
      (9654 10 2 11 6 #x20 #x30 #x38 #x3c #x3e #x3f #x3e #x3c #x38 #x30 #x20)
      ;; ◇
      (9671 10 0 10 8 #x18 #x18 #x3c #x66 #xc3 #x66 #x3c #x18 #x18)
      ;; ◊
      (9674 10 0 10 8 #x18 #x18 #x3c #x66 #xc3 #x66 #x3c #x18 #x18)
      ;; ⚙
      (9881 10 0 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 10 0 12 9 #x10 #x10 #x28 #x28 #x38 #x54 #x54 #x92 #x92 #x82 #x111
        #x1ff)
      ;; ✓
      (10003 10 1 8 8 #x3 #x3 #x6 #x6 #xcc #x6c #x38 #x18)
      ;; ❚
      (10074 10 3 11 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("CADR HL10" 12 9 3
      ;; the slug, which a character the face lacks draws
      (#f 5 1 8 3 #x7 #x5 #x5 #x5 #x5 #x5 #x5 #x7)
      ;; space
      (32 5)
      ;; !
      (33 3 1 8 1 #x1 #x1 #x1 #x1 #x1 #x0 #x1 #x1)
      ;; "
      (34 5 1 8 3 #x5 #x5 #x5)
      ;; #
      (35 11 1 8 9 #x12 #x12 #x7f #x24 #x48 #x1fc #x90 #x90)
      ;; $
      (36 7 1 9 5 #x4 #xe #x15 #x14 #xe #x5 #x5 #x15 #xe #x4)
      ;; %
      (37 12 1 8 10 #x188 #x248 #x250 #x190 #x26 #x29 #x49 #x46)
      ;; &
      (38 9 1 8 7 #x18 #x24 #x24 #x18 #x28 #x45 #x42 #x3d)
      ;; '
      (39 4 1 8 2 #x3 #x1 #x1 #x2)
      ;; (
      (40 5 1 8 3 #x1 #x2 #x2 #x4 #x4 #x4 #x4 #x4 #x2 #x2 #x1)
      ;; )
      (41 5 1 8 3 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4)
      ;; *
      (42 7 1 9 5 #x4 #x15 #xe #x15 #x4)
      ;; +
      (43 9 1 7 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8)
      ;; ,
      (44 4 1 2 2 #x3 #x1 #x1 #x2)
      ;; -
      (45 7 1 5 5 #x1f)
      ;; .
      (46 3 1 2 1 #x1 #x1)
      ;; /
      (47 6 1 8 4 #x1 #x1 #x2 #x2 #x4 #x4 #x8 #x8)
      ;; 0
      (48 8 1 8 6 #x1e #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; 1
      (49 8 3 8 3 #x1 #x3 #x5 #x1 #x1 #x1 #x1 #x1)
      ;; 2
      (50 8 1 8 6 #x1e #x21 #x21 #x1 #x6 #x18 #x20 #x3f)
      ;; 3
      (51 8 1 8 6 #x1e #x21 #x21 #x6 #x1 #x21 #x21 #x1e)
      ;; 4
      (52 8 1 8 6 #x6 #xa #xa #x12 #x22 #x3f #x2 #x2)
      ;; 5
      (53 8 1 8 6 #x1f #x10 #x10 #x3e #x21 #x1 #x21 #x1e)
      ;; 6
      (54 8 1 8 6 #xe #x11 #x20 #x3e #x21 #x21 #x21 #x1e)
      ;; 7
      (55 8 1 8 6 #x3f #x1 #x2 #x2 #x4 #x4 #x8 #x8)
      ;; 8
      (56 8 1 8 6 #x1e #x21 #x21 #x1e #x21 #x21 #x21 #x1e)
      ;; 9
      (57 8 1 8 6 #x1e #x21 #x21 #x21 #x1f #x1 #x22 #x1c)
      ;; :
      (58 3 1 6 1 #x1 #x1 #x0 #x0 #x1 #x1)
      ;; ;
      (59 4 1 6 2 #x1 #x1 #x0 #x0 #x3 #x1 #x1 #x2)
      ;; <
      (60 6 1 8 4 #x1 #x2 #x4 #x8 #x8 #x4 #x2 #x1)
      ;; =
      (61 7 1 5 5 #x1f #x0 #x1f)
      ;; >
      (62 6 1 8 4 #x8 #x4 #x2 #x1 #x1 #x2 #x4 #x8)
      ;; ?
      (63 7 1 8 5 #xe #x11 #x1 #x2 #x4 #x0 #x4 #x4)
      ;; @
      (64 10 1 8 8 #x3c #x42 #x99 #xa5 #xa5 #x9a #x40 #x3f)
      ;; A
      (65 9 1 8 7 #x8 #x8 #x14 #x14 #x22 #x3e #x41 #x41)
      ;; B
      (66 8 1 8 6 #x3e #x21 #x21 #x3e #x21 #x21 #x21 #x3e)
      ;; C
      (67 9 1 8 7 #x1e #x21 #x41 #x40 #x40 #x41 #x21 #x1e)
      ;; D
      (68 9 1 8 7 #x7c #x42 #x41 #x41 #x41 #x41 #x42 #x7c)
      ;; E
      (69 7 1 8 5 #x1f #x10 #x10 #x1e #x10 #x10 #x10 #x1f)
      ;; F
      (70 6 1 8 5 #x1f #x10 #x10 #x1e #x10 #x10 #x10 #x10)
      ;; G
      (71 9 1 8 7 #x1e #x21 #x41 #x40 #x47 #x41 #x23 #x1d)
      ;; H
      (72 8 1 8 6 #x21 #x21 #x21 #x3f #x21 #x21 #x21 #x21)
      ;; I
      (73 3 1 8 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; J
      (74 6 0 8 5 #x1 #x1 #x1 #x1 #x1 #x1 #x11 #xe)
      ;; K
      (75 8 1 8 7 #x42 #x44 #x48 #x50 #x68 #x44 #x42 #x41)
      ;; L
      (76 6 1 8 5 #x10 #x10 #x10 #x10 #x10 #x10 #x10 #x1f)
      ;; M
      (77 11 1 8 9 #x183 #x183 #x145 #x145 #x129 #x129 #x111 #x111)
      ;; N
      (78 9 1 8 7 #x61 #x51 #x51 #x49 #x49 #x45 #x45 #x43)
      ;; O
      (79 9 1 8 7 #x1c #x22 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; P
      (80 7 1 8 6 #x3e #x21 #x21 #x21 #x3e #x20 #x20 #x20)
      ;; Q
      (81 9 1 8 8 #x38 #x44 #x82 #x82 #x82 #x8a #x44 #x3a #x1)
      ;; R
      (82 8 1 8 6 #x3e #x21 #x21 #x3e #x21 #x21 #x21 #x21)
      ;; S
      (83 8 1 8 6 #x1e #x21 #x20 #x1e #x1 #x21 #x21 #x1e)
      ;; T
      (84 9 1 8 7 #x7f #x8 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; U
      (85 8 1 8 6 #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; V
      (86 9 1 8 7 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8)
      ;; W
      (87 11 1 8 9 #x111 #x111 #x111 #xaa #xaa #xaa #x44 #x44)
      ;; X
      (88 9 1 8 7 #x22 #x22 #x14 #x8 #x14 #x22 #x22 #x41)
      ;; Y
      (89 9 1 8 7 #x41 #x22 #x22 #x14 #x8 #x8 #x8 #x8)
      ;; Z
      (90 8 1 8 6 #x3f #x1 #x2 #x4 #x8 #x10 #x20 #x3f)
      ;; [
      (91 6 1 8 4 #xf #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #xf)
      ;; \
      (92 6 1 8 4 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ]
      (93 6 1 8 4 #xf #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #xf)
      ;; ^
      (94 7 1 7 5 #x4 #xe #x15 #x4 #x4 #x4)
      ;; _
      (95 8 1 7 6 #x8 #x10 #x3f #x10 #x8)
      ;; `
      (96 4 1 8 2 #x3 #x2 #x2 #x1)
      ;; a
      (97 8 1 6 6 #x1c #x2 #x1e #x22 #x22 #x1d)
      ;; b
      (98 7 1 8 5 #x10 #x10 #x16 #x19 #x11 #x11 #x11 #x1e)
      ;; c
      (99 7 1 6 5 #xe #x11 #x10 #x10 #x11 #xe)
      ;; d
      (100 7 1 8 5 #x1 #x1 #xd #x13 #x11 #x11 #x11 #xf)
      ;; e
      (101 7 1 6 5 #xe #x11 #x11 #x1f #x10 #xf)
      ;; f
      (102 5 1 8 4 #x3 #x4 #xf #x4 #x4 #x4 #x4 #x4)
      ;; g
      (103 7 1 6 5 #xd #x13 #x11 #x11 #x11 #xf #x1 #x11 #xe)
      ;; h
      (104 7 1 8 5 #x10 #x10 #x1e #x11 #x11 #x11 #x11 #x11)
      ;; i
      (105 3 1 9 1 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; j
      (106 4 0 9 3 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x6)
      ;; k
      (107 6 1 8 5 #x10 #x10 #x12 #x14 #x18 #x14 #x12 #x11)
      ;; l
      (108 3 1 8 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; m
      (109 9 1 6 7 #x76 #x49 #x49 #x49 #x49 #x49)
      ;; n
      (110 7 1 6 5 #x1e #x11 #x11 #x11 #x11 #x11)
      ;; o
      (111 7 1 6 5 #xe #x11 #x11 #x11 #x11 #xe)
      ;; p
      (112 7 1 6 5 #x16 #x19 #x11 #x11 #x11 #x1e #x10 #x10 #x10)
      ;; q
      (113 7 1 6 5 #xd #x13 #x11 #x11 #x11 #xf #x1 #x1 #x1)
      ;; r
      (114 5 1 6 4 #xb #xc #x8 #x8 #x8 #x8)
      ;; s
      (115 6 1 6 4 #x7 #x8 #x6 #x1 #x1 #xe)
      ;; t
      (116 6 1 7 4 #x4 #xf #x4 #x4 #x4 #x4 #x3)
      ;; u
      (117 7 1 6 5 #x11 #x11 #x11 #x11 #x11 #xf)
      ;; v
      (118 7 1 6 5 #x11 #x11 #xa #xa #x4 #x4)
      ;; w
      (119 11 1 6 9 #x111 #x111 #xaa #xaa #x44 #x44)
      ;; x
      (120 7 1 6 5 #x11 #xa #x4 #x4 #xa #x11)
      ;; y
      (121 8 1 6 6 #x21 #x11 #x12 #xa #xc #x4 #x8 #x30)
      ;; z
      (122 6 1 6 4 #xf #x1 #x2 #x4 #x8 #xf)
      ;; {
      (123 7 1 8 5 #x3 #x4 #x4 #x4 #x4 #x18 #x4 #x4 #x4 #x4 #x3)
      ;; |
      (124 3 1 8 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; }
      (125 7 1 8 5 #x18 #x4 #x4 #x4 #x4 #x3 #x4 #x4 #x4 #x4 #x18)
      ;; ~
      (126 8 1 6 6 #x19 #x26)
      ;; °
      (176 6 1 8 4 #x6 #x9 #x9 #x6)
      ;; µ
      (181 7 1 6 5 #x11 #x11 #x11 #x11 #x11 #xf #x10 #x10 #x10)
      ;; ·
      (183 3 1 3 1 #x1 #x1)
      ;; À
      (192 9 1 9 7 #x10 #x8 #x0 #x8 #x14 #x22 #x3e #x41 #x41)
      ;; Á
      (193 9 1 9 7 #x8 #x10 #x0 #x8 #x14 #x22 #x3e #x41 #x41)
      ;; Â
      (194 9 1 9 7 #x10 #x28 #x0 #x8 #x14 #x22 #x3e #x41 #x41)
      ;; Ã
      (195 9 1 9 7 #x14 #x28 #x0 #x8 #x14 #x22 #x3e #x41 #x41)
      ;; Ä
      (196 9 1 9 7 #x28 #x0 #x8 #x8 #x14 #x22 #x3e #x41 #x41)
      ;; Å
      (197 9 1 9 7 #x10 #x28 #x10 #x8 #x14 #x22 #x3e #x41 #x41)
      ;; Ç
      (199 9 1 8 7 #x1e #x21 #x41 #x40 #x40 #x41 #x21 #x1e #x8 #x10)
      ;; È
      (200 7 1 9 5 #x8 #x4 #x0 #x1f #x10 #x1e #x10 #x10 #x1f)
      ;; É
      (201 7 1 9 5 #x4 #x8 #x0 #x1f #x10 #x1e #x10 #x10 #x1f)
      ;; Ê
      (202 7 1 9 5 #x8 #x14 #x0 #x1f #x10 #x1e #x10 #x10 #x1f)
      ;; Ë
      (203 7 1 9 5 #x14 #x0 #x1f #x10 #x1e #x10 #x10 #x10 #x1f)
      ;; Ì
      (204 3 0 9 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Í
      (205 3 0 9 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Î
      (206 3 -1 9 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Ï
      (207 3 -1 9 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Ñ
      (209 9 1 9 7 #x14 #x28 #x0 #x61 #x51 #x49 #x45 #x45 #x43)
      ;; Ò
      (210 9 1 9 7 #x10 #x8 #x0 #x1c #x22 #x41 #x41 #x22 #x1c)
      ;; Ó
      (211 9 1 9 7 #x8 #x10 #x0 #x1c #x22 #x41 #x41 #x22 #x1c)
      ;; Ô
      (212 9 1 9 7 #x10 #x28 #x0 #x1c #x22 #x41 #x41 #x22 #x1c)
      ;; Õ
      (213 9 1 9 7 #x14 #x28 #x0 #x1c #x22 #x41 #x41 #x22 #x1c)
      ;; Ö
      (214 9 1 9 7 #x28 #x0 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; ×
      (215 7 1 6 5 #x11 #xa #x4 #x4 #xa #x11)
      ;; Ù
      (217 8 1 9 6 #x8 #x4 #x0 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ú
      (218 8 1 9 6 #x4 #x8 #x0 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Û
      (219 8 1 9 6 #x8 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ü
      (220 8 1 9 6 #x14 #x0 #x21 #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; Ý
      (221 9 1 9 7 #x8 #x10 #x0 #x41 #x22 #x14 #x8 #x8 #x8)
      ;; à
      (224 8 1 9 6 #x8 #x4 #x0 #x1c #x2 #x1e #x22 #x22 #x1d)
      ;; á
      (225 8 1 9 6 #x4 #x8 #x0 #x1c #x2 #x1e #x22 #x22 #x1d)
      ;; â
      (226 8 1 9 6 #x8 #x14 #x0 #x1c #x2 #x1e #x22 #x22 #x1d)
      ;; ã
      (227 8 1 9 6 #xa #x14 #x0 #x1c #x2 #x1e #x22 #x22 #x1d)
      ;; ä
      (228 8 1 8 6 #x14 #x0 #x1c #x2 #x1e #x22 #x22 #x1d)
      ;; å
      (229 8 1 9 6 #x8 #x14 #x8 #x0 #x1c #x2 #x1e #x22 #x1d)
      ;; ç
      (231 7 1 6 5 #xe #x11 #x10 #x10 #x11 #xe #x4 #x8)
      ;; è
      (232 7 1 9 5 #x8 #x4 #x0 #xe #x11 #x11 #x1f #x10 #xf)
      ;; é
      (233 7 1 9 5 #x4 #x8 #x0 #xe #x11 #x11 #x1f #x10 #xf)
      ;; ê
      (234 7 1 9 5 #x8 #x14 #x0 #xe #x11 #x11 #x1f #x10 #xf)
      ;; ë
      (235 7 1 8 5 #x14 #x0 #xe #x11 #x11 #x1f #x10 #xf)
      ;; ì
      (236 3 0 9 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; í
      (237 3 0 9 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; î
      (238 3 -1 9 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ï
      (239 3 -1 8 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ñ
      (241 7 1 9 5 #xa #x14 #x0 #x1e #x11 #x11 #x11 #x11 #x11)
      ;; ò
      (242 7 1 9 5 #x8 #x4 #x0 #xe #x11 #x11 #x11 #x11 #xe)
      ;; ó
      (243 7 1 9 5 #x4 #x8 #x0 #xe #x11 #x11 #x11 #x11 #xe)
      ;; ô
      (244 7 1 9 5 #x8 #x14 #x0 #xe #x11 #x11 #x11 #x11 #xe)
      ;; õ
      (245 7 1 9 5 #xa #x14 #x0 #xe #x11 #x11 #x11 #x11 #xe)
      ;; ö
      (246 7 1 8 5 #x14 #x0 #xe #x11 #x11 #x11 #x11 #xe)
      ;; ù
      (249 7 1 9 5 #x8 #x4 #x0 #x11 #x11 #x11 #x11 #x11 #xf)
      ;; ú
      (250 7 1 9 5 #x4 #x8 #x0 #x11 #x11 #x11 #x11 #x11 #xf)
      ;; û
      (251 7 1 9 5 #x8 #x14 #x0 #x11 #x11 #x11 #x11 #x11 #xf)
      ;; ü
      (252 7 1 8 5 #x14 #x0 #x11 #x11 #x11 #x11 #x11 #xf)
      ;; ý
      (253 8 1 9 6 #x4 #x8 #x0 #x21 #x11 #x12 #xa #xc #x4 #x8 #x30)
      ;; ÿ
      (255 8 1 8 6 #x14 #x0 #x21 #x11 #x12 #xa #xc #x4 #x8 #x30)
      ;; λ
      (955 7 0 8 5 #x10 #x8 #x8 #x4 #xc #xa #x12 #x11)
      ;; –
      (8211 7 0 5 6 #x3f)
      ;; —
      (8212 11 0 5 11 #x7ff)
      ;; ‘
      (8216 4 1 8 2 #x3 #x1 #x1 #x2)
      ;; ’
      (8217 4 1 8 2 #x3 #x1 #x1 #x2)
      ;; “
      (8220 5 1 8 3 #x5 #x5 #x5)
      ;; ”
      (8221 5 1 8 3 #x5 #x5 #x5)
      ;; …
      (8230 9 1 2 7 #x49 #x49)
      ;; ←
      (8592 10 1 5 8 #x20 #x40 #xff #x40 #x20)
      ;; ↑
      (8593 7 1 8 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 10 1 5 8 #x4 #x2 #xff #x2 #x4)
      ;; ↓
      (8595 7 1 8 5 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↳
      (8627 10 1 8 8 #x80 #x80 #x80 #x84 #x82 #xff #x2 #x4)
      ;; −
      (8722 9 1 4 7 #x7f)
      ;; ▶
      (9654 6 1 7 4 #x8 #xc #xe #xf #xe #xc #x8)
      ;; ⚙
      (9881 11 1 9 9 #x10 #xfe #xfe #xee #x1c7 #xee #xfe #xfe #x10)
      ;; ⚠
      (9888 11 1 9 9 #x10 #x10 #x28 #x54 #x54 #x54 #x82 #x111 #x1ff)
      ;; ✓
      (10003 7 0 7 6 #x1 #x1 #x2 #x22 #x14 #x14 #x8)
      ;; ❚
      (10074 4 1 8 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3))
     ("CADR HL10 Bold" 12 9 3
      ;; the slug, which a character the face lacks draws
      (#f 5 1 8 3 #x7 #x5 #x5 #x5 #x5 #x5 #x5 #x7)
      ;; space
      (32 5)
      ;; !
      (33 4 1 8 2 #x3 #x3 #x3 #x3 #x3 #x0 #x3 #x3)
      ;; "
      (34 7 1 8 5 #x1b #x1b #x1b)
      ;; #
      (35 9 1 8 7 #xa #xa #x3f #x14 #x14 #x7e #x28 #x28)
      ;; $
      (36 9 1 9 7 #x8 #x3e #x6b #x68 #x7e #x1f #xb #x6b #x3e #x8)
      ;; %
      (37 14 1 8 12 #x710 #xd90 #xda0 #x720 #x4e #x5b #x9b #x8e)
      ;; &
      (38 9 1 8 7 #x18 #x34 #x34 #x18 #x3b #x6e #x66 #x3b)
      ;; '
      (39 4 1 8 2 #x3 #x3 #x3 #x1 #x2)
      ;; (
      (40 6 1 8 4 #x3 #x6 #x6 #xc #xc #xc #xc #xc #x6 #x6 #x3)
      ;; )
      (41 6 1 8 4 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc)
      ;; *
      (42 7 1 9 5 #x4 #x15 #xe #xe #x15 #x4)
      ;; +
      (43 8 1 6 6 #xc #xc #x3f #x3f #xc #xc)
      ;; ,
      (44 4 1 2 2 #x3 #x3 #x1 #x1 #x2)
      ;; -
      (45 7 1 5 5 #x1f #x1f)
      ;; .
      (46 4 1 2 2 #x3 #x3)
      ;; /
      (47 7 1 8 5 #x3 #x3 #x6 #x6 #xc #xc #x18 #x18)
      ;; 0
      (48 8 1 8 6 #x1e #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; 1
      (49 8 2 8 4 #x3 #x7 #xf #x3 #x3 #x3 #x3 #x3)
      ;; 2
      (50 8 1 8 6 #x1e #x33 #x3 #x6 #xc #x18 #x30 #x3f)
      ;; 3
      (51 8 1 8 6 #x1e #x33 #x3 #xe #x3 #x33 #x33 #x1e)
      ;; 4
      (52 8 1 8 6 #xe #x1e #x16 #x36 #x26 #x3f #x6 #x6)
      ;; 5
      (53 8 1 8 6 #x1f #x18 #x18 #x3e #x33 #x3 #x33 #x1e)
      ;; 6
      (54 8 1 8 6 #x1e #x33 #x30 #x3e #x33 #x33 #x33 #x1e)
      ;; 7
      (55 8 1 8 6 #x3f #x3 #x6 #x6 #xc #xc #x18 #x18)
      ;; 8
      (56 8 1 8 6 #x1e #x33 #x33 #x1e #x33 #x33 #x33 #x1e)
      ;; 9
      (57 8 1 8 6 #x1e #x33 #x33 #x33 #x1f #x3 #x33 #x1e)
      ;; :
      (58 4 1 6 2 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; ;
      (59 4 1 6 2 #x3 #x3 #x0 #x0 #x3 #x3 #x1 #x1 #x2)
      ;; <
      (60 7 1 8 5 #x3 #x6 #xc #x18 #x18 #xc #x6 #x3)
      ;; =
      (61 7 1 6 5 #x1f #x1f #x0 #x1f #x1f)
      ;; >
      (62 7 1 8 5 #x18 #xc #x6 #x3 #x3 #x6 #xc #x18)
      ;; ?
      (63 8 1 8 6 #x1e #x33 #x33 #x6 #xc #x0 #xc #xc)
      ;; @
      (64 11 1 8 9 #x7c #x82 #x139 #x16d #x16d #x16d #x136 #x80 #x7f)
      ;; A
      (65 8 0 8 7 #x8 #x1c #x1c #x36 #x36 #x3e #x63 #x63)
      ;; B
      (66 7 0 8 6 #x3e #x33 #x33 #x3e #x33 #x33 #x33 #x3e)
      ;; C
      (67 8 0 8 7 #x3e #x63 #x63 #x60 #x60 #x63 #x63 #x3e)
      ;; D
      (68 8 0 8 7 #x7e #x63 #x63 #x63 #x63 #x63 #x63 #x7e)
      ;; E
      (69 7 0 8 6 #x3f #x30 #x30 #x3e #x30 #x30 #x30 #x3f)
      ;; F
      (70 7 0 8 6 #x3f #x30 #x30 #x3e #x30 #x30 #x30 #x30)
      ;; G
      (71 8 0 8 7 #x3e #x63 #x60 #x67 #x63 #x63 #x67 #x3b)
      ;; H
      (72 8 0 8 7 #x63 #x63 #x63 #x7f #x63 #x63 #x63 #x63)
      ;; I
      (73 3 0 8 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; J
      (74 7 0 8 6 #x3 #x3 #x3 #x3 #x3 #x33 #x33 #x1e)
      ;; K
      (75 8 0 8 7 #x66 #x6c #x78 #x70 #x78 #x6c #x66 #x63)
      ;; L
      (76 7 0 8 6 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x3f)
      ;; M
      (77 10 0 8 9 #x1c7 #x1c7 #x1ef #x1ef #x1bb #x1bb #x1bb #x193)
      ;; N
      (78 9 0 8 8 #xe3 #xf3 #xf3 #xdb #xdb #xcf #xcf #xc7)
      ;; O
      (79 8 0 8 7 #x3e #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; P
      (80 7 0 8 6 #x3e #x33 #x33 #x33 #x3e #x30 #x30 #x30)
      ;; Q
      (81 8 0 8 7 #x3e #x63 #x63 #x63 #x63 #x63 #x6b #x3e #x6 #x3)
      ;; R
      (82 7 0 8 6 #x3e #x33 #x33 #x33 #x3e #x33 #x33 #x33)
      ;; S
      (83 7 0 8 6 #x1e #x33 #x38 #x1e #xf #x3 #x33 #x3e)
      ;; T
      (84 7 0 8 6 #x3f #xc #xc #xc #xc #xc #xc #xc)
      ;; U
      (85 8 0 8 7 #x63 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; V
      (86 9 0 8 8 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18 #x18)
      ;; W
      (87 12 0 8 11 #x623 #x623 #x376 #x376 #x356 #x1dc #x1dc #x88)
      ;; X
      (88 7 0 8 6 #x33 #x33 #x1e #xc #xc #x1e #x33 #x33)
      ;; Y
      (89 9 0 8 8 #xc3 #xc3 #x66 #x3c #x18 #x18 #x18 #x18)
      ;; Z
      (90 7 0 8 6 #x3f #x3 #x6 #xc #xc #x18 #x30 #x3f)
      ;; [
      (91 6 1 8 4 #xf #xc #xc #xc #xc #xc #xc #xc #xc #xc #xf)
      ;; \
      (92 7 1 8 5 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ]
      (93 6 1 8 4 #xf #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #xf)
      ;; ^
      (94 8 1 7 6 #xc #x1e #x3f #x2d #xc #xc #xc)
      ;; _
      (95 9 1 7 7 #x18 #x30 #x7f #x7f #x30 #x18)
      ;; `
      (96 4 1 8 2 #x3 #x3 #x3 #x2 #x1)
      ;; a
      (97 7 0 6 6 #x1c #x6 #x1e #x36 #x36 #x1f)
      ;; b
      (98 7 0 8 6 #x30 #x30 #x3e #x33 #x33 #x33 #x33 #x3e)
      ;; c
      (99 7 0 6 6 #x1e #x33 #x30 #x30 #x33 #x1e)
      ;; d
      (100 7 0 8 6 #x3 #x3 #x1f #x33 #x33 #x33 #x33 #x1f)
      ;; e
      (101 7 0 6 6 #x1e #x33 #x3f #x30 #x33 #x1e)
      ;; f
      (102 6 0 8 5 #x7 #xc #x1f #xc #xc #xc #xc #xc)
      ;; g
      (103 7 0 6 6 #x1f #x33 #x33 #x33 #x33 #x1f #x3 #x33 #x1e)
      ;; h
      (104 7 0 8 6 #x30 #x30 #x3e #x33 #x33 #x33 #x33 #x33)
      ;; i
      (105 3 0 9 2 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; j
      (106 4 0 9 3 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x6)
      ;; k
      (107 8 0 8 7 #x60 #x60 #x66 #x6c #x78 #x6c #x66 #x63)
      ;; l
      (108 3 0 8 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; m
      (109 11 0 6 10 #x3de #x333 #x333 #x333 #x333 #x333)
      ;; n
      (110 7 0 6 6 #x3e #x33 #x33 #x33 #x33 #x33)
      ;; o
      (111 7 0 6 6 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; p
      (112 7 0 6 6 #x3e #x33 #x33 #x33 #x33 #x3e #x30 #x30 #x30)
      ;; q
      (113 7 0 6 6 #x1f #x33 #x33 #x33 #x33 #x1f #x3 #x3 #x3)
      ;; r
      (114 6 0 6 5 #x1f #x1b #x18 #x18 #x18 #x18)
      ;; s
      (115 6 0 6 5 #xf #x19 #x1c #x7 #x13 #x1e)
      ;; t
      (116 6 0 7 5 #xc #x1f #xc #xc #xc #xc #x7)
      ;; u
      (117 7 0 6 6 #x33 #x33 #x33 #x33 #x33 #x1f)
      ;; v
      (118 8 0 6 7 #x63 #x63 #x36 #x36 #x1c #x1c)
      ;; w
      (119 11 0 6 10 #x333 #x333 #x1b6 #x1fe #xcc #xcc)
      ;; x
      (120 7 0 6 6 #x33 #x1e #xc #xc #x1e #x33)
      ;; y
      (121 8 0 6 7 #x63 #x63 #x36 #x14 #x1c #x8 #x58 #x30)
      ;; z
      (122 6 0 6 5 #x1f #x3 #x6 #xc #x18 #x1f)
      ;; {
      (123 7 1 8 5 #x7 #xc #xc #xc #xc #x18 #xc #xc #xc #xc #x7)
      ;; |
      (124 4 1 8 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; }
      (125 7 1 8 5 #x1c #x6 #x6 #x6 #x6 #x3 #x6 #x6 #x6 #x6 #x1c)
      ;; ~
      (126 10 1 6 8 #x33 #x7e #xcc)
      ;; °
      (176 6 1 8 4 #x6 #x9 #x9 #x6)
      ;; µ
      (181 7 0 6 6 #x33 #x33 #x33 #x33 #x33 #x1f #x30 #x30 #x30)
      ;; ·
      (183 4 1 3 2 #x3 #x3)
      ;; À
      (192 8 0 9 7 #x30 #x18 #x0 #x8 #x1c #x36 #x3e #x63 #x63)
      ;; Á
      (193 8 0 9 7 #x18 #x30 #x0 #x8 #x1c #x36 #x3e #x63 #x63)
      ;; Â
      (194 8 0 9 7 #x18 #x3c #x0 #x8 #x1c #x36 #x3e #x63 #x63)
      ;; Ã
      (195 8 0 9 7 #x3c #x78 #x0 #x8 #x1c #x36 #x3e #x63 #x63)
      ;; Ä
      (196 8 0 9 7 #x3c #x0 #x8 #x1c #x36 #x36 #x3e #x63 #x63)
      ;; Å
      (197 8 0 9 7 #x18 #x3c #x18 #x8 #x1c #x36 #x3e #x63 #x63)
      ;; Ç
      (199 8 0 8 7 #x3e #x63 #x63 #x60 #x60 #x63 #x63 #x3e #x18 #x30)
      ;; È
      (200 7 0 9 6 #x18 #xc #x0 #x3f #x30 #x3e #x30 #x30 #x3f)
      ;; É
      (201 7 0 9 6 #xc #x18 #x0 #x3f #x30 #x3e #x30 #x30 #x3f)
      ;; Ê
      (202 7 0 9 6 #xc #x1e #x0 #x3f #x30 #x3e #x30 #x30 #x3f)
      ;; Ë
      (203 7 0 9 6 #x1e #x0 #x3f #x30 #x3e #x30 #x30 #x30 #x3f)
      ;; Ì
      (204 3 -1 9 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; Í
      (205 3 -1 9 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; Î
      (206 3 -1 9 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; Ï
      (207 3 -1 9 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; Ñ
      (209 9 0 9 8 #x3c #x78 #x0 #xe3 #xf3 #xdb #xcf #xcf #xc7)
      ;; Ò
      (210 8 0 9 7 #x30 #x18 #x0 #x3e #x63 #x63 #x63 #x63 #x3e)
      ;; Ó
      (211 8 0 9 7 #x18 #x30 #x0 #x3e #x63 #x63 #x63 #x63 #x3e)
      ;; Ô
      (212 8 0 9 7 #x18 #x3c #x0 #x3e #x63 #x63 #x63 #x63 #x3e)
      ;; Õ
      (213 8 0 9 7 #x3c #x78 #x0 #x3e #x63 #x63 #x63 #x63 #x3e)
      ;; Ö
      (214 8 0 9 7 #x3c #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ×
      (215 7 0 6 6 #x33 #x1e #xc #xc #x1e #x33)
      ;; Ù
      (217 8 0 9 7 #x30 #x18 #x0 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Ú
      (218 8 0 9 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Û
      (219 8 0 9 7 #x18 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Ü
      (220 8 0 9 7 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; Ý
      (221 9 0 9 8 #x18 #x30 #x0 #xc3 #x66 #x3c #x18 #x18 #x18)
      ;; à
      (224 7 0 9 6 #x18 #xc #x0 #x1c #x6 #x1e #x36 #x36 #x1f)
      ;; á
      (225 7 0 9 6 #xc #x18 #x0 #x1c #x6 #x1e #x36 #x36 #x1f)
      ;; â
      (226 7 0 9 6 #xc #x1e #x0 #x1c #x6 #x1e #x36 #x36 #x1f)
      ;; ã
      (227 7 0 9 6 #x1e #x3c #x0 #x1c #x6 #x1e #x36 #x36 #x1f)
      ;; ä
      (228 7 0 8 6 #x1e #x0 #x1c #x6 #x1e #x36 #x36 #x1f)
      ;; å
      (229 7 0 9 6 #xc #x1e #xc #x0 #x1c #x6 #x1e #x36 #x1f)
      ;; ç
      (231 7 0 6 6 #x1e #x33 #x30 #x30 #x33 #x1e #xc #x18)
      ;; è
      (232 7 0 9 6 #x18 #xc #x0 #x1e #x33 #x3f #x30 #x33 #x1e)
      ;; é
      (233 7 0 9 6 #xc #x18 #x0 #x1e #x33 #x3f #x30 #x33 #x1e)
      ;; ê
      (234 7 0 9 6 #xc #x1e #x0 #x1e #x33 #x3f #x30 #x33 #x1e)
      ;; ë
      (235 7 0 8 6 #x1e #x0 #x1e #x33 #x3f #x30 #x33 #x1e)
      ;; ì
      (236 3 -1 9 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; í
      (237 3 -1 9 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; î
      (238 3 -1 9 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ï
      (239 3 -1 8 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ñ
      (241 7 0 9 6 #x1e #x3c #x0 #x3e #x33 #x33 #x33 #x33 #x33)
      ;; ò
      (242 7 0 9 6 #x18 #xc #x0 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; ó
      (243 7 0 9 6 #xc #x18 #x0 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; ô
      (244 7 0 9 6 #xc #x1e #x0 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; õ
      (245 7 0 9 6 #x1e #x3c #x0 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; ö
      (246 7 0 8 6 #x1e #x0 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; ù
      (249 7 0 9 6 #x18 #xc #x0 #x33 #x33 #x33 #x33 #x33 #x1f)
      ;; ú
      (250 7 0 9 6 #xc #x18 #x0 #x33 #x33 #x33 #x33 #x33 #x1f)
      ;; û
      (251 7 0 9 6 #xc #x1e #x0 #x33 #x33 #x33 #x33 #x33 #x1f)
      ;; ü
      (252 7 0 8 6 #x1e #x0 #x33 #x33 #x33 #x33 #x33 #x1f)
      ;; ý
      (253 8 0 9 7 #x18 #x30 #x0 #x63 #x63 #x36 #x14 #x1c #x8 #x58 #x30)
      ;; ÿ
      (255 8 0 8 7 #x3c #x0 #x63 #x63 #x36 #x14 #x1c #x8 #x58 #x30)
      ;; λ
      (955 7 0 8 5 #x18 #x18 #xc #xc #xe #x1e #x1b #x1b)
      ;; –
      (8211 7 0 5 6 #x3f #x3f)
      ;; —
      (8212 10 0 5 10 #x3ff #x3ff)
      ;; ‘
      (8216 4 1 8 2 #x3 #x3 #x3 #x1 #x2)
      ;; ’
      (8217 4 1 8 2 #x3 #x3 #x3 #x1 #x2)
      ;; “
      (8220 7 1 8 5 #x1b #x1b #x1b)
      ;; ”
      (8221 7 1 8 5 #x1b #x1b #x1b)
      ;; …
      (8230 12 1 2 10 #x333 #x333)
      ;; ←
      (8592 10 1 5 8 #x20 #x40 #xff #x40 #x20)
      ;; ↑
      (8593 7 1 8 6 #xc #x1e #x3f #xc #xc #xc #xc #xc)
      ;; →
      (8594 10 1 5 8 #x4 #x2 #xff #x2 #x4)
      ;; ↓
      (8595 7 1 8 6 #xc #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↳
      (8627 10 1 8 8 #xc0 #xc0 #xc0 #xc4 #xc2 #xff #x2 #x4)
      ;; −
      (8722 8 1 4 6 #x3f #x3f)
      ;; ▶
      (9654 6 1 7 4 #x8 #xc #xe #xf #xe #xc #x8)
      ;; ⚙
      (9881 11 1 9 9 #x10 #xfe #xfe #xee #x1c7 #xee #xfe #xfe #x10)
      ;; ⚠
      (9888 11 1 9 9 #x10 #x10 #x28 #x54 #x54 #x54 #x82 #x111 #x1ff)
      ;; ✓
      (10003 8 0 7 7 #x3 #x3 #x6 #x66 #x3c #x3c #x18)
      ;; ❚
      (10074 6 1 8 4 #xf #xf #xf #xf #xf #xf #xf #xf))
     ("CADR HL12" 14 11 3
      ;; the slug, which a character the face lacks draws
      (#f 6 1 10 4 #xf #x9 #x9 #x9 #x9 #x9 #x9 #x9 #x9 #xf)
      ;; space
      (32 6)
      ;; !
      (33 3 1 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x1 #x1)
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
      (39 3 1 10 2 #x1 #x1 #x1 #x2)
      ;; (
      (40 5 1 10 3 #x1 #x2 #x2 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x2 #x2 #x1)
      ;; )
      (41 5 1 10 3 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4)
      ;; *
      (42 7 1 9 5 #x4 #x15 #xe #x15 #x4)
      ;; +
      (43 9 1 8 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8)
      ;; ,
      (44 4 1 2 2 #x3 #x1 #x1 #x2)
      ;; -
      (45 8 1 5 6 #x3f)
      ;; .
      (46 3 1 2 1 #x1 #x1)
      ;; /
      (47 7 1 10 5 #x1 #x1 #x2 #x2 #x4 #x4 #x8 #x8 #x10 #x10)
      ;; 0
      (48 9 1 10 7 #x1c #x22 #x41 #x41 #x41 #x41 #x41 #x41 #x22 #x1c)
      ;; 1
      (49 9 2 10 4 #x1 #x3 #xd #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; 2
      (50 9 1 10 7 #x1e #x21 #x21 #x1 #x2 #x4 #x8 #x10 #x20 #x7f)
      ;; 3
      (51 9 1 10 7 #x1c #x22 #x22 #x2 #xc #x2 #x41 #x41 #x22 #x1c)
      ;; 4
      (52 9 1 10 7 #x6 #xa #x12 #x12 #x22 #x42 #x7f #x2 #x2 #x2)
      ;; 5
      (53 9 1 10 7 #x3e #x20 #x40 #x7c #x42 #x1 #x1 #x1 #x42 #x3c)
      ;; 6
      (54 9 1 10 7 #x1e #x21 #x40 #x5c #x62 #x41 #x41 #x41 #x22 #x1c)
      ;; 7
      (55 9 1 10 7 #x7f #x1 #x1 #x2 #x4 #x8 #x8 #x10 #x10 #x10)
      ;; 8
      (56 9 1 10 7 #x1c #x22 #x22 #x22 #x1c #x22 #x41 #x41 #x22 #x1c)
      ;; 9
      (57 9 1 10 7 #x1c #x22 #x41 #x41 #x41 #x23 #x1d #x1 #x42 #x3c)
      ;; :
      (58 3 1 7 1 #x1 #x1 #x0 #x0 #x0 #x1 #x1)
      ;; ;
      (59 4 1 7 2 #x1 #x1 #x0 #x0 #x0 #x3 #x1 #x1 #x2)
      ;; <
      (60 7 1 10 5 #x1 #x2 #x4 #x8 #x10 #x10 #x8 #x4 #x2 #x1)
      ;; =
      (61 8 1 6 6 #x3f #x0 #x3f)
      ;; >
      (62 7 1 10 5 #x10 #x8 #x4 #x2 #x1 #x1 #x2 #x4 #x8 #x10)
      ;; ?
      (63 8 1 10 6 #x1e #x21 #x21 #x1 #x2 #x4 #x4 #x0 #x4 #x4)
      ;; @
      (64 12 1 10 10 #x78 #x186 #x132 #x249 #x249 #x249 #x24a #x134 #x180 #x7e)
      ;; A
      (65 10 1 10 8 #x18 #x18 #x24 #x24 #x24 #x42 #x7e #x42 #x81 #x81)
      ;; B
      (66 9 1 10 7 #x7e #x41 #x41 #x41 #x7e #x41 #x41 #x41 #x41 #x7e)
      ;; C
      (67 11 1 10 9 #x3c #xc2 #x81 #x101 #x100 #x100 #x101 #x81 #xc2 #x3c)
      ;; D
      (68 10 1 10 8 #xfc #x82 #x81 #x81 #x81 #x81 #x81 #x81 #x82 #xfc)
      ;; E
      (69 9 1 10 7 #x7f #x40 #x40 #x40 #x7e #x40 #x40 #x40 #x40 #x7f)
      ;; F
      (70 8 1 10 7 #x7f #x40 #x40 #x40 #x7e #x40 #x40 #x40 #x40 #x40)
      ;; G
      (71 11 1 10 9 #x3c #xc2 #x81 #x101 #x100 #x11f #x101 #x81 #xc3 #x3d)
      ;; H
      (72 10 1 10 8 #x81 #x81 #x81 #x81 #xff #x81 #x81 #x81 #x81 #x81)
      ;; I
      (73 3 1 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; J
      (74 7 1 10 5 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x11 #x11 #xe)
      ;; K
      (75 9 1 10 8 #x82 #x84 #x88 #x90 #xa0 #xd0 #x88 #x84 #x82 #x81)
      ;; L
      (76 8 1 10 7 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x40 #x7f)
      ;; M
      (77 12 1 10 10 #x303 #x303 #x285 #x285 #x285 #x249 #x249 #x249 #x231
        #x231)
      ;; N
      (78 10 1 10 8 #xc1 #xa1 #xa1 #x91 #x91 #x89 #x89 #x85 #x85 #x83)
      ;; O
      (79 12 1 10 10 #x78 #x186 #x102 #x201 #x201 #x201 #x201 #x102 #x186 #x78)
      ;; P
      (80 8 1 10 7 #x7e #x41 #x41 #x41 #x41 #x7e #x40 #x40 #x40 #x40)
      ;; Q
      (81 12 1 10 10 #x78 #x186 #x102 #x201 #x201 #x201 #x201 #x112 #x18e #x7c
        #x2 #x1)
      ;; R
      (82 9 1 10 7 #x7e #x41 #x41 #x41 #x7e #x41 #x41 #x41 #x41 #x41)
      ;; S
      (83 10 1 10 8 #x3e #x41 #x41 #x40 #x38 #x6 #x81 #x81 #x41 #x3e)
      ;; T
      (84 11 1 10 9 #x1ff #x10 #x10 #x10 #x10 #x10 #x10 #x10 #x10 #x10)
      ;; U
      (85 10 1 10 8 #x81 #x81 #x81 #x81 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; V
      (86 10 1 10 8 #x81 #x81 #x42 #x42 #x42 #x24 #x24 #x24 #x18 #x18)
      ;; W
      (87 13 1 10 11 #x421 #x421 #x451 #x252 #x252 #x28a #x28a #x104 #x104
        #x104)
      ;; X
      (88 11 1 10 9 #x82 #x82 #x44 #x28 #x10 #x28 #x44 #x44 #x82 #x101)
      ;; Y
      (89 11 1 10 9 #x101 #x82 #x82 #x44 #x28 #x28 #x10 #x10 #x10 #x10)
      ;; Z
      (90 10 1 10 8 #xff #x1 #x2 #x4 #x8 #x10 #x20 #x40 #x80 #xff)
      ;; [
      (91 6 1 10 4 #xf #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #x8 #xf)
      ;; \
      (92 7 1 10 5 #x10 #x10 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ]
      (93 6 1 10 4 #xf #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #xf)
      ;; ^
      (94 7 1 10 5 #x4 #xa #x11)
      ;; _
      (95 9 1 -2 7 #x7f)
      ;; `
      (96 3 1 10 2 #x2 #x2 #x2 #x1)
      ;; a
      (97 8 1 7 6 #x1c #x22 #x6 #x1a #x22 #x22 #x1d)
      ;; b
      (98 8 1 10 6 #x20 #x20 #x20 #x2c #x32 #x21 #x21 #x21 #x32 #x2c)
      ;; c
      (99 8 1 7 6 #xe #x11 #x20 #x20 #x20 #x11 #xe)
      ;; d
      (100 8 1 10 6 #x1 #x1 #x1 #xd #x13 #x21 #x21 #x21 #x13 #xd)
      ;; e
      (101 8 1 7 6 #xc #x12 #x21 #x3f #x20 #x11 #xe)
      ;; f
      (102 6 1 10 4 #x3 #x4 #x4 #xf #x4 #x4 #x4 #x4 #x4 #x4)
      ;; g
      (103 8 1 7 6 #xd #x13 #x21 #x21 #x21 #x13 #xd #x1 #x21 #x1e)
      ;; h
      (104 8 1 10 6 #x20 #x20 #x20 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; i
      (105 3 1 10 1 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; j
      (106 4 0 10 3 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x6)
      ;; k
      (107 7 1 10 6 #x20 #x20 #x20 #x22 #x24 #x38 #x28 #x24 #x22 #x21)
      ;; l
      (108 3 1 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; m
      (109 11 1 7 9 #x166 #x199 #x111 #x111 #x111 #x111 #x111)
      ;; n
      (110 8 1 7 6 #x2e #x31 #x21 #x21 #x21 #x21 #x21)
      ;; o
      (111 9 1 7 7 #x1c #x22 #x41 #x41 #x41 #x22 #x1c)
      ;; p
      (112 8 1 7 6 #x2c #x32 #x21 #x21 #x21 #x32 #x2c #x20 #x20 #x20)
      ;; q
      (113 8 1 7 6 #xd #x13 #x21 #x21 #x21 #x13 #xd #x1 #x1 #x1)
      ;; r
      (114 5 1 7 4 #xb #xc #x8 #x8 #x8 #x8 #x8)
      ;; s
      (115 8 1 7 6 #x1e #x21 #x20 #x1e #x1 #x21 #x1e)
      ;; t
      (116 5 1 9 4 #x4 #x4 #xf #x4 #x4 #x4 #x4 #x4 #x3)
      ;; u
      (117 8 1 7 6 #x21 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; v
      (118 9 1 7 7 #x41 #x41 #x22 #x22 #x14 #x14 #x8)
      ;; w
      (119 11 1 7 9 #x111 #x111 #xaa #xaa #xaa #x44 #x44)
      ;; x
      (120 7 1 7 5 #x11 #x11 #xa #x4 #xa #x11 #x11)
      ;; y
      (121 9 1 7 7 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x48 #x30)
      ;; z
      (122 7 1 7 5 #x1f #x1 #x2 #x4 #x8 #x10 #x1f)
      ;; {
      (123 8 1 10 6 #x7 #x8 #x8 #x8 #x8 #x8 #x30 #x8 #x8 #x8 #x8 #x8 #x7)
      ;; |
      (124 4 2 10 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; }
      (125 8 1 10 6 #x38 #x4 #x4 #x4 #x4 #x4 #x3 #x4 #x4 #x4 #x4 #x4 #x38)
      ;; ~
      (126 8 1 8 6 #x19 #x26)
      ;; ¬
      (172 8 1 6 6 #x3f #x1 #x1)
      ;; °
      (176 6 1 10 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 9 1 9 7 #x8 #x8 #x8 #x7f #x8 #x8 #x8 #x0 #x7f)
      ;; µ
      (181 8 1 7 6 #x21 #x21 #x21 #x21 #x21 #x23 #x1d #x20 #x20 #x20)
      ;; ·
      (183 5 1 6 3 #x7 #x7 #x7)
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
      (199 11 1 10 9 #x3c #xc2 #x81 #x101 #x100 #x100 #x101 #x81 #xc2 #x3c
        #x10 #x20)
      ;; È
      (200 9 1 11 7 #x10 #x8 #x0 #x7f #x40 #x7e #x40 #x40 #x40 #x40 #x7f)
      ;; É
      (201 9 1 11 7 #x8 #x10 #x0 #x7f #x40 #x7e #x40 #x40 #x40 #x40 #x7f)
      ;; Ê
      (202 9 1 11 7 #x10 #x28 #x0 #x7f #x40 #x7e #x40 #x40 #x40 #x40 #x7f)
      ;; Ë
      (203 9 1 11 7 #x28 #x0 #x7f #x40 #x40 #x7e #x40 #x40 #x40 #x40 #x7f)
      ;; Ì
      (204 3 0 11 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Í
      (205 3 0 11 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Î
      (206 3 -1 11 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Ï
      (207 3 -1 11 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; Ñ
      (209 10 1 11 8 #x14 #x28 #x0 #xc1 #xa1 #x91 #x89 #x89 #x85 #x85 #x83)
      ;; Ò
      (210 12 1 11 10 #x20 #x10 #x0 #x78 #x186 #x102 #x201 #x201 #x102 #x186
        #x78)
      ;; Ó
      (211 12 1 11 10 #x10 #x20 #x0 #x78 #x186 #x102 #x201 #x201 #x102 #x186
        #x78)
      ;; Ô
      (212 12 1 11 10 #x20 #x50 #x0 #x78 #x186 #x102 #x201 #x201 #x102 #x186
        #x78)
      ;; Õ
      (213 12 1 11 10 #x28 #x50 #x0 #x78 #x186 #x102 #x201 #x201 #x102 #x186
        #x78)
      ;; Ö
      (214 12 1 11 10 #x50 #x0 #x78 #x186 #x102 #x201 #x201 #x201 #x102 #x186
        #x78)
      ;; ×
      (215 7 1 7 5 #x11 #x11 #xa #x4 #xa #x11 #x11)
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
      (224 8 1 10 6 #x8 #x4 #x0 #x1c #x22 #x6 #x1a #x22 #x22 #x1d)
      ;; á
      (225 8 1 10 6 #x4 #x8 #x0 #x1c #x22 #x6 #x1a #x22 #x22 #x1d)
      ;; â
      (226 8 1 10 6 #x8 #x14 #x0 #x1c #x22 #x6 #x1a #x22 #x22 #x1d)
      ;; ã
      (227 8 1 10 6 #xa #x14 #x0 #x1c #x22 #x6 #x1a #x22 #x22 #x1d)
      ;; ä
      (228 8 1 9 6 #x14 #x0 #x1c #x22 #x6 #x1a #x22 #x22 #x1d)
      ;; å
      (229 8 1 11 6 #x8 #x14 #x8 #x0 #x1c #x22 #x6 #x1a #x22 #x22 #x1d)
      ;; ç
      (231 8 1 7 6 #xe #x11 #x20 #x20 #x20 #x11 #xe #x4 #x8)
      ;; è
      (232 8 1 10 6 #x8 #x4 #x0 #xc #x12 #x21 #x3f #x20 #x11 #xe)
      ;; é
      (233 8 1 10 6 #x4 #x8 #x0 #xc #x12 #x21 #x3f #x20 #x11 #xe)
      ;; ê
      (234 8 1 10 6 #x8 #x14 #x0 #xc #x12 #x21 #x3f #x20 #x11 #xe)
      ;; ë
      (235 8 1 9 6 #x14 #x0 #xc #x12 #x21 #x3f #x20 #x11 #xe)
      ;; ì
      (236 3 0 10 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; í
      (237 3 0 10 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; î
      (238 3 -1 10 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; ï
      (239 3 -1 9 3 #x5 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
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
      (253 9 1 10 7 #x8 #x10 #x0 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x48
        #x30)
      ;; ÿ
      (255 9 1 9 7 #x28 #x0 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x48 #x30)
      ;; α
      (945 9 1 5 7 #x39 #x46 #x44 #x44 #x3b)
      ;; β
      (946 8 0 8 7 #x1e #x21 #x21 #x3e #x21 #x21 #x31 #x2e #x20 #x20 #x40)
      ;; γ
      (947 8 1 9 6 #x1 #x1a #x2c #xc #x14 #x14 #x14 #x18 #x8)
      ;; δ
      (948 7 1 10 5 #x6 #x9 #x8 #x4 #x6 #x9 #x11 #x11 #x11 #xe)
      ;; ε
      (949 6 1 7 4 #x7 #x8 #x8 #xf #x8 #x8 #x7)
      ;; λ
      (955 8 1 9 6 #x20 #x20 #x10 #x8 #xc #xa #x12 #x11 #x21)
      ;; π
      (960 9 1 7 7 #x3f #x52 #x12 #x12 #x12 #x12 #x22)
      ;; –
      (8211 8 0 5 7 #x7f)
      ;; —
      (8212 12 0 5 12 #xfff)
      ;; ‘
      (8216 3 1 10 2 #x1 #x1 #x1 #x2)
      ;; ’
      (8217 3 1 10 2 #x1 #x1 #x1 #x2)
      ;; “
      (8220 5 1 10 3 #x5 #x5 #x5 #x5)
      ;; ”
      (8221 5 1 10 3 #x5 #x5 #x5 #x5)
      ;; …
      (8230 9 1 2 7 #x49 #x49)
      ;; ←
      (8592 9 1 7 7 #x10 #x20 #x7f #x20 #x10)
      ;; ↑
      (8593 7 1 9 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 9 1 7 7 #x4 #x2 #x7f #x2 #x4)
      ;; ↓
      (8595 7 1 9 5 #x4 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↔
      (8596 10 1 7 8 #x24 #x42 #xff #x42 #x24)
      ;; ↳
      (8627 9 1 10 7 #x40 #x40 #x40 #x44 #x42 #x7f #x2 #x4)
      ;; ∀
      (8704 10 2 9 6 #x21 #x21 #x21 #x3f #x21 #x12 #x12 #x12 #xc)
      ;; ∂
      (8706 7 1 8 5 #x1c #x2 #x1 #xf #x11 #x11 #x11 #xe)
      ;; ∃
      (8707 8 1 9 6 #x3f #x1 #x1 #x1 #x1f #x1 #x1 #x1 #x3f)
      ;; −
      (8722 9 1 5 7 #x7f)
      ;; ∞
      (8734 11 1 7 9 #xee #x111 #x111 #x111 #xee)
      ;; ∧
      (8743 8 1 6 6 #xc #x12 #x21)
      ;; ∨
      (8744 8 1 6 6 #x21 #x12 #xc)
      ;; ∩
      (8745 7 1 7 5 #xe #x11 #x11 #x11 #x11 #x11)
      ;; ∪
      (8746 7 1 7 5 #x11 #x11 #x11 #x11 #x11 #xe)
      ;; ∫
      (8747 7 1 10 5 #x3 #x5 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x14 #x18)
      ;; ≠
      (8800 9 1 8 7 #x2 #x4 #x7f #x8 #x7f #x10 #x20)
      ;; ≡
      (8801 9 1 6 7 #x7f #x0 #x7f #x0 #x7f)
      ;; ≤
      (8804 6 1 10 4 #x1 #x2 #x4 #x8 #x8 #x4 #x2 #x1 #x0 #xf)
      ;; ≥
      (8805 6 1 10 4 #x8 #x4 #x2 #x1 #x1 #x2 #x4 #x8 #x0 #xf)
      ;; ⊂
      (8834 8 1 6 6 #x1f #x20 #x20 #x1f)
      ;; ⊃
      (8835 8 1 6 6 #x3e #x1 #x1 #x3e)
      ;; ⊕
      (8853 9 1 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 9 1 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 5 1 6 3 #x7 #x7 #x7)
      ;; ▶
      (9654 7 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 7 1 8 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ◊
      (9674 7 1 8 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
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
     ("CADR HL12 Bold" 14 11 3
      ;; the slug, which a character the face lacks draws
      (#f 7 1 10 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #x1f)
      ;; space
      (32 7)
      ;; !
      (33 4 1 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x0 #x3 #x3)
      ;; "
      (34 7 1 10 5 #x1b #x1b #x1b #x1b)
      ;; #
      (35 12 1 10 10 #x33 #x33 #x66 #x1ff #xcc #xcc #x3fe #x198 #x330 #x330)
      ;; $
      (36 9 1 11 7 #x8 #x3e #x6b #x6b #x68 #x7c #x1e #xb #x6b #x6b #x3e #x8)
      ;; %
      (37 14 1 10 12 #x718 #xd98 #xdb0 #x730 #x60 #x60 #xce #xdb #x19b #x18e)
      ;; &
      (38 11 1 10 9 #x70 #xd8 #xd8 #x50 #x70 #xfb #x18e #x18c #x19e #xf7)
      ;; '
      (39 4 1 10 2 #x3 #x3 #x1 #x2)
      ;; (
      (40 6 1 10 4 #x3 #x6 #x6 #xc #xc #xc #xc #xc #xc #x6 #x6 #x3)
      ;; )
      (41 6 1 10 4 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc)
      ;; *
      (42 7 1 10 5 #x4 #x15 #xe #xe #x15 #x4)
      ;; +
      (43 8 1 7 6 #xc #xc #x3f #x3f #xc #xc)
      ;; ,
      (44 4 1 2 2 #x3 #x3 #x1 #x3 #x2)
      ;; -
      (45 9 2 5 6 #x3f #x3f)
      ;; .
      (46 4 1 2 2 #x3 #x3)
      ;; /
      (47 8 1 10 6 #x3 #x3 #x6 #x6 #xc #xc #x18 #x18 #x30 #x30)
      ;; 0
      (48 9 1 10 7 #x1c #x36 #x63 #x63 #x63 #x63 #x63 #x63 #x36 #x1c)
      ;; 1
      (49 9 2 10 5 #x3 #x7 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; 2
      (50 9 1 10 7 #x3e #x63 #x63 #x3 #x6 #xc #x18 #x30 #x60 #x7f)
      ;; 3
      (51 9 1 10 7 #x3e #x63 #x63 #x3 #xe #x3 #x3 #x63 #x63 #x3e)
      ;; 4
      (52 9 1 10 7 #x6 #xe #x1e #x16 #x36 #x66 #x66 #x7f #x6 #x6)
      ;; 5
      (53 9 1 10 7 #x3f #x30 #x30 #x7e #x63 #x63 #x3 #x63 #x63 #x3e)
      ;; 6
      (54 9 1 10 7 #x1e #x33 #x63 #x60 #x7e #x63 #x63 #x63 #x63 #x3e)
      ;; 7
      (55 9 1 10 7 #x7f #x3 #x6 #xc #xc #x18 #x18 #x30 #x30 #x30)
      ;; 8
      (56 9 1 10 7 #x3e #x63 #x63 #x63 #x3e #x63 #x63 #x63 #x63 #x3e)
      ;; 9
      (57 9 1 10 7 #x3e #x63 #x63 #x63 #x63 #x3f #x3 #x63 #x66 #x3c)
      ;; :
      (58 4 1 7 2 #x3 #x3 #x0 #x0 #x0 #x3 #x3)
      ;; ;
      (59 4 1 7 2 #x3 #x3 #x0 #x0 #x0 #x3 #x3 #x1 #x3 #x2)
      ;; <
      (60 8 1 10 6 #x3 #x6 #xc #x18 #x30 #x30 #x18 #xc #x6 #x3)
      ;; =
      (61 9 2 7 6 #x3f #x3f #x0 #x3f #x3f)
      ;; >
      (62 8 1 10 6 #x30 #x18 #xc #x6 #x3 #x3 #x6 #xc #x18 #x30)
      ;; ?
      (63 8 1 10 6 #x1e #x33 #x33 #x3 #x6 #xc #xc #x0 #xc #xc)
      ;; @
      (64 14 1 10 12 #x3fc #x606 #xcf3 #xd9b #xd9b #xd9b #xd9a #xcec #x601
        #x3fe)
      ;; A
      (65 9 1 10 8 #x18 #x18 #x3c #x3c #x24 #x66 #x7e #x66 #xc3 #xc3)
      ;; B
      (66 8 1 10 7 #x7c #x66 #x66 #x66 #x7e #x63 #x63 #x63 #x63 #x7e)
      ;; C
      (67 9 1 10 8 #x3e #x63 #xc3 #xc0 #xc0 #xc0 #xc3 #xc3 #x63 #x3e)
      ;; D
      (68 9 1 10 8 #xfc #xc6 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6 #xfc)
      ;; E
      (69 8 1 10 7 #x7f #x60 #x60 #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; F
      (70 8 1 10 7 #x7f #x60 #x60 #x60 #x7e #x60 #x60 #x60 #x60 #x60)
      ;; G
      (71 10 1 10 9 #x7e #xc3 #x183 #x180 #x180 #x18f #x183 #x183 #xc7 #x7b)
      ;; H
      (72 9 1 10 8 #xc3 #xc3 #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; I
      (73 3 1 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; J
      (74 7 1 10 6 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x33 #x33 #x1e)
      ;; K
      (75 9 1 10 8 #xc6 #xcc #xd8 #xf0 #xe0 #xf0 #xd8 #xcc #xc6 #xc3)
      ;; L
      (76 7 1 10 6 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x3f)
      ;; M
      (77 12 1 10 11 #x707 #x707 #x78f #x78f #x6db #x6db #x6db #x673 #x673
        #x623)
      ;; N
      (78 9 1 10 8 #xc3 #xe3 #xe3 #xf3 #xf3 #xdb #xdb #xcf #xcf #xc7)
      ;; O
      (79 10 1 10 9 #x7c #xc6 #x183 #x183 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; P
      (80 8 1 10 7 #x7e #x63 #x63 #x63 #x63 #x7e #x60 #x60 #x60 #x60)
      ;; Q
      (81 10 1 10 9 #x7c #xc6 #x183 #x183 #x183 #x183 #x183 #x19b #xce #x7e
        #x3)
      ;; R
      (82 9 1 10 8 #xfe #xc3 #xc3 #xc3 #xfe #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; S
      (83 8 1 10 7 #x3e #x63 #x63 #x78 #x3e #xf #x63 #x63 #x63 #x3e)
      ;; T
      (84 9 1 10 8 #xff #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18)
      ;; U
      (85 9 1 10 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; V
      (86 9 1 10 8 #xc3 #xc3 #xc3 #x66 #x66 #x66 #x24 #x3c #x18 #x18)
      ;; W
      (87 14 1 10 13 #x1843 #x1843 #xce6 #xce6 #xce6 #x5f4 #x7bc #x71c #x318
        #x318)
      ;; X
      (88 9 1 10 8 #xc3 #xc3 #x66 #x3c #x18 #x18 #x3c #x66 #xc3 #xc3)
      ;; Y
      (89 9 1 10 8 #xc3 #xc3 #x66 #x66 #x3c #x18 #x18 #x18 #x18 #x18)
      ;; Z
      (90 10 1 10 9 #xff #x3 #x6 #xc #x18 #x30 #x60 #xc0 #x180 #x1ff)
      ;; [
      (91 7 1 10 5 #x1f #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18
        #x1f)
      ;; \
      (92 8 1 10 6 #x30 #x30 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ]
      (93 7 1 10 5 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x1f)
      ;; ^
      (94 8 1 10 6 #xc #x1e #x33)
      ;; _
      (95 10 1 -1 8 #xff #xff)
      ;; `
      (96 4 1 10 2 #x3 #x3 #x2 #x1)
      ;; a
      (97 8 1 7 7 #x3c #x66 #x6 #x3e #x66 #x66 #x3b)
      ;; b
      (98 8 1 10 7 #x60 #x60 #x60 #x7e #x63 #x63 #x63 #x63 #x63 #x7e)
      ;; c
      (99 8 1 7 7 #x3e #x63 #x60 #x60 #x63 #x63 #x3e)
      ;; d
      (100 8 1 10 7 #x3 #x3 #x3 #x3f #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; e
      (101 8 1 7 7 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; f
      (102 6 1 10 5 #x7 #xc #xc #x1f #xc #xc #xc #xc #xc #xc)
      ;; g
      (103 8 1 7 7 #x3f #x63 #x63 #x63 #x63 #x63 #x3f #x3 #x63 #x3e)
      ;; h
      (104 8 1 10 7 #x60 #x60 #x60 #x7e #x63 #x63 #x63 #x63 #x63 #x63)
      ;; i
      (105 3 1 10 2 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; j
      (106 5 0 10 4 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #xe)
      ;; k
      (107 8 1 10 7 #x60 #x60 #x60 #x66 #x6c #x78 #x78 #x6c #x66 #x63)
      ;; l
      (108 3 1 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; m
      (109 11 1 7 10 #x3ee #x333 #x333 #x333 #x333 #x333 #x333)
      ;; n
      (110 8 1 7 7 #x7e #x63 #x63 #x63 #x63 #x63 #x63)
      ;; o
      (111 8 1 7 7 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; p
      (112 8 1 7 7 #x7e #x63 #x63 #x63 #x63 #x63 #x7e #x60 #x60 #x60)
      ;; q
      (113 8 1 7 7 #x3f #x63 #x63 #x63 #x63 #x63 #x3f #x3 #x3 #x3)
      ;; r
      (114 6 1 7 5 #x1f #x1b #x18 #x18 #x18 #x18 #x18)
      ;; s
      (115 7 1 7 6 #x1e #x33 #x38 #x1e #x7 #x33 #x1e)
      ;; t
      (116 6 1 9 5 #xc #xc #x1f #xc #xc #xc #xc #xc #x7)
      ;; u
      (117 8 1 7 7 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; v
      (118 9 1 7 8 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18)
      ;; w
      (119 12 1 7 11 #x623 #x623 #x376 #x376 #x3de #x18c #x18c)
      ;; x
      (120 7 1 7 6 #x33 #x33 #x1e #xc #x1e #x33 #x33)
      ;; y
      (121 8 1 7 7 #x63 #x63 #x33 #x36 #x16 #x1e #xc #xc #x6c #x38)
      ;; z
      (122 7 1 7 6 #x3f #x3 #x6 #xc #x18 #x30 #x3f)
      ;; {
      (123 8 1 10 6 #x7 #xc #xc #xc #xc #xc #x38 #xc #xc #xc #xc #xc #x7)
      ;; |
      (124 5 2 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; }
      (125 8 1 10 6 #x38 #xc #xc #xc #xc #xc #x7 #xc #xc #xc #xc #xc #x38)
      ;; ~
      (126 10 1 8 8 #x33 #x7e #xcc)
      ;; ¬
      (172 7 1 5 5 #x1f #x1f #x3)
      ;; °
      (176 6 1 10 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 8 1 9 6 #xc #xc #x3f #x3f #xc #xc #x0 #x3f #x3f)
      ;; µ
      (181 8 1 7 7 #x63 #x63 #x63 #x63 #x63 #x63 #x3f #x60 #x60 #x60)
      ;; ·
      (183 5 1 7 3 #x7 #x7 #x7)
      ;; À
      (192 9 1 11 8 #x30 #x18 #x0 #x18 #x3c #x24 #x66 #x7e #x66 #xc3 #xc3)
      ;; Á
      (193 9 1 11 8 #x18 #x30 #x0 #x18 #x3c #x24 #x66 #x7e #x66 #xc3 #xc3)
      ;; Â
      (194 9 1 11 8 #x18 #x3c #x0 #x18 #x3c #x24 #x66 #x7e #x66 #xc3 #xc3)
      ;; Ã
      (195 9 1 11 8 #x3c #x78 #x0 #x18 #x3c #x24 #x66 #x7e #x66 #xc3 #xc3)
      ;; Ä
      (196 9 1 11 8 #x3c #x0 #x18 #x18 #x3c #x24 #x66 #x7e #x66 #xc3 #xc3)
      ;; Å
      (197 9 1 11 8 #x18 #x3c #x18 #x18 #x3c #x24 #x66 #x7e #x66 #xc3 #xc3)
      ;; Ç
      (199 9 1 10 8 #x3e #x63 #xc3 #xc0 #xc0 #xc0 #xc3 #xc3 #x63 #x3e #x18
        #x30)
      ;; È
      (200 8 1 11 7 #x30 #x18 #x0 #x7f #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; É
      (201 8 1 11 7 #x18 #x30 #x0 #x7f #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; Ê
      (202 8 1 11 7 #x18 #x3c #x0 #x7f #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; Ë
      (203 8 1 11 7 #x3c #x0 #x7f #x60 #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; Ì
      (204 3 0 11 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; Í
      (205 3 0 11 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; Î
      (206 3 0 11 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; Ï
      (207 3 0 11 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; Ñ
      (209 9 1 11 8 #x3c #x78 #x0 #xc3 #xe3 #xf3 #xdb #xdb #xcf #xcf #xc7)
      ;; Ò
      (210 10 1 11 9 #x60 #x30 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; Ó
      (211 10 1 11 9 #x30 #x60 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; Ô
      (212 10 1 11 9 #x30 #x78 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; Õ
      (213 10 1 11 9 #x78 #xf0 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; Ö
      (214 10 1 11 9 #x78 #x0 #x7c #xc6 #x183 #x183 #x183 #x183 #x183 #xc6
        #x7c)
      ;; ×
      (215 7 1 7 6 #x33 #x33 #x1e #xc #x1e #x33 #x33)
      ;; Ù
      (217 9 1 11 8 #x30 #x18 #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ú
      (218 9 1 11 8 #x18 #x30 #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Û
      (219 9 1 11 8 #x18 #x3c #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ü
      (220 9 1 11 8 #x3c #x0 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; Ý
      (221 9 1 11 8 #x18 #x30 #x0 #xc3 #x66 #x3c #x18 #x18 #x18 #x18 #x18)
      ;; à
      (224 8 1 10 7 #x30 #x18 #x0 #x3c #x66 #x6 #x3e #x66 #x66 #x3b)
      ;; á
      (225 8 1 10 7 #x18 #x30 #x0 #x3c #x66 #x6 #x3e #x66 #x66 #x3b)
      ;; â
      (226 8 1 10 7 #x18 #x3c #x0 #x3c #x66 #x6 #x3e #x66 #x66 #x3b)
      ;; ã
      (227 8 1 10 7 #x3c #x78 #x0 #x3c #x66 #x6 #x3e #x66 #x66 #x3b)
      ;; ä
      (228 8 1 9 7 #x3c #x0 #x3c #x66 #x6 #x3e #x66 #x66 #x3b)
      ;; å
      (229 8 1 11 7 #x18 #x3c #x18 #x0 #x3c #x66 #x6 #x3e #x66 #x66 #x3b)
      ;; ç
      (231 8 1 7 7 #x3e #x63 #x60 #x60 #x63 #x63 #x3e #x18 #x30)
      ;; è
      (232 8 1 10 7 #x30 #x18 #x0 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; é
      (233 8 1 10 7 #x18 #x30 #x0 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; ê
      (234 8 1 10 7 #x18 #x3c #x0 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; ë
      (235 8 1 9 7 #x3c #x0 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; ì
      (236 3 0 10 3 #x6 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; í
      (237 3 0 10 3 #x3 #x6 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; î
      (238 3 0 10 4 #x6 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ï
      (239 3 0 9 4 #xf #x0 #x6 #x6 #x6 #x6 #x6 #x6 #x6)
      ;; ñ
      (241 8 1 10 7 #x3c #x78 #x0 #x7e #x63 #x63 #x63 #x63 #x63 #x63)
      ;; ò
      (242 8 1 10 7 #x30 #x18 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ó
      (243 8 1 10 7 #x18 #x30 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ô
      (244 8 1 10 7 #x18 #x3c #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; õ
      (245 8 1 10 7 #x3c #x78 #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ö
      (246 8 1 9 7 #x3c #x0 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; ù
      (249 8 1 10 7 #x30 #x18 #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; ú
      (250 8 1 10 7 #x18 #x30 #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; û
      (251 8 1 10 7 #x18 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; ü
      (252 8 1 9 7 #x3c #x0 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; ý
      (253 8 1 10 7 #x18 #x30 #x0 #x63 #x63 #x33 #x36 #x16 #x1e #xc #xc #x6c
        #x38)
      ;; ÿ
      (255 8 1 9 7 #x3c #x0 #x63 #x63 #x33 #x36 #x16 #x1e #xc #xc #x6c #x38)
      ;; α
      (945 10 1 5 8 #x7b #xce #xcc #xcc #x7b)
      ;; β
      (946 9 0 8 8 #x3e #x63 #x63 #x7e #x63 #x63 #x73 #x6e #x60 #x60 #xc0)
      ;; γ
      (947 9 1 9 7 #x3 #x3e #x6c #x1c #x34 #x34 #x34 #x3c #x18)
      ;; δ
      (948 8 1 10 6 #xe #x1b #x18 #x1c #xe #x1b #x33 #x33 #x37 #x1e)
      ;; ε
      (949 7 1 7 5 #x7 #xc #x18 #x1f #x18 #xc #x7)
      ;; λ
      (955 9 1 9 7 #x60 #x60 #x30 #x18 #x1c #x1e #x36 #x33 #x63)
      ;; π
      (960 10 1 7 9 #xff #x166 #x66 #x66 #x66 #x66 #xc6)
      ;; –
      (8211 8 0 5 7 #x7f #x7f)
      ;; —
      (8212 12 0 5 12 #xfff #xfff)
      ;; ‘
      (8216 4 1 10 2 #x3 #x3 #x1 #x2)
      ;; ’
      (8217 4 1 10 2 #x3 #x3 #x1 #x2)
      ;; “
      (8220 7 1 10 5 #x1b #x1b #x1b #x1b)
      ;; ”
      (8221 7 1 10 5 #x1b #x1b #x1b #x1b)
      ;; …
      (8230 12 1 2 10 #x333 #x333)
      ;; ←
      (8592 10 1 8 8 #x20 #x60 #xff #xff #x60 #x20)
      ;; ↑
      (8593 8 1 9 6 #xc #x1e #x3f #xc #xc #xc #xc #xc)
      ;; →
      (8594 10 1 8 8 #x4 #x6 #xff #xff #x6 #x4)
      ;; ↓
      (8595 8 1 9 6 #xc #xc #xc #xc #xc #x3f #x1e #xc)
      ;; ↔
      (8596 12 1 8 9 #x44 #xc6 #x1ff #x1ff #xc6 #x44)
      ;; ↳
      (8627 10 1 10 8 #xc0 #xc0 #xc4 #xc6 #xff #xff #x6 #x4)
      ;; ∀
      (8704 8 1 10 6 #x33 #x33 #x33 #x3f #x33 #x12 #x1e #x1e #xc #xc)
      ;; ∂
      (8706 9 1 10 7 #x3c #x66 #x3 #x3 #x3f #x77 #x63 #x63 #x76 #x3c)
      ;; ∃
      (8707 8 1 10 7 #x7f #x3 #x3 #x3 #x3f #x3 #x3 #x3 #x3 #x7f)
      ;; −
      (8722 8 1 5 6 #x3f #x3f)
      ;; ∞
      (8734 11 1 8 9 #xee #x1ff #x1bb #x1bb #x1ff #xee)
      ;; ∧
      (8743 9 1 7 7 #x8 #x1c #x36 #x63)
      ;; ∨
      (8744 9 1 6 7 #x63 #x36 #x1c #x8)
      ;; ∩
      (8745 8 1 9 6 #x1e #x33 #x33 #x33 #x33 #x33 #x33)
      ;; ∪
      (8746 8 1 9 6 #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; ∫
      (8747 8 1 10 6 #x6 #xd #xc #xc #xc #xc #xc #xc #x2c #x18)
      ;; ≠
      (8800 9 2 8 6 #x3 #x6 #x3f #x3f #xc #x3f #x3f #x18 #x30)
      ;; ≡
      (8801 8 1 8 6 #x3f #x3f #x0 #x3f #x3f #x0 #x3f #x3f)
      ;; ≤
      (8804 6 1 9 4 #x3 #x6 #xc #xc #x6 #x3 #x0 #xf #xf)
      ;; ≥
      (8805 6 1 9 4 #xc #x6 #x3 #x3 #x6 #xc #x0 #xf #xf)
      ;; ⊂
      (8834 8 1 8 6 #x1f #x3f #x30 #x30 #x3f #x1f)
      ;; ⊃
      (8835 8 1 8 6 #x3e #x3f #x3 #x3 #x3f #x3e)
      ;; ⊕
      (8853 10 1 9 8 #x3c #x7e #xdb #xff #xdb #x7e #x3c)
      ;; ⊗
      (8855 10 1 9 8 #x3c #x66 #xff #xdb #xff #x66 #x3c)
      ;; ⋅
      (8901 5 1 7 3 #x7 #x7 #x7)
      ;; ▶
      (9654 7 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 9 1 9 7 #x8 #x8 #x1c #x36 #x63 #x36 #x1c #x8 #x8)
      ;; ◊
      (9674 9 1 9 7 #x8 #x8 #x1c #x36 #x63 #x36 #x1c #x8 #x8)
      ;; ⚙
      (9881 13 1 11 11 #x70 #x124 #x3fe #x1fc #x58d #x78f #x58d #x1fc #x3fe
        #x124 #x70)
      ;; ⚠
      (9888 13 1 11 11 #x20 #x20 #x50 #x88 #xa8 #xa8 #x124 #x222 #x202 #x222
        #x7ff)
      ;; ✓
      (10003 9 0 8 8 #x3 #x3 #x6 #x6 #xcc #x6c #x38 #x18)
      ;; ❚
      (10074 6 1 10 4 #xf #xf #xf #xf #xf #xf #xf #xf #xf #xf))
     ("CADR HL12 Italic" 14 11 3
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
      (39 4 2 10 2 #x1 #x1 #x2)
      ;; (
      (40 7 2 10 5 #x1 #x2 #x4 #x8 #x8 #x10 #x10 #x10 #x10 #x10 #x10 #x8 #x8)
      ;; )
      (41 7 2 10 5 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4 #x8 #x10)
      ;; *
      (42 7 2 10 5 #x4 #x15 #xe #x15 #x4)
      ;; +
      (43 8 2 7 6 #x4 #x4 #x4 #x3f #x8 #x8 #x8)
      ;; ,
      (44 4 1 2 3 #x3 #x1 #x1 #x6)
      ;; -
      (45 7 2 5 5 #x1f)
      ;; .
      (46 3 1 2 1 #x1 #x1)
      ;; /
      (47 9 2 10 7 #x1 #x2 #x2 #x4 #x8 #x8 #x10 #x20 #x20 #x40)
      ;; 0
      (48 9 2 10 7 #xc #x32 #x21 #x41 #x41 #x41 #x41 #x42 #x26 #x18)
      ;; 1
      (49 9 3 10 5 #x3 #x7 #x9 #x12 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; 2
      (50 9 2 10 7 #xe #x11 #x21 #x21 #x2 #xc #x10 #x20 #x40 #x7f)
      ;; 3
      (51 9 2 10 7 #xe #x11 #x21 #x2 #x1c #x2 #x2 #x42 #x44 #x38)
      ;; 4
      (52 9 2 10 7 #x3 #x3 #x5 #x9 #x12 #x22 #x42 #x7f #x4 #x4)
      ;; 5
      (53 9 2 10 7 #x1f #x10 #x20 #x3c #x42 #x42 #x2 #x42 #x44 #x38)
      ;; 6
      (54 9 2 10 7 #xe #x11 #x20 #x2e #x71 #x41 #x41 #x41 #x22 #x1c)
      ;; 7
      (55 9 3 10 6 #x3f #x1 #x2 #x4 #x8 #x8 #x10 #x10 #x20 #x20)
      ;; 8
      (56 9 2 10 7 #xe #x11 #x11 #x11 #x1e #x21 #x41 #x41 #x42 #x3c)
      ;; 9
      (57 9 2 10 7 #x1c #x22 #x41 #x41 #x41 #x21 #x1f #x2 #x42 #x3c)
      ;; :
      (58 4 2 7 2 #x1 #x1 #x0 #x0 #x0 #x2 #x2)
      ;; ;
      (59 5 1 7 4 #x1 #x1 #x0 #x0 #x0 #x6 #x2 #x2 #xc)
      ;; <
      (60 8 1 9 7 #x1 #x6 #x18 #x60 #x40 #x20 #x10 #x8 #x4)
      ;; =
      (61 8 1 6 7 #x3f #x0 #x7e)
      ;; >
      (62 9 1 9 8 #x10 #x8 #x4 #x2 #x1 #x6 #x18 #x60 #x80)
      ;; ?
      (63 8 2 10 6 #xe #x11 #x21 #x1 #x6 #x8 #x8 #x0 #x10 #x10)
      ;; @
      (64 14 2 10 12 #xfc #x302 #x469 #x499 #x911 #x911 #x932 #x8dc #x400
        #x3fc)
      ;; A
      (65 9 1 10 7 #x3 #x5 #x5 #x9 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; B
      (66 9 1 10 8 #x3e #x21 #x21 #x41 #x7e #x41 #x41 #x81 #x82 #xfc)
      ;; C
      (67 9 1 10 8 #xe #x31 #x41 #x40 #x80 #x80 #x81 #x81 #x42 #x3c)
      ;; D
      (68 10 1 10 9 #x7c #x42 #x41 #x81 #x81 #x81 #x82 #x102 #x10c #x1f0)
      ;; E
      (69 10 1 10 9 #x7f #x40 #x40 #x80 #xfc #x80 #x80 #x100 #x100 #x1fc)
      ;; F
      (70 8 1 10 8 #x3f #x20 #x20 #x40 #x7c #x40 #x40 #x80 #x80 #x80)
      ;; G
      (71 10 1 10 9 #x1e #x61 #x81 #x80 #x100 #x10f #x101 #x101 #x86 #x7a)
      ;; H
      (72 10 1 10 9 #x41 #x41 #x41 #x82 #xfe #x82 #x82 #x104 #x104 #x104)
      ;; I
      (73 4 1 10 3 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; J
      (74 7 1 10 7 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x44 #x44 #x38)
      ;; K
      (75 9 1 10 8 #x21 #x22 #x24 #x48 #x70 #x50 #x48 #x88 #x84 #x84)
      ;; L
      (76 8 1 10 7 #x10 #x10 #x10 #x20 #x20 #x20 #x20 #x40 #x40 #x7f)
      ;; M
      (77 12 1 10 12 #x303 #x305 #x305 #x50a #x50a #x512 #x4a2 #x8a4 #x8c4
        #x8c4)
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
      (83 9 1 10 8 #x1e #x21 #x41 #x40 #x3c #x2 #x1 #x81 #x82 #x7c)
      ;; T
      (84 10 2 10 9 #x1ff #x10 #x10 #x20 #x20 #x20 #x20 #x40 #x40 #x40)
      ;; U
      (85 10 1 10 9 #x41 #x41 #x41 #x82 #x82 #x82 #x102 #x104 #x104 #xf8)
      ;; V
      (86 10 2 10 8 #x81 #x81 #x82 #x84 #x84 #x88 #x90 #x90 #xa0 #xc0)
      ;; W
      (87 14 2 10 12 #x861 #x861 #x8a2 #x8a2 #x924 #x924 #xa28 #xa28 #xc30
        #xc30)
      ;; X
      (88 10 1 10 9 #x41 #x42 #x24 #x28 #x10 #x10 #x28 #x48 #x84 #x104)
      ;; Y
      (89 10 1 10 9 #x101 #x102 #x84 #x88 #x50 #x60 #x40 #x40 #x80 #x80)
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
      (94 6 1 10 5 #x4 #xa #x11)
      ;; _
      (95 7 0 -2 6 #x3f)
      ;; `
      (96 4 2 10 2 #x2 #x2 #x1)
      ;; a
      (97 8 1 7 7 #x1e #x21 #x1 #x3f #x42 #x42 #x3d)
      ;; b
      (98 8 1 10 7 #x10 #x10 #x10 #x3e #x21 #x21 #x21 #x41 #x62 #x5c)
      ;; c
      (99 8 1 7 7 #x1e #x21 #x41 #x40 #x42 #x42 #x3c)
      ;; d
      (100 8 1 10 8 #x1 #x1 #x1 #x1e #x62 #x42 #x82 #x84 #x8c #x74)
      ;; e
      (101 8 1 7 7 #xe #x31 #x21 #x7f #x40 #x42 #x3c)
      ;; f
      (102 6 1 10 6 #x7 #x8 #x8 #x3e #x10 #x10 #x10 #x20 #x20 #x20)
      ;; g
      (103 8 0 7 8 #x1d #x23 #x41 #x42 #x42 #x42 #x3e #x4 #xc4 #x78)
      ;; h
      (104 8 1 10 7 #x10 #x10 #x10 #x3e #x21 #x21 #x21 #x41 #x42 #x42)
      ;; i
      (105 4 1 10 3 #x1 #x1 #x0 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; j
      (106 5 0 10 5 #x1 #x1 #x0 #x2 #x2 #x2 #x2 #x4 #x4 #x4 #x4 #x18)
      ;; k
      (107 7 1 10 6 #x8 #x8 #x8 #x11 #x12 #x14 #x1a #x22 #x21 #x21)
      ;; l
      (108 4 1 10 3 #x1 #x1 #x1 #x2 #x2 #x2 #x2 #x4 #x4 #x4)
      ;; m
      (109 11 1 7 10 #x176 #x199 #x111 #x111 #x211 #x222 #x222)
      ;; n
      (110 8 1 7 7 #x2e #x31 #x21 #x21 #x41 #x42 #x42)
      ;; o
      (111 8 1 7 7 #x1e #x21 #x41 #x41 #x41 #x42 #x3c)
      ;; p
      (112 8 0 7 8 #x2e #x31 #x21 #x41 #x41 #x42 #x7c #x80 #x80 #x80)
      ;; q
      (113 8 1 7 7 #x1d #x23 #x41 #x42 #x42 #x42 #x3e #x4 #x4 #x4)
      ;; r
      (114 6 1 7 6 #x17 #x18 #x10 #x10 #x20 #x20 #x20)
      ;; s
      (115 7 1 7 6 #xe #x11 #x10 #xe #x21 #x21 #x1e)
      ;; t
      (116 7 2 9 5 #x4 #x4 #x1f #x8 #x8 #x8 #x10 #x10 #xe)
      ;; u
      (117 8 1 7 7 #x21 #x21 #x21 #x42 #x42 #x46 #x3a)
      ;; v
      (118 7 2 7 5 #x11 #x11 #x12 #x12 #x14 #x14 #x18)
      ;; w
      (119 12 2 7 10 #x231 #x231 #x252 #x252 #x294 #x294 #x318)
      ;; x
      (120 8 1 7 7 #x21 #x22 #x14 #x8 #x14 #x22 #x42)
      ;; y
      (121 8 0 7 8 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x90 #x60)
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
      (172 7 1 6 5 #x1f #x1 #x2)
      ;; °
      (176 6 1 10 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 8 1 9 7 #x4 #x4 #x4 #x3f #x8 #x8 #x8 #x0 #x7e)
      ;; µ
      (181 8 1 7 7 #x21 #x21 #x21 #x42 #x42 #x46 #x3a #x40 #x40 #x40)
      ;; ·
      (183 4 1 5 2 #x3 #x3)
      ;; À
      (192 9 1 11 7 #x10 #x8 #x0 #x3 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Á
      (193 9 1 11 7 #x8 #x10 #x0 #x3 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Â
      (194 9 1 11 7 #x10 #x28 #x0 #x3 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Ã
      (195 9 1 11 7 #x14 #x28 #x0 #x3 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Ä
      (196 9 1 11 7 #x28 #x0 #x3 #x5 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Å
      (197 9 1 11 7 #x10 #x28 #x10 #x3 #x5 #x9 #x11 #x21 #x3f #x41 #x41)
      ;; Ç
      (199 9 1 10 8 #xe #x31 #x41 #x40 #x80 #x80 #x81 #x81 #x42 #x3c #x8 #x10)
      ;; È
      (200 10 1 11 9 #x20 #x10 #x0 #x7f #x40 #x80 #xfc #x80 #x100 #x100 #x1fc)
      ;; É
      (201 10 1 11 9 #x10 #x20 #x0 #x7f #x40 #x80 #xfc #x80 #x100 #x100 #x1fc)
      ;; Ê
      (202 10 1 11 9 #x20 #x50 #x0 #x7f #x40 #x80 #xfc #x80 #x100 #x100 #x1fc)
      ;; Ë
      (203 10 1 11 9 #x50 #x0 #x7f #x40 #x80 #xfc #x80 #x80 #x100 #x100 #x1fc)
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
      (221 10 1 11 9 #x10 #x20 #x0 #x101 #x84 #x88 #x50 #x60 #x40 #x80 #x80)
      ;; à
      (224 8 1 10 7 #x10 #x8 #x0 #x1e #x21 #x1 #x3f #x42 #x42 #x3d)
      ;; á
      (225 8 1 10 7 #x8 #x10 #x0 #x1e #x21 #x1 #x3f #x42 #x42 #x3d)
      ;; â
      (226 8 1 10 7 #x10 #x28 #x0 #x1e #x21 #x1 #x3f #x42 #x42 #x3d)
      ;; ã
      (227 8 1 10 7 #x14 #x28 #x0 #x1e #x21 #x1 #x3f #x42 #x42 #x3d)
      ;; ä
      (228 8 1 9 7 #x28 #x0 #x1e #x21 #x1 #x3f #x42 #x42 #x3d)
      ;; å
      (229 8 1 11 7 #x10 #x28 #x10 #x0 #x1e #x21 #x1 #x3f #x42 #x42 #x3d)
      ;; ç
      (231 8 1 7 7 #x1e #x21 #x41 #x40 #x42 #x42 #x3c #x8 #x10)
      ;; è
      (232 8 1 10 7 #x10 #x8 #x0 #xe #x31 #x21 #x7f #x40 #x42 #x3c)
      ;; é
      (233 8 1 10 7 #x8 #x10 #x0 #xe #x31 #x21 #x7f #x40 #x42 #x3c)
      ;; ê
      (234 8 1 10 7 #x10 #x28 #x0 #xe #x31 #x21 #x7f #x40 #x42 #x3c)
      ;; ë
      (235 8 1 9 7 #x28 #x0 #xe #x31 #x21 #x7f #x40 #x42 #x3c)
      ;; ì
      (236 4 1 10 2 #x2 #x1 #x0 #x1 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; í
      (237 4 1 10 2 #x1 #x2 #x0 #x1 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; î
      (238 4 0 10 3 #x2 #x5 #x0 #x1 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; ï
      (239 4 0 9 3 #x5 #x0 #x1 #x1 #x1 #x1 #x2 #x2 #x2)
      ;; ñ
      (241 8 1 10 7 #x14 #x28 #x0 #x2e #x31 #x21 #x21 #x41 #x42 #x42)
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
      (253 8 0 10 8 #x8 #x10 #x0 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x90
        #x60)
      ;; ÿ
      (255 8 0 9 8 #x28 #x0 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8 #x90 #x60)
      ;; α
      (945 8 1 6 7 #x1d #x22 #x22 #x44 #x44 #x3a)
      ;; β
      (946 9 0 9 8 #x6 #x9 #x9 #x12 #x1c #x12 #x22 #x22 #x3c #x40 #x40 #x80)
      ;; γ
      (947 6 1 8 5 #x1 #xa #x14 #xc #x14 #x14 #x14 #x8)
      ;; δ
      (948 7 1 9 5 #x6 #x9 #x8 #x4 #x6 #x9 #x11 #x11 #xe)
      ;; ε
      (949 6 1 5 5 #x7 #x8 #x1e #x10 #xe)
      ;; λ
      (955 8 1 8 6 #x10 #x10 #x10 #x8 #x8 #x14 #x12 #x21)
      ;; π
      (960 9 1 6 7 #x3f #x52 #x12 #x24 #x24 #x24)
      ;; –
      (8211 8 0 5 7 #x7f)
      ;; —
      (8212 12 0 5 12 #xfff)
      ;; ‘
      (8216 4 2 10 2 #x1 #x1 #x2)
      ;; ’
      (8217 4 2 10 2 #x1 #x1 #x2)
      ;; “
      (8220 7 2 10 5 #x9 #x9 #x12 #x12)
      ;; ”
      (8221 7 2 10 5 #x9 #x9 #x12 #x12)
      ;; …
      (8230 9 1 2 7 #x49 #x49)
      ;; ←
      (8592 8 1 8 7 #x10 #x20 #x7f #x20 #x20)
      ;; ↑
      (8593 6 1 11 5 #x4 #xe #x15 #x4 #x8 #x8 #x8 #x10 #x10 #x10)
      ;; →
      (8594 8 1 8 7 #x2 #x2 #x7f #x2 #x4)
      ;; ↓
      (8595 6 1 10 5 #x1 #x1 #x1 #x2 #x2 #x2 #x15 #xe #x4)
      ;; ↔
      (8596 9 1 8 8 #x22 #x42 #xff #x42 #x44)
      ;; ↳
      (8627 8 1 10 7 #x40 #x40 #x42 #x42 #x7f #x2 #x4)
      ;; ∀
      (8704 7 1 9 6 #x21 #x21 #x22 #x22 #x3c #x24 #x28 #x28 #x10)
      ;; ∂
      (8706 7 1 8 5 #xc #x2 #x1 #x7 #x9 #x11 #x12 #xc)
      ;; ∃
      (8707 8 1 9 7 #x1f #x1 #x1 #x2 #x3e #x2 #x4 #x4 #x7c)
      ;; −
      (8722 8 2 4 6 #x3f)
      ;; ∞
      (8734 9 1 6 7 #x36 #x49 #x49 #x76)
      ;; ∧
      (8743 7 1 7 5 #x4 #xa #x11)
      ;; ∨
      (8744 7 1 7 5 #x11 #xa #x4)
      ;; ∩
      (8745 7 1 7 6 #xe #x11 #x11 #x22 #x22)
      ;; ∪
      (8746 7 1 7 6 #x11 #x11 #x22 #x22 #x1c)
      ;; ∫
      (8747 8 1 10 8 #x2 #x5 #x5 #x8 #x8 #x8 #x10 #x10 #x10 #xa0 #xa0 #x40)
      ;; ≠
      (8800 8 1 8 7 #x1 #x2 #x3f #x8 #x7e #x20 #x40)
      ;; ≡
      (8801 9 1 6 8 #x3f #x0 #x7e #x0 #xfc)
      ;; ≤
      (8804 7 1 9 6 #x1 #x6 #x18 #x10 #x8 #x4 #x2 #x0 #x3e)
      ;; ≥
      (8805 8 1 9 7 #x8 #x4 #x2 #x1 #x6 #x18 #x20 #x0 #x7e)
      ;; ⊂
      (8834 7 1 7 6 #x1f #x20 #x20 #x3e)
      ;; ⊃
      (8835 7 1 7 6 #x1e #x1 #x1 #x3e)
      ;; ⊕
      (8853 8 1 8 7 #x1c #x2a #x49 #x7f #x49 #x2a #x1c)
      ;; ⊗
      (8855 8 1 8 7 #x1c #x22 #x55 #x49 #x55 #x22 #x1c)
      ;; ⋅
      (8901 4 1 5 2 #x3 #x3)
      ;; ▶
      (9654 7 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 7 1 8 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
      ;; ◊
      (9674 7 1 8 5 #x4 #x4 #xa #x11 #xa #x4 #x4)
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
     ("CADR HL12 Bold Italic" 14 11 3
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
      (39 5 1 10 4 #x3 #x3 #x6 #xc)
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
      (46 5)
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
      (56 10 2 10 8 #x1e #x33 #x33 #x33 #x3e #x63 #xc3 #xc3 #xc6 #x7c)
      ;; 9
      (57 10 2 10 8 #x3c #x66 #xc3 #xc3 #xc3 #x63 #x3f #x6 #xc6 #x7c)
      ;; :
      (58 5 2 7 3 #x3 #x3 #x0 #x0 #x0 #x6 #x6)
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
      (65 10 1 10 8 #x7 #xf #xf #x1b #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; B
      (66 10 1 10 9 #x7e #x63 #x63 #xc3 #xfe #xc3 #xc3 #x183 #x186 #x1fc)
      ;; C
      (67 10 1 10 9 #x1e #x73 #xc3 #xc0 #x180 #x180 #x183 #x183 #xc6 #x7c)
      ;; D
      (68 11 1 10 10 #xfc #xc6 #xc3 #x183 #x183 #x183 #x186 #x306 #x31c #x3f0)
      ;; E
      (69 11 1 10 10 #xff #xc0 #xc0 #x180 #x1fc #x180 #x180 #x300 #x300 #x3fc)
      ;; F
      (70 9 1 10 9 #x7f #x60 #x60 #xc0 #xfc #xc0 #xc0 #x180 #x180 #x180)
      ;; G
      (71 11 1 10 10 #x3e #xe3 #x183 #x180 #x300 #x31f #x303 #x303 #x18e #xfe)
      ;; H
      (72 11 1 10 10 #xc3 #xc3 #xc3 #x186 #x1fe #x186 #x186 #x30c #x30c #x30c)
      ;; I
      (73 5 1 10 4 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xc #xc #xc)
      ;; J
      (74 8 1 10 8 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xcc #xcc #x78)
      ;; K
      (75 10 1 10 9 #x63 #x66 #x6c #xd8 #xf0 #xf0 #xd8 #x198 #x18c #x18c)
      ;; L
      (76 9 1 10 8 #x30 #x30 #x30 #x60 #x60 #x60 #x60 #xc0 #xc0 #xff)
      ;; M
      (77 13 1 10 13 #x707 #x70f #x70f #xf1e #xf1e #xf36 #xde6 #x19ec #x19cc
        #x19cc)
      ;; N
      (78 12 1 10 11 #x1c3 #x1c3 #x1e3 #x366 #x366 #x336 #x336 #x63c #x61c
        #x61c)
      ;; O
      (79 11 1 10 10 #x7c #x1c6 #x183 #x303 #x303 #x303 #x303 #x306 #x18e #xf8)
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
      (86 11 2 10 9 #x183 #x183 #x186 #x18c #x18c #x198 #x1b0 #x1b0 #x1e0
        #x1c0)
      ;; W
      (87 15 2 10 13 #x18e3 #x18e3 #x19e6 #x19e6 #x1b6c #x1b6c #x1e78 #x1e78
        #x1c70 #x1c70)
      ;; X
      (88 11 1 10 10 #xc3 #xc6 #x6c #x78 #x30 #x30 #x78 #xd8 #x18c #x30c)
      ;; Y
      (89 11 1 10 10 #x303 #x306 #x18c #x198 #xf0 #xe0 #xc0 #xc0 #x180 #x180)
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
      (94 8 1 10 6 #xc #x1e #x33)
      ;; _
      (95 8 1 -2 7 #x7f)
      ;; `
      (96 4 1 10 3 #x6 #x6 #x6 #x3)
      ;; a
      (97 9 1 7 8 #x3e #x63 #x3 #x7f #xc6 #xc6 #x7f)
      ;; b
      (98 9 1 10 8 #x30 #x30 #x30 #x7e #x63 #x63 #x63 #xc3 #xe6 #xfc)
      ;; c
      (99 9 1 7 8 #x3e #x63 #xc3 #xc0 #xc6 #xc6 #x7c)
      ;; d
      (100 9 1 10 9 #x3 #x3 #x3 #x3e #xe6 #xc6 #x186 #x18c #x19c #xfc)
      ;; e
      (101 9 1 7 8 #x1e #x73 #x63 #xff #xc0 #xc6 #x7c)
      ;; f
      (102 7 1 10 7 #xf #x18 #x18 #x7e #x30 #x30 #x30 #x60 #x60 #x60)
      ;; g
      (103 9 0 7 9 #x3f #x67 #xc3 #xc6 #xc6 #xc6 #x7e #xc #x1cc #xf8)
      ;; h
      (104 9 1 10 8 #x30 #x30 #x30 #x7e #x63 #x63 #x63 #xc3 #xc6 #xc6)
      ;; i
      (105 5 1 10 4 #x3 #x3 #x0 #x6 #x6 #x6 #x6 #xc #xc #xc)
      ;; j
      (106 6 0 10 6 #x3 #x3 #x0 #x6 #x6 #x6 #x6 #xc #xc #xc #xc #x38)
      ;; k
      (107 8 1 10 7 #x18 #x18 #x18 #x33 #x36 #x3c #x3e #x66 #x63 #x63)
      ;; l
      (108 5 1 10 4 #x3 #x3 #x3 #x6 #x6 #x6 #x6 #xc #xc #xc)
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
      (115 8 1 7 7 #x1e #x33 #x30 #x1e #x63 #x63 #x3e)
      ;; t
      (116 8 2 9 6 #xc #xc #x3f #x18 #x18 #x18 #x30 #x30 #x1e)
      ;; u
      (117 9 1 7 8 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e)
      ;; v
      (118 8 2 7 6 #x33 #x33 #x36 #x36 #x3c #x3c #x38)
      ;; w
      (119 13 2 7 11 #x673 #x673 #x6f6 #x6f6 #x7bc #x7bc #x738)
      ;; x
      (120 9 1 7 8 #x63 #x66 #x3c #x18 #x3c #x66 #xc6)
      ;; y
      (121 9 0 7 9 #xc3 #xc3 #x66 #x66 #x3c #x3c #x18 #x18 #x1b0 #xe0)
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
      (172 1)
      ;; °
      (176 6 1 10 4 #x6 #x9 #x9 #x6)
      ;; ±
      (177 1)
      ;; µ
      (181 9 1 7 8 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e #xc0 #xc0 #xc0)
      ;; ·
      (183 1)
      ;; À
      (192 10 1 11 8 #x30 #x18 #x0 #x7 #xf #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Á
      (193 10 1 11 8 #x18 #x30 #x0 #x7 #xf #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Â
      (194 10 1 11 8 #x18 #x3c #x0 #x7 #xf #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Ã
      (195 10 1 11 8 #x3c #x78 #x0 #x7 #xf #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Ä
      (196 10 1 11 8 #x3c #x0 #x7 #xf #xf #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Å
      (197 10 1 11 8 #x18 #x3c #x18 #x7 #xf #x1b #x33 #x63 #x7f #xc3 #xc3)
      ;; Ç
      (199 10 1 10 9 #x1e #x73 #xc3 #xc0 #x180 #x180 #x183 #x183 #xc6 #x7c
        #x30 #x60)
      ;; È
      (200 11 1 11 10 #x60 #x30 #x0 #xff #xc0 #x180 #x1fc #x180 #x300 #x300
        #x3fc)
      ;; É
      (201 11 1 11 10 #x30 #x60 #x0 #xff #xc0 #x180 #x1fc #x180 #x300 #x300
        #x3fc)
      ;; Ê
      (202 11 1 11 10 #x30 #x78 #x0 #xff #xc0 #x180 #x1fc #x180 #x300 #x300
        #x3fc)
      ;; Ë
      (203 11 1 11 10 #x78 #x0 #xff #xc0 #x180 #x1fc #x180 #x180 #x300 #x300
        #x3fc)
      ;; Ì
      (204 5 1 11 4 #xc #x6 #x0 #x3 #x3 #x3 #x6 #x6 #xc #xc #xc)
      ;; Í
      (205 5 1 11 4 #x6 #xc #x0 #x3 #x3 #x3 #x6 #x6 #xc #xc #xc)
      ;; Î
      (206 5 1 11 4 #x6 #xf #x0 #x3 #x3 #x3 #x6 #x6 #xc #xc #xc)
      ;; Ï
      (207 5 1 11 4 #xf #x0 #x3 #x3 #x3 #x6 #x6 #x6 #xc #xc #xc)
      ;; Ñ
      (209 12 1 11 11 #xf0 #x1e0 #x0 #x1c3 #x1e3 #x366 #x336 #x336 #x63c #x61c
        #x61c)
      ;; Ò
      (210 11 1 11 10 #x60 #x30 #x0 #x7c #x1c6 #x183 #x303 #x303 #x306 #x18e
        #xf8)
      ;; Ó
      (211 11 1 11 10 #x30 #x60 #x0 #x7c #x1c6 #x183 #x303 #x303 #x306 #x18e
        #xf8)
      ;; Ô
      (212 11 1 11 10 #x30 #x78 #x0 #x7c #x1c6 #x183 #x303 #x303 #x306 #x18e
        #xf8)
      ;; Õ
      (213 11 1 11 10 #x78 #xf0 #x0 #x7c #x1c6 #x183 #x303 #x303 #x306 #x18e
        #xf8)
      ;; Ö
      (214 11 1 11 10 #x78 #x0 #x7c #x1c6 #x183 #x303 #x303 #x303 #x306 #x18e
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
      (220 11 1 11 10 #x78 #x0 #xc3 #xc3 #xc3 #x186 #x186 #x306 #x30c #x30c
        #x1f8)
      ;; Ý
      (221 11 1 11 10 #x30 #x60 #x0 #x303 #x18c #x198 #xf0 #xe0 #xc0 #x180
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
      (228 9 1 9 8 #x3c #x0 #x3e #x63 #x3 #x7f #xc6 #xc6 #x7f)
      ;; å
      (229 9 1 11 8 #x18 #x3c #x18 #x0 #x3e #x63 #x3 #x7f #xc6 #xc6 #x7f)
      ;; ç
      (231 9 1 7 8 #x3e #x63 #xc3 #xc0 #xc6 #xc6 #x7c #x18 #x30)
      ;; è
      (232 9 1 10 8 #x30 #x18 #x0 #x1e #x73 #x63 #xff #xc0 #xc6 #x7c)
      ;; é
      (233 9 1 10 8 #x18 #x30 #x0 #x1e #x73 #x63 #xff #xc0 #xc6 #x7c)
      ;; ê
      (234 9 1 10 8 #x18 #x3c #x0 #x1e #x73 #x63 #xff #xc0 #xc6 #x7c)
      ;; ë
      (235 9 1 9 8 #x3c #x0 #x1e #x73 #x63 #xff #xc0 #xc6 #x7c)
      ;; ì
      (236 5 0 10 4 #xc #x6 #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6)
      ;; í
      (237 5 0 10 4 #x6 #xc #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6)
      ;; î
      (238 5 0 10 4 #x6 #xf #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6)
      ;; ï
      (239 5 0 9 4 #xf #x0 #x3 #x3 #x3 #x3 #x6 #x6 #x6)
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
      (246 9 1 9 8 #x3c #x0 #x3e #x63 #xc3 #xc3 #xc3 #xc6 #x7c)
      ;; ù
      (249 9 1 10 8 #x30 #x18 #x0 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e)
      ;; ú
      (250 9 1 10 8 #x18 #x30 #x0 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e)
      ;; û
      (251 9 1 10 8 #x18 #x3c #x0 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e)
      ;; ü
      (252 9 1 9 8 #x3c #x0 #x63 #x63 #x63 #xc6 #xc6 #xce #x7e)
      ;; ý
      (253 9 0 10 9 #x30 #x60 #x0 #xc3 #xc3 #x66 #x66 #x3c #x3c #x18 #x18
        #x1b0 #xe0)
      ;; ÿ
      (255 9 0 9 9 #x78 #x0 #xc3 #xc3 #x66 #x66 #x3c #x3c #x18 #x18 #x1b0 #xe0)
      ;; α
      (945 1)
      ;; β
      (946 1)
      ;; γ
      (947 1)
      ;; δ
      (948 1)
      ;; ε
      (949 1)
      ;; λ
      (955 1)
      ;; π
      (960 1)
      ;; –
      (8211 9 0 5 8 #xff)
      ;; —
      (8212 13 0 5 13 #x1fff)
      ;; ‘
      (8216 5 1 10 4 #x3 #x3 #x6 #xc)
      ;; ’
      (8217 5 1 10 4 #x3 #x3 #x6 #xc)
      ;; “
      (8220 8 2 10 6 #x1b #x1b #x36 #x36)
      ;; ”
      (8221 8 2 10 6 #x1b #x1b #x36 #x36)
      ;; …
      (8230 15 1 2 12 #xc63 #xc63)
      ;; ←
      (8592 1)
      ;; ↑
      (8593 1)
      ;; →
      (8594 1)
      ;; ↓
      (8595 1)
      ;; ↔
      (8596 1)
      ;; ↳
      (8627 1 1 10 8 #xc0 #xc0 #xc4 #xc6 #xff #xff #x6 #x4)
      ;; ∀
      (8704 1)
      ;; ∂
      (8706 1)
      ;; ∃
      (8707 1)
      ;; −
      (8722 9 2 4 7 #x7f)
      ;; ∞
      (8734 1)
      ;; ∧
      (8743 1)
      ;; ∨
      (8744 1)
      ;; ∩
      (8745 1)
      ;; ∪
      (8746 1)
      ;; ∫
      (8747 1)
      ;; ≠
      (8800 1)
      ;; ≡
      (8801 1)
      ;; ≤
      (8804 1)
      ;; ≥
      (8805 1)
      ;; ⊂
      (8834 1)
      ;; ⊃
      (8835 1)
      ;; ⊕
      (8853 1)
      ;; ⊗
      (8855 1)
      ;; ⋅
      (8901 1)
      ;; ▶
      (9654 7 1 9 5 #x10 #x18 #x1c #x1e #x1f #x1e #x1c #x18 #x10)
      ;; ◇
      (9671 1)
      ;; ◊
      (9674 1)
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
     ("CADR TR10 Italic" 12 9 3
      ;; the slug, which a character the face lacks draws
      (#f 5 1 8 3 #x7 #x5 #x5 #x5 #x5 #x5 #x5 #x7)
      ;; space
      (32 5)
      ;; !
      (33 5 2 8 3 #x1 #x1 #x1 #x2 #x2 #x0 #x4 #x4)
      ;; "
      (34 7 2 8 5 #x9 #x9 #x12 #x12)
      ;; #
      (35 11 2 8 9 #x9 #x12 #x7f #x24 #x48 #x1fc #x90 #x120)
      ;; $
      (36 8 2 9 6 #x2 #xf #x15 #x14 #xc #x6 #x9 #x29 #x3e #x10)
      ;; %
      (37 12 2 8 10 #xfe #x124 #x248 #x190 #x26 #x49 #x92 #x10c)
      ;; &
      (38 9 2 8 7 #x6 #xa #xc #x18 #x2b #x4a #x44 #x3f)
      ;; '
      (39 4 2 8 2 #x1 #x1 #x2 #x2)
      ;; (
      (40 7 2 8 5 #x1 #x2 #x4 #x8 #x8 #x10 #x10 #x10 #x10 #x8)
      ;; )
      (41 7 2 8 5 #x2 #x1 #x1 #x1 #x1 #x2 #x2 #x4 #x8 #x10)
      ;; *
      (42 7 2 9 5 #x4 #x15 #xe #x15 #x4)
      ;; +
      (43 8 2 5 6 #x4 #x4 #x3f #x8 #x8)
      ;; ,
      (44 4 1 2 3 #x3 #x1 #x2 #x4)
      ;; -
      (45 6 2 4 4 #xf)
      ;; .
      (46 3 2 2 1 #x1 #x1)
      ;; /
      (47 7 2 8 5 #x1 #x1 #x2 #x4 #x4 #x8 #x10 #x10)
      ;; 0
      (48 6 1 8 5 #x6 #x9 #x9 #x11 #x11 #x12 #x12 #xc)
      ;; 1
      (49 6 2 8 4 #x1 #x7 #x1 #x2 #x2 #x4 #x4 #xe)
      ;; 2
      (50 6 1 8 5 #x6 #x9 #x1 #x1 #x2 #x4 #x9 #x1e)
      ;; 3
      (51 6 1 8 5 #x6 #x9 #x1 #xe #x2 #x2 #x12 #xc)
      ;; 4
      (52 6 1 8 5 #x3 #x5 #x9 #xa #x12 #x1f #x4 #x4)
      ;; 5
      (53 6 1 8 5 #x7 #x8 #x8 #x14 #x2 #x2 #x4 #x18)
      ;; 6
      (54 6 1 8 5 #x3 #x4 #x8 #xc #x12 #x12 #x12 #xc)
      ;; 7
      (55 6 1 8 5 #xf #x12 #x4 #x4 #x8 #x8 #x10 #x10)
      ;; 8
      (56 6 1 8 5 #x6 #x9 #x9 #x6 #xc #x12 #x12 #xc)
      ;; 9
      (57 6 1 8 5 #x6 #x9 #x9 #x9 #x6 #x2 #x4 #x18)
      ;; :
      (58 4 2 6 2 #x1 #x1 #x0 #x0 #x2 #x2)
      ;; ;
      (59 5 1 6 4 #x1 #x1 #x0 #x0 #x6 #x2 #x4 #x8)
      ;; <
      (60 7 2 8 5 #x1 #x2 #x4 #x8 #x10 #x8 #x4 #x2)
      ;; =
      (61 7 2 4 5 #xf #x0 #x1e)
      ;; >
      (62 7 2 8 5 #x8 #x4 #x2 #x1 #x2 #x4 #x8 #x10)
      ;; ?
      (63 6 2 8 4 #x6 #x9 #x1 #x2 #x4 #x0 #x8 #x8)
      ;; @
      (64 13 2 9 11 #x3c #xc2 #x101 #x239 #x449 #x492 #x4b4 #x458 #x200 #x1fc)
      ;; A
      (65 8 1 8 7 #x6 #x6 #xa #xa #x12 #x1e #x22 #x77)
      ;; B
      (66 8 1 8 7 #x1e #x9 #x9 #x1e #x12 #x12 #x22 #x7c)
      ;; C
      (67 8 1 8 7 #xd #x33 #x20 #x40 #x40 #x40 #x42 #x3c)
      ;; D
      (68 9 1 8 8 #x3e #x11 #x11 #x21 #x21 #x22 #x46 #xf8)
      ;; E
      (69 9 1 8 8 #x3f #x11 #x14 #x38 #x28 #x20 #x42 #xfc)
      ;; F
      (70 9 1 8 8 #x3f #x11 #x14 #x38 #x28 #x20 #x40 #xe0)
      ;; G
      (71 8 1 8 7 #xd #x33 #x20 #x40 #x47 #x42 #x44 #x38)
      ;; H
      (72 10 1 8 9 #x77 #x22 #x22 #x7c #x44 #x44 #x88 #x1dc)
      ;; I
      (73 6 1 8 5 #x7 #x2 #x2 #x4 #x4 #x4 #x8 #x1c)
      ;; J
      (74 7 1 8 6 #x7 #x2 #x2 #x4 #x4 #x4 #x28 #x38)
      ;; K
      (75 9 1 8 8 #x3b #x12 #x14 #x38 #x28 #x28 #x44 #xee)
      ;; L
      (76 8 1 8 7 #x1c #x8 #x8 #x10 #x10 #x11 #x22 #x7e)
      ;; M
      (77 14 1 8 13 #x787 #x28a #x294 #x494 #x4a4 #x4c8 #x8c8 #x1c9c)
      ;; N
      (78 11 1 8 10 #xc7 #x42 #x62 #xa4 #x94 #x94 #x108 #x388)
      ;; O
      (79 9 1 8 8 #x1c #x62 #x41 #x81 #x81 #x82 #x46 #x38)
      ;; P
      (80 9 1 8 7 #x1e #x9 #x9 #x11 #x1e #x10 #x20 #x70)
      ;; Q
      (81 9 1 8 8 #x1c #x62 #x41 #x81 #x81 #x82 #x46 #x38 #x22 #x5c)
      ;; R
      (82 8 1 8 7 #x1e #x9 #x9 #x1e #x14 #x14 #x22 #x73)
      ;; S
      (83 7 1 8 6 #xd #x13 #x10 #x8 #x4 #x2 #x32 #x2c)
      ;; T
      (84 8 1 8 7 #x7f #x49 #x8 #x10 #x10 #x10 #x20 #x70)
      ;; U
      (85 10 2 8 8 #xe7 #x42 #x42 #x84 #x84 #x84 #x88 #x70)
      ;; V
      (86 8 1 8 7 #x77 #x22 #x24 #x24 #x28 #x28 #x30 #x30)
      ;; W
      (87 12 1 8 11 #x777 #x222 #x264 #x2a8 #x2a8 #x330 #x330 #x220)
      ;; X
      (88 8 1 8 7 #x3b #x12 #x14 #x8 #x8 #x14 #x24 #x6e)
      ;; Y
      (89 8 1 8 7 #x73 #x22 #x14 #x18 #x10 #x10 #x20 #x70)
      ;; Z
      (90 8 1 8 6 #x1f #x21 #x2 #x4 #x8 #x10 #x21 #x3e)
      ;; [
      (91 8 2 8 6 #x7 #x4 #x8 #x8 #x8 #x10 #x10 #x10 #x20 #x38)
      ;; \
      (92 5 2 8 3 #x4 #x4 #x2 #x2 #x2 #x1 #x1 #x1)
      ;; ]
      (93 8 2 8 6 #x7 #x1 #x2 #x2 #x2 #x4 #x4 #x4 #x8 #x38)
      ;; ^
      (94 6 1 8 5 #x4 #xa #x11)
      ;; _
      (95 8 0 -2 7 #x7f)
      ;; `
      (96 4 1 9 2 #x2 #x2 #x1)
      ;; a
      (97 7 1 6 6 #xd #x12 #x22 #x24 #x24 #x1a)
      ;; b
      (98 6 1 8 5 #xc #x4 #x6 #x9 #x9 #x11 #x12 #xc)
      ;; c
      (99 6 1 6 5 #x6 #x9 #x10 #x10 #x12 #xc)
      ;; d
      (100 7 1 8 6 #x3 #x1 #xe #x12 #x24 #x24 #x24 #x1a)
      ;; e
      (101 6 1 6 5 #x6 #x9 #x12 #x1c #x11 #xe)
      ;; f
      (102 6 0 8 8 #x7 #x8 #x3e #x8 #x10 #x10 #x10 #x20 #xa0 #x40)
      ;; g
      (103 7 0 6 7 #xd #x12 #x12 #xc #x10 #x2c #x42 #x3c)
      ;; h
      (104 6 1 8 5 #xc #x4 #x6 #x9 #x9 #x9 #x12 #x13)
      ;; i
      (105 5 2 9 3 #x1 #x1 #x0 #x6 #x2 #x2 #x4 #x4 #x6)
      ;; j
      (106 6 1 9 5 #x1 #x1 #x0 #x6 #x2 #x2 #x4 #x4 #x4 #x14 #x18)
      ;; k
      (107 7 1 8 6 #x18 #x8 #x13 #x14 #x18 #x28 #x24 #x26)
      ;; l
      (108 5 2 8 3 #x3 #x1 #x2 #x2 #x2 #x4 #x4 #x6)
      ;; m
      (109 9 1 6 8 #xd2 #x6d #x49 #x92 #x92 #x93)
      ;; n
      (110 6 1 6 5 #x1e #x9 #x9 #x12 #x12 #x13)
      ;; o
      (111 6 1 6 5 #x6 #x9 #x11 #x11 #x12 #xc)
      ;; p
      (112 7 0 6 7 #x1e #x9 #x9 #x11 #x12 #x1c #x20 #x70)
      ;; q
      (113 6 1 6 5 #x7 #x9 #x11 #x12 #x12 #xe #x4 #xe)
      ;; r
      (114 6 1 6 5 #xf #x5 #x4 #x8 #x8 #x1c)
      ;; s
      (115 6 1 6 5 #x7 #x9 #x4 #x2 #x12 #x1c)
      ;; t
      (116 4 1 8 4 #x2 #x2 #xf #x4 #x4 #x8 #xa #xc)
      ;; u
      (117 6 1 6 5 #x1b #x9 #x9 #x12 #x12 #xf)
      ;; v
      (118 6 1 6 5 #x1b #x9 #x9 #xa #xa #xc)
      ;; w
      (119 10 1 6 9 #x19b #x99 #xaa #xaa #xcc #x88)
      ;; x
      (120 8 1 6 7 #x33 #x14 #xc #x18 #x14 #x66)
      ;; y
      (121 8 1 6 7 #x33 #x11 #x12 #x12 #x14 #xc #x8 #x50 #x20)
      ;; z
      (122 6 1 6 5 #x7 #x9 #x2 #x4 #x9 #x1e)
      ;; {
      (123 8 2 8 6 #x3 #x4 #x4 #x8 #x30 #x8 #x8 #x10 #x10 #xc)
      ;; |
      (124 6 2 8 4 #x1 #x1 #x2 #x2 #x2 #x4 #x4 #x4 #x8 #x8)
      ;; }
      (125 8 2 8 6 #xc #x2 #x4 #x4 #x3 #x4 #x8 #x8 #x8 #x30)
      ;; ~
      (126 8 1 7 6 #x19 #x26)
      ;; °
      (176 6 1 8 4 #x6 #x9 #x9 #x6)
      ;; µ
      (181 6 1 6 5 #x1b #x9 #x9 #x12 #x12 #xf #x10 #x10)
      ;; ·
      (183 3 2 3 1 #x1 #x1)
      ;; À
      (192 8 1 9 7 #x10 #x8 #x0 #x6 #xa #x12 #x1e #x22 #x77)
      ;; Á
      (193 8 1 9 7 #x8 #x10 #x0 #x6 #xa #x12 #x1e #x22 #x77)
      ;; Â
      (194 8 1 9 7 #x10 #x28 #x0 #x6 #xa #x12 #x1e #x22 #x77)
      ;; Ã
      (195 8 1 9 7 #x14 #x28 #x0 #x6 #xa #x12 #x1e #x22 #x77)
      ;; Ä
      (196 8 1 9 7 #x28 #x0 #x6 #x6 #xa #x12 #x1e #x22 #x77)
      ;; Å
      (197 8 1 9 7 #x10 #x28 #x10 #x6 #xa #x12 #x1e #x22 #x77)
      ;; Ç
      (199 8 1 8 7 #xd #x33 #x20 #x40 #x40 #x40 #x42 #x3c #x8 #x10)
      ;; È
      (200 9 1 9 8 #x10 #x8 #x0 #x3f #x38 #x28 #x20 #x42 #xfc)
      ;; É
      (201 9 1 9 8 #x8 #x10 #x0 #x3f #x38 #x28 #x20 #x42 #xfc)
      ;; Ê
      (202 9 1 9 8 #x10 #x28 #x0 #x3f #x38 #x28 #x20 #x42 #xfc)
      ;; Ë
      (203 9 1 9 8 #x28 #x0 #x3f #x14 #x38 #x28 #x20 #x42 #xfc)
      ;; Ì
      (204 6 1 9 5 #x8 #x4 #x0 #x7 #x2 #x4 #x4 #x8 #x1c)
      ;; Í
      (205 6 1 9 5 #x4 #x8 #x0 #x7 #x2 #x4 #x4 #x8 #x1c)
      ;; Î
      (206 6 1 9 5 #x8 #x14 #x0 #x7 #x2 #x4 #x4 #x8 #x1c)
      ;; Ï
      (207 6 1 9 5 #x14 #x0 #x7 #x2 #x4 #x4 #x4 #x8 #x1c)
      ;; Ñ
      (209 11 1 9 10 #x28 #x50 #x0 #xc7 #x62 #xa4 #x94 #x108 #x388)
      ;; Ò
      (210 9 1 9 8 #x10 #x8 #x0 #x1c #x41 #x81 #x82 #x46 #x38)
      ;; Ó
      (211 9 1 9 8 #x8 #x10 #x0 #x1c #x41 #x81 #x82 #x46 #x38)
      ;; Ô
      (212 9 1 9 8 #x10 #x28 #x0 #x1c #x41 #x81 #x82 #x46 #x38)
      ;; Õ
      (213 9 1 9 8 #x14 #x28 #x0 #x1c #x41 #x81 #x82 #x46 #x38)
      ;; Ö
      (214 9 1 9 8 #x28 #x0 #x1c #x62 #x41 #x81 #x82 #x46 #x38)
      ;; ×
      (215 8 1 6 7 #x33 #x14 #xc #x18 #x14 #x66)
      ;; Ù
      (217 10 2 9 8 #x10 #x8 #x0 #xe7 #x42 #x84 #x84 #x88 #x70)
      ;; Ú
      (218 10 2 9 8 #x8 #x10 #x0 #xe7 #x42 #x84 #x84 #x88 #x70)
      ;; Û
      (219 10 2 9 8 #x10 #x28 #x0 #xe7 #x42 #x84 #x84 #x88 #x70)
      ;; Ü
      (220 10 2 9 8 #x28 #x0 #xe7 #x42 #x84 #x84 #x84 #x88 #x70)
      ;; Ý
      (221 8 1 9 7 #x8 #x10 #x0 #x73 #x14 #x18 #x10 #x20 #x70)
      ;; à
      (224 7 1 9 6 #x8 #x4 #x0 #xd #x12 #x22 #x24 #x24 #x1a)
      ;; á
      (225 7 1 9 6 #x4 #x8 #x0 #xd #x12 #x22 #x24 #x24 #x1a)
      ;; â
      (226 7 1 9 6 #x8 #x14 #x0 #xd #x12 #x22 #x24 #x24 #x1a)
      ;; ã
      (227 7 1 9 6 #xa #x14 #x0 #xd #x12 #x22 #x24 #x24 #x1a)
      ;; ä
      (228 7 1 8 6 #x14 #x0 #xd #x12 #x22 #x24 #x24 #x1a)
      ;; å
      (229 7 1 9 6 #x8 #x14 #x8 #x0 #xd #x12 #x22 #x24 #x1a)
      ;; ç
      (231 6 1 6 5 #x6 #x9 #x10 #x10 #x12 #xc #x4 #x8)
      ;; è
      (232 6 1 9 5 #x8 #x4 #x0 #x6 #x9 #x12 #x1c #x11 #xe)
      ;; é
      (233 6 1 9 5 #x4 #x8 #x0 #x6 #x9 #x12 #x1c #x11 #xe)
      ;; ê
      (234 6 1 9 5 #x8 #x14 #x0 #x6 #x9 #x12 #x1c #x11 #xe)
      ;; ë
      (235 6 1 8 5 #x14 #x0 #x6 #x9 #x12 #x1c #x11 #xe)
      ;; ì
      (236 5 2 9 2 #x2 #x1 #x0 #x3 #x1 #x1 #x2 #x2 #x3)
      ;; í
      (237 5 2 9 2 #x1 #x2 #x0 #x3 #x1 #x1 #x2 #x2 #x3)
      ;; î
      (238 5 1 9 3 #x2 #x5 #x0 #x3 #x1 #x1 #x2 #x2 #x3)
      ;; ï
      (239 5 1 8 3 #x5 #x0 #x3 #x1 #x1 #x2 #x2 #x3)
      ;; ñ
      (241 6 1 9 5 #xa #x14 #x0 #x1e #x9 #x9 #x12 #x12 #x13)
      ;; ò
      (242 6 1 9 5 #x8 #x4 #x0 #x6 #x9 #x11 #x11 #x12 #xc)
      ;; ó
      (243 6 1 9 5 #x4 #x8 #x0 #x6 #x9 #x11 #x11 #x12 #xc)
      ;; ô
      (244 6 1 9 5 #x8 #x14 #x0 #x6 #x9 #x11 #x11 #x12 #xc)
      ;; õ
      (245 6 1 9 5 #xa #x14 #x0 #x6 #x9 #x11 #x11 #x12 #xc)
      ;; ö
      (246 6 1 8 5 #x14 #x0 #x6 #x9 #x11 #x11 #x12 #xc)
      ;; ù
      (249 6 1 9 5 #x8 #x4 #x0 #x1b #x9 #x9 #x12 #x12 #xf)
      ;; ú
      (250 6 1 9 5 #x4 #x8 #x0 #x1b #x9 #x9 #x12 #x12 #xf)
      ;; û
      (251 6 1 9 5 #x8 #x14 #x0 #x1b #x9 #x9 #x12 #x12 #xf)
      ;; ü
      (252 6 1 8 5 #x14 #x0 #x1b #x9 #x9 #x12 #x12 #xf)
      ;; ý
      (253 8 1 9 7 #x8 #x10 #x0 #x33 #x11 #x12 #x12 #x14 #xc #x8 #x50 #x20)
      ;; ÿ
      (255 8 1 8 7 #x28 #x0 #x33 #x11 #x12 #x12 #x14 #xc #x8 #x50 #x20)
      ;; λ
      (955 8 0 8 6 #x20 #x10 #x10 #x8 #x14 #x12 #x22 #x21)
      ;; –
      (8211 6 0 4 5 #x1f)
      ;; —
      (8212 14 0 4 14 #x3fff)
      ;; ‘
      (8216 4 2 8 2 #x1 #x1 #x2 #x2)
      ;; ’
      (8217 4 2 8 2 #x1 #x1 #x2 #x2)
      ;; “
      (8220 7 2 8 5 #x9 #x9 #x12 #x12)
      ;; ”
      (8221 7 2 8 5 #x9 #x9 #x12 #x12)
      ;; …
      (8230 9 2 2 7 #x49 #x49)
      ;; ←
      (8592 10 1 5 8 #x20 #x40 #xff #x40 #x20)
      ;; ↑
      (8593 7 1 8 5 #x4 #xe #x15 #x4 #x4 #x4 #x4 #x4)
      ;; →
      (8594 10 1 5 8 #x4 #x2 #xff #x2 #x4)
      ;; ↓
      (8595 7 1 8 5 #x4 #x4 #x4 #x4 #x4 #x15 #xe #x4)
      ;; ↳
      (8627 10 1 8 8 #x80 #x80 #x80 #x84 #x82 #xff #x2 #x4)
      ;; −
      (8722 8 2 3 6 #x3f)
      ;; ▶
      (9654 6 1 7 4 #x8 #xc #xe #xf #xe #xc #x8)
      ;; ⚙
      (9881 11 1 9 9 #x10 #xfe #xfe #xee #x1c7 #xee #xfe #xfe #x10)
      ;; ⚠
      (9888 11 1 9 9 #x10 #x10 #x28 #x54 #x54 #x54 #x82 #x111 #x1ff)
      ;; ✓
      (10003 6 0 7 5 #x1 #x1 #x2 #x12 #xa #xc #x4)
      ;; ❚
      (10074 4 1 8 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)))))
