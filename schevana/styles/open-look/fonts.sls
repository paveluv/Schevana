;;; (schevana styles open-look fonts) — OLGX's glyph fonts, the pictures
;;; the OPEN LOOK style draws its fixed parts from. OLGX draws nearly every
;;; fixed-size part (resize corners, pushpins, the window button, menu
;;; marks, the ends of buttons) as characters of a glyph font, one font for
;;; each scale, each drawn by hand at 10, 12, 14 and 19 pixels (75 dpi, one
;;; pixel per point). Here are the glyphs the style draws, as bitmap fonts
;;; that it registers and draws its parts in as text, generated from
;;; olgl10/12/14/19.bdf (X11R6 contrib, fonts/bdf/misc), with the fonts'
;;; notice, which every copy must carry:
;;;
;;;  Copyright 1989 by Sun Microsystems, Inc. Mountain View, CA.
;;;
;;;  Permission to use, copy, modify, and distribute this software and
;;;  its documentation for any purpose and without fee is hereby granted,
;;;  provided that the above copyright notices appear in all copies and
;;;  that both those copyright notices and this permission notice appear
;;;  in supporting documentation, and that the name of Sun Microsystems
;;;  not be used in advertising or publicity pertaining to distribution
;;;  of the software without specific, written prior permission.  Sun
;;;  Microsystems make no representations about the suitability of this
;;;  software for any purpose.  It is provided "as is" without express or
;;;  implied warranty.
;;;
;;;  SUN MICROSYSTEMS DISCLAIM ALL WARRANTIES WITH REGARD TO THIS
;;;  SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
;;;  FITNESS, IN NO EVENT SHALL SUN MICROSYSTEMS BE LIABLE FOR ANY
;;;  SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER
;;;  RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF
;;;  CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
;;;  CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

(library (schevana styles open-look fonts)
  (export open-look-fonts open-look-font-glyph open-look-glyph-string)
  (import (chezscheme)
          (only (schevana base) library-layer))

  (library-layer looks)

  ;; Returns the string of glyph name's one character in OLGX's glyph fonts,
  ;; name being what olgx.h calls it, in lower case with OLG_ dropped; #f
  ;; for a glyph not here.
  (define (open-look-glyph-string name)
    (let ([g (assq name open-look-glyph-strings)]) (and g (cdr g))))

  ;; Returns glyph name of the font for size 10, 12, 14 or 19, as
  ;; define-bitmap-font has it: (char advance left top width row ...), each
  ;; row width bits wide, with its leftmost pixel in the highest bit; #f for
  ;; a glyph not here.
  (define (open-look-font-glyph size name)
    (let ([s (open-look-glyph-string name)])
      (and s
           (let loop ([fonts open-look-fonts])
             (cond [(null? fonts) #f]
                   [(= (cadar fonts) size)
                    (assv (char->integer (string-ref s 0))
                          (cddddr (car fonts)))]
                   [else (loop (cdr fonts))])))))

  ;; The glyphs by name, each the string of its character (olgx.h's number,
  ;; on the right).
  (define open-look-glyph-strings
    '((menu-pin-out . "\x13;")                    ; 19
      (menu-pin-in . "\x14;")                     ; 20
      (abbrev-menu-button . "\x16;")              ; 22
      (abbrev-menu-button-inverted . "\x17;")     ; 23
      (button-ul . "\x18;")                       ; 24
      (button-ll . "\x19;")                       ; 25
      (button-left-endcap-fill . "\x1a;")         ; 26
      (button-lr . "\x1b;")                       ; 27
      (button-ur . "\x1c;")                       ; 28
      (button-right-endcap-fill . "\x1d;")        ; 29
      (button-top-1 . "\x1e;")                    ; 30
      (button-bottom-1 . "\x23;")                 ; 35
      (button-fill-1 . "\x28;")                   ; 40
      (vert-menu-mark-ul . "\x2d;")               ; 45
      (vert-menu-mark-lr . "\x2e;")               ; 46
      (vert-menu-mark-fill . "\x2f;")             ; 47
      (abbrev-menu-ul . "\x33;")                  ; 51
      (abbrev-menu-lr . "\x34;")                  ; 52
      (abbrev-menu-fill . "\x35;")                ; 53
      (ul-resize-ul . "\x58;")                    ; 88
      (ul-resize-lr . "\x59;")                    ; 89
      (ul-resize-fill . "\x5a;")                  ; 90
      (ur-resize-ul . "\x5b;")                    ; 91
      (ur-resize-lr . "\x5c;")                    ; 92
      (ur-resize-fill . "\x5d;")                  ; 93
      (lr-resize-ul . "\x5e;")                    ; 94
      (lr-resize-lr . "\x5f;")                    ; 95
      (lr-resize-fill . "\x60;")                  ; 96
      (ll-resize-ul . "\x61;")                    ; 97
      (ll-resize-lr . "\x62;")                    ; 98
      (ll-resize-fill . "\x63;")                  ; 99
      (pushpin-out-top . "\x64;")                 ; 100
      (pushpin-out-bottom . "\x65;")              ; 101
      (pushpin-out-middle . "\x66;")              ; 102
      (pushpin-in-top . "\x67;")                  ; 103
      (pushpin-in-bottom . "\x68;")               ; 104
      (pushpin-in-middle . "\x69;")               ; 105
      (dflt-button-left-endcap . "\x6a;")         ; 106
      (dflt-button-right-endcap . "\x6b;")        ; 107
      (dflt-button-middle-1 . "\x6c;")            ; 108
      (button-outline-left-endcap . "\x8b;")      ; 139
      (button-outline-right-endcap . "\x8c;")     ; 140
      (button-outline-middle-1 . "\x8d;")         ; 141
      (button-fill-2d-leftendcap . "\x92;")       ; 146
      (button-fill-2d-rightendcap . "\x93;")      ; 147
      (button-fill-2d-middle-1 . "\x94;")         ; 148
      (ul-resize-outline . "\xa2;")               ; 162
      (ur-resize-outline . "\xa3;")               ; 163
      (lr-resize-outline . "\xa4;")               ; 164
      (ll-resize-outline . "\xa5;")))             ; 165

  ;; OLGX's glyph fonts, each (name pixel-size ascent descent glyph ...) as
  ;; define-bitmap-font takes it. A glyph's top-left pixel is where OLGX
  ;; draws it, so a font's baseline is its top: its ascent is 0, its descent
  ;; its tallest glyph, and every glyph's left and top 0.
  (define open-look-fonts
    '(("OPEN LOOK Glyph 10" 10 0 18
       ;; 19 OLG_MENU_PIN_OUT
       (19 26 0 0 26 #x1c00 #x1206 #x1209 #x13f9 #x1209 #x1ff209 #xff209
         #x13f9 #x18013ff #x2401e0f #x2401e06 #x1801c00)
       ;; 20 OLG_MENU_PIN_IN
       (20 13 0 0 13 #x38 #x1c6 #x682 #x901 #x901 #x1101 #x1182 #x10c6 #x18fe
         #x83c #xe1c #x1ff8 #x19e0)
       ;; 22 OLG_ABBREV_MENU_BUTTON
       (22 14 0 0 14 #x1ffc #x2002 #x2003 #x27f3 #x2413 #x2223 #x2223 #x2143
         #x2143 #x2083 #x2003 #x1fff #xffe)
       ;; 23 OLG_ABBREV_MENU_BUTTON_INVERTED
       (23 14 0 0 14 #x1ffc #x2002 #x2ffb #x280b #x2beb #x2ddb #x2ddb #x2ebb
         #x2ebb #x2f7b #x2003 #x1fff #xffe)
       ;; 24 BUTTON_UL
       (24 8 0 0 8 #x3 #xc #x10 #x20 #x40 #x40 #x80 #x80 #x80 #x80 #x80 #x40
         #x40 #x20 #x0 #x0 #x0 #x0)
       ;; 25 BUTTON_LL
       (25 8 0 0 8 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x10 #xc #x3)
       ;; 26 BUTTON_LEFT_ENDCAP_FILL
       (26 8 0 0 8 #x0 #x3 #xf #x1f #x3f #x3f #x7f #x7f #x7f #x7f #x7f #x3f
         #x3f #x1f #xf #x3)
       ;; 27 BUTTON_LR
       (27 8 0 0 8 #x0 #x0 #x0 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x2 #x2 #x4 #x8
         #x30 #xc0)
       ;; 28 BUTTON_UR
       (28 5 0 0 5 #x18 #x6 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0)
       ;; 29 BUTTON_RIGHT_ENDCAP_FILL
       (29 7 0 0 7 #x0 #x60 #x78 #x7c #x7e #x7e #x7f #x7f #x7f #x7f #x7f #x7e
         #x7e #x7c #x78 #x60)
       ;; 30 BUTTON_TOP_1
       (30 1 0 0 1 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0)
       ;; 35 BUTTON_BOTTOM_1
       (35 1 0 0 1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x1)
       ;; 40 BUTTON_FILL_1
       (40 1 0 0 1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x0)
       ;; 45 VERT_MENU_MARK_UL
       (45 7 0 0 7 #x7f #x40 #x20 #x20 #x10 #x10 #x0)
       ;; 46 VERT_MENU_MARK_LR
       (46 7 0 0 7 #x0 #x1 #x2 #x2 #x4 #x4 #x8)
       ;; 47 VERT_MENU_MARK_FILL
       (47 7 0 0 7 #x0 #x3e #x1c #x1c #x8 #x8 #x0)
       ;; 51 ABBREV_MENU_UL
       (51 14 0 0 14 #x1ffe #x2000 #x2000 #x2000 #x2000 #x2000 #x2000 #x2000
         #x2000 #x2000 #x2000 #x0)
       ;; 52 ABBREV_MENU_LR
       (52 14 0 0 14 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1ffe)
       ;; 53 ABBREV_MENU_FILL
       (53 14 0 0 14 #x0 #x1ffe #x1ffe #x1ffe #x1ffe #x1ffe #x1ffe #x1ffe
         #x1ffe #x1ffe #x1ffe #x0)
       ;; 88 UL_RESIZE_UL
       (88 10 0 0 10 #x3ff #x200 #x200 #x200 #x200 #x200 #x200 #x200 #x200
         #x200)
       ;; 89 UL_RESIZE_LR
       (89 10 0 0 10 #x0 #x1 #x1 #x1 #x3f #x20 #x20 #x20 #x20 #x1e0)
       ;; 90 UL_RESIZE_FILL
       (90 10 0 0 10 #x0 #x1fe #x1fe #x1fe #x1c0 #x1c0 #x1c0 #x1c0 #x1c0 #x0)
       ;; 91 UR_RESIZE_UL
       (91 10 0 0 10 #x3ff #x200 #x200 #x200 #x200 #x10 #x10 #x10 #x10 #x10)
       ;; 92 UR_RESIZE_LR
       (92 10 0 0 10 #x0 #x1 #x1 #x1 #x1f1 #x1 #x1 #x1 #x1 #xf)
       ;; 93 UR_RESIZE_FILL
       (93 10 0 0 10 #x0 #x1fe #x1fe #x1fe #xe #xe #xe #xe #xe #x0)
       ;; 94 LR_RESIZE_UL
       (94 10 0 0 10 #x1f #x10 #x10 #x10 #x10 #x3f0 #x200 #x200 #x200 #x200)
       ;; 95 LR_RESIZE_LR
       (95 10 0 0 10 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1ff)
       ;; 96 LR_RESIZE_FILL
       (96 10 0 0 10 #x0 #xe #xe #xe #xe #xe #x1fe #x1fe #x1fe #x0)
       ;; 97 LL_RESIZE_UL
       (97 10 0 0 10 #x3e0 #x200 #x200 #x200 #x200 #x23f #x200 #x200 #x200
         #x200)
       ;; 98 LL_RESIZE_LR
       (98 10 0 0 10 #x0 #x20 #x20 #x20 #x20 #x0 #x1 #x1 #x1 #x1ff)
       ;; 99 LL_RESIZE_FILL
       (99 10 0 0 10 #x0 #x1c0 #x1c0 #x1c0 #x1c0 #x1c0 #x1fe #x1fe #x1fe #x0
         #x0)
       ;; 100 PUSHPIN_OUT_TOP
       (100 26 0 0 26 #x1c00 #x1006 #x1008 #x11f8 #x1008 #x1ff008 #x1008
         #x1008 #x1000 #x401000 #x401000 #x1801000)
       ;; 101 PUSHPIN_OUT_BOTTOM
       (101 26 0 0 26 #x0 #x200 #x201 #x201 #x201 #x201 #xfe209 #x3f9
         #x18003ff #x2000f0f #x2000e06 #xc00)
       ;; 102 PUSHPIN_OUT_MIDDLE
       (102 26 0 0 26 #x0 #xc00 #xc06 #xc06 #xdf6 #xdf6 #xdf6 #xc06 #xc00
         #x1800000 #x1800000 #x0)
       ;; 103 PUSHPIN_IN_TOP
       (103 13 0 0 13 #x38 #x1c4 #x680 #x900 #x900 #x1100 #x1180 #x1000 #x1800
         #x800 #x800 #x1000 #x0)
       ;; 104 PUSHPIN_IN_BOTTOM
       (104 13 0 0 13 #x0 #x2 #x2 #x1 #x1 #x1 #x2 #xc6 #xfe #x3c #x61c #xff8
         #x19e0)
       ;; 105 PUSHPIN_IN_MIDDLE
       (105 13 0 0 13 #x0 #x38 #x17c #x6fe #x6fe #xefe #xe7c #xf38 #x700 #x7c0
         #x1e0 #x0 #x0)
       ;; 106 DFLT_BUTTON_LEFT_ENDCAP
       (106 8 0 0 8 #x0 #x0 #x1 #x6 #x8 #x10 #x10 #x20 #x20 #x20 #x10 #x10 #x8
         #x6 #x1 #x0)
       ;; 107 DFLT_BUTTON_RIGHT_ENDCAP
       (107 8 0 0 8 #x0 #x0 #x80 #x60 #x10 #x8 #x8 #x4 #x4 #x4 #x8 #x8 #x10
         #x60 #x80 #x0)
       ;; 108 DFLT_BUTTON_MIDDLE_1
       (108 1 0 0 1 #x0 #x0 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x1 #x0)
       ;; 139 BUTTON_OUTLINE_LEFT_ENDCAP
       (139 8 0 0 8 #x3 #xc #x10 #x20 #x40 #x40 #x80 #x80 #x80 #x80 #x80 #x40
         #x40 #x20 #x10 #xc #x7 #x1)
       ;; 140 BUTTON_OUTLINE_RIGHT_ENDCAP
       (140 9 0 0 9 #x180 #x60 #x10 #x8 #x4 #x6 #x2 #x3 #x3 #x3 #x3 #x7 #x6
         #xe #x1c #x78 #x1f0 #x1c0)
       ;; 141 BUTTON_OUTLINE_MIDDLE_1
       (141 1 0 0 1 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x1 #x1)
       ;; 146 BUTTON_FILL_2D_LEFTENDCAP
       (146 8 0 0 8 #x0 #x0 #x1 #x7 #xf #x1f #x1f #x3f #x3f #x3f #x1f #x1f #xf
         #x7 #x1 #x0 #x0 #x0)
       ;; 147 BUTTON_FILL_2D_RIGHTENDCAP
       (147 8 0 0 8 #x0 #x0 #x80 #xe0 #xf0 #xf8 #xf8 #xfc #xfc #xfc #xf8 #xf8
         #xf0 #xe0 #x80 #x0 #x0 #x0)
       ;; 148 BUTTON_FILL_2D_MIDDLE_1
       (148 1 0 0 1 #x0 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x0 #x0 #x0)
       ;; 162 UL_RESIZE_OUTLINE
       (162 10 0 0 10 #x3ff #x201 #x201 #x201 #x23f #x220 #x220 #x220 #x220
         #x3e0)
       ;; 163 UR_RESIZE_OUTLINE
       (163 10 0 0 10 #x3ff #x201 #x201 #x201 #x3f1 #x11 #x11 #x11 #x11 #x1f)
       ;; 164 LR_RESIZE_OUTLINE
       (164 10 0 0 10 #x1f #x11 #x11 #x11 #x11 #x3f1 #x201 #x201 #x201 #x3ff)
       ;; 165 LL_RESIZE_OUTLINE
       (165 10 0 0 10 #x3e0 #x220 #x220 #x220 #x220 #x23f #x201 #x201 #x201
         #x3ff))
     ("OPEN LOOK Glyph 12" 12 0 20
       ;; 19 OLG_MENU_PIN_OUT
       (19 26 0 0 26 #x1c00 #x1206 #x1209 #x13f9 #x1209 #x1ff209 #xff209
         #x13f9 #x18013ff #x2401e0f #x2401e06 #x1801c00)
       ;; 20 OLG_MENU_PIN_IN
       (20 13 0 0 13 #x38 #x1c6 #x682 #x901 #x901 #x1101 #x1182 #x10c6 #x18fe
         #x83c #xe1c #x1ff8 #x19e0)
       ;; 22 OLG_ABBREV_MENU_BUTTON
       (22 16 0 0 16 #x7ffc #x8002 #x8003 #x8003 #x8fe3 #x8823 #x8443 #x8443
         #x8283 #x8283 #x8103 #x8003 #x8003 #x7fff #x3ffe)
       ;; 23 OLG_ABBREV_MENU_BUTTON_INVERTED
       (23 16 0 0 16 #x7ffc #x8002 #xbffb #xbffb #xb01b #xb7db #xbbbb #xbbbb
         #xbd7b #xbd7b #xbefb #xbffb #x8003 #x7ffe #x3ffc)
       ;; 24 BUTTON_UL
       (24 11 0 0 11 #x1c #x60 #x80 #x100 #x200 #x200 #x400 #x400 #x400 #x400
         #x400 #x400 #x400 #x200 #x200 #x100 #x0 #x0 #x0 #x0)
       ;; 25 BUTTON_LL
       (25 9 0 0 9 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x20 #x18 #x7 #x0)
       ;; 26 BUTTON_LEFT_ENDCAP_FILL
       (26 9 0 0 9 #x0 #x7 #x1f #x3f #x7f #x7f #xff #xff #xff #xff #xff #xff
         #xff #x7f #x7f #x3f #x1f #x7 #x0 #x0)
       ;; 27 BUTTON_LR
       (27 9 0 0 9 #x0 #x0 #x0 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x2
         #x4 #x8 #x30 #x1c0 #x0)
       ;; 28 BUTTON_UR
       (28 9 0 0 9 #x1c0 #x30 #x8 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0)
       ;; 29 BUTTON_RIGHT_ENDCAP_FILL
       (29 9 0 0 9 #x0 #x1c0 #x1f0 #x1f8 #x1fc #x1fc #x1fe #x1fe #x1fe #x1fe
         #x1fe #x1fe #x1fe #x1fc #x1fc #x1f8 #x1f0 #x1c0 #x0 #x0)
       ;; 30 BUTTON_TOP_1
       (30 1 0 0 1 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0)
       ;; 35 BUTTON_BOTTOM_1
       (35 1 0 0 1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x1)
       ;; 40 BUTTON_FILL_1
       (40 1 0 0 1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1 #x1 #x0)
       ;; 45 VERT_MENU_MARK_UL
       (45 7 0 0 7 #x7f #x40 #x20 #x20 #x10 #x10 #x0)
       ;; 46 VERT_MENU_MARK_LR
       (46 7 0 0 7 #x0 #x1 #x2 #x2 #x4 #x4 #x8)
       ;; 47 VERT_MENU_MARK_FILL
       (47 7 0 0 7 #x0 #x3e #x1c #x1c #x8 #x8 #x0)
       ;; 51 ABBREV_MENU_UL
       (51 16 0 0 16 #x7ffe #x8000 #x8000 #x8000 #x8000 #x8000 #x8000 #x8000
         #x8000 #x8000 #x8000 #x8000 #x8000 #x8000 #x0)
       ;; 52 ABBREV_MENU_LR
       (52 16 0 0 16 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x7ffe)
       ;; 53 ABBREV_MENU_FILL
       (53 16 0 0 16 #x0 #x7ffe #x7ffe #x7ffe #x7ffe #x7ffe #x7ffe #x7ffe
         #x7ffe #x7ffe #x7ffe #x7ffe #x7ffe #x7ffe #x0)
       ;; 88 UL_RESIZE_UL
       (88 11 0 0 11 #x7ff #x400 #x400 #x400 #x400 #x400 #x400 #x400 #x400
         #x400 #x400)
       ;; 89 UL_RESIZE_LR
       (89 11 0 0 11 #x0 #x1 #x1 #x1 #x7f #x40 #x40 #x40 #x40 #x40 #x3c0)
       ;; 90 UL_RESIZE_FILL
       (90 11 0 0 11 #x0 #x3fe #x3fe #x3fe #x380 #x380 #x380 #x380 #x380 #x380
         #x0)
       ;; 91 UR_RESIZE_UL
       (91 11 0 0 11 #x7ff #x400 #x400 #x400 #x400 #x10 #x10 #x10 #x10 #x10
         #x10)
       ;; 92 UR_RESIZE_LR
       (92 11 0 0 11 #x0 #x1 #x1 #x1 #x3f1 #x1 #x1 #x1 #x1 #x1 #xf)
       ;; 93 UR_RESIZE_FILL
       (93 11 0 0 11 #x0 #x3fe #x3fe #x3fe #xe #xe #xe #xe #xe #xe #x0)
       ;; 94 LR_RESIZE_UL
       (94 11 0 0 11 #x1f #x10 #x10 #x10 #x10 #x10 #x7f0 #x400 #x400 #x400
         #x400)
       ;; 95 LR_RESIZE_LR
       (95 11 0 0 11 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x3ff)
       ;; 96 LR_RESIZE_FILL
       (96 11 0 0 11 #x0 #xe #xe #xe #xe #xe #xe #x3fe #x3fe #x3fe #x0)
       ;; 97 LL_RESIZE_UL
       (97 11 0 0 11 #x7c0 #x400 #x400 #x400 #x400 #x400 #x43f #x400 #x400
         #x400 #x400)
       ;; 98 LL_RESIZE_LR
       (98 11 0 0 11 #x0 #x40 #x40 #x40 #x40 #x40 #x40 #x1 #x1 #x1 #x3ff)
       ;; 99 LL_RESIZE_FILL
       (99 11 0 0 11 #x0 #x380 #x380 #x380 #x380 #x380 #x380 #x3fe #x3fe #x3fe
         #x0)
       ;; 100 PUSHPIN_OUT_TOP
       (100 26 0 0 26 #x1c00 #x1006 #x1008 #x11f8 #x1008 #x1ff008 #x1008
         #x1008 #x1000 #x401000 #x401000 #x1801000)
       ;; 101 PUSHPIN_OUT_BOTTOM
       (101 26 0 0 26 #x0 #x200 #x201 #x201 #x201 #x201 #xfe209 #x3f9
         #x18003ff #x2000f0f #x2000e06 #xc00)
       ;; 102 PUSHPIN_OUT_MIDDLE
       (102 26 0 0 26 #x0 #xc00 #xc06 #xc06 #xdf6 #xdf6 #xdf6 #xc06 #xc00
         #x1800000 #x1800000 #x0)
       ;; 103 PUSHPIN_IN_TOP
       (103 13 0 0 13 #x38 #x1c4 #x680 #x900 #x900 #x1100 #x1180 #x1000 #x1800
         #x800 #x800 #x1000 #x0)
       ;; 104 PUSHPIN_IN_BOTTOM
       (104 13 0 0 13 #x0 #x2 #x2 #x1 #x1 #x1 #x2 #xc6 #xfe #x3c #x61c #xff8
         #x19e0)
       ;; 105 PUSHPIN_IN_MIDDLE
       (105 13 0 0 13 #x0 #x38 #x17c #x6fe #x6fe #xefe #xe7c #xf38 #x700 #x7c0
         #x1e0 #x0 #x0)
       ;; 106 DFLT_BUTTON_LEFT_ENDCAP
       (106 9 0 0 9 #x0 #x0 #x3 #xc #x10 #x20 #x20 #x40 #x40 #x40 #x40 #x40
         #x20 #x20 #x10 #xc #x3 #x0)
       ;; 107 DFLT_BUTTON_RIGHT_ENDCAP
       (107 9 0 0 9 #x0 #x0 #x180 #x60 #x10 #x8 #x8 #x4 #x4 #x4 #x4 #x4 #x8
         #x8 #x10 #x60 #x180 #x0)
       ;; 108 DFLT_BUTTON_MIDDLE_1
       (108 1 0 0 1 #x0 #x0 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x1 #x0)
       ;; 139 BUTTON_OUTLINE_LEFT_ENDCAP
       (139 9 0 0 9 #x7 #x18 #x20 #x40 #x80 #x80 #x100 #x100 #x100 #x100 #x100
         #x100 #x100 #x80 #x80 #x40 #x20 #x18 #xf #x7)
       ;; 140 BUTTON_OUTLINE_RIGHT_ENDCAP
       (140 10 0 0 10 #x380 #x60 #x10 #x8 #x4 #x6 #x2 #x3 #x3 #x3 #x3 #x3 #x3
         #x7 #x6 #xe #x1c #x78 #x3f0 #x3c0)
       ;; 141 BUTTON_OUTLINE_MIDDLE_1
       (141 1 0 0 1 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x1 #x1)
       ;; 146 BUTTON_FILL_2D_LEFTENDCAP
       (146 9 0 0 9 #x0 #x0 #x3 #xf #x1f #x3f #x3f #x7f #x7f #x7f #x7f #x7f
         #x3f #x3f #x1f #xf #x3)
       ;; 147 BUTTON_FILL_2D_RIGHTENDCAP
       (147 7 0 0 7 #x0 #x0 #x60 #x78 #x7c #x7e #x7e #x7f #x7f #x7f #x7f #x7f
         #x7e #x7e #x7c #x78 #x60 #x0 #x0 #x0)
       ;; 148 BUTTON_FILL_2D_MIDDLE_1
       (148 1 0 0 1 #x0 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1 #x1 #x0 #x0 #x0)
       ;; 162 UL_RESIZE_OUTLINE
       (162 11 0 0 11 #x7ff #x401 #x401 #x401 #x47f #x440 #x440 #x440 #x440
         #x440 #x7c0)
       ;; 163 UR_RESIZE_OUTLINE
       (163 11 0 0 11 #x7ff #x401 #x401 #x401 #x7f1 #x11 #x11 #x11 #x11 #x11
         #x1f)
       ;; 164 LR_RESIZE_OUTLINE
       (164 11 0 0 11 #x1f #x11 #x11 #x11 #x11 #x11 #x7f1 #x401 #x401 #x401
         #x7ff)
       ;; 165 LL_RESIZE_OUTLINE
       (165 11 0 0 11 #x7c0 #x440 #x440 #x440 #x440 #x440 #x47f #x401 #x401
         #x401 #x7ff))
     ("OPEN LOOK Glyph 14" 14 0 22
       ;; 19 OLG_MENU_PIN_OUT
       (19 29 0 0 29 #x3800 #x2406 #x2409 #x27f9 #x2409 #x2409 #xffe409
         #x7fe409 #x2409 #x27f9 #xc0027ff #x12003c0f #x12003c06 #xc003800)
       ;; 20 OLG_MENU_PIN_IN
       (20 15 0 0 15 #x70 #x38c #xe02 #x1202 #x2401 #x2401 #x4401 #x4603
         #x4202 #x638e #x21fc #x307c #x3c38 #x7ff0 #x6000)
       ;; 22 OLG_ABBREV_MENU_BUTTON
       (22 18 0 0 18 #x1fffc #x20002 #x20003 #x20003 #x23fe3 #x22023 #x21043
         #x21043 #x20883 #x20883 #x20503 #x20503 #x20203 #x20003 #x20003
         #x1ffff #xfffe)
       ;; 23 OLG_ABBREV_MENU_BUTTON_INVERTED
       (23 18 0 0 18 #x1fffc #x20002 #x2fffb #x2fffb #x2c01b #x2dfdb #x2efbb
         #x2efbb #x2f77b #x2f77b #x2fafb #x2fafb #x2fdfb #x2fffb #x20003
         #x1ffff #xfffe)
       ;; 24 BUTTON_UL
       (24 11 0 0 11 #xf #x30 #x40 #x80 #x100 #x200 #x200 #x400 #x400 #x400
         #x400 #x400 #x400 #x400 #x200 #x200 #x100 #x80 #x0 #x0 #x0 #x0)
       ;; 25 BUTTON_LL
       (25 11 0 0 11 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x40 #x30 #xf)
       ;; 26 BUTTON_LEFT_ENDCAP_FILL
       (26 11 0 0 11 #x0 #xf #x3f #x7f #xff #x1ff #x1ff #x3ff #x3ff #x3ff
         #x3ff #x3ff #x3ff #x3ff #x1ff #x1ff #xff #x7f #x3f #xf)
       ;; 27 BUTTON_LR
       (27 11 0 0 11 #x0 #x0 #x0 #x8 #x4 #x2 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x2 #x2 #x4 #x8 #x10 #x60 #x780)
       ;; 28 BUTTON_UR
       (28 11 0 0 11 #x780 #x60 #x10 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0)
       ;; 29 BUTTON_RIGHT_ENDCAP_FILL
       (29 11 0 0 11 #x0 #x780 #x7e0 #x7f0 #x7f8 #x7fc #x7fc #x7fe #x7fe #x7fe
         #x7fe #x7fe #x7fe #x7fe #x7fc #x7fc #x7f8 #x7f0 #x7e0 #x780)
       ;; 30 BUTTON_TOP_1
       (30 1 0 0 1 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x0 #x0)
       ;; 35 BUTTON_BOTTOM_1
       (35 1 0 0 1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x0 #x1)
       ;; 40 BUTTON_FILL_1
       (40 1 0 0 1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1 #x1 #x1 #x1 #x0)
       ;; 45 VERT_MENU_MARK_UL
       (45 11 0 0 11 #x7ff #x400 #x200 #x200 #x100 #x100 #x80 #x80 #x40 #x40
         #x0)
       ;; 46 VERT_MENU_MARK_LR
       (46 11 0 0 11 #x0 #x1 #x2 #x2 #x4 #x4 #x8 #x8 #x10 #x10 #x20)
       ;; 47 VERT_MENU_MARK_FILL
       (47 11 0 0 11 #x0 #x3fe #x1fc #x1fc #xf8 #xf8 #x70 #x70 #x20 #x20 #x0)
       ;; 51 ABBREV_MENU_UL
       (51 18 0 0 18 #x1fffe #x20000 #x20000 #x20000 #x20000 #x20000 #x20000
         #x20000 #x20000 #x20000 #x20000 #x20000 #x20000 #x20000 #x20000 #x0)
       ;; 52 ABBREV_MENU_LR
       (52 18 0 0 18 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1fffe)
       ;; 53 ABBREV_MENU_FILL
       (53 18 0 0 18 #x0 #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe
         #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe #x0)
       ;; 88 UL_RESIZE_UL
       (88 12 0 0 12 #xfff #x800 #x800 #x800 #x800 #x800 #x800 #x800 #x800
         #x800 #x800 #x800)
       ;; 89 UL_RESIZE_LR
       (89 12 0 0 12 #x0 #x1 #x1 #x1 #x1 #x7f #x40 #x40 #x40 #x40 #x40 #x7c0)
       ;; 90 UL_RESIZE_FILL
       (90 12 0 0 12 #x0 #x7fe #x7fe #x7fe #x7fe #x780 #x780 #x780 #x780 #x780
         #x780 #x0)
       ;; 91 UR_RESIZE_UL
       (91 12 0 0 12 #xfff #x800 #x800 #x800 #x800 #x800 #x20 #x20 #x20 #x20
         #x20 #x20)
       ;; 92 UR_RESIZE_LR
       (92 12 0 0 12 #x0 #x1 #x1 #x1 #x1 #x7e1 #x1 #x1 #x1 #x1 #x1 #x1f)
       ;; 93 UR_RESIZE_FILL
       (93 12 0 0 12 #x0 #x7fe #x7fe #x7fe #x7fe #x1e #x1e #x1e #x1e #x1e #x1e
         #x0)
       ;; 94 LR_RESIZE_UL
       (94 12 0 0 12 #x3f #x20 #x20 #x20 #x20 #x20 #xfe0 #x800 #x800 #x800
         #x800 #x800)
       ;; 95 LR_RESIZE_LR
       (95 12 0 0 12 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x7ff)
       ;; 96 LR_RESIZE_FILL
       (96 12 0 0 12 #x0 #x1e #x1e #x1e #x1e #x1e #x1e #x7fe #x7fe #x7fe #x7fe
         #x0)
       ;; 97 LL_RESIZE_UL
       (97 12 0 0 12 #xf80 #x800 #x800 #x800 #x800 #x800 #x87f #x800 #x800
         #x800 #x800 #x800)
       ;; 98 LL_RESIZE_LR
       (98 12 0 0 12 #x0 #x40 #x40 #x40 #x40 #x40 #x0 #x1 #x1 #x1 #x1 #x7ff)
       ;; 99 LL_RESIZE_FILL
       (99 12 0 0 12 #x0 #x780 #x780 #x780 #x780 #x780 #x780 #x7fe #x7fe #x7fe
         #x7fe #x0)
       ;; 100 PUSHPIN_OUT_TOP
       (100 28 0 0 28 #x1c00 #x1006 #x1008 #x11f8 #x1008 #x1008 #x7ff008
         #x1008 #x1008 #x1008 #x1000 #x1001000 #x1001000 #x6001000)
       ;; 101 PUSHPIN_OUT_BOTTOM
       (101 28 0 0 28 #x0 #x200 #x201 #x201 #x201 #x201 #x201 #x3fe209 #x3f9
         #x3ff #x600020f #x8000e06 #x8000e00 #xc00)
       ;; 102 PUSHPIN_OUT_MIDDLE
       (102 28 0 0 28 #x0 #xc00 #xc06 #xc06 #xdf6 #xdf6 #xdf6 #xdf6 #xdf6
         #xc06 #xc00 #x6000000 #x6000000 #x0)
       ;; 103 PUSHPIN_IN_TOP
       (103 15 0 0 15 #x70 #x388 #xe00 #x1200 #x2400 #x2400 #x4400 #x4600
         #x4000 #x6000 #x2000 #x2000 #x2000 #x4000 #x0)
       ;; 104 PUSHPIN_IN_BOTTOM
       (104 15 0 0 15 #x0 #x4 #x2 #x2 #x1 #x1 #x1 #x3 #x202 #x38e #x1fc #x107c
         #x1c38 #x3ff0 #x63c0)
       ;; 105 PUSHPIN_IN_MIDDLE
       (105 15 0 0 15 #x0 #x70 #x1fc #xdfc #x1bfe #x1bfe #x3bfe #x39fc #x3dfc
         #x1c70 #x1e00 #xf80 #x3c0 #x0 #x0)
       ;; 106 DFLT_BUTTON_LEFT_ENDCAP
       (106 11 0 0 11 #x0 #x0 #x7 #x18 #x20 #x40 #x80 #x80 #x100 #x100 #x100
         #x100 #x100 #x80 #x80 #x40 #x20 #x18 #x7 #x0)
       ;; 107 DFLT_BUTTON_RIGHT_ENDCAP
       (107 11 0 0 11 #x0 #x0 #x700 #xc0 #x20 #x10 #x8 #x8 #x4 #x4 #x4 #x4 #x4
         #x8 #x8 #x10 #x20 #xc0 #x700 #x0)
       ;; 108 DFLT_BUTTON_MIDDLE_1
       (108 1 0 0 1 #x0 #x0 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x1 #x0)
       ;; 139 BUTTON_OUTLINE_LEFT_ENDCAP
       (139 11 0 0 11 #xf #x30 #x40 #x80 #x100 #x200 #x200 #x400 #x400 #x400
         #x400 #x400 #x400 #x400 #x200 #x200 #x100 #x80 #x40 #x30 #x1f #xf)
       ;; 140 BUTTON_OUTLINE_RIGHT_ENDCAP
       (140 12 0 0 12 #xf00 #xc0 #x20 #x10 #x8 #x4 #x6 #x2 #x3 #x3 #x3 #x3 #x3
         #x3 #x7 #x6 #xe #x1c #x38 #xf0 #xfe0 #xf80)
       ;; 141 BUTTON_OUTLINE_MIDDLE_1
       (141 1 0 0 1 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x0 #x0 #x1 #x1)
       ;; 146 BUTTON_FILL_2D_LEFTENDCAP
       (146 11 0 0 11 #x0 #x0 #x7 #x1f #x3f #x7f #xff #xff #x1ff #x1ff #x1ff
         #x1ff #x1ff #xff #xff #x7f #x3f #x1f #x7 #x0 #x0 #x0)
       ;; 147 BUTTON_FILL_2D_RIGHTENDCAP
       (147 11 0 0 11 #x0 #x0 #x700 #x7c0 #x7e0 #x7f0 #x7f8 #x7f8 #x7fc #x7fc
         #x7fc #x7fc #x7fc #x7f8 #x7f8 #x7f0 #x7e0 #x7c0 #x700 #x0 #x0 #x0)
       ;; 148 BUTTON_FILL_2D_MIDDLE_1
       (148 1 0 0 1 #x0 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1 #x1 #x1 #x1 #x0 #x0 #x0)
       ;; 162 UL_RESIZE_OUTLINE
       (162 12 0 0 12 #xfff #x801 #x801 #x801 #x801 #x87f #x840 #x840 #x840
         #x840 #x840 #xfc0)
       ;; 163 UR_RESIZE_OUTLINE
       (163 12 0 0 12 #xfff #x801 #x801 #x801 #x801 #xfe1 #x21 #x21 #x21 #x21
         #x21 #x3f)
       ;; 164 LR_RESIZE_OUTLINE
       (164 12 0 0 12 #x3f #x21 #x21 #x21 #x21 #x21 #xfe1 #x801 #x801 #x801
         #x801 #xfff)
       ;; 165 LL_RESIZE_OUTLINE
       (165 12 0 0 12 #xfc0 #x840 #x840 #x840 #x840 #x840 #x87f #x801 #x801
         #x801 #x801 #xfff))
     ("OPEN LOOK Glyph 19" 19 0 29
       ;; 19 OLG_MENU_PIN_OUT
       (19 29 0 0 29 #x3800 #x2406 #x2409 #x27f9 #x2409 #x2409 #xffe409
         #x7fe409 #x2409 #x27f9 #xc0027ff #x12003c0f #x12003c06 #xc003800)
       ;; 20 OLG_MENU_PIN_IN
       (20 15 0 0 15 #x70 #x38c #xe02 #x1202 #x2401 #x2401 #x4401 #x4603
         #x4202 #x638e #x21fc #x307c #x3c38 #x7ff0 #x6000)
       ;; 22 OLG_ABBREV_MENU_BUTTON
       (22 22 0 0 22 #xffff8 #x100004 #x200002 #x200003 #x200003 #x21ffc3
         #x210043 #x208083 #x208083 #x204103 #x204103 #x202203 #x202203
         #x201403 #x201403 #x200803 #x200003 #x200003 #x100007 #xffffe #x7fffc)
       ;; 23 OLG_ABBREV_MENU_BUTTON_INVERTED
       (23 22 0 0 22 #xffff8 #x100004 #x27fff2 #x2ffffb #x2ffffb #x2e003b
         #x2effbb #x2f7f7b #x2f7f7b #x2fbefb #x2fbefb #x2fddfb #x2fddfb
         #x2febfb #x2febfb #x2ff7fb #x2ffffb #x27fff3 #x100007 #xffffe #x7fffc)
       ;; 24 BUTTON_UL
       (24 18 0 0 18 #xff #x700 #xc00 #x3000 #x6000 #x4000 #x8000 #x18000
         #x10000 #x10000 #x20000 #x20000 #x20000 #x20000 #x20000 #x20000
         #x20000 #x10000 #x10000 #x18000 #x8000 #x4000 #x6000 #x3000 #x0 #x0
         #x0 #x0)
       ;; 25 BUTTON_LL
       (25 18 0 0 18 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x1c00 #x700 #x1ff)
       ;; 26 BUTTON_LEFT_ENDCAP_FILL
       (26 18 0 0 18 #x0 #xff #x3ff #xfff #x1fff #x3fff #x7fff #x7fff #xffff
         #xffff #x1ffff #x1ffff #x1ffff #x1ffff #x1ffff #x1ffff #x1ffff #xffff
         #xffff #x7fff #x7fff #x3fff #x1fff #xfff #x3ff #xff #x0 #x0)
       ;; 27 BUTTON_LR
       (27 18 0 0 18 #x0 #x0 #x0 #x30 #x18 #x8 #x4 #x6 #x2 #x2 #x1 #x1 #x1 #x1
         #x1 #x1 #x1 #x2 #x2 #x6 #x4 #x8 #x18 #x30 #xc0 #x380 #x3fc00)
       ;; 28 BUTTON_UR
       (28 18 0 0 18 #x3fc00 #x380 #xc0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0)
       ;; 29 BUTTON_RIGHT_ENDCAP_FILL
       (29 18 0 0 18 #x0 #x3fc00 #x3ff00 #x3ffc0 #x3ffe0 #x3fff0 #x3fff8
         #x3fff8 #x3fffc #x3fffc #x3fffe #x3fffe #x3fffe #x3fffe #x3fffe
         #x3fffe #x3fffe #x3fffc #x3fffc #x3fff8 #x3fff8 #x3fff0 #x3ffe0
         #x3ffc0 #x3ff00 #x3fc00 #x0 #x0)
       ;; 30 BUTTON_TOP_1
       (30 1 0 0 1 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0)
       ;; 35 BUTTON_BOTTOM_1
       (35 1 0 0 1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x1)
       ;; 40 BUTTON_FILL_1
       (40 1 0 0 1 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x0 #x0)
       ;; 45 VERT_MENU_MARK_UL
       (45 13 0 0 13 #x1fff #x1000 #x800 #x800 #x400 #x400 #x200 #x200 #x100
         #x100 #x80 #x80 #x0)
       ;; 46 VERT_MENU_MARK_LR
       (46 13 0 0 13 #x0 #x1 #x2 #x2 #x4 #x4 #x8 #x8 #x10 #x10 #x20 #x20 #x40)
       ;; 47 VERT_MENU_MARK_FILL
       (47 13 0 0 13 #x0 #xffe #x7fc #x7fc #x3f8 #x3f8 #x1f0 #x1f0 #xe0 #xe0
         #x40 #x40 #x0)
       ;; 51 ABBREV_MENU_UL
       (51 21 0 0 21 #x7fffc #x80000 #x100000 #x100000 #x100000 #x100000
         #x100000 #x100000 #x100000 #x100000 #x100000 #x100000 #x100000
         #x100000 #x100000 #x100000 #x100000 #x100000 #x100000 #x80000 #x0)
       ;; 52 ABBREV_MENU_LR
       (52 21 0 0 21 #x0 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1 #x1 #x1 #x1 #x2 #x7fffc)
       ;; 53 ABBREV_MENU_FILL
       (53 21 0 0 21 #x0 #x7fffc #xffffe #xffffe #xffffe #xffffe #xffffe
         #xffffe #xffffe #xffffe #xffffe #xffffe #xffffe #xffffe #xffffe
         #xffffe #xffffe #xffffe #xffffe #x7fffc #x0)
       ;; 88 UL_RESIZE_UL
       (88 14 0 0 14 #x3fff #x2000 #x2000 #x2000 #x2000 #x2000 #x2000 #x2000
         #x2000 #x2000 #x2000 #x2000 #x2000 #x2000)
       ;; 89 UL_RESIZE_LR
       (89 14 0 0 14 #x0 #x1 #x1 #x1 #x1 #x1ff #x100 #x100 #x100 #x100 #x100
         #x100 #x100 #x1f00)
       ;; 90 UL_RESIZE_FILL
       (90 14 0 0 14 #x0 #x1ffe #x1ffe #x1ffe #x1ffe #x1e00 #x1e00 #x1e00
         #x1e00 #x1e00 #x1e00 #x1e00 #x1e00 #x0)
       ;; 91 UR_RESIZE_UL
       (91 14 0 0 14 #x3fff #x2000 #x2000 #x2000 #x2000 #x2000 #x20 #x20 #x20
         #x20 #x20 #x20 #x20 #x20)
       ;; 92 UR_RESIZE_LR
       (92 14 0 0 14 #x0 #x1 #x1 #x1 #x1 #x1fc1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1f)
       ;; 93 UR_RESIZE_FILL
       (93 14 0 0 14 #x0 #x1ffe #x1ffe #x1ffe #x1ffe #x1e #x1e #x1e #x1e #x1e
         #x1e #x1e #x1e #x0)
       ;; 94 LR_RESIZE_UL
       (94 14 0 0 14 #x3f #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x3fe0 #x2000
         #x2000 #x2000 #x2000 #x2000)
       ;; 95 LR_RESIZE_LR
       (95 14 0 0 14 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1fff)
       ;; 96 LR_RESIZE_FILL
       (96 14 0 0 14 #x0 #x1e #x1e #x1e #x1e #x1e #x1e #x1e #x1e #x1ffe #x1ffe
         #x1ffe #x1ffe #x0)
       ;; 97 LL_RESIZE_UL
       (97 14 0 0 14 #x3f00 #x2000 #x2000 #x2000 #x2000 #x2000 #x2000 #x2000
         #x20ff #x2000 #x2000 #x2000 #x2000 #x2000)
       ;; 98 LL_RESIZE_LR
       (98 14 0 0 14 #x0 #x100 #x100 #x100 #x100 #x100 #x100 #x100 #x0 #x1 #x1
         #x1 #x1 #x1fff)
       ;; 99 LL_RESIZE_FILL
       (99 13 0 0 13 #x0 #xf00 #xf00 #xf00 #xf00 #xf00 #xf00 #xf00 #xf00 #xfff
         #xfff #xfff #xfff)
       ;; 100 PUSHPIN_OUT_TOP
       (100 28 0 0 28 #x1c00 #x1006 #x1008 #x11f8 #x1008 #x1008 #x7ff008
         #x1008 #x1008 #x1008 #x1000 #x1001000 #x1001000 #x6001000)
       ;; 101 PUSHPIN_OUT_BOTTOM
       (101 28 0 0 28 #x0 #x200 #x201 #x201 #x201 #x201 #x201 #x3fe209 #x3f9
         #x3ff #x600020f #x8000e06 #x8000e00 #xc00)
       ;; 102 PUSHPIN_OUT_MIDDLE
       (102 28 0 0 28 #x0 #xc00 #xc06 #xc06 #xdf6 #xdf6 #xdf6 #xdf6 #xdf6
         #xc06 #xc00 #x6000000 #x6000000 #x0)
       ;; 103 PUSHPIN_IN_TOP
       (103 15 0 0 15 #x70 #x388 #xe00 #x1200 #x2400 #x2400 #x4400 #x4600
         #x4000 #x6000 #x2000 #x2000 #x2000 #x4000 #x0)
       ;; 104 PUSHPIN_IN_BOTTOM
       (104 15 0 0 15 #x0 #x4 #x2 #x2 #x1 #x1 #x1 #x3 #x202 #x38e #x1fc #x107c
         #x1c38 #x3ff0 #x63c0)
       ;; 105 PUSHPIN_IN_MIDDLE
       (105 15 0 0 15 #x0 #x70 #x1fc #xdfc #x1bfe #x1bfe #x3bfe #x39fc #x3dfc
         #x1c70 #x1e00 #xf80 #x3c0 #x0 #x0)
       ;; 106 DFLT_BUTTON_LEFT_ENDCAP
       (106 18 0 0 18 #x0 #x0 #x7f #x180 #x600 #x800 #x1000 #x2000 #x2000
         #x4000 #x4000 #x8000 #x8000 #x8000 #x8000 #x8000 #x4000 #x4000 #x2000
         #x2000 #x1000 #x800 #x600 #x180 #x7f #x0)
       ;; 107 DFLT_BUTTON_RIGHT_ENDCAP
       (107 18 0 0 18 #x0 #x0 #x3f800 #x600 #x180 #x40 #x20 #x10 #x10 #x8 #x8
         #x4 #x4 #x4 #x4 #x4 #x8 #x8 #x10 #x10 #x20 #x40 #x180 #x600 #x3f800
         #x0)
       ;; 108 DFLT_BUTTON_MIDDLE_1
       (108 1 0 0 1 #x0 #x0 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x1 #x0)
       ;; 139 BUTTON_OUTLINE_LEFT_ENDCAP
       (139 18 0 0 18 #xff #x700 #xc00 #x3000 #x6000 #x4000 #x8000 #x18000
         #x10000 #x10000 #x20000 #x20000 #x20000 #x20000 #x20000 #x20000
         #x20000 #x10000 #x10000 #x18000 #x8000 #x4000 #x6000 #x3000 #x1c00
         #x700 #x3ff #x7f)
       ;; 140 BUTTON_OUTLINE_RIGHT_ENDCAP
       (140 19 0 0 19 #x7f800 #x700 #x180 #x60 #x30 #x18 #x8 #xc #x6 #x6 #x2
         #x3 #x3 #x3 #x3 #x3 #x3 #x7 #x6 #xe #xc #x1c #x38 #x78 #x1f0 #x7e0
         #x7ff80 #x7fc00)
       ;; 141 BUTTON_OUTLINE_MIDDLE_1
       (141 1 0 0 1 #x1 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0
         #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x0 #x1 #x1)
       ;; 146 BUTTON_FILL_2D_LEFTENDCAP
       (146 18 0 0 18 #x0 #x0 #x0 #x7f #x1ff #x7ff #xfff #x1fff #x1fff #x3fff
         #x3fff #x7fff #x7fff #x7fff #x7fff #x7fff #x3fff #x3fff #x1fff #x1fff
         #xfff #x7ff #x1ff #x7f #x0 #x0 #x0)
       ;; 147 BUTTON_FILL_2D_RIGHTENDCAP
       (147 18 0 0 18 #x0 #x0 #x0 #x3f800 #x3fe00 #x3ff80 #x3ffc0 #x3ffe0
         #x3ffe0 #x3fff0 #x3fff0 #x3fff8 #x3fff8 #x3fff8 #x3fff8 #x3fff8
         #x3fff0 #x3fff0 #x3ffe0 #x3ffe0 #x3ffc0 #x3ff80 #x3fe00 #x3f800 #x0
         #x0 #x0)
       ;; 148 BUTTON_FILL_2D_MIDDLE_1
       (148 1 0 0 1 #x0 #x0 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x0 #x0 #x0)
       ;; 162 UL_RESIZE_OUTLINE
       (162 14 0 0 14 #x3fff #x2001 #x2001 #x2001 #x2001 #x21ff #x2100 #x2100
         #x2100 #x2100 #x2100 #x2100 #x2100 #x3f00)
       ;; 163 UR_RESIZE_OUTLINE
       (163 14 0 0 14 #x3fff #x2001 #x2001 #x2001 #x2001 #x3fe1 #x21 #x21 #x21
         #x21 #x21 #x21 #x21 #x3f)
       ;; 164 LR_RESIZE_OUTLINE
       (164 14 0 0 14 #x3f #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x3fe1 #x2001
         #x2001 #x2001 #x2001 #x3fff)
       ;; 165 LL_RESIZE_OUTLINE
       (165 14 0 0 14 #x3f00 #x2100 #x2100 #x2100 #x2100 #x2100 #x2100 #x2100
         #x21ff #x2001 #x2001 #x2001 #x2001 #x3fff)))))
