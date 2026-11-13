;;; tests/units/fork.ss — the world on a thread of its own, core0 on the
;;; process's first, as with a window, but headless (--fork): a run of
;;; main.ss in a process of its own, HOME a scratch folder, which reports
;;; what it saw (tests/fork/run.ss).

(let* ([home (string-append out-dir "/fork-home")]
       [out (string-append out-dir "/fork-seen.ss")]
       [run (string-append *schevana-root* "/tests/fork/run.ss")]
       [status
        (begin
          (unless (file-directory? home) (mkdir home))
          (when (file-exists? out) (delete-file out))
          (units-system-within 120
            (string-append
              (units-chez (list (cons "HOME" home))
                          (string-append *schevana-root* "/main.ss")
                          "--headless" "--fork" "--size" "400x300"
                          "--eval" (format "(define *fork-out* ~s)" out)
                          "--eval" (format "(load ~s)" run))
              " > /dev/null")))]
       [seen (and (file-exists? out) (call-with-input-file out read))])
  (define (saw key) (and (pair? seen) (cdr (assq key seen))))
  (check (format "a forked world loads on its own thread, draws frames \
                  core0 presents, and quits, ending the process ~s" seen)
         (and (eqv? status 0) (saw 'forked) (saw 'core1) (saw 'frames)))
  (check "on a forked world, readbacks that would hold core1 raise; one by a \
          then hands the screen's bytes back"
         (and (saw 'readback) (saw 'compute) (> (saw 'bytes) 0)))
  (check (format "frame turns follow core0's screen: a window that \
                  animates gets a frame a refresh, each one's t a period \
                  after the last (~a frames in ~a refreshes, ~a uneven)"
                 (saw 'animated) (saw 'refreshes) (saw 'uneven))
         (and (saw 'animated)
              (<= (abs (- (saw 'animated) 1 (saw 'refreshes))) 3)
              (= (saw 'uneven) 0)))
  (check (format "a forked world's ticks add up: core1's waits, for input or \
                  for core0 to take its frame, are its own, so each tick's \
                  phases sum to its time (~a ticks, ~a not)"
                 (saw 'ticks) (saw 'unsummed))
         (and (saw 'ticks) (> (saw 'ticks) 30) (= (saw 'unsummed) 0))))

;; The guard on that run: a run that hangs is killed in its time, and what
;; a word holds reaches sh whole.
(let ([began (real-time)])
  (check "a run still going after its time is killed, not waited for"
         (and (eqv? (units-system-within 1 "exec sleep 30") 137)
              (< (- (real-time) began) 5000))))
(let ([word "it's \"$HOME\" `x` \\ ~"]
      [file (string-append out-dir "/fork-word.txt")])
  (check "a word reaches sh whole, whatever it holds"
         (and (eqv? (system (format "printf %s ~a > ~a" (units-sh-word word)
                                    (units-sh-word file)))
                    0)
              (equal? (call-with-input-file file get-string-all) word))))
