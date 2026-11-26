;;; tests/units/docs.ss — the docs' examples run as they read. Each page's
;;; scheme blocks (README.md, CREDITS.md, docs/*.md) run in order, as typed
;;; at a REPL at "/": each form in a process, each page in a world of its
;;; own. A comment `; => value` after a form, on its line or the next, is
;;; checked against what the form returns; an error in a form, in what it
;;; left to run later (a timer, a then) or in a window's handler fails its
;;; block. A block fenced "```scheme no-run" is shown, not run: one that
;;; never ends, or that waits for a person. A page's run keeps the tests'
;;; names and reach out of "/" (tests/reach.ss), so that an example finds
;;; only what a REPL there finds: what the world gives. The names of
;;; Schevana's that a page's prose writes as code are held to the same.

;; Returns page's blocks to run, each (line . text), where line is the
;; line its code starts on.
(define (docs-blocks page)
  (let loop ([lines (call-with-input-file
                        (string-append *schevana-root* "/" page)
                      (lambda (p)
                        (let read-lines ([acc '()])
                          (let ([l (get-line p)])
                            (if (eof-object? l)
                                (reverse acc)
                                (read-lines (cons l acc)))))))]
             [n 1] [block #f] [acc '()])
    (cond [(null? lines) (reverse acc)]
          [(and (not block) (string=? (car lines) "```scheme"))
           (loop (cdr lines) (+ n 1) (cons (+ n 1) '()) acc)]
          [(and block (string=? (car lines) "```"))
           (loop (cdr lines) (+ n 1) #f
                 (cons (cons (car block)
                             (apply string-append
                                    (map (lambda (l) (string-append l "\n"))
                                         (reverse (cdr block)))))
                       acc))]
          [block
           (loop (cdr lines) (+ n 1) (cons (car block) (cons (car lines)
                                                               (cdr block)))
                 acc)]
          [else (loop (cdr lines) (+ n 1) #f acc)])))

;; Returns the value that a `; => value` comment right after text's index
;; i gives, as (value), or #f for none. Only blanks and at most one
;; newline may come between i and the comment.
(define (docs-expected text i)
  (let* ([n (string-length text)]
         [skip (lambda (i nl?)
                 (let loop ([i i] [nl? nl?])
                   (cond [(>= i n) i]
                         [(memv (string-ref text i) '(#\space #\tab))
                          (loop (+ i 1) nl?)]
                         [(and nl? (char=? (string-ref text i) #\newline))
                          (loop (+ i 1) #f)]
                         [else i])))]
         [j (skip i #t)])
    (and (<= (+ j 4) n) (string=? (substring text j (+ j 4)) "; =>")
         (list (read (open-string-input-port (substring text (+ j 4) n)))))))

;; Returns what form gives, run as a REPL runs its input: in a process, at
;; "/", with the world stepping until it ends (at most 10 s). What it
;; printed is dropped; what it raised is raised again here.
(define (docs-eval form)
  (let ([done #f])
    (parameterize ([current-output-port (open-output-string)])
      (spawn "docs"
             (lambda () (env-eval (env-root) form))
             (lambda (status value) (set! done (cons status value)))))
    (let ([end (+ (real-time) 10000)])
      (let loop ()
        (unless (or done (> (real-time) end)) (steps 1) (loop))))
    (cond [(not done) (errorf 'docs "~s never ended" form)]
          [(eq? (car done) 'ok) (apply values (cdr done))]
          [(eq? (car done) 'error) (raise (cdr done))]
          [else (errorf 'docs "~s was killed" form)])))

;; Runs text's forms in the world, each checked against its `; =>`, then
;; takes a few steps, for what they left to run later.
(define (docs-run! text)
  (let ([p (open-string-input-port text)]
        [error-before (car *last-error*)])
    (let loop ()
      (let ([form (read p)])
        (unless (eof-object? form)
          (let ([v (docs-eval form)]
                [expected (docs-expected text (port-position p))])
            (when (and expected (not (equal? v (car expected))))
              (errorf 'docs "~s gave ~a" form
                      (parameterize ([print-length #f] [print-level #f])
                        (format "~s, not ~s" v (car expected))))))
          (loop))))
    (steps 3)
    (unless (equal? (car *last-error*) error-before)
      (errorf 'docs "later: ~a" (car *last-error*)))
    (let ([crashed (find window-error (windows))])
      (when crashed
        (errorf 'docs "~s crashed in its ~a: ~a" (window-title crashed)
                (car (window-error crashed))
                (condition->string (cdr (window-error crashed))))))
    #t))

(define docs-page (getenv "SCHEVANA_DOCS_PAGE"))

;; A page's world is the desktop's, with the demos' folder given to it
;; (./desktop demo), as its examples expect.
(when docs-page (auto-load! (string-append *schevana-root* "/demo")))

(define (docs-backquote text i)
  (let loop ([k i])
    (cond [(>= k (string-length text)) #f]
          [(char=? (string-ref text k) #\`) k]
          [else (loop (+ k 1))])))

;; Returns what page's prose writes as code, between backquotes, outside
;; its fenced blocks.
(define (docs-prose-code page)
  (let ([text (call-with-input-file (string-append *schevana-root* "/" page)
                get-string-all)])
    (let loop ([i 0] [in-block? #f] [acc '()])
      (let ([j (docs-backquote text i)])
        (cond
          [(not j) (reverse acc)]
          [(and (<= (+ j 3) (string-length text))
                (string=? (substring text j (+ j 3)) "```"))
           (loop (+ j 3) (not in-block?) acc)]
          [in-block? (loop (+ j 1) #t acc)]
          [else
           (let ([e (docs-backquote text (+ j 1))])
             (if e
                 (loop (+ e 1) #f (cons (substring text (+ j 1) e) acc))
                 (reverse acc)))])))))

;; Returns the name that code shows, a call's head or, unless calls-only?,
;; a name alone; or #f.
(define (docs-code-name code calls-only?)
  (let ([x (guard (c [#t #f]) (read (open-string-input-port code)))])
    (cond [(and (pair? x) (symbol? (car x))) (car x)]
          [(and (symbol? x) (not calls-only?)) x]
          [else #f])))

;; The names of Schevana's that the docs mention although "/" lacks them,
;; on purpose: a hook that a library calls by its own name, a shader's
;; name, and how a list of the core's shows another.
(define docs-unreached-names '(draw-window gfx-vertex show-list))

;; Returns the names of Schevana's that page's prose shows and "/" lacks:
;; names that the core's or core0's libraries define. Of the pages that
;; describe the core's insides and where each platform's code lives, only
;; the calls count, which are what a person types.
(define (docs-names-missing page)
  (let ([world (make-eq-hashtable)] [schevana (make-eq-hashtable)])
    (for-each (lambda (n) (hashtable-set! world n #t))
              (environment-symbols world-env))
    (for-each (lambda (n) (hashtable-set! schevana n #t))
              (append (environment-symbols core-env)
                      (environment-symbols main-env)))
    (let loop ([names (filter-map
                       (lambda (code)
                         (docs-code-name code
                                         (member page '("docs/INTERNALS.md"
                                                        "docs/PLATFORMS.md"))))
                       (docs-prose-code page))]
               [acc '()])
      (cond [(null? names) (reverse acc)]
            [(and (hashtable-ref schevana (car names) #f)
                  (not (hashtable-ref world (car names) #f))
                  (not (memq (car names) docs-unreached-names))
                  (not (memq (car names) acc)))
             (loop (cdr names) (cons (car names) acc))]
            [else (loop (cdr names) acc)]))))

(if docs-page
    (begin
      (for-each (lambda (b)
                  (check (format "~a, line ~a: its example runs as it reads"
                                 docs-page (car b))
                         (docs-run! (cdr b))))
                (docs-blocks docs-page))
      (let ([missing (docs-names-missing docs-page)])
        (check (format "~a: every name of Schevana's that its prose shows is \
                        one that \"/\" has, as a REPL there finds it \
                        (lacking: ~s)"
                       docs-page missing)
               (null? missing))))
    ;; Run by itself, this topic runs the pages at once, as many as the
    ;; machine allows, each in a folder of its own, and shows what each
    ;; printed after it, in order. (The units' runner runs each page as a
    ;; run of its own instead.)
    (let* ([pages (units-docs-pages)]
           [dirs (map (lambda (page)
                        (let ([d (format "~a/~a" out-dir
                                         (path-root (path-last page)))])
                          (unless (file-directory? d) (mkdir d))
                          d))
                      pages)])
      ;; The libraries are compiled once first, as the units' runner does
      ;; before its runs side by side. Each page's world loads the demos,
      ;; and compiles one whose object file is stale; Chez writes that
      ;; file in place, so a page that loads it meanwhile finds half a
      ;; library ("run-time information ... has not been loaded").
      (test-warm!)
      (test-system-all
       (test-jobs units-topic-mb) 600
       (map (lambda (page dir)
              (format "~a > ~a 2>&1"
                      (test-chez (list (cons "SCHEVANA_DOCS_PAGE" page))
                                 (string-append *schevana-root*
                                                "/tests/units.ss")
                                 dir "docs")
                      (test-sh-word (string-append dir "/said.txt"))))
            pages dirs)
       (lambda (i status)
         (let* ([page (list-ref pages i)] [dir (list-ref dirs i)]
                [said (call-with-input-file (string-append dir "/said.txt")
                        get-string-all)])
           (unless (eof-object? said) (put-string (current-output-port) said))
           (check (format "~a: its examples run, in a world of their own"
                          page)
                  (zero? status)))))))
