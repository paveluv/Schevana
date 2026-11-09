;;; mousedoc.ss — the mouse documentation: what each button does under the
;;; pointer, as data, ((L . "Move") (L2 . "Maximize") (R . "Window menu")
;;; (W . "Shade")): a window's region in its style's own words (a region's
;;; sixth element) or its kind's, which read the style's actions; in the
;;; content the window's 'mouse-doc (the widget kit's for the widget there,
;;; or the app's); a surface's from its doc. A style turns mouse-doc on
;;; to show it: the built-in top bar does in its status area.

(theme-default! 'mouse-doc #f)

(define (mouse-doc)
  (let ([h *hover*])
    (case (and (pair? h) (car h))
      [(window) (window-doc (cadr h) (caddr h))]
      [(surface) (let ([s (find-surface (cadr h))])
                   (if s (surface-call s surface-doc (caddr h)) '()))]
      [else '()])))

(define (window-doc win region)
  (let ([own (find (lambda (r) (and (eq? (car r) region) (> (length r) 5)))
                   (frame-regions win))]
        [then (lambda (b action) (let ([w (action-words win action)])
                                   (if w (list (cons b w)) '())))])
    (cond
      [own (list-ref own 5)]
      [(memq region '(content scrollbar)) (window-ref win 'mouse-doc '())]
      [(eq? region 'title)
       (append '((L . "Move"))
               (then 'L2 (window-setting win 'title-double-click))
               '((R . "Window menu"))
               (then 'W (window-setting win 'title-wheel)))]
      [(memq region resize-kinds) '((L . "Resize"))]
      [(or (eq? region 'menu) (action-words win region))
       (append (list (cons 'L (or (action-words win region) "Window menu")))
               (let ([a (assq region
                              (window-setting win 'button-double-click))])
                 (if a (then 'L2 (cdr a)) '())))]
      [else '()])))

;; What an action of win's frame does, in words, or #f.
(define (action-words win action)
  (case action
    [(maximize) (if (maximized? win) "Restore" "Maximize")]
    [(shade) (if (shaded? win) "Unshade" "Shade")]
    [(minimize) "Minimize"]
    [(close) "Close"]
    [(depth) "Back or front"]
    [else #f]))

;; The documentation as the top bar shows it: "L: Move · R: Window menu".
(define-part (mouse-doc-text doc)
  (string-join (map (lambda (b) (format "~a: ~a" (car b) (cdr b))) doc)
               " · "))

(defvar *mouse-doc-shown* '())

;; Before a frame (a bar's): what shows the documentation is asked for,
;; box, when it changed, so a move between two regions of other words
;; redraws one thin strip, and one between the same words nothing.
(define (mouse-doc-frame box)
  (when (theme 'mouse-doc)
    (let ([d (mouse-doc)])
      (unless (equal? d *mouse-doc-shown*)
        (set! *mouse-doc-shown* d)
        (call-with-values box request-frame!)))))
