;;; kits/png.ss — PNG files, written with no library: nothing reads them, so
;;; this needs only stored blocks and two checksums.

(define png-crc-table
  (let ([t (make-vector 256 0)])
    (do ([n 0 (+ n 1)]) ((= n 256) t)
      (vector-set!
       t n
       (let loop ([c n] [k 0])
         (if (= k 8)
             c
             (loop (if (logtest c 1)
                       (logxor #xedb88320 (ash c -1))
                       (ash c -1))
                   (+ k 1))))))))

(define (png-crc bv start end)
  (let loop ([i start] [c #xffffffff])
    (if (= i end)
        (logxor c #xffffffff)
        (loop (+ i 1)
              (logxor (vector-ref png-crc-table
                                  (logand (logxor c (bytevector-u8-ref bv i))
                                          255))
                      (ash c -8))))))

(define (png-adler bv)
  (let loop ([i 0] [a 1] [b 0])
    (if (= i (bytevector-length bv))
        (+ (* b 65536) a)
        (let ([a (modulo (+ a (bytevector-u8-ref bv i)) 65521)])
          (loop (+ i 1) a (modulo (+ b a) 65521))))))

(define (png-u32 v)
  (let ([bv (make-bytevector 4)])
    (bytevector-u32-set! bv 0 v (endianness big))
    bv))

(define (png-chunk port type data)
  (let* ([n (bytevector-length data)]
         [all (make-bytevector (+ 4 n))])
    (bytevector-copy! (string->utf8 type) 0 all 0 4)
    (bytevector-copy! data 0 all 4 n)
    (put-bytevector port (png-u32 n))
    (put-bytevector port all)
    (put-bytevector port (png-u32 (png-crc all 0 (+ 4 n))))))

;; The zlib stream of raw, in stored blocks.
(define (png-zlib raw)
  (let* ([n (bytevector-length raw)]
         [blocks (max 1 (ceiling (/ n 65535)))]
         [out (make-bytevector (+ 2 (* 5 blocks) n 4))])
    (bytevector-u8-set! out 0 #x78)
    (bytevector-u8-set! out 1 1)
    (let loop ([from 0] [to 2])
      (let* ([size (min 65535 (- n from))]
             [last? (= (+ from size) n)])
        (bytevector-u8-set! out to (if last? 1 0))
        (bytevector-u16-set! out (+ to 1) size (endianness little))
        (bytevector-u16-set! out (+ to 3) (logxor size #xffff)
                             (endianness little))
        (bytevector-copy! raw from out (+ to 5) size)
        (if last?
            (bytevector-u32-set! out (+ to 5 size) (png-adler raw)
                                 (endianness big))
            (loop (+ from size) (+ to 5 size)))))
    out))

;; Writes pixels, row after row of premultiplied BGRA, to path.
(define (png-write path bytes w h)
  (let ([raw (make-bytevector (* h (+ 1 (* 4 w))) 0)])
    (do ([y 0 (+ y 1)]) ((= y h))
      (let ([row (* y (+ 1 (* 4 w)))])
        (do ([x 0 (+ x 1)]) ((= x w))
          (let* ([from (* 4 (+ x (* y w)))]
                 [to (+ row 1 (* 4 x))]
                 [a (bytevector-u8-ref bytes (+ from 3))]
                 [un (lambda (v)
                       (if (fx< 0 a 255)
                           (fxmin 255 (fxquotient (fx+ (fx* v 255)
                                                       (fxquotient a 2))
                                                  a))
                           v))])
            (bytevector-u8-set! raw to
                                (un (bytevector-u8-ref bytes (+ from 2))))
            (bytevector-u8-set! raw (+ to 1)
                                (un (bytevector-u8-ref bytes (+ from 1))))
            (bytevector-u8-set! raw (+ to 2)
                                (un (bytevector-u8-ref bytes from)))
            (bytevector-u8-set! raw (+ to 3) a)))))
    (call-with-port
     (open-file-output-port path (file-options no-fail))
     (lambda (port)
       (put-bytevector port (bytevector 137 80 78 71 13 10 26 10))
       (let ([head (make-bytevector 13 0)])
         (bytevector-u32-set! head 0 w (endianness big))
         (bytevector-u32-set! head 4 h (endianness big))
         (bytevector-u8-set! head 8 8)
         (bytevector-u8-set! head 9 6)
         (png-chunk port "IHDR" head))
       (png-chunk port "IDAT" (png-zlib raw))
       (png-chunk port "IEND" (make-bytevector 0))))))

;; Draws thunk on a clear image w × h pixels big, and writes it to path.
(define (png-write-drawing path w h thunk)
  (png-write path (drawing->bytes w h 1 thunk) w h))

;; The screen as it is now, to path. => path
(define (png-write-screen path)
  (png-write path (screen-bytes) (canvas-pixel-width) (canvas-pixel-height))
  path)

;; The same, written once core0 has drawn it, then called with path on
;; core1: nothing waits for it.
(define (png-write-screen-then path then)
  (let ([w (canvas-pixel-width)] [h (canvas-pixel-height)])
    (screen-bytes-then (lambda (bytes)
                         (png-write path bytes w h)
                         (then path)))))
