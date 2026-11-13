;;; tests/units/boot.ss — the boot's chain: core0 makes "/recorder" and
;;; "/core1" (src/core0/boot.ss), core1 makes "/" (src/core1/boot.ss), each
;;; given what the one before exports (src/base.ss's define-exports).

;; core0 makes the two again, with no sources for core1, to show what core1
;; is given; the tests' own stay as they were.
(let ([core1 (fluid-let ([*core0-core1* *core0-core1*]
                         [*core0-recorder* *core0-recorder*])
               (core0-make! *schevana-root* *schevana-recorder-sources* '()
                            '((mode . headless))))])
  (define (in-core1 form) (eval form core1))
  (define (named? name) (guard (c [#t #f]) (in-core1 name) #t))
  (check "core0 makes \"/core1\" with all of Chez and, of its own names, \
          only what it exports there: each core0's binding itself, and \
          read-only; and hands it the core's sources and the command \
          line's options"
         (and (eq? (in-core1 'car) car)
              (eq? (in-core1 'gpu-publish!) gpu-publish!)
              (eq? (in-core1 '*gpu-facts*) *gpu-facts*)
              (eq? (in-core1 'core0-clock-ns) (top-level-value 'core0-clock-ns
                                                               core0-env))
              (not (named? 'gpu-frame!))
              (not (named? '*sdl-window*))
              (not (named? 'sdl-get-ticks-ns))
              (raises? (lambda () (in-core1 '(set! gpu-publish! #f))))
              (raises? (lambda ()
                         (in-core1 '(fluid-let ([*core0-mode* 'sdl]) #t))))
              (equal? (in-core1 '*schevana-core1-sources*) '())
              (equal? (in-core1 '*schevana-options*) '((mode . headless)))
              (not (eq? core1 core0-env))))
  (check "\"/recorder\" is sealed: \"/core1\" holds what it exports, \
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
              (not (named? 'gpu-frame-earlier-set!))
              (eq? (env-kind (env-find "/recorder")) 'recorder))))

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
         (let ([real (top-level-value '*window-gone* core1-env)]
               [mine (lambda (win) 'gone)])
           (and (raises? (lambda () (in-world '(set! *window-gone* 5))))
                (eq? (top-level-value '*window-gone* core1-env) real)
                (eq? (in-world `(fluid-let ([*window-gone* ',mine])
                                  *window-gone*))
                     mine)
                (eq? (top-level-value '*window-gone* core1-env) real)))))

(check "an export list names only the chain's environments, and a name \
        that isn't there to give stops the install"
       (and (raises? (lambda ()
                       (eval '(define-exports units-x (export (moon) car))
                             core0-env)))
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
            (not (eq? *world-env* core0-env))
            (not (eq? core1-env core0-env))))

;;; Core0's step: jobs the world posts run at its next step, in order, by
;;; name; the events it pumps wait in the world's inbox until taken; what it
;;; says of the window it read at the step.

(let ([ran '()])
  (fluid-let ([*core0-jobs* (box '())]
              [*core0-job-failed* #f])
    (define-top-level-value 'boot-test-job!
      (lambda (x) (set! ran (cons x ran))) core0-env)
    (core0-post! '(boot-test-job! 1))
    (core0-post! '(boot-test-job! 2))
    (let ([before ran])
      (core0-step!)
      (check "a job posted runs at core0's next step, not before, in order"
             (and (null? before) (equal? ran '(2 1)))))
    (define-top-level-value 'boot-test-job!
      (lambda (x) (set! ran (cons (list 'again x) ran))) core0-env)
    (core0-post! '(boot-test-job! 3))
    (core0-post! '(car ()))
    (core0-post! '(boot-test-job! 4))
    (core0-step!)
    (check "by name, so a redefinition takes; one that raises is kept, and \
            the rest run"
           (and (equal? (list-head ran 2) '((again 4) (again 3)))
                (equal? (car *core0-job-failed*) '(car ()))))))

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
                    '(sizes scale flags frame-ns jobs events failed))))

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
