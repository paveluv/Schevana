;;; tests/units/platform.ss — which platform this is (src/base.ss,
;;; src/platform.ss, src/core0/platform.ss), as predicates, facts,
;;; Monitor's Platform tab and a row for docs/PLATFORMS.md; the screen's
;;; times read on the clock that fits them; and the trace
;;; (src/core0/trace.ss). Whatever the platform: each check holds on any
;;; of them.

(define (platform-test-one-of preds)
  (<= (length (filter (lambda (p) (p)) preds)) 1))

(check "the OS and the CPU are one each, and their predicates agree"
       (and (memq (platform-os) '(linux macos windows other))
            (memq (platform-cpu) '(x86-64 arm64 other))
            (platform-test-one-of (list platform-linux? platform-mac?
                                        platform-windows?))
            (platform-test-one-of (list platform-x86-64? platform-arm64?))
            (eq? (platform-linux?) (eq? (platform-os) 'linux))
            (eq? (platform-mac?) (eq? (platform-os) 'macos))
            (eq? (platform-arm64?) (eq? (platform-cpu) 'arm64))))

(check "core0 says the windowing system and the GPU's API, one each, as the \
        predicates do"
       (and (symbol? (platform-windowing))
            (not (eq? (platform-windowing) 'none))
            (= 1 (length (filter (lambda (p) (p))
                                 (list platform-wayland? platform-x11?
                                       platform-cocoa? platform-win32?
                                       platform-offscreen?))))
            (memq (platform-gpu-api) '(vulkan metal direct3d12))
            (= 1 (length (filter (lambda (p) (p))
                                 (list platform-vulkan? platform-metal?
                                       platform-direct3d12?))))))

(check "SDL's version reads as 3.x.y, from 3.2 on"
       (let ([v (map string->number
                     (string-split (platform-fact 'sdl) #\.))])
         (and (= 3 (length v)) (= 3 (car v)) (>= (cadr v) 2))))

(check "the process's memory and the machine's load, where the system says \
        them"
       (let ([b (platform-process-bytes)] [load (platform-machine-load)])
         (and (or (not b) (> b (* 1/2 (bytes-allocated))))
              (or (not load)
                  (let ([ns (map string->number (string-split load #\space))])
                    (and (= 3 (length ns)) (for-all (lambda (n) (>= n 0))
                                                    ns)))))))

(check "inspect-platform holds every fact, the predicates that hold among \
        them; its row for docs/PLATFORMS.md has the Runs' ten cells"
       (let ([p (inspect-platform)] [row (inspect-platform-row)])
         (and (for-all (lambda (k) (assq k p))
                       '(os system kernel cpu threads chez chez-machine
                         windowing desktop display scale gpu-api gpu-device
                         renderer present-mode present-modes reports sdl
                         freetype fontconfig predicates commit))
              (equal? (cdr (assq 'predicates p))
                      (map car (filter cdr (platform-predicates))))
              (= 11 (length (filter (lambda (c) (char=? c #\|))
                                    (string->list row))))
              (string-prefix? "| " row))))

(check "Monitor's Platform tab draws every group and copies the row"
       (let* ([m (monitor)] [ui (window-ref m 'ui)])
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect m)])
           (let* ([r (ui-find ui '(tab platform))]
                  [x (exact (round (+ cx (ui-region-x r)
                                      (/ (ui-region-w r) 2))))]
                  [y (exact (round (+ cy (ui-region-y r)
                                      (/ (ui-region-h r) 2))))])
             (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))))
         (steps 2)
         (let ([copy (ui-find ui 'monitor-platform-copy)])
           (when copy
             (let-values ([(cx cy cw ch) (content-rect m)])
               (let ([x (exact (round (+ cx (ui-region-x copy) 4)))]
                     [y (exact (round (+ cy (ui-region-y copy) 4)))])
                 (inject! `(mouse-down ,x ,y left 1)
                          `(mouse-up ,x ,y left)))))
           (steps 2)
           (let ([crashed (window-error m)] [text (clipboard-get)])
             (close-window! m)
             (and copy (not crashed)
                  (string? text) (string-prefix? "| " text))))))

;; A report's time on CLOCK_MONOTONIC_RAW, from a compositor that says
;; CLOCK_MONOTONIC: it fits after its frame was sent, whichever clock that
;; takes. Both are Linux's and a Mac's numbers alike.
(check "a report's time is read on the first clock under which its frame \
        shows after it was sent"
       (let* ([frame 1000003] [at (present-at frame)]
              [sent (- (now-ns) 1000000)])
         (fxvector-set! *present-ring* at frame)
         (fxvector-set! *present-ring* (+ at 2) sent)
         (let ([raw (- (now-ns) (platform-clock-offset 4))])
           (fluid-let ([*wayland-clock* 1] [*wayland-used* 1]
                       [core0-platform-read! void])
             (let ([shown (wayland-shown-ns frame raw)])
               (and (<= (- sent 1000000) shown (+ sent 1000000000))
                    (< (abs (- shown (now-ns))) 2000000)
                    (memv *wayland-used* '(1 4))))))))

(check "the trace keeps each thread's steps and writes them, by time, with \
        the screen's frames, to a file of its own"
       (let ([dir (string-append out-dir "/traces")])
         (fluid-let ([*core0-trace-dir* dir])
           (core0-trace! 22 0)
           (core0-trace! 24 7)
           (let* ([path (core0-trace-write!)]
                  [lines (call-with-input-file path
                           (lambda (p)
                             (let loop ([acc '()])
                               (let ([l (get-line p)])
                                 (if (eof-object? l)
                                     (reverse acc)
                                     (loop (cons l acc)))))))])
             (and (string-prefix? (string-append dir "/trace-") path)
                  (exists (lambda (l) (string-suffix? "tick 0" l)) lines)
                  (exists (lambda (l) (string-suffix? "publish 7" l)) lines)
                  (exists (lambda (l) (string-prefix? "# frames" l))
                          lines))))))

(check "a trace says why it was written, if that's said, and a second's \
        second trace goes beside the first"
       (fluid-let ([*core0-trace-dir* (string-append out-dir "/traces")])
         (let* ([a (core0-trace-write!)] [b (core0-trace-write! "a check")]
                [line3 (lambda (path)
                         (call-with-input-file path
                           (lambda (p) (get-line p) (get-line p)
                                   (get-line p))))])
           (and (not (equal? a b))
                (string-prefix? "# steps" (line3 a))
                (equal? (line3 b) "# written as a check")))))

;; No collection while it looks: one stamps a step of core1's (gc).
(check "core1 stopped past the limit, core0 writes the trace once, saying \
        core1's last step; a step of core1's later, again"
       (let ([whys '()])
         (parameterize ([collect-request-handler void])
           (fluid-let ([*core0-trace-dir* (string-append out-dir "/traces")]
                       [*core0-trace-stalled* -1]
                       [core0-trace-stall-ns -1]
                       [core0-trace-write!
                        (lambda (why) (set! whys (cons why whys)))])
             (core0-trace! 22 0)
             (core0-trace-watch!)
             (core0-trace-watch!)
             (let ([once (length whys)])
               (core0-trace! 23 0)
               (core0-trace-watch!)
               (fluid-let ([core0-trace-stall-ns 5000000000])
                 (core0-trace! 24 0)
                 (core0-trace-watch!))
               (and (= once 1)
                    (= 2 (length whys))
                    (string-prefix? "core1 hasn't stepped for " (car whys))
                    (string-suffix? "since its tick" (cadr whys))
                    (string-suffix? "since its draw" (car whys))))))))

(check "Ctrl-C writes the trace, then ends the run as the handler before \
        did"
       (let ([whys '()] [ended #f])
         (parameterize ([keyboard-interrupt-handler
                         (lambda () (set! ended (pair? whys)))])
           (fluid-let ([*core0-trace-interrupt* #f]
                       [core0-trace-write!
                        (lambda (why) (set! whys (cons why whys)))])
             (core0-trace-on-interrupt!)
             ((keyboard-interrupt-handler))
             (and ended (equal? whys '("Ctrl-C ended the run")))))))

(check "with no .work folder, or no window, nothing is traced"
       (fluid-let ([*core0-trace-dir* #f])
         (let ([n (unbox (vector-ref *core0-trace-rings* 1))])
           (core0-trace! 22 0)
           (and (= n (unbox (vector-ref *core0-trace-rings* 1)))
                (not (core0-trace-write!))))))

;; CLOCK_MONOTONIC is 1 on Linux alone: elsewhere there's no Wayland.
(check "an input's ms on the compositor's clock reads as its time on \
        now-ns's, to the ms, across the clock's 32-bit wrap; one a second \
        ahead fits no clock"
       (or (not (platform-linux?))
           (let* ([at (now-ns)]
                  [ms (quotient (- at (platform-clock-offset 1) 5000000)
                                1000000)])
             (fluid-let ([*wayland-input-clock* #f]
                         [*core0-input-wl* (box 0)])
               (wayland-input! (modulo ms 4294967296))
               (let ([t (unbox *core0-input-wl*)])
                 (and (<= (- at 7000000) t (- at 4000000))
                      (eqv? *wayland-input-clock* 1)
                      (not (wayland-input-on 1 (modulo (+ ms 2000) 4294967296)
                                             at))))))))

;; A frame's row begun as core0 sends it, at t: none of the screen's word
;; yet.
(define (platform-test-sent! n t)
  (let ([at (present-at n)])
    (fxvector-set! *present-ring* at n)
    (fxvector-set! *present-ring* (+ at 1) 0)
    (fxvector-set! *present-ring* (+ at 2) t)))

;; CLOCK_UPTIME_RAW, Metal's clock, is 8 on a Mac alone.
(check "Metal's word on a drawable is its frame's report: shown on now-ns's \
        clock at the window's refresh, its sequence the refreshes since the \
        last shown; a time before the frame was sent says nothing; 0 is \
        dropped"
       (or (not (platform-mac?))
           (let* ([r (core0-frame-ns)] [f 1000021] [t (now-ns)]
                  [mach (lambda (ns) (- ns (platform-clock-offset 8)))])
             (fluid-let ([*mac-refresh* 0] [*mac-refresh-at* 0])
               (for-each (lambda (n) (platform-test-sent! n (- t (* 4 r))))
                         (list f (+ f 1) (+ f 2)))
               (platform-test-sent! (+ f 3) (- t 20000000))
               (mac-reported! f (mach (- t (* 3 r))))
               (mac-reported! (+ f 1) (mach (- t r)))
               (mac-reported! (+ f 2) 0)
               (mac-reported! (+ f 3) (mach (- t 40000000)))
               (and (eqv? (core0-frame-report f 1) 1)
                    (< (abs (- (core0-frame-report f 3) (- t (* 3 r)))) 100000)
                    (= (core0-frame-report f 4) r)
                    (= 2 (- (core0-frame-report (+ f 1) 5)
                            (core0-frame-report f 5)))
                    (eqv? (core0-frame-report (+ f 2) 1) 2)
                    (eqv? (core0-frame-report (+ f 3) 1) 0))))))

(check "core0 reads the presented handlers' ring for the frames it sent, \
        each by its drawable's number, once its row is in"
       (let ([f 1000025])
         (fluid-let ([*mac-drawable* 41]
                     [*mac-waiting* (make-fxvector (* 2 mac-waiting-rows) -1)]
                     [*mac-shown* (make-fxvector (* 2 mac-rows) 0)])
           (platform-test-sent! f (now-ns))
           (mac-ask! f)
           (mac-pump!)
           (let ([before (core0-frame-report f 1)])
             (fxvector-set! *mac-shown* (+ 1 (* 2 41)) 0)
             (fxvector-set! *mac-shown* (* 2 41) 42)
             (mac-pump!)
             (and (eqv? before 0) (= *mac-drawable* -1)
                  (eqv? (core0-frame-report f 1) 2)
                  (= -1 (fxvector-ref *mac-waiting*
                                      (* 2 (modulo f mac-waiting-rows)))))))))

;; QOS_CLASS_USER_INTERACTIVE and QOS_CLASS_DEFAULT
(check "on a Mac a thread forked, as core1, starts at the default class \
        and asks for core0's, the user-interactive one; elsewhere no class \
        is known"
       (let* ([out (box #f)]
              [t (fork-thread
                  (lambda ()
                    (let ([before (platform-thread-class)])
                      (platform-thread-interactive!)
                      (set-box! out (list before (platform-thread-class))))))])
         (thread-join t)
         (if (platform-mac?)
             (equal? (unbox out) '(#x15 #x21))
             (equal? (unbox out) '(#f #f)))))
