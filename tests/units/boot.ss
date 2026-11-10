;;; tests/units/boot.ss — core0 as the bootloader: the world's environment
;;; it makes, "/" (src/host/boot.ss).

;; The tests' "/" forwards every name of core0's (tests/core0.ss), so a "/"
;; made again, with no sources, shows what the world is given.
(let ([world (fluid-let ([*host-world* *host-world*]
                         [*host-recorder* *host-recorder*])
               (host-boot! *schevana-root* *schevana-recorder-sources* '())
               *host-world*)])
  (define (in-world form) (eval form world))
  (check "core0 makes \"/\" with all of Chez and, of its own names, only its \
          interface: each core0's binding itself, and read-only"
         (and (eq? (in-world 'car) car)
              (eq? (in-world 'gpu-publish!) gpu-publish!)
              (eq? (in-world '*gpu-facts*) *gpu-facts*)
              (raises? (lambda () (in-world 'gpu-frame!)))
              (raises? (lambda () (in-world '*sdl-window*)))
              (raises? (lambda () (in-world '(set! gpu-publish! #f))))
              (raises? (lambda () (in-world '(fluid-let ([*host* 'sdl]) #t))))
              (equal? (in-world '*schevana-sources*) '())
              (not (eq? world core0-env)))))

(let ([world (fluid-let ([*host-world* *host-world*]
                         [*host-recorder* *host-recorder*])
               (host-boot! *schevana-root* *schevana-recorder-sources* '())
               *host-world*)])
  (define (named? name) (guard (c [#t #f]) (eval name world) #t))
  (check "\"/recorder\" is sealed: \"/\" holds its interface, read-only, and \
          none of the bytes it hands core0, nor what writes them"
         (and (procedure? (eval 'rec-write! world))
              (raises? (lambda () (eval '(set! rec-write! #f) world)))
              (not (named? '*rec-now*))
              (not (named? 'rec-take!))
              (not (named? 'gpu-recording-recs))
              (not (named? 'gpu-list-recording-set!))
              (not (named? 'make-gpu-list))
              (not (named? 'gpu-frame-root-set!))
              (not (named? 'gpu-frame-earlier-set!))
              (eq? (env-kind (env-find "/recorder")) 'recorder))))

(check "the world runs in an environment of its own, not core0's"
       (and (eq? *world-env* *host-world*)
            (not (eq? *world-env* core0-env))))

;;; Core0's step: jobs the world posts run at its next step, in order, by
;;; name; the events it pumps wait in the world's inbox until taken; what it
;;; says of the window it read at the step.

(let ([ran '()])
  (fluid-let ([*host-jobs* (box '())]
              [*host-job-failed* #f])
    (define-top-level-value 'boot-test-job!
      (lambda (x) (set! ran (cons x ran))) core0-env)
    (host-post! '(boot-test-job! 1))
    (host-post! '(boot-test-job! 2))
    (let ([before ran])
      (host-step!)
      (check "a job posted runs at core0's next step, not before, in order"
             (and (null? before) (equal? ran '(2 1)))))
    (define-top-level-value 'boot-test-job!
      (lambda (x) (set! ran (cons (list 'again x) ran))) core0-env)
    (host-post! '(boot-test-job! 3))
    (host-post! '(car ()))
    (host-post! '(boot-test-job! 4))
    (host-step!)
    (check "by name, so a redefinition takes; one that raises is kept, and \
            the rest run"
           (and (equal? (list-head ran 2) '((again 4) (again 3)))
                (equal? (car *host-job-failed*) '(car ()))))))

(fluid-let ([*host-inbox* (box '())])
  (host-put! *host-inbox* '(((key-down #\a ())) . (#x300)))
  (host-put! *host-inbox* '(((text "a")) . (#x303)))
  (let-values ([(events types) (host-window-events)])
    (let-values ([(again more) (host-window-events)])
      (check "the events of core0's steps wait in the inbox, the oldest \
              first, and are taken once"
             (and (equal? events '((key-down #\a ()) (text "a")))
                  (equal? types '(#x300 #x303))
                  (null? again) (null? more))))))

(check "headless, the window's facts are a world that's shown at 60 Hz, and \
        inspect-host reads core0's step"
       (and (not (host-hidden?))
            (= (host-frame-ns) (quotient 1000000000 60))
            (equal? (map car (inspect-host))
                    '(sizes scale flags frame-ns jobs events failed))))

;; Core0's sleep, on a thread of its own: a job posted or a frame published
;; wakes it, at once or from the next sleep; its events never do, so a
;; sleep with nothing to wake it lasts its whole time.
(fluid-let ([*host-forked* #t] [*host-woken* #f])
  (host-wake!)
  (let ([t0 (now-ms)])
    (host-sleep! 1000)
    (let ([before (- (now-ms) t0)] [t1 (now-ms)])
      (host-sleep! 20)
      (let ([alone (- (now-ms) t1)] [t2 (now-ms)])
        (fork-thread (lambda ()
                       (sleep (make-time 'time-duration 30000000 0))
                       (host-wake!)))
        (host-sleep! 1000)
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
