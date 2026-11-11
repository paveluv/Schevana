;;; tests/units/platform.ss — what the host is (src/base.ss, src/platform.ss,
;;; src/host/platform.ss), as predicates, facts, Monitor's Platform tab and
;;; a row for docs/PLATFORMS.md; the screen's times read on the clock that
;;; fits them; and the trace (src/host/trace.ss). Whatever the platform:
;;; each check holds on any of them.

(define (platform-test-one-of preds)
  (<= (length (filter (lambda (p) (p)) preds)) 1))

(check "the OS and the CPU are one each, and their predicates agree"
       (and (memq (host-os) '(linux macos windows other))
            (memq (host-cpu) '(x86-64 arm64 other))
            (platform-test-one-of (list host-linux? host-mac? host-windows?))
            (platform-test-one-of (list host-x86-64? host-arm64?))
            (eq? (host-linux?) (eq? (host-os) 'linux))
            (eq? (host-mac?) (eq? (host-os) 'macos))
            (eq? (host-arm64?) (eq? (host-cpu) 'arm64))))

(check "core0 says the windowing system and the GPU's API, one each, as the \
        predicates do"
       (and (symbol? (host-windowing))
            (not (eq? (host-windowing) 'none))
            (= 1 (length (filter (lambda (p) (p))
                                 (list host-wayland? host-x11? host-cocoa?
                                       host-win32? host-offscreen?))))
            (memq (host-gpu-api) '(vulkan metal direct3d12))
            (= 1 (length (filter (lambda (p) (p))
                                 (list host-vulkan? host-metal?
                                       host-direct3d12?))))))

(check "SDL's version reads as 3.x.y, from 3.2 on"
       (let ([v (map string->number
                     (string-split (host-platform-fact 'sdl) #\.))])
         (and (= 3 (length v)) (= 3 (car v)) (>= (cadr v) 2))))

(check "the process's memory and the machine's load, where the system says \
        them"
       (let ([b (host-process-bytes)] [load (host-machine-load)])
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
                      (map car (filter cdr (host-predicates))))
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
                       [host-platform-read! void])
             (let ([shown (wayland-shown-ns frame raw)])
               (and (<= (- sent 1000000) shown (+ sent 1000000000))
                    (< (abs (- shown (now-ns))) 2000000)
                    (memv *wayland-used* '(1 4))))))))

(check "the trace keeps each thread's steps and writes them, by time, with \
        the screen's frames, to a file of its own"
       (let ([dir (string-append out-dir "/traces")])
         (fluid-let ([*host-trace-dir* dir])
           (host-trace! 22 0)
           (host-trace! 24 7)
           (let* ([path (host-trace-write!)]
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

(check "with no .work folder, or no window, nothing is traced"
       (fluid-let ([*host-trace-dir* #f])
         (let ([n (unbox (vector-ref *host-trace-rings* 1))])
           (host-trace! 22 0)
           (and (= n (unbox (vector-ref *host-trace-rings* 1)))
                (not (host-trace-write!))))))

;; CLOCK_MONOTONIC is 1 on Linux alone: elsewhere there's no Wayland.
(check "an input's ms on the compositor's clock reads as its time on \
        now-ns's, to the ms, across the clock's 32-bit wrap; one a second \
        ahead fits no clock"
       (or (not (host-linux?))
           (let* ([at (now-ns)]
                  [ms (quotient (- at (platform-clock-offset 1) 5000000)
                                1000000)])
             (fluid-let ([*wayland-input-clock* #f]
                         [*host-input-wl* (box 0)])
               (wayland-input! (modulo ms 4294967296))
               (let ([t (unbox *host-input-wl*)])
                 (and (<= (- at 7000000) t (- at 4000000))
                      (eqv? *wayland-input-clock* 1)
                      (not (wayland-input-on 1 (modulo (+ ms 2000) 4294967296)
                                             at))))))))
