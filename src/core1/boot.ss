;;; core1/boot.ss — core1, the chain's third link: core0 loads the core
;;; into "/core1" and calls core1-boot!, which makes the world's
;;; environment, "/", gives it what src/core1/export.ss says, and loads the
;;; world into it. The first of the core's files, as the rest name what it
;;; defines.

;; Whether this is core1, the thread that loaded the core. The world's
;; state is core1's alone, and SDL core0's: a worker runs only worklets
;; (proc.ss), where neither can be named.
(define core1-thread?
  (if (threaded?)
      (let ([id (get-thread-id)]) (lambda () (fx= (get-thread-id) id)))
      (lambda () #t)))

;; "/core1", the core's own environment, where its files load.
(defvar *core1-env* (interaction-environment))

;; "/", the world's, once core1 has made it. Lookups by name go here, not
;; to (interaction-environment), which a private REPL rebinds.
(defvar *world-env* #f)

;; name's value as the world has it: "/"'s own, or else the core's, which
;; "/" has as a forwarder, and top-level-value can't follow one. What
;; calls a procedure by its name, so that a redefinition takes at the next
;; call, looks it up so.
(define (world-value name)
  (if (and *world-env* (top-level-bound? name *world-env*))
      (top-level-value name *world-env*)
      (top-level-value name *core1-env*)))

;; The names core1 gives the world (src/core1/export.ss).
(define (core1-exported) (exports-names core1-exports 'world))

;; Makes "/", gives it core1's exports, and loads the world's files into
;; it (load-world!), then script (world.ss), if any, which goes on there.
(define (core1-boot! script)
  (let ([world (copy-environment (scheme-environment) #t)])
    (set! *world-env* world)
    (exports-install! core1-exports *core1-env* 'world world)
    (load-world!)
    (when script
      (interaction-environment world)
      (load (source-path script)))))
