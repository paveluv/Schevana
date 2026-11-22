;;; tests/units/boot.ss — the boot's chain: a launcher starts core0, whose
;;; code is sealed in its libraries, and core1, the core sealed in its own,
;;; which imports what core0 and the recorder give it, their facades; core1
;;; makes "/", which imports what the core gives it, its facade, (schevana
;;; core). In the hacker edition, every library spliced into one
;;; environment, "/" itself, nothing sealed.

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
              (eq? (in-core 'core0-clock-ns) (top-level-value 'core0-clock-ns
                                                              main-env))
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

;; A "/" made as core1 makes it, importing the core's facade: the tests'
;; own has its names settable (tests/reach.ss).
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
         ;; read by eval: the hook is a library's, a macro there
         (let ([real (eval 'window-gone! core-env)]
               [mine (lambda (win) 'gone)])
           (and (raises? (lambda () (in-world '(set! window-gone! 5))))
                (eq? (eval 'window-gone! core-env) real)
                (eq? (in-world `(fluid-let ([window-gone! ',mine])
                                  window-gone!))
                     mine)
                (eq? (eval 'window-gone! core-env) real))))))

;; In the hacker edition every library's names are here, internals too, and
;; a redefinition takes at the core's next call, as a world of top-level
;; files has it. Evaluated there only: the library edition refuses the
;; set! as it expands.
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
;; once, in its defaults' order; a word it doesn't know prints the usage.
(let ([defaults (if test-hacker?
                    (map (lambda (d)
                           (if (eq? (car d) 'hacker) '(hacker . #t) d))
                         desktop-defaults)
                    desktop-defaults)])
  (fluid-let ([desktop-usage (lambda () 'usage)])
    (check "the desktop reads the command line once: what's asked over the \
            defaults, in their order, and the usage for a word it doesn't \
            know"
           (and (equal? (desktop-options '()) defaults)
                (equal? (desktop-options '("--headless" "--size" "400x300"
                                           "--eval" "1" "--fork" "--demo"
                                           "--eval" "2" "--hacker"))
                        '((mode . headless)
                          (size 400 . 300)
                          (full-screen? . #f)
                          (fork? . #t)
                          (desktop . #f)
                          (hacker . #t)
                          (demo . #t)
                          (evals "1" "2")))
                (eq? (desktop-options '("--size" "400")) 'usage)
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
;;; until taken; what it says of the window it read at the step.

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

;;; Core0's sleep, unwound from inside its wait: a second Ctrl-C before
;;; the first is answered makes Chez drop the first thread's stack where
;;; it stands, in the wait too, where the mutex is given up. Here the
;;; release that unwinding runs, in each of the three places.
(check "core0's sleep, dropped in its wait, unwinds without a word of the \
        mutex it gave up, and releases the one it holds, in the wait or not"
       (let ([held? (lambda ()   ; whether a release of the mutex is taken
                      (guard (c [#t #f])
                        (mutex-release *core0-world-mutex*)
                        #t))])
         (and
          ;; in the wait, the mutex not this thread's: nothing is raised
          (fluid-let ([*core0-sleeping* #t])
            (guard (c [#t #f])
              (core0-sleep-release!)
              (not *core0-sleeping*)))
          ;; in the wait's own frame, the mutex still held: released
          (fluid-let ([*core0-sleeping* #t])
            (mutex-acquire *core0-world-mutex*)
            (core0-sleep-release!)
            (not (held?)))
          ;; out of the wait: released, as with-mutex would
          (begin
            (mutex-acquire *core0-world-mutex*)
            (core0-sleep-release!)
            (not (held?))))))

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

(check "headless, the window's facts are a world that's shown at 60 Hz, and \
        inspect-core0 reads core0's step"
       (and (not (core0-hidden?))
            (= (core0-frame-ns) (quotient 1000000000 60))
            (equal? (map car (inspect-core0))
                    '(sizes scale flags frame-ns jobs events failed
                      refresh-said))))

;; Core0's sleep, on a thread of its own: a job posted or a frame published
;; wakes it, at once or from the next sleep; its events never do, so a
;; sleep with nothing to wake it lasts its whole time.
(fluid-let ([*core0-forked* #t] [*core0-woken* #f])
  (core0-wake!)
  (let ([t0 (now-ms)])
    (core0-sleep! 1000)
    (let ([before (- (now-ms) t0)] [t1 (now-ms)])
      (core0-sleep! 20)
      (let ([alone (- (now-ms) t1)] [t2 (now-ms)])
        (fork-thread (lambda ()
                       (sleep (make-time 'time-duration 30000000 0))
                       (core0-wake!)))
        (core0-sleep! 1000)
        (let ([during (- (now-ms) t2)])
          (check (format "a wake ends core0's sleep, before it or during it, \
                          and nothing else does (~a ~a ~a ms)"
                         before alone during)
                 (and (< before 100) (>= alone 15) (< 25 during 500))))))))

;; The boot screen, which draws only with a window, by its blits onto a
;; texture: the λ scaled up four times, sharp, on the ground; under it the
;; bar's track, its first half filled.
(let* ([r *renderer*]
       [d (renderer-device r)]
       [t (gpu-make-texture d gpu-format-bgra8
                            (fxior gpu-usage-sampler gpu-usage-target) 36 52)]
       [cb (sdl-acquire-gpu-commands d)])
  (gpu-boot-blit! cb t 0 0 9 12 0 0 36 48 #t)
  (gpu-boot-blit! cb t 0 12 1 1 0 50 36 2 #f)
  (gpu-boot-blit! cb t 1 12 1 1 0 50 18 2 #f)
  (let* ([bytes (gpu-read-texture! r cb t 36 52)]
         [px (lambda (x y)
               (bytevector-u32-native-ref bytes (* 4 (+ x (* y 36)))))]
         [color (lambda (c) (cdr (assv c gpu-boot-colors)))])
    (sdl-release-gpu-texture d t)
    (check "the boot screen's blits: the λ scaled up sharp on the ground, \
            the bar's track under it, filled as far as asked"
           (and (= (px 0 0) (px 7 3) (color #\#))
                (= (px 8 0) (px 35 0) (px 0 49) (color #\.))
                (= (px 0 50) (px 17 51) (color #\f))
                (= (px 18 50) (px 35 51) (color #\t))
                (= (px 32 47) (color #\#))))))

;; The process's end: whoever exits, core0 waits for the GPU first, as a
;; driver's threads may still be at work (lavapipe compiling a frame's
;; shaders) when exit() tears down what they use. Here the wait, once
;; done, leaves by a continuation, before Chez's handler would end the run;
;; an exit that never waited ends it with status 1, failed.
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
;;; imports its own layer or below loads. Libraries of the test's own, in a
;;; folder of out/.
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
  (parameterize ([library-directories (cons (cons dir dir)
                                            (library-directories))])
    (check "a library importing a layer above its own, or a piece of a \
            sealed layer not through its facade, is refused as it compiles; \
            one importing its own layer, or a sealed one's facade, loads"
           (and (not (loads? 'above))
                (not (loads? 'inside))
                (loads? 'through)
                (loads? 'beside))))))
