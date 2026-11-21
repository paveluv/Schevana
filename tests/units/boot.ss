;;; tests/units/boot.ss — the boot's chain: core0 makes "/core1"
;;; (src/core0/boot.ss), where the core imports what core0 and the recorder
;;; give it, their facades; core1 makes "/" (src/core1/boot.ss), given what
;;; core1 exports (src/base.ss's define-exports).

;; core0 makes "/core1" again, with no sources for core1, and the facades
;; are imported there as the core's boot does, to show what the core is
;; given; the tests' own stays as it was.
(let ([core1 (fluid-let ([*core0-core1* *core0-core1*])
               (core0-make! *schevana-root* '() '((mode . headless))))])
  (define (in-core1 form) (eval form core1))
  (define (named? name) (guard (c [#t #f]) (in-core1 name) #t))
  (in-core1 '(import (schevana core0) (schevana recorder)))
  (check "core0 makes \"/core1\" with all of Chez, and hands it the core's \
          sources and the command line's options; of core0's names the \
          core has what its facade gives, each core0's binding itself, and \
          read-only, a state or a hook core0 sets as a view"
         (and (eq? (in-core1 'car) car)
              (eq? (in-core1 'gpu-publish!) gpu-publish!)
              (eq? (in-core1 '*gpu-facts*) *gpu-facts*)
              (eq? (in-core1 'core0-clock-ns) (top-level-value 'core0-clock-ns
                                                               main-env))
              (not (named? 'gpu-frame!))
              (not (named? '*sdl-window*))
              (not (named? 'sdl-get-ticks-ns))
              (raises? (lambda () (in-core1 '(set! gpu-publish! #f))))
              (raises? (lambda ()
                         (in-core1 '(fluid-let ([*core0-mode* 'sdl]) #t))))
              (equal? (in-core1 '*schevana-core1-sources*) '())
              (equal? (in-core1 '*schevana-options*) '((mode . headless)))
              (not (eq? core1 main-env))))
  (check "the recorder is sealed: the core holds what its facade gives, \
          read-only, and none of the bytes it hands core0, nor what writes \
          them"
         (and (procedure? (in-core1 'rec-write!))
              (raises? (lambda () (in-core1 '(set! rec-write! #f))))
              (not (named? '*rec-now*))
              (not (named? 'rec-take!))
              (not (named? 'gpu-recording-recs))
              (not (named? 'gpu-list-recording-set!))
              (not (named? 'make-gpu-list))
              (not (named? 'gpu-frame-root-set!))
              (not (named? 'gpu-frame-earlier-set!)))))

;; A "/" made as core1 makes it, given core1's exports: the tests' own has
;; them settable (tests/reach.ss).
(let ([world (let ([w (copy-environment (scheme-environment) #t)])
               (exports-install! core1-exports core1-env 'world w)
               w)])
  (define (in-world form) (eval form world))
  (define (named? name) (guard (c [#t #f]) (in-world name) #t))
  (check "core1 gives \"/\" what it exports, each the core's binding \
          itself and read-only, core0's it gives again too; nothing else of \
          the core's, and none of its C"
         (and (eq? (in-world 'theme) (top-level-value 'theme core1-env))
              (eq? (in-world 'core0-frame-ns) core0-frame-ns)
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
         ;; read by eval: the hook is a library's, a macro in "/core1"
         (let ([real (eval 'window-gone! core1-env)]
               [mine (lambda (win) 'gone)])
           (and (raises? (lambda () (in-world '(set! window-gone! 5))))
                (eq? (eval 'window-gone! core1-env) real)
                (eq? (in-world `(fluid-let ([window-gone! ',mine])
                                  window-gone!))
                     mine)
                (eq? (eval 'window-gone! core1-env) real)))))

(check "an export list names only the chain's environments, and a name \
        that isn't there to give stops the install"
       (and (raises? (lambda ()
                       (eval '(define-exports units-x (export (moon) car))
                             main-env)))
            (raises? (lambda ()
                       (exports-install!
                        (list (cons '(world) '((units-no-such-name . #f))))
                        core1-env 'world
                        (copy-environment (scheme-environment) #t))))))

;; main.ss reads the command line before anything loads, each option once,
;; in its defaults' order; a word it doesn't know prints the usage.
(fluid-let ([main-usage (lambda () 'usage)])
  (check "main.ss reads the command line once: what's asked over the \
          defaults, in their order, and the usage for a word it doesn't know"
         (and (equal? (main-options '())
                      main-defaults)
              (equal? (main-options '("--headless" "--size" "400x300"
                                      "--eval" "1" "--fork" "--eval" "2"))
                      '((mode . headless)
                        (size 400 . 300)
                        (full-screen? . #f)
                        (fork? . #t)
                        (desktop . #f)
                        (evals "1" "2")))
              (eq? (main-options '("--size" "400")) 'usage)
              (eq? (main-options '("--size")) 'usage)
              (eq? (main-options '("--frobnicate")) 'usage)
              (equal? *schevana-options* (main-options '("--headless")))))
  (check "a window, or --fork, boots on two threads; installing the \
          desktop entry on one"
         (and (main-fork? (main-options '()))
              (main-fork? (main-options '("--headless" "--fork")))
              (not (main-fork? (main-options '("--headless"))))
              (not (main-fork? (main-options '("--install-desktop")))))))

(check "the world runs in an environment of its own, made by core1 in \
        one of its own, made by core0"
       (and (eq? *world-env* world-env)
            (eq? *core1-env* core1-env)
            (eq? core1-env *core0-core1*)
            (not (eq? *world-env* core1-env))
            (not (eq? *world-env* main-env))
            (not (eq? core1-env main-env))))

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

;;; A library is held to its layer as it compiles (library-layer, in
;;; (schevana base)): one that imports a layer above its own, or a piece of
;;; a sealed layer not its own, is refused; one that imports its own layer
;;; or below loads. Libraries of the test's own, in a folder of out/.
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
                (loads? 'beside)))))
