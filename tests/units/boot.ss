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
