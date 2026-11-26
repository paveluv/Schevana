;;; tests/fork/apps.ss — what tests/units/fork.ss has a forked world do
;;; with the desktop's apps. The suites' build gives every name of the
;;; tree's libraries to "/", which hides a name that the launcher's own
;;; world lacks: there "/" has only what the core's facade and the world's
;;; libraries give. So here, in that world, the Pipeline shows a selected
;;; record's shader, Allocations shows its Where, a census on Heap, its
;;; Hours, a Probe and the lines of a library it counts, and then each app
;;; opens and draws. It writes what it saw, as a datum, to the file that
;;; *fork-out* names, then quits.

(define fork-seen '())
(define (fork-saw! key value)
  (set! fork-seen (cons (cons key value) fork-seen)))

;; Calls then once pred is true, looking each 100 ms; or with #f once
;; limit ms have passed, however busy the machine is.
(define (fork-when pred limit then)
  (let look ([left limit])
    (cond [(pred) (then #t)]
          [(<= left 0) (then #f)]
          [else (after 100 (lambda () (look (- left 100))))])))

;; Returns the region named id in win's ui, or #f.
(define (fork-region win id)
  (let ([ui (window-ref win 'ui)])
    (and ui (ui-find ui id))))

;; Returns win's error as text, its handler and the message, or #f.
(define (fork-error win)
  (let ([e (window-error win)])
    (and e (format "~a: ~a" (car e) (condition->string (cdr e))))))

;; Presses the middle of the region named id in win, as a person would:
;; win is the only window open, so nothing covers it.
(define (fork-press! win id)
  (let ([r (fork-region win id)])
    (let-values ([(cx cy cw ch) (content-rect win)])
      (let ([x (exact (floor (+ cx (ui-region-x r)
                                (/ (caddr (ui-region-frame r)) 2))))]
            [y (exact (floor (+ cy (ui-region-y r)
                                (/ (cadddr (ui-region-frame r)) 2))))])
        (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                 `(mouse-up ,x ,y left))))))

;; Opens the app named name, presses the regions named in presses one
;; after another, each once it is there, and waits for the region named
;; shown. Records under key the window's error, or else whether shown
;; came, closes the window and goes on with next.
(define (fork-app-press name presses shown key next)
  (let ([win (app-launch! name)])
    (let press ([ids presses])
      (if (null? ids)
          (fork-when (lambda () (or (window-error win) (fork-region win shown)))
                     30000
                     (lambda (came?)
                       (fork-saw! key (or (fork-error win) came?))
                       (close-window! win)
                       (next)))
          (fork-when (lambda () (or (window-error win)
                                    (fork-region win (car ids))))
                     30000
                     (lambda (came?)
                       (if (and came? (not (window-error win)))
                           (begin
                             (fork-press! win (car ids))
                             (after 300 (lambda () (press (cdr ids)))))
                           (press '()))))))))

;; Opens every app, waits for 10 frames, and records each one's error, or
;; what its launch raised, or #f.
(define (fork-every-app next)
  (let* ([wins (map (lambda (name)
                      (cons name
                            (guard (c [#t (condition->string c)])
                              (app-launch! name))))
                    (apps))]
         [from *frames-drawn*])
    (fork-when (lambda () (>= *frames-drawn* (+ from 10)))
               30000
               (lambda (came?)
                 (fork-saw! 'apps
                            (map (lambda (w)
                                   (cons (car w)
                                         (let ([win (cdr w)])
                                           (cond [(string? win) win]
                                                 [(memq win *windows*)
                                                  (fork-error win)]
                                                 [else #f]))))
                                 wins))
                 (fork-saw! 'frames came?)
                 (next)))))

(define (fork-done!)
  (call-with-output-file *fork-out*
    (lambda (p) (write (reverse fork-seen) p))
    'replace)
  (quit!))

;; A press on the small screen selects the record at its pixel; Inside
;; shows it, and its shader's source.
(fork-app-press 'pipeline '((pipeline viewer) (pipeline inside))
                '(pipeline source-view) 'pipeline
  (lambda ()
    (fork-app-press 'allocations '((tab where)) '(places header own)
                    'allocations
      (lambda ()
        ;; a census, whose owners are found by their symbols' names
        (fork-app-press 'allocations '((tab heap) census)
                        '((heap owner) box ("code and names")) 'heap
          (lambda ()
            (fork-app-press 'allocations '((tab hours)) '(hours row 0)
                            'hours
              (lambda ()
                ;; the Probe of the first window, Allocations' own draw,
                ;; from its own press, and the check it writes
                (fork-app-press 'allocations
                                '((tab probe) (probe-targets row 0) probe)
                                'check 'probe
                  (lambda ()
                    ;; the taskbar's lines counted, a reload in this world,
                    ;; and shown in Lines, where a counted library is first
                    (allocation-count-library! '(schevana desktop taskbar)
                                               #t)
                    (fork-when
                     (lambda ()
                       (member '(schevana desktop taskbar)
                               (allocation-counted-libraries)))
                     30000
                     (lambda (counted?)
                       (fork-app-press 'allocations
                                       '((tab lines) (libraries row 0))
                                       '(lines row 0) 'lines
                         (lambda () (fork-every-app fork-done!)))))))))))))))
