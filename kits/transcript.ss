;;; kits/transcript.ss — lines of text that only grow, as a REPL shows them:
;;; wrapped to the width, the newest at the bottom, each in a style, Scheme in
;;; its colors. What's derived from it holds one (per window) and adds to it:
;;; the REPL, with an input under it; the Debug REPL, with none.
;;;
;;;   (define t (transcript-new))
;;;   (transcript-add! t 'result "42")        complete lines, on a fresh line
;;;   (transcript-append! t 'output "so f")   text in pieces, on the open line
;;;   (transcript-draw-view t w h)            all of it, in a draw handler
;;;
;;; A line's style says how it's drawn: input and request are Scheme after a
;;; prompt of three characters, in plain or in accent; the others a color each
;;; (transcript-draw-style-color).

(define-record-type transcript
  (nongenerative schevana-transcript)
  (fields (mutable lines)    ; newest first: ((style . text) ...)
          (mutable count)
          (mutable open?)    ; is the newest line unterminated output?
          (mutable scroll))) ; visual rows scrolled back from the bottom

(define (transcript-new) (make-transcript '() 0 #f 0))

(define transcript-max-lines 4000)
(define transcript-pad 10)
(define (transcript-line-height) (+ 3 (font-line-height 'mono)))

(define (transcript-clear! t)
  (transcript-lines-set! t '())
  (transcript-count-set! t 0)
  (transcript-open?-set! t #f))

(define (transcript-push! t style text)
  (transcript-lines-set! t (cons (cons style text) (transcript-lines t)))
  (transcript-count-set! t (+ 1 (transcript-count t)))
  (when (> (transcript-count t) (+ transcript-max-lines 500))
    (transcript-lines-set! t (list-head (transcript-lines t)
                                        transcript-max-lines))
    (transcript-count-set! t transcript-max-lines)))

;; Append text that may contain newlines; output can arrive in pieces.
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

;; Add complete lines, starting on a fresh line, and show them.
(define (transcript-add! t style str)
  (transcript-open?-set! t #f)
  (transcript-append! t style (string-append str "\n"))
  (transcript-scroll-set! t 0))

;; How many visual rows a logical line of len characters takes.
(define (transcript-rows len cols)
  (max 1 (quotient (+ len cols -1) cols)))

(define (transcript-fill-colors! v a b x)
  (do ([i a (+ i 1)]) ((>= i (min b (vector-length v)))) (vector-set! v i x)))

(define transcript-keywords
  '(define lambda let let* letrec letrec* if cond case when unless begin set! do
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

;; A color key per character, for the Scheme text in s (from index `from`).
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
            [(memv c '(#\' #\` #\,)) (fill! i (+ i 1) 'cyan) (loop (+ i 1) #f)]
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
                              [(member t '("#t" "#f" "#true" "#false")) 'orange]
                              [(memq (string->symbol t) transcript-keywords)
                               'accent-2]
                              [after-open? 'accent]
                              [else 'text]))
                     (loop j #f))))]))))
    v))

(color-default! 'repl-paren (theme-rule (theme 'text-faint)))

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

;; A line's colors, as a draw of it takes them.
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

;; The kit's scroll bar when scrolled back, on the style's side, no wider than
;; the text's inset (Interlisp's bars are 24): rows of total shown.
(define (transcript-draw-scrollbar t w h rows total)
  (when (> (transcript-scroll t) 0)
    (let ([size (/ rows (max rows total))]
          [bw (min (ui-scrollbar-width) transcript-pad)])
      (ui-draw-scrollbar (if (eq? (theme 'scrollbar-side) 'left) 0 (- w bw))
                         4 bw (- h 8) '()
                         (* (- 1 size)
                            (- 1 (/ (transcript-scroll t)
                                    (max 1 (- total rows)))))
                         size))))

;; All of it in the box w × h: laid out bottom-up, but hung from the top while
;; everything fits.
(define (transcript-draw-view t w h)
  (let* ([cw (font-char-width 'mono)]
         [lh (transcript-line-height)]
         [pad transcript-pad]
         [cols (max 8 (exact (floor (/ (- w pad pad) cw))))]
         [rows (max 1 (exact (floor (/ (- h pad pad) lh))))]
         [total (fold-left (lambda (acc l)
                             (+ acc (transcript-rows (string-length (cdr l))
                                                     cols)))
                           0 (transcript-lines t))])
    (transcript-scroll-set! t (clamp (transcript-scroll t) 0
                                     (max 0 (- total rows))))
    (let loop ([entries (transcript-lines t)]
               [bottom (if (< total rows) (+ pad (* total lh)) (- h pad))]
               [skip (transcript-scroll t)])
      (when (and (pair? entries) (> bottom 0))
        (let* ([e (car entries)]
               [k (transcript-rows (string-length (cdr e)) cols)]
               [shown (- k (min skip k))])
          (if (= shown 0)
              (loop (cdr entries) bottom (- skip k))
              (let ([top (- bottom (* shown lh))])
                (transcript-draw-line pad top (cdr e)
                                      (transcript-draw-entry-colors e)
                                      cols 0 shown cw lh)
                (loop (cdr entries) top 0))))))
    (transcript-draw-scrollbar t w h rows total)))
