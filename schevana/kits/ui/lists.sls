;;; (schevana kits ui lists) — a part of the ui kit ((schevana kits ui)),
;;; which gives its names: lists: grids, the side panel, the table, the
;;; tree, rows and the split.

(library (schevana kits ui lists)
  (export
    ui-split ui-split-stacked ui-draw-split ui-draw-split* ui-menu-grid
    ui-draw-menu-grid-panel* ui-draw-menu-grid-heading* ui-draw-menu-grid-item*
    ui-choice-grid ui-draw-choice-grid-label* ui-draw-choice-grid-cell*
    ui-keycap ui-draw-keycap* ui-inline-choices ui-draw-inline-choice*
    ui-inline-choice-size* ui-side-panel-toggle! ui-side-panel
    ui-side-panel-button ui-table-room ui-table-fit ui-table ui-table-step
    ui-table-page ui-table-columns ui-table-header-height ui-table-row-height
    ui-table-cell-inset ui-table-cell-inset* ui-draw-cell ui-draw-cell*
    ui-draw-table-header ui-draw-table-header* ui-draw-table-divider
    ui-draw-table-divider* ui-draw-table-row ui-draw-table-row* ui-tree-states
    ui-tree-expand! ui-tree-key ui-tree ui-tree-areas ui-tree-areas*
    ui-draw-tree-row ui-draw-tree-row* ui-draw-dim ui-draw-dim* ui-rows
    ui-rows-height ui-switch-row ui-check-row ui-entry-row ui-rows-spacing
    ui-rows-spacing* ui-row-height ui-row-height* ui-row-areas ui-row-areas*
    ui-add-row-height ui-add-row-height* ui-draw-add-row ui-draw-add-row*
    ui-rows-radius ui-rows-radius* ui-draw-rows ui-draw-rows* ui-draw-row
    ui-draw-row*)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-hook filter-map
                library-layer list-index plist-ref)
          (only (schevana core) alpha current-window define-part draw-text
                fill-box font-line-height invalidate! plist-remove point-in?
                stroke-box text-width theme theme-default! theme-rule
                window-hover with-clip with-place with-transpose)
          (only (schevana kits text) text-fit)
          (schevana kits ui base)
          (schevana kits ui controls)
          (schevana kits ui text))

  (library-layer kits)


  ;;; ---------------------------------------------------------------- split
  ;;; Two panes side by side, with the line between them dragged to share
  ;;; the room. An app asks for a split where the person should share the
  ;;; room; a pane of a fixed width (Tasks' details) needs none.

  ;; Returns the left pane's width in x..x+w: at, the app's choice, until
  ;; the line is dragged, and then where the line was left, kept so that the
  ;; left pane is at least lo wide and the right one at least hi. A double
  ;; click on the line goes back to at. The line's handle, from y and h
  ;; high, goes over the panes: it is laid out at ui-end!, after them, cut
  ;; to the scroll view the split lies in.
  (define (ui-split ui id x y w h at lo hi)
    (ui-split-of ui id x y w h at lo hi #f))

  ;; The same of two panes one above the other: returns the top pane's
  ;; height in y..y+h, the bottom one at least hi high. The line is the
  ;; style's, transposed.
  (define (ui-split-stacked ui id x y w h at lo hi)
    (ui-split-of ui id x y w h at lo hi #t))

  (define (ui-split-of ui id x y w h at lo hi stacked?)
    (let* ([room (if stacked? h w)] [from (if stacked? y x)]
           [most (max lo (- room hi))]
           [first (clamp (ui-memo ui (ui-id ui id 'at) at) lo most)]
           [line (+ from first)]
           ;; the view the split lies in, if any, which cuts its line too
           [cx (ui-state-clip-x ui)] [cy (ui-state-clip-y ui)]
           [cw (ui-state-clip-w ui)] [ch (ui-state-clip-h ui)])
      (define (handle)
        (ui-region! ui id
          (if stacked? x (- line 3)) (if stacked? (- line 3) y)
          (if stacked? w 6) (if stacked? 6 h)
          'focus 'keep 'cursor (if stacked? 'resize-ns 'resize-ew)
          'doc '((L . "Resize the panes") (L2 . "Back to their sizes"))
          'on
          (lambda (ev)
            (let ([p (if stacked? (caddr ev) (cadr ev))])
              (case (car ev)
                [(press)
                 (and (eq? (list-ref ev 3) 'left)
                      (begin
                        (if (>= (list-ref ev 4) 2)
                            (hashtable-delete! (ui-state-memo ui)
                                               (list id 'at))
                            (ui-memo! ui (list id 'grab) (- p line)))
                        #t))]
                [(drag)
                 (let ([new (clamp (exact (round (- p from
                                                    (ui-memo ui
                                                             (list id 'grab)
                                                             0))))
                                   lo most)])
                   (and (< (cadddr ev) 2) (not (= new first))
                        (begin (ui-memo! ui (list id 'at) new) #t)))]
                [else #f]))))
        (if stacked?
            (with-transpose (ui-draw-split line x w (ui-flags ui id)))
            (ui-draw-split line y h (ui-flags ui id))))
      (ui-later! ui
        (lambda (ww wh)
          (if cw (ui-with-clip ui (cx cy cw ch) (handle)) (handle))))
      first))

  ;; The line between two panes at x, which a drag moves: it shows under the
  ;; pointer and while dragged (flags hover, pressed); at rest, the panes'
  ;; own edges show it.
  (define-part (ui-draw-split x y h flags)
    (when (or (memq 'hover flags) (memq 'pressed flags))
      (fill-box (- x 1) y 2 h 'accent)))

  ;;; ---------------------------------------------------------------- grids
  ;;; The Lisp machines' menus of columns and their choice matrices (TV's
  ;;; multiple-choice menus, Genera's accept-values), made of the kit's
  ;;; parts so that every style draws them its own way.

  ;; A menu of columns, each a heading over its choices: columns is
  ;; ((heading (label . value) ...) ...) and selected the values chosen. A
  ;; press on a choice calls (on-change selected) with the new list, as
  ;; opts' 'policy says: single (that one value), multiple (each on and
  ;; off), or columns (one in each column). 'enabled? (value) is false for
  ;; a choice not to be had now; 'row-height. Returns the grid's bottom.
  (define (ui-menu-grid ui id x y w columns selected on-change . opts)
    (let* ([h (plist-ref opts 'row-height (ui-control-height))]
           [policy (plist-ref opts 'policy 'single)]
           [enabled? (plist-ref opts 'enabled? (lambda (v) #t))]
           [n (length columns)] [cw (/ w (max n 1))]
           [rows (fold-left (lambda (r c) (max r (length c))) 0 columns)]
           [height (+ 8 (* rows h))])
      (ui-draw-menu-grid-panel x y w height '())
      (for-each
       (lambda (column c)
         (let ([cx (+ x (* c cw))])
           (ui-draw-menu-grid-heading (+ cx 4) (+ y 4) (- cw 8) h '()
                                      (car column))
           (for-each
            (lambda (entry r)
              (let* ([value (cdr entry)] [on? (and (member value selected) #t)]
                     [rid (list id c r)] [ey (+ y 4 (* (+ r 1) h))]
                     [off? (not (enabled? value))])
                (ui-pressable! ui rid (+ cx 4) ey (- cw 8) h
                  (lambda ()
                    (on-change
                     (case policy
                       [(multiple)
                        (if on? (remove value selected) (cons value selected))]
                       [(columns)
                        (cons value
                              (filter (lambda (v)
                                        (not (member v (map cdr (cdr column)))))
                                      selected))]
                       [else (list value)])))
                  '(#\space return) (list 'disabled off?) '((L . "Choose")))
                (ui-draw-menu-grid-item (+ cx 4) ey (- cw 8) h
                                        (apply ui-flags ui rid
                                               (append
                                                (if on? '(selected) '())
                                                (if off? '(disabled) '())))
                                        (car entry))))
            (cdr column) (iota (length (cdr column))))))
       columns (iota n))
      (+ y height)))

  (define-part (ui-draw-menu-grid-panel x y w h flags)
    (ui-draw-panel x y w h (cons 'menu flags)))
  (define-part (ui-draw-menu-grid-heading x y w h flags label)
    (ui-draw-label x y w h (append '(group center) flags) label))
  (define-part (ui-draw-menu-grid-item x y w h flags label)
    (ui-draw-button x y w h flags label #f))

  ;; A matrix of choices, rows by columns, each cell a box to tick:
  ;; (checked? row column) and (on-change row column on?). opts: 'enabled?
  ;; (row column), false for a cell not to be had, which is left blank, or
  ;; drawn disabled with 'show-unavailable; 'heading over the rows' names,
  ;; 'label-width, 'row-height. Returns the matrix's bottom.
  (define (ui-choice-grid ui id x y w rows columns checked? on-change . opts)
    (let* ([h (plist-ref opts 'row-height (ui-control-height))]
           [name-w (plist-ref opts 'label-width (* w 9/25))]
           [cw (/ (- w name-w) (max 1 (length columns)))]
           [enabled? (plist-ref opts 'enabled? (lambda (r c) #t))]
           [show? (plist-ref opts 'show-unavailable #f)])
      (ui-draw-choice-grid-label x y name-w h '(group)
                                 (plist-ref opts 'heading "Item"))
      (for-each (lambda (label c)
                  (ui-draw-choice-grid-label (+ x name-w (* c cw)) y cw h
                                             '(group center) label))
                columns (iota (length columns)))
      (for-each
       (lambda (label r)
         (let ([ry (+ y (* (+ r 1) h))])
           (ui-draw-choice-grid-label x ry name-w h '() label)
           (do ([c 0 (+ c 1)]) ((= c (length columns)))
             (let* ([on (enabled? r c)] [on? (checked? r c)]
                    [rid (list id r c)] [bx (+ x name-w (* c cw))])
               (when (or on show?)
                 (ui-pressable! ui rid bx ry cw h
                                (lambda () (on-change r c (not on?)))
                                '(#\space) (list 'disabled (not on))
                                '((L . "Toggle the choice")))
                 (ui-draw-choice-grid-cell
                  bx ry cw h
                  (apply ui-flags ui rid
                         (append (if on? '(checked) '())
                                 (if on '() '(disabled))))))))))
       rows (iota (length rows)))
      (+ y (* h (+ 1 (length rows))))))

  (define-part (ui-draw-choice-grid-label x y w h flags label)
    (ui-draw-label x y w h flags label))
  (define-part (ui-draw-choice-grid-cell x y w h flags)
    (let-values ([(cw ch) (ui-checkbox-size "")])
      (ui-draw-checkbox (+ x (/ (- w cw) 2)) y cw h flags #f)))

  ;; A key cap: a button that does action, and answers to keys (as
  ;; ui-pressable! takes them) while it has the keyboard, labeled with the
  ;; key; a style draws it as its keys look (Genera's, in a lozenge).
  (define (ui-keycap ui id x y w h label action keys)
    (ui-pressable! ui id x y w h action keys '() (list (cons 'L label)))
    (ui-draw-keycap x y w h (ui-flags ui id) label))

  (define-part (ui-draw-keycap x y w h flags label)
    (ui-draw-button x y w h flags label #f))

  ;; A choice of a few values shown all at once, in a row from x, the
  ;; current one marked (Genera's accept-values: the words, the current
  ;; one bold): choices ((label . value) ...). A press on one calls
  ;; (on-select value). Returns where the row ends.
  (define (ui-inline-choices ui id x y h choices current on-select)
    (let loop ([cs choices] [cx x] [i 0])
      (if (null? cs)
          cx
          (let*-values ([(c) (car cs)] [(rid) (list id i)]
                        [(cw ch) (ui-inline-choice-size (car c))])
            (ui-pressable! ui rid cx y cw h (lambda () (on-select (cdr c)))
                           '(#\space return) '() '((L . "Choose")))
            (ui-draw-inline-choice cx y cw h
                                   (apply ui-flags ui rid
                                          (if (equal? (cdr c) current)
                                              '(selected)
                                              '()))
                                   (car c))
            (loop (cdr cs) (+ cx cw 4) (+ i 1))))))

  (define-part (ui-draw-inline-choice x y w h flags label)
    (ui-draw-button x y w h flags label #f))
  (define-part (ui-inline-choice-size label) (ui-button-size label #f))

  ;;; --------------------------------------------------------------- side panel
  ;;; What an app shows beside its work, for those who want it: controls,
  ;;; numbers, details. Its button hides it and shows it again; while
  ;;; hidden, it takes none of the room. The button is a widget of its own,
  ;;; placed where the app has room for it (a toolbar, a status line), never
  ;;; over the work, and best where it stays put as the panel comes and goes,
  ;;; so that a second press undoes the first.
  ;;;
  ;;;   (ui-side-panel ui 'controls 0 0 w h 'right 240 200
  ;;;     (lambda (x y w h) ...the rest...)
  ;;;     (lambda (x y w h) ...the panel, its surface already there...))
  ;;;   (ui-side-panel-button ui 'controls x y 24 20 'right)
  ;;;   (ui-side-panel-toggle! ui 'controls)    for a key
  ;;;
  ;;; An app whose work should not change size as the panel comes and goes
  ;;; gives 'floating #t: the rest keeps all the room, and the panel lies
  ;;; over it.

  (at-load
   (theme-default! 'floating-opacity 0.8))   ; of a surface over what's under it

  (define (ui-side-panel-open? ui id)
    (not (ui-memo ui (list id 'hidden) #f)))

  ;; Does what the button does, for a key; the caller invalidates.
  (define (ui-side-panel-toggle! ui id)
    (ui-memo! ui (list id 'hidden) (ui-side-panel-open? ui id)))

  ;; Lays out x y w h: calls rest, then panel (width wide, at side, left or
  ;; right), each with its rectangle. Where the rest would be narrower than
  ;; least, there is no panel and rest has all the room. opts: 'floating,
  ;; for a panel over the rest, which keeps all the room; a press on the
  ;; panel does not reach the rest.
  (define (ui-side-panel ui id x y w h side width least rest panel . opts)
    (let* ([fits? (>= w (+ width least))]
           [floating? (plist-ref opts 'floating #f)]
           [room (if (and fits? (ui-side-panel-open? ui id)) width 0)]
           [beside (if floating? 0 room)]
           [right? (eq? side 'right)])
      (ui-memo! ui (list id 'fits) fits?)
      (rest (if right? x (+ x beside)) y (- w beside) h)
      (when (> room 0)
        (let ([px (if right? (- (+ x w) room) x)])
          (when floating? (ui-region! ui (list id 'floating) px y room h))
          (ui-draw-surface px y room h
                           (append (if right? '(side) '(nav))
                                   (if floating? '(floating) '())))
          (panel px y room h)))))

  ;; The button for panel id at side, in the rectangle given. Its glyph is a
  ;; window with a pane on that side, filled in while the panel shows. The
  ;; button is disabled where the panel has no room.
  (define (ui-side-panel-button ui id x y w h side)
    (let ([open? (ui-side-panel-open? ui id)]
          [fits? (ui-memo ui (list id 'fits) #t)])
      (ui-button ui (list id 'button) x y w h #f
                 (lambda () (ui-side-panel-toggle! ui id))
                 'glyph (if (eq? side 'right)
                            (if open? 'panel-right-shown 'panel-right)
                            (if open? 'panel-left-shown 'panel-left))
                 'quiet #t
                 'disabled (not fits?)
                 'tip (cond [(not fits?) "No room for the panel here"]
                            [open? "Hide this panel"]
                            [else "Show the panel"]))))

  ;;; ---------------------------------------------------------------- table

  ;; Returns the width a table or tree w wide gives its columns: w less the
  ;; room its scroll bar keeps (ui-scrollbar-inset), so that columns fitted
  ;; to it stay clear of the bar.
  (define (ui-table-room w)
    (- w (ui-scrollbar-inset 'left) (ui-scrollbar-inset 'right)))

  ;; Returns columns that fit in w, in the form a table or tree takes them.
  ;; One column has width #f and takes what the others leave; the columns
  ;; that drops names are left out, in that order, while that column would
  ;; be narrower than least.
  (define (ui-table-fit w columns drops least)
    (let loop ([cols columns] [drops drops])
      (let ([fixed (apply + (filter-map caddr cols))])
        (if (or (null? drops) (<= (+ fixed least) w))
            (map (lambda (c)
                   (if (caddr c)
                       c
                       (cons* (car c) (cadr c) (- w fixed) (cdddr c))))
                 cols)
            (loop (remp (lambda (c) (eq? (car c) (car drops))) cols)
                  (cdr drops))))))

  ;; columns: ((key title width flag ...) ...). Each width is a default the
  ;; user may change by dragging (ui-table-columns); the flags are the
  ;; heading's and the cells' (right: aligned at the right, as numbers are),
  ;; and a string among them is the heading's tooltip, saying what the
  ;; column means. rows are the app's values, and selected is the one eq?
  ;; to it; a left press calls on-select. cell draws a cell: (lambda (row key
  ;; x y w h flags) ...), with flags its row's and its column's. opts: 'sort
  ;; ((key . up|down) or #f); 'on-sort (key), called on a press on a
  ;; heading; 'on-open (row), on a double click; 'on-menu (row x y), on a
  ;; right press; 'tip (row), a row's tooltip or #f; 'reveal, which when
  ;; true scrolls the selected row into view; 'checked (row), for a checkbox
  ;; before each row's first cell, checked when it returns true, and checked
  ;; and disabled when it returns fixed, with 'on-check (row) called on a
  ;; press on it; and 'resize, how a drag resizes the columns, pair or
  ;; shift, by default the style's (table-resize).
  (define (ui-table ui id x y w h columns rows selected on-select cell . opts)
    (with-place 'list
      (lambda ()
        (let* (;; the scroll view's rect, its bar in a margin the content keeps
               [sx x] [sw w]
               [x (+ sx (ui-scrollbar-inset 'left))]
               [w (ui-table-room sw)]
               [columns (ui-table-columns ui id columns)]
               [left (ui-table-left columns w)]
               [hh (ui-table-header-height)] [rh (ui-table-row-height)]
               [sort (plist-ref opts 'sort #f)]
               [on-sort (plist-ref opts 'on-sort (lambda (k) #f))]
               [on-open (plist-ref opts 'on-open (lambda (r) #f))]
               [on-menu (plist-ref opts 'on-menu (lambda (r x y) #f))]
               [checked (plist-ref opts 'checked #f)]
               [on-check (plist-ref opts 'on-check (lambda (r) #f))]
               [doc (if (plist-ref opts 'on-menu #f)
                        '((L . "Select") (R . "Menu"))
                        '((L . "Select")))]
               ;; each column's flags, found once a draw
               [col-flags (map ui-column-flags columns)]
               ;; the checkboxes' lane, before the first cell
               [box (ui-checkbox-box)]
               [lane (if checked (+ (ui-table-cell-inset) box) 0)]
               [body (ui-id ui id 'body)] [view-h (max 0 (- h hh))]
               [i (and (plist-ref opts 'reveal #f)
                       (list-index (lambda (r) (eq? r selected)) rows))]
               [n (length rows)])
          (ui-table-headings! ui id sx sw x y hh columns left sort on-sort
                              (+ x lane) (plist-ref opts 'resize #f))
          (when i (ui-reveal! ui body (* i rh) (* (+ i 1) rh) view-h))
          (ui-memo! ui (ui-id ui id 'page)
                    (max 1 (exact (floor (/ view-h rh)))))
          (ui-scroll ui body sx (+ y hh) sw view-h
            (lambda (top)
              (let* ([vy (+ y hh)]
                     [first (max 0 (exact (floor (/ (- vy top) rh))))]
                     ;; one handler for every row, which a press finds by
                     ;; its place
                     [on (lambda (ev)
                           (and (eq? (car ev) 'press)
                                (let ([k (exact (floor (/ (- (caddr ev) top)
                                                          rh)))])
                                  (and (< -1 k n)
                                       (let ([row (list-ref rows k)])
                                         (case (list-ref ev 3)
                                           [(left)
                                            (on-select row)
                                            (when (>= (list-ref ev 4) 2)
                                              (on-open row))
                                            #t]
                                           [(right)
                                            (on-menu row (cadr ev) (caddr ev))
                                            #t]
                                           [else #f]))))))])
                (let loop ([i first]
                           [rs (if (< first n) (list-tail rows first) '())])
                  (unless (or (null? rs) (>= (+ top (* i rh)) (+ vy view-h)))
                    (let* ([row (car rs)] [ry (+ top (* i rh))]
                           [rid (ui-id ui id 'row i)]
                           [r (ui-region!* ui rid x ry w rh on #f
                                           (plist-ref opts 'tip #f) #f #f doc
                                           #f)]
                           [flags (ui-flags* ui rid (if (eq? row selected)
                                                        '(selected)
                                                        '()))])
                      (ui-region-item-set! r row)
                      (ui-draw-table-row x ry w rh flags)
                      (when checked
                        (let ([state (checked row)] [cid (ui-id ui id 'check i)]
                              [bx (+ x (ui-table-cell-inset))])
                          (unless (eq? state 'fixed)
                            (ui-pressable! ui cid (- bx 4) ry (+ box 8) rh
                                           (lambda () (on-check row)) '()
                                           '(focus keep) '((L . "Check"))))
                          (ui-draw-checkbox bx ry box rh
                                            (ui-flags* ui cid
                                                       (case state
                                                         [(fixed)
                                                          '(checked disabled)]
                                                         [(#f) '()]
                                                         [else '(checked)]))
                                            #f)))
                      (let cells ([cs columns] [fs col-flags] [cx x] [in lane])
                        (unless (null? cs)
                          (let ([cw (ui-table-width (car cs) (null? (cdr cs))
                                                    left)])
                            (cell row (caar cs) (+ cx in) ry (- cw in) rh
                                  (if (null? flags)
                                      (car fs)
                                      (append flags (car fs))))
                            (cells (cdr cs) (cdr fs) (+ cx cw) 0))))
                      (when (eq? row selected)
                        (ui-draw-highlight-over x ry w rh '())))
                    (loop (+ i 1) (cdr rs)))))
              (+ top (* n rh))))))))

  ;; Returns the new row index for a key, or #f for any other key: Up and
  ;; Down move by 1, Page Up and Page Down by page, Home goes to 0 and End to
  ;; n−1. From i #f, Down, Page Down and Home give 0, and the others n−1.
  ;; Returns #f when n is 0.
  (define (ui-table-step i n page key)
    (and (> n 0)
         (case key
           [(up) (if i (max 0 (- i 1)) (- n 1))]
           [(down) (if i (min (- n 1) (+ i 1)) 0)]
           [(page-up) (if i (max 0 (- i page)) (- n 1))]
           [(page-down) (if i (min (- n 1) (+ i page)) 0)]
           [(home) 0]
           [(end) (- n 1)]
           [else #f])))

  ;; Returns the rows per page of table id at its last draw.
  (define (ui-table-page ui id) (ui-memo ui (list id 'page) 1))

  ;; Returns the columns of table or tree id as it shows them: the app's
  ;; columns, with the width the user dragged in place of a column's
  ;; default. The kit keeps those widths while the window is open.
  (define (ui-table-columns ui id columns)
    (define (dragged c) (ui-memo ui (ui-id ui id 'width (car c)) #f))
    (if (exists dragged columns)
        (map (lambda (c)
               (let ([w (dragged c)])
                 (if w (cons* (car c) (cadr c) w (cdddr c)) c)))
             columns)
        columns))

  ;; Returns what the last of columns gets past its own width, so that the
  ;; headings and rows reach w: what the columns, in whole pixels, leave of
  ;; it, or 0.
  (define (ui-table-left columns w)
    (max 0 (- w (fold-left (lambda (sum c) (+ sum (ui-whole (caddr c)))) 0
                           columns))))

  ;; Returns column c's width as drawn, in whole pixels, so that what lies
  ;; in it is placed with no fractions to allocate; the last one (last?)
  ;; takes left too.
  (define (ui-table-width c last? left)
    (+ (ui-whole (caddr c)) (if last? left 0)))

  ;; Returns columns as drawn in w: when the widths the user dragged leave
  ;; room at the right, the last column takes it, so that the headings reach
  ;; the table's edge as its rows do.
  (define (ui-table-filled columns w)
    (let ([left (- w (apply + (map caddr columns)))])
      (if (or (null? columns) (<= left 0))
          columns
          (let ([c (car (last-pair columns))])
            (append (list-head columns (- (length columns) 1))
                    (list (cons* (car c) (cadr c) (+ (caddr c) left)
                                 (cdddr c))))))))

  ;; The narrowest the user can drag a column: two line heights.
  (define (ui-table-column-min) (exact (round (* 2 (font-line-height 'ui)))))

  ;; The handles of table or tree id: a few pixels on each line between two
  ;; of its headings, the first heading at x, h high. Dragging a handle sets
  ;; the width of the column to its left, in whole pixels, at least
  ;; ui-table-column-min. With resize pair, the width comes from the column
  ;; to its right, which keeps at least that width too; with shift, the
  ;; columns to its right move along. A double click sets their defaults
  ;; back.
  ;; How a style's tables resize (table-resize): pair, between two columns,
  ;; keeping the table's width; or shift, the Finder's and Explorer's way.
  (at-load
   (theme-default! 'table-resize 'pair))

  ;; When a table's column dividers show (table-dividers): always, faintly;
  ;; hover, while the pointer is over the headings; or handle, only the one
  ;; under the pointer. A divider under the pointer or being dragged always
  ;; shows, strongly.
  (at-load
   (theme-default! 'table-dividers 'hover))

  (define (ui-table-divider-shown? row-hover? hot?)
    (or hot?
        (case (theme 'table-dividers)
          [(always) #t]
          [(hover) row-hover?]
          [else #f])))

  (define (ui-table-handles! ui id x y h columns left sx sw resize)
    (define row-hover?
      (let ([win (current-window)])
        (and win
             (memq (window-hover win) '(content scrollbar))
             (ui-hover? ui sx y sw h))))
    (let loop ([cs columns] [cx x])
      (unless (or (null? cs) (null? (cdr cs)))
        (let* ([key (caar cs)] [cw (ui-table-width (car cs) #f left)]
               [line (+ cx cw)]
               [width (ui-id ui id 'width key)] [grab (ui-id ui id 'width-grab)]
               [pair? (eq? resize 'pair)]
               [next (ui-id ui id 'width (caadr cs))]
               [both (+ cw (ui-table-width (cadr cs) (null? (cddr cs)) left))]
               [hid (ui-id ui id 'handle key)])
          (ui-region!* ui hid (- line 3) y 6 h
            (lambda (ev)
              (case (car ev)
                [(press)
                 (and (eq? (list-ref ev 3) 'left)
                      (begin
                        (if (>= (list-ref ev 4) 2)
                            (begin
                              (hashtable-delete! (ui-state-memo ui) width)
                              (when pair?
                                (hashtable-delete! (ui-state-memo ui) next)))
                            (ui-memo! ui grab (- (cadr ev) line)))
                        #t))]
                [(drag)
                 (let* ([least (ui-table-column-min)]
                        [new (max least
                                  (exact (round (- (cadr ev) (ui-memo ui grab 0)
                                                   cx))))]
                        [new (if pair? (min new (- both least)) new)])
                   (and (< (cadddr ev) 2) (not (= new cw))
                        (begin
                          (ui-memo! ui width new)
                          (when pair? (ui-memo! ui next (- both new)))
                          #t)))]
                [else #f]))
            'keep #f 'resize-ew #f
            '((L . "Resize column") (L2 . "Default width")) #f)
          (let* ([flags (ui-flags* ui hid '())]
                 [hot? (or (memq 'hover flags) (memq 'pressed flags))])
            (when (ui-table-divider-shown? row-hover? hot?)
              (ui-draw-table-divider line y h flags)))
          (loop (cdr cs) line)))))

  ;; A column's flags, apart from its tooltip; and its tooltip (the string
  ;; among them), or #f.
  (define (ui-column-flags c) (filter symbol? (cdddr c)))
  (define (ui-column-tip c) (find string? (cdddr c)))

  ;; Draws the headings of table or tree id over columns from x, h high, cut
  ;; to its view sx sw, and their handles; a column's flags and its tooltip
  ;; are its heading's. With on-sort, a left press on a heading calls
  ;; (on-sort key), and the heading that sort names ((key . up|down), or #f)
  ;; shows its direction. The first title starts at title-x: a tree's starts
  ;; over its roots' cells.
  (define (ui-table-headings! ui id sx sw x y h columns left sort on-sort
                              title-x resize)
    (ui-with-clip ui (sx y sw h)
      (let loop ([cs columns] [cx x])
        (unless (null? cs)
          (let* ([key (caar cs)]
                 [cw (ui-table-width (car cs) (null? (cdr cs)) left)]
                 [hid (ui-id ui id 'header key)]
                 [tx (if (eq? cs columns) title-x cx)]
                 [flags (ui-column-flags (car cs))]
                 [tip (ui-column-tip (car cs))])
            (cond
              [on-sort
               (ui-region!* ui hid cx y cw h
                            (lambda (ev)
                              (and (eq? (car ev) 'press)
                                   (eq? (list-ref ev 3) 'left)
                                   (begin (on-sort key) #t)))
                            'keep tip #f #f '((L . "Sort")) #f)]
              [tip (ui-region!* ui hid cx y cw h #f #f tip #f #f '() #f)])
            (unless (= tx cx)
              (ui-draw-table-header cx y (- tx cx) h '() "" #f))
            (ui-draw-table-header tx y (- (+ cx cw) tx) h
                                  (if on-sort (ui-flags* ui hid flags) flags)
                                  (cadar cs)
                                  (and sort (eq? (car sort) key) (cdr sort)))
            (loop (cdr cs) (+ cx cw)))))
      (ui-table-handles! ui id x y h columns left sx sw
                         (or resize (theme 'table-resize)))))

  (at-load
   (theme-default! 'table-header-height
                   (theme-rule (round (+ (font-line-height 'ui-small) 13)))))
  (at-load
   (theme-default! 'table-row-height
                   (theme-rule (round (+ (font-line-height 'ui) 13)))))
  (define (ui-table-header-height) (theme 'table-header-height))
  (define (ui-table-row-height) (theme 'table-row-height))

  ;; Where a table's text starts in a cell, and in its heading: what a cell
  ;; draws itself starts there, so that it lines up under the heading.
  (define-part (ui-table-cell-inset) 10)

  ;; A cell's text, from the inset, cut to the cell (with right, a number at
  ;; the right, the inset short of the edge); its flags, its row's and its
  ;; column's, are a label's (dim, mono).
  (define-part (ui-draw-cell x y w h flags text)
    (let ([in (ui-table-cell-inset)])
      (ui-draw-label (+ x in) y (max 0 (- w in in)) h flags text)))

  ;; dir: up, down or #f (not sorted by this column). A heading lines up
  ;; with its column's cells: from the inset at the left, or up to it at the
  ;; right (flags right: numbers), with its sort arrow on its other side.
  (define-part (ui-draw-table-header x y w h flags label dir)
    (let* ([in (ui-table-cell-inset)]
           [sh (font-line-height 'ui-small)] [g (ui-small-glyph-size)]
           [s (text-fit label (max 0 (- w 16 g)) 'ui-small)]
           [color (if (or dir (memq 'hover flags)) 'text 'text-faint)]
           [right? (memq 'right flags)]
           [tx (if right? (- (+ x w) in (text-width s 'ui-small)) (+ x in))]
           [end (draw-text tx (+ y (/ (- h sh) 2)) s color 'ui-small)])
      (fill-box x (- (+ y h) 1) w 1 'window-border)
      (when dir
        (ui-draw-glyph (if right? (- tx 4 g) (+ end 4)) (+ y (/ (- h g) 2)) g g
                       '(hover) dir))))

  ;; The line between two headings at x, where a drag resizes the column on
  ;; its left: faint where the style shows it at rest (table-dividers), and
  ;; stronger under the pointer or while dragged (flags hover, pressed).
  (define-part (ui-draw-table-divider x y h flags)
    (if (or (memq 'hover flags) (memq 'pressed flags))
        (fill-box (- x 1) y 2 h 'accent)
        (fill-box x (+ y 5) 1 (- h 10) 'window-border)))

  (define-part (ui-draw-table-row x y w h flags)
    (cond [(memq 'selected flags) (fill-box x y w h 'selection)]
          [(memq 'hover flags) (fill-box x y w h 'bg-2)])
    (fill-box x (- (+ y h) 1) w 1 (alpha 'window-border 0.6)))

  ;;; ---------------------------------------------------------------- tree
  ;;; A tree of the app's values (nodes), given by its roots and a children
  ;;; procedure, shown as rows with columns, as a table is. The first
  ;;; column is indented by depth, with a twisty that expands and collapses
  ;;; a node that has children. The kit keeps which nodes are expanded, and
  ;;; the app which is selected. Children are asked for only of the nodes
  ;;; shown, and only the rows in view are drawn. Like the table, the tree
  ;;; takes no keyboard focus: the app passes it keys (ui-tree-key).

  ;; A row as shown: its node, its depth (0 for a root), its parent's row
  ;; index (#f for a root), whether the node has children, and whether they
  ;; show.
  (define-record-type ui-tree-row
    (nongenerative schevana-ui-tree-row-1)
    (fields node depth parent kids? expanded?))

  ;; Returns the rows shown, as a vector of ui-tree-row: each root and,
  ;; under each expanded node, its children, depth first. children: (lambda
  ;; (node) ...), returning a list, empty for a leaf; expanded?: (lambda
  ;; (node) ...). Pure.
  (define (ui-tree-rows roots children expanded?)
    (let ([acc '()] [n 0])
      (let walk ([nodes roots] [depth 0] [parent #f])
        (for-each (lambda (node)
                    (let* ([kids (children node)]
                           [open? (and (pair? kids) (expanded? node) #t)]
                           [i n])
                      (set! acc (cons (make-ui-tree-row node depth parent
                                                        (pair? kids) open?)
                                      acc))
                      (set! n (+ n 1))
                      (when open? (walk kids (+ depth 1) i))))
                  nodes))
      (list->vector (reverse acc))))

  ;; Returns the index of the row in rows whose node is equal? to node, or
  ;; #f.
  (define (ui-tree-index rows node)
    (let loop ([i 0])
      (cond [(= i (vector-length rows)) #f]
            [(equal? (ui-tree-row-node (vector-ref rows i)) node) i]
            [else (loop (+ i 1))])))

  ;; Whether row j of rows (#f: none) is under row i, at any depth. (A row's
  ;; parent comes before it.)
  (define (ui-tree-under? rows j i)
    (let up ([p (and j (ui-tree-row-parent (vector-ref rows j)))])
      (and p (>= p i)
           (or (= p i) (up (ui-tree-row-parent (vector-ref rows p)))))))

  ;; Returns what key does to rows (as ui-tree-rows makes them), with row i
  ;; selected (#f: none) and page rows to a page: (select . j),
  ;; (expand . i), (collapse . i), (open . i), or #f. Up, Down, Page Up,
  ;; Page Down, Home and End move as in a table; Right expands a node, or
  ;; goes to its first child; Left collapses it, or goes to its parent;
  ;; Space expands or collapses; Return opens. Pure.
  (define (ui-tree-step rows i page key)
    (let ([r (and i (vector-ref rows i))])
      (case key
        [(right) (and r (ui-tree-row-kids? r)
                      (if (ui-tree-row-expanded? r)
                          (cons 'select (+ i 1))
                          (cons 'expand i)))]
        [(left) (and r (if (ui-tree-row-expanded? r)
                           (cons 'collapse i)
                           (let ([p (ui-tree-row-parent r)])
                             (and p (cons 'select p)))))]
        [(#\space) (and r (ui-tree-row-kids? r)
                        (cons (if (ui-tree-row-expanded? r) 'collapse 'expand)
                              i))]
        [(return) (and r (cons 'open i))]
        [else (let ([j (ui-table-step i (vector-length rows) page key)])
                (and j (cons 'select j)))])))

  ;; Returns which nodes of tree id are expanded or collapsed, where that
  ;; differs from how they start: a hashtable the kit keeps.
  (define (ui-tree-states ui id)
    (or (ui-memo ui (list id 'expanded) #f)
        (let ([states (make-hashtable equal-hash equal?)])
          (ui-memo! ui (list id 'expanded) states)
          states)))

  ;; Expands node in tree id (on? #t) or collapses it, from its next draw.
  (define (ui-tree-expand! ui id node on?)
    (let ([states (ui-tree-states ui id)])
      (unless (eq? on? (hashtable-ref states node 'unset))
        (hashtable-set! states node on?)
        (ui-memo! ui (list id 'generation) #f)   ; its rows change
        (invalidate! (current-window)))))

  ;; Handles a key that the app's key handler passes to tree id, as the
  ;; tree's last draw showed it (see ui-tree-step): the selection moves by
  ;; (on-select node), and Return calls (on-open node). Returns true when it
  ;; acted. A tree that the last draw did not show (the app showed something
  ;; else instead) takes no key.
  (define (ui-tree-key ui id key mods selected on-select on-open)
    (let* ([rows (if (ui-find ui (list id 'body))
                     (ui-memo ui (list id 'rows) '#())
                     '#())]
           [act (and (null? mods)
                     (ui-tree-step rows (ui-tree-index rows selected)
                                   (ui-memo ui (list id 'page) 1) key))])
      (and act
           (let ([node (ui-tree-row-node (vector-ref rows (cdr act)))])
             (case (car act)
               [(select) (on-select node)]
               [(open) (on-open node)]
               [else (ui-tree-expand! ui id node (eq? (car act) 'expand))])
             #t))))

  ;; roots: the top nodes; children: (lambda (node) ...), returning a list.
  ;; columns: ((key title width flag ...) ...), as a table's, under a
  ;; header; the first column holds the tree. selected: the node equal? to
  ;; it is selected. A left press calls on-select, or, on a twisty, expands
  ;; or collapses the node. cell draws a cell: (lambda (node key x y w h
  ;; flags) ...), as a table's; the first column's cell comes after the
  ;; indentation and the twisty. opts: 'expanded (true when nodes start
  ;; expanded; else they start collapsed); 'on-open (node), called on a
  ;; double click; 'on-menu (node x y), on a right press; 'on-hide (node),
  ;; called when a collapse hides the selected row, with node, the collapsed
  ;; one, to be selected, as Left would (by default on-select); 'tip (node
  ;; w), its tooltip or #f, w being its first cell's width; 'reveal, which
  ;; when true scrolls the selected row into view; 'dim (node), true to dim
  ;; its row (the flag dim); 'sort, 'on-sort and 'resize, as a table's
  ;; (without 'on-sort the headings take no presses, and the app gives roots
  ;; and children in the order sort names); and 'generation, a value that
  ;; changes (eqv?) whenever roots or children would give other nodes, so
  ;; that the rows are kept until it changes or a node is expanded or
  ;; collapsed (without it, they are made at every draw).
  (define (ui-tree ui id x y w h columns roots children selected on-select cell
                   . opts)
    (with-place 'list
      (lambda ()
        (let* (;; the scroll view's rect, its bar in a margin the content keeps
               [sx x] [sw w]
               [x (+ sx (ui-scrollbar-inset 'left))]
               [w (ui-table-room sw)]
               [columns (ui-table-filled (ui-table-columns ui id columns) w)]
               [hh (ui-table-header-height)] [rh (ui-tree-row-height)]
               [tip (plist-ref opts 'tip (lambda (node w) #f))]
               [on-open (plist-ref opts 'on-open (lambda (node) #f))]
               [on-menu (plist-ref opts 'on-menu (lambda (node x y) #f))]
               [on-hide (plist-ref opts 'on-hide on-select)]
               [sort (plist-ref opts 'sort #f)]
               [on-sort (plist-ref opts 'on-sort #f)]
               [dim? (plist-ref opts 'dim (lambda (node) #f))]
               [start (plist-ref opts 'expanded #f)]
               [generation (plist-ref opts 'generation #f)]
               [states (ui-tree-states ui id)]
               [rows (if (and generation
                              (eqv? generation
                                    (ui-memo ui (list id 'generation) #f)))
                         (ui-memo ui (list id 'rows) #f)
                         (ui-tree-rows roots children
                                       (lambda (node)
                                         (hashtable-ref states node start))))]
               [n (vector-length rows)] [body (list id 'body)]
               [view-h (max 0 (- h hh))] [w0 (caddr (car columns))]
               [c0 (cdr (assq 'cell (ui-tree-areas x y w0 rh 0)))])
          (ui-memo! ui (list id 'rows) rows)
          (ui-memo! ui (list id 'generation) generation)
          ;; The first title starts over a root's cell.
          (ui-table-headings! ui id sx sw x y hh columns 0 sort on-sort (car c0)
                              (plist-ref opts 'resize #f))
          (when (plist-ref opts 'reveal #f)
            (let ([i (ui-tree-index rows selected)])
              (when i (ui-reveal! ui body (* i rh) (* (+ i 1) rh) view-h))))
          (ui-memo! ui (list id 'page) (max 1 (exact (floor (/ view-h rh)))))
          (ui-scroll ui body sx (+ y hh) sw view-h
            (lambda (top)
              (let ([vy (+ y hh)])
                (do ([i (max 0 (exact (floor (/ (- vy top) rh)))) (+ i 1)])
                    ((or (>= i n) (>= (+ top (* i rh)) (+ vy view-h))))
                  (let* ([r (vector-ref rows i)] [node (ui-tree-row-node r)]
                         [ry (+ top (* i rh))] [rid (list id 'row i)]
                         [areas (ui-tree-areas x ry w0 rh
                                               (ui-tree-row-depth r))]
                         [twisty (cdr (assq 'twisty areas))]
                         [c (cdr (assq 'cell areas))])
                    (ui-region! ui rid x ry w rh 'tip (tip node (caddr c))
                      'doc (if (plist-ref opts 'on-menu #f)
                               '((L . "Select or open") (R . "Menu"))
                               '((L . "Select or open")))
                      'on
                      (lambda (ev)
                        (and (eq? (car ev) 'press)
                             (case (list-ref ev 3)
                               [(left)
                                (if (and (ui-tree-row-kids? r)
                                         (apply point-in? (cadr ev) (caddr ev)
                                                twisty))
                                    (let ([open? (ui-tree-row-expanded? r)])
                                      (ui-tree-expand! ui id node (not open?))
                                      (when (and open?
                                                 (ui-tree-under?
                                                  rows
                                                  (ui-tree-index rows selected)
                                                  i))
                                        (on-hide node)))
                                    (begin
                                      (on-select node)
                                      (when (>= (list-ref ev 4) 2)
                                        (on-open node))))
                                #t]
                               [(right) (on-menu node (cadr ev) (caddr ev)) #t]
                               [else #f]))))
                    (let ([flags (apply ui-flags ui rid
                                        (append
                                         (if (equal? node selected)
                                             '(selected)
                                             '())
                                         (if (dim? node) '(dim) '())
                                         (if (ui-tree-row-kids? r) '(kids) '())
                                         (if (ui-tree-row-expanded? r)
                                             '(expanded)
                                             '())))])
                      (ui-draw-tree-row x ry w rh flags w0
                                        (ui-tree-row-depth r))
                      (cell node (caar columns) (car c) ry (caddr c) rh
                            (append flags (ui-column-flags (car columns))))
                      (let cells ([cs (cdr columns)] [cx (+ x w0)])
                        (unless (null? cs)
                          (cell node (caar cs) cx ry (caddr (car cs)) rh
                                (append flags (ui-column-flags (car cs))))
                          (cells (cdr cs) (+ cx (caddr (car cs))))))
                      (when (memq 'selected flags)
                        (ui-draw-highlight-over x ry w rh '())))))
                (+ top (* n rh)))))))))

  ;; A tree's rows are as high as a table's.
  (define (ui-tree-row-height) (ui-table-row-height))

  ;; Where a row at depth puts its twisty and its first cell, in its first
  ;; column x y w h, as ((twisty x y w h) (cell x y w h)): indented by a
  ;; twisty's width per level, but by at most half the column, so that a
  ;; deep row keeps room for its cell.
  (define-part (ui-tree-areas x y w h depth)
    (let* ([s (+ (ui-glyph-size) 8)]
           [in (min (* depth s) (max 0 (floor (/ (- w s) 2))))])
      (list (list 'twisty (+ x 4 in) y s h)
            (list 'cell (+ x 4 in s) y (max 0 (- w 4 in s)) h))))

  ;; A row's look: a table row's, with the twisty of a node with children
  ;; (flags kids, expanded) at its depth in its first column, w0 wide. With
  ;; dim, everything left of its first cell is dimmed, as the cells dim
  ;; themselves.
  (define-part (ui-draw-tree-row x y w h flags w0 depth)
    (let ([areas (ui-tree-areas x y w0 h depth)] [g (ui-glyph-size)])
      (ui-draw-table-row x y w h flags)
      (when (memq 'kids flags)
        (let ([t (cdr (assq 'twisty areas))])
          (ui-draw-glyph (+ (car t) (/ (- (caddr t) g) 2)) (+ y (/ (- h g) 2))
                         g g (if (memq 'hover flags) '(hover) '(quiet))
                         (if (memq 'expanded flags)
                             'chevron-down
                             'chevron-right))))
      (ui-draw-dim x y (- (cadr (assq 'cell areas)) x) h flags)))

  ;; A row that a view shows but leaves out (flags: dim; outside the app's
  ;; search, say), or a part of it, x y w h: shaded, unless it is selected.
  (define-part (ui-draw-dim x y w h flags)
    (when (and (memq 'dim flags) (not (memq 'selected flags)))
      (fill-box x y w h (alpha 'bg-0 0.6))))

  ;;; ---------------------------------------------------------------- rows
  ;;; A boxed list: rows in one box, with a line between two rows. Each row
  ;;; has a title, maybe a subtitle under it, and what the app draws at its
  ;;; end (a switch, a button, a value) or before its title (a check box);
  ;;; over the box go a group's title and what the group is for. GNOME's
  ;;; preferences are made of these. The rows are the app's data, as a
  ;;; form's are, and the box knows its height before it is drawn
  ;;; (ui-rows-height).
  ;;;
  ;;;   (ui-rows ui 'net x y w
  ;;;     (list (ui-switch-row ui 'wifi "Wi-Fi" on? set-on! 'subtitle "On")
  ;;;           (list "Proxy" "Manual" 0 #f 'on-press open-proxy!))
  ;;;     'title "Network"
  ;;;     'add (list "Add Network" add-network!))

  ;; rows: each is (title subtitle suffix-w suffix opt ...): title a string,
  ;; subtitle a string or #f, and suffix #f or a (lambda (x y w h) ...) that
  ;; draws what ends the row, in a place suffix-w wide. opts: 'on-press, a
  ;; thunk that a press, Space or Return on the row calls (the row then
  ;; shows the pointer on it); 'prefix-width and 'prefix, a place before the
  ;; title and what draws in it; 'body, a (lambda (x y w h) ...) that draws
  ;; the title's place itself (an entry row's field); 'key, what names the
  ;; row and its widgets, (id key) (by default its index); 'height; 'tip;
  ;; 'disabled; 'selected. ui-rows' own opts: 'title and 'description, a
  ;; heading over the box; 'add, (label thunk), a last row that adds one, as
  ;; the style makes it (ui-draw-add-row): a press, Space or Return on it
  ;; calls thunk, and its id is (id add). Returns the y below the box.
  (define (ui-rows ui id x y w rows . opts)
    (let* ([top (ui-rows-heading x y w (plist-ref opts 'title #f)
                                 (plist-ref opts 'description #f) #t)]
           [add (plist-ref opts 'add #f)]
           [hs (map ui-row-spec-height rows)]
           [rh (apply + hs)]
           [h (+ rh (if add (ui-add-row-height) 0))])
      (unless (and (null? rows) (not add))
        (ui-draw-rows x top w h '())
        ;; The rows are cut to the box's corners, then its edge is drawn
        ;; over them.
        (with-clip (x top w h (ui-rows-radius))
          (let loop ([rs rows] [hs hs] [ry top] [i 0])
            (unless (null? rs)
              (ui-row ui (list id (plist-ref (cddddr (car rs)) 'key i))
                      x ry w (car hs) (car rs) (= i 0)
                      (and (null? (cdr rs)) (not add)))
              (loop (cdr rs) (cdr hs) (+ ry (car hs)) (+ i 1))))
          (when add
            (ui-add-row ui (list id 'add) x (+ top rh) w (- h rh) (car add)
                        (cadr add) (null? rows))))
        (ui-draw-rows x top w h '(over)))
      (+ top h)))

  ;; Returns the height ui-rows takes at width w, with opts as ui-rows takes
  ;; them.
  (define (ui-rows-height w rows . opts)
    (+ (ui-rows-heading 0 0 w (plist-ref opts 'title #f)
                        (plist-ref opts 'description #f) #f)
       (apply + (map ui-row-spec-height rows))
       (if (plist-ref opts 'add #f) (ui-add-row-height) 0)))

  ;; The row that ends a box of rows and adds one, with rid its id: label,
  ;; and thunk, which a press, Space or Return on it calls.
  (define (ui-add-row ui rid x y w h label thunk first?)
    (ui-pressable! ui rid x y w h thunk '(#\space return) '() '((L . "Add")))
    (ui-draw-add-row x y w h
                     (apply ui-flags ui rid
                            (append (if first? '(first) '())
                                    '(last activatable)))
                     label))

  ;; Returns a row's height: its own 'height, or as tall as its title and
  ;; subtitle need.
  (define (ui-row-spec-height row)
    (or (plist-ref (cddddr row) 'height #f)
        (ui-row-height (car row) (cadr row))))

  ;; The heading over a box of rows, from y and w wide, drawn when draw?:
  ;; its title and its description, each if given. Returns the y the box
  ;; starts at.
  (define (ui-rows-heading x y w title description draw?)
    (if (not (or title description))
        y
        (let*-values ([(gap below) (ui-rows-spacing)]
                      [(tw th) (if title
                                   (ui-label-size '(group) title w)
                                   (values 0 0))]
                      [(dy) (if (and title description)
                                (+ y th gap)
                                (+ y th))]
                      [(dw dh) (if description
                                   (ui-label-size '(dim wrap) description w)
                                   (values 0 0))])
          (when draw?
            (when title (ui-draw-label x y w th '(group) title))
            (when description
              (ui-draw-label x dy w dh '(dim wrap) description)))
          (+ dy dh below))))

  ;; A row of ui-rows at x y w h, with rid its id: its region, its look,
  ;; then what it holds.
  (define (ui-row ui rid x y w h row first? last?)
    (let* ([title (car row)] [subtitle (cadr row)]
           [suffix (cadddr row)] [sw (if suffix (or (caddr row) 0) 0)]
           [opts (cddddr row)]
           [on-press (plist-ref opts 'on-press #f)]
           [prefix (plist-ref opts 'prefix #f)]
           [body (plist-ref opts 'body #f)]
           [areas (ui-row-areas x y w h
                                (if prefix (plist-ref opts 'prefix-width 0) 0)
                                sw)]
           [t (cdr (assq 'title areas))]
           [flags (ui-opt-flags opts '(disabled selected))])
      (if on-press
          (ui-pressable! ui rid x y w h on-press '(#\space return) opts
                         '((L . "Choose")))
          (ui-region! ui rid x y w h 'tip (plist-ref opts 'tip #f)))
      (ui-draw-row x y w h
                   (apply ui-flags ui rid
                          (append (if first? '(first) '())
                                  (if last? '(last) '())
                                  (if on-press '(activatable) '())
                                  flags))
                   (and (not body) title) (and (not body) subtitle)
                   (car t) (caddr t))
      (when prefix (apply prefix (cdr (assq 'prefix areas))))
      (when body (apply body t))
      (when suffix (apply suffix (cdr (assq 'suffix areas))))
      (when (memq 'selected flags) (ui-draw-highlight-over x y w h '()))))

  ;; A row whose switch says whether something is on (a switch row): a
  ;; press anywhere on the row switches it. opts: 'subtitle, and a row's.
  ;; Returns a row for ui-rows.
  (define (ui-switch-row ui id title on? on-change . opts)
    (let-values ([(tw th) (ui-toggle-track)])
      (cons* title (plist-ref opts 'subtitle #f) tw
             (lambda (x y w h)
               (ui-toggle ui (list id 'switch) x y w h #f on? on-change
                          'focus 'keep))
             'on-press (lambda () (on-change (not on?)))
             'key id
             opts)))

  ;; A row with a check box before its title (a check row): a press
  ;; anywhere on the row checks it or clears it. opts: 'subtitle, and a
  ;; row's. Returns a row for ui-rows.
  (define (ui-check-row ui id title checked? on-change . opts)
    (cons* title (plist-ref opts 'subtitle #f) 0 #f
           'prefix-width (ui-checkbox-box)
           'prefix (lambda (x y w h)
                     (ui-checkbox ui (list id 'check) x y w h #f checked?
                                  on-change 'focus 'keep))
           'on-press (lambda () (on-change (not checked?)))
           'key id
           opts))

  ;; A row that is a text field (an entry row): its title sits in the text's
  ;; place while the field is empty and does not have the keyboard, and
  ;; small over the text otherwise; a pencil at its end, while it does not
  ;; have the keyboard, says that it can be changed. id is the field's.
  ;; opts: the field's (except 'placeholder), and a row's. Returns a row for
  ;; ui-rows.
  (define (ui-entry-row ui id title text on-change . opts)
    (cons* title #f 0 #f
           'key id
           'body
           (lambda (x y w h)
             (let* ([lh (font-line-height 'ui)]
                    [sh (font-line-height 'ui-small)]
                    [g (ui-glyph-size)]
                    [focused? (equal? (ui-focused ui) id)]
                    [up? (or focused? (not (string=? text "")))]
                    [ty (+ y (/ (- h sh 2 lh) 2))]
                    [in (ui-text-box-inset '(field inner))]
                    [fw (if focused? w (- w g (ui-gap)))])
               ;; a press on the title gives the field the keyboard
               (ui-pressable! ui (list id 'title) x y w h
                              (lambda () (ui-focus! ui id)) '() '(focus keep))
               (if up?
                   (ui-draw-label x ty fw sh '(hint) title)
                   (ui-draw-label x y fw h '(dim) title))
               (unless focused?
                 (ui-draw-glyph (- (+ x w) g) (+ y (/ (- h g) 2)) g g
                                '(hover) 'edit))
               (apply ui-text-field ui id (- x in)
                      (if up? (- (+ ty sh 2) 4) y) (+ fw in)
                      (if up? (+ lh 8) h) text on-change 'inner #t
                      (plist-remove opts 'placeholder))))
           opts))

  ;; How far a heading's description is under its title, and how far the
  ;; box is under the heading.
  (define-part (ui-rows-spacing) (values 4 (ui-gap)))

  ;; A row's height for its title and subtitle (#f: none).
  (define-part (ui-row-height title subtitle)
    (max (+ (ui-control-height) 8)
         (round (+ 12 (font-line-height 'ui)
                   (if subtitle (+ 2 (font-line-height 'ui-small)) 0)))))

  ;; Where a row x y w h puts what it holds: ((prefix x y w h) (title ..)
  ;; (suffix ..)), with the prefix pw wide and the suffix sw wide (0: none),
  ;; the pad in from the box's sides, and a gap between them.
  (define-part (ui-row-areas x y w h pw sw)
    (let* ([m (ui-pad)] [g (ui-gap)]
           [tx (if (> pw 0) (+ x m pw g) (+ x m))]
           [sx (- (+ x w) m sw)]
           [te (if (> sw 0) (- sx g) (- (+ x w) m))])
      (list (list 'prefix (+ x m) y pw h)
            (list 'title tx y (max 0 (- te tx)) h)
            (list 'suffix sx y sw h))))

  ;; The height of the row that adds one.
  (define-part (ui-add-row-height) (ui-row-height "" #f))

  ;; The row that adds one: its flags are a row's, and a plus and its label
  ;; go where a row's title goes, in the accent, or as what can't be used.
  (define-part (ui-draw-add-row x y w h flags label)
    (let* ([t (cdr (assq 'title (ui-row-areas x y w h 0 0)))]
           [g (ui-glyph-size)] [lh (font-line-height 'ui)]
           [tx (car t)] [lx (+ tx g (ui-gap))])
      (ui-draw-row x y w h flags #f #f tx (caddr t))
      (ui-draw-glyph tx (+ y (/ (- h g) 2)) g g
                     (cons '(ink . accent)
                           (if (memq 'disabled flags) '(disabled) '()))
                     'plus)
      (draw-text lx (ui-text-y (+ y (/ (- h lh) 2)) 'ui)
                 (text-fit label (max 0 (- (+ tx (caddr t)) lx)) 'ui)
                 (if (memq 'disabled flags) 'text-disabled 'accent)
                 'ui)))

  ;; The corner radius of the box of rows.
  (define-part (ui-rows-radius) 8)

  ;; The box of rows: its fill under them (flags ()), and its edge over them
  ;; (over).
  (define-part (ui-draw-rows x y w h flags)
    (if (memq 'over flags)
        (stroke-box x y w h 'window-border 1 (ui-rows-radius))
        (fill-box x y w h 'bg-0 (ui-rows-radius))))

  ;; A row. flags: first, last (no line under it), activatable (a press
  ;; acts, so it shows the pointer), hover, pressed, focused, selected,
  ;; disabled. Its title and subtitle (each #f for none) go in tx..tx+tw.
  (define-part (ui-draw-row x y w h flags title subtitle tx tw)
    (let* ([on? (lambda (f) (memq f flags))]
           [lh (font-line-height 'ui)] [sh (font-line-height 'ui-small)]
           [th (if subtitle (+ lh 2 sh) lh)] [ty (+ y (/ (- h th) 2))]
           [ink (lambda (c) (if (on? 'disabled) 'text-disabled c))])
      (cond [(on? 'selected) (fill-box x y w h 'selection)]
            [(and (on? 'activatable) (on? 'pressed)) (fill-box x y w h 'bg-3)]
            [(and (on? 'activatable) (on? 'hover)) (fill-box x y w h 'bg-2)])
      (unless (on? 'last)
        (fill-box x (+ y h -1) w 1 'window-border))
      (when title
        (draw-text tx ty (text-fit title tw 'ui) (ink 'text) 'ui))
      (when subtitle
        (draw-text tx (+ ty lh 2) (text-fit subtitle tw 'ui-small)
                   (ink 'text-dim) 'ui-small))
      (when (on? 'focused)
        (ui-draw-focus (+ x 3) (+ y 3) (- w 6) (- h 6) flags 4)))))
