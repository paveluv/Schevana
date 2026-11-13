;;; tests/units/drawing.ss — the drawing layer: measuring, core0's window,
;;; invalidation.

;;; measuring: arithmetic on a font's tables, with no device

(define (measured)
  (list (text-width "Schevana λ" 'ui)
        (text-width "(define x 1)" 'mono)
        (font-metrics (make-font* "sans" 13))
        (font-metrics (make-font* "monospace" 11 'bold))))

;; Fontconfig's own choices there lack a λ or break the layouts.
(when (string-contains-ci? (symbol->string (machine-type)) "osx")
  (check "a Mac's generic font names give DejaVu, or the nearest it has"
         (for-all
          (lambda (family names)
            (let ([file (car (font-file-match family 'normal 'normal))])
              (exists (lambda (n) (string-contains-ci? file n)) names)))
          '("sans-serif" "monospace")
          '(("DejaVuSans" "LucidaGrande") ("DejaVuSansMono" "Menlo")))))

(check "text-width and font-metrics work before the first frame"
       (and (zero? *frame-ms*)
            (> (text-width "Schevana" 'ui) 0)
            (> (font-line-height 'ui) 0)))

(steps 2)

(define (stray-drawing!)
  (fill-box 0 0 600 400 'red)
  (draw-text 20 20 "stray" 'text 'big)
  (draw-shadow 100 100 300 200 9 14)
  (pixmap-draw (make-pixmap 2 2 #xff0000) 10 10 50 50))

(check "a window's present mode follows 'present-mode at its next frame, \
        asked once a change; a mode it doesn't offer, or that the swapchain \
        refuses, leaves it as it is, and with no window there's none to change"
       (let ([asked '()] [answer #t])
         (define (frame!) (request-frame!) (schevana-step! 0))
         (define (choose! mode)
           (override! 'present-mode mode)
           (frame!)
           (frame!)
           (cons *gpu-present-mode* (length asked)))
         (let* ([results
                 (fluid-let ([gpu-present-modes (lambda () '(vsync mailbox))]
                             [sdl-set-swapchain-parameters
                              (lambda (device window composition mode)
                                (set! asked (cons mode asked))
                                answer)])
                   (let* ([mailbox (choose! 'mailbox)]
                          [vsync (choose! 'vsync)]
                          [not-offered (choose! 'immediate)]
                          [refused (begin (set! answer #f)
                                          (choose! 'mailbox))])
                     (set! answer #t)
                     (override! 'present-mode)
                     (frame!)
                     (list mailbox vsync not-offered refused)))]
                [windowless (choose! 'mailbox)])
           (override! 'present-mode)
           (frame!)
           (and (equal? results
                        '((mailbox . 1) (vsync . 2) (vsync . 2) (vsync . 3)))
                (equal? (reverse asked) '(2 0 2 0))
                (equal? (car windowless) 'vsync)
                (eq? (cdr (assq 'present-mode (inspect-device))) 'vsync)))))

(check "stray drawing between frames leaves the screen untouched"
       (let ([before (canvas-bytes)])
         (stray-drawing!)
         (bytevector=? before (canvas-bytes))))

(check "measuring doesn't depend on the scale (100, 125, 150, 200%), nor on \
        where it happens: in a half-scale style preview, it is the same"
       (let* ([at-100 (measured)]
              [same?
               (for-all
                (lambda (s)
                  (canvas-create! 1280 800 s)
                  (and (equal? at-100 (measured))
                       (equal? at-100
                               (begin
                                 (rec-begin! *canvas-ratio*)
                                 (draw-style-preview 'genera 0 0 200 150 0.5)
                                 (with-scale (0.5) (measured))))))
                '(1 5/4 3/2 2))])
         (canvas-create! 1280 800 *screen-chosen-scale*)
         same?))
(steps 1)

(set-theme! 'scale 200)
(steps 1)
(check "stray drawing at 200% leaves the screen untouched"
       (let ([before (canvas-bytes)])
         (stray-drawing!)
         (bytevector=? before (canvas-bytes))))
(set-theme! 'scale 0)
(steps 1)

;;; ------------------------------------------------------------------
;;; core0's window

;; (w h scale ratio) -> window units: logical size × scale / pixel ratio.
(check
 "core0's window opens at the logical size times the scale, in window units"
 (equal? (map (lambda (args)
                (call-with-values (lambda () (apply screen-window-size args))
                                  list))
              '((1280 800 1 1) (1280 800 2 1) (1280 800 2 2) (1280 800 3/2 2)
                (1280 800 1 2) (1024 640 5/4 1) (1281 801 7/4 2)))
         '((1280 800) (2560 1600) (1280 800) (960 600) (640 400) (1280 800)
           (1121 701))))

;;; invalidation

(let ([w (open-window "Dirty" 'size '(200 . 100))])
  (define (asks? thunk) (set! *dirty* #f) (thunk) *dirty*)
  (check "(invalidate!), (invalidate! #f), (invalidate! win), \
          (invalidate! win x y w h) and (request-frame!) ask for a frame"
         (for-all asks? (list (lambda () (invalidate!))
                              (lambda () (invalidate! #f))
                              (lambda () (invalidate! w))
                              (lambda () (invalidate! w 1 2 3 4))
                              request-frame!)))
  (let ([plain *styles*]
        [bleed-of (lambda (w)   ; how far w's extent reaches past its frame
                    (let-values ([(x y ew eh) (window-extent w)])
                      (- (window-x w) x)))])
    (define-style wide "Wide" 'frame-bleed (lambda (win) 5))
    (override! 'shadow 0)
    (window-set! w 'window-style 'wide)
    (let ([wide (bleed-of w)])
      (window-set! w 'window-style 'mac)
      (override! 'shadow -6)
      (let ([narrow (bleed-of w)])
        (override! 'shadow)
        (set! *styles* plain)
        (check (format "a style's 'bleed widens its windows' extent (~a); \
                        nothing makes it smaller than the frame (~a)"
                       wide narrow)
               (and (= wide 5) (= narrow 0))))))
  (window-call w 'key #\a '())   ; no key handler: nothing to see
  (window-on! w 'key (lambda (win key mods) (void)))
  (check "input to a handler asks for a frame"
         (asks? (lambda () (window-call w 'key #\a '()))))
  (window-on! w 'key (lambda (win key mods) (current-window)))
  (check "handlers run with (current-window) set"
         (and (eq? w (window-call w 'key #\a '())) (not (current-window))))
  (close-window! w))

;;; what core0 draws: a run waits for the objects it names

(check "core0 draws a run only once the objects it names are made and not \
        let go of: a list recorded for the next frame can name what that \
        frame's jobs make, which core0 hasn't run yet"
       (let* ([made (gpu-image-make-target 4 4)]
              [later (make-gpu-image 999999 4 4 1 #f #f)]
              [run (lambda (image) (list 0 image 0 1 0))])
         (steps 1)   ; the frame that carries made's job
         (and (gpu-run-drawable? (run made))
              (not (gpu-run-drawable? (run later)))
              (begin (gpu-image-release! made)
                     (not (gpu-run-drawable? (run made)))))))
