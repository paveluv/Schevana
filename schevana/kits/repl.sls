;;; (schevana kits repl) — what a REPL is made of, for an app that reads
;;; Scheme and answers it (the REPL, the Debug REPL): its prompts, an input
;;; read with its places, a value as a REPL shows it, and a window sized as
;;; a terminal is.

(library (schevana kits repl)
  (export repl-prompt repl-cont repl-read-input! repl-value->string
          repl-initial-cols repl-initial-rows repl-window-size)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) font-char-width keep-source-text!)
          (only (schevana kits transcript) transcript-line-height
                transcript-pad))

  (library-layer kits)

  ;; What stands before an input's first line, and before its other lines.
  (define repl-prompt "λ> ")
  (define repl-cont   "   ")

  ;; Returns the forms of src, an input called name, with their places in
  ;; it, so that what they define tells where it came from (its
  ;; description, an error's place), and keeps src as the core keeps a
  ;; loaded file's text; () for an input with no form. Each input needs a
  ;; name of its own ("REPL input 12").
  (define (repl-read-input! src name)
    (let ([sfd (make-source-file-descriptor
                name (open-bytevector-input-port (string->utf8 src)))]
          [p (open-string-input-port src)])
      (let loop ([pos 0] [acc '()])
        (let-values ([(x end) (get-datum/annotations p sfd pos)])
          (cond
            [(not (eof-object? x)) (loop end (cons x acc))]
            [(null? acc) '()]
            [else (keep-source-text! name src) (reverse acc)])))))

  ;; Returns v as a REPL shows it: pretty-printed, with no newline at its
  ;; end.
  (define (repl-value->string v)
    (let ([s (with-output-to-string (lambda () (pretty-print v)))])
      (if (and (> (string-length s) 0)
               (char=? #\newline (string-ref s (- (string-length s) 1))))
          (substring s 0 (- (string-length s) 1))
          s)))

  ;; A new REPL opens with room for this many characters, like a terminal,
  ;; whatever size the code font is.
  (define repl-initial-cols 80)
  (define repl-initial-rows 22)

  ;; Returns the size a REPL's window opens at, as (w . h).
  (define (repl-window-size)
    (cons (exact (ceiling (+ transcript-pad transcript-pad
                             (* repl-initial-cols (font-char-width 'mono)))))
          (exact (ceiling (+ transcript-pad transcript-pad
                             (* repl-initial-rows
                                (transcript-line-height))))))))
