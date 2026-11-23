;;; (schevana desktop app-grid) — the app grid: a view of the whole screen
;;; with a search field at its top and entries as large icons with their
;;; names, in pages, as GNOME Shell's overview shows its apps. It is opened
;;; with a procedure that gives the entries for what is typed, each (label
;;; app . thunk), where app is the name of the app whose icon the entry
;;; shows, or #f for an action of another kind (the launcher's,
;;; (schevana desktop launcher)). While it is open, it takes every key and
;;; text: typing searches, the arrows choose an entry, Page Up and Page Down
;;; turn the pages, Return opens the chosen entry and Escape closes the
;;; grid. The search field shows that the keys go to it, with its caret,
;;; once it is pressed or typed in. A press elsewhere opens the entry under
;;; the pointer, turns to the page of a page's dot, or, anywhere else,
;;; closes the grid. It lies over the windows
;;; and under the bars, so the bars stay as they are while it shows. A style
;;; lays it out and draws it (app-grid-areas, draw-app-grid).

(library (schevana desktop app-grid)
  (export
    open-app-grid! close-app-grid! app-grid-open? app-grid-areas
    app-grid-areas* app-grid-draw draw-app-grid draw-app-grid* app-grid-box
    app-grid-at app-grid-mouse app-grid-takes app-grid-doc)
  (import (chezscheme)
          (only (schevana base) at-load define-hook define-state
                library-layer)
          (only (schevana core) *hover* alpha define-part define-surface
                desktop-rect draw-text fill-box fill-circle font-line-height
                point-in? report-error! request-frame! safe-call screen-h
                screen-w text-width with-clip world-value)
          (only (schevana kits text) text-draw-centered text-fit)
          (only (schevana kits ui) ui-draw-app-icon ui-draw-highlight))

  (library-layer desktop)

  ;; While the grid is open: the procedure that gives its entries for what
  ;; is typed, else #f; what is typed; whether the search field has the
  ;; keys' focus; the page shown; and the entry that the keys chose, or #f.
  (define-state *app-grid-items* #f)
  (define-state *app-grid-filter* "")
  (define-state *app-grid-search-focus?* #f)
  (define-state *app-grid-page* 0)
  (define-state *app-grid-sel* #f)

  (define (app-grid-open?) (and *app-grid-items* #t))

  ;; Opens the grid on its first page, with nothing typed. items is
  ;; (lambda (typed) entries).
  (define (open-app-grid! items)
    (set! *app-grid-items* items)
    (set! *app-grid-filter* "")
    (set! *app-grid-search-focus?* #f)
    (set! *app-grid-page* 0)
    (set! *app-grid-sel* #f)
    (request-frame!))

  (define (close-app-grid!)
    (when *app-grid-items*
      (set! *app-grid-items* #f)
      (request-frame!)))

  (define (app-grid-entries) (*app-grid-items* *app-grid-filter*))

  ;; Returns where the grid's pieces are, for n entries with page shown:
  ;; (search x y w h), the search field; then, when there is more than one
  ;; page, a dot for each, ((page . k) x y w h); then each entry of the
  ;; page, (i x y w h), where i counts the entries from the first page's
  ;; first. A page is full before the next one starts.
  (define-part (app-grid-areas n page)
    (let*-values ([(dx dy dw dh) (desktop-rect)]
                  [(lh) (font-line-height 'ui)]
                  [(gap) 12]
                  [(sw) (min (- dw 24) (* 24 lh))] [(sh) (+ lh 12)]
                  [(tile) (+ 48 6 lh 16)] [(pitch) (+ tile gap)]
                  [(top) (+ dy gap sh gap)]
                  [(cols) (max 1 (quotient (+ (- dw 48) gap) pitch))]
                  [(rows) (max 1 (quotient (- (+ dy dh) top lh gap gap) pitch))]
                  [(per) (* rows cols)]
                  [(pages) (max 1 (quotient (+ n per -1) per))]
                  [(x0) (+ dx (quotient (- dw (- (* cols pitch) gap)) 2))])
      (append
       (list (list 'search (+ dx (quotient (- dw sw) 2)) (+ dy gap) sw sh))
       (if (> pages 1)
           (let ([dots-x (+ dx (quotient (- dw (* pages 20)) 2))])
             (map (lambda (k)
                    (list (cons 'page k) (+ dots-x (* k 20))
                          (- (+ dy dh) gap lh) 20 lh))
                  (iota pages)))
           '())
       (map (lambda (j)
              (list (+ (* page per) j) (+ x0 (* (remainder j cols) pitch))
                    (+ top (* (quotient j cols) pitch)) tile tile))
            (iota (max 0 (min per (- n (* page per)))))))))

  ;; Draws the grid: entries as given for what is typed (filter), their
  ;; areas (app-grid-areas), whether the search field has the keys' focus
  ;; (focus?), the page shown, and the entry the keys chose (sel), or #f.
  ;; The pointer's entry is the one *hover* names.
  (define-part (draw-app-grid entries areas filter focus? page sel)
    (let ([es (list->vector entries)] [lh (font-line-height 'ui)])
      (fill-box 0 0 (screen-w) (screen-h) (alpha 'bg-0 0.96))
      (for-each
       (lambda (a)
         (apply
          (lambda (what x y w h)
            (cond
              [(eq? what 'search)
               (fill-box x y w h 'bg-2 6)
               (with-clip (x y w h)
                 (let* ([ty (+ y (/ (- h lh) 2))]
                        [ex (if (string=? filter "")
                                (begin
                                  (draw-text (+ x 10) ty "Type to search…"
                                             'text-faint 'ui)
                                  (+ x 9))
                                (+ 1 (draw-text (min (+ x 10)
                                                     (- (+ x w) 13
                                                        (text-width filter
                                                                    'ui)))
                                                ty filter 'text 'ui)))])
                   (when focus? (fill-box ex ty 1.5 lh 'accent))))]
              [(pair? what)
               (fill-circle (+ x (/ w 2)) (+ y (/ h 2)) 4
                            (if (= (cdr what) page)
                                'text
                                (alpha 'text 0.4)))]
              [else
               (let* ([e (vector-ref es what)] [app (cadr e)] [s 48]
                      [ix (+ x (/ (- w s) 2))] [iy (+ y 8)])
                 (when (or (eqv? what sel)
                           (equal? *hover* (list 'surface 'app-grid what)))
                   (ui-draw-highlight x y w h '()))
                 (if app
                     (ui-draw-app-icon ix iy s '() app)
                     (begin
                       (fill-circle (+ ix (/ s 2)) (+ iy (/ s 2)) (/ s 2)
                                    (alpha 'text 0.1))
                       (text-draw-centered ix iy s s
                                           (string (char-upcase
                                                    (string-ref (car e) 0)))
                                           'text 'big)))
                 (text-draw-centered (+ x 4) (+ iy s 6) (- w 8) lh
                                     (text-fit (car e) (- w 8) 'ui)
                                     'text 'ui))]))
          a))
       areas)))

  ;; Returns (values how many entries a page holds, how many pages there
  ;; are, how many entries a row holds) for n entries, as the style lays
  ;; them out: one page, without dots, holds them all.
  (define (app-grid-paging n)
    (let* ([as (app-grid-areas n 0)]
           [tiles (filter (lambda (a) (fixnum? (car a))) as)]
           [dots (length (filter (lambda (a) (pair? (car a))) as))]
           [cols (if (null? tiles)
                     1
                     (length (filter (lambda (a)
                                       (= (caddr a) (caddr (car tiles))))
                                     tiles)))])
      (if (< dots 2)
          (values (max n 1) 1 cols)
          (values (length tiles) dots cols))))

  ;; Draws the open grid with the style's draw-app-grid (called by name),
  ;; which is handed what it shows.
  (define (app-grid-draw)
    (when *app-grid-items*
      (let ([es (app-grid-entries)])
        ((world-value 'draw-app-grid) es
                                      (app-grid-areas (length es)
                                                      *app-grid-page*)
                                      *app-grid-filter*
                                      *app-grid-search-focus?*
                                      *app-grid-page* *app-grid-sel*))))

  ;; Runs entry e's action, once the grid has closed.
  (define (app-grid-run! e)
    (close-app-grid!)
    (safe-call 'app-grid (cddr e) (lambda (c) (report-error! 'app-grid c))))

  ;; Searches for f: the first page shows what it finds, and its first
  ;; entry is chosen, for Return to open. The search field has the keys'
  ;; focus from then on.
  (define (app-grid-search! f)
    (set! *app-grid-filter* f)
    (set! *app-grid-search-focus?* #t)
    (set! *app-grid-page* 0)
    (set! *app-grid-sel*
      (and (not (string=? f "")) (pair? (app-grid-entries)) 0))
    (request-frame!))

  ;; Turns to page k; an entry the keys chose becomes that page's first.
  (define (app-grid-turn! k)
    (let-values ([(per pages cols)
                  (app-grid-paging (length (app-grid-entries)))])
      (let ([k (max 0 (min k (- pages 1)))])
        (set! *app-grid-page* k)
        (when *app-grid-sel* (set! *app-grid-sel* (* k per)))
        (request-frame!))))

  ;; Chooses entry i, if there is one, and shows its page.
  (define (app-grid-choose! i n per)
    (when (and (>= i 0) (< i n))
      (set! *app-grid-sel* i)
      (set! *app-grid-page* (quotient i per))
      (request-frame!)))

  ;; The keys: the arrows choose the next entry in their direction, left
  ;; and right across the pages, up and down within one; the first arrow
  ;; chooses the page's first entry.
  (define (app-grid-key key)
    (let* ([es (app-grid-entries)] [n (length es)] [sel *app-grid-sel*])
      (let-values ([(per pages cols) (app-grid-paging n)])
        (define (move! di)
          (if sel
              (let ([i (+ sel di)])
                (when (or (memv di '(-1 1))
                          (= (quotient i per) (quotient sel per)))
                  (app-grid-choose! i n per)))
              (app-grid-choose! (* *app-grid-page* per) n per)))
        (case key
          [(escape) (close-app-grid!)]
          [(return)
           (when (and sel (< sel n)) (app-grid-run! (list-ref es sel)))]
          [(left) (move! -1)]
          [(right) (move! 1)]
          [(up) (move! (- cols))]
          [(down) (move! cols)]
          [(page-up) (app-grid-turn! (- *app-grid-page* 1))]
          [(page-down) (app-grid-turn! (+ *app-grid-page* 1))]
          [(backspace)
           (let ([f *app-grid-filter*])
             (when (> (string-length f) 0)
               (app-grid-search! (substring f 0 (- (string-length f) 1)))))]))))

  ;;; The grid's surface, over the windows and under the bars.

  (define (app-grid-box)
    (if *app-grid-items*
        (values 0 0 (screen-w) (screen-h))
        (values 0 0 0 0)))

  ;; Returns what is at (x, y) while the grid is open: an area's what, or
  ;; empty.
  (define (app-grid-at x y)
    (and *app-grid-items*
         (let* ([es (app-grid-entries)]
                [a (find (lambda (a) (apply point-in? x y (cdr a)))
                         (app-grid-areas (length es) *app-grid-page*))])
           (if a (car a) 'empty))))

  (define (app-grid-mouse kind what x y button clicks)
    (when (eq? kind 'down)
      (cond [(fixnum? what)
             (when (eq? button 'left)
               (app-grid-run! (list-ref (app-grid-entries) what)))]
            [(pair? what) (app-grid-turn! (cdr what))]
            [(eq? what 'search)
             (set! *app-grid-search-focus?* #t)
             (request-frame!)]
            [else (close-app-grid!)])))

  (define (app-grid-takes kind value mods)
    (and *app-grid-items*
         (begin (if (eq? kind 'key)
                    (app-grid-key value)
                    (app-grid-search! (string-append *app-grid-filter*
                                                     value)))
                #t)))

  (define (app-grid-doc what)
    (cond [(fixnum? what) '((L . "Open"))]
          [(pair? what) '((L . "Turn to this page"))]
          [(eq? what 'empty) '((L . "Close"))]
          [else '()]))

  (at-load
   (define-surface app-grid 5
     'draw 'app-grid-draw 'box 'app-grid-box 'at 'app-grid-at
     'mouse 'app-grid-mouse 'key 'app-grid-takes 'doc 'app-grid-doc)))
