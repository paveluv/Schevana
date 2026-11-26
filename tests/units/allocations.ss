;;; tests/units/allocations.ss — the Allocations app ((schevana apps
;;; allocations)): the heap as a picture, from the profiler's bytes and
;;; the allocation service's log.

(for-each close-window! (windows))
(steps 2)

;; A window whose draw allocates some 2 MB a frame, so that collections
;; come as it is drawn.
(define allocations-test-hog
  (open-window "Hog" 'size '(80 . 60) 'pos '(40 . 40)
               'draw (lambda (win w h)
                       (let loop ([i 0] [keep '()])
                         (when (< i 20000)
                           (loop (+ i 1)
                                 (cons (make-vector 8)
                                       (if (> (length keep) 10)
                                           '()
                                           keep))))))))

;; Draws the hog n times, a step each.
(define (allocations-test-run n)
  (do ([i 0 (+ i 1)]) ((= i n))
    (invalidate! allocations-test-hog)
    (steps 1)))

(define allocations-test-win (allocations))
(define allocations-test-ui (window-ref allocations-test-win 'ui))
(allocations-test-run 40)

;; Returns the rows that table id has laid out, by index.
(define (allocations-test-rows table)
  (let loop ([i 0] [acc '()])
    (if (ui-find allocations-test-ui (list table 'row i))
        (loop (+ i 1) (cons i acc))
        (reverse acc))))

;; Returns the tooltip of region id.
(define (allocations-test-tip id)
  (let ([tip (ui-region-tip (test-region allocations-test-ui id))])
    (if (procedure? tip) (tip) tip)))

(check "the app opens on Who, with the Column and the Flow, and starts \
        the tap"
       (and (allocation-recording?)
            (ui-find allocations-test-ui '(tab who))
            (ui-find allocations-test-ui '(tab collections))
            (ui-find allocations-test-ui '(who header rate))
            (ui-find allocations-test-ui '(flow))
            (pair? (allocations-test-rows 'who))))

(check "Who's first row is the window that allocates most; a press \
        chooses it, and its share goes over the Flow's bars"
       (let ([first (lambda () (allocations-test-tip '(who row 0)))])
         (printf "  ~a\n" (first))
         (and (string-contains-ci? (first) "Hog:")
              (string-contains-ci? (first) "MB")
              (not (string-contains-ci? (first) "Flow"))
              (begin
                (test-click! allocations-test-win '(who row 0))
                (string-contains-ci? (first) "Flow"))
              (begin
                (test-click! allocations-test-win '(who row 0))
                (not (string-contains-ci? (first) "Flow"))))))

(check "the young generation's level is what was allocated since the \
        last collection, and its limit the collector's trip, or none \
        while a request is held off"
       (let* ([keep #f]
              [level (lambda () (cdr (assq 'bytes (allocation-young))))]
              [limit (lambda () (cdr (assq 'limit (allocation-young))))])
         (allocation-record! #f)
         (collect-rendezvous)
         (let ([low (level)] [open (limit)])
           (set! keep (make-bytevector (* 512 1024) 1))
           (let ([high (level)])
             (allocation-record! #t)
             (and (< low (* 256 1024))
                  (>= (- high low) (* 512 1024))
                  (= open collector-trip)
                  ;; with the tap on, the limit is still the collector's
                  (= (limit) collector-trip)
                  (fluid-let ([*collector-holding?* #t]
                              [*collector-held?* #f]
                              [*collector-pass* #f])
                    (allocation-record! #f)
                    (collector-collect!)
                    (let ([held (limit)])
                      (set! *collector-holding?* #f)
                      (collector-collect!)
                      (allocation-record! #t)
                      (not held)))
                  (= 1 (bytevector-u8-ref keep 0)))))))

(check "the Flow places each collection on the tick it ended in: no more \
        ticks are marked than there were collections, each with its \
        pause, and one that a frame turn held off says so; a second look \
        places nothing twice"
       (let* ([marks (make-eqv-hashtable)]
              [newest (profile-newest-tick)]
              [next (allocations-place! marks 0 newest)])
         (let-values ([(ticks ms) (hashtable-entries marks)])
           (and (> (vector-length ticks) 10)
                (<= (vector-length ticks) next)
                (<= next (allocation-collection-count))
                (for-all (lambda (seq) (<= seq newest)) (vector->list ticks))
                (for-all (lambda (m) (> (car m) 0)) (vector->list ms))
                (exists (lambda (m) (> (cdr m) 0)) (vector->list ms))
                (= next (allocations-place! marks next newest))
                (= (vector-length ticks) (hashtable-size marks))))))

(test-click! allocations-test-win '(tab where))
(allocations-test-run 40)

(check "Where shows the tap's paths as a flame, under the span that was \
        open, and the procedures by what their samples come down to: the \
        hog's draw first, with its file and line"
       (let ([root (allocations-test-tip '(flame box ()))]
             [span (allocations-test-tip '(flame box ("Hog, draw")))]
             [first (allocations-test-tip '(places row 0))])
         (printf "  ~a\n  ~a\n  ~a\n" root span first)
         (and (string-contains-ci? root "all:")
              (string-contains-ci? span "Hog, draw:")
              (string-contains-ci? first "of the bytes sampled")
              (not (ui-find allocations-test-ui 'source)))))

(check "a press on a procedure's row shows its source, and a second press \
        puts it away"
       (begin
         (test-click! allocations-test-win '(places row 0))
         (allocations-test-run 1)
         (let ([shown (ui-find allocations-test-ui 'source)])
           (test-click! allocations-test-win '(places row 0))
           (allocations-test-run 1)
           (and shown (not (ui-find allocations-test-ui 'source))))))

(test-click! allocations-test-win '(tab collections))
(allocations-test-run 3)

;; Returns the seq that a row of Collections names in its tooltip.
(define (allocations-test-seq row)
  (let* ([tip (allocations-test-tip (list 'collections 'row row))]
         [end (let find ([i 0])
                (if (char=? (string-ref tip i) #\:) i (find (+ i 1))))])
    (string->number (substring tip 1 end))))

(check "Collections lists the log, the newest first, with what each kept"
       (let ([tip (allocations-test-tip '(collections row 0))])
         (printf "  ~a\n" tip)
         (and (> (length (allocations-test-rows 'collections)) 2)
              (ui-find allocations-test-ui '(collections header pass))
              (string-contains-ci? tip "kept of")
              (< (allocations-test-seq 0) (allocation-collection-count))
              (= (allocations-test-seq 1) (- (allocations-test-seq 0) 1))
              (= (allocations-test-seq 2) (- (allocations-test-seq 0) 2)))))

(check "a press on the Flow holds the app at that tick, and Resume lets \
        it go"
       (begin
         (test-click! allocations-test-win '(flow))
         (let ([held (allocations-test-tip 'hold)])
           (allocations-test-run 3)
           (and (string-contains-ci? held "Held at tick")
                (equal? held (allocations-test-tip 'hold))
                (begin
                  (test-click! allocations-test-win 'hold)
                  (not (string-contains-ci? (allocations-test-tip 'hold)
                                            "Held at tick")))))))

(test-click! allocations-test-win '(tab heap))
(allocations-test-run 1)

;; Returns the tooltip of row i of table, scrolled into view.
(define (allocations-test-row-tip table i)
  (test-show! allocations-test-win (list table 'body) (list table 'row i))
  (allocations-test-tip (list table 'row i)))

;; Returns the index of the first of rows that pred holds of.
(define (allocations-test-index pred rows)
  (let loop ([rows rows] [i 0])
    (cond [(null? rows) #f]
          [(pred (car rows)) i]
          [else (loop (cdr rows) (+ i 1))])))

;; Returns the index of the first of the census's owners whose label
;; begins with text.
(define (allocations-test-owner text)
  (allocations-test-index
   (lambda (leaf)
     (let ([label (car (cdr leaf))])
       (and (>= (string-length label) (string-length text))
            (string=? (substring label 0 (string-length text)) text))))
   (allocations-owner-leaves (cdr (assq 'owners (allocation-census))))))

(check "Heap asks for a census first; Take a census shows the heap by \
        owner, as a treemap and as a table, the heaviest first"
       (let ([before (ui-find allocations-test-ui '((heap owner) box ()))])
         (test-click! allocations-test-win 'census)
         (allocations-test-run 1)
         (let* ([first (allocations-test-tip '(owners row 0))]
                [shown (length (allocations-test-rows 'owners))]
                ;; down the table, as test-show! scrolls; in the hacker
                ;; edition a state is a name at "/", which the code and
                ;; names take
                [hours (and (not test-hacker?)
                            (allocations-test-row-tip
                             'owners
                             (allocations-test-owner "*allocation-hours*")))]
                [hog (allocations-test-row-tip
                      'owners (allocations-test-owner "Hog ("))])
           (printf "  ~a\n  ~a\n  ~a\n" first hog hours)
           (and (not before)
                (ui-find allocations-test-ui '((heap owner) box ()))
                (ui-find allocations-test-ui
                         '((heap owner) box ("code and names")))
                (> shown 3)
                (string-contains-ci? hog "Hog (")
                (or test-hacker?
                    (string-contains-ci? hours "*allocation-hours*"))))))

(define allocations-test-keep #f)

(check "By kind shows the census's kinds and their counts; after Mark, \
        the next census tells what grew since"
       (begin
         (test-click! allocations-test-win '(by kind))
         (allocations-test-run 1)
         (let* ([kind (lambda (name)
                        (allocations-test-index
                         (lambda (k) (eq? (car k) name))
                         (cdr (assq 'kinds (allocation-census)))))]
                [pairs (allocations-test-row-tip 'kinds (kind 'pair))])
           (test-click! allocations-test-win 'mark)
           (set! allocations-test-keep (make-bytevector (* 3 1024 1024) 1))
           (test-click! allocations-test-win 'census)
           (allocations-test-run 1)
           (let ([grew (allocations-test-row-tip 'kinds
                                                 (kind 'bytevector))])
             (printf "  ~a\n  ~a\n" pairs grew)
             (and pairs (string-contains-ci? pairs "objects")
                  (ui-find allocations-test-ui '((heap kind) box ("pair")))
                  grew (string-contains-ci? grew "since the mark"))))))

(check "Hours lists each generation, what Chez and the process hold, the \
        GPU's bytes and the longest pause, each with its line"
       (begin
         (test-click! allocations-test-win '(tab hours))
         (allocation-hours-row!)
         (allocation-hours-row!)
         (allocations-test-run 1)
         (let ([rows (allocations-test-rows 'hours)])
           (printf "  ~a\n" (allocations-test-tip '(hours row 4)))
           (and (= (length rows) 9)
                (string-contains-ci? (allocations-test-tip '(hours row 4))
                                     "generation 4:")))))

(check "a check's budget is a quarter more than the least probed, rounded \
        up to two figures, and nothing stays nothing"
       (and (= (allocations-budget 29664) 38000)
            (= (allocations-budget 53360) 67000)
            (= (allocations-budget 7) 9)
            (= (allocations-budget 0) 0)
            (string=? (allocations-figure 38000) "38,000")
            (string=? (allocations-figure 1234567) "1,234,567")
            (string=? (allocations-figure 512) "512")))

;; Returns whether the check that the Probe writes for what, after a
;; probe of it, holds when it runs: it reads as (check text expression).
(define (allocations-test-check-holds? what)
  (let* ([least (cdr (assq 'least (allocation-probe-draw what 5)))]
         [form (read (open-string-input-port
                      (allocations-check-text what least)))])
    (printf "  ~s\n" form)
    (and (eq? (car form) 'check)
         (string? (cadr form))
         (eval (caddr form)))))

(check "the Probe runs a window's draw 20 times and keeps the least it \
        allocates, against the probe before"
       (let ([row (allocations-test-index
                   (lambda (what) (eq? what allocations-test-hog))
                   (append *windows* (surfaces)))])
         (test-click! allocations-test-win '(tab probe))
         (allocations-test-run 1)
         (test-click! allocations-test-win (list 'probe-targets 'row row))
         (let ([before (allocations-test-tip (list 'probe-targets 'row row))])
           (test-click! allocations-test-win 'probe)
           (allocations-test-run 1)
           (let ([after (allocations-test-tip
                         (list 'probe-targets 'row row))])
             (printf "  ~a\n  ~a\n" before after)
             (and (string-contains-ci? before "choose it")
                  (string-contains-ci? after "Hog's draw:")
                  (string-contains-ci? after "MB at least")
                  (ui-find allocations-test-ui 'check)
                  (not (window-error allocations-test-win)))))))

(check "the check the Probe writes holds when it runs: for a surface, for \
        an app's window, which it opens and closes, and for a window it \
        finds by its title"
       (let ([clock (app-launch! 'clock)])
         (steps 2)
         (let ([ok? (and (allocations-test-check-holds? 'taskbar)
                         (allocations-test-check-holds? clock)
                         (allocations-test-check-holds? allocations-test-hog))])
           (close-window! clock)
           (steps 1)
           ok?)))

(unless test-hacker?
  (let ([taskbar '(schevana desktop taskbar)])
    (check "Lines counts the lines of the library chosen: it comes first, \
            with its lines, the most run first, and the source around the \
            one chosen; Stop counting evaluates it plain again"
           (let ([row (allocations-test-index
                       (lambda (l) (equal? (car l) taskbar))
                       (allocation-libraries))])
             (test-click! allocations-test-win '(tab lines))
             (allocations-test-run 1)
             (test-show! allocations-test-win '(libraries body)
                         (list 'libraries 'row row))
             (test-click! allocations-test-win (list 'libraries 'row row))
             (test-click! allocations-test-win 'count)
             (and (test-wait 20000
                             (lambda ()
                               (member taskbar
                                       (allocation-counted-libraries))))
                  (test-wait 5000
                             (lambda ()
                               (allocations-test-run 1)
                               (ui-find allocations-test-ui '(lines row 0))))
                  ;; the table was scrolled down to the library's row,
                  ;; which is the first now
                  (let ([first (let up ([n 0])
                                 (if (or (= n 40)
                                         (ui-find allocations-test-ui
                                                  '(libraries row 0)))
                                     (allocations-test-tip
                                      '(libraries row 0))
                                     (let-values ([(x y)
                                                   (test-point
                                                    allocations-test-win
                                                    '(libraries body))])
                                       (inject! `(mouse-move ,x ,y)
                                                '(wheel 0 1))
                                       (steps 1)
                                       (up (+ n 1)))))]
                        [line (allocations-test-tip '(lines row 0))])
                    (printf "  ~a\n  ~a\n" first line)
                    (test-click! allocations-test-win '(lines row 0))
                    (allocations-test-run 1)
                    (and (string-contains-ci? first "lines are counted")
                         (string-contains-ci? line "runs in")
                         (ui-find allocations-test-ui 'lines-source)
                         (begin
                           (test-click! allocations-test-win 'count)
                           (test-wait 20000
                                      (lambda ()
                                        (not (member
                                              taskbar
                                              (allocation-counted-libraries)))
                                        ))))))))))

(check "the app draws in one-bit styles and in color ones"
       (let ([errors 0] [report report-error!])
         (fluid-let ([report-error! (lambda args
                                      (set! errors (+ errors 1))
                                      (apply report args))])
           (for-each (lambda (style)
                       (set-style! style)
                       (for-each (lambda (tab)
                                   (test-click! allocations-test-win
                                                (list 'tab tab))
                                   (allocations-test-run 2))
                                 '(who collections heap hours probe lines)))
                     '(genera cadr interlisp mac cons)))
         (and (= errors 0) (not (window-error allocations-test-win)))))

(check "closing the window stops the tap it started"
       (begin
         (close-window! allocations-test-win)
         (steps 1)
         (not (allocation-recording?))))
