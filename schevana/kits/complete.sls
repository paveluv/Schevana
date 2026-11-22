;;; (schevana kits complete) — a completion list beside a caret.
;;;
;;; A text field (the owner: any value, such as the REPL's record) completes
;;; the word before its caret. At Tab (complete-tab!) the field gives the
;;; choices that match the word, best first. A single choice that adds to
;;; the word goes in; or else the word grows to what the choices starting
;;; with it share, and a list of them opens under or over the caret's line.
;;; With nothing to add, a popup says so. The field narrows the list as its
;;; text changes (complete-narrow!); keys, the wheel and clicks choose from
;;; it, and the field puts the chosen one in. A row under the pointer shows
;;; that it can be clicked, and says what a click does (complete-pointer!).
;;; The field keeps what is its own: where the word starts, the choices,
;;; their kinds and descriptions, and putting one in. An owner shows one
;;; list or popup at a time.
;;;
;;; An item is (name kind matched): kind is a string, or #f when the field
;;; works it out only once the item shows; matched lists the indices of the
;;; characters of name that the typed text matched, drawn in the accent.
;;;
;;; The seam is as in (schevana kits ui): only the complete-draw-…
;;; procedures draw or name a theme color, and complete-size measures for
;;; them.

(library (schevana kits complete)
  (export
    complete make-complete complete? complete-context complete-start
    complete-items complete-sel complete-sel-set! complete-top
    complete-top-set! complete-message complete-box complete-box-set!
    complete-hover complete-hover-set! *complete-open* complete-rows
    complete-max-items complete-of complete-close! complete-open! complete-say!
    complete-page complete-move! complete-page! complete-tab! complete-narrow!
    complete-shared complete-key! complete-text! complete-wheel!
    complete-mouse-down! complete-pointer! complete-pointer-at complete-item-at
    make-complete-source complete-source? complete-source-text
    complete-source-heads complete-source-codes complete-source-mask
    complete-separator? complete-slot complete-source-of *complete-sources*
    complete-source complete-codes-within? complete-align complete-search
    complete-score complete-less? complete-rank complete-row-height
    complete-detail-height complete-show complete-rows-y complete-kinds-width
    complete-doc-lines complete-size complete-draw-list complete-source-record)
  (import (chezscheme)
          (only (schevana base) clamp define-made define-state filter-map
                library-layer set-hook! string-prefix?)
          (only (schevana core) *mouse-x* *mouse-y* core0-set-cursor!
                current-window draw-text font-char-width font-line-height
                point-in? text-width theme window-hover window-local
                window-props window-ref)
          (only (schevana kits text) text-fit text-wrap text-widest)
          (only (schevana kits ui) ui-draw-separator ui-draw-scrollbar
                ui-scrollbar-width ui-draw-highlight-over ui-draw-highlight
                ui-draw-panel ui-scrollbar-inset ui-rank))

  (library-layer kits)

  ;;; ---------------------------------------------------------------- state

  (define-record-type complete
    (nongenerative schevana-complete)
    (fields context        ; the field's own: what it completes (the REPL's
                           ; symbols, a path or a library)
            start          ; where the completed word starts in the text
            items          ; #(item ...), best first
            (mutable sel)  ; the selected row
            (mutable top)  ; the first row shown
            message        ; #f for a list; else a popup's text, shown over
                           ; the description of its item, if it has one
            (mutable box)    ; (x y w h rows rows-y) as last drawn, or #f
            (mutable hover)))  ; the item under the pointer (its index), or #f

  (define-state *complete-open* (make-weak-eq-hashtable))   ; owner -> its list

  (define complete-rows 8)          ; the most rows shown at once
  (define complete-max-items 200)

  ;; Returns the list or popup that owner shows, or #f.
  (define (complete-of owner) (hashtable-ref *complete-open* owner #f))

  (define (complete-close! owner) (hashtable-delete! *complete-open* owner))

  ;; Opens a list of items for the word at start, with its first row
  ;; selected; with no items, it closes the list instead. Opened again with
  ;; fewer items, the list narrows.
  (define (complete-open! owner context start items)
    (if (= 0 (vector-length items))
        (complete-close! owner)
        (hashtable-set! *complete-open* owner
                        (make-complete context start items 0 0 #f #f #f))))

  ;; Opens a popup instead: message, shown over the description of the
  ;; first of items, if there is one.
  (define (complete-say! owner message context start items)
    (hashtable-set! *complete-open* owner
                    (make-complete context start items 0 0 message #f #f)))

  ;; Returns how many rows a page has: as many as the last draw showed
  ;; (fewer in a small window).
  (define (complete-page c)
    (let ([box (complete-box c)]) (if box (list-ref box 4) complete-rows)))

  ;; Moves the selection by delta rows, wrapping, and keeps it in view.
  (define (complete-move! c delta)
    (let* ([n (vector-length (complete-items c))]
           [sel (mod (+ (complete-sel c) delta) n)])
      (complete-sel-set! c sel)
      (complete-top-set! c (clamp (complete-top c)
                                  (max 0 (- sel (- (complete-page c) 1)))
                                  sel))))

  ;; Selects the first row of the next page (dir 1) or the previous one
  ;; (-1), wrapping, and shows that page.
  (define (complete-page! c dir)
    (let* ([n (vector-length (complete-items c))] [rows (complete-page c)]
           [pages (quotient (+ n rows -1) rows)]
           [page (mod (+ (quotient (complete-sel c) rows) dir) pages)]
           [sel (* page rows)])
      (complete-sel-set! c sel)
      (complete-top-set! c (min sel (max 0 (- n rows))))))

  ;; Handles Tab for the word typed at start, with items ranked for it.
  ;; With nothing to add, a popup says so: nothing matches, or only the word
  ;; itself does. A single other match goes in (accept! puts it in).
  ;; Otherwise the list opens, and the word grows to what the names starting
  ;; with it share, as in a shell (replace! puts that in place of the word,
  ;; and narrows the list).
  (define (complete-tab! owner context start typed items replace! accept!)
    (let ([n (vector-length items)])
      (cond
        [(= n 0) (complete-say! owner "No completions" context start items)]
        [(and (= n 1) (string=? typed (car (vector-ref items 0))))
         (complete-say! owner "Sole completion" context start items)]
        [(= n 1) (accept! (vector-ref items 0))]
        [else
         (complete-open! owner context start items)
         (let ([shared (complete-shared typed items)])
           (when (> (string-length shared) (string-length typed))
             (replace! shared)))])))

  ;; Called when the word changed to typed while the list was open, with
  ;; items ranked for it: the list narrows, or closes when nothing matches
  ;; or only the word itself does.
  (define (complete-narrow! owner context start typed items)
    (if (and (= 1 (vector-length items))
             (string=? typed (car (vector-ref items 0))))
        (complete-close! owner)
        (complete-open! owner context start items)))

  ;; Returns the prefix that the names of items starting with typed share,
  ;; or typed when none starts with it.
  (define (complete-shared typed items)
    (let ([names (filter (lambda (name) (string-prefix? typed name))
                         (map car (vector->list items)))])
      (if (null? names)
          typed
          (fold-left (lambda (a b)
                       (let loop ([i 0])
                         (if (and (< i (string-length a))
                                  (< i (string-length b))
                                  (char=? (string-ref a i) (string-ref b i)))
                             (loop (+ i 1))
                             (substring a 0 i))))
                     (car names) (cdr names)))))

  ;;; ---------------------------------------------------------------- input
  ;;; Each returns #t when the list used the input. A popup closes at any
  ;;; input, which then acts as usual (#f). accept! puts an item in.

  ;; Up and Down move the selection, Page Up and Page Down move it by a
  ;; page's rows, and Tab and Shift+Tab move it to the next or previous
  ;; page's first row; Return accepts, and Escape closes. Tab accepts a list
  ;; narrowed to one, as on a sole match.
  (define (complete-key! owner key mods accept!)
    (let ([c (complete-of owner)])
      (cond
        [(not c) #f]
        [(complete-message c) (complete-close! owner) #f]
        [(pair? (remq 'shift mods)) #f]
        [else
         (case key
           [(down) (complete-move! c 1) #t]
           [(up) (complete-move! c -1) #t]
           [(page-down) (complete-move! c (complete-page c)) #t]
           [(page-up) (complete-move! c (- (complete-page c))) #t]
           [(tab)
            (if (= 1 (vector-length (complete-items c)))
                (accept! (vector-ref (complete-items c) 0))
                (complete-page! c (if (memq 'shift mods) -1 1)))
            #t]
           [(return)
            (accept! (vector-ref (complete-items c) (complete-sel c)))
            #t]
           [(escape) (complete-close! owner) #t]
           [else #f])])))

  ;; Typed text never goes to the list (the field narrows it); it only
  ;; closes a popup. Returns #f.
  (define (complete-text! owner)
    (let ([c (complete-of owner)])
      (when (and c (complete-message c)) (complete-close! owner))
      #f))

  ;; The wheel moves the selection.
  (define (complete-wheel! owner dy)
    (let ([c (complete-of owner)])
      (cond [(not c) #f]
            [(complete-message c) (complete-close! owner) #f]
            [else (complete-move! c (- dy)) #t])))

  ;; A press at (x, y): a left press on a row accepts the row; any other
  ;; press on the list does nothing; a press outside the list closes it and
  ;; acts as usual.
  (define (complete-mouse-down! owner x y button accept!)
    (let* ([c (complete-of owner)] [box (and c (complete-box c))])
      (cond
        [(not c) #f]
        [(or (complete-message c) (not box)
             (not (point-in? x y (car box) (cadr box) (caddr box)
                             (cadddr box))))
         (complete-close! owner)
         #f]
        [else
         (let ([i (complete-item-at c x y)])
           (when (and i (eq? button 'left))
             (accept! (vector-ref (complete-items c) i)))
           #t)])))

  ;; Sets the pointer's shape and the mouse documentation in win, owner's
  ;; window, for where the pointer is: over a row, a hand and what a click
  ;; does; over the rest of the list, an arrow; elsewhere, cursor, the
  ;; field's own, and its doc while nothing is open (else what a click there
  ;; does). It is called as the pointer moves and after each draw (the list
  ;; opens, moves or closes under a still pointer). Returns #t when the item
  ;; under the pointer changed, so that the caller redraws.
  (define (complete-pointer! owner win cursor doc)
    (let* ([c (complete-of owner)] [at (complete-pointer-at win)]
           [box (and c at (complete-box c))]
           [in? (and box (point-in? (car at) (cdr at) (car box) (cadr box)
                                    (caddr box) (cadddr box)))]
           [i (and in? (complete-item-at c (car at) (cdr at)))]
           [shape (cond [i 'hand] [in? 'arrow] [else cursor])])
      ;; neither of these asks for a redraw
      (hashtable-set! (window-props win) 'mouse-doc
                      (cond [i '((L . "Complete") (W . "Scroll"))]
                            [(not c) doc]
                            [(complete-message c) '((L . "Close"))]
                            [in? '((W . "Scroll"))]
                            [else '((L . "Close the list"))]))
      (unless (eq? shape (window-ref win 'cursor 'arrow))
        (hashtable-set! (window-props win) 'cursor shape)
        (when at (core0-set-cursor! shape)))
      (and c (not (eqv? i (complete-hover c)))
           (begin (complete-hover-set! c i) #t))))

  ;; Returns where the pointer is over win's content, in its coordinates, as
  ;; (x . y), or #f.
  (define (complete-pointer-at win)
    (and win (memq (window-hover win) '(content scrollbar))
         (let-values ([(x y) (window-local win *mouse-x* *mouse-y*)])
           (cons x y))))

  ;; Returns the index of the item on the row of c's list at (x, y), as last
  ;; drawn, or #f.
  (define (complete-item-at c x y)
    (let ([box (complete-box c)])
      (and box (not (complete-message c))
           (point-in? x y (car box) (cadr box) (caddr box) (cadddr box))
           (let ([row (exact (floor (/ (- y (list-ref box 5))
                                       (complete-row-height))))])
             (and (<= 0 row) (< row (list-ref box 4))
                  (+ (complete-top c) row))))))

  ;;; ------------------------------------------------------------------
  ;;; matching
  ;;; Taken from the editor e (its lib/foundation/fuzzy.sls). The typed text
  ;;; aligns with a name in disjoint segments, in any order. Each segment
  ;;; starts where a part of the name starts (at its beginning, or after a
  ;;; character that is not a letter or digit), or at a separator that the
  ;;; segment leads with: "stp" finds set-theme-plist!, and ":sp" finds
  ;;; head:split-window but not head:window-split. Except at the name's
  ;;; first character, a segment must hold a letter or digit ("*" finds
  ;;; *scratch*). Case is ignored.

  ;; A name prepared for matching: its characters case-folded; where its
  ;; segments may start (where its parts start, then the separators past
  ;; its first character that start no part); its character codes, sorted;
  ;; and a mask of the kinds of character it holds.
  (define-record-type (complete-source-record make-complete-source
                                              complete-source?)
    (nongenerative schevana-complete-source)
    (fields (immutable text complete-source-text)
            (immutable heads complete-source-heads)
            (immutable codes complete-source-codes)
            (immutable mask complete-source-mask)))

  (define (complete-separator? c)
    (not (or (char-alphabetic? c) (char-numeric? c))))

  ;; Returns a mask bit for each common character of names; the other
  ;; characters share one.
  (define (complete-slot c)
    (let ([n (char->integer c)])
      (cond [(<= 97 n 122) (- n 97)]
            [(<= 48 n 57) (+ 26 (- n 48))]
            [else (case c
                    [(#\-) 36] [(#\:) 37] [(#\!) 38] [(#\?) 39] [(#\*) 40]
                    [(#\<) 41] [(#\>) 42] [(#\=) 43] [(#\/) 44] [(#\+) 45]
                    [(#\.) 46] [(#\_) 47] [(#\$) 48] [(#\%) 49] [(#\&) 50]
                    [(#\^) 51] [(#\~) 52] [(#\@) 53] [(#\#) 54] [else 55])])))

  (define (complete-source-of name)
    (let* ([n (string-length name)] [text (make-string n)]
           [codes (make-vector n 0)])
      (let scan ([i 0] [mask 0] [starts (if (> n 0) '(0) '())] [leads '()])
        (if (= i n)
            (begin
              (vector-sort! < codes)
              (make-complete-source text (append (reverse starts)
                                                 (reverse leads))
                                    codes mask))
            (let* ([c (char-foldcase (string-ref name i))]
                   [sep? (complete-separator? c)])
              (string-set! text i c)
              (vector-set! codes i (char->integer c))
              (scan (+ i 1)
                    (logor mask (ash 1 (complete-slot c)))
                    (if (and sep? (< (+ i 1) n)) (cons (+ i 1) starts) starts)
                    (if (and sep? (> i 0) (not (= (car starts) i)))
                        (cons i leads)
                        leads)))))))

  ;; Names recur from keystroke to keystroke, so their sources are kept (a
  ;; keystroke ranks 3,400 names in 0.2 to 0.7 ms with them, and in 1.7 to
  ;; 2.2 ms without), until there are too many.
  (define-made *complete-sources* (make-hashtable string-hash string=?))

  (define (complete-source name)
    (or (hashtable-ref *complete-sources* name #f)
        (let ([s (complete-source-of name)])
          (when (> (hashtable-size *complete-sources*) 16384)
            (hashtable-clear! *complete-sources*))
          (hashtable-set! *complete-sources* name s)
          s)))

  ;; Whether the sorted multiset part is within the sorted multiset whole.
  (define (complete-codes-within? part whole)
    (let ([m (vector-length part)] [n (vector-length whole)])
      (let walk ([i 0] [j 0])
        (cond [(= i m) #t]
              [(= j n) #f]
              [(< (vector-ref whole j) (vector-ref part i)) (walk i (+ j 1))]
              [(= (vector-ref whole j) (vector-ref part i))
               (walk (+ i 1) (+ j 1))]
              [else #f]))))

  ;; Returns how the prepared query q aligns with the source s: its
  ;; segments, ((query-index name-index length) ...), or #f. The masks and
  ;; the codes turn most names away before a search.
  (define (complete-align q s)
    (and (<= (string-length (complete-source-text q))
             (string-length (complete-source-text s)))
         (zero? (logand (complete-source-mask q)
                        (lognot (complete-source-mask s))))
         (complete-codes-within? (complete-source-codes q)
                                 (complete-source-codes s))
         (complete-search q s)))

  ;; Searches for the segments: the longest segment first, then the
  ;; earliest start. Backtracking keeps what matches independent of a
  ;; greedy choice; used marks the name's characters already taken, and
  ;; what failed is remembered once a choice has been undone.
  (define (complete-search q s)
    (let* ([text (complete-source-text q)] [m (string-length text)]
           [name (complete-source-text s)] [n (string-length name)]
           [failed #f] [stride (ash 1 n)])
      ;; how far text from at matches name from start, through characters
      ;; not yet used
      (define (run at start used)
        (let loop ([k 0])
          (if (and (< (+ at k) m) (< (+ start k) n)
                   (not (bitwise-bit-set? used (+ start k)))
                   (char=? (string-ref text (+ at k))
                           (string-ref name (+ start k))))
              (loop (+ k 1))
              k)))
      ;; the shortest run from start, of at most size, that holds a letter
      ;; or digit; #f when none does
      (define (shortest start size)
        (let scan ([k 0])
          (cond [(= k size) #f]
                [(complete-separator? (string-ref name (+ start k)))
                 (scan (+ k 1))]
                [else (+ k 1)])))
      (let solve ([at 0] [used 0])
        (cond
          [(= at m) '()]
          [(and failed (hashtable-ref failed (+ used (* at stride)) #f)) #f]
          [else
           (or (exists
                (lambda (option)
                  (let ([start (cadr option)] [least (caddr option)])
                    (let sizes ([size (car option)])
                      (and (>= size least)
                           (let ([tail (solve (+ at size)
                                              (logor used
                                                     (ash (- (ash 1 size) 1)
                                                          start)))])
                             (if tail
                                 (cons (list at start size) tail)
                                 (sizes (- size 1))))))))
                ;; (size start least) for each start whose run matches,
                ;; longest first, and in the starts' order among equals
                (sort (lambda (a b) (> (car a) (car b)))
                      (filter-map
                       (lambda (start)
                         (let* ([size (run at start used)]
                                [least (if (= start 0)
                                           1
                                           (shortest start size))])
                           (and (> size 0) least (list size start least))))
                       (complete-source-heads s))))
               (begin
                 (unless failed (set! failed (make-eqv-hashtable)))
                 (hashtable-set! failed (+ used (* at stride)) #t)
                 #f))]))))

  ;; Returns how well segments align a query size long with a name
  ;; name-size long: fewer segments, fewer pairs out of order, an earlier
  ;; first character, a tighter span and a shorter name rank first. Scores
  ;; compare as lists of numbers, smaller first; the empty query matches
  ;; every name alike.
  (define (complete-score segments size name-size)
    (if (null? segments)
        '()
        (let loop ([ss segments] [count 0] [inversions 0] [first name-size]
                   [end 0])
          (if (null? ss)
              (list (- count 1) inversions first (- end first size) name-size)
              (let ([start (cadar ss)])
                (loop (cdr ss) (+ count 1)
                      (+ inversions
                         (length (filter (lambda (s) (> start (cadr s)))
                                         (cdr ss))))
                      (min first start)
                      (max end (+ start (caddar ss)))))))))

  (define (complete-less? a b)
    (cond [(null? a) #f]
          [(< (car a) (car b)) #t]
          [(> (car a) (car b)) #f]
          [else (complete-less? (cdr a) (cdr b))]))

  ;; Returns the choices ((name . kind) ...) that typed matches, best
  ;; first, as #(item ...), at most complete-max-items of them. Among equal
  ;; matches, the names that first? accepts come first, and ties go in
  ;; alphabetical order.
  (define (complete-rank typed choices first?)
    (let* ([q (complete-source-of typed)]
           [scored
            (filter-map
             (lambda (c)
               (let ([segments (complete-align q (complete-source (car c)))])
                 (and segments
                      (list (append (complete-score segments
                                                    (string-length typed)
                                                    (string-length (car c)))
                                    (list (if (first? (car c)) 0 1)))
                            (car c) (cdr c)
                            (apply append
                                   (map (lambda (s)
                                          (map (lambda (k) (+ (cadr s) k))
                                               (iota (caddr s))))
                                        segments))))))
             choices)]
           [sorted (sort (lambda (a b)
                           (or (complete-less? (car a) (car b))
                               (and (not (complete-less? (car b) (car a)))
                                    (string<? (cadr a) (cadr b)))))
                         scored)])
      (list->vector
       (map cdr (list-head sorted (min complete-max-items (length sorted)))))))

  ;; The widget kit's suggestions are ranked by this (ui-rank, (schevana
  ;; kits ui)).
  (set-hook! (ui-rank typed choices first?)
             (complete-rank typed choices first?))

  ;;; ------------------------------------------------------------------
  ;;; placement

  (define (complete-row-height) (+ 3 (font-line-height 'mono)))

  ;; Returns the description's height, with lines of doc under the
  ;; signature.
  (define (complete-detail-height lines)
    (round (+ 12 (font-line-height 'mono-small)
              (* lines (+ (font-line-height 'ui-small) 2)))))

  ;; Draws c, owner's list or popup, beside the caret at (x . y), or nothing
  ;; when the caret is out of view (#f), and keeps where it drew, for clicks
  ;; and the pointer. The description goes on the far side of the rows from
  ;; the line, so that the rows stay put as it changes. The word before the
  ;; caret is word-w wide, its line is line-h high, and the window is w × h.
  ;; kind-of gives the kind of an item's name when the item has none;
  ;; describe gives an item's (values signature doc).
  (define (complete-show c caret word-w line-h w h kind-of describe)
    (complete-box-set! c #f)
    (when caret
      (let*-values
          ([(items) (complete-items c)] [(n) (vector-length items)]
           [(sel) (complete-sel c)] [(message) (complete-message c)]
           [(flags) (if message '(message) '())]
           [(sig doc) (if (< sel n)
                          (describe (vector-ref items sel))
                          (values "" ""))]
           [(rh) (complete-row-height)]
           [(most) (if message 1 complete-rows)]
           ;; Below the line, or above it, chosen by the tallest the list
           ;; can be, so it stays on its side while typing narrows it and
           ;; descriptions change length. Where that fits on neither side,
           ;; the side with more room; the description keeps the lines that
           ;; fit, and so do the rows, so the list leaves the line in view
           ;; while one row fits.
           [(below) (+ (cdr caret) line-h 2)]
           [(room-below) (- h 4 below)]
           [(room-above) (- (cdr caret) 2 4)]
           [(below?) (or (<= (+ 8 (* most rh) (complete-detail-height 3))
                             room-below)
                         (>= room-below room-above))]
           [(room) (if below? room-below room-above)]
           [(sig) (if (<= (+ 8 rh (complete-detail-height 0)) room) sig "")]
           [(rows) (max 1 (min (min most n)
                               (exact (floor
                                       (/ (- room 8
                                             (if (string=? sig "")
                                                 0
                                                 (complete-detail-height 0)))
                                          rh)))))]
           ;; the selection shown, and no row past the last
           [(top) (clamp (complete-top c) (max 0 (+ (- sel rows) 1))
                         (min sel (- n rows)))]
           [(shown)
            (if message
                (list (list message "" '() #f))
                (map (lambda (i)
                       (let ([it (vector-ref items i)])
                         (list (car it) (or (cadr it) (kind-of (car it)))
                               (caddr it) (= i sel))))
                     (map (lambda (k) (+ top k)) (iota rows))))]
           [(k) (max 0 (min 3 (exact (floor
                                      (/ (- room 8 (* rows rh)
                                            (complete-detail-height 0))
                                         (+ (font-line-height 'ui-small)
                                            2))))))]
           [(pw ph) (complete-size flags shown sig doc k (- w 8))]
           [(px) (clamp (- (car caret) word-w 10) 4 (max 4 (- w pw 4)))]
           [(py) (if below? below (max 4 (- (cdr caret) ph 2)))]
           [(flags) (if below? flags (cons 'above flags))])
        (unless message (complete-top-set! c top))
        (complete-box-set! c (list px py pw ph rows
                                   (complete-rows-y py ph rows flags)))
        ;; the item under the pointer, as the list lies now
        (complete-hover-set!
         c (let ([at (complete-pointer-at (current-window))])
             (and at (complete-item-at c (car at) (cdr at)))))
        (complete-draw-list px py pw ph flags
                            (map (lambda (row i)
                                   (append row
                                           (list (eqv? (+ top i)
                                                       (complete-hover c)))))
                                 shown (iota (length shown)))
                            top n sig doc k))))

  ;; Returns where the count rows of a list at y, h high, start: at its top,
  ;; or, with above in flags, at its bottom, under its description.
  (define (complete-rows-y y h count flags)
    (if (memq 'above flags)
        (- (+ y h) 4 (* count (complete-row-height)))
        (+ y 4)))

  ;;; ------------------------------------------------------------------
  ;;; drawing
  ;;; rows: ((name kind matched selected? hover?) ...), the rows shown, from
  ;;; row top of n; with message in flags, one row that holds a popup's
  ;;; text. Under them (over them, with above in flags) go the signature,
  ;;; unless it is "", and the first k lines of doc.

  ;; Returns the width of the widest kind, with room around it.
  (define (complete-kinds-width rows)
    (+ 14 (text-widest (map cadr rows) 'ui-small)))

  ;; Returns doc's lines under sig in a list w wide, at most k of them.
  (define (complete-doc-lines sig doc w k)
    (if (or (string=? sig "") (string=? doc ""))
        '()
        (let ([lines (text-wrap doc (- w 20) 'ui-small)])
          (if (> (length lines) k) (list-head lines k) lines))))

  ;; Returns the list's size as (values w h): at least 260 wide, and at most
  ;; max-w.
  (define (complete-size flags rows sig doc k max-w)
    (let ([w (min max-w
                  (max 260
                       (if (memq 'message flags)
                           (+ 20 (text-width (caar rows) 'ui))
                           (+ 20 (* (font-char-width 'mono)
                                    (apply max (map (lambda (r)
                                                      (string-length (car r)))
                                                    rows)))
                              (complete-kinds-width rows)
                              ;; room a style keeps beside its scroll bar
                              (ui-scrollbar-inset 'left)
                              (ui-scrollbar-inset 'right)))))])
      (values w
              (+ 8 (* (length rows) (complete-row-height))
                 (if (string=? sig "")
                     0
                     (complete-detail-height
                      (length (complete-doc-lines sig doc w k))))))))

  (define (complete-draw-list x y w h flags rows top n sig doc k)
    (let* ([rh (complete-row-height)] [cw (font-char-width 'mono)]
           [small-lh (font-line-height 'ui-small)]
           [kind-w (complete-kinds-width rows)]
           [count (length rows)] [above? (memq 'above flags)]
           [rows-y (complete-rows-y y h count flags)]
           ;; the rows, clear of a scroll bar the style keeps room for
           [bar? (> n count)]
           [left (max 4 (if bar? (ui-scrollbar-inset 'left) 0))]
           [right (max 4 (if bar? (ui-scrollbar-inset 'right) 0))]
           [rx (+ x left)] [rw (- w left right)])
      (ui-draw-panel x y w h '(menu))
      (for-each
       (lambda (row i)
         (let ([ry (+ rows-y (* i rh))] [name (car row)]
               [selected? (cadddr row)])
           (cond [selected? (ui-draw-highlight rx ry rw rh '())]
                 [(list-ref row 4)
                  (ui-draw-highlight rx ry rw rh '(hover popup))])
           (if (memq 'message flags)
               (draw-text (+ rx 6) (+ ry (/ (- rh (font-line-height 'ui)) 2))
                          name 'text-dim 'ui)
               (let ([tx (+ rx 6)]
                     [ty (+ ry (/ (- rh (font-line-height 'mono)) 2))])
                 (draw-text tx ty name (if selected? 'text 'text-dim) 'mono)
                 (for-each (lambda (j)
                             (when (< j (string-length name))
                               (draw-text (+ tx (* j cw)) ty
                                          (string (string-ref name j))
                                          'accent 'mono-bold)))
                           (caddr row))
                 (draw-text (- (+ rx rw) kind-w -8) (+ ry (/ (- rh small-lh) 2))
                            (cadr row) 'text-faint 'ui-small)))
           (when selected? (ui-draw-highlight-over rx ry rw rh '()))))
       rows (iota count))
      ;; a scroll bar for where the rows shown are in the whole list, on
      ;; the style's side and no wider than the names' inset (Interlisp's
      ;; bars are 24)
      (when (> n count)
        (let ([bw (min (ui-scrollbar-width) 10)])
          (ui-draw-scrollbar (if (eq? (theme 'scrollbar-side) 'left)
                                 x
                                 (+ x w (- bw)))
                             rows-y bw (* count rh) '() (/ top n)
                             (/ count n))))
      (unless (string=? sig "")
        (let* ([lines (complete-doc-lines sig doc w k)]
               [sep-y (if above? (- rows-y 5) (+ rows-y (* count rh) 4))]
               [ty (if above? (+ y 6) (+ sep-y 5))])
          (ui-draw-separator (+ x 6) sep-y (- w 12) 1 '())
          (draw-text (+ x 10) ty (text-fit sig (- w 20) 'mono-small)
                     'text 'mono-small)
          (for-each (lambda (line i)
                      (draw-text (+ x 10)
                                 (+ ty (font-line-height 'mono-small) 3
                                    (* i (+ small-lh 2)))
                                 line 'text-faint 'ui-small))
                    lines (iota (length lines))))))))
