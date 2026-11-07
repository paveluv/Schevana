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

(eval `(define-shader (shader-test-ints x y)
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
        '((define-shader (shader-test-bad x y) ([in fx-buffer])
            (do-bounded (fx+ 1 1) ([i 0 (fx+ i 1)]) ((fx= i 1) i)))
          (define-shader (shader-test-bad x y) ([in fx-buffer])
            (car in))
          (define-shader (shader-test-bad x y) ([in fx-buffer])
            (fx-ref elsewhere 0))
          (define-shader (shader-test-bad x y) ([in fx-buffer])
            (fx-set! in 0 1)))))

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

(eval `(define-shader (shader-test-odd x y)
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

;; Metal's fast math would take (a + b) - a for b, and contract a product and
;; a sum. Other drivers may do as they like: the language promises its
;; floats no more than this, and Metal alone has a switch for it.
(when (eq? shader-target 'msl)
  (let* ([ops '((fl+ a b) (fl- a b) (fl* a b) (fl/ a b) (fl+ (fl* a b) c)
                (fl- (fl+ a b) a) (flfloor a) (flceiling a) (flround a)
                (flmin a b) (flmax a b) (flabs a) (fl- a))]
         [count (length ops)]
         [cells (* 200 count)]
         [body (let loop ([ops ops] [i 0])
                 (if (null? (cdr ops))
                     (car ops)
                     `(if (fx= k ,i)
                          ,(car ops)
                          ,(loop (cdr ops) (+ i 1)))))]
         [s (eval `(let ()
                     (define-shader (shader-test-floats x y)
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
            does, a product and a sum and (a + b) - a among them"
           (bytevector=? (gpu-buffer-bytes out) expected))
    (gpu-buffer-release! in)
    (gpu-buffer-release! out)))

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
