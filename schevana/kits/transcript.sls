;;; (schevana kits transcript) — lines of text that only grow, as a REPL shows
;;; them: wrapped to the width, the newest at the bottom, each in a style,
;;; with Scheme in its colors. An app built on it holds one per window and
;;; adds to it: the REPL, with an input under it; the Debug REPL, with none.
;;;
;;;   (define t (transcript-new))
;;;   (transcript-add! t 'result "42")        complete lines, on a fresh line
;;;   (transcript-append! t 'output "so f")   text in pieces, on the open line
;;;   (transcript-draw-view t w h)            all of it, in a draw handler
;;;
;;; A line's style says how it is drawn: input and request lines are Scheme
;;; after a prompt of three characters, faint for input and in accent for a
;;; request; the other styles have a color each (transcript-draw-style-color).
;;;
;;; Its text can be selected and copied: a press and a drag select it, two
;;; clicks a word and three a line, and a right press opens the text menu
;;; (transcript-press!). Each draw records which lines it placed where
;;; (transcript-place!), and the pointer is read against that. A position
;;; is (line . index): the line's number, counted from the first line ever
;;; added, so that the lines the oldest end loses move no position, and a
;;; character's index in it. An app that shows lines after t's (a REPL's
;;; input) numbers them on from (transcript-end t), and hands their texts,
;;; in order, to transcript-placing!.

(library (schevana kits transcript)
  (export
    transcript-lines transcript-count transcript-scroll transcript-scroll-set!
    transcript-new transcript-pad transcript-inset transcript-line-height
    transcript-clear!
    transcript-append! transcript-add! transcript-rows transcript-fill-colors!
    transcript-draw-style-color transcript-draw-scheme transcript-draw-line
    transcript-draw-scrollbar transcript-draw-view transcript-end
    transcript-placing! transcript-place! transcript-point transcript-press!
    transcript-drag! transcript-release! transcript-bar-pointer
    transcript-selection transcript-more)
  (import (chezscheme)
          (only (schevana base) at-load clamp library-layer string-split)
          (only (schevana core) alpha color-default! draw-text fill-box
                font-char-width font-line-height style theme theme-default!
                theme-rule)
          (only (schevana kits ui) make-ui ui-active? ui-begin! ui-end!
                ui-memo! ui-mouse-down ui-mouse-move ui-mouse-up
                ui-open-text-menu! ui-pointer ui-scrollbar ui-scrollbar-inset
                ui-scrollbar-width))

  (library-layer kits)

  (define-record-type transcript
    (nongenerative schevana-transcript-3)
    (fields (mutable lines)    ; newest first: ((style . text) ...)
            (mutable count)
            (mutable open?)    ; is the newest line unterminated output?
            (mutable scroll)   ; visual rows scrolled back from the bottom
            (mutable dropped)  ; how many lines the oldest end has lost
            (mutable sel)      ; what is selected, (anchor . end), or #f
            (mutable held?)    ; does a left press select as it moves?
            (mutable placed)   ; the lines last drawn: ((line top rows len) ...)
            (mutable grid)     ; their grid, #(x cw lh cols), or #f
            (mutable more)     ; the texts of the lines drawn after t's
            ui))               ; the kit's, for the scroll bar

  (define (transcript-new)
    (let ([ui (make-ui)])
      (ui-memo! ui 'ui-cursor 'ibeam)   ; over the lines
      (make-transcript '() 0 #f 0 0 #f #f '() #f '() ui)))

  (define transcript-max-lines 4000)
  (define transcript-pad 10)

  ;; Returns how far in from a side (left or right) the lines are: their
  ;; margin, or, where the style's bars are there whether they are needed or
  ;; not (scrollbar-full), the room its bar keeps on that side if more.
  (define (transcript-inset side)
    (if (theme 'scrollbar-full)
        (max transcript-pad (ui-scrollbar-inset side))
        transcript-pad))

  ;; A line is the code font's and a little room, which a look sets (the
  ;; Lisp machines' 2).
  (at-load
   (theme-default! 'transcript-line-spacing 3))
  (define (transcript-line-height)
    (+ (theme 'transcript-line-spacing) (font-line-height 'mono)))

  (define (transcript-clear! t)
    (transcript-dropped-set! t (transcript-end t))
    (transcript-lines-set! t '())
    (transcript-count-set! t 0)
    (transcript-open?-set! t #f)
    (transcript-sel-set! t #f)
    (transcript-placed-set! t '()))

  ;; Returns the number that a line added next would have.
  (define (transcript-end t) (+ (transcript-dropped t) (transcript-count t)))

  (define (transcript-push! t style text)
    (transcript-lines-set! t (cons (cons style text) (transcript-lines t)))
    (transcript-count-set! t (+ 1 (transcript-count t)))
    (when (> (transcript-count t) (+ transcript-max-lines 500))
      (transcript-lines-set! t (list-head (transcript-lines t)
                                          transcript-max-lines))
      (transcript-dropped-set! t (- (transcript-end t) transcript-max-lines))
      (transcript-count-set! t transcript-max-lines)))

  ;; Appends text that may contain newlines. Output can arrive in pieces, so
  ;; the first piece goes on the open line when its style is the same.
  (define (transcript-append! t style str)
    (let loop ([pieces (string-split str #\newline)] [first? #t])
      (unless (null? pieces)
        (let ([p (car pieces)] [last? (null? (cdr pieces))])
          (cond
            [(and first? (transcript-open? t)
                  (eq? (caar (transcript-lines t)) style))
             (set-cdr! (car (transcript-lines t))
                       (string-append (cdar (transcript-lines t)) p))]
            [(and last? (string=? p "")) (void)]
            [else (transcript-push! t style p)])
          (when last? (transcript-open?-set! t (not (string=? p ""))))
          (loop (cdr pieces) #f)))))

  ;; Adds complete lines, starting on a fresh line, and scrolls to show them.
  (define (transcript-add! t style str)
    (transcript-open?-set! t #f)
    (transcript-append! t style (string-append str "\n"))
    (transcript-scroll-set! t 0))

  ;; Returns how many visual rows, of cols characters each, a logical line
  ;; of len characters takes.
  (define (transcript-rows len cols)
    (max 1 (quotient (+ len cols -1) cols)))

  (define (transcript-fill-colors! v a b x)
    (do ([i a (+ i 1)]) ((>= i (min b (vector-length v)))) (vector-set! v i x)))

  (define transcript-keywords
    '(define lambda let let* letrec letrec* if cond case when unless begin set!
       do
      quote quasiquote and or define-syntax syntax-rules syntax-case let-values
      let*-values define-record-type guard parameterize case-lambda define-app
      else import library export fluid-let delay define-values with-syntax))

  (define (transcript-draw-style-color style)
    (case style
      [(input) 'text]
      [(output) 'text-dim]
      [(result) 'teal]
      [(error) 'red]
      [(banner) 'accent]
      [(info) 'text-faint]
      [else 'text]))

  ;; Returns a vector of a color key per character, for the Scheme text in s
  ;; from index `from` on.
  (define (transcript-draw-scheme s from)
    (let* ([n (string-length s)] [v (make-vector n 'text)])
      (define (fill! a b color)
        (do ([i a (+ i 1)]) ((>= i (min b n))) (vector-set! v i color)))
      (define (delimiter? c)
        (or (char-whitespace? c) (memv c '(#\( #\) #\[ #\] #\" #\;))))
      (let loop ([i from] [after-open? #f])
        (when (< i n)
          (let ([c (string-ref s i)])
            (cond
              [(char=? c #\;) (fill! i n 'text-faint)]
              [(char=? c #\")
               (let str ([j (+ i 1)])
                 (cond
                   [(>= j n) (fill! i n 'green) (loop n #f)]
                   [(char=? (string-ref s j) #\\) (str (+ j 2))]
                   [(char=? (string-ref s j) #\")
                    (fill! i (+ j 1) 'green)
                    (loop (+ j 1) #f)]
                   [else (str (+ j 1))]))]
              [(memv c '(#\( #\[ #\) #\]))
               (fill! i (+ i 1) 'repl-paren)
               (loop (+ i 1) (memv c '(#\( #\[)))]
              [(memv c '(#\' #\` #\,)) (fill! i (+ i 1) 'cyan)
                                       (loop (+ i 1) #f)]
              [(char-whitespace? c) (loop (+ i 1) after-open?)]
              [(and (char=? c #\#) (< (+ i 1) n)
                    (char=? (string-ref s (+ i 1)) #\\))
               (let tok ([j (+ i 3)])
                 (if (and (< j n) (not (delimiter? (string-ref s j))))
                     (tok (+ j 1))
                     (begin (fill! i j 'green) (loop j #f))))]
              [else
               (let tok ([j i])
                 (if (and (< j n) (not (delimiter? (string-ref s j))))
                     (tok (+ j 1))
                     (let ([t (substring s i j)])
                       (fill! i j
                              (cond
                                [(string->number t) 'orange]
                                [(member t
                                         '("#t" "#f" "#true" "#false")) 'orange]
                                [(memq (string->symbol t) transcript-keywords)
                                 'accent-2]
                                [after-open? 'accent]
                                [else 'text]))
                       (loop j #f))))]))))
      v))

  ;; Parentheses have a color of their own, repl-paren: as quiet as faint
  ;; text, but a color of code rather than of a hint, so that a style's
  ;; font for faint text (Genera's italic) leaves them looking like the
  ;; rest of the code.
  (at-load
   (color-default! 'repl-paren (theme-rule (theme 'text-faint))))

  ;; The mark under the parenthesis that matches the one at a REPL's
  ;; cursor, and under that one too.
  (at-load
   (color-default! 'repl-paren-mark (theme-rule (alpha 'yellow 0.25))))

  ;; Draws the visual rows [row0, row1) of one wrapped logical line.
  (define (transcript-draw-line x y text colors cols row0 row1 cw lh)
    (let ([n (string-length text)])
      (do ([row row0 (+ row 1)] [yy y (+ yy lh)]) ((>= row row1))
        (let ([a (* row cols)] [b (min n (* (+ row 1) cols))])
          (if (symbol? colors)
              (when (< a b) (draw-text x yy (substring text a b) colors 'mono))
              (let run ([i a])
                (when (< i b)
                  (let ([c (vector-ref colors i)])
                    (let end ([j (+ i 1)])
                      (if (and (< j b) (eq? (vector-ref colors j) c))
                          (end (+ j 1))
                          (begin
                            (draw-text (+ x (* cw (- i a))) yy
                                       (substring text i j) c 'mono)
                            (run j))))))))))))

  ;; Returns a line's colors as transcript-draw-line takes them: one color
  ;; key, or a vector of one per character.
  (define (transcript-draw-entry-colors e)
    (case (car e)
      [(input request)
       (let ([colors (transcript-draw-scheme (cdr e) 3)])
         (transcript-fill-colors! colors 0 3
                                  (if (eq? (car e) 'request)
                                      'accent
                                      'text-faint))
         colors)]
      [else (transcript-draw-style-color (car e))]))

  ;; Draws the kit's scroll bar on the style's side, no wider than the
  ;; lines' inset there (Interlisp's bars are 24), showing rows of total:
  ;; while t is scrolled back, or always, where the style's bars are there
  ;; whether they are needed or not.
  (define (transcript-draw-scrollbar t w h rows total)
    (let* ([ui (transcript-ui t)] [lh (transcript-line-height)]
           [full? (theme 'scrollbar-full)]
           [side (if (eq? (theme 'scrollbar-side) 'left) 'left 'right)]
           [bw (min (ui-scrollbar-width) (transcript-inset side))]
           [y (if full? 0 4)]
           [most (max 0 (- total rows))])
      (ui-begin! ui)
      (when (or full? (> (transcript-scroll t) 0) (ui-active? ui 'bar))
        (ui-scrollbar ui 'bar (if (eq? side 'left) 0 (- w bw)) y bw (- h y y)
                      (* lh (- most (transcript-scroll t))) (* lh total)
                      (* lh rows)
                      (lambda (off)
                        (transcript-scroll-set!
                         t (clamp (- most (exact (round (/ off lh))))
                                  0 most)))
                      'line lh 'noun "history"))
      (ui-end! ui w h)))

  ;;; ------------------------------------------------------------ selection

  ;; Begins a draw's placing of lines, on a grid of cols characters cw wide
  ;; from x, and rows lh high. more: the texts of the lines that the draw
  ;; shows after t's, in order (a REPL's input), numbered on from
  ;; (transcript-end t).
  (define (transcript-placing! t x cw lh cols . more)
    (transcript-placed-set! t '())
    (transcript-grid-set! t (vector x cw lh cols))
    (transcript-more-set! t (if (pair? more) (car more) '())))

  ;; Records that line n, of len characters, shows its first rows rows from
  ;; top, and draws what of it is selected; called before its text is drawn.
  (define (transcript-place! t n top rows len)
    (transcript-placed-set! t (cons (list n top rows len)
                                    (transcript-placed t)))
    (transcript-draw-selection t n top rows len))

  (define (transcript-before? a b)
    (or (< (car a) (car b)) (and (= (car a) (car b)) (< (cdr a) (cdr b)))))

  ;; Returns what is selected as (start . end), in order, or #f for nothing.
  (define (transcript-range t)
    (let ([s (transcript-sel t)])
      (and s (not (equal? (car s) (cdr s)))
           (if (transcript-before? (cdr s) (car s)) (cons (cdr s) (car s)) s))))

  ;; Fills what of line n is selected, of its first rows rows from top, as a
  ;; text box shows its selection (text-selection: a fill, or an
  ;; underline). A selection that goes on past the line's end takes a cell
  ;; more, the line's break.
  (define (transcript-draw-selection t n top rows len)
    (let ([r (transcript-range t)] [g (transcript-grid t)])
      (when (and r g (<= (caar r) n (cadr r)))
        (let ([x0 (vector-ref g 0)] [cw (vector-ref g 1)] [lh (vector-ref g 2)]
              [cols (vector-ref g 3)]
              [a (if (= n (caar r)) (cdar r) 0)]
              [b (if (= n (cadr r)) (cddr r) (+ len 1))])
          (do ([row 0 (+ row 1)]) ((= row rows))
            (let ([lo (max a (* row cols))] [hi (min b (* (+ row 1) cols))])
              (when (< lo hi)
                (let ([x (+ x0 (* cw (- lo (* row cols))))]
                      [y (+ top (* row lh))] [w (* cw (- hi lo))])
                  (if (eq? (theme 'text-selection) 'underline)
                      (fill-box x (+ y lh -1) w 1 'text)
                      (fill-box x y w lh 'selection))))))))))

  ;; Returns the position at (x, y) among the lines last drawn: before the
  ;; character there, or after it in its right half; above them all, the
  ;; topmost's start, and below, the lowest's end. #f with none drawn.
  (define (transcript-point t x y)
    (let ([g (transcript-grid t)] [placed (transcript-placed t)])
      (and g (pair? placed)
           (let* ([x0 (vector-ref g 0)] [cw (vector-ref g 1)]
                  [lh (vector-ref g 2)] [cols (vector-ref g 3)]
                  [hit (find (lambda (p)
                               (and (<= (cadr p) y)
                                    (< y (+ (cadr p) (* (caddr p) lh)))))
                             placed)])
             (if hit
                 (let ([row (exact (floor (/ (- y (cadr hit)) lh)))]
                       [col (clamp (exact (round (/ (- x x0) cw))) 0 cols)])
                   (cons (car hit) (min (cadddr hit) (+ (* row cols) col))))
                 (let ([top (fold-left (lambda (a p)
                                         (if (< (cadr p) (cadr a)) p a))
                                       (car placed) placed)]
                       [low (fold-left (lambda (a p)
                                         (if (> (cadr p) (cadr a)) p a))
                                       (car placed) placed)])
                   (if (< y (cadr top))
                       (cons (car top) 0)
                       (cons (car low) (cadddr low)))))))))

  ;; Returns the text of line n: one of t's, else one of the lines drawn
  ;; after them; #f for none.
  (define (transcript-line-text t n)
    (let ([i (- (transcript-end t) 1 n)] [more (transcript-more t)])
      (cond [(and (>= i 0) (< i (transcript-count t)))
             (cdr (list-ref (transcript-lines t) i))]
            [(< i 0) (let ([k (- -1 i)])
                       (and (< k (length more)) (list-ref more k)))]
            [else #f])))

  ;; Returns the text selected, its lines joined by line breaks, or "".
  (define (transcript-selection t)
    (let ([r (transcript-range t)])
      (if r
          (let loop ([n (caar r)] [acc '()])
            (if (> n (cadr r))
                (apply string-append (reverse acc))
                (let* ([text (or (transcript-line-text t n) "")]
                       [len (string-length text)]
                       [a (min len (if (= n (caar r)) (cdar r) 0))]
                       [b (min len (if (= n (cadr r)) (cddr r) len))])
                  (loop (+ n 1)
                        (cons (string-append (if (= n (caar r)) "" "\n")
                                             (substring text a (max a b)))
                              acc)))))
          "")))

  ;; Returns the bounds of the word, or else of the run of other characters,
  ;; at position p of text: a word is what lies between spaces and Scheme's
  ;; delimiters.
  (define (transcript-word text p)
    (let* ([n (string-length text)] [i (min (cdr p) (max 0 (- n 1)))]
           [word? (lambda (c) (not (or (char-whitespace? c)
                                       (memv c '(#\( #\) #\[ #\] #\" #\;
                                                 #\' #\` #\,)))))]
           [kind (and (< i n) (word? (string-ref text i)))])
      (let ([lo (let back ([j i])
                  (if (and (> j 0) (< j n)
                           (eq? (word? (string-ref text (- j 1))) kind))
                      (back (- j 1))
                      j))]
            [hi (let on ([j i])
                  (if (and (< j n) (eq? (word? (string-ref text j)) kind))
                      (on (+ j 1))
                      j))])
        (cons (cons (car p) lo) (cons (car p) (max hi (min n (+ lo 1))))))))

  ;; A press at (x, y) of the lines last drawn. The left button's one click
  ;; begins a selection, which follows the pointer till the release
  ;; (transcript-drag!, transcript-release!), two clicks select a word and
  ;; three the line; the right one opens the text menu: Copy, and Paste
  ;; where paste is given (a procedure that takes the clipboard's text).
  ;; opts: ui-open-text-menu!'s. A press on the scroll bar is the bar's.
  ;; Returns whether it took the press: bar, where the bar did.
  (define (transcript-press! t x y button clicks paste . opts)
    (let ([p (transcript-point t x y)])
      (cond
        [(transcript-bar-pointer t x y)
         (ui-mouse-down (transcript-ui t) x y button clicks)
         'bar]
        [(not p) #f]
        [else
         (case button
           [(left)
            (transcript-held?-set! t (= clicks 1))
            (transcript-sel-set!
             t
             (case clicks
               [(1) (cons p p)]
               [(2) (transcript-word (or (transcript-line-text t (car p)) "")
                                     p)]
               [else (let ([text (or (transcript-line-text t (car p)) "")])
                       (cons (cons (car p) 0)
                             (cons (car p) (string-length text))))]))
            #t]
           [(right)
            (apply ui-open-text-menu! #f x y (transcript-selection t) paste
                   opts)
            #t]
           [else #f])])))

  ;; Moves the selection's end to (x, y) while a left press holds it, or
  ;; the scroll bar's thumb while one holds that. Returns whether the
  ;; selection moved.
  (define (transcript-drag! t x y)
    (ui-mouse-move (transcript-ui t) x y)
    (let ([s (transcript-sel t)] [p (transcript-point t x y)])
      (and (transcript-held? t) s p (not (equal? p (cdr s)))
           (begin (transcript-sel-set! t (cons (car s) p)) #t))))

  ;; The button that pressed at (x, y) was released.
  (define (transcript-release! t x y button)
    (ui-mouse-up (transcript-ui t) x y button)
    (transcript-held?-set! t #f))

  ;; Returns the pointer's shape at (x, y) and what the mouse buttons do
  ;; there, as (cursor . doc), where that is over the scroll bar, else #f.
  (define (transcript-bar-pointer t x y) (ui-pointer (transcript-ui t) x y))

  ;; Draws all of t in the box w × h, laid out from the bottom up, but hung
  ;; from the top while everything fits.
  (define (transcript-draw-view t w h)
    (let* ([cw (font-char-width 'mono)]
           [lh (transcript-line-height)]
           [pad transcript-pad] [left (transcript-inset 'left)]
           [cols (max 8 (exact (floor (/ (- w left (transcript-inset 'right))
                                         cw))))]
           [rows (max 1 (exact (floor (/ (- h pad pad) lh))))]
           [total (fold-left (lambda (acc l)
                               (+ acc (transcript-rows (string-length (cdr l))
                                                       cols)))
                             0 (transcript-lines t))])
      (transcript-scroll-set! t (clamp (transcript-scroll t) 0
                                       (max 0 (- total rows))))
      (transcript-placing! t left cw lh cols)
      (let loop ([entries (transcript-lines t)]
                 [n (- (transcript-end t) 1)]
                 [bottom (if (< total rows) (+ pad (* total lh)) (- h pad))]
                 [skip (transcript-scroll t)])
        (when (and (pair? entries) (> bottom 0))
          (let* ([e (car entries)]
                 [k (transcript-rows (string-length (cdr e)) cols)]
                 [shown (- k (min skip k))])
            (if (= shown 0)
                (loop (cdr entries) (- n 1) bottom (- skip k))
                (let ([top (- bottom (* shown lh))])
                  (transcript-place! t n top shown (string-length (cdr e)))
                  (transcript-draw-line left top (cdr e)
                                        (transcript-draw-entry-colors e)
                                        cols 0 shown cw lh)
                  (loop (cdr entries) (- n 1) top 0))))))
      (transcript-draw-scrollbar t w h rows total))))
