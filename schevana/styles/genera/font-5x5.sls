;;; (schevana styles genera font-5x5) — the MIT CADR's 5X5 font, in which
;;; Genera and the CADR write people's names in lozenges: characters 32 to
;;; 96 (its small letters are its capitals), as px-bitmap-text takes a
;;; font. It is MIT's, decoded from MIT System 99's fonts/5x5.qfasl, and is
;;; used under this license:
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

(library (schevana styles genera font-5x5)
  (export genera-5x5)
  (import (chezscheme)
          (only (schevana base) define-made library-layer))

  (library-layer looks)

  (define-made genera-5x5
    (list 32 6 5
     '#(#x0          ; space
        #x8008208    ; !
        #x514        ; "
        #x12fd2fd2   ; #
        #x1ea1c2bc   ; $
        #x32108426   ; %
        #x2c4ac284   ; &
        #x108        ; '
        #x8104108    ; (
        #x4208204    ; )
        #x2273e722   ; *
        #x823e208    ; +
        #x4200000    ; ,
        #x3e000      ; -
        #x8000000    ; .
        #x2108420    ; /
        #xc49248c    ; 0
        #x1c20820c   ; 1
        #x3e21089c   ; 2
        #x1c89889c   ; 3
        #x1043e492   ; 4
        #x1e81e0be   ; 5
        #x1e89e09c   ; 6
        #x841083e    ; 7
        #x1c89c89c   ; 8
        #x1e83c89c   ; 9
        #x8008000    ; :
        #x4200200    ; ;
        #x10204210   ; <
        #x780780     ; =
        #x4210204    ; >
        #x410848c    ; ?
        #x3c09a89c   ; @
        #x228be89c   ; A
        #x1e89e89e   ; B
        #x3c0820bc   ; C
        #x1e92491e   ; D
        #x3e09e0be   ; E
        #x208e0be    ; F
        #x1c8b20bc   ; G
        #x228be8a2   ; H
        #x3e20823e   ; I
        #xc49043e    ; J
        #x12286292   ; K
        #x1e082082   ; L
        #x228aada2   ; M
        #x228b2aa6   ; N
        #x1c8a289c   ; O
        #x209e89e    ; P
        #x1429248c   ; Q
        #x2249e89e   ; R
        #x1e81c0bc   ; S
        #x820823e    ; T
        #x1c8a28a2   ; U
        #x85228a2    ; V
        #x22daa8a2   ; W
        #x22508522   ; X
        #x8208522    ; Y
        #x3e10843e   ; Z
        #xc10410c    ; [
        #x20408102   ; \
        #xc20820c    ; ]
        #x508        ; ^
        #x3e000000   ; _
        #x204))))    ; `
