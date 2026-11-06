;;; tests/units.ss — the world piece by piece, headless: a file a topic in
;;; tests/units/, an app's, a kit's, a service's or the core's, each in a
;;; process of its own, so that none leans on what another left behind:
;;;
;;;   scheme --script tests/units.ss [output-dir [topic ...]]
;;;   scheme --script tests/units.ss out              every file there
;;;   scheme --script tests/units.ss out life boids   those
;;;
;;; This file is what they share: the checks, the images, the helpers more
;;; than one of them uses. output-dir only receives scratch files.

(define *schevana-root*
  (let ([dir (path-parent (path-parent (car (command-line))))])
    (if (string=? dir "") "." dir)))

(define out-dir
  (if (pair? (command-line-arguments)) (car (command-line-arguments)) "."))

(define units-asked
  (if (pair? (command-line-arguments)) (cdr (command-line-arguments)) '()))

;; Every file of tests/units.
(define (units-topics)
  (map path-root
       (sort string<?
             (directory-list (string-append *schevana-root* "/tests/units")))))

;; Whether topic passes, run by this file in a process of its own.
(define (units-run topic)
  (printf "--- ~a\n" topic)
  (flush-output-port (current-output-port))
  (zero? (system (format "scheme --script \"~a/tests/units.ss\" \"~a\" \"~a\""
                         *schevana-root* out-dir topic))))

;; All of them, or those asked for: here only the topics' verdicts.
(unless (= (length units-asked) 1)
  (let ([failed (remp units-run
                      (if (null? units-asked) (units-topics) units-asked))])
    (if (null? failed)
        (printf "all topics passed\n")
        (printf "~a topic(s) FAILED: ~a\n" (length failed) failed))
    (exit (if (null? failed) 0 1))))

;;; ------------------------------------------------------------------ a topic

(load (string-append *schevana-root* "/load.ss"))

;; Never touch the user's real theme file, nor their apps' permissions.
(set! *theme-file-path* (string-append out-dir "/theme.ss"))
(when (file-exists? *theme-file-path*) (delete-file *theme-file-path*))
(set! *grant-file-path* (string-append out-dir "/permissions.ss"))
(when (file-exists? *grant-file-path*) (delete-file *grant-file-path*))

(define failures 0)

(define-syntax check
  (syntax-rules ()
    [(_ name expr)
     (let ([ok (guard (c [#t (printf "  error: ~a\n" (condition->string c))
                             #f])
                 expr)])
       (unless ok (set! failures (+ failures 1)))
       (printf "~a ~a\n" (if ok "ok  " "FAIL") name))]))

(define (steps n) (do ([i 0 (+ i 1)]) ((= i n)) (schevana-step! 0)))

(define (raises? thunk) (guard (c [#t #t]) (thunk) #f))

;;; ------------------------------------------------------------------ images

;; A fresh pw × ph image drawn by thunk with *cr* on it, scaled by s.
(define (image pw ph s thunk)
  (let* ([surface (cairo-image-surface-create CAIRO_FORMAT_ARGB32 pw ph)]
         [cr (cairo-create surface)])
    (cairo-scale cr s s)
    (fluid-let ([*cr* cr]) (thunk))
    (cairo-destroy cr)
    (cairo-surface-flush surface)
    surface))

(define (pixel-at surface x y)
  (foreign-ref 'unsigned-32 (cairo-image-surface-get-data surface)
               (+ (* y (cairo-image-surface-get-stride surface)) (* 4 x))))

;; The largest channel difference between two images of the same size,
;; outside the mask rects ((x0 y0 x1 y1) ...).
(define (max-diff a b . mask)
  (unless (and (= (cairo-image-surface-get-width a)
                  (cairo-image-surface-get-width b))
               (= (cairo-image-surface-get-height a)
                  (cairo-image-surface-get-height b)))
    (errorf 'max-diff "images differ in size"))
  (cairo-surface-flush a)
  (cairo-surface-flush b)
  (let ([pa (cairo-image-surface-get-data a)]
        [pb (cairo-image-surface-get-data b)]
        [sa (cairo-image-surface-get-stride a)]
        [sb (cairo-image-surface-get-stride b)]
        [w (cairo-image-surface-get-width a)]
        [h (cairo-image-surface-get-height a)])
    (define (masked? x y)
      (exists (lambda (r)
                (and (<= (car r) x) (< x (caddr r))
                     (<= (cadr r) y) (< y (cadddr r))))
              mask))
    (let row ([y 0] [worst 0])
      (cond
        [(= y h) worst]
        [(zero? (sdl-memcmp (+ pa (* y sa)) (+ pb (* y sb)) (* 4 w)))
         (row (+ y 1) worst)]
        [else
         (let col ([x 0] [worst worst])
           (if (= x w)
               (row (+ y 1) worst)
               (let ([p (foreign-ref 'unsigned-32 pa (+ (* y sa) (* 4 x)))]
                     [q (foreign-ref 'unsigned-32 pb (+ (* y sb) (* 4 x)))])
                 (col (+ x 1)
                      (if (or (fx= p q) (masked? x y))
                          worst
                          (fxmax worst (pixel-diff p q)))))))]))))

;; The largest difference of the four channels of two pixels.
(define (pixel-diff p q)
  (let loop ([k 0] [d 0])
    (if (fx= k 32)
        d
        (loop (fx+ k 8)
              (fxmax d (fxabs (fx- (fxand (fxsrl p k) 255)
                                   (fxand (fxsrl q k) 255))))))))

(define (report-worst worst where)
  (printf "  worst difference ~a~a\n"
          worst (if where (format " at ~s" where) "")))

(define (same-bytes? a b)
  (and (= (cairo-image-surface-get-width a) (cairo-image-surface-get-width b))
       (= (cairo-image-surface-get-height a) (cairo-image-surface-get-height b))
       (zero? (max-diff a b))))

;; The canvas's pixels, copied.
(define (canvas-bytes)
  (cairo-surface-flush *canvas*)
  (let* ([n (* (cairo-image-surface-get-stride *canvas*) (canvas-pixel-height))]
         [bv (make-immobile-bytevector n)])
    (sdl-memcpy (object->reference-address bv)
                (cairo-image-surface-get-data *canvas*)
                n)
    bv))

(define (cairo-matrix-xx cr)
  (cairo-get-matrix cr *scratch*)
  (foreign-ref 'double *scratch* 0))

;;; ------------------------------------------------------------------ helpers
;;; What more than one topic uses.

(define (bytes-total) (+ (bytes-allocated) (bytes-deallocated)))

;; The canvas's pixel at logical point (x, y).
(define (canvas-pixel x y)
  (cairo-surface-flush *canvas*)
  (pixel-at *canvas* (exact (floor (* x *scale*)))
            (exact (floor (* y *scale*)))))

;; thunk's result, with the styles registered meanwhile gone after it.
(define (with-test-styles thunk)
  (let ([plain *styles*])
    (dynamic-wind void thunk
                  (lambda () (set! *styles* plain) (set-style! 'mac)))))

;; Whether thunk ends within the fuel an app's handler gets.
(define (within-fuel? thunk)
  ((make-engine thunk) handler-fuel (lambda (left . r) #t) (lambda (e) #f)))

;; The characters text-width is given while thunk runs.
(define (characters-measured thunk)
  (let ([n 0] [plain text-width])
    (dynamic-wind
      (lambda ()
        (set! text-width
              (case-lambda
                [(s) (set! n (+ n (string-length s))) (plain s)]
                [(s f) (set! n (+ n (string-length s))) (plain s f)])))
      thunk
      (lambda () (set! text-width plain)))
    n))

;; words, then spaces, to n characters: "words words wo".
(define (words-of n)
  (substring (apply string-append (make-list (+ 1 (quotient n 6)) "words "))
             0 n))

;; An image's pixels as rows of characters, by colors ((pixel . char)
;; ...); # for any other.
(define (pixel-rows surface key)
  (let ([w (cairo-image-surface-get-width surface)]
        [h (cairo-image-surface-get-height surface)])
    (map (lambda (y)
           (list->string
            (map (lambda (x)
                   (let ([p (assv (pixel-at surface x y) key)])
                     (if p (cdr p) #\#)))
                 (iota w))))
         (iota h))))

;; A window holding a text field, a label under it: (values win ui).
(define (field-window text)
  (let ([ui (make-ui)])
    (values (apply open-window "Field" 'size '(400 . 120) 'pos '(200 . 200)
                   'ui ui
                   'draw (lambda (win w h)
                           (ui-begin! ui)
                           (ui-text-field ui 'f 20 20 300 30 text void)
                           (ui-draw-label 20 70 300 20 '() "a label")
                           (ui-end! ui w h))
                   (ui-handlers ui))
            ui)))

;; A window whose content is a scroll view of 40 bars, 800 high.
(define (scroll-window title . opts)
  (let ([ui (make-ui)])
    (apply open-window title 'size '(300 . 200) 'pos '(300 . 200)
           'draw (lambda (win w h)
                   (ui-begin! ui)
                   (ui-scroll ui 'v 0 0 w h
                     (lambda (top)
                       (do ([i 0 (+ i 1)]) ((= i 40))
                         (fill-rect 10 (+ top (* i 20)) 260 10 'accent))
                       (+ top 800)))
                   (ui-end! ui w h))
           (append opts (ui-handlers ui)))))

;; Where the window's view has its bar: its region's x, or #f for none.
(define (bar-x win)
  (let ([r (ui-find (window-ref win 'ui) '(v bar))]) (and r (ui-region-x r))))

;; The ticks recorded by thunk, the newest first.
(define (profile-test-ticks thunk)
  (let ([before (profile-ticks)])
    (thunk)
    (let loop ([l (profile-ticks)] [acc '()])
      (if (or (null? l) (memv (car l) before))
          (reverse acc)
          (loop (cdr l) (cons (car l) acc))))))

;;; ------------------------------------------------------------------ boot

(schevana-boot! 'headless 1280 800)

(load (format "~a/tests/units/~a.ss" *schevana-root* (car units-asked)))

(steps 2)
(check "the world still renders after all this" (begin (render-frame!) #t))

(if (zero? failures)
    (printf "all checks passed\n")
    (printf "~a check(s) FAILED\n" failures))
(exit (if (zero? failures) 0 1))
