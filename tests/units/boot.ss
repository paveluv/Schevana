;;; tests/units/boot.ss — the boot's chain. A launcher starts core0, whose
;;; code is sealed in its libraries, and core1, the core, sealed in its own
;;; libraries, which imports what core0 and the recorder give it through
;;; their facades. Core1 makes "/", which imports what the core gives it
;;; through its facade, (schevana core). In the hacker edition every
;;; library is spliced into one environment, "/" itself, and nothing is
;;; sealed.

;; What the core is given: the facades, imported as the core's libraries
;; import them.
(unless test-hacker?
(let ([given (environment '(chezscheme) '(schevana core0)
                          '(schevana recorder))])
  (define (in-core form) (eval form given))
  (define (named? name) (guard (c [#t #f]) (in-core name) #t))
  (check "of core0's names the core has what its facade gives, each \
          core0's binding itself, and read-only, a state or a hook core0 \
          sets as a view"
         (and (eq? (in-core 'gpu-publish!) gpu-publish!)
              (eq? (in-core '*gpu-facts*) *gpu-facts*)
              (eq? (in-core 'core0-clock-ns) (eval 'core0-clock-ns main-env))
              (not (named? 'gpu-frame!))
              (not (named? '*sdl-window*))
              (not (named? 'sdl-get-ticks-ns))
              (raises? (lambda () (in-core '(set! gpu-publish! #f))))
              (raises? (lambda ()
                         (in-core '(fluid-let ([*core0-mode* 'sdl]) #t))))))
  (check "the recorder is sealed: the core holds what its facade gives, \
          read-only, and none of the bytes it hands core0, nor what writes \
          them"
         (and (procedure? (in-core 'rec-write!))
              (raises? (lambda () (in-core '(set! rec-write! #f))))
              (not (named? '*rec-now*))
              (not (named? 'rec-take!))
              (not (named? 'gpu-recording-recs))
              (not (named? 'gpu-list-recording-set!))
              (not (named? 'make-gpu-list))
              (not (named? 'gpu-frame-root-set!))
              (not (named? 'gpu-frame-earlier-set!))))))

;; A "/" made as core1 makes it, importing the core's facade; the tests'
;; own "/" has its names made settable (tests/reach.ss).
(unless test-hacker?
(let ([world (let ([w (copy-environment (scheme-environment) #t)])
               (eval '(import (schevana core)) w)
               w)])
  (define (in-world form) (eval form world))
  (define (named? name) (guard (c [#t #f]) (in-world name) #t))
  (check "the core gives \"/\" what its facade exports, each the core's \
          binding itself and read-only, core0's it gives again too; nothing \
          else of the core's, and none of its C"
         (and (eq? (in-world 'theme) (eval 'theme core-env))
              (eq? (in-world 'core0-frame-ns) core0-frame-ns)
              (eq? (in-world '*style-name*) (eval '*style-name* core-env))
              (raises? (lambda () (in-world '(set! theme #f))))
              (raises? (lambda ()
                         (in-world '(fluid-let ([*style-name* 'mac]) #t))))
              (not (memq 'compute-rule! (core1-exported)))
              (not (named? 'compute-rule!))
              (not (named? 'ft-init-freetype))
              (not (named? 'c-socket))
              (not (named? 'core0-clock-ns))
              (not (named? 'gpu-publish!))))
  (check "a hook is settable from \"/\", reaching the core's variable, \
          but only with what the core calls"
         ;; read with eval: the hook is a library's, a macro there
         (let ([real (eval 'window-gone! core-env)]
               [mine (lambda (win) 'gone)])
           (and (raises? (lambda () (in-world '(set! window-gone! 5))))
                (eq? (eval 'window-gone! core-env) real)
                (eq? (in-world `(fluid-let ([window-gone! ',mine])
                                  window-gone!))
                     mine)
                (eq? (eval 'window-gone! core-env) real))))))

;; In the hacker edition every library's names are here, internals
;; included, and a redefinition takes effect at the core's next call, as in
;; a world of top-level files. This is evaluated only there: the library
;; edition refuses the set! as it expands.
(when test-hacker?
  (check "in the hacker edition every library's internals are names of the \
          world's, and the core's own calls reach a redefinition"
         (eval '(and (for-all top-level-bound?
                              '(compute-rule! sdl-get-ticks-ns rec-take!
                                gpu-frame! *sdl-window* theme-busy
                                desktop-options))
                     (let ([real theme])
                       (dynamic-wind
                         (lambda ()
                           (set! theme
                             (lambda (key)
                               (if (eq? key 'units-hacker-part) cdr
                                   (real key)))))
                         (lambda ()
                           (eq? (theme-part 'units-hacker-part) cdr))
                         (lambda () (set! theme real))))))))

;; The desktop reads the command line before the world loads, each option
;; once, in its defaults' order; an option it doesn't know, or a path that
;; is no folder, prints the usage.
(let ([defaults (if test-hacker?
                    (map (lambda (d)
                           (if (eq? (car d) 'hacker) '(hacker . #t) d))
                         desktop-defaults)
                    desktop-defaults)])
  (fluid-let ([desktop-usage (lambda () 'usage)])
    (check "the desktop reads the command line once: what's asked over the \
            defaults, in their order, a word that is no option a path to \
            load, and the usage for an option it doesn't know"
           (and (equal? (desktop-options '()) defaults)
                (equal? (desktop-options '("--headless" "--size" "400x300"
                                           "--eval" "1" "--fork" "demos"
                                           "--eval" "2" "--hacker"
                                           "/tmp/more"))
                        '((mode . headless)
                          (size 400 . 300)
                          (full-screen? . #f)
                          (fork? . #t)
                          (desktop . #f)
                          (hacker . #t)
                          (evals "1" "2")
                          (auto-loads "demos" "/tmp/more")))
                (eq? (desktop-options '("--size" "400")) 'usage)
                ;; a folder to load, not a file
                (eq? (desktop-options (list (string-append *schevana-root*
                                                           "/README.md")))
                     'usage)
                (eq? (desktop-options '("--size")) 'usage)
                (eq? (desktop-options '("--frobnicate")) 'usage)
                (equal? *schevana-options* (desktop-options '("--headless")))))
    (check "a window, or --fork, boots on two threads; installing the \
            desktop entry on one"
           (and (desktop-fork? (desktop-options '()))
                (desktop-fork? (desktop-options '("--headless" "--fork")))
                (not (desktop-fork? (desktop-options '("--headless"))))
                (not (desktop-fork?
                      (desktop-options '("--install-desktop"))))))))

(check "the world runs in an environment of its own, made by core1; in the \
        hacker edition, the one every library was spliced into"
       (and (eq? *world-env* world-env)
            (if test-hacker?
                (eq? *world-env* main-env)
                (and (not (eq? *world-env* main-env))
                     (not (eq? *world-env* core-env))))))

;;; Core0's step: jobs posted (each a procedure and its arguments) run at
;;; its next step, in order; the events it pumps wait in the world's inbox
;;; until taken; and what it says about the window was read at that step.

(let* ([ran '()]
       [job! (lambda (x) (set! ran (cons x ran)))]
       [raising (list car '())])
  (fluid-let ([*core0-jobs* (box '())]
              [*core0-job-failed* #f])
    (core0-post! (list job! 1))
    (core0-post! (list job! 2))
    (let ([before ran])
      (core0-step!)
      (check "a job posted runs at core0's next step, not before, in order"
             (and (null? before) (equal? ran '(2 1)))))
    (core0-post! (list job! 3))
    (core0-post! raising)
    (core0-post! (list job! 4))
    (core0-step!)
    (check "a job that raises is kept, and the rest run"
           (and (equal? (list-head ran 2) '(4 3))
                (eq? (car *core0-job-failed*) raising)))))

(fluid-let ([*core0-inbox* (box '())])
  (core0-put! *core0-inbox* '(((key-down #\a ())) . (#x300)))
  (core0-put! *core0-inbox* '(((text "a")) . (#x303)))
  (let-values ([(events types) (core0-window-events)])
    (let-values ([(again more) (core0-window-events)])
      (check "the events of core0's steps wait in the inbox, the oldest \
              first, and are taken once"
             (and (equal? events '((key-down #\a ()) (text "a")))
                  (equal? types '(#x300 #x303))
                  (null? again) (null? more))))))

;; A resize: core1, woken for it, reads the window's size from the facts,
;; so core0 reads them again before it hands the events over.
(let ([order '()] [put core0-put!])
  (fluid-let ([*core0-inbox* (box '())]
              [core0-window-pump
               (lambda () (values '((window-resized)) '(#x206) 0))]
              [platform-reports-pump! void]
              [core0-world-wake! void]
              [core0-facts-refresh!
               (lambda (all?) (set! order (cons 'facts order)))]
              [core0-put! (lambda (b x)
                           (set! order (cons 'put order))
                           (put b x))])
    (core0-step!)
    (check (format "core0 reads what the window says of itself before it \
                    hands the world its events, so a resize finds the new \
                    size; once a step (~a)" (reverse order))
           (equal? (reverse order) '(facts put)))))

;; A pump that holds core0 is traced with what it brought.
(let ([traced '()])
  (fluid-let ([*core0-inbox* (box '())]
              [core0-window-pump
               (lambda ()
                 (sleep (make-time 'time-duration 3000000 0))
                 (values '((mouse-leave)) '(#x20d) 0))]
              [platform-reports-pump! void]
              [core0-world-wake! void]
              [core0-facts-refresh! (lambda (all?) (void))]
              [core0-trace! (lambda (code a)
                             (set! traced (cons (cons code a) traced)))])
    (core0-events-pumped!)
    (check (format "a pump that held core0 past 2 ms is traced, µs, with its \
                    events' types (~a)" (reverse traced))
           (let ([slow (assv 13 traced)])
             (and slow (>= (cdr slow) 2000)
                  (equal? (assv 14 traced) '(14 . #x20d)))))))

(check "headless, the window's facts are a world that's shown at 60 Hz, with \
        no light or dark of a desktop's, and inspect-core0 reads core0's step \
        and who the window is to the desktop"
       (and (not (core0-hidden?))
            (= (core0-frame-ns) (quotient 1000000000 60))
            (not (screen-system-theme))
            (equal? (map car (inspect-core0))
                    '(sizes app-id least system-theme scale flags frame-ns jobs
                      events failed refresh-said))
            (equal? (cdr (assq 'app-id (inspect-core0))) "schevana")))

;; Core0's sleep, on a thread of its own, with a window and nothing of a
;; frame's awaited: SDL's wait for events, which a posted job or a
;; published frame ends, at once or from its next sleep, by an event it
;; pushes; nothing else ends it, so a sleep with nothing to wake it lasts
;; its whole time. Headless, SDL has no window to wait on, and looks at its
;; queue each ms instead, which the pushed event ends all the same.
(fluid-let ([*core0-forked* #t] [*core0-woken* #f] [*core0-mode* 'sdl]
            [present-awaiting? (lambda (now reports?) #f)])
  (core0-window-pump)                   ; SDL's queue, emptied
  (core0-wake!)
  (let ([t0 (now-ms)])
    (core0-sleep!)
    (let ([before (- (now-ms) t0)] [t1 (now-ms)])
      (fluid-let ([core0-idle-ms 100]) (core0-sleep!))
      (let ([alone (- (now-ms) t1)] [t2 (now-ms)])
        (fork-thread (lambda ()
                       (sleep (make-time 'time-duration 30000000 0))
                       (core0-wake!)))
        (core0-sleep!)
        (let ([during (- (now-ms) t2)]
              [types (let-values ([(events types first)
                                   (core0-window-pump)])
                       types)])
          (check (format "a wake ends core0's wait for events, before it or \
                          during it, by an event the pump passes over, and \
                          nothing else ends it (~a ~a ~a ms, ~a)"
                         before alone during types)
                 (and (< before 100) (>= alone 80) (< 25 during 500)
                      (null? types))))))))

;; While core0 awaits a frame's GPU work or its report, it looks: its sleep
;; is a timed wait on its condition, core0-look-ns, never SDL's.
(fluid-let ([*core0-forked* #t] [*core0-woken* #f] [*core0-mode* 'sdl]
            [present-awaiting? (lambda (now reports?) #t)])
  (let ([t0 (now-ms)])
    (core0-sleep!)
    (let ([look (- (now-ms) t0)])
      (check (format "while core0 awaits something of a frame, its sleep is \
                      a look that ends by itself (~a ms, of ~a µs)"
                     look (quotient core0-look-ns 1000))
             (< look (quotient core0-idle-ms 2))))))

;; Core1's wait, with core0 on a thread of its own: up to ns, or with no
;; end (#f); at once when woken before it, and a wake ends it.
(fluid-let ([*core0-forked* #t] [*core0-world-woken* #f])
  (core0-world-wake!)
  (let ([t0 (now-ns)])
    (core0-world-wait-ns! 2000000000)
    (let ([before (- (now-ns) t0)] [t1 (now-ns)])
      (core0-world-wait-ns! 1500000)
      (let ([alone (- (now-ns) t1)] [t2 (now-ns)])
        (fork-thread (lambda ()
                       (sleep (make-time 'time-duration 30000000 0))
                       (core0-world-wake!)))
        (core0-world-wait-ns! #f)
        (let ([during (- (now-ns) t2)])
          (check (format "core1's wait lasts its ns, a ms and a half, ends \
                          at a wake before it or during it, and with no end \
                          waits for one (~a ~a ~a µs)"
                         (quotient before 1000) (quotient alone 1000)
                         (quotient during 1000))
                 (and (< before 100000000) (>= alone 1400000)
                      (< 25000000 during 500000000))))))))

;; The process's end: whoever exits, core0 waits for the GPU first, since
;; a driver's threads may still be at work (lavapipe compiling a frame's
;; shaders) when exit() tears down what they use. Here the wait, once done,
;; leaves through a continuation before Chez's handler would end the run;
;; an exit that never waited ends the run with status 1, a failure.
(check "an exit waits for the GPU first: core0's exit handler waits for \
        the device, by name, before Chez's ends the process"
       (let ([real gpu-idle!])
         (eq? 'waited
              (call/cc
               (lambda (k)
                 (fluid-let ([gpu-idle! (lambda () (real) (k 'waited))])
                   ((exit-handler) 1)
                   'went-on))))))

;;; In the library edition a library is held to its layer as it compiles
;;; (library-layer, in (schevana base)): one that imports a layer above its
;;; own, or a piece of a sealed layer not its own, is refused; one that
;;; imports its own layer or one below loads. The looks are below the
;;; desktop. The test writes libraries of its own, in a folder of
;;; output-dir.
(unless test-hacker?
(let* ([dir (string-append out-dir "/library-layers")]
       [write! (lambda (name layer imports)
                 (call-with-output-file
                   (string-append dir "/units/layers/" (symbol->string name)
                                  ".sls")
                   (lambda (p)
                     (write `(library (units layers ,name)
                               (export ,name)
                               (import (chezscheme) (schevana base)
                                       ,@(map (lambda (i)
                                                `(units layers ,i))
                                              imports))
                               (library-layer ,@layer)
                               (define (,name) ',name))
                            p))
                   'replace))]
       [loads? (lambda (name)
                 (guard (c [#t #f])
                   (eval `(import (units layers ,name))
                         (copy-environment (scheme-environment) #t))
                   #t))])
  (system (format "rm -rf '~a' && mkdir -p '~a/units/layers'" dir dir))
  (write! 'high '(apps) '())
  (write! 'piece '(core0) '())
  (write! 'door '(core0 facade) '(piece))
  (write! 'above '(kits) '(high))
  (write! 'inside '(kits) '(piece))
  (write! 'through '(kits) '(door))
  (write! 'beside '(apps) '(high))
  (write! 'shell '(desktop) '())
  (write! 'look '(looks) '(shell))
  (write! 'paint '(looks) '())
  (write! 'bars '(desktop) '(paint))
  (parameterize ([library-directories (cons (cons dir dir)
                                            (library-directories))])
    (check "a library importing a layer above its own, or a piece of a \
            sealed layer not through its facade, is refused as it compiles; \
            one importing its own layer, or a sealed one's facade, loads; a \
            look importing the desktop is refused, the desktop importing a \
            look loads"
           (and (not (loads? 'above))
                (not (loads? 'inside))
                (loads? 'through)
                (loads? 'beside)
                (not (loads? 'look))
                (loads? 'bars))))))
