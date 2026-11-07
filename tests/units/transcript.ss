;;; tests/units/transcript.ss — lines that only grow, as a REPL shows them.

(check "a transcript adds complete lines, carries pieces on the open line, \
        and a clear forgets them; a line takes the rows it wraps to"
       (let ([t (transcript-new)])
         (transcript-add! t 'result "one\ntwo")
         (transcript-append! t 'output "thr")
         (transcript-append! t 'output "ee\nfour")
         (transcript-add! t 'info "five")
         (let ([lines (reverse (transcript-lines t))])
           (and (equal? lines '((result . "one") (result . "two")
                                (output . "three") (output . "four")
                                (info . "five")))
                (= (transcript-rows 0 10) 1)
                (= (transcript-rows 10 10) 1)
                (= (transcript-rows 11 10) 2)
                (begin (transcript-clear! t)
                       (null? (transcript-lines t)))))))

(check "a request shows as Scheme after a prompt in accent, an input after a \
        faint one; the others in a color each"
       (let ([request (transcript-draw-entry-colors '(request . "λ> (car x)"))]
             [input (transcript-draw-entry-colors '(input . "λ> (car x)"))])
         (and (eq? (vector-ref request 0) 'accent)
              (eq? (vector-ref input 0) 'text-faint)
              (eq? (vector-ref request 4) 'accent)
              (eq? (transcript-draw-entry-colors '(error . "no")) 'red)
              (eq? (transcript-draw-entry-colors '(result . "1")) 'teal))))
