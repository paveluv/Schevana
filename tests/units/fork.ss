;;; tests/units/fork.ss — the world on a thread of its own, core0 on the
;;; process's first, as with a window, but headless (--fork): a run of
;;; main.ss in a process of its own, HOME a scratch folder, which reports
;;; what it saw (tests/fork/run.ss).

(let* ([home (string-append out-dir "/fork-home")]
       [out (string-append out-dir "/fork-seen.ss")]
       [status
        (begin
          (unless (file-directory? home) (mkdir home))
          (when (file-exists? out) (delete-file out))
          (system
           (format "HOME=\"~a\" timeout 120 $(command -v chez || echo scheme) \
                    --script \"~a/main.ss\" --headless --fork --size 400x300 \
                    --eval '(define *fork-out* \"~a\")' \
                    --eval '(load \"~a/tests/fork/run.ss\")' > /dev/null"
                   home *schevana-root* out *schevana-root*)))]
       [seen (and (file-exists? out) (call-with-input-file out read))])
  (define (saw key) (and (pair? seen) (cdr (assq key seen))))
  (check (format "a forked world loads on its own thread, draws frames \
                  core0 presents, and quits, ending the process ~s" seen)
         (and (eqv? status 0) (saw 'forked) (saw 'main) (saw 'frames)))
  (check "on a forked world, readbacks that would hold main raise; one by a \
          then hands the screen's bytes back"
         (and (saw 'readback) (saw 'compute) (> (saw 'bytes) 0)))
  (check (format "frame turns follow core0's screen: a window that \
                  animates gets a frame a refresh, each one's t a period \
                  after the last (~a frames in ~a refreshes, ~a uneven)"
                 (saw 'animated) (saw 'refreshes) (saw 'uneven))
         (and (saw 'animated)
              (<= (abs (- (saw 'animated) 1 (saw 'refreshes))) 3)
              (= (saw 'uneven) 0)))
  (check (format "a forked world's ticks add up: main's waits, for input or \
                  for core0 to take its frame, are its own, so each tick's \
                  phases sum to its time (~a ticks, ~a not)"
                 (saw 'ticks) (saw 'unsummed))
         (and (saw 'ticks) (> (saw 'ticks) 30) (= (saw 'unsummed) 0))))
