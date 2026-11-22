;;; tests/chez.ss — a suite's own run of Chez, through /bin/sh: a units
;;; topic, a forked world, the sources' suite again. It leans on nothing of
;;; the tree, so a suite loads it before the world, right after it has
;;; found the tree's root:
;;;
;;;   (load (string-append *schevana-root* "/tests/chez.ss"))
;;;   (system (test-chez '(("NAME" . "value")) script arg ...))

;; s as one word of /bin/sh's, whatever it holds.
(define (test-sh-word s)
  (let ([o (open-output-string)])
    (put-char o #\')
    (string-for-each
      (lambda (c) (if (char=? c #\') (put-string o "'\\''") (put-char o c)))
      s)
    (put-char o #\')
    (get-output-string o)))

;; The loader's variables that macOS drops on the way into /bin/sh: set
;; here, they're handed on by name.
(define test-loader-variables
  '("DYLD_LIBRARY_PATH" "DYLD_FALLBACK_LIBRARY_PATH"))

;; /bin/sh's command that becomes a run of Chez on script with args, with
;; env's variables, (name . value), and the loader's set. Chez is "chez"
;; where Homebrew installs it, else "scheme".
(define (test-chez env script . args)
  (format "exec env~{ ~a~} \"$(command -v chez || echo scheme)\" \
           --script~{ ~a~}"
          (map (lambda (v)
                 (string-append (car v) "=" (test-sh-word (cdr v))))
               (append env
                       (filter cdr
                               (map (lambda (name) (cons name (getenv name)))
                                    test-loader-variables))))
          (map test-sh-word (cons script args))))
