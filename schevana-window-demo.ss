;;; schevana-window-demo.ss — a checklist, an app of the host's desktop made
;;; of Schevana's widget kit: a plain program, no library of its own. Its
;;; one window is a window of GNOME's (or a Mac's), its look the host's own,
;;; light or dark as the desktop prefers ((schevana kits host)). Its title
;;; bar is the host's, or under GNOME its own header bar, with no shadow and
;;; square corners: SDL 3.2's Vulkan swapchain is always opaque. SDL 3.4
;;; gives a transparent window an alpha swapchain; once we move to it, the
;;; window gets GNOME's shadow (on subsurfaces under it) and rounded
;;; corners. Run with the tree as Chez's library folder, from the libraries'
;;; sources, or as schevana-window-demo.sh does, with them compiled into a
;;; cache:
;;;
;;;   CHEZSCHEMELIBDIRS=. scheme-script schevana-window-demo.ss
;;;   ... --headless     a frame, read back and told
;;;   ... --fork         the screen on a thread of its own

(import (chezscheme)
        (schevana core)
        (schevana kits ui)
        (schevana kits host)
        ;; the hosts' looks, each registered as its library runs
        (only (schevana styles adwaita))
        (only (schevana palettes adwaita))
        (only (schevana palettes adwaita-dark))
        (only (schevana styles mac))
        (only (schevana styles windows)))

(define args (cdr (command-line)))

;; Whether text is only spaces.
(define (blank? text) (for-all char-whitespace? (string->list text)))

;; The checklist's window: what's to do, each item (text . done?), checked
;; off, filtered, added to and cleared.
(define (checklist-open)
  (let ([ui (make-ui)]
        [items (list (cons "Water the plants" #f)
                     (cons "Return the library books" #t)
                     (cons "Call the plumber" #f))]
        [draft ""]
        [show 'all])
    (define (shown)
      (filter (lambda (i)
                (case show
                  [(active) (not (cdr i))]
                  [(done) (cdr i)]
                  [else #t]))
              items))
    (define (add!)
      (unless (blank? draft)
        (set! items (append items (list (cons draft #f))))
        (set! draft "")))
    (define (left) (length (filter (lambda (i) (not (cdr i))) items)))
    (apply open-window "Checklist"
      'size '(360 . 520)
      'min-size '(300 . 360)
      'draw
      (lambda (win w h)
        (ui-begin! ui)
        (let* ([pad (theme 'pad)] [gap (ui-gap)] [ch (ui-control-height)]
               [inner (- w pad pad)]
               [add-w (call-with-values (lambda () (ui-button-size "Add" #f))
                        (lambda (bw bh) bw))])
          (ui-text-field ui 'draft pad pad (- inner add-w gap) ch draft
                         (lambda (s) (set! draft s))
                         'placeholder "New item"
                         'on-enter add!)
          (ui-button ui 'add (- w pad add-w) pad add-w ch "Add" add!
                     'primary #t
                     'disabled (blank? draft))
          (ui-segmented ui 'show pad (+ pad ch gap) (+ inner 6) ch
                        '(("All" . all) ("To do" . active) ("Done" . done))
                        show (lambda (s) (set! show s)))
          (let* ([top (+ pad ch gap ch gap)]
                 [foot (- h pad ch)])
            (if (null? (shown))
                (ui-status-page ui 'empty pad top inner (- foot top gap)
                                (if (eq? show 'done) 'check 'edit)
                                (if (eq? show 'done)
                                    "Nothing Done Yet"
                                    "Nothing to Do")
                                (if (eq? show 'done)
                                    "Checked items show here"
                                    "Add an item above")
                                'compact #t)
                ;; the items, a boxed list, scrolled when it's longer than
                ;; its place
                (ui-scroll ui 'list 0 top w (- foot top gap)
                  (lambda (y)
                    (ui-rows ui 'items pad (+ y gap) inner
                             (map (lambda (i)
                                    (checklist-row ui i
                                      (lambda ()
                                        (set! items (remq i items)))))
                                  (shown))))))
            (ui-draw-label pad foot (- inner 120) ch '(dim)
                           (format "~a of ~a left" (left) (length items)))
            (ui-button ui 'clear (- w pad 110) foot 110 ch "Clear done"
                       (lambda ()
                         (set! items (filter (lambda (i) (not (cdr i)))
                                             items)))
                       'danger #t
                       'disabled (= (left) (length items)))))
        (ui-end! ui w h))
      (ui-handlers ui))))

;; An item's row of the boxed list: a check box before its text, and a
;; flat round button at its end that removes it.
(define (checklist-row ui item remove!)
  (let* ([ch (ui-control-height)]
         [row (ui-check-row ui (list 'item item) (car item) (cdr item)
                            (lambda (on?) (set-cdr! item on?)))])
    (cons* (car row) (cadr row) ch
           (lambda (x y w h)
             (ui-button ui (list 'remove item) x (+ y (/ (- h ch) 2)) ch ch
                        #f remove!
                        'quiet #t
                        'circular #t
                        'glyph 'close
                        'tip "Remove"))
           (cddddr row))))

;; The pixel at (x, y) of bytes, the screen's, as (r g b).
(define (pixel bytes x y)
  (let ([at (* 4 (+ x (* y *canvas-pw*)))])
    (list (bytevector-u8-ref bytes (+ at 2))
          (bytevector-u8-ref bytes (+ at 1))
          (bytevector-u8-ref bytes at))))

(host-main "org.schevana.Checklist" 360 520 args
  (lambda ()
    (let ([win (checklist-open)])
      ;; headless: what was drawn, read back, then quit
      (when (member "--headless" args)
        (after 200
          (lambda ()
            (screen-bytes-then
             (lambda (bytes)
               (printf "~a x ~a pixels in ~a, ~a; corners ~s ~s~n"
                       *canvas-pw* *canvas-ph* (current-style)
                       (if (window-error win) "crashed" "drawn")
                       (pixel bytes 0 0)
                       (pixel bytes (- *canvas-pw* 1) (- *canvas-ph* 1)))
               (quit!))))))
      win)))
