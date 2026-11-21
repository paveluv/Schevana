;;; core0/boot.ss — core0 as the bootloader (.work/gpu-design.md 9.13), the
;;; chain's second link: main.ss boots core0, core0 boots core1, and core1
;;; the world. Core0 makes "/core1", hands it where the tree is, the core's
;;; sources and what the command line asked, loads the core there and
;;; calls core1's boot. The core has of core0's and the recorder's only
;;; what their facades give it, (schevana core0) and (schevana recorder),
;;; which it imports.

;; "/core1", where the core lives, once core0 has made it.
(defvar *core0-core1* #f)

;; A sealed environment: all of Chez, and of anyone's only what is given
;; it.
(define (core0-sealed) (copy-environment (scheme-environment) #t))

(define (core0-load! e root sources)
  (parameterize ([interaction-environment e])
    (for-each (lambda (f) (load (string-append root "/" f))) sources)))

;; Makes "/core1", given what main.ss hands down: where the tree is, the
;; core's sources, and what the command line asked (main-options).
;; => "/core1", not loaded yet.
(define (core0-make! root sources options)
  (let ([core1 (core0-sealed)])
    (define-top-level-value '*schevana-root* root core1)
    (define-top-level-value '*schevana-core1-sources* sources core1)
    (define-top-level-value '*schevana-options* options core1)
    (set! *core0-core1* core1)
    core1))

;; Loads the core's sources into "/core1", then boots core1, which makes
;; the world and loads it, then script (world.ss), if any, which goes on
;; there.
(define (core0-boot-core1! core1 root sources script)
  (core0-load! core1 root sources)
  ((top-level-value 'core1-boot! core1) script))

;; The chain on this thread: core0 makes "/core1", then core1 boots.
(define (core0-boot! root sources options script)
  (core0-boot-core1! (core0-make! root sources options) root sources script))

;; Core0 on this thread, the world on its own (core0-window-start!,
;; core0-fork-loop!): between the two core0 makes "/core1", so the boot
;; screen shows while the core loads. Core1's thread loads the core
;; and boots it.
(define (core0-fork! root sources options script)
  (core0-window-start! (cdr (assq 'mode options))
                       (cadr (assq 'size options))
                       (cddr (assq 'size options))
                       (cdr (assq 'full-screen? options)))
  (let ([core1 (core0-make! root sources options)])
    (core0-fork-loop!
     (lambda () (core0-boot-core1! core1 root sources script)))))
