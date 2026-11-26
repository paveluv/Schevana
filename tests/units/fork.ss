;;; tests/units/fork.ss — the world on a thread of its own and core0 on the
;;; process's first thread, as with a window, but headless (--fork): a run
;;; of ./desktop in a process of its own, with HOME set to a scratch folder,
;;; which reports what it saw (tests/fork/run.ss).

;; Runs ./desktop forked on a screen of size (a string, "400x300"), with
;; HOME the scratch folder named, evaluating first (a string) before it
;; loads script, a file in tests/fork/. Returns (status . seen): how the
;; process ended, and what the run saw, or #f.
(define (fork-run name first script size)
  (let ([home (string-append out-dir "/" name "-home")]
        [out (string-append out-dir "/" name "-seen.ss")]
        [run (string-append *schevana-root* "/tests/fork/" script)])
    (unless (file-directory? home) (mkdir home))
    (when (file-exists? out) (delete-file out))
    (let ([status
           (test-system-within 120
             (string-append
               (test-chez (list (cons "HOME" home))
                          (string-append *schevana-root* "/desktop")
                          "--headless" "--fork" "--size" size
                          "--eval" (format "(define *fork-out* ~s)" out)
                          "--eval" first
                          "--eval" (format "(load ~s)" run))
               " > /dev/null"))])
      (cons status
            (and (file-exists? out) (call-with-input-file out read))))))

(let* ([ran (fork-run "fork" "(void)" "run.ss" "400x300")]
       [status (car ran)]
       [seen (cdr ran)])
  (define (saw key) (and (pair? seen) (cdr (assq key seen))))
  (check (format "a forked world loads on its own thread, draws frames \
                  core0 presents, and quits, ending the process ~s" seen)
         (and (eqv? status 0) (saw 'forked) (saw 'core1) (saw 'frames)))
  (check (format "on a forked world, readbacks that would hold core1 raise \
                  outside a process; one by a then hands the screen's bytes \
                  back, and a buffer's, after the compute run asked before \
                  it (~s); in a process, gpu-compute! and gpu-buffer-read! \
                  wait for theirs (~s)"
                 (saw 'read-then) (saw 'waited))
         (and (saw 'readback) (saw 'compute) (> (saw 'bytes) 0)
              (equal? (saw 'read-then) '(0 1 4 9))
              (equal? (saw 'waited) '(0 1 4 9))))
  ;; judged by the frames' own t, which follows core0's screen. How many
  ;; refreshes a busy machine is late for is for the bench to measure.
  (check (format "frame turns follow core0's screen: a window that \
                  animates gets its frames, each one's t whole refreshes \
                  after the last (~a frames, ~a uneven; ~a refreshes by \
                  the machine's clock)"
                 (saw 'animated) (saw 'uneven) (saw 'refreshes))
         (and (saw 'animated) (> (saw 'animated) 30)
              (= (saw 'uneven) 0)))
  (check (format "a forked world's ticks add up: core1's waits, for input or \
                  for core0 to take its frame, are its own, so each tick's \
                  phases sum to its time (~a ticks, ~a not)"
                 (saw 'ticks) (saw 'unsummed))
         (and (saw 'ticks) (> (saw 'ticks) 30) (= (saw 'unsummed) 0))))

;; The same with the second pacer ((schevana core pacer2)), whose turn waits
;; for the last frame's GPU work: each frame's, done as core0 gives it back,
;; wakes the world, so frames don't wait out the pacer's gate, eight
;; refreshes each.
(let* ([ran (fork-run "fork-pacer2" "(override! 'pacer 2)" "run.ss"
                      "400x300")]
       [seen (cdr ran)])
  (define (saw key) (and (pair? seen) (cdr (assq key seen))))
  (check (format "with the second pacer, a forked world's frames come at \
                  core0's rate, far more often than one in eight refreshes, \
                  each one's t whole refreshes after the last (~a frames, ~a \
                  uneven; ~a refreshes by the machine's clock)"
                 (saw 'animated) (saw 'uneven) (saw 'refreshes))
         (and (eqv? (car ran) 0) (saw 'animated) (> (saw 'animated) 30)
              (= (saw 'uneven) 0)
              (< (saw 'refreshes) (* 4 (saw 'animated))))))

;; The desktop's apps in the launcher's own world, where "/" has only the
;; names that the core's facade and the world's libraries give: the suites'
;; build gives every name, so a part's body or a shader that the world
;; looks up by name and lacks shows only here (tests/fork/apps.ss).
(let* ([ran (fork-run "fork-apps" "(void)" "apps.ss" "1280x800")]
       [seen (cdr ran)])
  (define (saw key) (and (pair? seen) (cdr (assq key seen))))
  (check (format "in the launcher's own world, the Pipeline shows the \
                  shader of a record pressed on its small screen (~s), and \
                  Allocations shows Where (~s), a census on Heap (~s) and \
                  Hours (~s)"
                 (saw 'pipeline) (saw 'allocations) (saw 'heap) (saw 'hours))
         (and (eq? (saw 'pipeline) #t) (eq? (saw 'allocations) #t)
              (eq? (saw 'heap) #t) (eq? (saw 'hours) #t)))
  (check (format "in the launcher's own world, each of the desktop's apps \
                  opens and draws with no error (~s)"
                 (saw 'apps))
         (and (eqv? (car ran) 0) (saw 'frames) (pair? (saw 'apps))
              (for-all (lambda (app) (not (cdr app))) (saw 'apps)))))

;; The guards on that run: a run that hangs is killed once its time is up,
;; and a word reaches sh whole, whatever it holds.
(let ([began (real-time)])
  (check "a run still going after its time is killed, not waited for"
         (and (eqv? (test-system-within 1 "exec sleep 30") 137)
              (< (- (real-time) began) 5000))))
(let ([word "it's \"$HOME\" `x` \\ ~"]
      [file (string-append out-dir "/fork-word.txt")])
  (check "a word reaches sh whole, whatever it holds"
         (and (eqv? (system (format "printf %s ~a > ~a" (test-sh-word word)
                                    (test-sh-word file)))
                    0)
              (equal? (call-with-input-file file get-string-all) word))))
