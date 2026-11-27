;;; (schevana kits ui pages) — a part of the ui kit ((schevana kits ui)),
;;; which gives its names: pages: boards, forms, the status page, banners
;;; and dialogs.

(library (schevana kits ui pages)
  (export
    ui-board-header-height ui-board-header-height* ui-board-column-insets
    ui-board-column-insets* ui-board-card-insets ui-board-card-insets*
    ui-draw-board-column ui-draw-board-column* ui-draw-board-slot
    ui-draw-board-slot* ui-draw-board-link ui-draw-board-link* ui-form
    ui-form-height ui-status-page ui-status-page-areas ui-status-page-areas*
    ui-draw-status-page ui-draw-status-page* ui-banner ui-banner-height
    ui-banner-height* ui-banner-areas ui-banner-areas* ui-draw-banner
    ui-draw-banner* ui-dialog ui-sheet ui-dialog-lines ui-dialog-size
    ui-dialog-size* ui-dialog-areas ui-dialog-areas* ui-draw-dialog
    ui-draw-dialog*)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-hook library-layer
                plist-ref)
          (only (schevana core) alpha current-window define-part draw-text
                fill-box font font-line-height invalidate! stroke-box
                text-width theme theme-default! with-place)
          (only (schevana kits text) text-draw-centered text-widest text-fit)
          (schevana kits ui base)
          (schevana kits ui controls))

  (library-layer kits)


  ;;; ---------------------------------------------------------------- boards
  ;;; A board is columns of cards side by side, as a kanban's: each column a
  ;;; well with a heading (a state's dot, its name and how many cards it
  ;;; holds) and its cards one under another, each with what links it to
  ;;; the next, and, while a card is dragged over a column, the slot where
  ;;; it would land. The app lays them out and handles the cards; these
  ;;; parts are their look and their room.

  (define-part (ui-board-header-height)
    (round (+ (font-line-height 'ui) 14)))

  ;; Inside a column: its cards' margin at either side, the room above the
  ;; first card and between two cards, and a heading button's distance from
  ;; the heading's end. A style that draws something between or beside the
  ;; cards (Cons's pointers) makes room for it.
  (define-part (ui-board-column-insets) (values 10 8 8 6))

  ;; The left and right insets of a column's cards: the column's side
  ;; margin, or the room a style's scroll bar keeps beside them (Genera's),
  ;; if that is more.
  (define-part (ui-board-card-insets)
    (let-values ([(side first between edge) (ui-board-column-insets)])
      (values (max side (ui-scrollbar-inset 'left))
              (max side (ui-scrollbar-inset 'right)))))

  ;; Draws a column's well and heading: a dot of color dot (none for #f),
  ;; label and count. flags: empty, when the column shows empty, the text
  ;; that says so, in its middle.
  (define-part (ui-draw-board-column x y w h flags label count dot empty)
    (let ([hh (ui-board-header-height)] [lh (font-line-height 'ui)]
          [sh (font-line-height 'ui-small)] [m (ui-mark-size)])
      (ui-draw-surface x y w h '(well))
      (let* ([dw (if dot
                     (ui-draw-mark (+ x 10) (+ y (/ (- hh m) 2)) m 'dot dot)
                     0)]
             [end (draw-text (if (> dw 0) (+ x 16 m) (+ x 10))
                             (+ y (/ (- hh lh) 2)) label 'text 'ui-bold)])
        (draw-text (+ end 8) (+ y (/ (- hh sh) 2)) (number->string count)
                   'text-faint 'ui-small))
      (when (memq 'empty flags)
        (text-draw-centered x (+ y hh) w (min 120 (- h hh)) empty
                            'text-faint 'ui))))

  ;; Where a dragged card would land.
  (define-part (ui-draw-board-slot x y w h)
    (fill-box x y w h (alpha 'accent 0.15) 8)
    (stroke-box x y w h 'accent 1 8))

  ;; Drawn after a card at x y w h, with its flags: what links it to the
  ;; next card, gap below it (Cons's pointer), or to nothing when it is the
  ;; last; by default, nothing.
  (define-part (ui-draw-board-link x y w h flags gap last?) (void))

  ;;; ---------------------------------------------------------------- form
  ;;; Rows of labeled controls: each label goes in a column as wide as the
  ;;; longest label needs, with its control beside it, or on a line of its
  ;;; own above the control when less than the control's least width would
  ;;; be left beside it. A row may say under its control what it means (a
  ;;; hint), or span the whole width (with no label: a list of choices, a
  ;;; table). The app draws the controls; the form places them and their
  ;;; labels, and knows its height before it is drawn (ui-form-height), as a
  ;;; sheet must.

  ;; rows: each is (label h place opt ...): label a string, or #f to span
  ;; the width; h the control's height, or a (lambda (w) ...) that returns
  ;; it at width w; place a (lambda (x y w) ...) that draws the control
  ;; there. opts: 'hint, words under the control; 'tip, the label's tooltip;
  ;; 'min, the least width the control takes beside its label (120 by
  ;; default). A row may instead be (section title): a group's heading over
  ;; the rows after it. Returns the y below the form.
  (define (ui-form ui id x y w rows)
    (ui-form-walk rows x y w
      (lambda (row inline? lx ly lw lh cx cy cw ch hint hh)
        (let ([label (car row)] [opts (cdddr row)])
          (when label
            (ui-draw-label lx ly lw lh '(dim) label)
            (let ([tip (plist-ref opts 'tip #f)])
              (when tip (ui-region! ui (list id 'label label) lx ly lw lh
                                    'tip tip))))
          ((caddr row) cx cy cw)
          (when hint (ui-draw-label cx (+ cy ch 4) cw hh '(hint wrap) hint))))
      (lambda (title sx sy sw sh)
        (ui-draw-label sx sy sw sh '(section) title))))

  (define (ui-form-height rows w)
    (ui-form-walk rows 0 0 w (lambda a #f) (lambda a #f)))

  ;; Lays rows out from (x, y), w wide, calling (row! row inline? label-x y
  ;; w h control-x y w h hint hint-h) and (section! title x y w h). Returns
  ;; the y below them.
  (define (ui-form-walk rows x y w row! section!)
    (let* ([gap (ui-gap)] [lh (font-line-height 'ui)]
           [labels (filter string? (map car rows))]
           [lw (if (null? labels) 0 (+ (text-widest labels 'ui) gap gap))])
      (let loop ([rs rows] [y y] [first? #t])
        (cond
          [(null? rs) (if first? y (- y gap))]
          [(eq? (caar rs) 'section)
           (let*-values ([(top) (if first? y (+ y gap))]
                         [(sw sh) (ui-label-size '(section) (cadar rs) w)])
             (section! (cadar rs) x top w sh)
             (loop (cdr rs) (+ top sh 6) #f))]
          [else
           (let* ([row (car rs)] [label (car row)] [opts (cdddr row)]
                  [inline? (and label
                                (>= (- w lw) (plist-ref opts 'min 120)))]
                  [cx (if inline? (+ x lw) x)]
                  [cw (if inline? (- w lw) w)]
                  [ch (let ([h (cadr row)]) (if (procedure? h) (h cw) h))]
                  [cy (if (and label (not inline?)) (+ y lh 4) y)]
                  [hint (plist-ref opts 'hint #f)]
                  [hh (if hint
                          (let-values ([(hw hh) (ui-label-size '(hint wrap) hint
                                                               cw)])
                            hh)
                          0)])
             ;; the label beside the control's first line, or above it
             (row! row inline? x y (if inline? (- lw gap) w)
                   (if inline? (min ch (ui-control-height)) lh)
                   cx cy cw ch hint hh)
             (loop (cdr rs)
                   (+ (max (+ cy ch (if hint (+ 4 hh) 0)) (+ y lh)) gap)
                   #f))]))))

  ;;; ---------------------------------------------------------- status page

  ;; What a view shows when it has nothing to show (an empty list, no
  ;; results), centered in x y w h: a large glyph, a title, what to do, and
  ;; maybe a button that does it. glyph: a name ui-draw-glyph knows, or a
  ;; (lambda (x y s flags) ...) that draws one s square; description: words
  ;; or #f. opts: 'compact (smaller, for a narrow pane), 'button (label
  ;; thunk), a pill under the words.
  (define (ui-status-page ui id x y w h glyph title description . opts)
    (let ([b (plist-ref opts 'button #f)]
          [flags (ui-opt-flags opts '(compact))])
      (ui-region! ui id x y w h)
      (ui-draw-status-page x y w h flags glyph title description
                           (and b (car b)))
      (when b
        (apply ui-button ui (list id 'button)
               (append (cdr (assq 'button
                                  (ui-status-page-areas x y w h flags title
                                                        description (car b))))
                       (list (car b) (cadr b) 'pill #t 'primary #t))))))

  ;; The font of a status page's title.
  (at-load
   (theme-default! 'status-title-font 'heading))

  ;; A status page's pieces in x y w h, as ((glyph x y s s) (title x y w h)
  ;; (description ..) (button ..)), with the block centered: the glyph over
  ;; the title, the description wrapped under it, and the button (when there
  ;; is a label) under that.
  (define-part (ui-status-page-areas x y w h flags title description label)
    (let*-values ([(s) (if (memq 'compact flags) 48 64)]
                  [(g) (ui-gap)]
                  [(tw) (max 0 (- w (* 2 (ui-pad))))]
                  [(tf) (theme 'status-title-font)]
                  [(th) (* (font-line-height tf)
                           (length (ui-label-lines title tw tf)))]
                  [(dh) (if description
                            (* (font-line-height 'ui)
                               (length (ui-label-lines description tw 'ui)))
                            0)]
                  [(bw bh) (if label (ui-button-size label #f) (values 0 0))]
                  [(bw) (if label (+ bw (* 2 (ui-pad))) 0)]
                  [(top) (+ y (max 0 (/ (- h (+ s g g th
                                                (if description (+ g dh) 0)
                                                (if label (+ g g bh) 0)))
                                        2)))]
                  [(ty) (+ top s g g)]
                  [(dy) (+ ty th g)]
                  [(by) (+ (if description (+ dy dh) (+ ty th)) g g)]
                  [(tx) (+ x (/ (- w tw) 2))])
      (list (list 'glyph (+ x (/ (- w s) 2)) top s s)
            (list 'title tx ty tw th)
            (list 'description tx dy tw dh)
            (list 'button (+ x (/ (- w bw) 2)) by bw bh))))

  ;; Draws text wrapped at w, each line centered in x..x+w, from y down.
  (define (ui-draw-centered-lines x y w text color font)
    (fold-left (lambda (ly line)
                 (draw-text (+ x (/ (- w (text-width line font)) 2))
                            (ui-text-y ly font) line color font)
                 (+ ly (font-line-height font)))
               y (ui-label-lines text w font)))

  ;; The glyph, faint, and the words, centered. label is the button's, whose
  ;; place the areas keep (the button draws itself).
  (define-part (ui-draw-status-page x y w h flags glyph title description
                                    label)
    (let* ([areas (ui-status-page-areas x y w h flags title description
                                        label)]
           [g (cdr (assq 'glyph areas))] [t (cdr (assq 'title areas))]
           [d (cdr (assq 'description areas))]
           [s (caddr g)] [tf (theme 'status-title-font)])
      (if (procedure? glyph)
          (glyph (car g) (cadr g) s '(dim))
          (ui-draw-glyph (car g) (cadr g) s s '((ink . text-faint)) glyph))
      (ui-draw-centered-lines (car t) (cadr t) (caddr t) title 'text tf)
      (when description
        (ui-draw-centered-lines (car d) (cadr d) (caddr d) description
                                'text-dim 'ui))))

  ;;; ---------------------------------------------------------------- banner

  ;; A strip across the top of a view that says something about it, with an
  ;; action at its end (a banner): title, and label and on-press for the
  ;; button (label #f for none). Returns its height.
  (define (ui-banner ui id x y w title label on-press)
    (let* ([h (ui-banner-height)]
           [b (assq 'button (ui-banner-areas x y w h title label))])
      (ui-region! ui id x y w h)
      (ui-draw-banner x y w h '() title label)
      (when label
        (apply ui-button ui (list id 'button)
               (append (cdr b) (list label on-press))))
      h))

  (define-part (ui-banner-height) (+ (ui-control-height) 12))

  ;; ((title x y w h) (button x y w h)): the button at the end (none without
  ;; a label), and the title centered in the strip where it fits, else at
  ;; the left of the room the button leaves.
  (define-part (ui-banner-areas x y w h title label)
    (let*-values ([(m) 6]
                  [(bw bh) (if label (ui-button-size label #f) (values 0 0))]
                  [(room) (- w m m (if label (+ bw m) 0))]
                  [(tw) (max 0 (min room (text-width title 'ui-bold)))]
                  [(tx) (max (+ x m) (+ x (/ (- w tw) 2)))]
                  [(tx) (if (> (+ tx tw) (+ x m room)) (+ x m) tx)])
      (list (list 'title tx y tw h)
            (list 'button (- (+ x w) m bw) (+ y (/ (- h bh) 2)) bw bh))))

  ;; The strip, with its title in its place; label is the button's.
  (define-part (ui-draw-banner x y w h flags title label)
    (let ([t (cdr (assq 'title (ui-banner-areas x y w h title label)))])
      (fill-box x y w h (alpha 'accent 0.15))
      (draw-text (car t) (+ y (/ (- h (font-line-height 'ui-bold)) 2))
                 (text-fit title (caddr t) 'ui-bold) 'text 'ui-bold)))

  ;;; ---------------------------------------------------------------- dialog

  ;; A modal dialog over the window, drawn at ui-end!. buttons: ((label
  ;; thunk flag ...) ...), right-aligned; the last is the default (Return),
  ;; unless it is disabled. Escape and a press outside call on-dismiss, and
  ;; so does a press on a dismiss area, where a style's areas have one
  ;; (Cons's nil). The dialog's flags carry its buttons' labels, (labels .
  ;; list), and the dismiss area's state, for a style whose dialog draws
  ;; around them.
  (define (ui-dialog ui id title message buttons on-dismiss)
    (ui-dialog-box ui id title message buttons on-dismiss #f))

  ;; Whether widget id f is under id: (id ...), or under one of those.
  (define (ui-under? f id)
    (and (pair? f) (or (equal? (car f) id) (ui-under? (car f) id))))

  ;; A sheet: a dialog whose body the app draws where a dialog's message
  ;; goes, between its title and its buttons: (body x y w), bw wide (or
  ;; wider, for the title and buttons) and bh high (a form's, say:
  ;; ui-form-height). The body's widgets take ids under id, (id ...) or
  ;; under those, and a widget elsewhere that has the keyboard loses it.
  (define (ui-sheet ui id title bw bh body buttons on-dismiss)
    (ui-dialog-box ui id title "" buttons on-dismiss (list bw bh body)))

  (define (ui-dialog-box ui id title message buttons on-dismiss sheet)
    (ui-later! ui
      (lambda (w h)
        (with-place 'dialog
          (lambda ()
            (let*-values ([(labels) (map car buttons)]
                          [(dw dh) (ui-dialog-size title message labels)]
                          ;; A sheet puts its body in the message's place,
                          ;; with the dialog's other parts around it as they
                          ;; are.
                          [(dw dh)
                           (if sheet
                               (let ([m (cdr (assq 'message
                                                   (ui-dialog-areas 0 0 dw dh
                                                                    labels)))])
                                 (values (max dw (+ (car sheet)
                                                    (- dw (caddr m))))
                                         (+ (cadr sheet) (- dh (cadddr m)))))
                               (values dw dh))]
                          [(dx dy) (values (max 0 (round (/ (- w dw) 2)))
                                           (max 0 (round (/ (- h dh) 2))))]
                          [(f) (ui-state-focus ui)]
                          [(areas) (ui-dialog-areas dx dy dw dh labels)]
                          [(dismiss) (assq 'dismiss areas)]
                          [(default) (car (last-pair buttons))])
              (unless (or (not f) (ui-under? f id))
                (ui-focus! ui #f)
                (invalidate! (current-window)))
              (ui-draw-scrim 0 0 w h '())
              (ui-region! ui id 0 0 w h 'modal #t 'focus 'keep
                'on (ui-modal-on on-dismiss
                      (lambda (key mods)
                        (and (eq? key 'return) (null? mods)
                             (not (memq 'disabled (cddr default)))
                             (begin ((cadr default)) #t)))))
              ;; The dialog's own panel takes a press that misses its
              ;; widgets, so that only a press outside it dismisses it.
              (ui-region! ui (list id 'inside) dx dy dw dh 'focus 'keep
                'on (lambda (ev) #t))
              (when dismiss
                (apply ui-pressable! ui (list id 'dismiss)
                       (append (cdr dismiss)
                               (list on-dismiss '() '(focus keep)
                                     '((L . "Cancel"))))))
              (ui-draw-dialog dx dy dw dh
                              (cons (cons 'labels labels)
                                    (ui-flags ui (list id 'dismiss)))
                              title message)
              (when sheet
                (let ([m (cdr (assq 'message areas))])
                  ((caddr sheet) (car m) (cadr m) (caddr m))))
              (for-each (lambda (b a i)
                          (apply ui-button ui (list id i)
                                 (append a (list (car b) (cadr b))
                                         (apply append
                                                (map (lambda (f) (list f #t))
                                                     (cddr b))))))
                        buttons
                        (map cdr (filter (lambda (a) (eq? (car a) 'button))
                                         areas))
                        (iota (length buttons)))))))))

  ;; Each button is at least 88 wide.
  (define (ui-dialog-button-widths labels)
    (map (lambda (l) (let-values ([(bw bh) (ui-button-size l #f)]) (max bw 88)))
         labels))

  ;; A dialog's message lines at width w: at most 6, so that a long message
  ;; keeps the dialog and its buttons small.
  (define (ui-dialog-lines message w)
    (let-values ([(lines cut?) (ui-wrap-lines message w 'ui 6)]) lines))

  ;; labels are the buttons' labels.
  (define-part (ui-dialog-size title message labels)
    (let* ([lh (font-line-height 'ui)]
           [bw (+ (apply + (ui-dialog-button-widths labels))
                  (* (ui-gap) (max 0 (- (length labels) 1))))]
           [w (clamp (+ 48 (max (text-width title 'heading)
                                (text-width message 'ui) bw))
                     360 (* 32 lh))])
      (values w
              (round (+ 24 (font-line-height 'heading) 8
                        (* lh (length (ui-dialog-lines message (- w 48))))
                        24 (ui-control-height) 20)))))

  ;; ((title x y w h) (message ..) (button x y w h) ...): one button per
  ;; label, right-aligned in the bottom row, a gap apart.
  (define-part (ui-dialog-areas x y w h labels)
    (let* ([hh (font-line-height 'heading)] [b (ui-control-height)]
           [gap (ui-gap)] [widths (ui-dialog-button-widths labels)]
           [by (- (+ y h) 20 b)])
      `((title ,(+ x 24) ,(+ y 24) ,(- w 48) ,hh)
        (message ,(+ x 24) ,(+ y 24 hh 8) ,(- w 48) ,(- h 24 hh 8 24 b 20))
        ,@(let loop ([ws widths]
                     [bx (- (+ x w -24) (apply + widths)
                            (* gap (max 0 (- (length widths) 1))))])
            (if (null? ws)
                '()
                (cons (list 'button bx by (car ws) b)
                      (loop (cdr ws) (+ bx (car ws) gap))))))))

  (define-part (ui-draw-dialog x y w h flags title message)
    (let* ([areas (ui-dialog-areas x y w h '())] [t (cdr (assq 'title areas))]
           [m (cdr (assq 'message areas))])
      (ui-draw-panel x y w h '(dialog))
      (draw-text (car t) (cadr t) (text-fit title (caddr t) 'heading) 'text
                 'heading)
      (fold-left (lambda (ly line) (draw-text (car m) ly line 'text-dim 'ui)
                   (+ ly (font-line-height 'ui)))
                 (cadr m) (ui-dialog-lines message (caddr m))))))
