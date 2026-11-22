;;; src/build.ss — compiles a program on the stack, and the libraries it
;;; imports, into out/lib: the libraries each to its own file, and the
;;; program with them all as one.
;;;
;;;   scheme --script src/build.ss schevana-demo/game.ss
;;;   scheme --program out/lib/game.so
;;;
;;; From the tree's root. A program runs from source too, compiled as it
;;; loads: scheme --libdirs . --program schevana-demo/game.ss

(let* ([program (car (command-line-arguments))]
       [name (path-root (path-last program))]
       [out (lambda (extension) (format "out/lib/~a.~a" name extension))])
  (library-directories '(("." . "out/lib")))
  (compile-imported-libraries #t)
  (generate-wpo-files #t)
  (for-each (lambda (dir) (unless (file-directory? dir) (mkdir dir)))
            '("out" "out/lib"))
  (compile-program program (out "program.so"))
  ;; The libraries stay visible to (environment ...), which a REPL's
  ;; environment is made with.
  (let ([missing (compile-whole-program (out "program.wpo") (out "so") #t)])
    (unless (null? missing)
      (printf "not in ~a, and loaded as it runs: ~s~n" (out "so") missing))))
