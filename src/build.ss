;;; src/build.ss — builds a library's main as a program of its own. The
;;; libraries it imports are compiled into out/lib, each to its own file,
;;; and the program is compiled with them all into one file, which runs
;;; without the tree.
;;;
;;;   scheme --script src/build.ss games fireflies fireflies-main
;;;   scheme --program out/lib/fireflies.so --headless
;;;
;;; Run it from the tree's root. The arguments are the parts of the
;;; library's name, then its main, which is handed the program's
;;; command-line arguments.

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
  ;; The libraries stay visible to (environment ...), with which a REPL's
  ;; environment is made.
  (let ([missing (compile-whole-program (out "program.wpo") (out "so") #t)])
    (unless (null? missing)
      (printf "not in ~a, and loaded as it runs: ~s~n" (out "so") missing))))
