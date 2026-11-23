;;; (schevana desktop mousedoc) — the mouse documentation: what each mouse
;;; button does under the pointer, as data, such as ((L . "Move") (L2 .
;;; "Maximize") (R . "Window menu") (W . "Shade")). A region of a window's
;;; frame is described in its style's own words (the region's sixth element)
;;; or else by its kind, whose words follow the style's actions. In the
;;; content, the words are the window's 'mouse-doc (the widget kit's, for the
;;; widget there, or the app's). A surface's words come from its doc. A style
;;; turns 'mouse-doc on to show the documentation: the top bar shows it (the
;;; built-in top bar in its status area), or, when a style has no top bar,
;;; the taskbar does (Genera's who line).

(library (schevana desktop mousedoc)
  (export
    mouse-doc mouse-doc-text mouse-doc-text* mouse-doc-line mouse-doc-frame)
  (import (chezscheme)
          (only (schevana base) at-load define-hook define-state library-layer
                string-join)
          (only (schevana core) *hover* define-part find-surface frame-regions
                maximized? request-frame! resize-kinds shaded? surface-call
                surface-doc theme theme-default! window-ref window-setting))

  (library-layer desktop)

  (at-load
   (theme-default! 'mouse-doc #f))

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

  ;; Returns what an action of win's frame does, in words, or #f.
  (define (action-words win action)
    (case action
      [(maximize) (if (maximized? win) "Restore" "Maximize")]
      [(shade) (if (shaded? win) "Unshade" "Shade")]
      [(minimize) "Minimize"]
      [(close) "Close"]
      [(depth) "Back or front"]
      [else #f]))

  ;; Returns the documentation as the top bar shows it:
  ;; "L: Move · R: Window menu".
  (define-part (mouse-doc-text doc)
    (string-join (map (lambda (b) (format "~a: ~a" (car b) (cdr b))) doc)
                 " · "))

  ;; Returns what a bar that shows the documentation is handed to draw: its
  ;; words (mouse-doc-text), or #f when the style shows none ('mouse-doc) or
  ;; nothing under the pointer is documented.
  (define (mouse-doc-line)
    (and (theme 'mouse-doc)
         (let ([doc (mouse-doc)]) (and (pair? doc) (mouse-doc-text doc)))))

  (define-state *mouse-doc-shown* '())

  ;; Called before a frame by the bar that shows the documentation, with box,
  ;; the bar's box procedure. When the documentation has changed, it asks for
  ;; a frame of that box alone, so moving between two regions with different
  ;; words redraws one thin strip, and moving between regions with the same
  ;; words redraws nothing.
  (define (mouse-doc-frame box)
    (when (theme 'mouse-doc)
      (let ([d (mouse-doc)])
        (unless (equal? d *mouse-doc-shown*)
          (set! *mouse-doc-shown* d)
          (call-with-values box request-frame!))))))
