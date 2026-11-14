;;; tests/units/edit.ss — the edit kit, with no window: editing, rows and their
;;; lazy layout. Text measures 7 px a character.

;;; the edit kit, the widget kit and Tasks, pure
;;; Text editing, rows, dates, flow and table keys, and Tasks' own
;;; procedures, with no window: text measures 7 px a character.

(define (m7 s) (* 7 (string-length s)))
(define (lay-of text width . measure)
  (edit-layout-of #f text width #f (if (pair? measure) (car measure) m7) #f))
(define (ed text caret . anchor)
  (make-edit text caret (if (pair? anchor) (car anchor) caret) #f #f))
(define (state e) (list (edit-text e) (edit-caret e) (edit-anchor e)))
(define (key e k . mods)
  (edit-key e k mods (lay-of (edit-text e) 1000) 1))
(define fbq "foo-bar  baz.qux")

(check "insert at a caret, over a selection, at both ends, into empty text"
       (and (equal? (state (edit-insert (ed "abc" 1) "X")) '("aXbc" 2 2))
            (equal? (state (edit-insert (ed "abcd" 1 3) "X")) '("aXd" 2 2))
            (equal? (state (edit-insert (ed "abc" 0) "X")) '("Xabc" 1 1))
            (equal? (state (edit-insert (ed "abc" 3) "X")) '("abcX" 4 4))
            (equal? (state (edit-insert (ed "" 0) "X")) '("X" 1 1))
            (equal? (state (edit-insert (ed "abc" 1 2) "")) '("ac" 1 1))))

(check "with a most, typing stops at it, a paste is cut to fit, and a \
        selection makes room; no most is no limit"
       (and (equal? (state (edit-insert (ed "abc" 3) "X" 3)) '("abc" 3 3))
            (equal? (state (edit-insert (ed "abc" 1) "XYZ" 5)) '("aXYbc" 3 3))
            (equal? (state (edit-insert (ed "abcd" 1 3) "XYZ" 4))
                    '("aXYd" 3 3))
            (equal? (state (edit-insert (ed "abc" 3) "XY" #f))
                    '("abcXY" 5 5))))

(check "what changes nothing keeps the very string: an empty insert, an \
        erase of nothing, a move, a text clean already"
       (let ([t "abc"])
         (and (eq? t (edit-text (edit-insert (ed t 1) "")))
              (eq? t (edit-text (key (ed t 0) 'backspace)))
              (eq? t (edit-text (key (ed t 1) 'right)))
              (eq? t (edit-text (edit-insert (ed t 3) "X" 3)))
              (eq? t (edit-clean t #t)))))

(check "an edit says what it changed, the text before and the range \
        replaced; a caret move keeps that word, and so does an edit \
        that changes nothing"
       (let* ([t "abcdef"] [e1 (edit-insert (ed t 2 4) "XYZ")]
              [e2 (key e1 'left)] [e3 (edit-insert e2 "")]
              [e4 (key (ed t 3) 'backspace)])
         (and (equal? (edit-change e1) (list t 2 4))
              (eq? (car (edit-change e1)) t)
              (eq? (edit-change e2) (edit-change e1))
              (eq? (edit-change e3) (edit-change e1))
              (equal? (edit-change e4) (list t 2 3))
              (not (edit-change (ed t 3))))))

(check "Backspace at the start and Delete at the end change nothing; \
        they erase a character, a selection, or a word with Ctrl"
       (and (equal? (state (key (ed "abc" 0) 'backspace)) '("abc" 0 0))
            (equal? (state (key (ed "abc" 3) 'delete)) '("abc" 3 3))
            (equal? (state (key (ed "abc" 2) 'backspace)) '("ac" 1 1))
            (equal? (state (key (ed "abc" 1) 'delete)) '("ac" 1 1))
            (equal? (state (key (ed "abcd" 3 1) 'backspace)) '("ad" 1 1))
            (equal? (state (key (ed fbq 16) 'backspace 'ctrl))
                    '("foo-bar  baz." 13 13))
            (equal? (state (key (ed fbq 9) 'backspace 'ctrl)) '("baz.qux" 0 0))
            (equal? (state (key (ed fbq 0) 'delete 'ctrl)) '("  baz.qux" 0 0))))

(check "Left and Right collapse a selection to its side; Shift extends it \
        and shrinks it across the anchor; Ctrl moves by words; Home, End"
       (and (equal? (state (key (ed "abcd" 3 1) 'left)) '("abcd" 1 1))
            (equal? (state (key (ed "abcd" 1 3) 'right)) '("abcd" 3 3))
            (equal? (state (key (ed "abcd" 2) 'right 'shift)) '("abcd" 3 2))
            (equal? (state (key (key (key (ed "abcd" 2) 'right 'shift)
                                     'left 'shift)
                                'left 'shift))
                    '("abcd" 1 2))
            (equal? (state (key (ed fbq 0) 'right 'ctrl)) (list fbq 7 7))
            (equal? (state (key (ed fbq 7) 'right 'ctrl)) (list fbq 12 12))
            (equal? (state (key (ed fbq 13) 'left 'ctrl)) (list fbq 9 9))
            (equal? (state (key (ed fbq 12) 'left 'ctrl 'shift))
                    (list fbq 9 12))
            (equal? (state (key (ed "abc" 1) 'home)) '("abc" 0 0))
            (equal? (state (key (ed "abc" 1) 'end 'shift)) '("abc" 3 1))))

(define (bounds f text i) (call-with-values (lambda () (f text i)) list))
(check "a double click's word: at its start, end and inside, on spaces, \
        across - and _, on a word's last character; a triple click's line"
       (and (equal? (bounds edit-word-bounds "foo bar" 0) '(0 3))
            (equal? (bounds edit-word-bounds "foo bar" 7) '(4 7))
            (equal? (bounds edit-word-bounds "foo bar" 1) '(0 3))
            (equal? (bounds edit-word-bounds "foo bar" 3) '(0 3))
            (equal? (bounds edit-word-bounds "a   b" 2) '(1 4))
            (equal? (bounds edit-word-bounds "foo-bar_baz qux" 5) '(0 11))
            (equal? (bounds edit-word-bounds "a.b" 1) '(0 1))
            (equal? (bounds edit-word-bounds "a.b" 2) '(2 3))
            (equal? (bounds edit-line-bounds "ab\ncd\nef" 4) '(3 5))))

(check "Ctrl+A selects everything; λ is one character"
       (let ([e (key (ed "λx y" 1) #\a 'ctrl)])
         (and (equal? (state e) '("λx y" 4 0))
              (equal? (edit-selection e) "λx y")
              (equal? (state (key (ed "λx" 0) 'right)) '("λx" 1 1)))))

(check "edit-key leaves Return, Escape, Tab, typed keys and Ctrl+C"
       (for-all (lambda (k) (not (apply key (ed "abc" 1) k)))
                '((return) (escape) (tab) (#\a) (#\c ctrl))))

(define (wrap text width . measure)
  (vector->list (edit-wrap text width (if (pair? measure) (car measure) m7))))
(check "wrapping: a row, newlines, empty text, a trailing newline; a soft \
        break keeps its space; a word wider than the width, and a width \
        under one character, break between characters; a last space \
        hangs"
       (and (equal? (wrap "hello" 100) '((0 . 5)))
            (equal? (wrap "ab\ncd" 100) '((0 . 2) (3 . 5)))
            (equal? (wrap "" 100) '((0 . 0)))
            (equal? (wrap "ab\n" 100) '((0 . 2) (3 . 3)))
            (equal? (wrap "aaa bbb ccc" 56) '((0 . 8) (8 . 11)))
            (equal? (wrap "aaa bbb ccc" 42) '((0 . 4) (4 . 8) (8 . 11)))
            (equal? (wrap "abcdefgh" 21) '((0 . 3) (3 . 6) (6 . 8)))
            (equal? (wrap "abc" 3) '((0 . 1) (1 . 2) (2 . 3)))
            (equal? (wrap "hello " 35) '((0 . 6)))))

;; Widths that differ: a space and narrow letters 3, wide ones 11, the
;; rest 7.
(define (mp s)
  (let loop ([i 0] [w 0])
    (if (= i (string-length s))
        w
        (loop (+ i 1) (+ w (case (string-ref s i)
                             [(#\space #\i #\l) 3]
                             [(#\m #\w) 11]
                             [else 7]))))))

;; The wrapping rule as plainly as it can be said: each row measures the
;; rest of its paragraph, then every space, then every prefix.
(define (wrap-plainly text width . measure)
  (let* ([n (string-length text)]
         [m (if (pair? measure) (car measure) m7)]
         [fits? (lambda (s e) (<= (m (substring text s e)) width))]
         [end (lambda (p)
                (let loop ([q p])
                  (if (or (= q n) (char=? (string-ref text q) #\newline))
                      q
                      (loop (+ q 1)))))])
    (let para ([p 0] [rows '()])
      (let ([q (end p)])
        (define (next rows) (if (< q n) (para (+ q 1) rows) (reverse rows)))
        (let row ([s p] [rows rows])
          (cond
            [(and (= s q) (> s p)) (next rows)]
            [(fits? s q) (next (cons (cons s q) rows))]
            [else
             (let* ([ks (filter (lambda (k) (and (char=? (string-ref text k)
                                                         #\space)
                                                 (fits? s k)))
                                (map (lambda (i) (+ s i)) (iota (- q s))))]
                    [e (if (pair? ks)
                           (+ 1 (apply max ks))
                           (let loop ([j (+ s 1)])
                             (if (and (< j q) (fits? s (+ j 1)))
                                 (loop (+ j 1))
                                 j)))])
               (row e (cons (cons s e) rows)))]))))))

(define (next-random x) (mod (+ (* x 1103515245) 12345) 2147483648))

;; A made-up text of len characters from seed, of the letters in abc.
(define (made-up len seed abc)
  (let fill ([k 0] [x seed] [acc '()])
    (if (= k len)
        (values (list->string acc) x)
        (fill (+ k 1) (next-random x)
              (cons (string-ref abc (mod (quotient x 9) (string-length abc)))
                    acc)))))

;; The rows as a typist breaks them, a character at a time, sharing no
;; code or search with the kit: a row takes characters while what it
;; holds fits, minding the last space before which it fit; at one that
;; does not fit, it breaks after that space (which hangs past the width),
;; else before the character, keeping one at least. A newline ends a row.
(define (wrap-by-character text width m)
  (let ([n (string-length text)])
    (define (end? j) (or (= j n) (char=? (string-ref text j) #\newline)))
    (define (fits? s e) (<= (m (substring text s e)) width))
    (let row ([s 0] [p 0] [rows '()])   ; a row from s, its paragraph's p
      (if (and (> s p) (end? s))   ; a break ended the paragraph
          (if (= s n) (reverse rows) (row (+ s 1) (+ s 1) rows))
          (let walk ([j s] [space #f])   ; [s, j) fits
            (if (end? j)
                (let ([rows (cons (cons s j) rows)])
                  (if (= j n) (reverse rows) (row (+ j 1) (+ j 1) rows)))
                (let ([space (if (char=? (string-ref text j) #\space)
                                 j
                                 space)])
                  (if (fits? s (+ j 1))
                      (walk (+ j 1) space)
                      (let ([e (if space (+ space 1) (max j (+ s 1)))])
                        (row e p (cons (cons s e) rows)))))))))))

(check "a character at a time breaks the made-up texts where the plain \
        rule does"
       (let loop ([i 0] [seed 5])
         (or (= i 500)
             (let-values ([(text x) (made-up (mod (quotient seed 7) 41) seed
                                             "aimw  \n")])
               (let ([width (mod x 78)] [m (if (even? i) m7 mp)])
                 (and (equal? (wrap-by-character text width m)
                              (wrap-plainly text width m))
                      (loop (+ i 1) (next-random x))))))))

(check "wrapping breaks every text where the plain rule does: 2000 made-up \
        texts of letters, spaces and newlines, at widths from 0 to 11 \
        characters, measured alike and unlike"
       (let loop ([i 0] [seed 7])
         (or (= i 2000)
             (let-values ([(text x) (made-up (mod (quotient seed 7) 41) seed
                                             "aimw  \n")])
               (let ([width (mod x 78)] [m (if (even? i) m7 mp)])
                 (and (equal? (wrap text width m) (wrap-plainly text width m))
                      (loop (+ i 1) (next-random x))))))))

;; A layout's rows, computed to the end.
(define (rows-of lay)
  (edit-layout-extend! lay (string-length (edit-layout-text lay)))
  (map (lambda (r) (call-with-values (lambda () (edit-row lay r)) cons))
       (iota (edit-layout-count lay))))

(check "the lazy layout follows edits: after each of 3000 random \
        insertions, deletions and replacements, told where or not, the \
        rows it keeps, takes back and computes, partly or to the end, are \
        those a character at a time finds"
       (let loop ([i 0] [seed 11] [text ""] [lay #f] [width 40] [m m7])
         (cond
           [(= i 3000) #t]
           [(zero? (mod i 100))   ; a new width and measure, a new text
            (let-values ([(t x) (made-up 300 seed "aaimw  \n")])
              (loop (+ i 1) (next-random x) t #f (+ 10 (mod x 90))
                    (if (even? (quotient i 100)) m7 mp)))]
           [else
            (let*-values ([(n) (string-length text)]
                          [(lo) (mod seed (+ n 1))]
                          [(hi) (if (zero? (mod i 3))   ; an insertion
                                    lo
                                    (min n (+ lo (mod (quotient seed 5)
                                                      (if (zero? (mod i 11))
                                                          90
                                                          9)))))]
                          [(ins x) (made-up (if (= (mod i 3) 1)
                                                0
                                                (mod (quotient seed 3) 7))
                                            (next-random seed) "aimw \n")]
                          [(new) (string-append (substring text 0 lo) ins
                                                (substring text hi n))]
                          ;; told where, as by an edit, or compared
                          [(lay) (edit-layout-of lay new width #f m
                                                 (and (even? (quotient i 2))
                                                      (list text lo hi)))])
              ;; as a draw would: rows as far as some index, sometimes all
              (if (zero? (mod x 5))
                  (edit-layout-extend! lay (string-length new))
                  (edit-row-at lay (mod x (+ 1 (string-length new)))))
              (and (or (not (zero? (mod i 7)))
                       (equal? (rows-of (lay-of new width m)) (rows-of lay)))
                   (equal? (wrap-by-character new width m) (rows-of lay))
                   (loop (+ i 1) (next-random x) new lay width m)))])))

(check "a layout computes rows only as far as they are asked for, and \
        remembers them; its total is a count once they reach the end, \
        an estimate before"
       (let* ([n 0] [count (lambda (s) (set! n (+ n 1)) (m7 s))]
              [text (apply string-append (make-list 2000 "words of a row "))]
              [lay (lay-of text 280 count)])
         (edit-layout-extend! lay 14)
         (let ([first (edit-layout-count lay)]
               [estimate (edit-layout-total lay)])
           (edit-row-at lay 3000)
           (let ([again n])
             (edit-row-at lay 3000)
             (and (= first 15) (= again n) (not (edit-layout-done? lay))
                  (edit-layout-scan! lay 1000) (edit-layout-done? lay)
                  (= (edit-layout-total lay) (edit-layout-count lay)
                     (length (wrap text 280)))
                  (< (abs (- estimate (edit-layout-count lay)))
                     (* 1/10 (edit-layout-count lay))))))))

;; The worst cases' texts at m7 and 280 px (40 characters a row): one
;; paragraph of words; no spaces; every row exactly full, so that a
;; character typed at its start moves a word down each row (a cascade).
(define (worst-case which n)
  (let ([o (open-output-string)])
    (let loop ([i 0])
      (when (< i n)
        (case which
          [(words) (put-string o (vector-ref '#("the " "quick " "brown "
                                                 "fox " "jumps " "a ")
                                             (mod i 6)))]
          [(none) (put-string o "0123456789abcdef")]
          [(full) (put-string o "aaaaaaaaa bbbbbbbbb ccccccccc dddddddddd ")])
        (loop (+ i 1))))
    (substring (get-output-string o) 0 n)))

;; What a keystroke measures, as a text area 14 rows high does it: the
;; layout follows the new text, the rows down to the caret's view are
;; computed (the view follows the caret), and the caret's x. Before it,
;; the view showed the caret at k: rows to there were computed then.
(define (keystroke-measures text k op)
  (let* ([n 0] [count (lambda (s) (set! n (+ n 1)) (m7 s))]
         [lay (lay-of text 280 count)])
    (define (view! lay caret)
      (edit-layout-extend! lay (+ (edit-row-at lay caret) 15))
      (edit-caret-x lay caret))
    (view! lay k)
    (set! n 0)
    (let* ([e (op (ed text k) lay)]
           [lay (edit-layout-of lay (edit-text e) 280 #f count
                                (edit-change e))])
      (view! lay (edit-caret e))
      n)))

(check "a keystroke in each worst case measures in proportion to the rows \
        in view, at most 4 a row, at 16,384 characters as at 65,536: \
        typing at the start, middle and end, Backspace, Delete, a paste of \
        a few words, everything selected and deleted, the wheel"
       (let ([ops
              (list (cons 0 (lambda (e lay) (edit-insert e "x")))
                    (cons 1/2 (lambda (e lay) (edit-insert e "x")))
                    (cons 1 (lambda (e lay) (edit-insert e "x")))
                    (cons 1/2 (lambda (e lay)
                                (edit-key e 'backspace '() lay 14)))
                    (cons 1/2 (lambda (e lay) (edit-key e 'delete '() lay 14)))
                    (cons 1/2 (lambda (e lay) (edit-insert e "pasted words ")))
                    (cons 1/2 (lambda (e lay)
                                (edit-key (edit-all (edit-text e)) 'backspace
                                          '() lay 14)))
                    (cons 0 (lambda (e lay)   ; three rows down, no change
                              (edit-move e (edit-row-last lay 3) #f))))])
         (for-all
          (lambda (which)
            (for-all
             (lambda (op)
               (let ([at (lambda (n)
                           (let ([text (worst-case which n)])
                             (keystroke-measures
                              text (exact (floor (* (car op) n))) (cdr op))))])
                 (let ([small (at 16384)] [big (at 65536)])
                   (or (and (<= small (* 4 17)) (<= big (* 4 17)))
                       (begin (printf "  ~a: ~a then ~a measures\n" which
                                      small big)
                              #f)))))
             ops))
          '(words none full))))

(check "Ctrl+End computes the rows to the end once, and a second one \
        measures none of them again"
       (let* ([n 0] [count (lambda (s) (set! n (+ n 1)) (m7 s))]
              [text (worst-case 'words 65536)]
              [lay (lay-of text 280 count)])
         (edit-layout-extend! lay 15)
         (let* ([e (edit-key (ed text 0) 'end '(ctrl) lay 14)]
                [r (edit-row-at lay (edit-caret e))] [first n])
           (edit-row-at lay (edit-caret e))
           (edit-key (ed text 0) 'end '(ctrl) lay 14)
           (and (= (edit-caret e) 65536) (edit-layout-done? lay)
                (> first 1000) (= n first)))))

;; Short lines, as in a log or base64: each a paragraph of its own.
(define (short-lines n)
  (substring (apply string-append
                    (map (lambda (i) (format "line ~a of short lines\n" i))
                         (iota (quotient n 20))))
             0 n))

(check "an edit takes back the rows past it: typed at the start or the \
        middle of 65,536 characters of words, or of short lines, or a \
        line deleted there, the rows to the end come back with a few \
        measured, and they are a whole wrap's"
       (for-all
        (lambda (text op)
          (let* ([n 0] [count (lambda (s) (set! n (+ n 1)) (m7 s))]
                 [lay (lay-of text 280 count)])
            (edit-layout-extend! lay (string-length text))
            (set! n 0)
            (let* ([e (op text)]
                   [lay (edit-layout-of lay (edit-text e) 280 #f count
                                        (edit-change e))])
              (edit-layout-extend! lay (string-length (edit-text e)))
              (or (and (<= n 20) (edit-layout-done? lay)
                       (equal? (rows-of lay)
                               (rows-of (lay-of (edit-text e) 280))))
                  (begin (printf "  ~a measures, ~a\n" n
                                 (substring (edit-text e) 0 50))
                         #f)))))
        (list (worst-case 'words 65536) (worst-case 'words 65536)
              (short-lines 65536) (short-lines 65536) (short-lines 65536))
        (list (lambda (t) (edit-insert (ed t 0) "x"))
              (lambda (t) (edit-insert (ed t 32768) "x"))
              (lambda (t) (edit-insert (ed t 3) "x"))
              (lambda (t) (edit-erase (ed t 30000) 30001))
              (lambda (t) (edit-erase (ed t 40 63) 0)))))

;; What an engine counts of a thunk: a tick for each procedure call or
;; turn of a loop, so a character looked at in a loop is one. A copy
;; (string-copy!, fxvector-copy) is one call before Chez 10.4.0; from it,
;; a copy counts by its size, up to a timer period (1,000) for a long one
;; (its release notes' "Interrupts and Large-Vector Operations").
(define (ticks thunk)
  ((make-engine thunk) 1000000000 (lambda (left . r) (- 1000000000 left))
   (lambda (e) +inf.0)))

;; A row's ticks at most. The worst case is 5,527 ticks before Chez
;; 10.4.0 and 9,424 from it, where a keystroke's copies of the text count
;; a period each; the bound leaves room for both, and stays under what a
;; look at every character would count.
(define edit-test-row-ticks 600)

(check "a keystroke's text work, in an engine's ticks, is at most 600 a \
        row in view (10,200 for 17 rows) at 65,535 characters as at \
        16,383, in each worst case, where a look at every character would \
        be 16,383 at least: the edit (as a description's box makes it), \
        Tasks taking the text from the box, the rows that follow it to the \
        caret's view, and the editor's line and column"
       (let ([ops (list (cons 0 (lambda (e lay) (edit-insert e "x" 65536)))
                        (cons 1/2 (lambda (e lay) (edit-insert e "x" 65536)))
                        (cons 1 (lambda (e lay) (edit-insert e "x" 65536)))
                        (cons 1/2 (lambda (e lay)
                                    (edit-insert e "\n" 65536)))
                        (cons 1/2 (lambda (e lay)
                                    (edit-key e 'backspace '() lay 14)))
                        (cons 1 (lambda (e lay)
                                  (edit-key e 'backspace '() lay 14)))
                        (cons 1/2 (lambda (e lay)
                                    (edit-key e 'delete '() lay 14))))])
         (define (work text k op)   ; the ticks of op at k in text
           (let* ([lay (lay-of text 280)]
                  [view! (lambda (lay caret)
                           (edit-layout-extend! lay (+ (edit-row-at lay caret)
                                                       15))
                           (edit-caret-x lay caret))]
                  [editor (make-tasks-editor #f #f #f text text #f #f)]
                  [e (ed text k)])
             (view! lay k)
             (tasks-editor-line-column editor e)
             (ticks (lambda ()
                      (let* ([e (op e lay)]
                             [d (tasks-normalize 'task-set! 'description
                                                 (edit-text e))]
                             [lay (edit-layout-of lay d 280 #f m7
                                                  (edit-change e))])
                        (view! lay (edit-caret e))
                        (tasks-editor-line-column editor e))))))
         (for-all
          (lambda (which)
            (for-all
             (lambda (op)
               (let ([at (lambda (n)
                           (let ([text (worst-case which n)])
                             (work text (exact (floor (* (car op) n)))
                                   (cdr op))))])
                 (let ([small (at 16383)] [big (at 65535)])
                   (or (< (max small big) (* edit-test-row-ticks 17))
                       (begin (printf "  ~a: ~a then ~a ticks\n" which
                                      small big)
                              #f)))))
             ops))
          '(words none full))))

(check "the editor's line and column, counted on from the last count, are \
        a plain count's through 3000 random edits, moves and clicks, \
        counted after each or after two"
       (let ([editor (make-tasks-editor #f #f #f "" "" #f #f)])
         (define (plainly t c)
           (let loop ([i 0] [line 1] [column 1])
             (cond [(= i c) (list line column)]
                   [(char=? (string-ref t i) #\newline)
                    (loop (+ i 1) (+ line 1) 1)]
                   [else (loop (+ i 1) line (+ column 1))])))
         (define (next e seed)   ; an edit, a move or a click
           (let*-values ([(t) (edit-text e)] [(n) (string-length t)]
                         [(ins x) (made-up (mod seed 5) seed "ab\n\n")])
             (values (case (mod (quotient seed 7) 6)
                       [(0 1) (edit-insert e ins)]
                       [(2) (edit-erase e (- (edit-caret e) 1))]
                       [(3) (edit-erase e (+ (edit-caret e) 1))]
                       [(4) (edit-move e (mod x (+ n 1)) (odd? x))]
                       [else (edit-at t (mod x (+ n 1)))])
                     (next-random x))))
         (let loop ([i 0] [seed 3] [e (ed "" 0)])
           (or (= i 3000)
               (let-values ([(line column)
                             (tasks-editor-line-column editor e)])
                 (and (equal? (list line column)
                              (plainly (edit-text e) (edit-caret e)))
                      (let*-values ([(e seed) (next e seed)]
                                    [(e seed) (if (zero? (mod i 5))
                                                  (next e seed)
                                                  (values e seed))])
                        (loop (+ i 1) seed e))))))))

(check "a search looks through a task's texts once for each change of \
        them: matched again, a 65,536-character description is not \
        searched, and changed, it is"
       (let ([t (make-task 0 "Title" (worst-case 'words 65536) 'todo
                           'feature 'normal #f '() #f '() '() 0 0)]
             [words (tasks-words "zebra")])
         (define (match) (tasks-match? t words #f #f #f #f #t))
         (let* ([first (ticks match)] [again (ticks match)])
           (task-description-set! t (string-append (task-description t)
                                                   " zebra"))
           (and (> first 65536) (< again 100) (match)))))

(check "wrapping measures a row about twice, not the paragraph's rest: a \
        6000-character paragraph and a 2000-character word measure under \
        5 characters per character"
       (let* ([n 0]
              [count (lambda (s) (set! n (+ n (string-length s))) (m7 s))]
              [measured (lambda (text)
                          (set! n 0)
                          (edit-wrap text 280 count)
                          (/ n (string-length text)))])
         (and (< (measured (apply string-append (make-list 1200 "word ")))
                 5)
              (< (measured (make-string 2000 #\W)) 5))))

(check "wrapping scans a row, not the rest of a long word: 100,000 \
        characters wrap within a handler's fuel, as one word or as words"
       (and (within-fuel? (lambda () (edit-wrap (make-string 100000 #\W) 280
                                                m7)))
            (within-fuel?
             (lambda ()
               (edit-wrap (apply string-append (make-list 20000 "word ")) 280
                          m7)))))

;; The index nearest x as plainly as it can be said: a character at a time.
(define (index-plainly lay r x)
  (let-values ([(s e) (edit-row lay r)])
    (let ([text (edit-layout-text lay)] [last (edit-row-last lay r)])
      (let loop ([j s])
        (if (or (>= j last)
                (< x (/ (+ (m7 (substring text s j))
                           (m7 (substring text s (+ j 1))))
                        2)))
            j
            (loop (+ j 1)))))))

(check "a click lands where a character at a time finds it, in log n \
        measures: 34 at most in a row of 100,000 characters"
       (let* ([n 0] [count (lambda (s) (set! n (+ n 1)) (m7 s))]
              [long (make-string 100000 #\W)]
              [at (edit-index-at (lay-of long #f count) 0 350003)])
         (and (= at 50000) (<= n 34)
              (for-all
               (lambda (text)
                 (let ([lay (lay-of text 30)])
                   (edit-layout-extend! lay (string-length text))
                   (for-all
                    (lambda (r)
                      (for-all (lambda (x)
                                 (= (edit-index-at lay r x)
                                    (index-plainly lay r x)))
                               (map (lambda (i) (- (/ i 2) 5)) (iota 90))))
                    (iota (edit-layout-count lay)))))
               '("" "a" "abc def" "aaa bbb ccc ddd" "ab\ncd\n"
                 "abcdefghijk")))))

(check "a wrapped label breaks a word wider than it, and its lines end \
        without the space a soft break leaves"
       (let-values ([(w h) (ui-label-size '(wrap) (make-string 200 #\W) 100)])
         (and (> h (* 5 (font-line-height 'ui)))
              (for-all (lambda (l) (<= (text-width l 'ui) 100))
                       (ui-label-lines (make-string 200 #\W) 100 'ui))
              (equal? (ui-label-lines "No task matches this, with Kind: Bug."
                                      120 'ui)
                      (text-wrap "No task matches this, with Kind: Bug."
                                 120 'ui)))))

(let ([soft (lay-of "aaa bbb ccc" 42)] [hard (lay-of "ab\ncd" 100)]
      [three (lay-of "abcdef\nab\nabcdef" 100)])
  (define (vert e lay dir) (state (edit-vertical e lay dir #f)))
  (check "a caret at a soft break shows on the next row, at a hard break on \
          its own; a click lands nearest a character's middle"
         (and (= 1 (edit-row-at soft 4)) (= 0 (edit-row-at soft 3))
              (= 0 (edit-row-at hard 2)) (= 1 (edit-row-at hard 3))
              (= 1 (edit-index-at (lay-of "abcd" 100) 0 10))
              (= 2 (edit-index-at (lay-of "abcd" 100) 0 11))
              (= 0 (edit-index-at (lay-of "abcd" 100) 0 3))))
  (check "Up and Down keep the goal across a short row; Up from the first \
          row goes to 0, Down from the last to the end; End stops before a \
          soft row's space"
         (let* ([e (ed "abcdef\nab\nabcdef" 5)]
                [d1 (edit-vertical e three 1 #f)]
                [d2 (edit-vertical d1 three 1 #f)])
           (and (= 9 (edit-caret d1)) (= 15 (edit-caret d2))
                (equal? (vert e three -1) '("abcdef\nab\nabcdef" 0 0))
                (equal? (vert d2 three 1) '("abcdef\nab\nabcdef" 16 16))
                (= 7 (edit-caret (edit-key (ed "aaa bbb ccc" 4) 'end '()
                                           soft 1)))))))

(check "Page Down and Up move a page of rows keeping the goal; past the \
        first or last row a page goes to it, and from it to the text's \
        start or end"
       (let* ([text (apply string-append
                           (map (lambda (i) (format "line ~2,'0d\n" i))
                                (iota 30)))]
              [lay (lay-of text 1000)]
              [at (lambda (line column) (+ (* 8 line) column))]
              [page (lambda (c k) (edit-caret (edit-key (ed text c) k '() lay
                                                        10)))])
         (and (= (page (at 2 3) 'page-down) (at 12 3))
              (= (page (at 12 3) 'page-up) (at 2 3))
              (= (page (at 5 3) 'page-up) (at 0 3))
              (= (page (at 0 3) 'page-up) 0)
              (= (page (at 25 3) 'page-down) (at 30 0))
              (= (page (at 30 0) 'page-down) (string-length text)))))

(check "edit-clean drops control characters, but a tab becomes a \
        space; without newlines they do too"
       (and (equal? (edit-clean "a\tb\r\nc\x1;" #t) "a b\nc")
            (equal? (edit-clean "a\tb\r\nc" #f) "a b c")
            (equal? (edit-clean "a\x7f;b" #t) "ab")))
