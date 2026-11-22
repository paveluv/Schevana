;;; tests/units.ss — the world piece by piece, headless: a file a topic in
;;; tests/units/, an app's, a kit's, a service's or the core's, each in a
;;; process of its own, so that none leans on what another left behind,
;;; as many at once as SCHEVANA_TEST_JOBS says (else the CPUs less two),
;;; each writing in a folder of its own, output-dir/topic:
;;;
;;;   scheme --script tests/units.ss [output-dir [topic ...]]
;;;   scheme --script tests/units.ss out              every file there
;;;   scheme --script tests/units.ss out life boids   those
;;;   SCHEVANA_CHECK=text scheme --script tests/units.ss out life
;;;                                         life up to its check named so
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

;; SCHEVANA_CHECK's text, as tests/lib.ss reads it, for the runner here.
(define test-only
  (let ([text (getenv "SCHEVANA_CHECK")])
    (and text (not (string=? text "")) text)))

;; Every topic in tests/units: its .ss files, by name, but those an editor
;; or a Mac's Finder leaves (a name starting with a dot).
(define (units-topics)
  (map path-root
       (sort string<?
             (filter (lambda (f)
                       (and (string=? (path-extension f) "ss")
                            (not (char=? (string-ref f 0) #\.))))
                     (directory-list
                      (string-append *schevana-root* "/tests/units"))))))

;; A run of Chez through /bin/sh, a Mac's loader path with it: test-chez
;; and test-sh-word, which the sources' suite runs itself again by too; and
;; runs at once, as many as the machine allows (test-system-all).
(load (string-append *schevana-root* "/tests/chez.ss"))

;; What a topic's run takes at its peak, MB, for how many go at once
;; (test-jobs): a few hundred MB in the library edition, the heaviest near
;; 800 (measured); some 1.1 to 1.3 GB in the hacker edition, each
;; compiling the world from source.
(define units-topic-mb (if (getenv "SCHEVANA_HACKER") 1500 600))

;; The docs' pages with examples to run (tests/units/docs.ss), each a path
;; from the tree's root: README.md, CREDITS.md and docs/*.md that hold a
;; ```scheme block.
(define (units-docs-pages)
  (filter (lambda (page)
            (call-with-input-file (string-append *schevana-root* "/" page)
              (lambda (p)
                (let loop ()
                  (let ([l (get-line p)])
                    (and (not (eof-object? l))
                         (or (string=? l "```scheme") (loop))))))))
          (append '("README.md" "CREDITS.md")
                  (map (lambda (f) (string-append "docs/" f))
                       (sort string<?
                             (filter (lambda (f)
                                       (let ([n (string-length f)])
                                         (and (> n 3)
                                              (string=? (substring f (- n 3) n)
                                                        ".md"))))
                                     (directory-list
                                      (string-append *schevana-root*
                                                     "/docs"))))))))

;; A run of the runner's: (name topic dir env), the topic's file run by
;; this one in a process of its own, with a folder of its own under
;; output-dir for what it writes, what it says there too, with env's
;; variables. Each docs page is a run of its own, as heavy as a topic.
(define (units-runs topic)
  (if (string=? topic "docs")
      (map (lambda (page)
             (list (string-append "docs " page) "docs"
                   (format "~a/docs-~a" out-dir (path-root (path-last page)))
                   (list (cons "SCHEVANA_DOCS_PAGE" page))))
           (units-docs-pages))
      (list (list topic topic (string-append out-dir "/" topic) '()))))

;; The runs that fail, as many at once as jobs, what each said printed in
;; the runs' order as each is done.
(define (units-run-all jobs runs)
  (let ([v (list->vector runs)] [failed '()])
    (for-each (lambda (r) (unless (file-directory? (caddr r))
                            (mkdir (caddr r))))
              runs)
    (test-system-all
     jobs 1800
     (map (lambda (r)
            (string-append
             (test-chez (cadddr r)
                        (string-append *schevana-root* "/tests/units.ss")
                        (caddr r) (cadr r))
             " > " (test-sh-word (string-append (caddr r) "/said.txt"))
             " 2>&1"))
          runs)
     (lambda (i s)
       (let ([r (vector-ref v i)])
         (printf "--- ~a\n" (car r))
         (let ([said (call-with-input-file
                      (string-append (caddr r) "/said.txt")
                      get-string-all)])
           (unless (eof-object? said)
             (put-string (current-output-port) said)))
         (flush-output-port (current-output-port))
         (unless (eqv? s 0) (set! failed (cons (car r) failed))))))
    (reverse failed)))

;; All of them, or those asked for: here only the topics' verdicts.
;; SCHEVANA_CHECK finds a check in the topics asked for: a run names one.
(when (and test-only (null? units-asked))
  (printf "SCHEVANA_CHECK needs its topic: tests/units.ss out topic\n")
  (exit 1))

;; The topics that time the world against core0's screen on the machine's
;; clock (a forked world's frame a refresh): a machine the other topics
;; keep busy misses refreshes, so these run after them, by themselves.
(define units-alone '("fork"))

(unless (= (length units-asked) 1)
  (test-warm!)
  (let* ([topics (if (null? units-asked) (units-topics) units-asked)]
         [jobs (test-jobs units-topic-mb)]
         [_ (printf "~a at once (~a CPUs, ~a MB free)\n" jobs (test-cpus)
                    (test-free-mb))]
         [runs (lambda (ts) (apply append (map units-runs ts)))]
         [failed (append (units-run-all
                          jobs
                          (runs (remp (lambda (t) (member t units-alone))
                                      topics)))
                         (units-run-all
                          1
                          (runs (filter (lambda (t) (member t units-alone))
                                        topics))))])
    (if (null? failed)
        (printf "all topics passed\n")
        (printf "~a run(s) FAILED: ~a\n" (length failed) failed))
    (exit (if (null? failed) 0 1))))

;;; ------------------------------------------------------------------ a topic

(load (string-append *schevana-root* "/tests/lib.ss"))

;; The insets Genera's rule gives with today's fonts: its 2-pixel border
;; and 4-pixel margin on each side, and at the bottom its label strip, the
;; label font's line and 2, at least 14 ((schevana styles genera)).
(define (test-genera-insets)
  (with-style 'genera
    (lambda ()
      (let ([label (font-line-height (theme 'genera-label-font))])
        (list 6 6 6 (+ 6 (max 14 (exact (round (+ label 2))))))))))

;; Medley's: a border of 4, and above it the title strip, at least
;; Medley's 15 pixels, the title font's line under the ink, or the title
;; bar's setting less 15 ((schevana styles interlisp)).
(define (test-interlisp-insets)
  (with-style 'interlisp
    (lambda ()
      (let ([line (exact (round (font-line-height 'ui-small)))])
        (list 4 (+ 2 (max 15 (- (title-height) 15) (+ 2 line))) 4 4)))))

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

;; The last frame published, its bytes as the recorder holds them (tests
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

(load (format "~a/tests/units/~a.ss" *schevana-root* (car units-asked))
      test-form-eval)

(steps 2)
(check "the world still renders after all this" (begin (render-frame!) #t))

(test-verdict!)
