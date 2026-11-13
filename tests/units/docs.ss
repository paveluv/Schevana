;;; tests/units/docs.ss — the docs' examples run as they read: each page's
;;; scheme blocks (README.md, CREDITS.md, docs/*.md), in order, as typed at
;;; a REPL at "/", each form in a process, a page in a world of its own. A
;;; comment `; => value` after a form, on its line or the next, is checked
;;; as what it returns; an error, in a form, in what it left to run later
;;; (a timer, a then) or in a window's handler, fails its block. A block
;;; fenced "```scheme no-run" is shown, not run: one that never ends, or
;;; waits for a person.

;; The pages, from the tree's root.
(define (docs-pages)
  (append '("README.md" "CREDITS.md")
          (map (lambda (f) (string-append "docs/" f))
               (sort string<?
                     (filter (lambda (f) (string-suffix? ".md" f))
                             (directory-list
                              (string-append *schevana-root* "/docs")))))))

;; page's blocks to run, each (line . text), line where its code starts.
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

;; The value a `; => value` comment right after text's index i gives, as
;; (value), or #f for none: blanks, at most one newline, then the comment.
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

;; What form gives, run as a REPL runs its input: in a process, at "/",
;; the world stepping until it ends (at most 10 s). What it printed
;; is dropped; what it raised is raised again here.
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

;; Runs text's forms in the world, each checked against its `; =>`; then
;; a few steps, for what they left to run later.
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

(if docs-page
    (for-each (lambda (b)
                (check (format "~a, line ~a: its example runs as it reads"
                               docs-page (car b))
                       (docs-run! (cdr b))))
              (docs-blocks docs-page))
    (for-each
     (lambda (page)
       (when (pair? (docs-blocks page))
         (check (format "~a: its examples run, in a world of their own" page)
                (zero? (units-system-within
                        600
                        (units-chez (list (cons "SCHEVANA_DOCS_PAGE" page))
                                    (string-append *schevana-root*
                                                   "/tests/units.ss")
                                    out-dir "docs"))))))
     (docs-pages)))
