;;; src/build.ss — a library's main as a program of its own, compiled with
;;; the libraries it imports into out/lib: the libraries each to its own
;;; file, and the program with them all as one, which runs with no tree.
;;;
;;;   scheme --script src/build.ss schevana-demo game game-main
;;;   scheme --program out/lib/game.so --headless
;;;
;;; From the tree's root: the library's name, its parts, then its main,
;;; which is handed the program's command line's arguments.

(let* ([args (command-line-arguments)]
       [library (map string->symbol (reverse (cdr (reverse args))))]
       [main (string->symbol (car (last-pair args)))]
       [name (symbol->string (car (last-pair library)))]
       [out (lambda (extension) (format "out/lib/~a.~a" name extension))])
  (library-directories '(("." . "out/lib")))
  (compile-imported-libraries #t)
  (generate-wpo-files #t)
  (for-each (lambda (dir) (unless (file-directory? dir) (mkdir dir)))
            '("out" "out/lib"))
  (call-with-output-file (out "ss")
    (lambda (p)
      (write `(import (chezscheme) ,library) p)
      (newline p)
      (write `(,main (command-line-arguments)) p)
      (newline p))
    'replace)
  (compile-program (out "ss") (out "program.so"))
  ;; The libraries stay visible to (environment ...), which a REPL's
  ;; environment is made with.
  (let ([missing (compile-whole-program (out "program.wpo") (out "so") #t)])
    (unless (null? missing)
      (printf "not in ~a, and loaded as it runs: ~s~n" (out "so") missing))))
