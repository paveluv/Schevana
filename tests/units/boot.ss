;;; tests/units/boot.ss — core0 as the bootloader: the world's environment
;;; it makes, "/" (src/host/boot.ss).

;; The tests' "/" forwards every name of core0's (tests/core0.ss), so a "/"
;; made again, with no sources, shows what the world is given.
(let ([world (fluid-let ([*host-world* *host-world*])
               (host-boot! *schevana-root* '())
               *host-world*)])
  (define (in-world form) (eval form world))
  (check "core0 makes \"/\" with all of Chez and, of its own names, only its \
          interface: each core0's binding itself, and read-only"
         (and (eq? (in-world 'car) car)
              (eq? (in-world 'gpu-present!) gpu-present!)
              (eq? (in-world '*gpu-facts*) *gpu-facts*)
              (raises? (lambda () (in-world 'gpu-frame!)))
              (raises? (lambda () (in-world '*sdl-window*)))
              (raises? (lambda () (in-world '(set! gpu-present! #f))))
              (raises? (lambda () (in-world '(fluid-let ([*host* 'sdl]) #t))))
              (equal? (in-world '*schevana-sources*) '())
              (not (eq? world core0-env)))))

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
      (host-step! 0)
      (check "a job posted runs at core0's next step, not before, in order"
             (and (null? before) (equal? ran '(2 1)))))
    (define-top-level-value 'boot-test-job!
      (lambda (x) (set! ran (cons (list 'again x) ran))) core0-env)
    (host-post! '(boot-test-job! 3))
    (host-post! '(car ()))
    (host-post! '(boot-test-job! 4))
    (host-step! 0)
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
