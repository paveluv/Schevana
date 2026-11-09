;;; font.ss — fonts, from FreeType directly, and the glyph atlas.
;;;
;;; Layout doesn't depend on the scale. When a face is first used, every
;;; character's unhinted advance and ink go into a table, so what a draw
;;; asks about text is arithmetic on read-only tables: no device, no context,
;;; any thread. Text wraps the same at every scale, and changing the scale
;;; measures nothing again.
;;;
;;; A glyph is drawn once for each size and quarter-pixel phase used, on
;;; first use, into one atlas (FreeType takes about 1 µs). A record holds its
;;; number, and a table on the GPU maps that to its place.

(define font-page-count (fx+ 1 (fxsrl #x10FFFF 8)))

;;; ------------------------------------------------------------------ faces
;;; FreeType's structs as far as what's read, laid out by Chez by the
;;; platform's C rules: FreeType's positions are C longs, whatever size.

(define-ftype ft-metrics
  (struct [width long] [height long] [left long] [top long] [advance long]
          [vertical-left long] [vertical-top long] [vertical-advance long]))
(define-ftype ft-slot
  (struct [library void*] [face void*] [next void*] [index unsigned]
          [generic (array 2 void*)]
          [metrics ft-metrics]
          [linear-advance long] [linear-vertical long]
          [advance-x long] [advance-y long]
          [format int]
          [bitmap (struct [rows unsigned] [width unsigned] [pitch int]
                          [buffer void*] [grays unsigned-short]
                          [pixel-mode unsigned-8] [palette-mode unsigned-8]
                          [palette void*])]
          [left int] [top int]))
(define-ftype ft-face
  (struct [faces long] [index long] [flags long] [style long] [glyphs long]
          [family void*] [style-name void*]
          [fixed-sizes int] [sizes void*]
          [charmaps-count int] [charmaps void*]
          [generic (array 2 void*)]
          [bbox (array 4 long)]
          [upem unsigned-short] [ascender short] [descender short]
          [height short] [max-width short] [max-height short]
          [underline-position short] [underline-thickness short]
          [glyph (* ft-slot)]))

;; The slot a face's last glyph was loaded into.
(define (ft-face-slot handle)
  (ftype-ref ft-face (glyph) (make-ftype-pointer ft-face handle)))

;;; A face's table: for each character, in font units, its advance and its
;;; ink's left, top (above the baseline), width and height. A page holds 256
;;; characters; -1 is a character the face hasn't.

(define-record-type font-file
  (nongenerative schevana-font-file-1)
  (fields path handle upem ascender descender height fixed? pages notdef
          (mutable size)))     ; the size FreeType is set to, in 1/64 pixels

;; What FreeType and fontconfig take or give through a pointer, one at a
;; time: a place for it, a pointer made once.
(define-ftype ft-scratch
  (union [pointer void*] [int int] [glyph unsigned-32]
         [vector (struct [x long] [y long])]))
(defvar *ft-scratch* (foreign-alloc (ftype-sizeof ft-scratch)))
(define ft-scratch* (make-ftype-pointer ft-scratch *ft-scratch*))
(defvar *ft-library*
  (begin
    (unless (zero? (ft-init-freetype *ft-scratch*))
      (errorf 'font "FreeType wouldn't start"))
    (ftype-ref ft-scratch (pointer) ft-scratch*)))
(defvar *font-files* (make-hashtable string-hash string=?))

(define ft-load-no-scale 1)
(define ft-load-render 4)
(define ft-load-target-light (ash 1 16))
(define ft-load-target-mono (ash 2 16))
(define ft-face-flag-fixed-width 4)

;; Where fontconfig finds this family: (file . index in it).
;; What a Mac asks for by the generic names, which there give a monospace with
;; no λ and a sans-serif taller than the layouts here are made for: DejaVu, as
;; on Linux, or where it isn't installed the nearest the system has.
(define font-generic-families
  (if host-mac?
      '(("sans-serif" . "DejaVu Sans,Lucida Grande")
        ("serif" . "DejaVu Serif,serif")
        ("monospace" . "DejaVu Sans Mono,Menlo"))
      '()))

(define (font-file-match family slant weight)
  (let* ([own (assoc family font-generic-families)]
         [name (format "~a:slant=~a:weight=~a" (if own (cdr own) family)
                       (if (eq? slant 'italic) 100 0)
                       (if (eq? weight 'bold) 200 80))]
         [pattern (fc-name-parse name)]
         [config (fc-config-get-current)])
    (fc-config-substitute config pattern 0)
    (fc-default-substitute pattern)
    (let ([match (fc-font-match config pattern *ft-scratch*)])
      (fc-pattern-destroy pattern)
      (when (eqv? match 0) (errorf 'font "no font for ~a" name))
      (fc-pattern-get-string match "file" 0 *ft-scratch*)
      (let ([file (c-string->string
                   (ftype-ref ft-scratch (pointer) ft-scratch*))])
        (fc-pattern-get-integer match "index" 0 *ft-scratch*)
        (let ([index (ftype-ref ft-scratch (int) ft-scratch*)])
          (fc-pattern-destroy match)
          (cons file index))))))

(define (font-file-open where)
  (let ([key (format "~a#~a" (car where) (cdr where))])
    (or (hashtable-ref *font-files* key #f)
        (begin
          (unless (zero? (ft-new-face *ft-library* (car where) (cdr where)
                                      *ft-scratch*))
            (errorf 'font "FreeType can't read ~a" (car where)))
          (let* ([h (ftype-ref ft-scratch (pointer) ft-scratch*)]
                 [pages (make-vector font-page-count #f)])
            (define face (make-ftype-pointer ft-face h))
            ;; A character's numbers, read from the glyph just loaded.
            (define (metrics! page i)
              (let ([g (ft-face-slot h)] [at (fx* 5 i)])
                (fxvector-set! page at
                               (ftype-ref ft-slot (metrics advance) g))
                (fxvector-set! page (fx+ at 1)
                               (ftype-ref ft-slot (metrics left) g))
                (fxvector-set! page (fx+ at 2)
                               (ftype-ref ft-slot (metrics top) g))
                (fxvector-set! page (fx+ at 3)
                               (ftype-ref ft-slot (metrics width) g))
                (fxvector-set! page (fx+ at 4)
                               (ftype-ref ft-slot (metrics height) g))))
            (ftype-set! ft-scratch (glyph) ft-scratch* 0)
            (let loop ([c (ft-get-first-char h *ft-scratch*)])
              (unless (zero? (ftype-ref ft-scratch (glyph) ft-scratch*))
                (when (zero? (ft-load-char h c ft-load-no-scale))
                  (let* ([n (fxsrl c 8)]
                         [page (or (vector-ref pages n)
                                   (let ([p (make-fxvector (fx* 5 256) -1)])
                                     (vector-set! pages n p)
                                     p))])
                    (metrics! page (fxand c 255))))
                (loop (ft-get-next-char h c *ft-scratch*))))
            ;; what a character the face hasn't draws: its .notdef
            (let ([notdef (make-fxvector 5 0)])
              (when (zero? (ft-load-char h 0 ft-load-no-scale))
                (fxvector-set! notdef 0
                               (ftype-ref ft-slot (metrics advance)
                                          (ft-face-slot h))))
              (let ([ff (make-font-file
                         (car where) h
                         (max 1 (ftype-ref ft-face (upem) face))
                         (ftype-ref ft-face (ascender) face)
                         (ftype-ref ft-face (descender) face)
                         (ftype-ref ft-face (height) face)
                         (logtest (ftype-ref ft-face (flags) face)
                                  ft-face-flag-fixed-width)
                         pages notdef -1)])
                (hashtable-set! *font-files* key ff)
                ff)))))))

;;; ------------------------------------------------------------------ fonts
;;; A font is a setting: the theme's roles ('ui, 'mono, 'title, ...) are
;;; rules, in gfx.ss, that make one with font, and get-font of a role reads
;;; the theme.

(define-record-type (font-type make-font font?)
  (nongenerative schevana-font-4)
  ;; slant italic or normal, weight bold or normal
  (fields (immutable family font-family) (immutable slant font-slant)
          (immutable weight font-weight) (immutable size font-size)
          (mutable file font-file-cache font-file-cache-set!)
          (mutable cache font-cache font-cache-set!)
          (immutable crisp? font-crisp?)     ; not antialiased
          (mutable size256 font-size256 font-size256-set!)
          (mutable pitch font-pitch font-pitch-set!)
          (mutable sized font-sized font-sized-set!)))

(define (make-font* family size . opts)
  (let ([italic? (memq 'italic opts)]
        [bold? (memq 'bold opts)])
    (make-font family (if italic? 'italic 'normal)
               (if bold? 'bold 'normal)
               size #f #f (and (memq 'crisp opts) #t) 0 #f '())))

;; (font family size . opts), opts bold, italic and crisp (not
;; antialiased: Platinum's text): one record for each, so that every theme
;; asking for it shares its metrics and what is laid out in it.
(defvar *font-specs* (make-hashtable equal-hash equal?))
(define (font family size . opts)
  (let ([spec (cons* family size opts)])
    (or (hashtable-ref *font-specs* spec #f)
        (let ([f (apply make-font* family size opts)])
          (hashtable-set! *font-specs* spec f)
          f))))

;; A font, or a theme key whose value is one ('ui, 'mono-bold, ...).
(define (get-font f) (if (font? f) f (theme f)))

;; The face of a font, opened on first use.
(define (font-file-of f)
  (or (font-file-cache f)
      (let ([ff (font-file-open
                 (font-file-match (font-family f) (font-slant f)
                                  (font-weight f)))])
        (font-file-cache-set! f ff)
        (font-size256-set! f (exact (round (* 256 (font-size f)))))
        ;; a fixed-pitch face's columns stay even: a whole logical pixel a
        ;; character, as are a crisp font's
        (when (or (font-file-fixed? ff) (font-crisp? f))
          (font-pitch-set!
           f (and (font-file-fixed? ff)
                  (fx* 256 (exact (round (/ (* (font-units ff #x4D)
                                               (font-size f))
                                            (font-file-upem ff))))))))
        ff)))

;; A character's advance in font units.
(define (font-units ff c)
  (let ([page (vector-ref (font-file-pages ff) (fxsrl c 8))])
    (let ([u (if page (fxvector-ref page (fx* 5 (fxand c 255))) -1)])
      (if (fx< u 0) (fxvector-ref (font-file-notdef ff) 0) u))))

;; A character's advance in 1/256ths of a logical pixel.
(define (font-advance f ff c)
  (or (font-pitch f)
      (let ([a (fxquotient (fx* (font-units ff c) (font-size256 f))
                           (font-file-upem ff))])
        (if (font-crisp? f) (fx* 256 (fxsra (fx+ a 128) 8)) a))))

;; #(ascent descent height char-width), whole logical pixels but for the
;; last.
(define (font-metrics f)
  (let ([f (get-font f)])
    (or (font-cache f)
        (let* ([ff (font-file-of f)]
               [scale (/ (font-size f) (font-file-upem ff))]
               [whole (lambda (v) (exact (round (* v scale))))]
               [m (vector (whole (font-file-ascender ff))
                          (whole (- (font-file-descender ff)))
                          (whole (font-file-height ff))
                          (flceiling (/ (font-advance f ff #x4D) 256.0)))])
          (font-cache-set! f m)
          m))))

(define (font-ascent f) (vector-ref (font-metrics f) 0))
(define (font-descent f) (vector-ref (font-metrics f) 1))
(define (font-line-height f) (vector-ref (font-metrics f) 2))
(define (font-char-width f) (vector-ref (font-metrics f) 3))

;; A font's face, ready to measure.
(define (font-ready f)
  (or (font-file-cache f) (font-file-of f)))

(define text-width
  (case-lambda
    [(str) (text-width str 'ui)]
    [(str font)
     (let* ([f (get-font font)] [ff (font-ready f)] [n (string-length str)])
       (let loop ([i 0] [w 0])
         (if (fx< i n)
             (loop (fx+ i 1)
                   (fx+ w (font-advance f ff (char->integer
                                              (string-ref str i)))))
             ;; whole logical pixels, up: layout's unit, and boxes stay crisp
             (flceiling (fl/ (fixnum->flonum w) 256.0)))))]))

;;; ------------------------------------------------------------------ atlas
;;; One texture of coverage, filled by shelves. Its rows' table holds, for a
;;; glyph's number: u v w h left top, in device pixels.

;; character is for readers: no shader needs it
(define-shader-layout glyph-row glyphs (u v w h left top character))
(defvar *glyph-table* (make-immobile-bytevector (* 4 glyph-row-words 4096) 0))
(defvar *glyph-count* 1)         ; numbers from 1: 0 is a glyph not made yet
(defvar *glyph-table-dirty?* #t)
(defvar *atlas-x* 0)
(defvar *atlas-y* 0)
(defvar *atlas-row* 0)
(defvar *atlas-pieces* '())      ; ((u v w h bytes) ...) on their way up
(defvar *atlas-full?* #f)

;; A place for w × h coverage bytes, on their way to the atlas: (u . v).
(define (atlas-place! w h bytes)
  (when (> (+ *atlas-x* w 1) gpu-atlas-side)
    (set! *atlas-x* 0)
    (set! *atlas-y* (+ *atlas-y* *atlas-row* 1))
    (set! *atlas-row* 0))
  (if (> (+ *atlas-y* h) gpu-atlas-side)
      (begin (set! *atlas-full?* #t) (cons 0 0))
      (let ([u *atlas-x*] [v *atlas-y*])
        (set! *atlas-x* (+ u w 1))
        (set! *atlas-row* (max *atlas-row* h))
        (set! *atlas-pieces* (cons (list u v w h bytes) *atlas-pieces*))
        (cons u v))))

;; The atlas filled up: everything is made again as it's next drawn.
(define (atlas-flush!)
  (set! *atlas-full?* #f)
  (set! *atlas-x* 0)
  (set! *atlas-y* 0)
  (set! *atlas-row* 0)
  (set! *atlas-pieces* '())
  (set! *glyph-count* 1)
  (set! *glyph-table-dirty?* #t)
  (hashtable-clear! *stipple-tiles*)
  (vector-for-each (lambda (f) (font-sized-set! f '()))
                   (hashtable-values *font-specs*)))

(defvar *stipple-tiles* (make-hashtable equal-hash equal?))

(define (glyph-table-grow!)
  (let ([new (make-immobile-bytevector
              (* 2 (bytevector-length *glyph-table*)) 0)])
    (bytevector-copy! *glyph-table* 0 new 0 (bytevector-length *glyph-table*))
    (set! *glyph-table* new)))

(define (glyph-row-set! n u v w h left top char)
  (when (>= (* 4 glyph-row-words (+ n 1)) (bytevector-length *glyph-table*))
    (glyph-table-grow!))
  (let ([at (* glyph-row-words n)] [t *glyph-table*])
    (define (put! field v)
      (bytevector-s32-native-set! t (* 4 (+ at field)) v))
    (put! glyph-row-u u)
    (put! glyph-row-v v)
    (put! glyph-row-w w)
    (put! glyph-row-h h)
    (put! glyph-row-left left)
    (put! glyph-row-top top)
    (put! glyph-row-character char))
  (set! *glyph-table-dirty?* #t))

;; Whether the glyph has this row: for clipping before a record is written.
(define (glyph-row-ref n k)
  (bytevector-s32-native-ref *glyph-table* (* 4 (+ (* glyph-row-words n) k))))

;; The pages of a font at a scale, num/den device pixels a logical pixel:
;; for each character, four glyph numbers by quarter-pixel phase; 0, not made
;; yet; -1, no ink.
(define (font-glyph-pages f num den)
  (let ([key (fx+ (fx* num 65536) den)] [sized (font-sized f)])
    (if (and (pair? sized) (fx= (caar sized) key))
        (cdar sized)
        (let ([found (assv key sized)])
          (if found
              (begin
                (font-sized-set! f (cons found (remq found sized)))
                (cdr found))
              (let ([pages (make-vector font-page-count #f)])
                (font-sized-set! f (cons (cons key pages) sized))
                pages))))))

;; The glyph's number at this phase, made if it must be; -1 if it has no ink.
(define (font-glyph f pages num den c phase)
  (let* ([n (fxsrl c 8)]
         [page (or (vector-ref pages n)
                   (let ([p (make-fxvector (fx* 4 256) 0)])
                     (vector-set! pages n p)
                     p))]
         [at (fx+ (fx* 4 (fxand c 255)) phase)]
         [g (fxvector-ref page at)])
    (if (fx= g 0)
        (let ([g (font-glyph-make f num den c phase)])
          (fxvector-set! page at g)
          g)
        g)))

;; FreeType's glyph, drawn at its phase, into the atlas.
(define (font-glyph-make f num den c phase)
  (let* ([ff (font-ready f)]
         [h (font-file-handle ff)]
         [size (exact (round (* 64 (font-size f) (/ num den))))])
    (unless (= size (font-file-size ff))
      (ft-set-char-size h 0 size 72 72)
      (font-file-size-set! ff size))
    ;; the phase in 1/64ths of a pixel
    (ftype-set! ft-scratch (vector x) ft-scratch* (* 16 phase))
    (ftype-set! ft-scratch (vector y) ft-scratch* 0)
    (ft-set-transform h 0 *ft-scratch*)
    (if (not (zero? (ft-load-char
                     h c (logor ft-load-render
                                (if (font-crisp? f)
                                    ft-load-target-mono
                                    ft-load-target-light)))))
        -1
        (let* ([g (ft-face-slot h)]
               [rows (ftype-ref ft-slot (bitmap rows) g)]
               [width (ftype-ref ft-slot (bitmap width) g)]
               [pitch (ftype-ref ft-slot (bitmap pitch) g)]
               [buffer (ftype-ref ft-slot (bitmap buffer) g)]
               [mode (ftype-ref ft-slot (bitmap pixel-mode) g)]
               [left (ftype-ref ft-slot (left) g)]
               [top (ftype-ref ft-slot (top) g)])
          (if (or (zero? rows) (zero? width))
              -1
              (let ([bytes (make-bytevector (* rows width))])
                (do ([y 0 (+ y 1)]) ((= y rows))
                  (let ([from (+ buffer (* y pitch))] [to (* y width)])
                    (do ([x 0 (+ x 1)]) ((= x width))
                      (bytevector-u8-set!
                       bytes (+ to x)
                       (if (= mode 1)      ; a bit a pixel, for crisp fonts
                           (if (logbit? (- 7 (modulo x 8))
                                        (foreign-ref 'unsigned-8 from
                                                     (quotient x 8)))
                               255
                               0)
                           (foreign-ref 'unsigned-8 from x))))))
                (let ([place (atlas-place! width rows bytes)]
                      [n *glyph-count*])
                  (set! *glyph-count* (+ n 1))
                  (glyph-row-set! n (car place) (cdr place) width rows
                                  left top c)
                  n)))))))
