;;; core0/boot.ss — core0 as the bootloader (.work/gpu-design.md 9.13), the
;;; chain's second link: main.ss boots core0, core0 boots core1, and core1
;;; the world. Core0 makes "/recorder" and "/core1", gives each what
;;; src/core0/export.ss says, loads them, and calls core1's boot. Of
;;; core0's own, nothing else is there to name.

;; Core0's own environment, where its files loaded: "/core0" holds it
;; (services/env.ss), for the person to evaluate in.
(define core0-environment
  (let ([e (interaction-environment)]) (lambda () e)))

;; Forms evaluated in core0's environment by core0 itself, between frames,
;; as a vat takes them: a REPL in "/core0" sends them, never touching core0's
;; state from core1. then gets, on core1, (ok text ...), what they
;; printed and their values but (void) written width wide, or (error text).
(define (core0-eval! forms width then)
  (core0-post! (list core0-eval-now! forms width then)))

(define (core0-eval-now! forms width then)
  (core0-put! *gpu-answers*
             (cons then
                   (guard (c [#t (list 'error (condition->string c))])
                     (cons 'ok (core0-eval-texts forms width)))))
  (core0-world-wake!))

(define (core0-eval-texts forms width)
  (let* ([chop (lambda (s)   ; its last newline off
                 (if (and (> (string-length s) 0)
                          (char=? #\newline
                                  (string-ref s (- (string-length s) 1))))
                     (substring s 0 (- (string-length s) 1))
                     s))]
         [text (lambda (v)
                 (chop (with-output-to-string (lambda () (pretty-print v)))))])
    (parameterize ([pretty-line-length width]
                   [interaction-environment (core0-environment)])
      (let loop ([forms forms] [texts '()])
        (if (null? forms)
            (reverse texts)
            (let* ([vals #f]
                   [out (with-output-to-string
                         (lambda ()
                           (set! vals (call-with-values
                                        (lambda ()
                                          (eval (car forms)
                                                (core0-environment)))
                                        list))))])
              (loop (cdr forms)
                    (append (reverse
                             (map text (filter (lambda (v)
                                                 (not (eq? v (void))))
                                               vals)))
                            (if (string=? out "") '() (list (chop out)))
                            texts))))))))

;; "/recorder", sealed (.work/gpu-design.md 9.14): the bytes of frames and
;; their writers, below core1, which names only what it exports.
(defvar *core0-recorder* #f)
(define (core0-recorder-environment) *core0-recorder*)

;; "/core1", where the core lives, once core0 has made it.
(defvar *core0-core1* #f)

;; A sealed environment: all of Chez, and of anyone's only what is given
;; it.
(define (core0-sealed) (copy-environment (scheme-environment) #t))

(define (core0-load! e root sources)
  (parameterize ([interaction-environment e])
    (for-each (lambda (f) (load (string-append root "/" f))) sources)))

;; Makes "/recorder", given core0's exports to it, and loads its sources
;; there; then "/core1", given core0's exports and the recorder's, and
;; what main.ss hands down: where the tree is, the core's sources, and what
;; the command line asked (main-options). => "/core1", not loaded yet.
(define (core0-make! root recorder-sources sources options)
  (let ([recorder (core0-sealed)] [core1 (core0-sealed)])
    (exports-install! core0-exports (core0-environment) 'recorder recorder)
    (set! *core0-recorder* recorder)
    (core0-load! recorder root recorder-sources)
    (exports-install! core0-exports (core0-environment) 'core1 core1)
    (exports-install! (top-level-value 'recorder-exports recorder) recorder
                      'core1 core1)
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

;; The chain on this thread: core0 makes the environments, then core1
;; boots.
(define (core0-boot! root recorder-sources sources options script)
  (core0-boot-core1! (core0-make! root recorder-sources sources options)
                     root sources script))

;; Core0 on this thread, the world on its own (core0-window-start!,
;; core0-fork-loop!): between the two core0 makes the environments, so
;; the boot screen shows while they load. Core1's thread loads the core
;; and boots it.
(define (core0-fork! root recorder-sources sources options script)
  (core0-window-start! (cdr (assq 'mode options))
                       (cadr (assq 'size options))
                       (cddr (assq 'size options))
                       (cdr (assq 'full-screen? options)))
  (let ([core1 (core0-make! root recorder-sources sources options)])
    (core0-fork-loop!
     (lambda () (core0-boot-core1! core1 root sources script)))))
