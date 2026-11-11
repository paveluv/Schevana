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

;; s as one word of /bin/sh's, whatever it holds.
(define (units-sh-word s)
  (let ([o (open-output-string)])
    (put-char o #\')
    (string-for-each
      (lambda (c) (if (char=? c #\') (put-string o "'\\''") (put-char o c)))
      s)
    (put-char o #\')
    (get-output-string o)))

;; The loader's variables that macOS drops on the way into /bin/sh: set
;; here, they're handed on by name.
(define units-loader-variables
  '("DYLD_LIBRARY_PATH" "DYLD_FALLBACK_LIBRARY_PATH"))

;; /bin/sh's command that becomes a run of Chez on script with args, with
;; env's variables, (name . value), and the loader's set. Chez is "chez"
;; where Homebrew installs it, as in ./schevana, else "scheme".
(define (units-chez env script . args)
  (format "exec env~{ ~a~} \"$(command -v chez || echo scheme)\" \
           --script~{ ~a~}"
          (map (lambda (v)
                 (string-append (car v) "=" (units-sh-word (cdr v))))
               (append env
                       (filter cdr
                               (map (lambda (name) (cons name (getenv name)))
                                    units-loader-variables))))
          (map units-sh-word (cons script args))))

;; command's exit status, or 137 if it still ran after seconds and was
;; killed, lest a hang hold up the suite. GNU's timeout isn't everywhere (a
;; Mac has none), so this is plain sh; command execs, so the process killed
;; is its own.
(define (units-system-within seconds command)
  (system
    (format "(~a) & p=$!; i=0; while kill -0 $p 2> /dev/null; do \
             if [ $i -ge ~a ]; then kill -9 $p; break; fi; \
             sleep 1; i=$((i + 1)); done; wait $p 2> /dev/null"
            command seconds)))

;; Whether topic passes, run by this file in a process of its own.
(define (units-run topic)
  (printf "--- ~a\n" topic)
  (flush-output-port (current-output-port))
  (zero? (system (units-chez '() (string-append *schevana-root*
                                                "/tests/units.ss")
                             out-dir topic))))

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
(load (string-append *schevana-root* "/tests/core0.ss"))

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

;; An image's pixels, read back from the GPU: premultiplied, a native word of
;; B, G, R and A bytes each.
(define-record-type picture
  (fields bytes w h))

;; A fresh pw × ph image drawn by thunk, scaled by s.
(define (image pw ph s thunk)
  (make-picture (drawing->bytes pw ph s thunk) pw ph))

;; What the last frame left on the screen.
(define (shown-picture)
  (let* ([r *renderer*]
         [w (renderer-target-w r)]
         [h (renderer-target-h r)]
         [cb (sdl-acquire-gpu-commands (renderer-device r))])
    (make-picture (gpu-read-texture! r cb (renderer-target r) w h) w h)))

;; The screen as it would be drawn now: the same picture until a frame is
;; asked for or drawn, so that reading pixel after pixel costs one drawing.
(define screen-picture-kept #f)
(define screen-picture-frames -1)
(define (screen-picture)
  (when (or *dirty* (not screen-picture-kept)
            (not (= screen-picture-frames *frames-drawn*)))
    (set! screen-picture-kept
      (make-picture (screen-bytes) *canvas-pw* *canvas-ph*))
    (set! screen-picture-frames *frames-drawn*))
  screen-picture-kept)

;; Nothing to free: a picture is a bytevector.
(define (picture-free! p) (void))

(define (pixel-at p x y)
  (bytevector-u32-native-ref (picture-bytes p)
                             (* 4 (+ x (* y (picture-w p))))))

;; What the GPU holds of a pixmap's pixels, drawn at its size: a picture.
(define (pixmap-picture pm)
  (image (pixmap-w pm) (pixmap-h pm) 1 (lambda () (pixmap-draw pm 0 0))))

;; The largest channel difference between two images of the same size,
;; outside the mask rects ((x0 y0 x1 y1) ...).
(define (max-diff a b . mask)
  (unless (and (= (picture-w a) (picture-w b))
               (= (picture-h a) (picture-h b)))
    (errorf 'max-diff "images differ in size"))
  (let ([pa (picture-bytes a)] [pb (picture-bytes b)]
        [w (picture-w a)] [h (picture-h a)])
    (define (masked? x y)
      (exists (lambda (r)
                (and (<= (car r) x) (< x (caddr r))
                     (<= (cadr r) y) (< y (cadddr r))))
              mask))
    (if (bytevector=? pa pb)
        0
        (let row ([y 0] [worst 0])
          (if (= y h)
              worst
              (let col ([x 0] [worst worst])
                (if (= x w)
                    (row (+ y 1) worst)
                    (let ([p (bytevector-u32-native-ref pa (* 4 (+ x (* y w))))]
                          [q (bytevector-u32-native-ref pb
                                                        (* 4 (+ x (* y w))))])
                      (col (+ x 1)
                           (if (or (fx= p q) (masked? x y))
                               worst
                               (fxmax worst (pixel-diff p q))))))))))))

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
  (and (= (picture-w a) (picture-w b))
       (= (picture-h a) (picture-h b))
       (bytevector=? (picture-bytes a) (picture-bytes b))))

;; The screen's pixels.
(define (canvas-bytes) (screen-bytes))

;;; ------------------------------------------------------------------ helpers
;;; What more than one topic uses.

(define (bytes-total) (+ (bytes-allocated) (bytes-deallocated)))

;; The last frame published, its bytes as "/recorder" holds them (tests
;; reach inside the seal): (values recs recs-n extras extras-n).
(define (rec-last)
  (let ([r *rec-root*])
    (values (gpu-recording-recs r) (gpu-recording-recs-n r)
            (gpu-recording-extras r) (gpu-recording-extras-n r))))

;; The screen's pixel at logical point (x, y).
(define (canvas-pixel x y)
  (pixel-at (screen-picture) (exact (floor (* x *scale*)))
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
    ;; none of the top bar's status: its ms/tick and its memory change length
    ;; as they please, and would count
    (fluid-let ([*status-segments* '()] [*status-shown* '()])
      (dynamic-wind
        (lambda ()
          (set! text-width
                (case-lambda
                  [(s) (set! n (+ n (string-length s))) (plain s)]
                  [(s f) (set! n (+ n (string-length s))) (plain s f)])))
        thunk
        (lambda () (set! text-width plain))))
    n))

;; words, then spaces, to n characters: "words words wo".
(define (words-of n)
  (substring (apply string-append (make-list (+ 1 (quotient n 6)) "words "))
             0 n))

;; An image's pixels as rows of characters, by colors ((pixel . char)
;; ...); # for any other.
(define (pixel-rows surface key)
  (let ([w (picture-w surface)]
        [h (picture-h surface)])
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
                         (fill-box 10 (+ top (* i 20)) 260 10 'accent))
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
