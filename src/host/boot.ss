;;; host/boot.ss — core0 as the bootloader (.work/gpu-design.md 9.13): it
;;; makes the world's environment, "/", shares its interface there, and
;;; loads the world into it. Everything of core0's not in the interface is
;;; its own: the world may not name it (tests/sources.ss), and in "/" it
;;; isn't there at all.

;; Core0's interface, the names it shares with the world, read-only, sorted
;; by what a thread other than core0's may do with them.
(define host-interface
  '(;; Constants, and procedures of their arguments alone: safe anywhere.
    host-app-id gpu-atlas-side gpu-usage-sampler gpu-usage-target
    host-flag-names host-event-name gpu-show-run? gpu-run-gone?
    ;; The records the two share. Their procedures touch nothing else, so
    ;; what's safe is who holds the record: a thread writes only those it
    ;; holds, and a frame is the world's from gpu-frame-take! until
    ;; gpu-present!.
    ;; compiled shaders
    shader make-shader shader-name shader-stage shader-coords shader-params
    shader-source shader-code shader-price shader-target shader-entry
    shader-group-x shader-uniforms shader-words
    ;; lists, and the runs that show them
    make-gpu-list gpu-list-id gpu-list-recs gpu-list-recs-set! gpu-list-recs-n
    gpu-list-recs-n-set! gpu-list-extras gpu-list-extras-set!
    gpu-list-extras-n gpu-list-extras-n-set! gpu-list-runs gpu-list-runs-set!
    gpu-list-labels gpu-list-labels-set! gpu-list-version
    gpu-list-version-set! gpu-list-recorded gpu-list-recorded-set!
    gpu-list-took gpu-list-took-set!
    ;; images, buffers and the calls that name them
    make-gpu-image gpu-image-id gpu-image-w gpu-image-h gpu-image-levels
    gpu-image-pending-set! gpu-image-gone?-set! make-gpu-buffer*
    gpu-buffer-id gpu-buffer-bytes gpu-buffer-from gpu-buffer-from-set!
    gpu-buffer-to gpu-buffer-to-set! gpu-buffer-gone?-set! make-gpu-call
    gpu-call? gpu-call-shader
    ;; frames
    gpu-frame-recs-set! gpu-frame-recs-n-set! gpu-frame-extras-set!
    gpu-frame-extras-n-set! gpu-frame-table-set! gpu-frame-table-n-set!
    gpu-frame-pieces-set! gpu-frame-images-set! gpu-frame-runs-set!
    gpu-frame-jobs-set! gpu-frame-dirty-set! gpu-frame-computes-set!
    gpu-frame-mode-set! gpu-frame-earlier-set!
    ;; What core0 says of itself, in variables it sets whole: another thread
    ;; reads each whole (Chez lets no thread see an object half made), but
    ;; not in step with the others, as ARM keeps no order between stores.
    ;; *gpu-waits* is filled in place, so its slots may come from two
    ;; frames.
    *gpu-facts* *gpu-frame-state* *gpu-waits* *host*
    ;; Calls into SDL or core0's own state: safe only on core0's thread.
    host-display host-frame-ns host-hidden? host-flags host-error-text
    gpu-frame-take! gpu-present! gpu-take-answers! gpu-drawing->bytes
    gpu-compute-now! gpu-submit-computes! gpu-buffer-download!
    host-environment host-window-headless!
    host-window-open! host-window-show! host-window-close! host-window-sizes
    host-window-resize! host-window-minimum! host-window-scale
    host-window-fullscreen? host-window-fullscreen! host-window-icon!
    host-window-events host-set-cursor! clipboard-get clipboard-set!))

;; The world's environment, "/", once core0 has made it.
(defvar *host-world* #f)

;; Core0's own environment, where its files loaded: "/host" holds it
;; (services/env.ss), for the person to evaluate in, and core0's loop calls
;; its procedures by name, so a redefinition there takes at the next call.
(define host-environment
  (let ([e (interaction-environment)]) (lambda () e)))

;; Makes "/", all of Chez and of core0 only its interface, each name a
;; read-only forwarder to core0's binding (an identifier made here names
;; it); then loads the world's sources there, from root.
(define (host-boot! root sources)
  (let ([world (copy-environment (scheme-environment) #t)])
    (for-each (lambda (name)
                (define-top-level-syntax name
                  (forwarder-to (datum->syntax #'host-boot! name))
                  world))
              host-interface)
    (define-top-level-value '*schevana-root* root world)
    (define-top-level-value '*schevana-sources* sources world)
    (set! *host-world* world)
    (parameterize ([interaction-environment world])
      (for-each (lambda (f) (load (string-append root "/" f))) sources))))

;; Moves a script that loaded the tree (main.ss, a test) into "/": its later
;; forms evaluate there, as the world's.
(define (host-enter-world!) (interaction-environment *host-world*))
