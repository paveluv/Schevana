;;; (schevana kits ui text) — a part of the ui kit ((schevana kits ui)),
;;; which gives its names: text: the text field and area, the stepper,
;;; chips, dates, the dropdown, the date field and the calendar.

(library (schevana kits ui text)
  (export
    ui-date->day ui-day->date ui-days-in-month ui-today ui-month-names
    ui-date-label ui-next-midnight ui-stepper ui-text-box-top ui-text-box-areas
    ui-text-box-areas* ui-text-box-inset ui-text-box-size ui-text-box-size*
    ui-text-area-size ui-text-area-size* ui-text-field ui-text-area
    ui-draw-text-box* ui-draw-suggestion ui-draw-suggestion* ui-rank
    ui-suggestions ui-draw-chip ui-draw-chip* ui-chip-size ui-chip-size*
    ui-chip-areas ui-chip-areas* ui-chip-input ui-chip-input-areas
    ui-chip-input-areas* ui-chip-input-size ui-chip-input-size* ui-chips
    ui-chips-height ui-dropdown ui-draw-dropdown ui-draw-dropdown*
    ui-dropdown-size ui-dropdown-size* ui-date-field ui-calendar-size
    ui-calendar-size* ui-calendar-areas ui-calendar-areas* ui-draw-calendar
    ui-draw-calendar* ui-draw-day ui-draw-day*)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-hook library-layer
                list-index plist-ref string-prefix? string-split)
          (only (schevana core) *scale* alpha clipboard-get clipboard-set!
                current-window define-part draw-text fill-box focused-window
                font font-char-width font-line-height get-font now-ms
                stroke-box text-width theme theme-default! with-clip
                with-place)
          (only (schevana kits app) app-color)
          (only (schevana kits edit) edit-layout-text edit-range edit-move
                edit-line-bounds edit-select edit-word-bounds edit-key
                edit-clean edit-insert edit-erase edit-selection edit-index-at
                edit-layout-done? edit-layout-total edit-row-at edit-caret-x
                edit-at edit-all edit-anchor make-edit edit-change edit-text
                edit-row-last edit-row edit-layout-count edit-layout-extend!
                edit-layout-of edit-caret edit?)
          (only (schevana kits px) px-invert)
          (only (schevana kits text) text-draw-centered text-widest text-fit)
          (schevana kits ui base)
          (schevana kits ui controls))

  (library-layer kits)


  ;;; ------------------------------------------------------------------
  ;;; dates, pure: a date is (year month day), and a day number counts the
  ;;; days since 1970-01-01

  (define (ui-date->day d)
    (let* ([m (cadr d)] [y (if (<= m 2) (- (car d) 1) (car d))]
           [era (div y 400)] [yoe (- y (* era 400))]
           [doy (+ (quotient (+ (* 153 (mod (+ m 9) 12)) 2) 5) (- (caddr d) 1))]
           [doe (+ (* yoe 365) (quotient yoe 4) (- (quotient yoe 100)) doy)])
      (+ (* era 146097) doe -719468)))

  (define (ui-day->date n)
    (let* ([z (+ n 719468)] [era (div z 146097)] [doe (- z (* era 146097))]
           [yoe (quotient (- doe (quotient doe 1460) (- (quotient doe 36524))
                             (quotient doe 146096))
                          365)]
           [doy (- doe (+ (* 365 yoe) (quotient yoe 4) (- (quotient yoe 100))))]
           [mp (quotient (+ (* 5 doy) 2) 153)]
           [d (+ (- doy (quotient (+ (* 153 mp) 2) 5)) 1)]
           [m (if (< mp 10) (+ mp 3) (- mp 9))])
      (list (+ yoe (* era 400) (if (<= m 2) 1 0)) m d)))

  ;; 0 is Monday.
  (define (ui-week-day n) (mod (+ n 3) 7))

  (define (ui-days-in-month y m)
    (- (ui-date->day (if (= m 12) (list (+ y 1) 1 1) (list y (+ m 1) 1)))
       (ui-date->day (list y m 1))))

  ;; Returns day n moved by k months, its day of the month clamped to the
  ;; new month.
  (define (ui-add-months n k)
    (let* ([d (ui-day->date n)] [m0 (+ (cadr d) k -1)]
           [y (+ (car d) (div m0 12))] [m (+ 1 (mod m0 12))])
      (ui-date->day (list y m (min (caddr d) (ui-days-in-month y m))))))

  (define (ui-today)
    (let ([d (current-date)]) (list (date-year d) (date-month d) (date-day d))))

  ;; The months' short names.
  (define ui-month-names
    '#("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

  ;; A date's label: "Nov 14, 2026".
  (define (ui-date-label d)
    (format "~a ~a, ~a" (vector-ref ui-month-names (- (cadr d) 1)) (caddr d)
            (car d)))

  (define ui-month-titles
    '#("January" "February" "March" "April" "May" "June" "July" "August"
       "September" "October" "November" "December"))

  ;; The time, in ms, of the next local midnight.
  (define (ui-next-midnight)
    (let ([d (current-date)])
      (+ (now-ms)
         (* 1000 (- 86400 (* 3600 (date-hour d)) (* 60 (date-minute d))
                    (date-second d))))))

  ;; A whole number from lo to hi: a field that takes only digits, aligned
  ;; at its right as a table's numbers are, with a button on either side, or
  ;; both after it (ui-stepper-areas), each a step of 1, as Up and Down are.
  ;; What is typed counts at once if it is in range; if not, Return brings it
  ;; into range, and the field forgets it when it loses the keyboard. opts:
  ;; 'tip. Returns the stepper's width.
  (define (ui-stepper ui id x y value lo hi on-change . opts)
    (let-values ([(w h) (ui-stepper-size lo hi)])
      (let* ([tip (plist-ref opts 'tip #f)]
             [areas (ui-stepper-areas x y w h)]
             [area (lambda (k) (list-head (cdr (assq k areas)) 4))]
             [joins (lambda (k)
                      (apply append
                             (map (lambda (f) (list f #t))
                                  (list-tail (cdr (assq k areas)) 4))))]
             [glyphs (theme 'stepper-glyphs)]
             [field (list id 'field)] [typed (list id 'typed)]
             [step! (lambda (n)
                      (ui-memo! ui typed #f)
                      (on-change (clamp n lo hi)))])
        (unless (equal? (ui-focused ui) field) (ui-memo! ui typed #f))
        (apply ui-button ui (list id 'down)
               (append (area 'down)
                       (list #f (lambda () (step! (- value 1)))
                             'glyph (car glyphs) 'disabled (<= value lo)
                             'tip tip)
                       (joins 'down)))
        (apply ui-text-field ui field
               (append
                (area 'field)
                (list (or (ui-memo ui typed #f) (number->string value))
                      (lambda (text)
                        (when (ui-stepper-text? text lo)
                          (ui-memo! ui typed text)
                          (let ([n (string->number text)])
                            (when (and n (<= lo n hi)) (on-change n)))))
                      'tip tip
                      'right #t
                      'max (apply max
                                  (map (lambda (n)
                                         (string-length (number->string n)))
                                       (list lo hi)))
                      'on-enter (lambda ()
                                  (let ([n (string->number
                                            (or (ui-memo ui typed #f) ""))])
                                    (if n
                                        (step! n)
                                        (ui-memo! ui typed #f))))
                      'on-key (lambda (key mods text)
                                (and (null? mods) (memq key '(up down))
                                     (begin
                                       (step! (+ value
                                                 (if (eq? key 'up) 1 -1)))
                                       #t))))
                (joins 'field)))
        (apply ui-button ui (list id 'up)
               (append (area 'up)
                       (list #f (lambda () (step! (+ value 1)))
                             'glyph (cdr glyphs) 'disabled (>= value hi)
                             'tip tip)
                       (joins 'up)))
        w)))

  ;; Whether text, as it is typed, can become a number here: digits, after a
  ;; minus sign when the range goes below 0.
  (define (ui-stepper-text? text lo)
    (let ([chars (string->list text)])
      (for-all char-numeric?
               (if (and (< lo 0) (pair? chars) (char=? (car chars) #\-))
                   (cdr chars)
                   chars))))

  ;; A stepper's size: its two buttons, and a field whose text holds the
  ;; widest number and no more, inside the style's own insets, so that the
  ;; widest number fills it with the same room on either side, and a
  ;; narrower one sits at its right.
  (define (ui-stepper-size lo hi)
    (let ([b (ui-control-height)])
      (values (+ b b (ui-text-box-insets '(field))
                 (text-widest (map number->string (list lo hi)) 'ui))
              b)))

  ;;; ------------------------------------------------------------------
  ;;; text field and text area: one box, with one row or wrapped rows

  ;; Returns how far down a box h high its text starts: a field's one row
  ;; is centered, where a label beside it has its own; an area's rows,
  ;; however many, start margin down.
  (define (ui-text-box-top h flags font margin)
    (if (memq 'field flags)
        (max 0 (/ (- h (font-line-height font)) 2))
        margin))

  ;; Returns the box's inner rect and font, and where an area's scroll bar
  ;; goes (over its right padding, its thumb a pixel clear of a full row's
  ;; end), as ((edit tx ty tw th font) (bar x y w h)).
  (define-part (ui-text-box-areas x y w h flags)
    (let* ([left (if (memq 'search flags) (+ (ui-glyph-size) 14) 8)]
           [bw (ui-scrollbar-width)]
           [font (if (memq 'large flags) 'heading 'ui)]
           [top (ui-text-box-top h flags font 6)])
      (list (list 'edit (+ x left) (+ y top) (max 0 (- w left 8))
                  (max 0 (- h top top)) font)
            (list 'bar (+ x w 1 (- bw)) (+ y 3) bw (max 0 (- h 6))))))

  ;; Returns how far in from the box's left edge its text starts: a bare box
  ;; moved that much to the left lines its text up with what is above and
  ;; below it. A box's sizes, areas and drawing all belong to its place,
  ;; field.
  (define (ui-text-box-inset flags)
    (with-place 'field
      (lambda () (cadr (car (ui-text-box-areas 0 0 0 0 flags))))))

  ;; Returns how much of a box's width its text does not get: what the style
  ;; keeps on either side for its marks and margins.
  (define (ui-text-box-insets flags)
    (with-place 'field
      (lambda ()
        (- 100 (list-ref (car (ui-text-box-areas 0 0 100 0 flags)) 3)))))

  ;; Returns (values w h) for a box with rows of text.
  (define-part (ui-text-box-size flags w rows)
    (with-place 'field
      (lambda ()
        (let ([large? (memq 'large flags)])
          (values w
                  (if (and (= rows 1) (not large?))
                      (ui-control-height)
                      (round (+ 12 (* rows (font-line-height
                                            (if large? 'heading 'ui)))))))))))

  ;; Returns the rows of box id's text, tw wide in font (unwrapped for a
  ;; field). The kit keeps them, so that the layout pass and the frame share
  ;; them, and a draw computes only the rows it shows. When the text came
  ;; from the focused box's edit, the edit says where it changed, so that
  ;; the rows need not compare the texts. The rows measure in the font they
  ;; were laid out in (a click comes outside the box's place).
  (define (ui-text-layout ui id text tw font area?)
    (let* ([e (ui-edit ui)] [f (get-font font)]
           [lay (edit-layout-of (ui-memo ui (list id 'rows) #f) text
                                (and area? tw) (cons f *scale*)
                                (lambda (s) (text-width s f))
                                (and e (equal? (ui-state-focus ui) id)
                                     (eq? (edit-text e) text)
                                     (edit-change e)))])
      (ui-memo! ui (list id 'rows) lay)
      lay))

  ;; Returns the size of text area id: as tall as text wrapped at w needs,
  ;; within the row counts. Only the rows up to max-rows are computed, and
  ;; the box draws those.
  (define-part (ui-text-area-size ui id flags w text min-rows max-rows)
    (with-place 'field
      (lambda ()
        (let* ([a (car (ui-text-box-areas 0 0 w 0 flags))]
               [lay (ui-text-layout ui id text (list-ref a 3) (list-ref a 5)
                                    #t)])
          (edit-layout-extend! lay (- max-rows 1))
          (ui-text-box-size flags w
                            (clamp (edit-layout-count lay) min-rows
                                   max-rows))))))

  (define (ui-text-field ui id x y w h text on-change . opts)
    (with-place 'field
      (lambda () (ui-text-box ui id x y w h text on-change #f opts))))

  (define (ui-text-area ui id x y w h text on-change . opts)
    (with-place 'field
      (lambda () (ui-text-box ui id x y w h text on-change #t opts))))

  ;; Returns the focused text's edit of text: the kept edit, or one clamped
  ;; to text when the text changed elsewhere. A new focus puts the caret at
  ;; the end, or where ui-focus! said.
  (define (ui-text-edit ui text)
    (let* ([e (ui-state-edit ui)] [n (string-length text)]
           [e (cond [(edit? e)
                     (if (eq? (edit-text e) text)
                         e
                         (make-edit text (min (edit-caret e) n)
                                    (min (edit-anchor e) n) #f #f))]
                    [(eq? e 'all) (edit-all text)]
                    [(fixnum? e) (edit-at text e)]
                    [else (edit-at text n)])])
      (ui-state-edit-set! ui e)
      e))

  ;; opts: 'placeholder, 'tip, 'max (the most characters the text may
  ;; hold), 'on-enter (a thunk for Return), 'on-key ((lambda (key mods text)
  ;; ...), true when it acted), 'suggest and 'on-pick (below), and the flags
  ;; 'large, 'bare, 'search, 'single (an area whose Return is not a
  ;; newline), 'inner (inside another widget's box: never a box of its
  ;; own), 'right (a field's text at its right, while it fits), and
  ;; 'join-left and 'join-right (the box square on that side, where a
  ;; neighbor shares its edge, as in a stepper). An area of lines taller
  ;; than its box has a scroll bar.
  ;;
  ;; Suggestions: (suggest text) returns what the text may become, best
  ;; first (ui-suggestions ranks them); while the box has the keyboard, up
  ;; to 8 of them show in a list under it. Down and Up choose one, Return or
  ;; a click picks it, and Escape closes the list until the text changes. A
  ;; pick calls (on-pick s), which by default makes s the text.
  (define (ui-text-box ui id x y w h text on-change area? opts)
    (let* ([own (append (ui-opt-flags opts
                                      '(large bare search single inner right
                                        join-left join-right))
                        (if area? '() '(field))
                        ;; an area of lines: a box of its own, not a field
                        (if (and area? (not (plist-ref opts 'single #f)))
                            '(lines)
                            '()))]
           [areas (ui-text-box-areas x y w h own)]
           [a (car areas)] [tx (list-ref a 1)] [ty (list-ref a 2)]
           [tw (list-ref a 3)] [th (list-ref a 4)] [font (list-ref a 5)]
           [lh (font-line-height font)]
           [lines? (and area? (not (memq 'single own)))]
           [most (plist-ref opts 'max #f)]
           [on-key (plist-ref opts 'on-key #f)]
           [on-enter (plist-ref opts 'on-enter #f)]
           [lay (ui-text-layout ui id text tw font area?)]
           [e (and (equal? (ui-state-focus ui) id) (ui-text-edit ui text))]
           [suggest (plist-ref opts 'suggest #f)]
           [sid (list id 'suggest)]   ; (chosen . the text it closed at)
           [shown (and suggest e (current-window)
                       (eq? (current-window) (focused-window))
                       (not (equal? (cdr (ui-memo ui sid '(#f . #f))) text))
                       (let ([l (suggest text)])
                         (list-head l (min 8 (length l)))))]
           [chosen (let ([c (car (ui-memo ui sid '(#f . #f)))])
                     (and shown c (< c (length shown)) c))]
           [page (max 1 (exact (floor (/ th lh))))]
           ;; a text at the right is a text scrolled back past its start
           [room (if (and (memq 'right own) (not area?))
                     (- tw (edit-caret-x lay (string-length text)))
                     0)]
           [dx (cond [(> room 0) (- room)]
                     [(and e (not area?))
                      (max 0 (- (edit-caret-x lay (edit-caret e)) tw))]
                     [else 0])]
           [dy (if area?
                   (let* ([off (ui-memo ui id 0)]
                          [c (and e (edit-caret e))]
                          [moved? (and c
                                       (not (eqv? c (ui-memo ui (list id 'caret)
                                                               #f))))]
                          [off (cond
                                 [moved?
                                  (let ([top (* lh (edit-row-at lay c))])
                                    (min top (max off (- (+ top lh) th))))]
                                 ;; The focus left: back to the start.
                                 [(and (not c) (ui-memo ui (list id 'caret) #f))
                                  0]
                                 [else off])])
                     ;; the rows in view, and one more
                     (edit-layout-extend! lay
                                          (+ (exact (floor (/ (+ off th) lh)))
                                                 1))
                     (let ([off (clamp off 0 (max 0 (- (* lh (edit-layout-total
                                                              lay))
                                                       th)))])
                       (ui-memo! ui id off)
                       (ui-memo! ui (list id 'caret) c)
                       off))
                   (begin (edit-layout-extend! lay 0) 0))]
           [content (* lh (edit-layout-total lay))]
           ;; The bar shows an estimate: a scan is asked for even if the
           ;; caret's row, worked out below, brings the rows to the end, so
           ;; that the frame that finds them done draws the bar again.
           [estimate? (not (edit-layout-done? lay))]
           [max-dy (if area? (max 0 (- content th)) 0)]
           [bar? (and lines? (or (> max-dy 0)
                                 (and (theme 'scrollbar-full)
                                      (not (memq 'bare own)))))])
      (define (current) (ui-text-edit ui text))
      (define (index-at px py)
        (let ([r (max 0 (exact (floor (/ (- (+ py dy) ty) lh))))])
          (edit-layout-extend! lay r)
          (edit-index-at lay (min r (- (edit-layout-count lay) 1))
                         (- (+ px dx) tx))))
      ;; Whatever moves the caret, changes the text or acts on a key shows
      ;; the box: it asks to be scrolled into view at the next draw.
      (define (show!) (ui-state-reveal-set! ui (cons id #f)) #t)
      (define (apply! e2)
        (ui-state-edit-set! ui e2)
        (ui-state-blink-at-set! ui (now-ms))
        (unless (eq? (edit-text e2) text)
          (ui-memo! ui sid '(#f . #f))   ; the list starts over
          (on-change (edit-text e2)))
        (show!))
      (define (pick! s)
        (ui-memo! ui sid (cons #f s))
        ((plist-ref opts 'on-pick
                    (lambda (s) (apply! (edit-at s (string-length s)))))
         s)
        (show!))
      (define (key! key mods)
        (let ([e (current)])
          (cond
            [(and shown (pair? shown) (null? mods) (memq key '(up down)))
             (let ([n (length shown)] [down? (eq? key 'down)])
               (ui-memo! ui sid
                         (cons (cond [chosen (mod (+ chosen (if down? 1 -1)) n)]
                                     [down? 0]
                                     [else (- n 1)])
                               #f))
               (show!))]
            [(and chosen (null? mods) (eq? key 'return))
             (pick! (list-ref shown chosen))]
            [(and shown (pair? shown) (null? mods) (eq? key 'escape))
             (ui-memo! ui sid (cons #f text))
             #t]
            [(and on-key (on-key key mods (edit-text e))) (show!)]
            [(and (equal? mods '(ctrl)) (memv key '(#\c #\x #\v)))
             (let ([s (edit-selection e)])
               (case key
                 [(#\c) (unless (string=? s "") (clipboard-set! s)) #t]
                 [(#\x) (unless (string=? s "")
                          (clipboard-set! s)
                          (apply! (edit-erase e 0)))
                        #t]
                 [else (apply! (edit-insert
                                e (edit-clean (clipboard-get) lines?) most))]))]
            [(eq? key 'return)
             (cond [lines? (apply! (edit-insert e "\n" most))]
                   [on-enter (on-enter) (show!)]
                   [else #f])]
            [(edit-key e key mods lay page)
             => (lambda (e2)
                  ;; Page Up and Page Down scroll the view as many rows as
                  ;; they move the caret, so the caret keeps its place in it.
                  (when (and area? (memq key '(page-up page-down)))
                    (ui-memo! ui id (max 0 (+ (ui-memo ui id 0)
                                              (* lh (if (eq? key 'page-up)
                                                        (- page)
                                                        page))))))
                  (apply! e2))]
            [else #f])))
      ;; When asked to be shown, a focused box names its caret's row, where
      ;; the typing goes, for a scroll view too short to show all of it; on
      ;; its first and last rows, the box's edges come along.
      (let ([rv (ui-state-reveal ui)])
        (when (and e rv (equal? (car rv) id))
          (let* ([r (edit-row-at lay (edit-caret e))]
                 [top (- (+ (- ty y) (* r lh)) dy)]
                 [last? (begin (edit-layout-extend! lay (+ r 1))
                               (>= (+ r 1) (edit-layout-count lay)))])
            (ui-state-reveal-set!
             ui (cons id (cons (if (= r 0) 0 top) (if last? h (+ top lh))))))))
      (ui-region! ui id x y w h 'focus 'click 'cursor 'ibeam
        'tip (plist-ref opts 'tip #f)
        'doc (plist-ref opts 'doc '((L . "Place the caret")
                                     (L2 . "Select a word")
                                     (R . "Copy, Paste")))
        'on (lambda (ev)
              (case (car ev)
                [(press)
                 (case (list-ref ev 3)
                   [(left)
                    (let ([i (index-at (cadr ev) (caddr ev))])
                      (apply!
                       (case (list-ref ev 4)
                         [(1) (edit-at text i)]
                         [(2) (let-values ([(lo hi) (edit-word-bounds text i)])
                                (edit-select (current) lo hi))]
                         [else (let-values ([(lo hi) (edit-line-bounds text
                                                                       i)])
                                 (edit-select (current) lo hi))])))]
                   ;; the text menu, on what is selected; a press outside
                   ;; the selection places the caret first
                   [(right)
                    (let ([i (index-at (cadr ev) (caddr ev))])
                      (let-values ([(lo hi) (edit-range (current))])
                        (unless (and (< lo hi) (<= lo i) (< i hi))
                          (apply! (edit-at text i))))
                      (ui-open-text-menu!
                       ui (cadr ev) (caddr ev) (edit-selection (current))
                       (lambda (s)
                         (apply! (edit-insert (current) (edit-clean s lines?)
                                              most))))
                      #t)]
                   [else #f])]
                [(drag)
                 (and (eqv? (cadddr ev) 1)
                      (apply! (edit-move (current)
                                         (index-at (cadr ev) (caddr ev)) #t)))]
                [(key) (key! (cadr ev) (caddr ev))]
                [(text) (apply! (edit-insert
                                 (current) (edit-clean (cadr ev) lines?) most))]
                [(wheel)
                 (and (> max-dy 0)
                      (let* ([old (ui-memo ui id 0)]
                             [new (clamp (- old (* (cadr ev) (ui-scroll-step)))
                                         0 max-dy)])
                        (and (not (= new old))
                             (begin (ui-memo! ui id new) #t))))]
                [else #f])))
      (let* ([base (apply ui-flags ui id own)]
             [flags (append base
                            (if (and (memq 'focused base) (ui-caret-on? ui))
                                '(caret)
                                '())
                            (if (string=? text "") '(placeholder) '()))])
        (let-values ([(lo hi) (if (and e (memq 'focused base))
                                  (edit-range e)
                                  (values 0 0))])
          (ui-draw-text-box x y w h flags lay lo hi (if e (edit-caret e) 0) dx
                            dy
                            (plist-ref opts 'placeholder #f))))
      (when (and shown (pair? shown))
        (ui-later! ui
          (lambda (ww wh)
            (with-place 'field
              (lambda ()
                (ui-suggestion-list ui id x y w h shown chosen pick! ww wh))))))
      ;; The bar's total is an estimate until the window's frames finish the
      ;; rows.
      (when bar?
        (when estimate?
          (ui-state-scans-set! ui (cons lay (ui-state-scans ui))))
        (let ([bar (cdr (cadr areas))] [asked (list id 'asked)])
          ;; the bar's thumb is asked for by the pointer coming to it, and
          ;; holds until the text changes in size: a style may show none
          ;; before (ZWEI's, flag unasked)
          (when (or (apply ui-hover? ui bar) (ui-active? ui (list id 'bar)))
            (ui-memo! ui asked (string-length text)))
          (apply ui-scrollbar ui (list id 'bar)
                 (append bar
                         (list dy content th
                               (lambda (off) (ui-memo! ui id off))
                               'flags
                               (if (eqv? (ui-memo ui asked #f)
                                         (string-length text))
                                   '()
                                   '(unasked)))))))))

  ;; lay is the text's rows (an edit-layout), with those in view computed;
  ;; [lo, hi) is the selection; dx and dy are how far the text is scrolled.
  (define-part (ui-draw-text-box x y w h flags lay lo hi caret dx dy
                                 placeholder)
    (let* ([a (car (ui-text-box-areas x y w h flags))]
           [tx (list-ref a 1)] [ty (list-ref a 2)] [tw (list-ref a 3)]
           [th (list-ref a 4)] [font (list-ref a 5)]
           [lh (font-line-height font)] [text (edit-layout-text lay)]
           [measure (lambda (s) (text-width s font))]
           [focused? (memq 'focused flags)] [hover? (memq 'hover flags)])
      (unless (or (memq 'inner flags)
                  (and (memq 'bare flags) (not hover?) (not focused?)))
        (ui-draw-field x y w h flags))
      (when (memq 'search flags)
        (let ([s (+ (ui-glyph-size) 2)])
          (ui-draw-glyph (+ x 7) (+ y (/ (- h s) 2)) s s '(quiet) 'search)))
      ;; The clip is the edit rect and 2 px on either side for the caret, so
      ;; a scrolled row never shows in the padding. Scrolled sideways, the
      ;; caret is at the right, so the left margin is dropped.
      (with-clip ((if (> dx 0) tx (- tx 2)) ty (+ tw (if (> dx 0) 2 4)) th)
        (if (memq 'placeholder flags)
            (when placeholder
              (draw-text tx (ui-text-y ty font) (text-fit placeholder tw font)
                         (theme 'text-placeholder-color) font))
            ;; only the rows in view
            (let loop ([r (max 0 (- (exact (floor (/ dy lh))) 1))])
              (let ([ry (- (+ ty (* r lh)) dy)] [rx (- tx dx)])
                (when (and (< r (edit-layout-count lay)) (< (+ ry 1) (+ ty th)))
                  ;; A row at most a pixel into view would show only the
                  ;; tips of its descenders, so it is skipped.
                  (when (> (+ ry lh) (+ ty 1))
                    (let-values ([(s e) (edit-row lay r)])
                      (when (and (< lo hi) (< lo (max e (+ s 1))) (> hi s))
                        (let* ([x0 (measure (substring text s (max s lo)))]
                               [x1 (if (> hi e)
                                       (+ (measure (substring text s e)) 4)
                                       (measure (substring text s hi)))])
                          (if (eq? (theme 'text-selection) 'underline)
                              (fill-box (+ rx x0) (+ ry lh -1) (- x1 x0) 1
                                        'text)
                              (fill-box (+ rx x0) ry (- x1 x0) lh
                                        'selection))))
                      ;; Unfocused and scrolled to its start, the box's last
                      ;; row in view says that more follows.
                      (draw-text rx (ui-text-y ry font)
                                 (if (and (not focused?) (= dy 0)
                                          (or (< (+ r 1)
                                                 (edit-layout-count lay))
                                              (not (edit-layout-done? lay)))
                                          (> (+ ry lh lh) (+ ty th 1)))
                                     (text-fit
                                      (string-append
                                       (substring text s (edit-row-last lay r))
                                       "…")
                                      tw font)
                                     (substring text s e))
                                 (if (memq 'disabled flags)
                                     'text-disabled
                                     'text)
                                 font)))
                  (loop (+ r 1))))))
        (when (memq 'caret flags)
          (let ([cx (+ (- tx dx) (edit-caret-x lay caret))]
                [cy (- (+ ty (* lh (edit-row-at lay caret))) dy)])
            (if (eq? (theme 'text-caret) 'block)
                (px-invert cx cy (ui-caret-block-width text caret font) lh)
                (let ([cw (theme 'text-caret-width)])
                  (fill-box (- cx (/ cw 2)) cy cw lh
                            (theme 'text-caret-color)))))))))

  ;; How the text's caret and selection show: a bar and a fill (bar, fill),
  ;; or, as the Lisp machines showed them, a block in reverse video over the
  ;; character and an underline (block, underline).
  (at-load
   (theme-default! 'text-caret 'bar))
  (at-load
   (theme-default! 'text-selection 'fill))
  ;; A bar caret's width and color, and a placeholder's color.
  (at-load
   (theme-default! 'text-caret-width 2))
  (at-load
   (theme-default! 'text-caret-color 'accent))
  (at-load
   (theme-default! 'text-placeholder-color 'text-faint))

  ;; A block caret is as wide as the character under it; at the end of the
  ;; text or of a line, it is the font's own character width.
  (define (ui-caret-block-width text i font)
    (if (and (< i (string-length text))
             (not (char=? (string-ref text i) #\newline)))
        (text-width (string (string-ref text i)) font)
        (font-char-width font)))

  ;; Draws the suggestions under box id at x y w h (above it when there is
  ;; no room below), in a window ww × wh: each is a row that a press picks.
  (define (ui-suggestion-list ui id x y w h shown chosen pick! ww wh)
    (let*-values ([(rh) (ui-suggestion-row-height)] [(pad) 4]
                  [(lh) (+ pad pad (* rh (length shown)))]
                  [(lx ly) (ui-popup-place x (+ y h 2) (- y 2) w lh ww wh)])
      (ui-draw-panel lx ly w lh '(menu))
      (for-each
       (lambda (s i)
         (let ([rid (list id 'suggestion i)] [ry (+ ly pad (* i rh))])
           (ui-pressable! ui rid lx ry w rh (lambda () (pick! s)) '()
                          '(focus keep) '((L . "Pick")))
           (ui-draw-suggestion (+ lx pad) ry (- w pad pad) rh
                               (apply ui-flags ui rid
                                      (if (eqv? i chosen) '(selected) '()))
                               s)))
       shown (iota (length shown)))))

  (define (ui-suggestion-row-height) (round (+ (font-line-height 'ui) 8)))

  ;; A suggestion's row. flags: selected (chosen by the keyboard), hover,
  ;; disabled.
  (define-part (ui-draw-suggestion x y w h flags label)
    (let ([on? (or (memq 'selected flags) (memq 'hover flags))])
      (when on? (ui-draw-highlight x y w h (if (memq 'selected flags)
                                               '()
                                               '(hover))))
      (draw-text (+ x 8) (+ y (/ (- h (font-line-height 'ui)) 2))
                 (text-fit label (- w 16) 'ui)
                 (cond [(memq 'disabled flags) 'text-disabled]
                       [on? 'text]
                       [else 'text-dim])
                 'ui)
      (when (memq 'selected flags) (ui-draw-highlight-over x y w h '()))))

  ;; Returns the choices ((name . detail) ...) that typed matches, best
  ;; first, as a vector of (name detail positions); first? says whether a
  ;; name goes first among equals. The completion kit ((schevana kits
  ;; complete)) sets this hook to its ranking by segments; until it does,
  ;; the names that begin with typed match.
  (define-hook (ui-rank typed choices first?)
    (list->vector
     (map (lambda (c) (list (car c) (cdr c) '()))
          (filter (lambda (c) (string-prefix? typed (car c))) choices))))

  ;; Returns the choices (strings) that typed matches, best first, at most
  ;; n, in the ranking's order (ui-rank), by segments ("dtc" finds
  ;; draw-text-centered). Returns none when nothing is typed, or when typed
  ;; itself is the only match.
  (define (ui-suggestions typed choices n)
    (if (string=? typed "")
        '()
        (let* ([ranked (ui-rank typed (map (lambda (c) (cons c #f)) choices)
                                (lambda (c) #f))]
               [names (map car (vector->list ranked))])
          (if (equal? names (list typed))
              '()
              (list-head names (min n (length names)))))))

  ;;; ---------------------------------------------------------------- chips

  ;; A tag: a pill whose hue comes from its label, so that a tag keeps its
  ;; color everywhere. The flag removable adds a ×, which turns red under the
  ;; pointer.
  (define-part (ui-draw-chip x y w h flags label)
    (let* ([sh (font-line-height 'ui-small)] [r (/ h 2)]
           [g (ui-small-glyph-size)] [removable? (memq 'removable flags)]
           [hue (app-color (string->symbol label))])
      (fill-box x y w h (alpha hue (if (memq 'disabled flags) 0.08 0.18)) r)
      (draw-text (+ x 8) (+ y (/ (- h sh) 2))
                 (text-fit label (- w 16 (if removable? (+ g 4) 0)) 'ui-small)
                 (if (memq 'disabled flags) 'text-disabled 'text) 'ui-small)
      (when removable?
        (let ([a (cdr (assq 'remove (ui-chip-areas x y w h)))])
          (ui-draw-glyph (+ (car a) (/ (- (caddr a) g) 2))
                         (+ (cadr a) (/ (- (cadddr a) g) 2)) g g
                         (if (memq 'hover flags) '(danger hover) '())
                         'cross)))))

  ;; A chip's size: its text 8 in from either end, and, when removable, a ×
  ;; after it.
  (define-part (ui-chip-size label removable?)
    (values (+ 16 (text-width label 'ui-small)
               (if removable? (+ (ui-small-glyph-size) 4) 0))
            (round (+ (font-line-height 'ui-small) 8))))

  (define-part (ui-chip-areas x y w h)
    (let ([g (ui-small-glyph-size)])
      (list (list 'remove (- (+ x w) g 10) y (+ g 6) h))))

  ;; Chips (removable) and a field to type more, wrapped in one box. The
  ;; draft is the field's text; a comma or Return adds it (Return with
  ;; nothing but spaces typed is left to others), and Backspace in an empty
  ;; field removes the last chip. on-add gets a list: the draft, or a
  ;; paste's comma-separated parts all at once. opts: 'placeholder, and
  ;; 'suggest, as a text field's; a pick adds the suggestion. Returns the
  ;; box's bottom. The box's flags say that it holds chips, the last chip's
  ;; that it is last, and every other chip's where the next one starts,
  ;; (next x y), so that a style that draws the chips as a list knows where
  ;; the list ends and where it wraps.
  (define (ui-chip-input ui id x y w chips draft on-draft on-add on-remove
                         . opts)
    (with-place 'field
      (lambda ()
        (let* ([areas (ui-chip-input-areas x y w chips)]
               [field (cdr (assq 'field areas))]
               [bottom (+ (cadr field) (cadddr field))]
               [fid (list id 'field)] [n (length chips)]
               [chip-areas (map cdr (filter (lambda (a) (eq? (car a) 'chip))
                                            areas))])
          (ui-draw-field x y w (- bottom y) (ui-flags ui fid 'chips))
          (for-each
           (lambda (chip a i)
             (let ([rid (list id 'remove i)]
                   [r (cdr (assq 'remove (apply ui-chip-areas a)))])
               (ui-pressable! ui rid (car r) (cadr r) (caddr r) (cadddr r)
                              (lambda () (on-remove i)) '()
                              '(focus keep tip "Remove") '((L . "Remove")))
               (apply ui-draw-chip
                      (append a (list (apply ui-flags ui rid 'removable
                                             (ui-chain-flags chip-areas i))
                                      chip)))))
           chips chip-areas
           (iota (length chips)))
          (apply ui-text-field ui fid
                 (append field
                         (list draft
                               (lambda (s)
                                 (let ([parts (string-split s #\,)])
                                   (when (pair? (cdr parts))
                                     (on-add (list-head parts
                                                        (- (length parts) 1))))
                                   (on-draft (car (last-pair parts)))))
                               'inner #t
                               'placeholder (plist-ref opts 'placeholder #f)
                               'suggest (plist-ref opts 'suggest #f)
                               'on-pick (lambda (s) (on-add (list s))
                                          (on-draft ""))
                               'on-key
                               (lambda (key mods text)
                                 (cond
                                   [(and (eq? key 'return) (null? mods)
                                         (exists (lambda (c)
                                                   (not (char-whitespace? c)))
                                                 (string->list text)))
                                    (on-add (list text)) (on-draft "") #t]
                                   [(and (eq? key 'backspace) (string=? text "")
                                         (pair? chips))
                                    (on-remove (- (length chips) 1)) #t]
                                   [else #f])))))
          bottom))))

  ;; Returns a chain's flags for the i-th element of areas ((x y w h) ...):
  ;; last, or where the next one starts, (next x y).
  (define (ui-chain-flags areas i)
    (if (= i (- (length areas) 1))
        '(last)
        (let ([b (list-ref areas (+ i 1))])
          (list (list 'next (car b) (cadr b))))))

  ;; Where a chip input at (x, y), w wide, puts its chips and its field:
  ;; ((chip x y w h) ... (field x y w h)), flowed in rows of a control's
  ;; height, 4 apart and 4 in from the sides. The field takes the rest of
  ;; the last row, or a row of its own when less than 8 line heights of
  ;; width is left.
  (define-part (ui-chip-input-areas x y w chips)
    (let*-values ([(pad ch) (values 4 (ui-control-height))]
                  [(sizes) (map (lambda (c)
                                  (call-with-values
                                    (lambda () (ui-chip-size c #t))
                                    cons))
                                chips)]
                  [(at height)
                   (ui-flow (+ x pad) y (- w pad pad) pad
                            (append (map (lambda (s) (cons (car s) ch)) sizes)
                                    (list (cons (min (- w pad pad)
                                                     (* 8
                                                        (font-line-height 'ui)))
                                                ch))))])
      (let ([f (list-ref at (length chips))])
        (append (map (lambda (s p)
                       (list 'chip (car p)
                             (+ (cdr p) (floor (/ (- ch (cdr s)) 2)))
                             (car s) (cdr s)))
                     sizes (list-head at (length chips)))
                (list (list 'field (car f) (cdr f) (- (+ x w) pad (car f))
                            ch))))))

  ;; Returns the box's height for chips at width w.
  (define-part (ui-chip-input-size w chips)
    (let ([f (cdr (assq 'field (ui-chip-input-areas 0 0 w chips)))])
      (+ (cadr f) (cadddr f))))

  ;; Chips in rows from (x, y), w wide, each row a control's height: a
  ;; left press on chip i calls (on-press i) (with on-press #f, they take no
  ;; press). opts: 'on-remove (i), for a × on each; 'add, a thunk, and
  ;; 'add-label ("Add" by default), for a button after them; 'empty, the
  ;; words shown when there are none and no add ("None" by default); 'tip
  ;; (i), a chip's tooltip; 'keys, what names each chip's widgets, (id key)
  ;; and (id remove key) (by default its index). Returns the y below them.
  (define (ui-chips ui id x y w labels on-press . opts)
    (let* ([on-remove (plist-ref opts 'on-remove #f)]
           [keys (plist-ref opts 'keys (iota (length labels)))]
           [add (plist-ref opts 'add #f)]
           [add-label (plist-ref opts 'add-label "Add")]
           [tip (plist-ref opts 'tip (lambda (i) #f))]
           [areas (ui-chips-areas x y w labels (and on-remove #t)
                                  (and add add-label))]
           [chips (map cdr (filter (lambda (a) (eq? (car a) 'chip)) areas))]
           [ch (ui-control-height)])
      (for-each
       (lambda (l a i key)
         (let ([cid (list id key)] [rid (list id 'remove key)])
           (when on-press
             (apply ui-region! ui cid
                    (append a (list 'cursor 'hand 'focus 'keep 'tip (tip i)
                                    'doc '((L . "Open"))
                                    'on (lambda (ev)
                                          (and (eq? (car ev) 'press)
                                               (eq? (list-ref ev 3) 'left)
                                               (begin (on-press i) #t)))))))
           (when on-remove
             (let ([r (cdr (assq 'remove (apply ui-chip-areas a)))])
               (ui-pressable! ui rid (car r) (cadr r) (caddr r) (cadddr r)
                              (lambda () (on-remove i)) '()
                              '(focus keep tip "Remove") '((L . "Remove")))))
           (apply ui-draw-chip
                  (append a
                          (list (append (cond [on-remove
                                               (ui-flags ui rid 'removable)]
                                              [on-press (ui-flags ui cid)]
                                              [else '()])
                                        (ui-chain-flags chips i))
                                l)))))
       labels chips (iota (length labels)) keys)
      (let ([b (assq 'add areas)])
        (cond
          [b (apply ui-button ui (list id 'add)
                    (append (cdr b) (list add-label add 'glyph 'plus 'quiet #t
                                          'focus 'keep)))]
          [(null? labels)
           (ui-draw-label x y w ch '(hint) (plist-ref opts 'empty "None"))]))
      (cdr (assq 'bottom areas))))

  ;; Where chips go in rows from (x, y), w wide, each row a control's height
  ;; and 4 apart, with each chip centered in its row and cut to w, and the
  ;; add button (with add-label) after them: ((chip x y w h) ... (add x y w
  ;; h) (bottom . y)).
  (define (ui-chips-areas x y w labels removable? add-label)
    (let*-values ([(ch) (ui-control-height)]
                  [(sizes) (map (lambda (l)
                                  (let-values ([(cw h) (ui-chip-size
                                                        l removable?)])
                                    (cons (min cw w) h)))
                                labels)]
                  [(bw bh) (if add-label
                               (ui-button-size add-label 'plus)
                               (values 0 0))]
                  [(at height)
                   (ui-flow x y w 4
                            (append (map (lambda (s) (cons (car s) ch)) sizes)
                                    (if add-label (list (cons bw bh)) '())))])
      (append (map (lambda (s p)
                     (list 'chip (car p)
                           (+ (cdr p) (floor (/ (- ch (cdr s)) 2)))
                           (car s) (cdr s)))
                   sizes (list-head at (length labels)))
              (if add-label
                  (let ([p (list-ref at (length labels))])
                    (list (list 'add (car p) (cdr p) bw bh)))
                  '())
              (list (cons 'bottom (+ y (max ch height)))))))

  ;; Returns the chips' height.
  (define (ui-chips-height w labels removable? add-label)
    (cdr (assq 'bottom (ui-chips-areas 0 0 w labels removable? add-label))))

  ;;; ------------------------------------------------------------------
  ;;; dropdown, date field and calendar

  ;; choices: ((label . value) ...). A press opens the desktop's menu under
  ;; the dropdown, with the current choice selected. opts: 'label (shown
  ;; instead of the current choice's label), 'set (the choice matters: a
  ;; filter in use), 'tip.
  ;; The mark after the current choice in a dropdown's menu: one that the
  ;; style's menu font has (Genera's *).
  (at-load
   (theme-default! 'dropdown-selected-mark "  ✓"))

  (define (ui-dropdown ui id x y w h choices current on-select . opts)
    (let ([i (list-index (lambda (c) (equal? (cdr c) current)) choices)]
          [open? (equal? (ui-menu-open-tag) (cons ui id))])
      (ui-pressable! ui id x y w h
        (lambda ()
          (ui-open-menu! ui x (+ y h)
            (map (lambda (c)
                   (cons (if (equal? (cdr c) current)
                             (string-append (car c)
                                            (theme 'dropdown-selected-mark))
                             (car c))
                         (lambda () (on-select (cdr c)))))
                 choices)
            'selected i 'tag (cons ui id) 'filter (> (length choices) 8)))
        '(#\space return down) opts '((L . "Choose")))
      (ui-draw-dropdown x y w h
                        (apply ui-flags ui id
                               (append (if open? '(open) '())
                                       (ui-opt-flags opts '(set label))))
                        (or (plist-ref opts 'label #f)
                            (if i (car (list-ref choices i)) "")))))

  ;; flags: open, set (an accent border and text), placeholder, label (it
  ;; shows its 'label, not a choice).
  (define-part (ui-draw-dropdown x y w h flags label)
    (let ([lh (font-line-height 'ui)] [hot? (memq 'hover flags)]
          [set? (memq 'set flags)] [s (+ (ui-glyph-size) 2)])
      (fill-box x y w h (if hot? 'bg-3 'bg-2) 6)
      (stroke-box x y w h
                  (if (or set? (memq 'open flags)) 'accent 'window-border) 1 6)
      (draw-text (+ x 10) (+ y (/ (- h lh) 2)) (text-fit label (- w 22 s) 'ui)
                 (cond [(memq 'disabled flags) 'text-disabled]
                       [set? 'accent] [(memq 'placeholder flags) 'text-faint]
                       [hot? 'text] [else 'text-dim])
                 'ui)
      ;; The chevron, 6 from the text's room and 6 from the edge.
      (ui-draw-glyph (- (+ x w) 6 s) (+ y (/ (- h s) 2)) s s flags
                     'chevron-down)
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 6))))

  ;; The text 10 in, then 6, the chevron and 6; at most 10 line heights
  ;; wide.
  (define-part (ui-dropdown-size labels)
    (values (min (* 10 (font-line-height 'ui))
                 (+ 24 (ui-glyph-size) (text-widest labels 'ui)))
            (ui-control-height)))

  ;; A date field: date is (year month day) or #f. A press, Space, Return or
  ;; Down opens a calendar under it; Delete and Backspace clear it. opts:
  ;; 'label (a procedure from the date to what is shown; ui-date-label by
  ;; default), 'placeholder, 'tip.
  (define (ui-date-field ui id x y w h date on-select . opts)
    (let* ([p (ui-state-popup ui)] [open? (and p (equal? (car p) id))]
           [open! (lambda ()
                    (ui-state-popup-set! ui (cons id (ui-date->day
                                                      (or date (ui-today))))))])
      (ui-region! ui id x y w h 'focus 'tab 'tip (plist-ref opts 'tip #f)
        'doc (plist-ref opts 'doc '((L . "Choose"))) 'on (lambda (ev)
              (case (car ev)
                [(press) (and (eq? (list-ref ev 3) 'left) (begin (open!) #t))]
                [(key)
                 (and (null? (caddr ev))
                      (cond [(memv (cadr ev) '(#\space return down)) (open!) #t]
                            [(memq (cadr ev) '(delete backspace))
                             (on-select #f) #t]
                            [else #f]))]
                [else #f])))
      (ui-draw-dropdown x y w h
                        (apply ui-flags ui id
                               (append (if open? '(open) '())
                                       (if date '() '(placeholder))))
                        (if date
                            ((plist-ref opts 'label ui-date-label) date)
                            (plist-ref opts 'placeholder "No date")))
      (when open?
        (ui-later! ui (lambda (ww wh)
                        (ui-calendar ui id x y h date on-select ww wh))))))

  ;; The calendar of the field id at (fx, fy), fh high, in a window ww × wh:
  ;; under the field, or above it when there is no room below, over a modal
  ;; region that closes it on a press outside.
  (define (ui-calendar ui id fx fy fh date on-select ww wh)
    (with-place 'dialog
      (lambda ()
        (let*-values ([(cw ch) (ui-calendar-size)]
                      [(x y) (ui-popup-place fx (+ fy fh 4) (- fy 4) cw ch ww
                                             wh)])
          (let* ([cursor (cdr (ui-state-popup ui))]
                 [close (lambda () (ui-state-popup-set! ui #f))]
                 [pick (lambda (n) (close) (on-select (ui-day->date n)))]
                 [move (lambda (n) (ui-state-popup-set! ui (cons id n)) #t)]
                 [today (ui-date->day (ui-today))]
                 [cd (ui-day->date cursor)]
                 [first (ui-date->day (list (car cd) (cadr cd) 1))]
                 [start (- first (ui-week-day first))]
                 [chosen (and date (ui-date->day date))]
                 [areas (ui-calendar-areas x y cw ch)]
                 [area (lambda (k) (cdr (assq k areas)))]
                 [button (lambda (k label thunk . opts)
                           (apply ui-button ui (list id k)
                                  (append (area k) (list label thunk 'quiet #t
                                                         'focus 'keep)
                                          opts)))])
            (ui-region! ui (list id 'calendar) 0 0 ww wh 'modal #t 'focus 'keep
              'on (ui-modal-on close
                    (lambda (key mods)
                      (case key
                        [(left) (move (- cursor 1))]
                        [(right) (move (+ cursor 1))]
                        [(up) (move (- cursor 7))]
                        [(down) (move (+ cursor 7))]
                        [(page-up) (move (ui-add-months cursor -1))]
                        [(page-down) (move (ui-add-months cursor 1))]
                        [(home) (move today)]
                        [(return) (pick cursor) #t]
                        [else #f]))))
            (ui-draw-calendar x y cw ch '()
                              (format "~a ~a" (vector-ref ui-month-titles
                                                          (- (cadr cd) 1))
                                      (car cd)))
            (button 'prev (and (theme 'calendar-step-words) "Previous")
                    (lambda () (move (ui-add-months cursor -1)))
                    'glyph 'chevron-left)
            (button 'next (and (theme 'calendar-step-words) "Next")
                    (lambda () (move (ui-add-months cursor 1)))
                    'glyph 'chevron-right)
            (let* ([g (area 'grid)] [gx (car g)] [gy (cadr g)] [cell (caddr g)])
              (do ([i 0 (+ i 1)]) ((= i 42))
                (let* ([n (+ start i)] [did (list id 'day n)]
                       [dx (+ gx (* cell (mod i 7)))]
                       [dy (+ gy (* cell (div i 7)))])
                  (ui-pressable! ui did dx dy cell cell (lambda () (pick n)) '()
                                 '(focus keep) '((L . "Choose")))
                  (ui-draw-day dx dy cell cell
                               (apply ui-flags ui did
                                      (append (if (= n today) '(today) '())
                                              (if (eqv? n chosen) '(selected)
                                                  '())
                                              (if (= n cursor) '(cursor) '())
                                              (if (= (cadr (ui-day->date n))
                                                     (cadr cd))
                                                  '()
                                                  '(outside))))
                               (number->string (caddr (ui-day->date n)))))))
            (button 'today "Today" (lambda () (pick today)))
            (button 'clear "Clear" (lambda () (close) (on-select #f))))))))

  (define (ui-calendar-cell) (max 28 (round (* (font-line-height 'ui) 1.9))))

  ;; Whether the month's steps show as the words Previous and Next, or as
  ;; glyphs (#f).
  (at-load
   (theme-default! 'calendar-step-words #f))

  (define-part (ui-calendar-size)
    (let* ([w (+ 20 (* 7 (ui-calendar-cell)))]
           [t (cdr (assq 'today (ui-calendar-areas 0 0 w 0)))])
      (values w (round (+ (cadr t) (cadddr t) 8)))))

  ;; ((prev x y w h) (next ..) (title ..) (week x y w h) (grid gx gy cell)
  ;; (today ..) (clear ..)); day i of the grid lies at gx + (i mod 7)·cell,
  ;; gy + (i div 7)·cell.
  (define-part (ui-calendar-areas x y w h)
    (let* ([cell (ui-calendar-cell)] [sh (font-line-height 'ui-small)]
           [b (ui-control-height)] [gy (+ y 4 b sh 6)]
           [fy (+ gy (* 6 cell) 8)])
      `((prev ,(+ x 8) ,(+ y 4) ,b ,b)
        (next ,(- (+ x w) 8 b) ,(+ y 4) ,b ,b)
        (title ,(+ x 8 b) ,(+ y 4) ,(- w 16 b b) ,b)
        (week ,(+ x 10) ,(+ y 4 b) ,(* 7 cell) ,(+ sh 6))
        (grid ,(+ x 10) ,gy ,cell)
        (today ,(+ x 8) ,fy ,(/ (- w 24) 2) ,b)
        (clear ,(+ x 16 (/ (- w 24) 2)) ,fy ,(/ (- w 24) 2) ,b))))

  ;; Draws the panel, its title and the weekday initials.
  (define-part (ui-draw-calendar x y w h flags title)
    (let* ([areas (ui-calendar-areas x y w h)]
           [t (cdr (assq 'title areas))] [wk (cdr (assq 'week areas))]
           [cell (/ (caddr wk) 7)])
      (ui-draw-panel x y w h '())
      (apply text-draw-centered (append t (list title 'text 'ui-bold)))
      (do ([i 0 (+ i 1)]) ((= i 7))
        (text-draw-centered (+ (car wk) (* i cell)) (cadr wk) cell (cadddr wk)
                            (string (string-ref "MTWTFSS" i)) 'text-faint
                            'ui-small))))

  ;; flags: hover, today (a ring), selected (filled), cursor (the keyboard's
  ;; day), outside (another month), disabled.
  (define-part (ui-draw-day x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [s (- (min w h) 4)]
           [cx (+ x (/ (- w s) 2))] [cy (+ y (/ (- h s) 2))])
      (cond [(on? 'selected) (fill-box cx cy s s 'accent 6)]
            [(on? 'hover) (fill-box cx cy s s 'bg-3 6)])
      (when (on? 'today)
        (stroke-box cx cy s s (if (on? 'selected) 'text 'accent) 1.5 6))
      (when (on? 'cursor)
        (stroke-box (- cx 1) (- cy 1) (+ s 2) (+ s 2) 'text 1 7))
      (text-draw-centered x y w h label
                          (cond [(on? 'selected) 'accent-ink]
                                [(on? 'disabled) 'text-disabled]
                                [(on? 'outside) 'text-faint]
                                [else 'text])
                          'ui))))
