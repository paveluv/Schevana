;;; tests/units/text.ss — long text: cut, colored and searched in time at any
;;; length.

;;; long text: cut, colored and searched in time at any length

;; text-fit as plainly as it can be said: a character shorter at a time. An
;; empty string has nothing to cut, so it's never an ellipsis.
(define (fit-plainly str max-w font)
  (if (or (string=? str "") (<= (text-width str font) max-w))
      str
      (let loop ([n (- (string-length str) 1)])
        (let ([s (string-append (substring str 0 (max n 0)) "…")])
          (if (or (<= n 0) (<= (text-width s font) max-w)) s (loop (- n 1)))))))

(check "text-fit cuts where cutting a character at a time does: window, \
        task and made-up titles, other scripts, in five fonts and many \
        widths"
       (let ([strings
              (append
               (list "" "a" "…" "REPL" "REPL — running · Ctrl+C to interrupt"
                     "Life" "Sketch" "Settings" "Tasks" "Clock" "Monitor"
                     "Überschrift: Größenänderung — ½ × 東京 λ"
                     "Ελληνικά και Русский текст с ударени́ем"
                     "emoji 😀 and a tab\tand spaces    end"
                     (make-string 40 #\λ) (make-string 60 #\i)
                     (make-string 26 #\W))
               (begin (tasks-reset!) (map task-title *tasks*))
               (let ([abc "aW i.λ東Ü\x301;😀-"])   ; made up, the same each run
                 (map (lambda (i)
                        (list->string
                         (map (lambda (j)
                                (string-ref abc (mod (* (+ i 3) (+ j 7) 37)
                                                     (string-length abc))))
                              (iota (mod (* i 17) 90)))))
                      (iota 30))))])
         (for-all (lambda (font)
                    (for-all (lambda (w)
                               (for-all (lambda (s)
                                          (equal? (text-fit s w font)
                                                  (fit-plainly s w font)))
                                        strings))
                             '(-1 0 6 13 25 40 64 100 150 220 320)))
                  '(ui title ui-small mono-small heading))))

(check "text-fit measures log n times: 100,000 characters in at most 18"
       (let* ([n 0] [orig text-width]
              [s (dynamic-wind
                   (lambda ()
                     (set! text-width
                           (lambda args (set! n (+ n 1)) (apply orig args))))
                   (lambda () (text-fit (make-string 100000 #\W) 300 'ui))
                   (lambda () (set! text-width orig)))]
              [k (- (string-length s) 1)])
         (and (<= 1 n 18)
              (<= (text-width s 'ui) 300)
              (> (text-width (string-append (make-string (+ k 1) #\W) "…")
                             'ui)
                 300))))

(check "text-fit looks at no more characters than its width could show: as \
        many measured to fit 100,000 characters into 300 pixels as to fit \
        2,000, with words or without"
       (for-all (lambda (make)
                  (= (characters-measured
                      (lambda () (text-fit (make 2000) 300 'ui)))
                     (characters-measured
                      (lambda () (text-fit (make 100000) 300 'ui)))))
                (list words-of (lambda (n) (make-string n #\W)))))

(check "text-within: a string cut to one character more than its width in \
        pixels, the string itself when it is no longer"
       (let ([s "a short one"])
         (and (equal? (text-within (make-string 500 #\i) 40.7)
                      (make-string 41 #\i))
              (eq? (text-within s 40) s) (eq? (text-within s 10) s)
              (equal? (text-within s 3) "a sh")
              (equal? (text-within s -5) "a"))))

(check "Reticle's spaced title: cut with … to its room, and an empty one \
        stays empty however little room is left"
       (and (equal? (reticle-label "Tasks" 1000) "TASKS")
            (string-suffix? "…" (reticle-label (make-string 40 #\m) 100))
            (for-all (lambda (room) (equal? (reticle-label "" room) ""))
                     '(-40 -3 -1 0 50))))

(check "app-color: the color the whole hash gives, and a name of 100,000 \
        characters within a handler's fuel"
       (and (for-all
             (lambda (name)
               (eq? (app-color name)
                    (list-ref (theme 'app-colors)
                              (mod (fold-left (lambda (h c)
                                                (+ (* h 31) (char->integer c)))
                                              7
                                              (string->list
                                               (symbol->string name)))
                                   (length (theme 'app-colors))))))
             '(repl life settings tasks clock |Pavel Uvarov| perf λ ||))
            (let ([long (string->symbol (make-string 100000 #\a))])
              (within-fuel? (lambda () (app-color long))))))

(check "string-contains-ci?: case ignored, the empty string found, and a \
        word missing from 100,000 characters looked for within a handler's \
        fuel"
       (and (string-contains-ci? "Hello World" "O w")
            (string-contains-ci? "ΛΑΜΒΔΑ λ" "λαμ")
            (string-contains-ci? "abc" "") (string-contains-ci? "" "")
            (not (string-contains-ci? "abc" "abcd"))
            (not (string-contains-ci? "" "a"))
            (string-contains-ci? "xxabcab" "cab")
            (let ([s (apply string-append (make-list 12500 "abcdefg "))]
                  [w (make-string 1000 #\z)])
              (within-fuel? (lambda () (string-contains-ci? s w))))))
