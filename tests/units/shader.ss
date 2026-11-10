;;; tests/units/shader.ss — the shader language's contract: every operation
;;; gives the same on the device and on the twin (kits/twin.ss), whatever
;;; the driver; what's outside the language is refused at expansion. A paint
;;; colors its box, in its clip, and needs nothing recorded to change.

;; A buffer holding words.
(define (shader-test-buffer words)
  (let ([b (make-gpu-buffer (length words))])
    (for-each (lambda (v i) (gpu-buffer-set! b i v))
              words (iota (length words)))
    b))

;; every operation; one per cell, chosen by the cell's number
(define shader-test-ops
  '((fx+ v w) (fx- v w) (fx* v w) (fxquotient v w) (fxmod v w)
    (fxand v w) (fxior v w) (fxxor v w) (fxsll v w) (fxsrl v w) (fxsra v w)
    (fx- v) (fxnot v)
    (if (fx= v w) 1 0) (if (fx< v w) 1 0) (if (fx>= v w) 1 0)
    (flonum->fixnum (fl* 1000.0 (flsqrt (flabs (fixnum->flonum v)))))
    (flonum->fixnum (flfloor (fl/ (fixnum->flonum v) 3.0)))
    (flonum->fixnum (flceiling (fl/ (fixnum->flonum v) 3.0)))
    (do-bounded 100 ([i 0 (fx+ i 1)] [acc k (fx+ acc i)])
      ((fx>= i (fxand v 15)) acc))))

(define shader-test-body
  (let loop ([ops shader-test-ops] [i 0])
    (if (null? (cdr ops))
        (car ops)
        `(if (fx= x ,i) ,(car ops) ,(loop (cdr ops) (+ i 1))))))

(eval `(define-compute-shader (shader-test-ints x y)
         ([in fx-buffer] [out fx-buffer write] [k fixnum])
         (let ([v (fx-ref in (fx* x 2))] [w (fx-ref in (fx+ 1 (fx* x 2)))])
           (fx-set! out x ,shader-test-body))))

(define shader-test-pairs
  '((7 2) (-7 2) (7 -2) (-7 -2) (7 0) (2147483647 1) (-2147483648 -1)
    (100000 100000) (3 33) (-8 1) (0 0) (1 31)))

(check "every operation gives the same on the device as on the twin, for \
        every pair, division by nothing and overflow among them"
       (let* ([n (length shader-test-ops)]
              [twin (twin-procedure shader-test-ints)]
              [bad '()])
         (for-each
          (lambda (p)
            (let ([in (shader-test-buffer
                       (apply append (make-list n p)))]
                  [out (make-gpu-buffer n)]
                  [expected (make-bytevector (* 4 n) 0)])
              (gpu-compute! shader-test-ints n 1 in out 5)
              (gpu-buffer-read! out)
              (do ([x 0 (+ x 1)]) ((= x n))
                (twin x 0 n 1 (gpu-buffer-bytes in) expected 5)
                (unless (= (gpu-buffer-ref out x)
                           (bytevector-s32-native-ref expected (* 4 x)))
                  (set! bad (cons (list p x (gpu-buffer-ref out x)
                                        (bytevector-s32-native-ref expected
                                                                   (* 4 x)))
                                  bad))))
              (gpu-buffer-release! in)
              (gpu-buffer-release! out)))
          shader-test-pairs)
         (printf "  ~a differ of ~a: ~s\n" (length bad)
                 (* n (length shader-test-pairs)) bad)
         (null? bad)))

(check "what's outside the language is refused where it is defined"
       (for-all
        (lambda (form) (raises? (lambda () (eval form))))
        '((define-compute-shader (shader-test-bad x y) ([in fx-buffer])
            (do-bounded (fx+ 1 1) ([i 0 (fx+ i 1)]) ((fx= i 1) i)))
          (define-compute-shader (shader-test-bad x y) ([in fx-buffer])
            (car in))
          (define-compute-shader (shader-test-bad x y) ([in fx-buffer])
            (fx-ref elsewhere 0))
          (define-compute-shader (shader-test-bad x y) ([in fx-buffer])
            (fx-set! in 0 1)))))

;; The nodes of a tree that head starts, in order.
(define (shader-test-nodes t head)
  (if (pair? t)
      (append (if (eq? (car t) head) (list t) '())
              (apply append (map (lambda (x) (shader-test-nodes x head)) t)))
      '()))

(check "a float constant is 32 bits on the twin, as on the device"
       (let* ([s (eval '(let ()
                          (define-compute-shader (shader-test-tenth x y)
                            ([out fl-buffer write])
                            (fl-set! out x (fl* (fixnum->flonum x) 0.1)))
                          shader-test-tenth))]
              [twin (twin-procedure s)]
              [out (make-bytevector 400 0)])
         (do ([x 0 (+ x 1)]) ((= x 100)) (twin x 0 100 1 out))
         (for-all (lambda (x)
                    (= (bytevector-ieee-single-native-ref out (* 4 x))
                       (flsingle (fl* (fixnum->flonum x) (flsingle 0.1)))))
                  (iota 100))))

;;; What a back end prints.

(define shader-test-odd-names
  '((|a); evil(| fixnum)
    (|b[[x]]| fx-buffer write)))

(define (shader-test-text-has? text piece)
  (let ([n (string-length piece)])
    (let loop ([i 0])
      (and (<= (+ i n) (string-length text))
           (or (string=? (substring text i (+ i n)) piece)
               (loop (+ i 1)))))))

(check "MSL's text holds no name from the source, which could say anything: \
        a parameter's, a buffer's or a coordinate's"
       (let* ([forms '((fx-set! |b[[x]]| |x(| |a); evil(|))]
              [text (shader-msl
                     'compute '(|x(| |y(|) shader-test-odd-names
                     (shader-lower 'compute '(|x(| |y(|)
                                   shader-test-odd-names forms))])
         (not (or (shader-test-text-has? text "evil")
                  (shader-test-text-has? text "[[x]]")
                  (shader-test-text-has? text "x(")))))

(eval `(define-compute-shader (shader-test-odd x y)
         ,shader-test-odd-names
         (fx-set! |b[[x]]| x |a); evil(|)))

(check "a parameter may be called anything, on the device"
       (let ([out (make-gpu-buffer 4)])
         (gpu-compute! shader-test-odd 4 1 7 out)
         (gpu-buffer-read! out)
         (let ([ok (for-all (lambda (i) (= 7 (gpu-buffer-ref out i)))
                            (iota 4))])
           (gpu-buffer-release! out)
           ok)))

;;; A texture at a level.

(define shader-test-texture-params '((tex texture)))

(define (shader-test-fragment forms)
  (shader-lower 'fragment '(x y id) shader-test-texture-params forms))

(define-fragment-shader (shader-test-level x y id)
  ([tex texture])
  (define (at c) (texture-ref tex 3 4 c (fx+ id 1)))
  (emit-color (at 0) (at 1) (at 2) (at 3)))

(check "a texture's read at a level, its channel any constant, on the twin"
       (let ([seen '()])
         ((twin-procedure shader-test-level) 0.5 0.5 1
          (lambda (u v c level)
            (set! seen (cons (list u v c level) seen))
            1.0))
         (for-all (lambda (c) (member (list 3 4 c 2) seen)) '(0 1 2 3))))

(check "at a level in MSL's text too, the first if none is said"
       (let ([text (lambda (forms)
                     (shader-msl 'fragment '(x y id)
                                 shader-test-texture-params
                                 (shader-test-fragment forms)))]
             [color (lambda (t) `((emit-color ,t 0.0 0.0 1.0)))])
         (and (shader-test-text-has?
               (text (color '(texture-ref tex 3 4 0 (fx+ id 1))))
               ")), uint(v")
              (shader-test-text-has?
               (text (color '(texture-ref tex 3 4 0)))
               ")), uint(int(0u)))"))))

;;; cond, case, when and unless: only ways to write if.

(define (shader-test-color t)
  (shader-test-fragment `((emit-color ,t 0.0 0.0 1.0))))

(define (shader-test-same-tree? a b)
  (equal? (shader-test-color a) (shader-test-color b)))

(check "cond and case are the ifs they stand for, to the tree"
       (and (shader-test-same-tree?
             '(cond [(fx= id 0) 1.0] [(fx= id 1) 2.0] [else 3.0])
             '(if (fx= id 0) 1.0 (if (fx= id 1) 2.0 3.0)))
            (shader-test-same-tree?
             '(case id [(0) 1.0] [(1 2) 2.0] [else 3.0])
             '(if (fx= id 0) 1.0 (if (or (fx= id 1) (fx= id 2)) 2.0 3.0)))))

(check "case reads what it's given once"
       (= 1 (let count ([t (shader-test-color
                            '(case (fx+ id 1) [(0) 1.0] [(1) 2.0] [else 3.0]))])
              (cond [(pair? t) (+ (count (car t)) (count (cdr t)))]
                    [(eq? t 'fx+) 1]
                    [else 0]))))

(check "what isn't one is refused: a case's data, else, a clause with no body, \
        a value with no else"
       (for-all
        (lambda (t) (raises? (lambda () (shader-test-color t))))
        '((case id [(a) 1.0] [else 2.0])
          (case id [() 1.0] [else 2.0])
          (cond [else 1.0] [(fx= id 0) 2.0])
          (cond [(fx= id 0)] [else 1.0])
          (cond [(fx= id 0) 1.0]))))

(check "a test known when it's compiled leaves only its arm, and the other is \
        still checked"
       (and (shader-test-same-tree? '(let ([on? #f]) (if on? 1.0 2.0)) 2.0)
            (shader-test-same-tree? '(if (and #f (fx= id 0)) 1.0 2.0) 2.0)
            (shader-test-same-tree? '(if (or #t (fx= id 0)) 1.0 2.0) 1.0)
            (raises? (lambda () (shader-test-color '(if #f (car id) 1.0))))))

(define-compute-shader (shader-test-branches x y)
  ([out fx-buffer write])
  (when (fx= x 0) (fx-set! out x 10))
  (unless (fx= x 0)
    (fx-set! out x (case x
                     [(1) 20]
                     [(2 3) 30]
                     [else (cond [(fx= x 4) 40]
                                 [(fx> x 5) 60]
                                 [else 50])]))))

(check "they give the same on the device as on the twin"
       (let* ([expected '(10 20 30 30 40 50 60 60)]
              [n (length expected)]
              [out (make-gpu-buffer n)]
              [mine (make-bytevector (* 4 n) 0)]
              [twin (twin-procedure shader-test-branches)])
         (gpu-compute! shader-test-branches n 1 out)
         (gpu-buffer-read! out)
         (do ([x 0 (+ x 1)]) ((= x n)) (twin x 0 n 1 mine))
         (let ([device (map (lambda (i) (gpu-buffer-ref out i)) (iota n))]
               [other (map (lambda (i)
                             (bytevector-s32-native-ref mine (* 4 i)))
                           (iota n))])
           (gpu-buffer-release! out)
           (and (equal? device expected) (equal? other expected)))))

(check "and MSL's text comes of them, empty arms and all"
       (let ([params '((out fx-buffer write))] [coords '(x y)])
         (shader-test-text-has?
          (shader-msl 'compute coords params
                      (shader-lower 'compute coords params
                                    '((when (fx= x 0) (fx-set! out x 1))
                                      (unless (fx= x 0) (fx-set! out x 2)))))
          "if (")))

;;; What shaders share: constants and helpers, gone by the tree too.

(define-shader-constant shader-test-seven 7)

(define-shader-helpers shader-test-helpers
  (define (shader-test-more n) (fx+ n shader-test-seven))
  ;; id is the shader's, and k whatever's in scope where it's taken
  (define (shader-test-scoped) (fx+ id k)))

(define (shader-test-forms . forms)
  (shader-test-fragment forms))

(define shader-test-emit '(emit-color (fixnum->flonum (shader-test-more id))
                                      0.0 0.0 1.0))

(check "a constant is its number to a shader, and to Scheme"
       (and (= shader-test-seven 7)
            (shader-test-same-tree? '(fixnum->flonum shader-test-seven)
                                    '(fixnum->flonum 7))
            (shader-test-same-tree?
             '(case id [(shader-test-seven) 1.0] [else 2.0])
             '(if (fx= id 7) 1.0 2.0))))

(check "a name in scope comes before a constant's, and a name that's neither \
        is refused"
       (and (shader-test-same-tree?
             '(let ([shader-test-seven 2]) (fixnum->flonum shader-test-seven))
             '(fixnum->flonum 2))
            (raises? (lambda () (shader-test-color '(fixnum->flonum no-such))))
            (raises? (lambda ()
                       (shader-test-color
                        '(case id [(no-such) 1.0] [else 2.0]))))))

(check "helpers are the local functions they stand for, to the tree, and what \
        isn't called costs nothing"
       (and (equal? (shader-test-forms '(use-shader-helpers shader-test-helpers)
                                       shader-test-emit)
                    (shader-test-forms
                     '(define (shader-test-more n)
                        (fx+ n shader-test-seven))
                     shader-test-emit))
            (equal? (shader-test-forms '(use-shader-helpers shader-test-helpers)
                                       '(emit-color 1.0 0.0 0.0 1.0))
                    (shader-test-forms '(emit-color 1.0 0.0 0.0 1.0)))))

(check "helpers see what's in scope where they're taken, and a set that isn't \
        there is refused"
       (and (equal? (shader-test-forms
                     '(let ([k 5])
                        (use-shader-helpers shader-test-helpers)
                        (emit-color (fixnum->flonum (shader-test-scoped))
                                    0.0 0.0 1.0)))
                    (shader-test-forms
                     '(emit-color (fixnum->flonum (fx+ id 5)) 0.0 0.0 1.0)))
            (raises? (lambda ()
                       (shader-test-forms '(use-shader-helpers no-such)
                                          '(emit-color 1.0 0.0 0.0 1.0))))))

(define-compute-shader (shader-test-shared x y)
  ([out fx-buffer write])
  (use-shader-helpers shader-test-helpers)
  (fx-set! out x (shader-test-more x)))

(check "they give the same on the device as on the twin"
       (let* ([n 4]
              [out (make-gpu-buffer n)]
              [mine (make-bytevector (* 4 n) 0)]
              [twin (twin-procedure shader-test-shared)]
              [expected '(7 8 9 10)])
         (gpu-compute! shader-test-shared n 1 out)
         (gpu-buffer-read! out)
         (do ([x 0 (+ x 1)]) ((= x n)) (twin x 0 n 1 mine))
         (let ([device (map (lambda (i) (gpu-buffer-ref out i)) (iota n))]
               [other (map (lambda (i)
                             (bytevector-s32-native-ref mine (* 4 i)))
                           (iota n))])
           (gpu-buffer-release! out)
           (and (equal? device expected) (equal? other expected)))))

(check "the inspect kit reads what's shared: the kinds shaders name, and the \
        world's helpers"
       (and (eqv? (cdr (assq 'rec-kind-glyph (inspect-shader-constants)))
                  rec-kind-glyph)
            (eqv? (cdr (assq 'rec-paint-image (inspect-shader-constants)))
                  rec-paint-image)
            (let ([helpers (assq 'gfx-helpers (inspect-shader-helpers))])
              (and helpers
                   (for-all (lambda (f) (memq f (cdr helpers)))
                            '(word extra pixels clamp01 mixed channel
                              box-distance clip-coverage))))))

;;; Layouts: names for a row's words.

(define-shader-layout shader-test-row in (a b c))
(define-shader-layout shader-test-through shader-test-read (a b))

(define shader-test-layout-params '((in fx-buffer) (out fx-buffer write)))

(define (shader-test-layout-tree . forms)
  (shader-lower 'compute '(x y) shader-test-layout-params forms))

(define (shader-test-same-read? a b)
  (equal? (shader-test-layout-tree `(fx-set! out x ,a))
          (shader-test-layout-tree `(fx-set! out x ,b))))

(check "a field is its offset to Scheme and to a shader, and a layout says how \
        long a row is"
       (and (= shader-test-row-words 3)
            (= shader-test-row-c 2)
            (shader-test-same-read? 'shader-test-row-c 2)))

(check "a field reads the word it names: at a row, or at its offset with none"
       (and (shader-test-same-read? '(shader-test-row-a x) '(fx-ref in x))
            (shader-test-same-read? '(shader-test-row-b x)
                                    '(fx-ref in (fx+ x 1)))
            (shader-test-same-read? '(shader-test-row-b) '(fx-ref in 1))))

(check "its reader may be a function in scope"
       (let ([read '(define (shader-test-read k) (fx-ref in (fx* k 2)))])
         (equal? (shader-test-layout-tree
                  read '(fx-set! out x (shader-test-through-b x)))
                 (shader-test-layout-tree
                  read '(fx-set! out x (shader-test-read (fx+ x 1)))))))

(check "a reader that isn't in scope is refused, and more than one row"
       (and (raises? (lambda ()
                       (shader-test-layout-tree
                        '(fx-set! out x (shader-test-through-a x)))))
            (raises? (lambda ()
                       (shader-test-layout-tree
                        '(fx-set! out x (shader-test-row-a x x)))))))

(define-compute-shader (shader-test-layout x y)
  ([in fx-buffer] [out fx-buffer write])
  (let ([row (fx* x shader-test-row-words)])
    (fx-set! out x (fx+ (shader-test-row-a row) (shader-test-row-c row)))))

(check "and it reads the same on the device as on the twin"
       (let* ([n 2]
              [in (shader-test-buffer '(1 100 2 3 100 4))]
              [out (make-gpu-buffer n)]
              [mine (make-bytevector (* 4 n) 0)]
              [twin (twin-procedure shader-test-layout)])
         (gpu-compute! shader-test-layout n 1 in out)
         (gpu-buffer-read! out)
         (do ([x 0 (+ x 1)]) ((= x n))
           (twin x 0 n 1 (gpu-buffer-bytes in) mine))
         (let ([device (map (lambda (i) (gpu-buffer-ref out i)) (iota n))]
               [other (map (lambda (i)
                             (bytevector-s32-native-ref mine (* 4 i)))
                           (iota n))])
           (gpu-buffer-release! in)
           (gpu-buffer-release! out)
           (and (equal? device '(3 7)) (equal? other '(3 7))))))

;; What each writer really writes, read back by its layout's names: writers
;; append their words in order, so only this ties the two together.
(define shader-test-written
  (let ([target (gpu-image-make-target 16 16)]
        [word32 (lambda (row k) (logand (rec-extra-ref row k) #xffffffff))]
        [found '()])
    (let ([img
           (image
            20 20 1
            (lambda ()
              (let* ([note! (lambda (name . values)
                              (set! found (cons (cons name values) found)))]
                     [at (lambda () (rec-extra-at))]
                     [red (color-word #xff0000)]
                     [green (color-word #x00ff00)])
                (let* ([row (rec-gradient
                             (linear-gradient 1 2 3 4 #xff0000 #x00ff00))]
                       [end (at)])
                  (note! 'linear
                         (rec-extra-ref row gradient-row-kind)
                         (rec-extra-ref row gradient-row-x0)
                         (rec-extra-ref row gradient-row-y1)
                         (rec-extra-ref row gradient-row-stops)
                         (= (word32 row gradient-row-color0) red)
                         (= (word32 row gradient-row-color1) green)
                         (- end row)))
                (let ([row (rec-gradient
                            (radial-gradient 1 2 3 #xff0000 #x00ff00))])
                  (note! 'radial
                         (= (rec-extra-ref row gradient-row-kind)
                            rec-gradient-radial)
                         (rec-extra-ref row gradient-row-x1)))
                (let* ([row (rec-stipple
                             (stipple #xff0000 #x00ff00 "#." ".#"))]
                       [end (at)])
                  (note! 'stipple
                         (rec-extra-ref row stipple-row-w)
                         (rec-extra-ref row stipple-row-h)
                         (= (word32 row stipple-row-ink) red)
                         (= (word32 row stipple-row-paper) green)
                         (- end row)))
                (let* ([row (at)])
                  (draw-image target 0 0 8 8)
                  (note! 'image
                         (rec-extra-ref row image-row-w)
                         (rec-extra-ref row image-row-h)
                         (rec-extra-ref row image-row-level)
                         (- (at) row)))
                (let ([outer *rec-clip*] [start (at)])
                  (with-clip (1 2 3 4 1)
                    (let ([row *rec-clip*])
                      (note! 'clip
                             (rec-extra-ref row clip-row-x0)
                             (rec-extra-ref row clip-row-y1)
                             (> (rec-extra-ref row clip-row-radius) 0)
                             (= (rec-extra-ref row clip-row-parent) outer)
                             (rec-extra-ref row clip-row-rx0)
                             (rec-extra-ref row clip-row-ry1)
                             (- (at) start)))))
                (let* ([word (lambda (k)
                               (bytevector-s32-native-ref
                                (gpu-recording-recs *rec-now*)
                                (+ (- (gpu-recording-recs-n *rec-now*)
                                      (* 4 rec-row-words))
                                   (* 4 k))))]
                       [kind (lambda () (fxand (word rec-row-head) 15))])
                  (fill-box 1 2 3 4 #xff0000)
                  (note! 'record
                         (= (kind) rec-kind-box)
                         (= (logand (word rec-row-paint) #xffffffff) red)
                         (word rec-row-x0)
                         (word rec-row-y1))
                  (stroke-box 1 2 6 6 #xff0000 1 2)
                  (note! 'box
                         (= (kind) rec-kind-box)
                         (= (word rec-box-radius) (rec-radius 2 6 6))
                         (= (word rec-box-line) (rec-line-width 1)))
                  (draw-line 1 2 5 6 #xff0000 2)
                  (note! 'segment
                         (= (kind) rec-kind-segment)
                         (= (word rec-segment-width) (rec-length 2)))
                  (rec-shadow! 1 2 6 6 1 3 #xff0000)
                  (note! 'shadow
                         (= (kind) rec-kind-shadow)
                         (= (word rec-shadow-radius) (rec-radius 1 6 6))
                         (= (word rec-shadow-size) (rec-length 3)))
                  (fill-polygon '((1 . 1) (5 . 1) (3 . 5)) #xff0000)
                  (note! 'polygon
                         (= (kind) rec-kind-polygon)
                         (word rec-polygon-count)
                         (rec-extra-ref (word rec-polygon-points) 0))))))])
      (picture-free! img)
      (gpu-image-release! target)
      found)))

(define (shader-test-wrote name)
  (cdr (assq name shader-test-written)))

(check "a gradient's row is where its layout says"
       (and (equal? (shader-test-wrote 'linear)
                    (list 0 256 1024 2 #t #t (+ gradient-row-color0 2)))
            (equal? (shader-test-wrote 'radial) (list #t 768))))

(check "and a stipple's"
       (equal? (shader-test-wrote 'stipple)
               (list 2 2 #t #t stipple-row-words)))

(check "and an image's"
       (equal? (shader-test-wrote 'image) (list 16 16 1 image-row-words)))

(check "and a clip's"
       (equal? (shader-test-wrote 'clip)
               (list 256 1536 #t #t 256 1536 clip-row-words)))

(check "and a record's, whatever its kind"
       (and (equal? (shader-test-wrote 'record) (list #t #t 256 1536))
            (equal? (shader-test-wrote 'box) (list #t #t #t))
            (equal? (shader-test-wrote 'segment) (list #t #t))
            (equal? (shader-test-wrote 'shadow) (list #t #t #t))
            (equal? (shader-test-wrote 'polygon) (list #t 3 256))))

(check "and a glyph's, in its table"
       (let ([n *glyph-count*])
         (glyph-row-set! n 1 2 3 4 5 6 65)
         (equal? (map (lambda (k) (glyph-row-ref n k))
                      (list glyph-row-u glyph-row-v glyph-row-w glyph-row-h
                            glyph-row-left glyph-row-top glyph-row-character))
                 '(1 2 3 4 5 6 65))))

(check "the inspect kit reads a layout's fields"
       (and (equal? (cdr (assq 'clip-row-parent (inspect-shader-fields)))
                    (cons 'extra clip-row-parent))
            (equal? (cdr (assq 'glyph-row-left (inspect-shader-fields)))
                    (cons 'glyphs glyph-row-left))))

(check "a channel is a constant, 0 to 3"
       (let ([color (lambda (t) `((emit-color ,t 0.0 0.0 1.0)))])
         (and (raises? (lambda ()
                         (shader-test-fragment
                          (color '(texture-ref tex 0 0 4)))))
              (raises? (lambda ()
                         (shader-test-fragment
                          (color '(texture-ref tex 0 0 id))))))))

;; Metal's fast math would take (a + b) - a for b, and contract a product and
;; a sum. Other drivers may do as they like: the language promises its
;; floats no more than this, and Metal alone has a switch for it.
(when (eq? shader-target 'msl)
  (let* ([ops '((fl+ a b) (fl- a b) (fl* a b) (fl/ a b) (fl+ (fl* a b) c)
                (fl- (fl+ a b) a) (flfloor a) (flceiling a) (flround a)
                (flmin a b) (flmax a b) (flabs a) (fl- a) (fl* a 0.1))]
         [count (length ops)]
         [cells (* 200 count)]
         [body (let loop ([ops ops] [i 0])
                 (if (null? (cdr ops))
                     (car ops)
                     `(if (fx= k ,i)
                          ,(car ops)
                          ,(loop (cdr ops) (+ i 1)))))]
         [s (eval `(let ()
                     (define-compute-shader (shader-test-floats x y)
                       ([in fl-buffer] [out fl-buffer write])
                       (let* ([k (fxmod x ,count)]
                              [a (fl-ref in (fx* x 3))]
                              [b (fl-ref in (fx+ 1 (fx* x 3)))]
                              [c (fl-ref in (fx+ 2 (fx* x 3)))])
                         (fl-set! out x ,body)))
                     shader-test-floats))]
         [in (make-gpu-buffer (* 3 cells))]
         [out (make-gpu-buffer cells)]
         [expected (make-bytevector (* 4 cells) 0)])
    (random-seed 12345)
    (do ([i 0 (+ i 1)]) ((= i (* 3 cells)))
      (gpu-buffer-set! in i
                       (flsingle (* (- (random 2000.0) 1000.0)
                                    (if (even? i) 1.0 0.001)))))
    (gpu-compute! s cells 1 in out)
    (gpu-buffer-read! out)
    (do ([x 0 (+ x 1)]) ((= x cells))
      ((twin-procedure s) x 0 cells 1 (gpu-buffer-bytes in) expected))
    (check "on Metal, floats add, multiply and divide exactly as the twin \
            does, a product and a sum, (a + b) - a and a constant among them"
           (bytevector=? (gpu-buffer-bytes out) expected))
    (gpu-buffer-release! in)
    (gpu-buffer-release! out)))

;; Out of a buffer, either end: a read reads its last word and a write is left
;; out, on any device, so that a shader an app hands the GPU reaches nothing
;; else.
(let* ([s (eval '(let ()
                   (define-compute-shader (shader-test-outside x y)
                     ([in fx-buffer] [out fx-buffer write])
                     (fx-set! out x (fx-ref in (fx- x 4)))
                     (fx-set! out (fx+ x 16) 99)
                     (fx-set! out (fx- x 20) 77))
                   shader-test-outside))]
       [in (make-gpu-buffer 8)]
       [out (make-gpu-buffer 16)]
       [expected (make-bytevector 64 0)])
  (do ([i 0 (+ i 1)]) ((= i 8)) (gpu-buffer-set! in i (* 11 (+ i 1))))
  (gpu-compute! s 16 1 in out)
  (gpu-buffer-read! out)
  (do ([x 0 (+ x 1)]) ((= x 16))
    ((twin-procedure s) x 0 16 1 (gpu-buffer-bytes in) expected))
  (check (format "a read outside a buffer reads its last word and a write \
                  outside it is left out, on the device as on the twin: ~s"
                 (map (lambda (i) (gpu-buffer-ref out i)) (iota 16)))
         (and (bytevector=? (gpu-buffer-bytes out) expected)
              (equal? (map (lambda (i) (gpu-buffer-ref out i)) (iota 16))
                      '(88 88 88 88 11 22 33 44 55 66 77 88 88 88 88 88))))
  (gpu-buffer-release! in)
  (gpu-buffer-release! out))

;; With the frame: what a compute run writes, a paint drawn after shows.
(check "a compute asked for with the next frame runs ahead of its drawing, so \
        that a paint shows what it wrote; the runs wait in order, and a buffer \
        let go takes those that name it"
       (let* ([fill (eval '(let ()
                             (define-compute-shader (shader-test-fill x y)
                               ([out fx-buffer write] [v fixnum])
                               (fx-set! out x v))
                             shader-test-fill))]
              [show (eval '(let ()
                             (define-paint (shader-test-show x y)
                               ([in fx-buffer])
                               (fx-ref in x))
                             shader-test-show))]
              [b (make-gpu-buffer 4)]
              [gone (make-gpu-buffer 4)])
         (gpu-compute-soon! fill 4 1 b #xff00ff00)
         (gpu-compute-soon! fill 4 1 gone 7)
         (let ([waiting (inspect-computes)])
           (gpu-buffer-release! gone)
           (let* ([left (inspect-computes)]
                  [p (image 4 1 1 (lambda () (fill-shader 0 0 4 1 show b)))]
                  [after (inspect-computes)])
             (gpu-buffer-release! b)
             (printf "  ~s ~s ~s\n" waiting left after)
             (and (equal? waiting '((shader-test-fill 4 1)
                                    (shader-test-fill 4 1)))
                  (equal? left '((shader-test-fill 4 1)))
                  (null? after)
                  (for-all (lambda (x) (= (pixel-at p x 0) #xff00ff00))
                           (iota 4)))))))

;; What a device can't show: a read outside a buffer may well give what's
;; there by chance, and a write outside lands where nothing reads it back. So
;; the tree: each read's index is held to the last word, and each write is
;; under a compare.
(check "every read of a buffer is at an index held to its last word, and \
        every write is under a compare: the world's shaders and an app's"
       (let ([writer (eval '(let ()
                              (define-compute-shader (shader-test-writer x y)
                                ([in fl-buffer] [out fl-buffer write])
                                (fl-set! out (fx* x 2) (fl-ref in x))
                                (fl-set! out (fx+ (fx* x 2) 1) 1.0))
                              shader-test-writer))])
         (for-all
          (lambda (s)
            (let ([tree (shader-tree s)])
              (and (for-all (lambda (t)
                              (let ([i (cadddr t)])
                                (and (eq? (car i) 'op)
                                     (eq? (caddr i) 'fxumin)
                                     (equal? (car (cddddr i))
                                             `(op fixnum fx-
                                                  (var fixnum
                                                       ,(shader-words
                                                         (caddr t)))
                                                  (const fixnum 1))))))
                            (shader-test-nodes tree 'load))
                   (= (length (shader-test-nodes tree 'store))
                      (length (filter (lambda (t)
                                        (and (eq? (cadr t) 'void)
                                             (eq? (car (caddr t)) 'op)
                                             (eq? (car (cadddr t)) 'store)))
                                      (shader-test-nodes tree 'if)))))))
          (list gfx-vertex gfx-fragment gfx-full-fragment writer))))

;;; The world's shaders.

;; How many nodes a tree has.
(define (shader-test-size t)
  (if (pair? t) (fold-left + 1 (map shader-test-size t)) 0))

(check "each variant of the fragment shader has the code of what it draws and \
        none of the rest's: lines, gradients, stipples and images by a node \
        only theirs has, shadows by the size they add"
       (let* ([variant (lambda (i)
                         (top-level-value (vector-ref gfx-fragments i)))]
              [has? (lambda (i head test)
                      (exists test (shader-test-nodes
                                    (shader-tree (variant i)) head)))]
              [features
               (lambda (i)
                 (list (has? i 'loop (lambda (t) #t))      ; a polygon's edges
                       (has? i 'const                      ; a gradient's dither
                             (lambda (t) (eqv? (caddr t) 52.9829189)))
                       (has? i 'op                         ; a stipple's tile
                             (lambda (t) (eq? (caddr t) 'fxrem)))
                       (has? i 'fetch (lambda (t) (eq? (cadr t) 'image)))))]
              [size (lambda (i) (shader-test-size (shader-tree (variant i))))])
         (printf "  ~s\n" (map size (iota 7)))
         (and (equal? (map features (iota 7))
                      '((#f #f #f #f)     ; boxes and glyphs, solid
                        (#t #f #f #f)     ; and lines
                        (#f #f #f #f)     ; and shadows
                        (#f #t #f #f)     ; and gradients
                        (#f #f #t #f)     ; and stipples
                        (#f #f #f #t)     ; and an image
                        (#t #t #t #f)))   ; all but images
              (for-all (lambda (i) (< (size 0) (size i))) '(1 2 3 4 5 6))
              (for-all (lambda (i) (< (size i) (size 6))) '(1 2 3 4)))))

(check "every byte of a color comes out as itself, and as its alpha takes it \
        over black"
       (let ([img (image 256 2 1
                         (lambda ()
                           (fill-box 0 0 256 2 #x000000)
                           (do ([k 0 (+ k 1)]) ((= k 256))
                             (fill-box k 0 1 1
                                       (rgb k (- 255 k) (mod (* 37 k) 256)))
                             (fill-box k 1 1 1
                                       (alpha (rgb 255 200 k) (/ k 255))))))]
             [word (lambda (r g b) (+ #xff000000 (* r 65536) (* g 256) b))]
             [scaled (lambda (c k) (round (/ (* c k) 255)))])
         (for-all (lambda (k)
                    (and (= (pixel-at img k 0)
                            (word k (- 255 k) (mod (* 37 k) 256)))
                         (= (pixel-at img k 1)
                            (word k (scaled 200 k) (scaled k k)))))
                  (iota 256))))

;;; Paints.

(define-paint (shader-test-half x y)
  ([colors fx-buffer]
   [split fixnum]
   [right color])
  (if (fx< x split) (fx-ref colors 0) right))

;; A shader keeps its source, to be compiled for whatever device is there.
(check "a paint's record compiles again to the code it holds, and its tree \
        names the coordinates the paint's source was lowered with"
       (let ([s (gfx-paint-shader shader-test-half)])
         (and (equal? (shader-coords s) '(px py id))
              (pair? (shader-tree s))
              (equal? (shader-code s)
                      (car (shader-compile 'fragment (shader-coords s)
                                           (shader-params s)
                                           (shader-source s)))))))

;; With no definitions of its own: the world's helpers are every paint's.
(define-paint (shader-test-helped x y)
  ()
  (if (fl> (mixed 0.0 (clamp01 4.0) (fl/ (fixnum->flonum x) 10.0)) 0.45)
      #xff00ff00
      #xffff0000))

(check "a paint has the world's helpers without asking"
       (let* ([img (image 10 2 1
                          (lambda ()
                            (fill-shader 0 0 10 2 shader-test-helped)))]
              [ok (and (= (pixel-at img 4 0) #xffff0000)
                       (= (pixel-at img 5 0) #xff00ff00))])
         (picture-free! img)
         ok))

(check "a paint colors its box, by its arguments and a buffer"
       (let* ([colors (shader-test-buffer (list #xff102030))]
              [img (image 20 10 1
                          (lambda ()
                            (fill-box 0 0 20 10 #x000000)
                            (fill-shader 2 2 10 6 shader-test-half
                                         colors 4 #x405060)))])
         (let ([ok (and (= (pixel-at img 1 3) #xff000000)
                        (= (pixel-at img 2 3) #xff102030)
                        (= (pixel-at img 5 3) #xff102030)
                        (= (pixel-at img 6 3) #xff405060)
                        (= (pixel-at img 11 3) #xff405060)
                        (= (pixel-at img 12 3) #xff000000)
                        (= (pixel-at img 6 1) #xff000000))])
           (gpu-buffer-release! colors)
           ok)))

(check "a paint obeys a clip, and a buffer's new word shows with nothing \
        else done"
       (let* ([colors (shader-test-buffer (list #xff102030))]
              [draw (lambda ()
                      (image 20 10 1
                             (lambda ()
                               (fill-box 0 0 20 10 #x000000)
                               (with-clip (0 0 5 10)
                                 (fill-shader 0 0 20 10 shader-test-half
                                              colors 20 #x405060)))))]
              [first (draw)])
         (gpu-buffer-set! colors 0 #xff708090)
         (let* ([second (draw)]
                [ok (and (= (pixel-at first 4 3) #xff102030)
                         (= (pixel-at first 5 3) #xff000000)
                         (= (pixel-at second 4 3) #xff708090))])
           (gpu-buffer-release! colors)
           ok)))

(check "a paint stays inside the rounded clip a square one lies in"
       (let* ([colors (shader-test-buffer (list #xff102030))]
              [img (image 20 20 1
                          (lambda ()
                            (fill-box 0 0 20 20 #x000000)
                            (with-clip (0 0 20 20 8)
                              (with-clip (0 0 20 20)
                                (fill-shader 0 0 20 20 shader-test-half
                                             colors 20 #x405060)))))]
              [ok (and (= (pixel-at img 0 0) #xff000000)
                       (= (pixel-at img 4 10) #xff102030))])
         (gpu-buffer-release! colors)
         ok))

(check "drawing goes on as ever after a paint, in order"
       (let* ([colors (shader-test-buffer (list #xff102030))]
              [img (image 10 10 1
                          (lambda ()
                            (fill-box 0 0 10 10 #x000000)
                            (fill-shader 0 0 10 10 shader-test-half
                                         colors 10 0)
                            (fill-box 2 2 2 2 #xff0000)
                            (draw-text 0 0 "." 'text 'ui)))])
         (gpu-buffer-release! colors)
         (and (= (pixel-at img 3 3) #xffff0000)
              (= (pixel-at img 8 8) #xff102030))))

;; A compute run asked for soon goes with the frame its turn makes, or, with
;; none, on its own at the turn's end: one stepped on a timer, its window
;; unseen, isn't kept waiting for a frame.
(define-compute-shader (shader-test-mark x y)
  ([out fx-buffer write] [k fixnum])
  (fx-set! out x k))

(check "a compute run no frame takes goes at its turn's end, on its own"
       (let ([out (make-gpu-buffer 8)] [frames *frames-drawn*])
         ;; no timer's frame (the status clock's) to take it
         (fluid-let ([*dirty* #f] [*timers* '()])
           (gpu-compute-soon! shader-test-mark 8 1 out 41)
           (schevana-step! 0))
         (let ([sent (null? *gpu-computes*)])
           (gpu-buffer-read! out)
           (let ([ok (and sent (= *frames-drawn* frames)
                          (for-all (lambda (i) (= 41 (gpu-buffer-ref out i)))
                                   (iota 8)))])
             (gpu-buffer-release! out)
             ok))))
