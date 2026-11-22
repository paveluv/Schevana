;;; (schevana kits edit) — text editing, pure: no window, no ui object and no
;;; screen.
;;;
;;; This is what a text field, a text area or an editor needs: an edit (the
;;; text, the caret and the selection, and where the text last changed),
;;; what the editing keys do to it, and the text's rows, wrapped at a width,
;;; computed only as far as they are asked for, and remembered. Measuring is
;;; a procedure passed in, (lambda (str) width), so editing needs no font.
;;; The widget kit's text boxes are built on it, and so is Tasks'
;;; description editor; an Editor app would add undo, find and files on
;;; top.
;;;
;;;   (define e (edit-at "hello world" 5))
;;;   (edit-text (edit-insert e ","))                  ; "hello, world"
;;;   (define m7 (lambda (s) (* 7 (string-length s))))
;;;   (define lay (edit-layout-of #f "hello world" 42 #f m7 #f))
;;;   (edit-row-at lay 8)                              ; 1: "world"
;;;
;;; Indices are character indices; the selection is [min(caret, anchor),
;;; max(caret, anchor)).

(library (schevana kits edit)
  (export
    edit make-edit edit? edit-text edit-caret edit-anchor edit-goal edit-change
    edit-at edit-all edit-range edit-selection edit-splice edit-replace
    edit-insert edit-erase edit-move edit-select edit-word-char? edit-word-left
    edit-word-right edit-run edit-word-bounds edit-line-bounds edit-clean
    edit-layout make-edit-layout edit-layout? edit-layout-text
    edit-layout-text-set! edit-layout-width edit-layout-key edit-layout-measure
    edit-layout-measure-set! edit-layout-starts edit-layout-starts-set!
    edit-layout-count edit-layout-count-set! edit-layout-done?
    edit-layout-done?-set! edit-layout-guess edit-layout-guess-set!
    edit-layout-old edit-layout-old-set! edit-layout-of edit-difference
    edit-search edit-layout-cut! edit-layout-recall edit-last edit-row-end
    edit-paragraph-end edit-layout-step! edit-layout-extend! edit-layout-scan!
    edit-layout-total edit-row* edit-row edit-row-last edit-row-at edit-caret-x
    edit-index-at edit-vertical edit-key edit-wrap)
  (import (chezscheme)
          (only (schevana base) clamp library-layer))

  (library-layer kits)

  ;;; ---------------------------------------------------------------- edits

  (define-record-type edit
    (nongenerative schevana-edit-1)
    (fields text caret anchor
            goal       ; the x that Up and Down keep, or #f
            change))   ; (before lo hi): text is before with [lo, hi)
                       ; replaced, so that a layout of before need not
                       ; compare the texts; caret moves keep it; or #f

  (define (edit-at text i)
    (let ([i (clamp i 0 (string-length text))]) (make-edit text i i #f #f)))

  (define (edit-all text) (make-edit text (string-length text) 0 #f #f))

  (define (edit-range e)
    (values (min (edit-caret e) (edit-anchor e))
            (max (edit-caret e) (edit-anchor e))))

  (define (edit-selection e)
    (let-values ([(lo hi) (edit-range e)]) (substring (edit-text e) lo hi)))

  ;; Returns t with [lo, hi) replaced by str, copied once; or t itself when
  ;; nothing changes, so that a caller can tell with eq?.
  (define (edit-splice t lo hi str)
    (let ([n (string-length t)] [k (string-length str)])
      (if (and (= lo hi) (= k 0))
          t
          (let ([new (make-string (+ lo k (- n hi)))])
            (string-copy! t 0 new 0 lo)
            (string-copy! str 0 new lo k)
            (string-copy! t hi new (+ lo k) (- n hi))
            new))))

  ;; Returns an edit of e's text with [lo, hi) replaced by str and the caret
  ;; at c. Its change says what changed, or is e's own when nothing did.
  (define (edit-replace e lo hi str c)
    (let* ([t (edit-text e)] [new (edit-splice t lo hi str)])
      (make-edit new c c #f (if (eq? new t) (edit-change e) (list t lo hi)))))

  ;; Replaces the selection with str and puts the caret after it. With most
  ;; (a number, or #f for no limit), the text stays within most characters:
  ;; typing stops there, and a paste is cut to fit.
  (define (edit-insert e str . most)
    (let*-values ([(lo hi) (edit-range e)]
                  [(t) (edit-text e)]
                  [(room) (if (and (pair? most) (car most))
                              (max 0 (- (car most)
                                        (- (string-length t) (- hi lo))))
                              (string-length str))]
                  [(str) (if (< room (string-length str))
                             (substring str 0 room)
                             str)])
      (edit-replace e lo hi str (+ lo (string-length str)))))

  ;; Deletes the selection; with none, deletes from the caret to to, in
  ;; either direction.
  (define (edit-erase e to)
    (let*-values ([(n) (string-length (edit-text e))]
                  [(lo hi) (edit-range e)]
                  [(lo hi) (if (< lo hi)
                               (values lo hi)
                               (let ([to (clamp to 0 n)] [c (edit-caret e)])
                                 (values (min c to) (max c to))))])
      (edit-replace e lo hi "" lo)))

  (define (edit-move e to extend?)
    (let ([to (clamp to 0 (string-length (edit-text e)))])
      (make-edit (edit-text e) to (if extend? (edit-anchor e) to) #f
                 (edit-change e))))

  (define (edit-select e from to)
    (let ([n (string-length (edit-text e))])
      (make-edit (edit-text e) (clamp to 0 n) (clamp from 0 n) #f
                 (edit-change e))))

  ;; Letters, digits, - and _ are word characters, so Lisp names are words.
  (define (edit-word-char? c)
    (or (char-alphabetic? c) (char-numeric? c) (memv c '(#\- #\_))))

  (define (edit-word-left text i)
    (let loop ([i i] [in-word? #f])
      (cond [(<= i 0) 0]
            [(edit-word-char? (string-ref text (- i 1))) (loop (- i 1) #t)]
            [in-word? i]
            [else (loop (- i 1) #f)])))

  (define (edit-word-right text i)
    (let ([n (string-length text)])
      (let loop ([i i] [in-word? #f])
        (cond [(>= i n) n]
              [(edit-word-char? (string-ref text i)) (loop (+ i 1) #t)]
              [in-word? i]
              [else (loop (+ i 1) #f)]))))

  ;; Returns (values lo hi), the run of characters around index j that pred
  ;; accepts (pred accepts the one at j).
  (define (edit-run text j pred)
    (let ([n (string-length text)])
      (values (let loop ([i j])
                (if (and (> i 0) (pred (string-ref text (- i 1))))
                    (loop (- i 1))
                    i))
              (let loop ([i (+ j 1)])
                (if (and (< i n) (pred (string-ref text i))) (loop (+ i 1))
                    i)))))

  ;; Returns (values lo hi) for a double click at i: the word touching i (by
  ;; the character after i first, then the one before), or else the run of
  ;; spaces there, or else the character after i.
  (define (edit-word-bounds text i)
    (let* ([n (string-length text)]
           [after (and (< i n) (string-ref text i))]
           [before (and (> i 0) (string-ref text (- i 1)))]
           [space? (lambda (c) (memv c '(#\space #\tab)))])
      (cond [(and after (edit-word-char? after))
             (edit-run text i edit-word-char?)]
            [(and before (edit-word-char? before))
             (edit-run text (- i 1) edit-word-char?)]
            [(and after (space? after)) (edit-run text i space?)]
            [(and before (space? before)) (edit-run text (- i 1) space?)]
            [after (values i (+ i 1))]
            [else (values i i)])))

  ;; Returns (values lo hi) for a triple click at i: the line between
  ;; newlines.
  (define (edit-line-bounds text i)
    (let ([n (string-length text)])
      (values (let loop ([j i])
                (if (and (> j 0)
                         (not (char=? (string-ref text (- j 1)) #\newline)))
                    (loop (- j 1))
                    j))
              (let loop ([j i])
                (if (and (< j n) (not (char=? (string-ref text j) #\newline)))
                    (loop (+ j 1))
                    j)))))

  ;; Returns str made insertable: a tab becomes a space, so pasted words stay
  ;; apart; other control characters (and DEL) are dropped, except newline,
  ;; and without newlines?, newlines become spaces. Text that is already
  ;; clean is returned as it is, so a caller can tell with eq? that nothing
  ;; changed.
  (define (edit-clean str newlines?)
    (define (keep c)
      (cond [(char=? c #\newline) (if newlines? c #\space)]
            [(char=? c #\tab) #\space]
            [(char<? c #\space) #f]
            [(char=? c #\delete) #f]
            [else c]))
    (let ([n (string-length str)])
      (if (let loop ([i 0])
            (or (= i n)
                (let ([c (string-ref str i)])
                  (if (char<? c #\space)
                      (and newlines? (char=? c #\newline) (loop (+ i 1)))
                      (and (not (char=? c #\delete)) (loop (+ i 1)))))))
          str
          (let ([o (open-output-string)])
            (string-for-each (lambda (c)
                               (let ([k (keep c)]) (when k (write-char k o))))
                             str)
            (get-output-string o)))))

  ;;; ---------------------------------------------------------------- rows
  ;;; A newline ends a row. A paragraph breaks after the last space that
  ;;; fits, and the space stays on its row (a soft break); inside a word
  ;;; wider than the width, it breaks between characters. A space at a
  ;;; paragraph's end hangs past the width rather than start a row. A layout
  ;;; computes rows from the top only as far as they are asked for, and
  ;;; keeps them with the text, width and font they belong to, so what a
  ;;; draw costs depends on the rows it shows, not on the text's length.
  ;;; After an edit, the rows past it are the rows of the text before,
  ;;; moved: once a row starts where one of them did, they are taken back,
  ;;; not computed again.

  (define-record-type edit-layout
    (nongenerative schevana-edit-layout-1)
    (fields (mutable text)
            width              ; where rows wrap; #f wraps only at newlines
            key                ; what else a measure depends on (the font)
            (mutable measure)  ; (lambda (str) width)
            (mutable starts)   ; fxvector: each row's start, then the next
                               ; row's (past the text's end after the last)
            (mutable count)    ; how many rows are computed
            (mutable done?)    ; whether they reach the text's end
            (mutable guess)    ; the length of the last row wrapped, where
                               ; the next row's search starts
            (mutable old)))    ; (starts last hi delta): the rows from before
                               ; the last change, to take back, or #f

  ;; Returns text's layout at width (#f for no wrapping) in the font that
  ;; key names (any value, compared with equal?), measured by measure. When
  ;; old (a layout, or #f) agrees on the width and key, the layout is old
  ;; itself, and a changed text keeps old's rows up to two rows before the
  ;; row of its first change. A word shortened or split there may now fit
  ;; on the row before, and on the row before that when the row between
  ;; holds only what the first could not (a word broken by character after
  ;; a narrow space). change is an edit's (before lo hi), or #f. When before
  ;; is old's text, where the text changed is known and the texts are not
  ;; compared (only a text changed from elsewhere, such as by the REPL, is).
  (define (edit-layout-of old text width key measure change)
    (cond
      [(and old (eqv? width (edit-layout-width old))
            (equal? key (edit-layout-key old)))
       (edit-layout-measure-set! old measure)
       (let ([before (edit-layout-text old)])
         (unless (eq? text before)
           (let-values ([(lo hi) (if (and change (eq? (car change) before))
                                     (values (cadr change) (caddr change))
                                     (edit-difference before text))])
             (edit-layout-cut! old lo hi
                               (- (string-length text) (string-length before))))
           (edit-layout-text-set! old text)))
       old]
      [else (make-edit-layout text width key measure (make-fxvector 64 0) 0 #f
                              0 #f)]))

  ;; Returns how b differs from a, as (values lo hi): b is a with [lo, hi)
  ;; replaced, leaving out the start and the end they share.
  (define (edit-difference a b)
    (let* ([na (string-length a)] [nb (string-length b)] [n (min na nb)]
           [lo (let loop ([i 0])
                 (if (and (< i n) (char=? (string-ref a i) (string-ref b i)))
                     (loop (+ i 1))
                     i))])
      (let loop ([k 0])   ; the shared end's length, not reaching into lo
        (if (and (< (+ lo k) n)
                 (char=? (string-ref a (- na k 1)) (string-ref b (- nb k 1))))
            (loop (+ k 1))
            (values lo (- na k))))))

  ;; Returns the last r in [0, last] whose start is at most i (starts[0] is
  ;; 0).
  (define (edit-search starts last i)
    (let loop ([lo 0] [hi last])   ; the answer is in [lo, hi]
      (if (>= lo hi)
          lo
          (let ([m (quotient (+ lo hi 1) 2)])
            (if (<= (fxvector-ref starts m) i) (loop m hi)
                (loop lo (- m 1)))))))

  ;; Tells lay that its text changed: [lo, hi) of it was replaced, and its
  ;; length changed by delta. Forgets the rows from two before the row of lo
  ;; on, and keeps the text's rows as they were (a copy of their starts,
  ;; while the vector goes on with the new ones), so that recall can take
  ;; back those from hi on. Rows kept from before an earlier change and not
  ;; all taken back yet (typing between idle steps) stay instead, when they
  ;; serve this change from its end on and reach further than the rows
  ;; computed now.
  (define (edit-layout-cut! lay lo hi delta)
    (let* ([c (edit-layout-count lay)] [starts (edit-layout-starts lay)]
           [r (edit-search starts c lo)]
           [old (edit-layout-old lay)])
      (edit-layout-old-set!
       lay
       (let ([d (and old (cadddr old))])   ; old's starts are d before ours
         (if (and old (<= (+ (caddr old) d) hi)
                  (> (+ (fxvector-ref (car old) (cadr old)) d)
                     (fxvector-ref starts c)))
             (list (car old) (cadr old) (- hi d) (+ d delta))
             (list (fxvector-copy starts) c hi delta))))
      (edit-layout-count-set! lay (min c (max 0 (- r 2))))
      (edit-layout-done?-set! lay #f)))

  ;; Returns where the row after a row from s starts, when a row of the text
  ;; before the change started at s (moved by the change) at or past the
  ;; change's end: from there on the texts agree, and so do their rows.
  ;; Else returns #f; once s is past the last row kept, the kept rows are
  ;; let go.
  (define (edit-layout-recall lay s)
    (let ([old (edit-layout-old lay)])
      (and old
           (let* ([starts (car old)] [last (cadr old)] [hi (caddr old)]
                  [delta (cadddr old)] [t (- s delta)])
             (cond
               [(< t hi) #f]
               [(> t (fxvector-ref starts last)) (edit-layout-old-set! lay #f)
                                                  #f]
               [else (let ([j (edit-search starts last t)])
                       (and (< j last) (= (fxvector-ref starts j) t)
                            (+ (fxvector-ref starts (+ j 1)) delta)))])))))

  ;; Returns the last i in [a, b] for which ok? holds, where ok? holds up to
  ;; a point and never after it; a - 1 if it holds for none. It probes from
  ;; i0 outward by doubling steps, then halves: about two probes when i0 is
  ;; next to the answer.
  (define (edit-last ok? a b i0)
    (define (halve lo hi)   ; ok? holds for lo (or lo is a - 1), not for hi
      (if (<= (- hi lo) 1)
          lo
          (let ([m (quotient (+ lo hi) 2)])
            (if (ok? m) (halve m hi) (halve lo m)))))
    (if (< b a)
        (- a 1)
        (let ([i0 (clamp i0 a b)])
          (if (ok? i0)
              (let up ([lo i0] [step 1])
                (if (= lo b)
                    lo
                    (let ([j (min b (+ lo step))])
                      (if (ok? j) (up j (* step 2)) (halve lo j)))))
              (let down ([hi i0] [step 1])
                (let ([j (- hi step)])
                  (cond [(< j a) (halve (- a 1) hi)]
                        [(ok? j) (halve j hi)]
                        [else (down j (* step 2))])))))))

  ;; Returns where the row from s ends, inside a paragraph (s is not at a
  ;; newline), as (values e end?). end? is true when e is the paragraph's
  ;; end: the rest fits, or its last character does not fit either.
  ;; Otherwise e is after the last space that fits, or inside a word that
  ;; does not fit. The candidates (the spaces, then the paragraph's end) are
  ;; looked for only up to twice g past s, where g is the last row's length,
  ;; and are probed from the one near g: about two measures for a row of
  ;; words, and nothing is scanned or measured much past the row (a longer
  ;; row looks again, twice as far).
  (define (edit-row-end text s width measure g)
    (let ([n (string-length text)])
      (define (fits? x) (<= (measure (substring text s x)) width))
      (let retry ([g (max g 4)])
        (let ([b (min n (+ s g g 16))])
          ;; the spaces in [s, b), and the paragraph's end if before b
          (let scan ([i s] [spaces '()])
            (cond
              [(and (< i b) (char=? (string-ref text i) #\space))
               (scan (+ i 1) (cons i spaces))]
              [(and (< i b) (not (char=? (string-ref text i) #\newline)))
               (scan (+ i 1) spaces)]
              [else
               (let* ([q (and (or (= i n) (< i b)) i)]   ; #f: the end is past b
                      [cs (list->vector (reverse (cons i spaces)))]
                      [m (vector-length cs)]
                      [i0 (let loop ([j 0])
                            (if (and (< (+ j 1) m)
                                     (<= (vector-ref cs (+ j 1)) (+ s g)))
                                (loop (+ j 1))
                                j))]
                      [j (edit-last (lambda (j) (fits? (vector-ref cs j)))
                                    0 (- m 1) i0)])
                 (cond
                   [(and (= j (- m 1)) q) (values q #t)]
                   [(= j (- m 1)) (retry (* 2 (- b s)))]   ; it goes past b
                   [(>= j 0)
                    (let ([e (+ (vector-ref cs j) 1)])
                      (values e (eqv? e q)))]
                   [else   ; inside the word: the most characters that fit
                    (let ([e (max (+ s 1)
                                  (edit-last fits? (+ s 1)
                                             (- (vector-ref cs 0) 1) (+ s g)))])
                      (values e (eqv? e q)))]))]))))))

  ;; Returns the first newline at or after s, or the text's end.
  (define (edit-paragraph-end text s)
    (let ([n (string-length text)])
      (let loop ([i s])
        (if (or (= i n) (char=? (string-ref text i) #\newline))
            i
            (loop (+ i 1))))))

  ;; Computes the next row, or takes it back (recall). Its end is kept as
  ;; the next row's start, which is past the text's end after the last row.
  (define (edit-layout-step! lay)
    (let* ([text (edit-layout-text lay)] [n (string-length text)]
           [c (edit-layout-count lay)] [starts (edit-layout-starts lay)]
           [s (fxvector-ref starts c)] [width (edit-layout-width lay)]
           [next
            (or (edit-layout-recall lay s)
                (let-values ([(e end?)
                              (cond [(or (= s n)
                                         (char=? (string-ref text s) #\newline))
                                     (values s #t)]
                                    [(not width)
                                     (values (edit-paragraph-end text s) #t)]
                                    [else (edit-row-end
                                           text s width
                                           (edit-layout-measure lay)
                                           (edit-layout-guess lay))])])
                  (unless end? (edit-layout-guess-set! lay (- e s)))
                  (if end? (+ e 1) e)))]
           [starts (if (< (+ c 1) (fxvector-length starts))
                       starts
                       (let ([new (make-fxvector (* 2 (fxvector-length starts))
                                                 0)])
                         (do ([i 0 (+ i 1)]) ((> i c))
                           (fxvector-set! new i (fxvector-ref starts i)))
                         (edit-layout-starts-set! lay new)
                         new))])
      (fxvector-set! starts (+ c 1) next)
      (edit-layout-count-set! lay (+ c 1))
      (when (> next n)
        (edit-layout-done?-set! lay #t)
        (edit-layout-old-set! lay #f))))

  ;; Computes rows until row r is computed, or to the text's end.
  (define (edit-layout-extend! lay r)
    (let loop ()
      (unless (or (< r (edit-layout-count lay)) (edit-layout-done? lay))
        (edit-layout-step! lay)
        (loop))))

  ;; Computes rows for about ms milliseconds, or to the text's end, and
  ;; returns true once the rows reach it. It is timed, not counted: a row
  ;; costs from a fraction of a microsecond (taken back) to tens of
  ;; microseconds (measured, in a long line), so no count of rows keeps a
  ;; slice near a millisecond.
  (define (edit-layout-scan! lay ms)
    (let ([t0 (current-time 'time-monotonic)])
      (let loop ()
        (cond [(edit-layout-done? lay) #t]
              [(let ([dt (time-difference (current-time 'time-monotonic) t0)])
                 (>= (+ (* 1000 (time-second dt)) (/ (time-nanosecond dt) 1e6))
                     ms))
               #f]
              [else (edit-layout-step! lay) (loop)]))))

  ;; Returns how many rows the text has: their count once computed to the
  ;; end, or else an estimate from the characters per row so far.
  (define (edit-layout-total lay)
    (let ([c (edit-layout-count lay)])
      (if (edit-layout-done? lay)
          c
          (let ([seen (fxvector-ref (edit-layout-starts lay) c)]
                [n (string-length (edit-layout-text lay))])
            (max (+ c 1)
                 (+ c (exact (ceiling (/ (* (- n seen) c) (max 1 seen))))))))))

  ;; Returns row r's start and end (its newline, or where the next row
  ;; starts), and whether it ends at a soft break, computing the row first
  ;; if need be.
  (define (edit-row* lay r)
    (edit-layout-extend! lay r)
    (let* ([text (edit-layout-text lay)] [n (string-length text)]
           [starts (edit-layout-starts lay)]
           [s (fxvector-ref starts r)] [next (fxvector-ref starts (+ r 1))])
      (cond [(> next n) (values s n #f)]   ; the last row
            [(char=? (string-ref text (- next 1)) #\newline)
             (values s (- next 1) #f)]
            [else (values s next #t)])))

  ;; Returns row r's start and end, as (values start end).
  (define (edit-row lay r)
    (let-values ([(s e soft?) (edit-row* lay r)]) (values s e)))

  ;; Returns the last caret index of row r: a row that ends at a soft break
  ;; stops before its trailing space (or last character).
  (define (edit-row-last lay r)
    (let-values ([(s e soft?) (edit-row* lay r)])
      (if soft? (max s (- e 1)) e)))

  ;; Returns the row of index i: the last row whose start is at most i (so a
  ;; caret at a soft break shows on the next row). Rows are computed as far
  ;; as i.
  (define (edit-row-at lay i)
    (let loop ()
      (unless (or (edit-layout-done? lay)
                  (> (fxvector-ref (edit-layout-starts lay)
                                   (edit-layout-count lay))
                     i))
        (edit-layout-step! lay)
        (loop)))
    (edit-search (edit-layout-starts lay) (- (edit-layout-count lay) 1) i))

  (define (edit-caret-x lay i)
    (let-values ([(s e) (edit-row lay (edit-row-at lay i))])
      ((edit-layout-measure lay)
       (substring (edit-layout-text lay) s (max s (min i e))))))

  ;; Returns the index in row r nearest x: an x past the middle of a
  ;; character goes after it. It is found by halving, so a long row takes
  ;; log n measures, not n.
  (define (edit-index-at lay r x)
    (let*-values ([(s e) (edit-row lay r)]
                  [(text measure) (values (edit-layout-text lay)
                                          (edit-layout-measure lay))]
                  [(w) (lambda (j) (measure (substring text s j)))])
      (let loop ([lo s] [hi (edit-row-last lay r)])   ; the index is in [lo, hi]
        (let ([j (quotient (+ lo hi) 2)])
          (cond [(>= lo hi) lo]
                [(< x (/ (+ (w j) (w (+ j 1))) 2)) (loop lo j)]
                [else (loop (+ j 1) hi)])))))

  ;; Moves the caret n rows down (up when n is negative), keeping the goal
  ;; x. Up from the first row goes to 0 and down from the last row to the
  ;; end; a page that would go past them stops at that row.
  (define (edit-vertical e lay n extend?)
    (let* ([t (edit-text e)] [c (edit-caret e)] [r (edit-row-at lay c)]
           [goal (or (edit-goal e) (edit-caret-x lay c))]
           [target (+ r n)]
           [to (begin
                 (edit-layout-extend! lay target)
                 (let ([last (- (edit-layout-count lay) 1)])
                   (cond [(and (< target 0) (= r 0)) 0]
                         [(< target 0) (edit-index-at lay 0 goal)]
                         [(and (> target last) (= r last)) (string-length t)]
                         [else (edit-index-at lay (min target last) goal)])))])
      (make-edit t to (if extend? (edit-anchor e) to) goal (edit-change e))))

  ;; Returns the edit after an editing key, or #f for any other key (Return,
  ;; Escape, Tab, the printable keys, whose text comes as 'text, and the
  ;; clipboard's keys). lay is the text's layout; page is how many rows Page
  ;; Up and Page Down move.
  (define (edit-key e key mods lay page)
    (let* ([t (edit-text e)] [c (edit-caret e)]
           [shift? (and (memq 'shift mods) #t)]
           [ctrl? (and (memq 'ctrl mods) #t)])
      (let-values ([(lo hi) (edit-range e)])
        (case key
          [(left) (cond [ctrl? (edit-move e (edit-word-left t c) shift?)]
                        [(and (not shift?) (< lo hi)) (edit-move e lo #f)]
                        [else (edit-move e (- c 1) shift?)])]
          [(right) (cond [ctrl? (edit-move e (edit-word-right t c) shift?)]
                         [(and (not shift?) (< lo hi)) (edit-move e hi #f)]
                         [else (edit-move e (+ c 1) shift?)])]
          [(home)
           (edit-move e (if ctrl?
                            0
                            (let-values ([(s end) (edit-row lay
                                                            (edit-row-at lay
                                                                         c))])
                              s))
                      shift?)]
          [(end) (edit-move e (if ctrl?
                                  (string-length t)
                                  (edit-row-last lay (edit-row-at lay c)))
                            shift?)]
          [(up) (edit-vertical e lay -1 shift?)]
          [(down) (edit-vertical e lay 1 shift?)]
          [(page-up) (edit-vertical e lay (- page) shift?)]
          [(page-down) (edit-vertical e lay page shift?)]
          [(backspace) (edit-erase e (if ctrl? (edit-word-left t c) (- c 1)))]
          [(delete) (edit-erase e (if ctrl? (edit-word-right t c) (+ c 1)))]
          [(#\a) (and (equal? mods '(ctrl)) (edit-all t))]
          [else #f]))))

  ;; Returns text's rows at width as a vector of (start . end), all made at
  ;; once (for a label).
  (define (edit-wrap text width measure)
    (let ([lay (edit-layout-of #f text width #f measure #f)])
      (edit-layout-extend! lay (string-length text))
      (let loop ([r (- (edit-layout-count lay) 1)] [acc '()])
        (if (< r 0)
            (list->vector acc)
            (let-values ([(s e) (edit-row lay r)])
              (loop (- r 1) (cons (cons s e) acc))))))))
