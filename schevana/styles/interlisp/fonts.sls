;;; (schevana styles interlisp fonts) — Medley's display fonts, which the
;;; Interlisp style draws all of its text in, as bitmap fonts
;;; (define-bitmap-font): Gacha 10, the Exec's, Helvetica 10, the menus' and
;;; the titles', its bold, and Helvetica 12 bold, Medley's BIGFONT
;;; (FONTPROFILE:186-225). They are generated from Medley's own files
;;; (fonts/medleydisplayfonts/*.MEDLEYDISPLAYFONT, in the format that
;;; sources/MEDLEYFONTFORMAT reads and writes), each glyph's bits as Medley
;;; draws them, and each one's code Unicode's, by Medley's tables
;;; (unicode/xerox). A character a font lacks is taken, where it can be, from
;;; the font Medley takes that font's other characters from: Helvetica's from
;;; Modern, Gacha's from Terminal and then Modern, fitting its 7-pixel cell.
;;; Medley draws _ as its left arrow and ^ as its up arrow, Interlisp's
;;; assignment; the right and down arrows are their mirror images. Gacha's
;;; ellipsis and dashes, which none of Medley's fixed-pitch fonts has, are
;;; drawn from its period and its hyphen. Each font's slug is Medley's
;;; (\BUILDSLUGCSINFO, FONT): black but for its first column, as tall as the
;;; font. They are used under this license:
;;;
;;;   MIT License
;;;
;;;   Copyright © 2024 Interlisp.org. Portions originally copyrighted by
;;;   Xerox, Venue, John Sybalsky, and other contributors.
;;;
;;;   Permission is hereby granted, free of charge, to any person obtaining
;;;   a copy of this software and associated documentation files (the
;;;   "Software"), to deal in the Software without restriction, including
;;;   without limitation the rights to use, copy, modify, merge, publish,
;;;   distribute, sublicense, and/or sell copies of the Software, and to
;;;   permit persons to whom the Software is furnished to do so, subject to
;;;   the following conditions:
;;;
;;;   The above copyright notice and this permission notice shall be
;;;   included in all copies or substantial portions of the Software.
;;;
;;;   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;;   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;;   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
;;;   IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
;;;   CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
;;;   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
;;;   SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

(library (schevana styles interlisp fonts)
  (export interlisp-fonts)
  (import (chezscheme)
          (only (schevana base) library-layer))

  (library-layer looks)

  ;; Medley's fonts, each (name pixel-size ascent descent glyph ...), as
  ;; define-bitmap-font takes them: a glyph is (char advance left top width
  ;; row ...), its rows from the top, the leftmost pixel in a row's highest
  ;; bit; #f is the slug.
  (define interlisp-fonts
    '(
     ("Medley Gacha 10"
      10 11 3
      ;; the slug, which a character the font lacks draws
      (#f 7 1 11 6 #x3f #x3f #x3f #x3f #x3f #x3f #x3f #x3f #x3f #x3f #x3f #x3f
        #x3f #x3f)
      ;; ' '
      (32 7)
      ;; '!'
      (33 7 3 8 1 #x1 #x1 #x1 #x1 #x1 #x0 #x1 #x1)
      ;; '"'
      (34 7 2 8 3 #x5 #x5 #x5)
      ;; '#'
      (35 7 0 8 7 #xa #xa #x3f #x14 #x14 #x7e #x28 #x28)
      ;; '$'
      (36 7 1 9 5 #x4 #xe #x15 #x15 #xc #x6 #x15 #x15 #xe #x4)
      ;; '%'
      (37 7 0 8 7 #x32 #x54 #x64 #x8 #x8 #x13 #x15 #x26)
      ;; '&'
      (38 7 1 8 6 #x8 #x14 #x14 #x8 #x15 #x22 #x22 #x1d)
      ;; "'"
      (39 7 2 8 2 #x3 #x1 #x2)
      ;; '('
      (40 7 2 9 3 #x1 #x2 #x2 #x4 #x4 #x4 #x4 #x4 #x2 #x2 #x1)
      ;; ')'
      (41 7 2 9 3 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4)
      ;; '*'
      (42 7 1 8 5 #x4 #x15 #xe #x15 #x4)
      ;; '+'
      (43 7 1 6 5 #x4 #x4 #x1f #x4 #x4)
      ;; ','
      (44 7 2 2 2 #x3 #x1 #x1 #x2)
      ;; '-'
      (45 7 1 4 5 #x1f)
      ;; '.'
      (46 7 3 2 1 #x1 #x1)
      ;; '/'
      (47 7 2 8 4 #x1 #x1 #x2 #x2 #x4 #x4 #x8 #x8)
      ;; '0'
      (48 7 1 8 5 #xe #x11 #x13 #x15 #x15 #x19 #x11 #xe)
      ;; '1'
      (49 7 1 8 5 #x4 #xc #x14 #x4 #x4 #x4 #x4 #x1f)
      ;; '2'
      (50 7 1 8 5 #xe #x11 #x11 #x2 #x4 #x8 #x10 #x1f)
      ;; '3'
      (51 7 1 8 5 #xe #x11 #x1 #xe #x1 #x1 #x11 #xe)
      ;; '4'
      (52 7 1 8 5 #x6 #xa #xa #x12 #x12 #x1f #x2 #x2)
      ;; '5'
      (53 7 1 8 5 #x1f #x10 #x10 #x1e #x11 #x1 #x11 #xe)
      ;; '6'
      (54 7 1 8 5 #xe #x11 #x10 #x1e #x11 #x11 #x11 #xe)
      ;; '7'
      (55 7 1 8 5 #x1f #x1 #x2 #x2 #x4 #x4 #x8 #x8)
      ;; '8'
      (56 7 1 8 5 #xe #x11 #x11 #xe #x11 #x11 #x11 #xe)
      ;; '9'
      (57 7 1 8 5 #xe #x11 #x11 #x11 #xf #x1 #x11 #xe)
      ;; ':'
      (58 7 3 6 1 #x1 #x1 #x0 #x0 #x1 #x1)
      ;; ';'
      (59 7 2 6 2 #x1 #x1 #x0 #x0 #x3 #x1 #x1 #x2)
      ;; '<'
      (60 7 1 8 4 #x1 #x2 #x4 #x8 #x8 #x4 #x2 #x1)
      ;; '='
      (61 7 1 5 5 #x1f #x0 #x1f)
      ;; '>'
      (62 7 1 8 4 #x8 #x4 #x2 #x1 #x1 #x2 #x4 #x8)
      ;; '?'
      (63 7 1 8 5 #xe #x11 #x11 #x2 #x4 #x0 #x4 #x4)
      ;; '@'
      (64 7 1 8 5 #xe #x11 #x17 #x15 #x15 #x17 #x10 #xf)
      ;; 'A'
      (65 7 1 8 5 #x4 #xa #xa #xa #x11 #x1f #x11 #x11)
      ;; 'B'
      (66 7 1 8 5 #x1c #x12 #x12 #x1e #x11 #x11 #x11 #x1e)
      ;; 'C'
      (67 7 1 8 5 #xe #x11 #x11 #x10 #x10 #x11 #x11 #xe)
      ;; 'D'
      (68 7 1 8 5 #x1e #x11 #x11 #x11 #x11 #x11 #x11 #x1e)
      ;; 'E'
      (69 7 1 8 5 #x1f #x10 #x10 #x1e #x10 #x10 #x10 #x1f)
      ;; 'F'
      (70 7 1 8 5 #x1f #x10 #x10 #x1e #x10 #x10 #x10 #x10)
      ;; 'G'
      (71 7 1 8 5 #xe #x11 #x11 #x10 #x17 #x11 #x11 #xe)
      ;; 'H'
      (72 7 1 8 5 #x11 #x11 #x11 #x1f #x11 #x11 #x11 #x11)
      ;; 'I'
      (73 7 2 8 3 #x7 #x2 #x2 #x2 #x2 #x2 #x2 #x7)
      ;; 'J'
      (74 7 1 8 5 #x7 #x1 #x1 #x1 #x1 #x11 #x11 #xe)
      ;; 'K'
      (75 7 1 8 5 #x11 #x12 #x14 #x1c #x12 #x12 #x11 #x11)
      ;; 'L'
      (76 7 1 8 5 #x10 #x10 #x10 #x10 #x10 #x10 #x10 #x1f)
      ;; 'M'
      (77 7 1 8 5 #x11 #x1b #x1b #x15 #x15 #x15 #x15 #x11)
      ;; 'N'
      (78 7 1 8 5 #x11 #x19 #x19 #x15 #x15 #x13 #x13 #x11)
      ;; 'O'
      (79 7 1 8 5 #xe #x11 #x11 #x11 #x11 #x11 #x11 #xe)
      ;; 'P'
      (80 7 1 8 5 #x1e #x11 #x11 #x11 #x1e #x10 #x10 #x10)
      ;; 'Q'
      (81 7 1 8 5 #xe #x11 #x11 #x11 #x11 #x11 #x11 #xe #x4 #x3)
      ;; 'R'
      (82 7 1 8 5 #x1e #x11 #x11 #x1e #x14 #x12 #x11 #x11)
      ;; 'S'
      (83 7 1 8 5 #xe #x11 #x11 #xc #x2 #x11 #x11 #xe)
      ;; 'T'
      (84 7 1 8 5 #x1f #x4 #x4 #x4 #x4 #x4 #x4 #x4)
      ;; 'U'
      (85 7 1 8 5 #x11 #x11 #x11 #x11 #x11 #x11 #x11 #xe)
      ;; 'V'
      (86 7 1 8 5 #x11 #x11 #x11 #xa #xa #xa #x4 #x4)
      ;; 'W'
      (87 7 1 8 5 #x11 #x11 #x15 #x15 #x15 #xa #xa #xa)
      ;; 'X'
      (88 7 1 8 5 #x11 #x11 #xa #x4 #x4 #xa #x11 #x11)
      ;; 'Y'
      (89 7 1 8 5 #x11 #x11 #xa #xa #x4 #x4 #x4 #x4)
      ;; 'Z'
      (90 7 1 8 5 #x1f #x1 #x2 #x4 #x4 #x8 #x10 #x1f)
      ;; '['
      (91 7 2 9 3 #x7 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x7)
      ;; '\\'
      (92 7 2 8 4 #x8 #x8 #x4 #x4 #x2 #x2 #x1 #x1)
      ;; ']'
      (93 7 2 9 3 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x7)
      ;; '^'
      (94 7 1 6 5 #x4 #xe #x15 #x4 #x4 #x4)
      ;; '_'
      (95 7 1 6 5 #x4 #x8 #x1f #x8 #x4)
      ;; '`'
      (96 7 2 8 2 #x3 #x2 #x1)
      ;; 'a'
      (97 7 1 6 5 #xe #x1 #xf #x11 #x11 #xf)
      ;; 'b'
      (98 7 1 8 5 #x10 #x10 #x16 #x19 #x11 #x11 #x19 #x16)
      ;; 'c'
      (99 7 1 6 5 #xe #x11 #x10 #x10 #x11 #xe)
      ;; 'd'
      (100 7 1 8 5 #x1 #x1 #xd #x13 #x11 #x11 #x13 #xd)
      ;; 'e'
      (101 7 1 6 5 #xe #x11 #x1f #x10 #x11 #xe)
      ;; 'f'
      (102 7 1 8 5 #x7 #x8 #x1e #x8 #x8 #x8 #x8 #x8)
      ;; 'g'
      (103 7 1 6 5 #xd #x13 #x11 #x11 #x13 #xd #x1 #xe)
      ;; 'h'
      (104 7 1 8 5 #x10 #x10 #x16 #x19 #x11 #x11 #x11 #x11)
      ;; 'i'
      (105 7 2 8 3 #x1 #x0 #x7 #x1 #x1 #x1 #x1 #x1)
      ;; 'j'
      (106 7 1 8 4 #x1 #x0 #x7 #x1 #x1 #x1 #x1 #x1 #x9 #x6)
      ;; 'k'
      (107 7 1 8 5 #x10 #x10 #x12 #x14 #x18 #x14 #x12 #x11)
      ;; 'l'
      (108 7 2 8 3 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; 'm'
      (109 7 1 6 5 #x1b #x15 #x15 #x15 #x15 #x15)
      ;; 'n'
      (110 7 1 6 5 #x16 #x19 #x11 #x11 #x11 #x11)
      ;; 'o'
      (111 7 1 6 5 #xe #x11 #x11 #x11 #x11 #xe)
      ;; 'p'
      (112 7 1 6 5 #x16 #x19 #x11 #x11 #x19 #x16 #x10 #x10)
      ;; 'q'
      (113 7 1 6 5 #xd #x13 #x11 #x11 #x13 #xd #x1 #x1)
      ;; 'r'
      (114 7 1 6 5 #x16 #x19 #x10 #x10 #x10 #x10)
      ;; 's'
      (115 7 1 6 5 #xe #x11 #xc #x2 #x11 #xe)
      ;; 't'
      (116 7 1 7 5 #x8 #x1e #x8 #x8 #x8 #x9 #x6)
      ;; 'u'
      (117 7 1 6 5 #x11 #x11 #x11 #x11 #x13 #xd)
      ;; 'v'
      (118 7 1 6 5 #x11 #x11 #xa #xa #x4 #x4)
      ;; 'w'
      (119 7 1 6 5 #x11 #x11 #x15 #x15 #xa #xa)
      ;; 'x'
      (120 7 1 6 5 #x11 #xa #x4 #x4 #xa #x11)
      ;; 'y'
      (121 7 1 6 5 #x11 #x11 #x11 #xa #xa #x4 #x4 #x18)
      ;; 'z'
      (122 7 1 6 5 #x1f #x2 #x4 #x4 #x8 #x1f)
      ;; '{'
      (123 7 1 9 5 #x3 #x4 #x4 #x4 #x4 #x18 #x4 #x4 #x4 #x4 #x3)
      ;; '|'
      (124 7 3 9 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; '}'
      (125 7 1 9 5 #x18 #x4 #x4 #x4 #x4 #x3 #x4 #x4 #x4 #x4 #x18)
      ;; '~'
      (126 7 1 5 6 #x19 #x26)
      ;; U+00A0  
      (160 6)
      ;; U+00A1 ¡
      (161 7 4 6 2 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; U+00A2 ¢
      (162 7 2 8 4 #x2 #x2 #xf #x9 #x8 #x9 #xf #x4 #x4)
      ;; U+00A3 £
      (163 7 0 8 5 #x7 #x8 #x8 #x1c #x8 #x8 #x9 #x1f)
      ;; U+00A5 ¥
      (165 7 2 8 5 #x11 #x11 #xe #x4 #x1f #x4 #x1f #x4)
      ;; U+00A6 ¦
      (166 6 6 9 1 #x1 #x1 #x1 #x1 #x1 #x0 #x0 #x1 #x1 #x1 #x1 #x1)
      ;; U+00A7 §
      (167 7 2 7 4 #x7 #x8 #x4 #xa #x9 #x5 #x2 #x1 #xe)
      ;; U+00A9 ©
      (169 7 0 9 6 #x1e #x21 #x2d #x31 #x31 #x2d #x21 #x1e)
      ;; U+00AA ª
      (170 7 2 8 4 #xe #x2 #xf #x0 #xf)
      ;; U+00AB «
      (171 7 2 5 5 #x5 #xa #x14 #xa #x5)
      ;; U+00AC ¬
      (172 6 0 6 5 #x1f #x1 #x1)
      ;; U+00AD ­
      (173 6 2 5 4 #xf)
      ;; U+00AE ®
      (174 7 0 9 6 #x1e #x21 #x3d #x33 #x3d #x33 #x21 #x1e)
      ;; U+00B0 °
      (176 7 0 8 3 #x2 #x5 #x5 #x2)
      ;; U+00B1 ±
      (177 7 0 6 5 #x4 #x4 #x1f #x4 #x4 #x1f)
      ;; U+00B2 ²
      (178 7 2 8 4 #xe #x1 #x6 #x8 #xf)
      ;; U+00B3 ³
      (179 7 2 8 3 #x7 #x1 #x3 #x1 #x7)
      ;; U+00B5 µ
      (181 7 2 6 5 #x12 #x12 #x12 #x12 #x12 #x1f #x10 #x10 #x10)
      ;; U+00B6 ¶
      (182 7 0 7 5 #xd #x1d #x1d #xd #x5 #x5 #x5 #x5 #x5)
      ;; U+00B7 ·
      (183 7 4 5 3 #x2 #x7 #x2)
      ;; U+00BA º
      (186 7 2 8 4 #xe #xa #xa #xe #x0 #xf)
      ;; U+00BB »
      (187 7 2 5 5 #x14 #xa #x5 #xa #x14)
      ;; U+00BC ¼
      (188 7 0 8 6 #x4 #xc #x4 #x4 #x4 #x3f #x4 #xc #x14 #x1e #x4)
      ;; U+00BD ½
      (189 7 0 8 6 #x4 #xc #x4 #x4 #x4 #x3f #xe #x2 #xc #xe)
      ;; U+00BE ¾
      (190 7 0 8 6 #xc #x2 #xc #x2 #xc #x3f #x4 #xc #x14 #x1e #x4)
      ;; U+00BF ¿
      (191 7 2 6 3 #x2 #x2 #x0 #x2 #x2 #x4 #x4 #x3)
      ;; U+00C6 Æ
      (198 7 0 8 6 #xf #x14 #x14 #x14 #x16 #x3c #x24 #x27)
      ;; U+00DF ß
      (223 7 2 8 5 #xc #x12 #x12 #x16 #x11 #x11 #x11 #x16)
      ;; U+00E6 æ
      (230 7 0 5 6 #x3f #x9 #x3f #x28 #x3f)
      ;; U+00F7 ÷
      (247 7 2 5 5 #x4 #x0 #x1f #x0 #x4)
      ;; U+00F8 ø
      (248 7 0 6 6 #x1 #xe #x16 #x1a #x12 #x1c #x20)
      ;; U+0391 Α
      (913 7 2 7 5 #x4 #x4 #xa #xa #xe #x11 #x11)
      ;; U+0392 Β
      (914 7 2 7 5 #x1c #x12 #x12 #x1e #x11 #x11 #x1e)
      ;; U+0393 Γ
      (915 7 2 7 4 #xf #x8 #x8 #x8 #x8 #x8 #x8)
      ;; U+0394 Δ
      (916 7 2 7 5 #x4 #x4 #xa #xa #xa #x11 #x1f)
      ;; U+0395 Ε
      (917 7 2 7 4 #xf #x8 #x8 #xf #x8 #x8 #xf)
      ;; U+0396 Ζ
      (918 7 2 7 4 #xf #x2 #x2 #x4 #x4 #x8 #xf)
      ;; U+0397 Η
      (919 7 2 7 5 #x11 #x11 #x11 #x1f #x11 #x11 #x11)
      ;; U+0399 Ι
      (921 7 2 7 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; U+039A Κ
      (922 7 2 7 5 #x11 #x12 #x14 #x18 #x14 #x12 #x11)
      ;; U+039B Λ
      (923 7 0 7 7 #x8 #x8 #x14 #x14 #x22 #x22 #x41)
      ;; U+039D Ν
      (925 7 2 7 5 #x11 #x19 #x15 #x15 #x15 #x13 #x11)
      ;; U+039E Ξ
      (926 7 2 7 4 #xf #x0 #x0 #xf #x0 #x0 #xf)
      ;; U+03A0 Π
      (928 7 2 7 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11)
      ;; U+03A1 Ρ
      (929 7 2 7 5 #x1e #x11 #x11 #x1e #x10 #x10 #x10)
      ;; U+03A3 Σ
      (931 7 2 7 5 #x1f #x8 #x4 #x2 #x4 #x8 #x1f)
      ;; U+03A4 Τ
      (932 7 2 7 5 #x1f #x4 #x4 #x4 #x4 #x4 #x4)
      ;; U+03A5 Υ
      (933 7 2 7 5 #x11 #xa #xa #x4 #x4 #x4 #x4)
      ;; U+03A7 Χ
      (935 7 2 7 5 #x11 #x11 #xa #x4 #xa #x11 #x11)
      ;; U+03B1 α
      (945 7 2 5 5 #xd #x12 #x12 #x12 #xd)
      ;; U+03B2 β
      (946 7 2 7 4 #x6 #x9 #x9 #xa #x9 #x9 #xa #x8 #x8)
      ;; U+03B3 γ
      (947 7 0 5 5 #x11 #xa #xa #x4 #x4 #x4 #x4)
      ;; U+03B4 δ
      (948 7 2 7 5 #x8 #x4 #xe #x11 #x11 #x11 #xe)
      ;; U+03B5 ε
      (949 7 2 5 3 #x3 #x4 #x2 #x4 #x3)
      ;; U+03B6 ζ
      (950 7 2 7 4 #xf #x2 #x4 #x8 #x8 #x8 #x6 #x1 #x1)
      ;; U+03B7 η
      (951 7 2 5 4 #xa #xd #x9 #x9 #x9 #x1 #x1)
      ;; U+03B8 θ
      (952 7 2 7 4 #x6 #x9 #x9 #xf #x9 #x9 #x6)
      ;; U+03B9 ι
      (953 7 2 5 1 #x1 #x1 #x1 #x1 #x1)
      ;; U+03BA κ
      (954 7 2 5 4 #x9 #xa #xc #xa #x9)
      ;; U+03BB λ
      (955 7 2 7 5 #x8 #x8 #x4 #x4 #xa #xa #x11)
      ;; U+03BC μ
      (956 7 2 5 4 #x9 #x9 #x9 #x9 #xf #x8 #x8)
      ;; U+03BD ν
      (957 7 0 5 5 #x11 #xa #xa #x4 #x4)
      ;; U+03BE ξ
      (958 7 2 7 4 #xf #x2 #x4 #x2 #x4 #x8 #x8 #x7 #x1)
      ;; U+03BF ο
      (959 7 2 5 5 #xe #x11 #x11 #x11 #xe)
      ;; U+03C0 π
      (960 6 0 6 6 #x3f #x12 #x12 #x12 #x12 #x12)
      ;; U+03C1 ρ
      (961 7 2 5 5 #xe #x11 #x11 #x11 #x1e #x10 #x10)
      ;; U+03C3 σ
      (963 7 2 5 5 #xf #x12 #x11 #x11 #xe)
      ;; U+03C4 τ
      (964 7 2 5 5 #x1f #x4 #x4 #x4 #x4)
      ;; U+03C5 υ
      (965 7 2 5 4 #x9 #x9 #x9 #x9 #x6)
      ;; U+03C7 χ
      (967 7 2 5 5 #x11 #xa #xa #x4 #xa #xa #x11)
      ;; U+03C8 ψ
      (968 7 2 5 5 #x15 #x15 #x15 #x15 #xe #x4 #x4)
      ;; U+2013 –
      (8211 6 0 5 5 #x1f)
      ;; U+2014 —
      (8212 7 0 4 7 #x7f)
      ;; U+2018 ‘
      (8216 7 2 8 3 #x6 #x6 #x3 #x3)
      ;; U+2019 ’
      (8217 7 4 8 2 #x1 #x1 #x3 #x2)
      ;; U+201C “
      (8220 7 2 8 4 #x9 #x9 #x9 #x9)
      ;; U+201D ”
      (8221 7 2 8 4 #x9 #x9 #x9 #x9)
      ;; U+2020 †
      (8224 7 4 7 3 #x2 #x2 #x7 #x2 #x2 #x2 #x2)
      ;; U+2021 ‡
      (8225 7 4 7 3 #x2 #x2 #x7 #x2 #x7 #x2 #x2)
      ;; U+2022 •
      (8226 7 2 4 5 #xe #x1f #x1f #x1f #xe)
      ;; U+2026 …
      (8230 7 0 2 7 #x2a #x2a)
      ;; U+2190 ←
      (8592 7 1 6 5 #x4 #x8 #x1f #x8 #x4)
      ;; U+2191 ↑
      (8593 7 1 6 5 #x4 #xe #x15 #x4 #x4 #x4)
      ;; U+2192 →
      (8594 7 1 6 5 #x4 #x2 #x1f #x2 #x4)
      ;; U+2193 ↓
      (8595 7 1 6 5 #x4 #x4 #x4 #x15 #xe #x4)
      ;; U+2212 −
      (8722 6 2 4 4 #xf)
      ;; U+2260 ≠
      (8800 6 0 9 6 #x2 #x4 #x3f #x4 #x8 #x3f #x10 #x20)
      ;; U+2264 ≤
      (8804 6 0 9 6 #x3 #xc #x30 #xc #x3 #x0 #x0 #x0 #x3f)
      ;; U+2265 ≥
      (8805 6 0 9 6 #x30 #xc #x3 #xc #x30 #x0 #x0 #x0 #x3f))
     ("Medley Helvetica 10"
      10 10 3
      ;; the slug, which a character the font lacks draws
      (#f 9 1 10 8 #xff #xff #xff #xff #xff #xff #xff #xff #xff #xff #xff #xff
        #xff)
      ;; ' '
      (32 3)
      ;; '!'
      (33 4 2 8 1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x1 #x1)
      ;; '"'
      (34 7 2 8 4 #x9 #x9 #x9)
      ;; '#'
      (35 15 2 8 10 #x24 #x24 #x1ff #x48 #x48 #x3fe #x90 #x90)
      ;; '$'
      (36 7 1 9 5 #x4 #xe #x15 #x14 #xe #x5 #x5 #x15 #xe #x4)
      ;; '%'
      (37 11 1 8 9 #xc4 #x128 #x128 #xd0 #x16 #x29 #x29 #x46)
      ;; '&'
      (38 9 1 8 7 #x18 #x24 #x24 #x18 #x2a #x46 #x46 #x39)
      ;; "'"
      (39 4 1 8 2 #x3 #x1 #x2)
      ;; '('
      (40 4 1 8 3 #x1 #x2 #x2 #x4 #x4 #x4 #x4 #x2 #x2 #x1)
      ;; ')'
      (41 4 1 8 3 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x2 #x2 #x4)
      ;; '*'
      (42 7 1 8 5 #x4 #x15 #xe #x15 #x4)
      ;; '+'
      (43 13 4 5 5 #x4 #x4 #x1f #x4 #x4)
      ;; ','
      (44 4 1 1 2 #x3 #x1 #x2)
      ;; '-'
      (45 4 1 3 2 #x3)
      ;; '.'
      (46 4 1 2 1 #x1 #x1)
      ;; '/'
      (47 7 1 8 5 #x1 #x1 #x2 #x4 #x4 #x8 #x10 #x10)
      ;; '0'
      (48 7 1 8 5 #xe #x11 #x11 #x11 #x11 #x11 #x11 #xe)
      ;; '1'
      (49 7 1 8 4 #x1 #x3 #xf #x1 #x1 #x1 #x1 #x1)
      ;; '2'
      (50 7 1 8 5 #xe #x11 #x1 #x1 #x6 #x8 #x10 #x1f)
      ;; '3'
      (51 7 1 8 5 #xe #x11 #x1 #x6 #x1 #x1 #x11 #xe)
      ;; '4'
      (52 7 1 8 5 #x6 #x6 #xa #xa #x12 #x1f #x2 #x2)
      ;; '5'
      (53 7 1 8 5 #xf #x8 #x1e #x11 #x1 #x1 #x11 #xe)
      ;; '6'
      (54 7 1 8 5 #xe #x11 #x10 #x1e #x11 #x11 #x11 #xe)
      ;; '7'
      (55 7 1 8 5 #x1f #x1 #x2 #x4 #x4 #x8 #x8 #x8)
      ;; '8'
      (56 7 1 8 5 #xe #x11 #x11 #xe #x11 #x11 #x11 #xe)
      ;; '9'
      (57 7 1 8 5 #xe #x11 #x11 #x11 #xf #x1 #x11 #xe)
      ;; ':'
      (58 4 1 6 1 #x1 #x1 #x0 #x0 #x0 #x1 #x1)
      ;; ';'
      (59 4 1 6 2 #x2 #x2 #x0 #x0 #x0 #x3 #x1 #x2)
      ;; '<'
      (60 7 1 8 4 #x1 #x2 #x4 #x8 #x8 #x4 #x2 #x1)
      ;; '='
      (61 13 3 4 7 #x7f #x0 #x7f)
      ;; '>'
      (62 7 1 8 4 #x8 #x4 #x2 #x1 #x1 #x2 #x4 #x8)
      ;; '?'
      (63 6 1 8 4 #x6 #x9 #x9 #x2 #x4 #x4 #x0 #x4 #x4)
      ;; '@'
      (64 15 1 9 12 #xf8 #x306 #x402 #x479 #x889 #x911 #x912 #x4ec #x401 #x306
        #xf8)
      ;; 'A'
      (65 9 1 8 7 #x8 #x8 #x14 #x14 #x22 #x3e #x41 #x41)
      ;; 'B'
      (66 9 1 8 7 #x7e #x41 #x41 #x7e #x41 #x41 #x41 #x7e)
      ;; 'C'
      (67 9 1 8 7 #x1e #x21 #x40 #x40 #x40 #x40 #x21 #x1e)
      ;; 'D'
      (68 9 1 8 7 #x7c #x42 #x41 #x41 #x41 #x41 #x42 #x7c)
      ;; 'E'
      (69 9 1 8 7 #x7f #x40 #x40 #x7e #x40 #x40 #x40 #x7f)
      ;; 'F'
      (70 8 1 8 6 #x3f #x20 #x20 #x3e #x20 #x20 #x20 #x20)
      ;; 'G'
      (71 10 1 8 8 #x3e #x41 #x80 #x80 #x8f #x81 #x43 #x3d)
      ;; 'H'
      (72 9 1 8 7 #x41 #x41 #x41 #x7f #x41 #x41 #x41 #x41)
      ;; 'I'
      (73 4 2 8 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; 'J'
      (74 7 1 8 5 #x1 #x1 #x1 #x1 #x1 #x1 #x11 #xe)
      ;; 'K'
      (75 9 1 8 7 #x42 #x44 #x48 #x50 #x68 #x44 #x42 #x41)
      ;; 'L'
      (76 8 1 8 6 #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x3f)
      ;; 'M'
      (77 11 1 8 9 #x183 #x183 #x145 #x145 #x129 #x129 #x111 #x111)
      ;; 'N'
      (78 9 1 8 7 #x41 #x61 #x51 #x49 #x49 #x45 #x43 #x41)
      ;; 'O'
      (79 10 1 8 8 #x3c #x42 #x81 #x81 #x81 #x81 #x42 #x3c)
      ;; 'P'
      (80 8 1 8 6 #x3e #x21 #x21 #x21 #x3e #x20 #x20 #x20)
      ;; 'Q'
      (81 10 1 8 8 #x3c #x42 #x81 #x81 #x81 #x89 #x46 #x3e #x1)
      ;; 'R'
      (82 9 1 8 7 #x7e #x41 #x41 #x41 #x7e #x41 #x41 #x41)
      ;; 'S'
      (83 9 1 8 7 #x3e #x41 #x40 #x3c #x2 #x1 #x41 #x3e)
      ;; 'T'
      (84 8 1 8 7 #x7f #x8 #x8 #x8 #x8 #x8 #x8 #x8)
      ;; 'U'
      (85 9 1 8 7 #x41 #x41 #x41 #x41 #x41 #x41 #x41 #x3e)
      ;; 'V'
      (86 9 1 8 7 #x41 #x41 #x22 #x22 #x14 #x14 #x8 #x8)
      ;; 'W'
      (87 12 1 8 10 #x231 #x231 #x231 #x14a #x14a #x14a #x84 #x84)
      ;; 'X'
      (88 9 1 8 7 #x41 #x22 #x14 #x8 #x8 #x14 #x22 #x41)
      ;; 'Y'
      (89 9 1 8 7 #x41 #x22 #x22 #x14 #x8 #x8 #x8 #x8)
      ;; 'Z'
      (90 9 1 8 7 #x7f #x2 #x4 #x8 #x8 #x10 #x20 #x7f)
      ;; '['
      (91 4 1 8 3 #x7 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x4 #x7)
      ;; '\\'
      (92 8 1 8 6 #x20 #x10 #x8 #x8 #x4 #x2 #x1 #x1)
      ;; ']'
      (93 4 1 8 3 #x7 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x7)
      ;; '^'
      (94 7 1 6 5 #x4 #xe #x15 #x4 #x4 #x4)
      ;; '_'
      (95 10 2 6 6 #x8 #x10 #x3f #x10 #x8)
      ;; '`'
      (96 4 1 8 2 #x1 #x2 #x3)
      ;; 'a'
      (97 7 1 6 6 #x1c #x22 #xe #x32 #x22 #x1d)
      ;; 'b'
      (98 8 1 8 6 #x20 #x20 #x2e #x31 #x21 #x21 #x31 #x2e)
      ;; 'c'
      (99 7 1 6 5 #xe #x11 #x10 #x10 #x11 #xe)
      ;; 'd'
      (100 8 1 8 6 #x1 #x1 #x1d #x23 #x21 #x21 #x23 #x1d)
      ;; 'e'
      (101 7 1 6 5 #xe #x11 #x1f #x10 #x11 #xe)
      ;; 'f'
      (102 4 0 8 4 #x7 #x4 #xf #x4 #x4 #x4 #x4 #x4)
      ;; 'g'
      (103 8 1 6 6 #x1d #x23 #x21 #x21 #x23 #x1d #x21 #x1e)
      ;; 'h'
      (104 8 1 8 6 #x20 #x20 #x2e #x31 #x21 #x21 #x21 #x21)
      ;; 'i'
      (105 3 1 9 1 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; 'j'
      (106 3 0 9 2 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x3)
      ;; 'k'
      (107 7 1 8 6 #x20 #x20 #x22 #x24 #x28 #x34 #x22 #x21)
      ;; 'l'
      (108 3 1 8 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; 'm'
      (109 11 1 6 9 #x166 #x199 #x111 #x111 #x111 #x111)
      ;; 'n'
      (110 8 1 6 6 #x2e #x31 #x21 #x21 #x21 #x21)
      ;; 'o'
      (111 8 1 6 6 #x1e #x21 #x21 #x21 #x21 #x1e)
      ;; 'p'
      (112 8 1 6 6 #x2e #x31 #x21 #x21 #x31 #x2e #x20 #x20)
      ;; 'q'
      (113 8 1 6 6 #x1d #x23 #x21 #x21 #x23 #x1d #x1 #x1)
      ;; 'r'
      (114 5 1 6 4 #xb #xd #x8 #x8 #x8 #x8)
      ;; 's'
      (115 7 1 6 5 #xe #x11 #xe #x1 #x11 #xe)
      ;; 't'
      (116 4 0 8 4 #x4 #x4 #xf #x4 #x4 #x4 #x4 #x3)
      ;; 'u'
      (117 8 1 6 6 #x21 #x21 #x21 #x21 #x23 #x1d)
      ;; 'v'
      (118 7 1 6 5 #x11 #x11 #xa #xa #x4 #x4)
      ;; 'w'
      (119 10 1 6 9 #x111 #x111 #xaa #xaa #x44 #x44)
      ;; 'x'
      (120 7 1 6 5 #x11 #xa #x4 #x4 #xa #x11)
      ;; 'y'
      (121 7 1 6 5 #x11 #x11 #xa #xa #x4 #x4 #x4 #x18)
      ;; 'z'
      (122 7 1 6 5 #x1f #x2 #x4 #x8 #x10 #x1f)
      ;; '{'
      (123 7 1 9 5 #x3 #x4 #x4 #x4 #x4 #x18 #x4 #x4 #x4 #x4 #x3)
      ;; '|'
      (124 3 1 9 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; '}'
      (125 7 1 9 5 #x18 #x4 #x4 #x4 #x4 #x3 #x4 #x4 #x4 #x4 #x18)
      ;; '~'
      (126 10 2 5 7 #x39 #x4e)
      ;; U+00A1 ¡
      (161 4 2 9 1 #x1 #x1 #x0 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; U+00A2 ¢
      (162 7 1 8 5 #x2 #x2 #xe #x15 #x14 #x14 #x15 #xe #x8 #x8)
      ;; U+00A3 £
      (163 7 0 8 7 #x1c #x22 #x22 #x10 #x7c #x10 #x20 #x7f)
      ;; U+00A5 ¥
      (165 11 0 9 9 #x1c7 #x82 #x44 #x28 #x1ff #x10 #x1ff #x10 #x10 #x38)
      ;; U+00A6 ¦
      (166 3 2 7 1 #x1 #x1 #x1 #x1 #x0 #x1 #x1 #x1 #x1)
      ;; U+00A7 §
      (167 6 2 7 4 #x7 #x8 #x4 #xa #x9 #x5 #x2 #x1 #xe)
      ;; U+00A9 ©
      (169 6 0 9 6 #x1e #x21 #x2d #x31 #x31 #x2d #x21 #x1e)
      ;; U+00AB «
      (171 6 2 5 5 #x5 #xa #x14 #xa #x5)
      ;; U+00AC ¬
      (172 10 2 5 7 #x7f #x1 #x1 #x1)
      ;; U+00AD ­
      (173 3 2 3 2 #x3)
      ;; U+00AE ®
      (174 6 0 9 6 #x1e #x21 #x3d #x33 #x3d #x33 #x21 #x1e)
      ;; U+00B0 °
      (176 3 0 8 3 #x2 #x5 #x5 #x2)
      ;; U+00B1 ±
      (177 13 4 7 5 #x4 #x4 #x1f #x4 #x4 #x0 #x1f)
      ;; U+00B6 ¶
      (182 7 1 8 5 #xf #x1d #x1d #x1d #xd #x5 #x5 #x5 #x5 #x5)
      ;; U+00B7 ·
      (183 11 3 5 3 #x2 #x7 #x2)
      ;; U+00BB »
      (187 6 2 5 5 #x14 #xa #x5 #xa #x14)
      ;; U+00BC ¼
      (188 6 0 8 6 #x4 #xc #x4 #x4 #x4 #x3f #x4 #xc #x14 #x1e #x4)
      ;; U+00BD ½
      (189 6 0 8 6 #x4 #xc #x4 #x4 #x4 #x3f #xe #x2 #xc #xe)
      ;; U+00BE ¾
      (190 6 0 8 6 #xc #x2 #xc #x2 #xc #x3f #x4 #xc #x14 #x1e #x4)
      ;; U+00BF ¿
      (191 6 1 7 4 #x2 #x2 #x0 #x2 #x2 #x4 #x8 #x9 #x6)
      ;; U+00C6 Æ
      (198 9 2 7 8 #x1f #x28 #x28 #x4e #x48 #xf8 #x8f)
      ;; U+00D7 ×
      (215 10 6 5 5 #x11 #xa #x4 #xa #x11)
      ;; U+00D8 Ø
      (216 8 2 7 6 #x1f #x23 #x25 #x29 #x29 #x31 #x3e)
      ;; U+00DF ß
      (223 6 2 8 5 #xc #x12 #x12 #x16 #x11 #x11 #x11 #x16)
      ;; U+00E6 æ
      (230 9 2 5 7 #x76 #x9 #x3f #x48 #x77)
      ;; U+00F7 ÷
      (247 10 6 5 5 #x4 #x0 #x1f #x0 #x4)
      ;; U+00F8 ø
      (248 6 0 6 6 #x1 #xe #x16 #x1a #x1a #x1c #x20)
      ;; U+0391 Α
      (913 7 2 7 5 #x4 #x4 #xa #xa #xe #x11 #x11)
      ;; U+0392 Β
      (914 6 2 7 5 #x1c #x12 #x12 #x1e #x11 #x11 #x1e)
      ;; U+0393 Γ
      (915 5 2 7 4 #xf #x8 #x8 #x8 #x8 #x8 #x8)
      ;; U+0394 Δ
      (916 6 2 7 5 #x4 #x4 #xa #xa #xa #x11 #x1f)
      ;; U+0395 Ε
      (917 6 2 7 4 #xf #x8 #x8 #xf #x8 #x8 #xf)
      ;; U+0396 Ζ
      (918 5 2 7 4 #xf #x2 #x2 #x4 #x4 #x8 #xf)
      ;; U+0397 Η
      (919 7 2 7 5 #x11 #x11 #x11 #x1f #x11 #x11 #x11)
      ;; U+0398 Θ
      (920 7 2 7 6 #x1e #x21 #x21 #x2d #x21 #x21 #x1e)
      ;; U+0399 Ι
      (921 3 2 7 1 #x1 #x1 #x1 #x1 #x1 #x1 #x1)
      ;; U+039A Κ
      (922 7 2 7 5 #x11 #x12 #x14 #x18 #x14 #x12 #x11)
      ;; U+039B Λ
      (923 7 0 7 7 #x8 #x8 #x14 #x14 #x22 #x22 #x41)
      ;; U+039C Μ
      (924 9 2 7 7 #x41 #x63 #x63 #x55 #x55 #x49 #x49)
      ;; U+039D Ν
      (925 7 2 7 5 #x11 #x19 #x15 #x15 #x15 #x13 #x11)
      ;; U+039E Ξ
      (926 6 2 7 4 #xf #x0 #x0 #xf #x0 #x0 #xf)
      ;; U+039F Ο
      (927 7 2 7 6 #x1e #x21 #x21 #x21 #x21 #x21 #x1e)
      ;; U+03A0 Π
      (928 7 2 7 5 #x1f #x11 #x11 #x11 #x11 #x11 #x11)
      ;; U+03A1 Ρ
      (929 6 2 7 5 #x1e #x11 #x11 #x1e #x10 #x10 #x10)
      ;; U+03A3 Σ
      (931 7 2 7 5 #x1f #x8 #x4 #x2 #x4 #x8 #x1f)
      ;; U+03A4 Τ
      (932 6 2 7 5 #x1f #x4 #x4 #x4 #x4 #x4 #x4)
      ;; U+03A5 Υ
      (933 7 2 7 5 #x11 #xa #xa #x4 #x4 #x4 #x4)
      ;; U+03A6 Φ
      (934 8 2 7 7 #x8 #x3e #x49 #x49 #x49 #x3e #x8)
      ;; U+03A7 Χ
      (935 7 2 7 5 #x11 #x11 #xa #x4 #xa #x11 #x11)
      ;; U+03A8 Ψ
      (936 8 2 7 7 #x49 #x49 #x49 #x49 #x49 #x3e #x8)
      ;; U+03A9 Ω
      (937 8 2 7 6 #x1e #x21 #x21 #x21 #x12 #x12 #x33)
      ;; U+03B1 α
      (945 6 2 5 5 #xd #x12 #x12 #x12 #xd)
      ;; U+03B2 β
      (946 6 2 7 4 #x6 #x9 #x9 #xa #x9 #x9 #xa #x8 #x8)
      ;; U+03B3 γ
      (947 5 0 5 5 #x11 #xa #xa #x4 #x4 #x4 #x4)
      ;; U+03B4 δ
      (948 6 2 7 5 #x8 #x4 #xe #x11 #x11 #x11 #xe)
      ;; U+03B5 ε
      (949 5 2 5 3 #x3 #x4 #x2 #x4 #x3)
      ;; U+03B6 ζ
      (950 5 2 7 4 #xf #x2 #x4 #x8 #x8 #x8 #x6 #x1 #x1)
      ;; U+03B7 η
      (951 6 2 5 4 #xa #xd #x9 #x9 #x9 #x1 #x1)
      ;; U+03B8 θ
      (952 6 2 7 4 #x6 #x9 #x9 #xf #x9 #x9 #x6)
      ;; U+03B9 ι
      (953 3 2 5 1 #x1 #x1 #x1 #x1 #x1)
      ;; U+03BA κ
      (954 6 2 5 4 #x9 #xa #xc #xa #x9)
      ;; U+03BB λ
      (955 6 2 7 5 #x8 #x8 #x4 #x4 #xa #xa #x11)
      ;; U+03BC μ
      (956 6 2 5 4 #x9 #x9 #x9 #x9 #xf #x8 #x8)
      ;; U+03BD ν
      (957 5 0 5 5 #x11 #xa #xa #x4 #x4)
      ;; U+03BE ξ
      (958 6 2 7 4 #xf #x2 #x4 #x2 #x4 #x8 #x8 #x7 #x1)
      ;; U+03BF ο
      (959 6 2 5 5 #xe #x11 #x11 #x11 #xe)
      ;; U+03C0 π
      (960 6 2 5 4 #xf #x9 #x9 #x9 #x9)
      ;; U+03C1 ρ
      (961 6 2 5 5 #xe #x11 #x11 #x11 #x1e #x10 #x10)
      ;; U+03C3 σ
      (963 6 2 5 5 #xf #x12 #x11 #x11 #xe)
      ;; U+03C4 τ
      (964 6 2 5 5 #x1f #x4 #x4 #x4 #x4)
      ;; U+03C5 υ
      (965 6 2 5 4 #x9 #x9 #x9 #x9 #x6)
      ;; U+03C6 φ
      (966 8 2 6 7 #x8 #x8 #x3e #x49 #x49 #x3e #x8 #x8)
      ;; U+03C7 χ
      (967 6 2 5 5 #x11 #xa #xa #x4 #xa #xa #x11)
      ;; U+03C8 ψ
      (968 7 2 5 5 #x15 #x15 #x15 #x15 #xe #x4 #x4)
      ;; U+03C9 ω
      (969 8 2 5 7 #x2a #x49 #x49 #x49 #x36)
      ;; U+2013 –
      (8211 5 0 3 5 #x1f)
      ;; U+2014 —
      (8212 10 0 3 10 #x3ff)
      ;; U+2018 ‘
      (8216 4 1 8 2 #x1 #x2 #x3)
      ;; U+2019 ’
      (8217 4 1 8 2 #x1 #x2 #x3)
      ;; U+201C “
      (8220 6 2 8 4 #x5 #xf #xa)
      ;; U+201D ”
      (8221 6 2 8 4 #x5 #xf #xa)
      ;; U+2020 †
      (8224 6 4 7 3 #x2 #x2 #x7 #x2 #x2 #x2 #x2)
      ;; U+2021 ‡
      (8225 6 4 7 3 #x2 #x2 #x7 #x2 #x7 #x2 #x2)
      ;; U+2022 •
      (8226 6 2 4 5 #xe #x1f #x1f #x1f #xe)
      ;; U+2026 …
      (8230 11 0 5 10 #x333 #x333)
      ;; U+2122 ™
      (8482 8 2 7 6 #x3f #x17 #x15)
      ;; U+2190 ←
      (8592 10 2 6 6 #x8 #x10 #x3f #x10 #x8)
      ;; U+2191 ↑
      (8593 7 1 6 5 #x4 #xe #x15 #x4 #x4 #x4)
      ;; U+2192 →
      (8594 10 2 6 6 #x4 #x2 #x3f #x2 #x4)
      ;; U+2193 ↓
      (8595 7 1 6 5 #x4 #x4 #x4 #x15 #xe #x4)
      ;; U+2212 −
      (8722 10 6 3 5 #x1f)
      ;; U+221E ∞
      (8734 11 0 7 9 #xee #x111 #x111 #x111 #xee)
      ;; U+2248 ≈
      (8776 10 4 5 6 #x19 #x26 #x0 #x19 #x26)
      ;; U+2260 ≠
      (8800 11 1 8 7 #x8 #x8 #x7f #x8 #x7f #x8 #x8)
      ;; U+2264 ≤
      (8804 11 1 9 8 #x3 #xc #x30 #xc0 #x30 #xc #x3 #xff #x0 #xff)
      ;; U+2265 ≥
      (8805 11 1 9 8 #xc0 #x30 #xc #x3 #xc #x30 #xc0 #xff #x0 #xff))
     ("Medley Helvetica 10 Bold"
      10 10 3
      ;; the slug, which a character the font lacks draws
      (#f 8 1 10 7 #x7f #x7f #x7f #x7f #x7f #x7f #x7f #x7f #x7f #x7f #x7f #x7f
        #x7f)
      ;; ' '
      (32 5)
      ;; '!'
      (33 4 1 8 2 #x3 #x3 #x3 #x3 #x3 #x0 #x3 #x3)
      ;; '"'
      (34 7 1 8 5 #x1b #x1b #x1b)
      ;; '#'
      (35 9 1 8 7 #xa #xa #x3f #x14 #x14 #x7e #x28 #x28)
      ;; '$'
      (36 9 1 9 7 #x8 #x3e #x6b #x68 #x7e #x1f #xb #x6b #x3e #x8)
      ;; '%'
      (37 14 1 8 12 #x710 #xd90 #xda0 #x720 #x4e #x5b #x9b #x8e)
      ;; '&'
      (38 9 1 8 7 #x18 #x34 #x34 #x18 #x3b #x6e #x66 #x3b)
      ;; "'"
      (39 4 1 8 2 #x3 #x3 #x1 #x2)
      ;; '('
      (40 6 1 8 4 #x3 #x6 #x6 #xc #xc #xc #xc #xc #x6 #x6 #x3)
      ;; ')'
      (41 6 1 8 4 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc)
      ;; '*'
      (42 7 1 9 5 #x4 #x15 #xe #xe #x15 #x4)
      ;; '+'
      (43 8 1 6 6 #xc #xc #x3f #x3f #xc #xc)
      ;; ','
      (44 4 1 2 2 #x3 #x3 #x1 #x1 #x2)
      ;; '-'
      (45 7 1 5 5 #x1f #x1f)
      ;; '.'
      (46 4 1 2 2 #x3 #x3)
      ;; '/'
      (47 7 1 8 5 #x3 #x3 #x6 #x6 #xc #xc #x18 #x18)
      ;; '0'
      (48 8 1 8 6 #x1e #x33 #x33 #x33 #x33 #x33 #x33 #x1e)
      ;; '1'
      (49 8 2 8 4 #x3 #x7 #xf #x3 #x3 #x3 #x3 #x3)
      ;; '2'
      (50 8 1 8 6 #x1e #x33 #x3 #x6 #xc #x18 #x30 #x3f)
      ;; '3'
      (51 8 1 8 6 #x1e #x33 #x3 #xe #x3 #x33 #x33 #x1e)
      ;; '4'
      (52 8 1 8 6 #xe #x1e #x16 #x36 #x26 #x3f #x6 #x6)
      ;; '5'
      (53 8 1 8 6 #x1f #x18 #x18 #x3e #x33 #x3 #x33 #x1e)
      ;; '6'
      (54 8 1 8 6 #x1e #x33 #x30 #x3e #x33 #x33 #x33 #x1e)
      ;; '7'
      (55 8 1 8 6 #x3f #x3 #x6 #x6 #xc #xc #x18 #x18)
      ;; '8'
      (56 8 1 8 6 #x1e #x33 #x33 #x1e #x33 #x33 #x33 #x1e)
      ;; '9'
      (57 8 1 8 6 #x1e #x33 #x33 #x33 #x1f #x3 #x33 #x1e)
      ;; ':'
      (58 4 1 6 2 #x3 #x3 #x0 #x0 #x3 #x3)
      ;; ';'
      (59 4 1 6 2 #x3 #x3 #x0 #x0 #x3 #x3 #x1 #x1 #x2)
      ;; '<'
      (60 7 1 8 5 #x3 #x6 #xc #x18 #x18 #xc #x6 #x3)
      ;; '='
      (61 7 1 6 5 #x1f #x1f #x0 #x1f #x1f)
      ;; '>'
      (62 7 1 8 5 #x18 #xc #x6 #x3 #x3 #x6 #xc #x18)
      ;; '?'
      (63 8 1 8 6 #x1e #x33 #x33 #x6 #xc #x0 #xc #xc)
      ;; '@'
      (64 11 1 8 9 #x7c #x82 #x139 #x16d #x16d #x16d #x136 #x80 #x7f)
      ;; 'A'
      (65 8 0 8 7 #x8 #x1c #x1c #x36 #x36 #x3e #x63 #x63)
      ;; 'B'
      (66 7 0 8 6 #x3e #x33 #x33 #x3e #x33 #x33 #x33 #x3e)
      ;; 'C'
      (67 8 0 8 7 #x3e #x63 #x63 #x60 #x60 #x63 #x63 #x3e)
      ;; 'D'
      (68 8 0 8 7 #x7e #x63 #x63 #x63 #x63 #x63 #x63 #x7e)
      ;; 'E'
      (69 7 0 8 6 #x3f #x30 #x30 #x3e #x30 #x30 #x30 #x3f)
      ;; 'F'
      (70 7 0 8 6 #x3f #x30 #x30 #x3e #x30 #x30 #x30 #x30)
      ;; 'G'
      (71 8 0 8 7 #x3e #x63 #x60 #x67 #x63 #x63 #x67 #x3b)
      ;; 'H'
      (72 8 0 8 7 #x63 #x63 #x63 #x7f #x63 #x63 #x63 #x63)
      ;; 'I'
      (73 3 0 8 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; 'J'
      (74 7 0 8 6 #x3 #x3 #x3 #x3 #x3 #x33 #x33 #x1e)
      ;; 'K'
      (75 8 0 8 7 #x66 #x6c #x78 #x70 #x78 #x6c #x66 #x63)
      ;; 'L'
      (76 7 0 8 6 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x3f)
      ;; 'M'
      (77 10 0 8 9 #x1c7 #x1c7 #x1ef #x1ef #x1bb #x1bb #x1bb #x193)
      ;; 'N'
      (78 9 0 8 8 #xe3 #xf3 #xf3 #xdb #xdb #xcf #xcf #xc7)
      ;; 'O'
      (79 8 0 8 7 #x3e #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; 'P'
      (80 7 0 8 6 #x3e #x33 #x33 #x33 #x3e #x30 #x30 #x30)
      ;; 'Q'
      (81 8 0 8 7 #x3e #x63 #x63 #x63 #x63 #x63 #x6b #x3e #x6 #x3)
      ;; 'R'
      (82 7 0 8 6 #x3e #x33 #x33 #x33 #x3e #x33 #x33 #x33)
      ;; 'S'
      (83 7 0 8 6 #x1e #x33 #x38 #x1e #xf #x3 #x33 #x3e)
      ;; 'T'
      (84 7 0 8 6 #x3f #xc #xc #xc #xc #xc #xc #xc)
      ;; 'U'
      (85 8 0 8 7 #x63 #x63 #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; 'V'
      (86 9 0 8 8 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18 #x18)
      ;; 'W'
      (87 12 0 8 11 #x623 #x623 #x376 #x376 #x356 #x1dc #x1dc #x88)
      ;; 'X'
      (88 7 0 8 6 #x33 #x33 #x1e #xc #xc #x1e #x33 #x33)
      ;; 'Y'
      (89 9 0 8 8 #xc3 #xc3 #x66 #x3c #x18 #x18 #x18 #x18)
      ;; 'Z'
      (90 7 0 8 6 #x3f #x3 #x6 #xc #xc #x18 #x30 #x3f)
      ;; '['
      (91 6 1 8 4 #xf #xc #xc #xc #xc #xc #xc #xc #xc #xc #xf)
      ;; '\\'
      (92 7 1 8 5 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ']'
      (93 6 1 8 4 #xf #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #xf)
      ;; '^'
      (94 8 1 7 6 #xc #x1e #x3f #x2d #xc #xc #xc)
      ;; '_'
      (95 9 1 7 7 #x18 #x30 #x7f #x7f #x30 #x18)
      ;; '`'
      (96 4 1 8 2 #x1 #x2 #x3 #x3)
      ;; 'a'
      (97 7 0 6 6 #x1c #x6 #x1e #x36 #x36 #x1f)
      ;; 'b'
      (98 7 0 8 6 #x30 #x30 #x3e #x33 #x33 #x33 #x33 #x3e)
      ;; 'c'
      (99 7 0 6 6 #x1e #x33 #x30 #x30 #x33 #x1e)
      ;; 'd'
      (100 7 0 8 6 #x3 #x3 #x1f #x33 #x33 #x33 #x33 #x1f)
      ;; 'e'
      (101 7 0 6 6 #x1e #x33 #x3f #x30 #x33 #x1e)
      ;; 'f'
      (102 6 0 8 5 #x7 #xc #x1f #xc #xc #xc #xc #xc)
      ;; 'g'
      (103 7 0 6 6 #x1f #x33 #x33 #x33 #x33 #x1f #x3 #x33 #x1e)
      ;; 'h'
      (104 7 0 8 6 #x30 #x30 #x3e #x33 #x33 #x33 #x33 #x33)
      ;; 'i'
      (105 3 0 9 2 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; 'j'
      (106 4 0 9 3 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x6)
      ;; 'k'
      (107 8 0 8 7 #x60 #x60 #x66 #x6c #x78 #x6c #x66 #x63)
      ;; 'l'
      (108 3 0 8 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; 'm'
      (109 11 0 6 10 #x3de #x333 #x333 #x333 #x333 #x333)
      ;; 'n'
      (110 7 0 6 6 #x3e #x33 #x33 #x33 #x33 #x33)
      ;; 'o'
      (111 7 0 6 6 #x1e #x33 #x33 #x33 #x33 #x1e)
      ;; 'p'
      (112 7 0 6 6 #x3e #x33 #x33 #x33 #x33 #x3e #x30 #x30 #x30)
      ;; 'q'
      (113 7 0 6 6 #x1f #x33 #x33 #x33 #x33 #x1f #x3 #x3 #x3)
      ;; 'r'
      (114 6 0 6 5 #x1f #x1b #x18 #x18 #x18 #x18)
      ;; 's'
      (115 6 0 6 5 #xf #x19 #x1c #x7 #x13 #x1e)
      ;; 't'
      (116 6 0 7 5 #xc #x1f #xc #xc #xc #xc #x7)
      ;; 'u'
      (117 7 0 6 6 #x33 #x33 #x33 #x33 #x33 #x1f)
      ;; 'v'
      (118 8 0 6 7 #x63 #x63 #x36 #x36 #x1c #x1c)
      ;; 'w'
      (119 11 0 6 10 #x333 #x333 #x1b6 #x1fe #xcc #xcc)
      ;; 'x'
      (120 7 0 6 6 #x33 #x1e #xc #xc #x1e #x33)
      ;; 'y'
      (121 8 0 6 7 #x63 #x63 #x36 #x14 #x1c #x8 #x58 #x30)
      ;; 'z'
      (122 6 0 6 5 #x1f #x3 #x6 #xc #x18 #x1f)
      ;; '{'
      (123 7 1 8 5 #x7 #xc #xc #xc #xc #x18 #xc #xc #xc #xc #x7)
      ;; '|'
      (124 4 1 8 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; '}'
      (125 7 1 8 5 #x1c #x6 #x6 #x6 #x6 #x3 #x6 #x6 #x6 #x6 #x1c)
      ;; '~'
      (126 10 1 6 8 #x33 #x7e #xcc)
      ;; U+00A1 ¡
      (161 4 2 6 2 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3)
      ;; U+00A2 ¢
      (162 6 2 6 5 #x2 #xf #x1a #x1a #x1a #xf #x4)
      ;; U+00A3 £
      (163 6 2 7 5 #x7 #xc #xc #x1e #xc #xc #x1f)
      ;; U+00A5 ¥
      (165 6 0 7 6 #x33 #x33 #x1e #xc #x3f #xc #xc)
      ;; U+00A7 §
      (167 6 2 7 5 #xf #x18 #xc #x1e #x1b #xf #x6 #x3 #x1e)
      ;; U+00AB «
      (171 6 0 5 7 #x1b #x36 #x6c #x36 #x1b)
      ;; U+00AD ­
      (173 3 2 3 2 #x3 #x3)
      ;; U+00B0 °
      (176 3 0 8 4 #x6 #xd #xb #x6)
      ;; U+00B1 ±
      (177 10 6 8 6 #xc #xc #x3f #x3f #xc #xc #x0 #x3f #x3f)
      ;; U+00B6 ¶
      (182 5 0 7 6 #x1b #x3d #x3b #x1d #xb #xd #xb #xd #xb)
      ;; U+00B7 ·
      (183 3 2 4 2 #x3 #x3)
      ;; U+00BB »
      (187 6 0 5 7 #x6c #x36 #x1b #x36 #x6c)
      ;; U+00BC ¼
      (188 6 0 8 7 #xc #x1c #xc #xc #xc #x7f #xc #x1c #x2c #x3e #xc)
      ;; U+00BD ½
      (189 6 0 8 7 #xc #x1c #xc #xc #xc #x7f #x3c #x6 #xc #x18 #x3e)
      ;; U+00BE ¾
      (190 6 0 8 7 #x3c #x6 #x1c #x6 #x3c #x7f #xc #x1c #x2c #x3e #xc)
      ;; U+00BF ¿
      (191 5 2 6 4 #x6 #x6 #x0 #x6 #x6 #xc #xc #x7)
      ;; U+00C6 Æ
      (198 10 2 7 9 #x3f #x78 #x78 #xde #xd8 #x1f8 #x19f)
      ;; U+00D7 ×
      (215 10 6 5 6 #x33 #x1e #xc #x1e #x33)
      ;; U+00D8 Ø
      (216 8 2 7 7 #x3f #x67 #x6f #x7b #x7b #x73 #x7e)
      ;; U+00DF ß
      (223 6 2 8 6 #x1c #x36 #x36 #x36 #x33 #x33 #x33 #x36)
      ;; U+00E6 æ
      (230 9 0 5 9 #xfe #x1b #xff #x198 #xff)
      ;; U+00F7 ÷
      (247 10 6 5 6 #xc #x0 #x3f #x3f #x0 #xc)
      ;; U+00F8 ø
      (248 6 0 6 7 #x3 #x1e #x2e #x3e #x36 #x3c #x60)
      ;; U+0391 Α
      (913 8 0 7 8 #x18 #x18 #x3c #x2c #x7e #x46 #xef)
      ;; U+0392 Β
      (914 8 2 7 7 #x7e #x33 #x32 #x3f #x33 #x33 #x7e)
      ;; U+0393 Γ
      (915 7 0 7 7 #x7f #x33 #x31 #x30 #x30 #x30 #x78)
      ;; U+0394 Δ
      (916 8 0 7 8 #x18 #x18 #x3c #x2c #x4e #x46 #xff)
      ;; U+0395 Ε
      (917 8 0 7 7 #x7f #x33 #x35 #x3c #x35 #x33 #x7f)
      ;; U+0396 Ζ
      (918 7 2 7 6 #x3f #x26 #x2c #xc #x19 #x39 #x3f)
      ;; U+0397 Η
      (919 9 0 7 9 #x1ef #xc6 #xc6 #xfe #xc6 #xc6 #x1ef)
      ;; U+0398 Θ
      (920 8 2 7 7 #x3e #x63 #x77 #x7f #x77 #x63 #x3e)
      ;; U+0399 Ι
      (921 4 0 7 4 #xf #x6 #x6 #x6 #x6 #x6 #xf)
      ;; U+039A Κ
      (922 8 0 7 8 #xf7 #x66 #x68 #x7c #x6e #x66 #xff)
      ;; U+039B Λ
      (923 8 0 7 8 #x18 #x18 #x2c #x2c #x46 #x46 #xef)
      ;; U+039C Μ
      (924 10 0 7 10 #x387 #x1ce #x1ce #x176 #x176 #x136 #x3a7)
      ;; U+039D Ν
      (925 8 0 7 8 #xe7 #x72 #x5a #x5e #x4e #x46 #xe2)
      ;; U+039E Ξ
      (926 8 2 7 6 #x3f #x3f #x21 #xc #x21 #x3f #x3f)
      ;; U+039F Ο
      (927 8 2 7 7 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; U+03A0 Π
      (928 9 2 7 8 #xff #x66 #x66 #x66 #x66 #x66 #xe7)
      ;; U+03A1 Ρ
      (929 8 2 7 7 #x7e #x33 #x33 #x3e #x30 #x30 #x78)
      ;; U+03A3 Σ
      (931 7 2 7 6 #x3f #x31 #x18 #x8 #x11 #x3f #x3f)
      ;; U+03A4 Τ
      (932 7 2 7 6 #x3f #x2d #x2d #xc #xc #xc #x1e)
      ;; U+03A5 Υ
      (933 8 0 7 8 #xf7 #x62 #x34 #x34 #x18 #x18 #x3c)
      ;; U+03A6 Φ
      (934 9 2 8 8 #x3c #x18 #x7e #xdb #xdb #xdb #x7e #x18 #x3c)
      ;; U+03A7 Χ
      (935 8 0 7 8 #xf7 #x74 #x38 #x1c #x2c #x46 #xef)
      ;; U+03A8 Ψ
      (936 10 0 7 10 #x3b7 #x1b6 #x1b6 #x1b6 #xfc #x30 #x78)
      ;; U+03A9 Ω
      (937 8 2 7 7 #x3e #x63 #x63 #x63 #x22 #x55 #x77)
      ;; U+03B1 α
      (945 7 2 5 6 #x1e #x36 #x36 #x36 #x1b)
      ;; U+03B2 β
      (946 7 0 7 6 #xe #x1b #x1b #x1f #x1b #x1b #x1e #x18 #x3c)
      ;; U+03B3 γ
      (947 6 0 5 6 #x3b #x1a #x1a #xc #xc #xc #x1e)
      ;; U+03B4 δ
      (948 6 2 8 5 #xe #x1a #x18 #xe #x1b #x1b #x1b #xe)
      ;; U+03B5 ε
      (949 6 0 5 6 #x1c #x3a #x1c #x39 #x1e)
      ;; U+03B6 ζ
      (950 5 2 7 4 #xf #x2 #x4 #xc #xc #xc #x7 #x1 #x2)
      ;; U+03B7 η
      (951 7 0 5 7 #x76 #x3e #x36 #x36 #x76 #x6 #xf)
      ;; U+03B8 θ
      (952 7 2 7 5 #xe #x1b #x1b #x1f #x1b #x1b #xe)
      ;; U+03B9 ι
      (953 3 0 5 4 #xe #x6 #x6 #x6 #xf)
      ;; U+03BA κ
      (954 7 0 5 7 #x76 #x34 #x3c #x36 #x77)
      ;; U+03BB λ
      (955 6 0 7 6 #x1c #xc #xc #xe #x16 #x16 #x37)
      ;; U+03BC μ
      (956 7 0 5 7 #x76 #x36 #x36 #x36 #x3f #x30 #x70)
      ;; U+03BD ν
      (957 6 0 5 6 #x3b #x1a #x1a #xc #xc)
      ;; U+03BE ξ
      (958 5 0 7 5 #x1f #xc #xc #x7 #xc #xc #x7 #x1 #x2)
      ;; U+03BF ο
      (959 6 2 5 5 #xe #x1b #x1b #x1b #xe)
      ;; U+03C0 π
      (960 7 0 5 7 #x7f #x36 #x36 #x36 #x77)
      ;; U+03C1 ρ
      (961 7 0 5 6 #xe #x1b #x1b #x1b #x1e #x18 #x3c)
      ;; U+03C2 ς
      (962 5 0 5 5 #xf #x19 #x18 #x1c #xf #x1 #x2)
      ;; U+03C3 σ
      (963 7 2 5 6 #x1f #x36 #x36 #x36 #x1c)
      ;; U+03C4 τ
      (964 4 0 5 5 #x1e #xc #xc #xd #x6)
      ;; U+03C5 υ
      (965 7 0 5 7 #x6f #x36 #x36 #x36 #x1c)
      ;; U+03C6 φ
      (966 8 2 7 6 #x1c #xc #x1e #x2d #x2d #x2d #x1e #xc #x1e)
      ;; U+03C7 χ
      (967 6 0 5 6 #x3b #x1a #x1e #xc #xe #x16 #x37)
      ;; U+03C8 ψ
      (968 9 2 5 8 #xdb #x5a #xdb #xdb #x7e #x18 #x3c)
      ;; U+03C9 ω
      (969 8 2 5 7 #x36 #x63 #x6b #x6b #x3e)
      ;; U+2013 –
      (8211 5 0 4 5 #x1f #x1f)
      ;; U+2014 —
      (8212 10 0 3 10 #x3ff #x3ff)
      ;; U+2018 ‘
      (8216 3 2 8 2 #x1 #x3 #x3)
      ;; U+2019 ’
      (8217 3 2 8 2 #x3 #x3 #x2)
      ;; U+201C “
      (8220 6 2 8 4 #x5 #xf #xf)
      ;; U+201D ”
      (8221 6 2 8 4 #xf #xf #xa)
      ;; U+2020 †
      (8224 6 2 7 4 #x6 #x6 #xf #x6 #x6 #x6 #x6)
      ;; U+2021 ‡
      (8225 6 2 7 4 #x6 #x6 #xf #x6 #xf #x6 #x6)
      ;; U+2022 •
      (8226 6 2 6 5 #xe #x1f #x1f #x1f #xe)
      ;; U+2190 ←
      (8592 9 1 7 7 #x18 #x30 #x7f #x7f #x30 #x18)
      ;; U+2191 ↑
      (8593 8 1 7 6 #xc #x1e #x3f #x2d #xc #xc #xc)
      ;; U+2192 →
      (8594 9 1 7 7 #xc #x6 #x7f #x7f #x6 #xc)
      ;; U+2193 ↓
      (8595 8 1 7 6 #xc #xc #xc #x2d #x3f #x1e #xc)
      ;; U+2212 −
      (8722 10 6 3 5 #x1f #x1f))
     ("Medley Helvetica 12 Bold"
      12 12 4
      ;; the slug, which a character the font lacks draws
      (#f 9 1 12 8 #xff #xff #xff #xff #xff #xff #xff #xff #xff #xff #xff #xff
        #xff #xff #xff #xff)
      ;; ' '
      (32 7)
      ;; '!'
      (33 4 1 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x0 #x3 #x3)
      ;; '"'
      (34 7 1 10 5 #x1b #x1b #x1b #x1b)
      ;; '#'
      (35 12 1 10 10 #x33 #x33 #x66 #x1ff #xcc #xcc #x3fe #x198 #x330 #x330)
      ;; '$'
      (36 9 1 11 7 #x8 #x3e #x6b #x6b #x68 #x7c #x1e #xb #x6b #x6b #x3e #x8)
      ;; '%'
      (37 14 1 10 12 #x718 #xd98 #xdb0 #x730 #x60 #x60 #xce #xdb #x19b #x18e)
      ;; '&'
      (38 11 1 10 9 #x70 #xd8 #xd8 #x50 #x70 #xfb #x18e #x18c #x19e #xf7)
      ;; "'"
      (39 4 0 10 3 #x7 #x7 #x3 #x3 #x6)
      ;; '('
      (40 6 1 10 4 #x3 #x6 #x6 #xc #xc #xc #xc #xc #xc #x6 #x6 #x3)
      ;; ')'
      (41 6 1 10 4 #xc #x6 #x6 #x3 #x3 #x3 #x3 #x3 #x3 #x6 #x6 #xc)
      ;; '*'
      (42 7 1 11 5 #x4 #x15 #xe #xe #x15 #x4)
      ;; '+'
      (43 10 1 8 8 #x18 #x18 #x18 #xff #xff #x18 #x18 #x18)
      ;; ','
      (44 4 1 2 2 #x3 #x3 #x1 #x1 #x2)
      ;; '-'
      (45 9 2 5 6 #x3f #x3f)
      ;; '.'
      (46 4 1 2 2 #x3 #x3)
      ;; '/'
      (47 8 1 10 6 #x3 #x3 #x6 #x6 #xc #xc #x18 #x18 #x30 #x30)
      ;; '0'
      (48 9 1 10 7 #x1c #x36 #x63 #x63 #x63 #x63 #x63 #x63 #x36 #x1c)
      ;; '1'
      (49 9 2 10 5 #x3 #x7 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; '2'
      (50 9 1 10 7 #x3e #x63 #x63 #x3 #x6 #xc #x18 #x30 #x60 #x7f)
      ;; '3'
      (51 9 1 10 7 #x3e #x63 #x63 #x3 #xe #x3 #x3 #x63 #x63 #x3e)
      ;; '4'
      (52 9 1 10 7 #x6 #xe #x1e #x16 #x36 #x66 #x66 #x7f #x6 #x6)
      ;; '5'
      (53 9 1 10 7 #x3f #x30 #x30 #x7e #x63 #x63 #x3 #x63 #x63 #x3e)
      ;; '6'
      (54 9 1 10 7 #x1e #x33 #x63 #x60 #x7e #x63 #x63 #x63 #x63 #x3e)
      ;; '7'
      (55 9 1 10 7 #x7f #x3 #x6 #xc #xc #x18 #x18 #x30 #x30 #x30)
      ;; '8'
      (56 9 1 10 7 #x3e #x63 #x63 #x63 #x3e #x63 #x63 #x63 #x63 #x3e)
      ;; '9'
      (57 9 1 10 7 #x3e #x63 #x63 #x63 #x63 #x3f #x3 #x63 #x66 #x3c)
      ;; ':'
      (58 4 1 7 2 #x3 #x3 #x0 #x0 #x0 #x3 #x3)
      ;; ';'
      (59 4 1 7 2 #x3 #x3 #x0 #x0 #x0 #x3 #x3 #x1 #x1 #x2)
      ;; '<'
      (60 8 1 10 6 #x3 #x6 #xc #x18 #x30 #x30 #x18 #xc #x6 #x3)
      ;; '='
      (61 8 2 6 5 #x1f #x1f #x0 #x1f #x1f)
      ;; '>'
      (62 8 1 10 6 #x30 #x18 #xc #x6 #x3 #x3 #x6 #xc #x18 #x30)
      ;; '?'
      (63 8 1 10 6 #x1e #x33 #x33 #x3 #x6 #xc #xc #x0 #xc #xc)
      ;; '@'
      (64 14 1 10 12 #x3fc #x606 #xcf3 #xd9b #xd9b #xd9b #xd9a #xcec #x601
        #x3fe)
      ;; 'A'
      (65 9 0 10 8 #x18 #x18 #x3c #x3c #x24 #x66 #x7e #x66 #xc3 #xc3)
      ;; 'B'
      (66 8 0 10 7 #x7c #x66 #x66 #x66 #x7e #x63 #x63 #x63 #x63 #x7e)
      ;; 'C'
      (67 9 0 10 8 #x3e #x63 #xc3 #xc0 #xc0 #xc0 #xc3 #xc3 #x63 #x3e)
      ;; 'D'
      (68 9 0 10 8 #xfc #xc6 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc6 #xfc)
      ;; 'E'
      (69 8 0 10 7 #x7f #x60 #x60 #x60 #x7e #x60 #x60 #x60 #x60 #x7f)
      ;; 'F'
      (70 8 0 10 7 #x7f #x60 #x60 #x60 #x7e #x60 #x60 #x60 #x60 #x60)
      ;; 'G'
      (71 10 0 10 9 #x7e #xc3 #x183 #x180 #x180 #x18f #x183 #x183 #xc7 #x7b)
      ;; 'H'
      (72 9 0 10 8 #xc3 #xc3 #xc3 #xc3 #xff #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; 'I'
      (73 3 0 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; 'J'
      (74 7 0 10 6 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x33 #x33 #x1e)
      ;; 'K'
      (75 9 0 10 8 #xc6 #xcc #xd8 #xf0 #xe0 #xf0 #xd8 #xcc #xc6 #xc3)
      ;; 'L'
      (76 7 0 10 6 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x30 #x3f)
      ;; 'M'
      (77 12 0 10 11 #x707 #x707 #x78f #x78f #x6db #x6db #x6db #x673 #x673
        #x623)
      ;; 'N'
      (78 9 0 10 8 #xc3 #xe3 #xe3 #xf3 #xf3 #xdb #xdb #xcf #xcf #xc7)
      ;; 'O'
      (79 10 0 10 9 #x7c #xc6 #x183 #x183 #x183 #x183 #x183 #x183 #xc6 #x7c)
      ;; 'P'
      (80 8 0 10 7 #x7e #x63 #x63 #x63 #x63 #x7e #x60 #x60 #x60 #x60)
      ;; 'Q'
      (81 10 0 10 9 #x7c #xc6 #x183 #x183 #x183 #x183 #x183 #x19b #xce #x7e
        #x3)
      ;; 'R'
      (82 9 0 10 8 #xfe #xc3 #xc3 #xc3 #xfe #xc3 #xc3 #xc3 #xc3 #xc3)
      ;; 'S'
      (83 8 0 10 7 #x3e #x63 #x63 #x78 #x3e #xf #x63 #x63 #x63 #x3e)
      ;; 'T'
      (84 9 0 10 8 #xff #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18)
      ;; 'U'
      (85 9 0 10 8 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #x66 #x3c)
      ;; 'V'
      (86 9 0 10 8 #xc3 #xc3 #xc3 #x66 #x66 #x66 #x24 #x3c #x18 #x18)
      ;; 'W'
      (87 14 0 10 13 #x1843 #x1843 #xce6 #xce6 #xce6 #x5f4 #x7bc #x71c #x318
        #x318)
      ;; 'X'
      (88 9 0 10 8 #xc3 #xc3 #x66 #x3c #x18 #x18 #x3c #x66 #xc3 #xc3)
      ;; 'Y'
      (89 9 0 10 8 #xc3 #xc3 #x66 #x66 #x3c #x18 #x18 #x18 #x18 #x18)
      ;; 'Z'
      (90 9 0 10 8 #xff #x3 #x6 #xc #x18 #x18 #x30 #x60 #xc0 #xff)
      ;; '['
      (91 7 1 10 5 #x1f #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18 #x18
        #x1f)
      ;; '\\'
      (92 8 1 10 6 #x30 #x30 #x18 #x18 #xc #xc #x6 #x6 #x3 #x3)
      ;; ']'
      (93 7 1 10 5 #x1f #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x1f)
      ;; '^'
      (94 8 1 9 6 #xc #x1e #x3f #x2d #xc #xc #xc #xc)
      ;; '_'
      (95 10 1 8 8 #x30 #x60 #xff #xff #x60 #x30)
      ;; '`'
      (96 4 0 10 3 #x3 #x6 #x6 #x7 #x7)
      ;; 'a'
      (97 8 0 7 7 #x3c #x66 #x6 #x3e #x66 #x66 #x3b)
      ;; 'b'
      (98 8 0 10 7 #x60 #x60 #x60 #x7e #x63 #x63 #x63 #x63 #x63 #x7e)
      ;; 'c'
      (99 8 0 7 7 #x3e #x63 #x60 #x60 #x63 #x63 #x3e)
      ;; 'd'
      (100 8 0 10 7 #x3 #x3 #x3 #x3f #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; 'e'
      (101 8 0 7 7 #x3e #x63 #x63 #x7f #x60 #x63 #x3e)
      ;; 'f'
      (102 6 0 10 5 #x7 #xc #xc #x1f #xc #xc #xc #xc #xc #xc)
      ;; 'g'
      (103 8 0 7 7 #x3f #x63 #x63 #x63 #x63 #x63 #x3f #x3 #x63 #x3e)
      ;; 'h'
      (104 8 0 10 7 #x60 #x60 #x60 #x7e #x63 #x63 #x63 #x63 #x63 #x63)
      ;; 'i'
      (105 3 0 10 2 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; 'j'
      (106 5 0 10 4 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #xe)
      ;; 'k'
      (107 8 0 10 7 #x60 #x60 #x60 #x66 #x6c #x78 #x78 #x6c #x66 #x63)
      ;; 'l'
      (108 3 0 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; 'm'
      (109 11 0 7 10 #x3ee #x333 #x333 #x333 #x333 #x333 #x333)
      ;; 'n'
      (110 8 0 7 7 #x7e #x63 #x63 #x63 #x63 #x63 #x63)
      ;; 'o'
      (111 8 0 7 7 #x3e #x63 #x63 #x63 #x63 #x63 #x3e)
      ;; 'p'
      (112 8 0 7 7 #x7e #x63 #x63 #x63 #x63 #x63 #x7e #x60 #x60 #x60)
      ;; 'q'
      (113 8 0 7 7 #x3f #x63 #x63 #x63 #x63 #x63 #x3f #x3 #x3 #x3)
      ;; 'r'
      (114 6 0 7 5 #x1f #x1b #x18 #x18 #x18 #x18 #x18)
      ;; 's'
      (115 7 0 7 6 #x1e #x33 #x38 #x1e #x7 #x33 #x1e)
      ;; 't'
      (116 6 0 9 5 #xc #xc #x1f #xc #xc #xc #xc #xc #x7)
      ;; 'u'
      (117 8 0 7 7 #x63 #x63 #x63 #x63 #x63 #x63 #x3f)
      ;; 'v'
      (118 9 0 7 8 #xc3 #xc3 #x66 #x66 #x24 #x3c #x18)
      ;; 'w'
      (119 12 0 7 11 #x623 #x623 #x376 #x376 #x3de #x18c #x18c)
      ;; 'x'
      (120 7 0 7 6 #x33 #x33 #x1e #xc #x1e #x33 #x33)
      ;; 'y'
      (121 8 0 7 7 #x63 #x63 #x33 #x36 #x16 #x1e #xc #xc #x6c #x38)
      ;; 'z'
      (122 7 0 7 6 #x3f #x3 #x6 #xc #x18 #x30 #x3f)
      ;; '{'
      (123 8 1 10 6 #x7 #xc #xc #xc #xc #xc #x38 #xc #xc #xc #xc #xc #x7)
      ;; '|'
      (124 5 2 10 2 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; '}'
      (125 8 1 10 6 #x38 #xc #xc #xc #xc #xc #x7 #xc #xc #xc #xc #xc #x38)
      ;; '~'
      (126 10 1 6 8 #x33 #x7e #xcc)
      ;; U+00A1 ¡
      (161 5 4 7 2 #x3 #x3 #x0 #x3 #x3 #x3 #x3 #x3 #x3)
      ;; U+00A2 ¢
      (162 7 2 8 6 #x6 #x6 #x1f #x3e #x36 #x36 #x3e #x1f #xc #xc)
      ;; U+00A3 £
      (163 7 2 8 6 #xf #x18 #x18 #x3e #x18 #x18 #x18 #x3f)
      ;; U+00A5 ¥
      (165 7 0 9 6 #x33 #x33 #x1e #x1e #xc #x3f #xc #xc #xc)
      ;; U+00A7 §
      (167 7 2 8 6 #x1e #x30 #x18 #x3c #x36 #x1b #xf #x6 #x3 #x1e)
      ;; U+00AB «
      (171 7 0 5 7 #x1b #x36 #x6c #x36 #x1b)
      ;; U+00AD ­
      (173 4 2 4 3 #x7 #x7)
      ;; U+00B0 °
      (176 4 0 9 5 #xe #x1b #x1b #xe)
      ;; U+00B1 ±
      (177 12 6 8 6 #xc #xc #x3f #x3f #xc #xc #x0 #x3f #x3f)
      ;; U+00B6 ¶
      (182 6 0 9 6 #x1f #x3f #x3f #x3f #x1f #xf #xf #xf #xf #xf #xf)
      ;; U+00B7 ·
      (183 3 2 5 2 #x3 #x3)
      ;; U+00BB »
      (187 7 0 5 7 #x6c #x36 #x1b #x36 #x6c)
      ;; U+00BC ¼
      (188 7 0 8 7 #xc #x1c #xc #xc #xc #x7f #x6 #xe #x16 #x3f #x6)
      ;; U+00BD ½
      (189 7 0 8 7 #xc #x1c #xc #xc #xc #x7f #x1c #x6 #xc #x18 #x1e)
      ;; U+00BE ¾
      (190 7 0 8 7 #x1c #x6 #xc #x6 #x1c #x7f #x6 #xe #x16 #x3f #x6)
      ;; U+00BF ¿
      (191 6 2 7 5 #x6 #x6 #x0 #x6 #x6 #xc #x18 #x18 #xf)
      ;; U+00C6 Æ
      (198 12 2 8 10 #x3f #x78 #xd8 #xdf #x198 #x1f8 #x318 #x31f)
      ;; U+00D7 ×
      (215 12 6 6 7 #x63 #x36 #x1c #x1c #x36 #x63)
      ;; U+00D8 Ø
      (216 9 2 8 8 #x3f #x66 #xcf #xdb #xdb #xf3 #x66 #xfc)
      ;; U+00DF ß
      (223 7 2 9 6 #x1e #x33 #x33 #x33 #x36 #x33 #x33 #x33 #x36)
      ;; U+00E6 æ
      (230 11 2 6 10 #x1fe #x33 #x1ff #x330 #x370 #x1df)
      ;; U+00F7 ÷
      (247 12 4 7 8 #x18 #x18 #x0 #xff #xff #x0 #x18 #x18)
      ;; U+00F8 ø
      (248 7 2 6 6 #x1f #x37 #x2f #x3d #x3b #x3e)
      ;; U+2013 –
      (8211 6 0 4 6 #x3f #x3f)
      ;; U+2014 —
      (8212 12 0 4 12 #xfff #xfff)
      ;; U+2018 ‘
      (8216 3 0 9 3 #x3 #x7 #x6)
      ;; U+2019 ’
      (8217 3 0 9 3 #x3 #x7 #x6)
      ;; U+201C “
      (8220 7 0 9 7 #x33 #x66 #x66)
      ;; U+201D ”
      (8221 7 0 9 7 #x33 #x33 #x66)
      ;; U+2020 †
      (8224 7 2 8 6 #xc #xc #x3f #xc #xc #xc #xc #xc)
      ;; U+2021 ‡
      (8225 7 2 8 6 #xc #xc #x3f #xc #xc #x3f #xc #xc)
      ;; U+2022 •
      (8226 7 0 7 6 #x1e #x3f #x3f #x3f #x3f #x1e)
      ;; U+2190 ←
      (8592 10 1 8 8 #x30 #x60 #xff #xff #x60 #x30)
      ;; U+2191 ↑
      (8593 8 1 9 6 #xc #x1e #x3f #x2d #xc #xc #xc #xc)
      ;; U+2192 →
      (8594 10 1 8 8 #xc #x6 #xff #xff #x6 #xc)
      ;; U+2193 ↓
      (8595 8 1 9 6 #xc #xc #xc #xc #x2d #x3f #x1e #xc)
      ;; U+2212 −
      (8722 12 6 4 6 #x3f #x3f)))))
