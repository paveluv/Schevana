;;; apps/repl.ss — a Scheme REPL living inside the world it can change.
;;;
;;; Each evaluation runs as a process (see proc.ss), so long computations
;;; keep the desktop alive and Ctrl+C interrupts them.
;;;
;;; A REPL window evaluates in one environment (services/env.ss), which its
;;; title names, and its title icon's kind ('title-icon: the style shows
;;; it as it will):
;;;   (repl)            the world itself, the shared environment the whole
;;;                     system lives in, so a define here changes the world
;;;   (repl 'private)   a new child of the world's of that kind, the
;;;                     window's own, dropped as it closes: private (what
;;;                     reads the world, live; set! of it refused), world
;;;                     (every name of the world's, those it gains later
;;;                     too), pure (plain Chez Scheme), sandbox, thread
;;;   (repl "/sandbox") an environment that is there (the Environments
;;;                     app opens these); not /worklets, where the pool's
;;;                     threads run
;;; In a thread's environment, a sandbox in a vat of its own, the forms go
;;; to the vat: its thread runs them and prints what they return, and
;;; Ctrl+C stops them there. Once its environment is dropped, a REPL
;;; evaluates nowhere. An evaluation that takes a while makes the window
;;; busy ('busy), which its style shows: by default a busy mark in place of
;;; the running input's prompt, which says, under the pointer, that Ctrl+C
;;; stops it. Inputs entered meanwhile wait under it, and run in turn.

(define-record-type repl
  (nongenerative schevana-repl-5)
  (fields transcript           ; what it has said (kits/transcript.ss)
          (mutable input)      ; the text being edited
          (mutable point)      ; cursor index into input
          (mutable history)    ; previous inputs, newest first
          (mutable hist-pos)   ; -1 while editing fresh input
          (mutable saved)      ; fresh input stashed while browsing history
          (mutable proc)       ; the running evaluation (a process, or a
                               ; vat's job), or #f
          (mutable pending)    ; output from the process, newest first
          (mutable port)
          (mutable blink)      ; cursor visible?
          (mutable blink-at)
          (mutable cols)       ; layout from the last draw
          (mutable rows)
          (mutable queue)      ; inputs entered while a form ran, to run
                               ; in turn, the oldest first
          env                  ; its environment
          own?                 ; made for it, so dropped as it closes
          (mutable started)    ; when the evaluation running began, or #f
          (mutable pointer)    ; where the pointer last moved, (x y ms)
          (mutable busy)       ; the busy mark as drawn, (x y w h ms), or #f
          (mutable running)))  ; the running input's first line in the
                               ; transcript, or #f

;; A REPL's look by its environment's kind: (kind prompt-color background),
;; a bare child's by its base.
(define repl-looks
  '((root accent bg-0)
    (private accent-2 repl-bg-private)
    (world accent repl-bg-world)
    (pure green repl-bg-pure)
    (sandbox teal repl-bg-sandbox)
    (thread orange repl-bg-thread)
    (host red repl-bg-host)       ; core0's: the screen's own code
    (recorder red repl-bg-host)))   ; the bytes of frames, sealed

;; The backgrounds, tinted by the prompt's color: rules, so that they
;; follow the style and palette as they change, as an open REPL must.
(for-each (lambda (key tint)
            (color-default! key (theme-rule (mix 'bg-0 tint 0.06))))
          '(repl-bg-private repl-bg-world repl-bg-pure repl-bg-sandbox
            repl-bg-thread repl-bg-host)
          '(accent-2 accent green teal orange red))

(define (repl-kind r) (vat-env-kind (repl-env r)))

(define (repl-look r)
  (cdr (or (assq (repl-kind r) repl-looks) (assq 'pure repl-looks))))

;; "REPL — /path".
(define (repl-title r)
  (let ([e (repl-env r)])
    (if (env-dropped? e)
        (format "REPL — ~a (dropped)" (env-path e))
        (format "REPL — ~a" (env-path e)))))

;; An evaluation shows as busy once it has run this long: one that ends
;; sooner shows nothing.
(define repl-busy-ms 300)

(define (repl-busy? r)
  (let ([t (repl-started r)])
    (and t (repl-proc r) (>= (- (now-ms) t) repl-busy-ms))))

;; What the busy mark says, and the window's 'busy.
(define (repl-busy-words r)
  (if (vat-of (repl-env r))
      "Running on its thread: Ctrl+C stops it"
      "Running: Ctrl+C stops it"))

;; A theme color, never one worked out once: a REPL opened in one style
;; and shown in another has the other's.
(define (repl-background r) (cadr (repl-look r)))

;; The environment a REPL opens in, and whether it is its own: what is
;; the world (root), a kind (a new child of the world's, the REPL's own),
;; an environment or its path. => (values env own?)
(define (repl-environment-of what)
  (let ([e (cond [(eq? what 'root) (env-root)]
                 [(symbol? what) (env-fork (env-root) what)]
                 [(string? what)
                  (or (env-find what) (errorf 'repl "no environment ~a" what))]
                 [(env? what) what]
                 [else (errorf 'repl "a REPL opens in a kind, an environment \
                                      or its path, not ~s" what)])])
    (cond [(env-dropped? e) (errorf 'repl "~a was dropped" (env-path e))]
          [(eq? (env-kind e) 'worklets)
           (errorf 'repl "no REPL in /worklets: the pool's threads run \
                          there, worklets only")])
    (values e (and (symbol? what) (not (eq? what 'root))))))

(define (repl-environment r) (env-environment (repl-env r)))

(define repl-prompt "λ> ")
(define repl-waiting "↳  ")   ; before an input that waits its turn
(define repl-cont   "   ")

;;; ------------------------------------------------------------------
;;; transcript

;; Its transcript's, as the rest of this file reads them.
(define (repl-lines r) (transcript-lines (repl-transcript r)))
(define (repl-scroll r) (transcript-scroll (repl-transcript r)))
(define (repl-scroll-set! r n) (transcript-scroll-set! (repl-transcript r) n))

;; Output arrives in pieces: text that may hold newlines, on the line it left
;; open.
(define (repl-append! r style str)
  (transcript-append! (repl-transcript r) style str))

;; Add complete lines, starting on a fresh line.
(define (repl-add! r style str)
  (transcript-add! (repl-transcript r) style str)
  (repl-invalidate! r))

;; The window showing r, or #f (before it opens).
(define (repl-window r)
  (find (lambda (w) (eq? (window-ref w 'state) r)) *windows*))

(define (repl-invalidate! r)
  (let ([w (repl-window r)]) (if w (invalidate! w) (request-frame!))))

;; Called from inside the evaluation process: queue, don't touch the
;; transcript, and ask for the frame that drains it.
(define (repl-emit! r style str)
  (with-interrupts-disabled
   (repl-pending-set! r (cons (cons style str) (repl-pending r)))
   (let ([w (repl-window r)]) (when w (window-frame-soon! w)))))

(define (repl-drain! r)
  (let ([chunks (with-interrupts-disabled
                 (let ([c (repl-pending r)]) (repl-pending-set! r '()) c))])
    (unless (null? chunks)
      (for-each (lambda (c)
                  (if (eq? (car c) 'output)
                      (repl-append! r 'output (cdr c))
                      (repl-add! r (car c) (cdr c))))
                (reverse chunks))
      (repl-scroll-set! r 0)
      (repl-invalidate! r))))

(define (make-repl-port r)
  (let ([p (make-custom-textual-output-port "repl"
             (lambda (s start n)
               (let ([out (substring s start (+ start n))])
                 (when (memv #\alarm (string->list out)) (bell))
                 (repl-emit! r 'output out))
               n)
             #f #f #f)])
    (set-textual-port-output-size! p 0)
    p))

;;; ------------------------------------------------------------------
;;; evaluation

;; The forms of src, one more REPL input: read with their places in it, so
;; that what they define tells where it came from (its description, an
;; error's place), and kept as the core keeps a loaded file's text.
(defvar *repl-inputs* 0)

(define (read-input! src)
  (set! *repl-inputs* (+ *repl-inputs* 1))
  (let* ([name (format "REPL input ~a" *repl-inputs*)]
         [sfd (make-source-file-descriptor
               name (open-bytevector-input-port (string->utf8 src)))]
         [p (open-string-input-port src)])
    (let loop ([pos 0] [acc '()])
      (let-values ([(x end) (get-datum/annotations p sfd pos)])
        (cond
          [(not (eof-object? x)) (loop end (cons x acc))]
          [(null? acc) '()]
          [else (keep-source-text! name src) (reverse acc)])))))

(define (value->string v)
  (let ([s (with-output-to-string (lambda () (pretty-print v)))])
    (if (and (> (string-length s) 0)
             (char=? #\newline (string-ref s (- (string-length s) 1))))
        (substring s 0 (- (string-length s) 1))
        s)))

;; src into the transcript after the prompt, its other lines under the
;; first. => its first line, as the transcript holds it
(define (repl-echo! r src)
  (let loop ([lines (string-split src #\newline)] [first #f])
    (if (null? lines)
        first
        (begin
          (repl-add! r 'input
                     (string-append (if first repl-cont repl-prompt)
                                    (car lines)))
          (loop (cdr lines) (or first (car (repl-lines r))))))))

;; Enter on a complete input: it runs, or, while a form runs, waits after
;; those waiting already, the input line free for the next. Either way it
;; is history.
(define (repl-submit! r win)
  (let ([src (repl-input r)])
    (unless (string=? "" (string-trim src))
      (repl-history-set! r (cons src (remove src (repl-history r)))))
    (repl-input-set! r "")
    (repl-point-set! r 0)
    (repl-hist-pos-set! r -1)
    (if (repl-proc r)
        (repl-queue-set! r (append (repl-queue r) (list src)))
        (repl-run! r win src))))

;; src echoed and evaluated, its forms read with their places. One that
;; does not read, or holds nothing to run, lets the next waiting one go.
(define (repl-run! r win src)
  (repl-running-set! r (repl-echo! r src))
  (let ([forms (guard (c [#t (repl-add! r 'error (condition->string c)) #f])
                 (read-input! src))])
    (when (and forms (pair? forms)) (repl-eval! r win forms))
    (unless (repl-proc r) (repl-next! r win))))

;; The running input is done: the next waiting one runs, if one waits.
(define (repl-next! r win)
  (repl-running-set! r #f)
  (let ([q (repl-queue r)])
    (when (pair? q)
      (repl-queue-set! r (cdr q))
      (repl-run! r win (car q)))))

;; forms evaluated where the REPL is: in a process here, or, in a vat's
;; sandbox, sent to the vat (root never evaluates there itself). Nowhere
;; once the environment is dropped.
(define (repl-eval! r win forms)
  (let ([width (max 20 (- (repl-cols r) 1))] [e (repl-env r)])
    (if (env-dropped? e)
        (repl-add! r 'error (format "; ~a was dropped: this REPL evaluates \
                                     nowhere now" (env-path e)))
        (let ([v (vat-of e)])
          (repl-started-set! r (now-ms))
          (repl-proc-set! r (cond
                              [v (repl-send! r win v forms width)]
                              [(eq? (env-kind e) 'host)
                               (repl-host-send! r win forms width)]
                              [else (repl-spawn! r win forms width)]))
          ;; its frames while it runs: what it prints, the busy mark
          (window-frame-soon! win)))))

(define (repl-spawn! r win forms width)
  (let ([port (repl-port r)])
    (spawn "repl"
           (lambda ()
             (parameterize ([current-output-port port]
                            [current-error-port port]
                            [current-input-port (open-input-string "")]
                            [pretty-line-length width])
               (for-each
                (lambda (form)
                  (call-with-values
                    (lambda () (env-eval (repl-env r) form))
                    (lambda vals
                      (for-each (lambda (v)
                                  (unless (eq? v (void))
                                    (repl-emit! r 'result (value->string v))))
                                vals))))
                forms)))
           (lambda (status value)
             (repl-drain! r)
             (case status
               [(error) (repl-add! r 'error (condition->string value))]
               [(killed) (repl-add! r 'info "; interrupted")])
             (repl-done! r win)))))

;; The vat's thread runs the forms and prints what they return there,
;; where the values live; the texts come back. => the job.
(define (repl-send! r win v forms width)
  (vat-repl! v forms width
             (lambda (texts)
               (for-each (lambda (t) (repl-add! r 'result t)) texts)
               (repl-done! r win))
             (lambda (text)
               (repl-add! r 'error text)
               (repl-done! r win))))

;; "/host": core0 runs the forms between frames, in its own environment, and
;; the texts come back. => what Ctrl+C finds: core0 is never interrupted.
(define (repl-host-send! r win forms width)
  (host-eval! forms width
              (lambda (answer)
                (if (eq? (car answer) 'ok)
                    (for-each (lambda (t) (repl-add! r 'result t))
                              (cdr answer))
                    (repl-add! r 'error (cadr answer)))
                (repl-done! r win)))
  'host)

;; The evaluation is over: the window is no longer busy, and the next
;; waiting input runs.
(define (repl-done! r win)
  (repl-proc-set! r #f)
  (repl-started-set! r #f)
  (when (window-ref win 'busy)
    (window-set! win 'busy #f)
    (invalidate!))   ; a style may show it in its bars
  (repl-next! r win)
  (invalidate!))

;; Ctrl+C: the evaluation stops; a vat's job escapes on the vat's thread,
;; and its then never comes.
(define (repl-stop! r win)
  (let ([p (repl-proc r)])
    (if (vat-job? p)
        (begin (vat-job-kill! p)
               (repl-add! r 'info "; interrupted")
               (repl-done! r win))
        (if (eq? p 'host)
            (repl-add! r 'info "; core0 runs it between frames, and isn't \
                                interrupted")
            (kill! p)))))

;;; ------------------------------------------------------------------ editing

(define (string-trim s)
  (let* ([n (string-length s)]
         [a (let loop ([i 0])
              (if (and (< i n) (char-whitespace? (string-ref s i)))
                  (loop (+ i 1))
                  i))]
         [b (let loop ([i n])
              (if (and (> i a) (char-whitespace? (string-ref s (- i 1))))
                  (loop (- i 1))
                  i))])
    (substring s a b)))

(define (line-start s i)
  (let loop ([i i])
    (if (and (> i 0) (not (char=? (string-ref s (- i 1)) #\newline)))
        (loop (- i 1))
        i)))

(define (line-end s i)
  (let ([n (string-length s)])
    (let loop ([i i])
      (if (and (< i n) (not (char=? (string-ref s i) #\newline)))
          (loop (+ i 1))
          i))))

;; Scan s[0, end) and return (values unclosed-opener-indices in-string?),
;; innermost opener first.
(define (scan-parens s end)
  (let loop ([i 0] [stack '()] [str? #f])
    (if (>= i end)
        (values stack str?)
        (let ([c (string-ref s i)])
          (cond
            [str? (cond [(char=? c #\\) (loop (+ i 2) stack #t)]
                        [(char=? c #\") (loop (+ i 1) stack #f)]
                        [else (loop (+ i 1) stack #t)])]
            [(char=? c #\") (loop (+ i 1) stack #t)]
            [(char=? c #\;) (loop (line-end s i) stack #f)]
            [(and (char=? c #\#) (< (+ i 1) end)
                  (char=? (string-ref s (+ i 1)) #\\))
             (loop (+ i 3) stack #f)]
            [(memv c '(#\( #\[)) (loop (+ i 1) (cons i stack) #f)]
            [(memv c '(#\) #\]))
             (loop (+ i 1) (if (pair? stack) (cdr stack) stack) #f)]
            [else (loop (+ i 1) stack #f)])))))

(define (input-complete? s)
  (let-values ([(stack str?) (scan-parens s (string-length s))])
    (and (null? stack) (not str?))))

;; Index of the paren matching the one at i, or #f.
(define (matching-paren s i)
  (and (>= i 0) (< i (string-length s))
       (let ([c (string-ref s i)])
         (cond
           [(memv c '(#\) #\]))
            (let-values ([(stack str?) (scan-parens s i)])
              (and (not str?) (pair? stack) (car stack)))]
           [(memv c '(#\( #\[))
            (let ([n (string-length s)])
              (let loop ([j (+ i 1)] [depth 0] [str? #f])
                (and (< j n)
                     (let ([c (string-ref s j)])
                       (cond
                         [str? (cond [(char=? c #\\) (loop (+ j 2) depth #t)]
                                     [(char=? c #\") (loop (+ j 1) depth #f)]
                                     [else (loop (+ j 1) depth #t)])]
                         [(char=? c #\") (loop (+ j 1) depth #t)]
                         [(char=? c #\;) (loop (line-end s j) depth #f)]
                         [(and (char=? c #\#) (< (+ j 1) n)
                               (char=? (string-ref s (+ j 1)) #\\))
                          (loop (+ j 3) depth #f)]
                         [(memv c '(#\( #\[)) (loop (+ j 1) (+ depth 1) #f)]
                         [(memv c '(#\) #\]))
                          (if (= depth 0) j (loop (+ j 1) (- depth 1) #f))]
                         [else (loop (+ j 1) depth #f)])))))]
           [else #f]))))

(define (repl-insert! r str)
  (let ([s (repl-input r)] [p (repl-point r)])
    (repl-input-set! r (string-append (substring s 0 p) str
                                      (substring s p (string-length s))))
    (repl-point-set! r (+ p (string-length str)))))

(define (repl-delete! r from to)
  (let ([s (repl-input r)])
    (when (< from to)
      (repl-input-set! r (string-append (substring s 0 from)
                                        (substring s to (string-length s))))
      (repl-point-set! r from))))

;; Newline plus Lisp-style indentation: two past the innermost open paren.
(define (repl-newline! r)
  (let-values ([(stack str?) (scan-parens (repl-input r) (repl-point r))])
    (let ([indent (if (pair? stack)
                      (let ([open (car stack)])
                        (+ 2 (- open (line-start (repl-input r) open))))
                      0)])
      (repl-insert! r (string-append "\n" (make-string indent #\space))))))

(define (repl-history-move! r dir)
  (let* ([h (repl-history r)] [pos (+ (repl-hist-pos r) dir)])
    (when (and (>= pos -1) (< pos (length h)))
      (when (= (repl-hist-pos r) -1) (repl-saved-set! r (repl-input r)))
      (repl-hist-pos-set! r pos)
      (repl-input-set! r (if (= pos -1)
                             (or (repl-saved r) "")
                             (list-ref h pos)))
      (repl-point-set! r (string-length (repl-input r))))))

(define (repl-up! r)
  (let* ([s (repl-input r)] [p (repl-point r)] [ls (line-start s p)])
    (if (= ls 0)
        (repl-history-move! r 1)
        (let* ([col (- p ls)] [pls (line-start s (- ls 1))])
          (repl-point-set! r (+ pls (min col (- (- ls 1) pls))))))))

(define (repl-down! r)
  (let* ([s (repl-input r)] [p (repl-point r)] [le (line-end s p)])
    (if (= le (string-length s))
        (repl-history-move! r -1)
        (let* ([col (- p (line-start s p))] [nls (+ le 1)])
          (repl-point-set! r (+ nls (min col (- (line-end s nls) nls))))))))

(define (symbol-char? c)
  (not (or (char-whitespace? c)
           (memv c '(#\( #\) #\[ #\] #\" #\' #\` #\, #\;)))))

;;; ------------------------------------------------------------------
;;; completion
;;; Tab completes the name before the cursor through the completion kit
;;; (kits/complete.ss): it extends the name to what the matches starting
;;; with it share and lists the matches under the cursor, narrowing as you
;;; type: Up/Down choose, Tab and Shift+Tab page, Enter or a click
;;; accepts, Esc, a click elsewhere in it or the keyboard going elsewhere
;;; closes. With nothing to choose, a popup says so: the sole completion,
;;; with its description, or none. What it offers depends on where the
;;; cursor is: inside a string, file names; after a quote in (theme '…),
;;; (app-launch! '…) and the like, the theme keys, apps, palettes or styles
;;; that fit there; inside (import (…)), library names a part at a time;
;;; otherwise every name bound in this REPL's environment. Names match by
;;; the kit's segments ("dtc" puts text-draw-centered first), Schevana's
;;; own first among equals. The chosen name shows its argument list and
;;; the comment above its definition, read from the sources.

;;; Names, and what the sources say about them.

;; Each name's definitions in the texts the core keeps (*source-texts*):
;; name -> ((source serial signature doc) ...); and what each source
;; defined: source -> (serial name ...). A source whose text was kept
;; again is read again.
(defvar *repl-source-docs* (make-hashtable string-hash string=?))
(defvar *repl-source-names* (make-hashtable string-hash string=?))

;; The index, brought up to date with the kept texts.
(define (name-docs)
  (let-values ([(sources kept) (hashtable-entries *source-texts*)])
    (vector-for-each
     (lambda (source k)
       (let ([had (hashtable-ref *repl-source-names* source #f)])
         (unless (and had (= (car had) (car k)))
           (when had
             (for-each (lambda (name) (forget-doc! name source)) (cdr had)))
           (hashtable-set! *repl-source-names* source
                           (cons (car k) (index-text! source (car k)
                                                      (cdr k)))))))
     sources kept))
  *repl-source-docs*)

(define (forget-doc! name source)
  (let ([ds (remp (lambda (d) (string=? (car d) source))
                  (hashtable-ref *repl-source-docs* name '()))])
    (if (null? ds)
        (hashtable-delete! *repl-source-docs* name)
        (hashtable-set! *repl-source-docs* name ds))))

;; Indexes every top-level definition in text: its argument list and the
;; ;; comment lines right above it. => the names it defines.
(define (index-text! source serial text)
  (let ([n (string-length text)] [port (open-string-input-port text)]
        [names '()])
    (guard (c [#t (void)])   ; a text that does not read gives what it read
      (let loop ([prev 0])
        (let ([start (skip-blank-and-comments text prev)])
          (when (< start n)
            (set-port-position! port start)
            (let ([form (read port)])
              (unless (eof-object? form)
                (for-each
                 (lambda (d)   ; (name . signature)
                   (hashtable-update! *repl-source-docs* (car d)
                     (lambda (ds)
                       (cons (list source serial (cdr d)
                                   (comment-above text prev start))
                             ds))
                     '())
                   (set! names (cons (car d) names)))
                 (form-definitions form))
                (loop (port-position port))))))))
    names))

(define (skip-blank-and-comments text i)
  (let ([n (string-length text)])
    (let loop ([i i])
      (cond
        [(>= i n) n]
        [(char-whitespace? (string-ref text i)) (loop (+ i 1))]
        [(char=? (string-ref text i) #\;) (loop (line-end text i))]
        [else i]))))

;; The ;; lines (not ;;; headings) directly above position start.
(define (comment-above text from start)
  (let loop ([lines (reverse (string-split (substring text from start)
                                           #\newline))]
             [acc '()])
    (let ([l (and (pair? lines) (string-trim (car lines)))])
      (cond
        [(not l) (string-join acc " ")]
        [(and (string=? l "") (null? acc)) (loop (cdr lines) acc)]
        [(and (string-prefix? ";;" l) (not (string-prefix? ";;;" l)))
         (loop (cdr lines)
               (cons (string-trim (substring l 2 (string-length l))) acc))]
        [else (string-join acc " ")]))))

;; What a top-level form defines: ((name . signature) ...), names as
;; strings.
(define (form-definitions form)
  (define (def name signature) (list (cons (symbol->string name) signature)))
  (if (and (pair? form) (pair? (cdr form)))
      (let ([head (cadr form)])
        (case (car form)
          [(define defvar)
           (cond
             [(and (pair? head) (symbol? (car head)))
              (def (car head) (format "~s" head))]
             [(symbol? head)
              (let ([v (and (pair? (cddr form)) (caddr form))])
                (cond
                  [(and (pair? v) (eq? (car v) 'lambda) (pair? (cdr v)))
                   (def head (format "~s" (cons head (cadr v))))]
                  [(and (pair? v) (eq? (car v) 'case-lambda))
                   (def head (string-join
                              (map (lambda (clause)
                                     (format "~s" (cons head (car clause))))
                                   (cdr v))
                              "  "))]
                  [else (def head (symbol->string head))]))]
             [else '()])]
          [(define-app)
           (if (and (pair? head) (symbol? (car head)))
               (def (car head) (format "~s" head))
               '())]
          [(define-part)   ; the part, and its built-in body
           (if (and (pair? head) (symbol? (car head)))
               (let ([built-in (string->symbol (format "~a*" (car head)))])
                 (append (def (car head) (format "~s" head))
                         (def built-in
                              (format "~s" (cons built-in (cdr head))))))
               '())]
          [(define-syntax)
           (if (symbol? head) (def head (format "(~a …)" head)) '())]
          [else '()]))
      '()))

;; Where procedure p's code came from (a file's path, a REPL input), and
;; the name its code bears; #f for either it does not tell.
(define (code-source p)
  (guard (c [#t #f])
    (let ([so (((inspect/object p) 'code) 'source-object)])
      (and so (source-file-descriptor-path (source-object-sfd so))))))
(define (code-name p)
  (guard (c [#t #f]) (((inspect/object p) 'code) 'name)))

;; The definition that describes v, name's value now: for a procedure,
;; the one in the source its code came from; for code without a source
;; that bears the name (an app's launcher, made by define-app), the
;; newest; none when v came from elsewhere (redefined in another source,
;; set! to another procedure). A value of another kind: the newest.
(define (doc-for name v ds)
  (define (newest)
    (fold-left (lambda (best d) (if (and best (> (cadr best) (cadr d))) best d))
               #f ds))
  (if (procedure? v)
      (let ([source (code-source v)])
        (cond [source (find (lambda (d) (string=? (car d) source)) ds)]
              [(equal? (code-name v) name) (newest)]
              [else #f]))
      (newest)))

;; (values signature doc) for name in e: what the source of its value
;; says (a shared name's: of what it forwards to), else what the value
;; itself tells.
(define (name-description name e)
  (let-values ([(env sym) (env-binding e (string->symbol name))])
    (let* ([name (symbol->string sym)]
           [bound? (top-level-bound? sym env)]
           [v (and bound? (top-level-value sym env))]
           [d (doc-for name v (hashtable-ref (name-docs) name '()))])
      (cond
        [d (values (caddr d) (cadddr d))]
        [bound?
         (if (procedure? v)
             (values (format "(~a …)" name)
                     (arity-description (procedure-arity-mask v)))
             (values (string-append name " = "
                                    (text-shorten
                                     (parameterize ([print-length 6]
                                                    [print-level 3])
                                       (format "~s" v))
                                     70))
                     ""))]
        [(top-level-syntax? sym env) (values (format "(~a …)" name) "Syntax.")]
        [else (values name "")]))))

;; "Takes 2 arguments." from a procedure-arity-mask: bit n set when n
;; arguments are accepted, negative when any number from some n up is.
(define (arity-description mask)
  (define (args n) (if (= n 1) "1 argument" (format "~a arguments" n)))
  (if (< mask 0)
      (let ([least (let loop ([n 0])
                     (if (bitwise-bit-set? mask n) n (loop (+ n 1))))])
        (if (= least 0)
            "Takes any number of arguments."
            (format "Takes ~a or more." (args least))))
      (let ([ns (filter (lambda (n) (bitwise-bit-set? mask n))
                        (iota (max 1 (bitwise-length mask))))])
        (cond
          [(null? ns) ""]
          [(null? (cdr ns)) (format "Takes ~a." (args (car ns)))]
          [else (format "Takes ~a or ~a."
                        (string-join (map number->string
                                          (reverse (cdr (reverse ns))))
                                     ", ")
                        (args (car (last-pair ns))))]))))

(define (name-kind name e)
  (let-values ([(env sym) (env-binding e (string->symbol name))])
    (cond
      [(top-level-bound? sym env)
       (if (procedure? (top-level-value sym env)) "proc" "var")]
      [(top-level-syntax? sym env) "syntax"]
      [else ""])))

;;; What to complete, by context.

;; After a quote in one of these forms, offer only what fits there.
;; (operator kind choices-thunk), or (operator kind thunk key) to apply only
;; when the form's text mentions 'key (set-theme!'s second argument).
(define completion-quoted
  `((set-theme! "style" ,(lambda () (map symbol->string (styles)))
                window-style)
    (set-theme! "wallpaper" ,(lambda () (map symbol->string (wallpapers)))
                wallpaper)
    (set-theme! "palette" ,(lambda () (map symbol->string (palettes))) palette)
    (set-theme! "key" ,(lambda () (map symbol->string (theme-keys))))
    (set-style! "style" ,(lambda () (map symbol->string (styles))))
    (override! "key" ,(lambda () (map symbol->string (theme-keys))))
    (reset-style! "key" ,(lambda () (map symbol->string (theme-keys))))
    (theme-source "key" ,(lambda () (map symbol->string (theme-keys))))
    (theme "key" ,(lambda () (map symbol->string (theme-keys))))
    (theme-part "key" ,(lambda () (map symbol->string (theme-keys))))
    (theme-default "key" ,(lambda () (map symbol->string (theme-keys))))
    (app-launch! "app" ,(lambda () (map symbol->string (apps))))
    (find-window "app" ,(lambda () (map symbol->string (apps))))
    (set-palette! "palette"
                         ,(lambda () (map symbol->string (palettes))))
    (theme-palette-preview "palette"
                           ,(lambda () (map symbol->string (palettes))))))

;; (values kind start typed choices): choices are (name . kind-or-#f);
;; a kind of #f is looked up in the environment when shown.
(define (completion-context r)
  (let ([s (repl-input r)] [p (repl-point r)])
    (let-values ([(stack str?) (scan-parens s p)])
      (cond
        [str? (path-context s p)]
        [(library-context s p stack)
         => (lambda (lib)
              (apply (lambda (parts start typed)
                       (values 'library start typed (library-choices parts)))
                     lib))]
        [else
          (let* ([start (let loop ([i p])
                          (if (and (> i 0)
                                   (symbol-char? (string-ref s (- i 1))))
                              (loop (- i 1))
                              i))]
                 [typed (substring s start p)]
                 [quoted (and (> start 0)
                              (char=? (string-ref s (- start 1)) #\')
                              (pair? stack)
                              (quoted-choices r s (car stack) start))])
            (values 'symbols start typed
                    (or quoted
                        (map (lambda (sym) (cons (symbol->string sym) #f))
                             (remp gensym?
                                   (environment-symbols
                                    (repl-environment r)))))))]))))

;; The choices for a quoted name inside the form opening at open, or #f.
(define (quoted-choices r s open start)
  (let* ([form (substring s open start)]
         [op (let ([end (let loop ([i (+ open 1)])
                          (if (and (< i start) (symbol-char? (string-ref s i)))
                              (loop (+ i 1))
                              i))])
               (string->symbol (substring s (+ open 1) end)))])
    (and (let-values ([(env name) (env-binding (repl-env r) op)])
           (top-level-bound? name env))
         (let ([entry (find (lambda (e)
                              (and (eq? (car e) op)
                                   (or (null? (cdddr e))
                                       (string-contains-ci?
                                        form (format "'~a" (cadddr e))))))
                            completion-quoted)])
           (and entry
                (guard (c [#t #f])
                  (map (lambda (name) (cons name (cadr entry)))
                       ((caddr entry)))))))))

;; Inside a string: complete the last part of a file name.
(define (path-context s p)
  (let* ([open (let loop ([i (- p 1)])
                 (if (and (>= i 0)
                          (not (and (char=? (string-ref s i) #\")
                                    (not (and (> i 0)
                                              (char=? (string-ref s (- i 1))
                                                      #\\))))))
                     (loop (- i 1))
                     i))]
         [text (substring s (+ open 1) p)]
         [slash (let loop ([i (- (string-length text) 1)])
                  (cond [(< i 0) #f]
                        [(char=? (string-ref text i) #\/) i]
                        [else (loop (- i 1))]))]
         [dir (if slash (substring text 0 (+ slash 1)) "")]
         [base (if slash
                   (substring text (+ slash 1) (string-length text))
                   text)]
         [real-dir (cond
                     [(string=? dir "") "."]
                     [(string-prefix? "~/" dir)
                      (string-append (or (getenv "HOME") "")
                                     (substring dir 1 (string-length dir)))]
                     [else dir])]
         [entries (guard (c [#t '()]) (directory-list real-dir))])
    (values 'path (- p (string-length base)) base
            (filter-map (lambda (e)
                          (and (or (string-prefix? "." base)
                                   (not (string-prefix? "." e)))
                               (if (guard (c [#t #f])
                                     (file-directory?
                                      (string-append real-dir "/" e)))
                                   (cons (string-append e "/") "dir")
                                   (cons e "file"))))
                        entries))))

;;; Library names inside (import ...), offered a part at a time like the
;;; folders of a file name: (import (acme m| offers math when acme/math.sls
;;; is in a library directory or (acme math) is loaded.

(define import-set-forms
  '((only "(only import-set name ...)" "Just these names.")
    (except "(except import-set name ...)" "Everything but these names.")
    (prefix "(prefix import-set prefix)" "Every name, with prefix in front.")
    (rename "(rename import-set (old new) ...)"
            "These names, called something else.")
    (for "(for import-set level ...)"
         "Imported for these levels (run, expand).")
    (library "(library name)"
             "A library whose name starts with one of these words.")))

;; The symbol right after the paren at open, and the index after it.
(define (form-head s open)
  (let* ([n (string-length s)]
         [b (let loop ([i (+ open 1)])
              (if (and (< i n) (char-whitespace? (string-ref s i)))
                  (loop (+ i 1))
                  i))]
         [e (let loop ([i b])
              (if (and (< i n) (symbol-char? (string-ref s i)))
                  (loop (+ i 1))
                  i))])
    (values (and (< b e) (string->symbol (substring s b e))) e)))

;; Does the list opening at (car stack) stand where an import set goes:
;; an argument of import, or the first argument of only, prefix and the like?
(define (import-set-position? s stack)
  (and (pair? stack) (pair? (cdr stack))
       (let-values ([(head end) (form-head s (cadr stack))])
         (case head
           [(import) #t]
           [(only except prefix rename for library)
            (and (for-all char-whitespace?
                          (string->list (substring s end (car stack))))
                 (import-set-position? s (cdr stack)))]
           [else #f]))))

;; In a library name: (parts start typed), parts being the symbols before
;; the one at the cursor; else #f.
(define (library-context s p stack)
  (and (import-set-position? s stack)
       (let* ([start (let loop ([i p])
                       (if (and (> i 0) (symbol-char? (string-ref s (- i 1))))
                           (loop (- i 1))
                           i))]
              [before (string->list (substring s (+ (car stack) 1) start))]
              [parts (let loop ([cs before] [word '()] [acc '()])
                       (define (flush)
                         (if (null? word)
                             acc
                             (cons (string->symbol
                                    (list->string (reverse word)))
                                   acc)))
                       (cond [(null? cs) (reverse (flush))]
                             [(char-whitespace? (car cs))
                              (loop (cdr cs) '() (flush))]
                             [else (loop (cdr cs) (cons (car cs) word) acc)]))])
         (and (for-all (lambda (c) (or (char-whitespace? c) (symbol-char? c)))
                       before)
              (not (and (pair? parts) (assq (car parts) import-set-forms)))
              (list parts start (substring s start p))))))

;; Where to look for library files: Chez's library directories, except the
;; current one (often the home folder; what is there still imports).
(define (library-source-directories)
  (filter (lambda (d) (not (member d '("" "."))))
          (map (lambda (e) (if (pair? e) (car e) e)) (library-directories))))

;; File extensions of library sources, longest first (.chezscheme.sls before
;; .sls).
(define (library-source-extensions)
  (sort (lambda (a b) (> (string-length a) (string-length b)))
        (map (lambda (e) (if (pair? e) (car e) e)) (library-extensions))))

;; "math" for "math.sls", or #f.
(define (library-file-name entry)
  (let ([ext (find (lambda (x) (string-suffix? x entry))
                   (library-source-extensions))])
    (and ext (> (string-length entry) (string-length ext))
         (substring entry 0 (- (string-length entry) (string-length ext))))))

;; The parts that can follow parts: (name . "library") when parts plus name
;; is a library, (name . "group") when only longer names go on from it.
(define (library-choices parts)
  ;; name -> (library? . group?)
  (let ([found (make-hashtable string-hash string=?)]
        [n (length parts)])
    (define (note! name lib? group?)
      (let ([old (hashtable-ref found name '(#f . #f))])
        (hashtable-set! found name
                        (cons (or lib? (car old)) (or group? (cdr old))))))
    (for-each (lambda (lib)
                (when (and (> (length lib) n)
                           (equal? (list-head lib n) parts)
                           (symbol? (list-ref lib n)))
                  (note! (symbol->string (list-ref lib n))
                         (= (length lib) (+ n 1))
                         (> (length lib) (+ n 1)))))
              (library-list))
    (for-each (lambda (dir)
                (let ([d (fold-left (lambda (acc p)
                                      (string-append acc "/"
                                                     (symbol->string p)))
                                    dir parts)])
                  (for-each (lambda (e)
                              (unless (string-prefix? "." e)
                                (cond
                                  [(guard (c [#t #f])
                                     (file-directory? (string-append d "/" e)))
                                   (note! e #f #t)]
                                  [(library-file-name e)
                                   => (lambda (name) (note! name #t #f))])))
                            (guard (c [#t '()]) (directory-list d)))))
              (library-source-directories))
    (let-values ([(names vals) (hashtable-entries found)])
      (append (map (lambda (name v) (cons name (if (car v) "library" "group")))
                   (vector->list names) (vector->list vals))
              (if (null? parts)
                  (map (lambda (f) (cons (symbol->string (car f)) "import set"))
                       import-set-forms)
                  '())))))

;; The source file of a library, or #f.
(define (library-file lib)
  (let ([rel (string-join (map symbol->string lib) "/")])
    (exists (lambda (dir)
              (exists (lambda (ext)
                        (let ([f (string-append dir "/" rel ext)])
                          (and (file-exists? f) f)))
                      (library-source-extensions)))
            (library-source-directories))))

;; The names a library file exports, read (not run) from its export clause.
(define (file-exports file)
  (guard (c [#t #f])
    (let ([form (call-with-input-file file read)])
      (and (pair? form) (memq (car form) '(library define-library))
           (let ([ex (find (lambda (x) (and (pair? x) (eq? (car x) 'export)))
                           (cdr form))])
             (and ex
                  (apply append
                         (map (lambda (spec)
                                (cond
                                  [(symbol? spec) (list spec)]
                                  [(and (pair? spec) (eq? (car spec) 'rename))
                                   (if (and (pair? (cdr spec))
                                            (symbol? (cadr spec)))
                                       ;; R7RS (rename old new)
                                       (cddr spec)
                                       ;; R6RS (rename (old new) ...)
                                       (filter-map (lambda (p)
                                                     (and (pair? p)
                                                          (pair? (cdr p))
                                                          (cadr p)))
                                                   (cdr spec)))]
                                  [else '()]))
                              (cdr ex)))))))))

;; (values signature doc) for a choice after parts.
(define (library-description parts name kind)
  (let ([lib (append parts (list (string->symbol name)))])
    (cond
      [(string=? kind "import set")
       (let ([f (assq (string->symbol name) import-set-forms)])
         (values (cadr f) (caddr f)))]
      [(string=? kind "group") (values (format "~s" (append lib '(...))) "")]
      [else
       (let* ([file (library-file lib)]
              [exports (if (member lib (library-list))
                           (library-exports lib)
                           (and file (file-exports file)))])
         (values (format "~s" lib)
                 (string-append
                   (if exports
                       (format "Exports ~a."
                               (string-join (sort string<?
                                                  (map symbol->string exports))
                                            " "))
                       "")
                   (if file (format " From ~a." file) ""))))])))

;;; Ranking.

;; The choices matching typed, best first: #((name kind matched) ...).
(define (rank-choices typed choices)
  (let ([docs (name-docs)])
    (complete-rank typed choices
                   (lambda (name) (hashtable-contains? docs name)))))

;;; Opening, narrowing and accepting.

;; Tab (see complete-tab!). A sole folder or library group goes in, to
;; carry on inside it.
(define (repl-complete! r)
  (let-values ([(kind start typed choices) (completion-context r)])
    (if (and (eq? kind 'symbols) (string=? typed ""))
        (repl-insert! r "  ")
        (let ([items (rank-choices typed choices)])
          (when (zero? (vector-length items)) (bell))   ; nothing to complete
          (if (and (= 1 (vector-length items))
                   (carries-on? kind (vector-ref items 0)))
              (accept-completion! r kind start (vector-ref items 0))
              (complete-tab! r kind start typed items
                             (lambda (shared)
                               (repl-delete! r start (repl-point r))
                               (repl-insert! r shared)
                               (refresh-completion! r))
                             (lambda (item)
                               (accept-completion! r kind start item))))))))

;; After the input changed while the list is open: narrow it, or close it
;; when the cursor has left the name.
(define (refresh-completion! r)
  (let ([c (complete-of r)])
    (when c
      (let-values ([(kind start typed choices) (completion-context r)])
        (if (or (not (eq? kind (complete-context c)))
                (and (memq kind '(symbols library))
                     (not (= start (complete-start c))))
                (and (eq? kind 'symbols) (string=? typed "")))
            (complete-close! r)
            (complete-narrow! r kind start typed
                              (rank-choices typed choices)))))))

;; Does taking item carry on inside it: a directory, or the start of
;; longer library names?
(define (carries-on? kind item)
  (or (and (eq? kind 'path) (string-suffix? "/" (car item)))
      (and (eq? kind 'library) (equal? (cadr item) "group"))))

(define (accept-completion! r kind start item)
  (repl-delete! r start (repl-point r))
  (repl-insert! r (car item))
  (complete-close! r)
  (when (carries-on? kind item)
    (when (eq? kind 'library) (repl-insert! r " "))
    (let-values ([(kind start typed choices) (completion-context r)])
      (complete-open! r kind start (rank-choices typed choices)))))

;; The item chosen from r's open list goes in.
(define (repl-accept! r item)
  (let ([c (complete-of r)])
    (accept-completion! r (complete-context c) (complete-start c) item)))

;; (values signature doc) for an item of c, r's list.
(define (completion-description r c item)
  (case (complete-context c)
    [(symbols) (name-description (car item) (repl-env r))]
    [(library)
     (let* ([s (repl-input r)] [start (complete-start c)]
            [lib (let-values ([(stack str?) (scan-parens s start)])
                   (library-context s start stack))])
       (if lib
           (library-description (car lib) (car item) (cadr item))
           (values "" "")))]
    [else (values "" "")]))

;; With the completion list open, it takes the keys it uses, and a popup
;; goes at any key. Moving the cursor away closes the list; editing
;; narrows it. (Printable characters arrive as 'text, and modifier keys
;; alone change nothing.)
(define (repl-key r win key mods)
  (if (complete-key! r key mods (lambda (item) (repl-accept! r item)))
      (invalidate! win)
      (let ([c (complete-of r)])
        (when (and c (or (memq key '(left right home end))
                         (memq 'ctrl mods) (memq 'alt mods)))
          (complete-close! r))
        (repl-edit-key r win key mods)
        (when (and c (memq key '(backspace delete)))
          (refresh-completion! r)))))

;; The pointer over the REPL: the completion list's where it is, an arrow
;; over the busy mark, else an I-beam with nothing to say (the REPL has no
;; use for the buttons); #t when the list's row under it changed.
(define (repl-pointer! r win)
  (complete-pointer! r win (if (repl-over-busy? r win) 'arrow 'ibeam) '()))

;; Is the pointer over the busy mark, as last drawn?
(define (repl-over-busy? r win)
  (let ([b (repl-busy r)] [at (complete-pointer-at win)])
    (and b at (point-in? (car at) (cdr at) (car b) (cadr b) (caddr b)
                         (cadddr b)))))

;; A press goes to the completion list; the REPL has no other use for it.
(define (repl-mouse-down r)
  (lambda (win x y button clicks)
    (complete-mouse-down! r x y button
                          (lambda (item) (repl-accept! r item)))))

;; Losing the keyboard closes the list or popup: a click on another
;; window or on the desktop, a key or a call that focuses another window,
;; the REPL minimized. A press on its own title bar or frame, or on an
;; empty part of a bar, leaves the REPL the keyboard, and the list open.
(define (repl-blur r)
  (lambda (win)
    (complete-close! r)
    (invalidate! win)))

;; While it has the keyboard its caret blinks, by a timer at each flip,
;; 530 ms after the last (a key holds it on); one timer at a time.
(define (repl-blink-soon! r win)
  (unless (window-ref win 'repl-blinking #f)
    (window-set! win 'repl-blinking #t)
    (repl-blink-next! r win)))

(define (repl-blink-next! r win)
  (after (max 1 (- (+ (repl-blink-at r) 530) (now-ms)))
         (lambda ()
           (cond
             [(not (and (memq win (windows)) (eq? win (focused-window))))
              (window-set! win 'repl-blinking #f)]
             [(>= (- (now-ms) (repl-blink-at r)) 530)
              (repl-blink-set! r (not (repl-blink r)))
              (repl-blink-at-set! r (now-ms))
              (invalidate! win)
              (repl-blink-next! r win)]
             [else (repl-blink-next! r win)]))))

(define (repl-edit-key r win key mods)
  (repl-blink-set! r #t)
  (repl-blink-at-set! r (now-ms))
  (let ([s (repl-input r)] [p (repl-point r)] [ctrl? (memq 'ctrl mods)])
    (cond
      ;; Ctrl+C stops the running form and drops what waits, as a
      ;; terminal's interrupt flushes its type-ahead (it is history)
      [(and ctrl? (eqv? key #\c))
       (if (repl-proc r)
           (begin (repl-queue-set! r '()) (repl-stop! r win))
           (begin (repl-echo! r (string-append s "^C"))
                  (repl-input-set! r "")
                  (repl-point-set! r 0)))]
      [(and ctrl? (eqv? key #\l))
       (transcript-clear! (repl-transcript r))]
      [(and ctrl? (eqv? key #\a)) (repl-point-set! r (line-start s p))]
      [(and ctrl? (eqv? key #\e)) (repl-point-set! r (line-end s p))]
      [(and ctrl? (eqv? key #\k))
       (repl-delete! r p (max (line-end s p) (min (+ p 1) (string-length s))))]
      [(and ctrl? (eqv? key #\u)) (repl-delete! r (line-start s p) p)]
      [(or (and ctrl? (eqv? key #\v))
           (and (eq? key 'insert) (memq 'shift mods)))
       (repl-insert! r (list->string
                        (remv #\return (string->list (clipboard-get)))))]
      [ctrl? (void)]
      [else
       (case key
         [(return)
          (cond
            [(memq 'shift mods) (repl-newline! r)]
            [(not (input-complete? s)) (repl-newline! r)]
            ;; nothing typed waits for nothing
            [(and (repl-proc r) (string=? "" (string-trim s))) (void)]
            [else (repl-submit! r win)])]
         [(backspace)
          (cond [(> p 0) (repl-delete! r (- p 1) p)]
                ;; on an empty line, the last waiting input comes back
                [(and (string=? s "") (pair? (repl-queue r)))
                 (let ([q (repl-queue r)])
                   (repl-queue-set! r (list-head q (- (length q) 1)))
                   (repl-input-set! r (car (last-pair q)))
                   (repl-point-set! r (string-length (repl-input r))))])]
         [(delete) (when (< p (string-length s)) (repl-delete! r p (+ p 1)))]
         [(left) (repl-point-set! r (max 0 (- p 1)))]
         [(right) (repl-point-set! r (min (string-length s) (+ p 1)))]
         [(home) (repl-point-set! r (line-start s p))]
         [(end) (repl-point-set! r (line-end s p))]
         [(up) (repl-up! r)]
         [(down) (repl-down! r)]
         [(tab) (repl-complete! r)]
         [(page-up)
          (repl-scroll-set! r (+ (repl-scroll r) (max 1 (- (repl-rows r) 2))))]
         [(page-down)
          (repl-scroll-set! r (max 0 (- (repl-scroll r)
                                        (max 1 (- (repl-rows r) 2)))))]
         [(escape) (repl-scroll-set! r 0)])])
    (invalidate! win)))

(define (repl-text r win str)
  (complete-text! r)
  (repl-insert! r str)
  (refresh-completion! r)
  (repl-scroll-set! r 0)
  (repl-blink-set! r #t)
  (repl-blink-at-set! r (now-ms))
  (invalidate! win))

;;; ------------------------------------------------------------------ drawing

(define repl-pad transcript-pad)
(define (repl-line-height) (transcript-line-height))

;; How far below a row's top what marks a character (the cursor, a
;; matching paren) starts, th high: centered on the ink of parentheses,
;; in whole device pixels. (The font's own box sits differently around
;; its glyphs at each size, as its metrics round.)
(define (repl-mark-top th)
  (let-values ([(l top w h) (text-ink "()" 'mono)])
    (let ([middle (+ (font-ascent 'mono) top (/ h 2))])
      (/ (round (* *scale* (- middle (/ th 2)))) *scale*))))

;; A new REPL opens with room for this many characters, like a terminal,
;; whatever size the code font is.
(define repl-initial-cols 80)
(define repl-initial-rows 22)

(define (repl-window-size)
  (cons (exact (ceiling (+ repl-pad repl-pad
                           (* repl-initial-cols (font-char-width 'mono)))))
        (exact (ceiling (+ repl-pad repl-pad
                           (* repl-initial-rows (repl-line-height)))))))

(define (repl-draw r win w h)
  (let* ([cw (font-char-width 'mono)]
         [lh (repl-line-height)]
         ;; the text's own height (a row is that and a gap below it), the
         ;; height of what marks a character
         [th (font-line-height 'mono)]
         [mark-top (repl-mark-top th)]
         [pad repl-pad]
         [cols (max 8 (exact (floor (/ (- w pad pad) cw))))]
         [rows (max 1 (exact (floor (/ (- h pad pad) lh))))]
         [focused? (eq? win (focused-window))]
         [busy? (repl-busy? r)]
         [input (repl-input r)]
         [ilines (string-split input #\newline)]
         ;; logical lines, bottom-up: input lines, the inputs waiting
         ;; (the newest lowest), then the transcript
         [input-entries
          (let loop ([ls ilines] [i 0] [start 0] [acc '()])
            (if (null? ls)
                acc
                (loop (cdr ls) (+ i 1) (+ start (string-length (car ls)) 1)
                      (cons (list 'edit
                                  (string-append (if (= i 0)
                                                     repl-prompt
                                                     repl-cont)
                                                 (car ls))
                                  start)
                            acc))))]
         [waiting
          (apply append
                 (map (lambda (src)
                        (reverse
                         (map (lambda (l i)
                                (cons 'wait
                                      (string-append (if (= i 0)
                                                         repl-waiting
                                                         repl-cont)
                                                     l)))
                              (string-split src #\newline)
                              (iota (length (string-split src #\newline))))))
                      (reverse (repl-queue r))))]
         ;; the running input's prompt is the busy mark's place, once it
         ;; shows, where its style gives it a size
         [marked (and busy? (repl-running r)
                      (let-values ([(bw bh) (ui-busy-size)]) (> bw 0))
                      (repl-running r))]
         [paren (let ([p (repl-point r)])
                  (or (and (> p 0) (memv (string-ref input (- p 1)) '(#\) #\]))
                           (let ([m (matching-paren input (- p 1))])
                             (and m (list m (- p 1)))))
                      (and (< p (string-length input))
                           (memv (string-ref input p) '(#\( #\[))
                           (let ([m (matching-paren input p)])
                             (and m (list p m))))))]
         [total
          (+ (fold-left (lambda (acc e)
                          (+ acc (transcript-rows (string-length (cadr e))
                                                  cols)))
                        0 input-entries)
             (fold-left (lambda (acc l)
                          (+ acc (transcript-rows (string-length (cdr l))
                                                  cols)))
                        0 (append waiting (repl-lines r))))]
         [caret #f]   ; where the cursor was drawn: (x . y)
         [mark #f])   ; where the running input's prompt was drawn: (x . y)
    (repl-cols-set! r cols)
    (repl-rows-set! r rows)
    (repl-scroll-set! r (clamp (repl-scroll r) 0 (max 0 (- total rows))))
    (fill-box 0 0 w h (repl-background r))
    ;; Lay out bottom-up; while everything fits, hang it from the top instead.
    (let loop ([entries (append input-entries waiting (repl-lines r))]
               [bottom (if (< total rows) (+ pad (* total lh)) (- h pad))]
               [skip (repl-scroll r)])
      (when (and (pair? entries) (> bottom 0))
        (let* ([e (car entries)]
               [edit? (and (pair? e) (eq? (car e) 'edit))]
               [text (if edit? (cadr e) (cdr e))]
               [k (transcript-rows (string-length text) cols)]
               [shown (- k (min skip k))])
          (if (= shown 0)
              (loop (cdr entries) bottom (- skip k))
              (let ([top (- bottom (* shown lh))])
                (cond
                  [edit?
                   (let* ([start (caddr e)]
                          [colors (transcript-draw-scheme text 3)])
                     (transcript-fill-colors! colors 0 3 (car (repl-look r)))
                     (when paren
                       (for-each
                        (lambda (i)
                          (let ([j (+ 3 (- i start))])
                            (when (and (>= i start) (< j (string-length text)))
                              (let ([row (quotient j cols)]
                                    [col (remainder j cols)])
                                (when (< row shown)
                                  (fill-box (+ pad (* col cw))
                                            (+ top (* row lh) mark-top) cw th
                                            'repl-paren-mark 3)))
                              (vector-set! colors j 'yellow))))
                        paren))
                     (transcript-draw-line pad top text colors cols 0 shown cw
                                           lh)
                     ;; the cursor
                     (let ([p (repl-point r)]
                           [end (+ start (- (string-length text) 3))])
                       (when (and (>= p start) (<= p end))
                         (let* ([j (+ 3 (- p start))]
                                [row (quotient j cols)]
                                [col (remainder j cols)])
                           (when (< row shown)
                             (set! caret (cons (+ pad (* col cw))
                                               (+ top (* row lh))))
                             (cond
                               [(not focused?)
                                (stroke-box (+ pad (* col cw))
                                            (+ top (* row lh) mark-top)
                                            cw th 'text-faint)]
                               [(repl-blink r)
                                (repl-draw-cursor (+ pad (* col cw))
                                                  (+ top (* row lh) mark-top)
                                                  cw th)]))))))]
                  [(eq? (car e) 'input)
                   (let ([colors (transcript-draw-scheme text 3)])
                     (transcript-fill-colors! colors 0 3 'text-faint)
                     (when (eq? e marked)
                       (transcript-fill-colors! colors 0 3 (repl-background r))
                       (set! mark (cons pad top)))
                     (transcript-draw-line pad top text colors cols 0 shown cw
                                           lh))]
                  [(eq? (car e) 'wait)
                   (transcript-draw-line pad top text 'text-faint cols 0 shown
                                         cw lh)]
                  [else
                   (transcript-draw-line pad top text
                                         (transcript-draw-style-color (car e))
                                         cols 0 shown cw lh)])
                (loop (cdr entries) top 0))))))
    (transcript-draw-scrollbar (repl-transcript r) w h rows total)
    (repl-draw-busy r win mark cw th mark-top)
    (let ([c (complete-of r)] [e (repl-env r)])
      (when c
        (complete-show c caret (* cw (- (repl-point r) (complete-start c)))
                       lh w h (lambda (name) (name-kind name e))
                       (lambda (item) (completion-description r c item)))))
    (repl-draw-busy-tip r win w h)
    (repl-pointer! r win)))

;; The busy mark, at the size its style gives it, from the prompt's start
;; (mark: its row's top, or #f, none to draw), centered on the cells cw
;; wide it spans (the default's two, Genera's one), and on the text th
;; high from mark-top.
(define (repl-draw-busy r win mark cw th mark-top)
  (let-values ([(bw bh) (ui-busy-size)])
    (repl-busy-set! r #f)
    (when (and mark (> bw 0) (> bh 0))
      (let* ([cells (* cw (max 1 (ceiling (/ bw cw))))]
             [bx (+ (car mark) (/ (- cells bw) 2))]
             [by (+ (cdr mark) mark-top (/ (- th bh) 2))])
        (repl-busy-set! r (list bx by bw bh (now-ms)))
        (ui-draw-busy bx by bw bh
                      (if (repl-over-busy? r win) '(hover) '())
                      (now-ms))))))

;; Its words, once the pointer has rested on it, as the kit's tooltips
;; wait, in a window w × h.
(define (repl-draw-busy-tip r win w h)
  (let ([p (repl-pointer r)])
    (when (and p (repl-over-busy? r win)
               (>= (- (now-ms) (caddr p)) ui-tip-ms))
      (with-place 'tooltip
        (lambda ()
          (let*-values ([(words) (repl-busy-words r)]
                        [(tw th) (ui-tooltip-size words)]
                        [(tx ty) (ui-popup-place (+ (car p) 12) (+ (cadr p) 20)
                                                 (- (cadr p) 8) tw th w h)])
            (ui-draw-tooltip tx ty tw th '() words)))))))

;; The cursor before the character cw × th at (x, y): the text kit's
;; caret, a bar, or a block in reverse video over the character.
(define (repl-draw-cursor x y cw th)
  (if (eq? (theme 'text-caret) 'block)
      (px-invert x y cw th)
      (fill-box x y 2 th 'accent)))

;; Under the parenthesis that matches the one at the cursor, and it.
(color-default! 'repl-paren-mark (theme-rule (alpha 'yellow 0.25)))

;; Parentheses: as quiet as faint text, but code, not a hint, so a style's
;; faint-text font (Genera's italic) leaves them as the rest of the code.

;;; ------------------------------------------------------------------ the app

(define (repl-examples! r examples)
  (for-each (lambda (l) (repl-add! r 'input (string-append "   " l))) examples))

(define (repl-banner! r)
  (let ([path (env-path (repl-env r))])
    (case (repl-kind r)
      [(root)
       (repl-add! r 'banner (format "Schevana — a world made of Scheme.   ~a"
                                    (scheme-version)))
       (repl-add! r 'info "Every window, color and key binding here is a \
                           live Scheme value. Try:")
       (repl-examples!
        r
        '("(clock)                          ; apps are just procedures"
          "(windows)                        ; the window list, as data"
          "(set-theme! 'accent #xff9e64)    ; recolor the world"
          "(spawn \"spin\" (lambda () (let loop () (loop))))"))
       (repl-add! r 'info "F1 apps · Ctrl+Tab switch · Tab completes · \
                           Shift+Enter newline · Ctrl+C stops")
       (repl-add! r 'info "To experiment without changing anything, \
                           Ctrl+Shift+P opens a Private REPL;")
       (repl-add! r 'info "(envs) shows the tree of environments, and opens \
                           a REPL in any of them.")]
      [(private)
       (repl-add! r 'banner (format "Private REPL in ~a — like a private \
                                     browsing window." path))
       (repl-add! r 'info "Your definitions stay here. Of the world it sees \
                           what reads it, live,")
       (repl-add! r 'info "and set! of that is refused. Try:")
       (repl-examples!
        r
        '("(map window-title (windows))"
          "(define (draw-window win) (error 'oops \"broken\"))  ; harmless \
here"))]
      [(world)
       (repl-add! r 'banner (format "World REPL in ~a — the world's names, \
                                     live, under yours." path))
       (repl-add! r 'info "Every name of the world's is here, those it gains \
                           later too, and set! of")
       (repl-add! r 'info "one is refused. Your definitions stay here. \
                           Calling the world's procedures")
       (repl-add! r 'info "still acts on the world: (set-theme! ...) \
                           recolors it. (fork) makes children.")]
      [(pure)
       (repl-add! r 'banner (format "Pure Scheme REPL in ~a — plain ~a."
                                    path (scheme-version)))
       (repl-add! r 'info "None of Schevana's names are bound here: a clean \
                           scratchpad whose")
       (repl-add! r 'info "definitions are invisible everywhere else.")]
      [(sandbox)
       (repl-add! r 'banner (format "Sandbox REPL in ~a — Scheme's pure \
                                     core, and what it was shared." path))
       (repl-add! r 'info "No files, no C, no threads: only what its parent \
                           shared with it reaches out.")]
      [(thread)
       (repl-add! r 'banner (format "Thread REPL in ~a — the forms run on \
                                     its vat's thread." path))
       (repl-add! r 'info "Its sandbox is the vat's alone: what you define \
                           lives there. Ctrl+C stops a form there.")])
    (when (and (env-parent (repl-env r)) (eq? (env-base (repl-env r)) 'chez))
      (repl-add! r 'info "(exit) closes this REPL."))
    (repl-add! r 'info "")))

;; A REPL in what (see repl-environment-of): the world's by default.
(define (open-repl what)
  (let-values ([(e own?) (repl-environment-of what)])
    (let ([r (make-repl (transcript-new) "" 0 '() -1 #f #f '() #f #t (now-ms)
                        repl-initial-cols repl-initial-rows '() e own? #f #f
                        #f #f)])
      (repl-port-set! r (make-repl-port r))
      (repl-banner! r)
      (let ([win (open-repl-window r)])
        ;; In a namespace, (exit) closes the window, not the world; but in
        ;; core0's, where exit is how core0 ends the process
        (when (and (env-parent e) (eq? (env-base e) 'chez)
                   (not (eq? (env-kind e) 'host)))
          (repl-define-exit! win e))
        win))))

(define (repl-define-exit! win e)
  (define-top-level-value 'exit (lambda args (close-window! win))
                          (env-environment e)))

(define-app (repl . what) "REPL"
  (open-repl (if (pair? what) (car what) 'root)))
(define-app (private-repl) "Private REPL" (open-repl 'private))
(define-app (pure-repl) "Pure Scheme REPL" (open-repl 'pure))

(define (open-repl-window r)
  (open-window (repl-title r)
    'size (repl-window-size)
    'min-size '(240 . 120)
    'cursor 'ibeam
    'bg (repl-background r)
    'title-icon (lambda (x y s flags)
                  (ui-draw-env-icon x y s flags (repl-kind r)))
    'draw (lambda (win w h)
            ;; the environment dropped since: the title says so, in the
            ;; next frame, the bars' too
            (unless (string=? (window-title win) (repl-title r))
              (window-title-set! win (repl-title r))
              (invalidate!))
            (repl-draw r win w h))
    'key (lambda (win key mods) (repl-key r win key mods))
    'text (lambda (win str) (repl-text r win str))
    'wheel (lambda (win dx dy)
             (unless (complete-wheel! r dy)
               (repl-scroll-set! r (max 0 (+ (repl-scroll r) (* 3 dy)))))
             (invalidate! win))
    'mouse-down (repl-mouse-down r)
    'mouse-move (lambda (win x y)
                  (let ([p (repl-pointer r)])
                    (unless (and p (= x (car p)) (= y (cadr p)))
                      (repl-pointer-set! r (list x y (now-ms)))
                      (when (repl-busy r) (invalidate! win))))
                  (when (repl-pointer! r win) (invalidate! win)))
    'blur (repl-blur r)
    'focus (lambda (win) (repl-blink-soon! r win))
    ;; what came out of its evaluation, while it runs or has output
    'frame (lambda (win t)
            (repl-drain! r)
            ;; busy once it has run a while; its mark drawn again as it
            ;; moves
            (let ([b (repl-busy r)])
              (cond [(and (repl-busy? r) (not (window-ref win 'busy)))
                     (window-set! win 'busy (repl-busy-words r))
                     (invalidate!)]   ; a style may show it in its bars
                    [(and b (>= (- (now-ms) (list-ref b 4))
                                (ui-busy-frame-ms)))
                     (invalidate! win)]))
            (when (repl-proc r) (window-frame-soon! win)))
    'close (lambda (win)
             (let ([p (repl-proc r)])
               (cond [(vat-job? p) (vat-job-kill! p)]
                     [p (kill! p)]))
             (when (and (repl-own? r) (not (env-dropped? (repl-env r))))
               (vat-drop-env! (repl-env r))))
    'state r))

;; A REPL opened before a reload has no mouse or blur handler: it gets
;; them, where it has none (one of a user's stays). Those it has call the
;; kit by name, so they run the code just loaded.
(for-each (lambda (win)
            (let ([r (window-ref win 'state #f)] [hs (window-handlers win)])
              (when (repl? r)
                (unless (hashtable-contains? hs 'mouse-down)
                  (hashtable-set! hs 'mouse-down (repl-mouse-down r)))
                (unless (hashtable-contains? hs 'blur)
                  (hashtable-set! hs 'blur (repl-blur r))))))
          (windows))
