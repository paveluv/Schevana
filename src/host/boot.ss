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
    ;; holds, and a frame is the world's from gpu-frame-make, or
    ;; gpu-frames-back!, until gpu-publish!.
    ;; compiled shaders
    shader make-shader shader-name shader-stage shader-coords shader-params
    shader-source shader-code shader-price shader-target shader-entry
    shader-group-x shader-uniforms shader-words
    ;; lists, and the runs that show them; their recordings are the
    ;; recorder's alone (host-recorder-share)
    gpu-list-id gpu-list-labels gpu-list-labels-set! gpu-list-recorded
    gpu-list-recorded-set! gpu-list-took gpu-list-took-set!
    ;; images, buffers and the calls that name them
    make-gpu-image gpu-image-id gpu-image-w gpu-image-h gpu-image-levels
    gpu-image-gone?-set! make-gpu-buffer* gpu-buffer-id gpu-buffer-size
    gpu-buffer-gone?-set! make-gpu-call gpu-call? gpu-call-shader
    ;; frames; what they write is the recorder's (host-recorder-share)
    gpu-frame-make gpu-frame-table-set! gpu-frame-table-n-set!
    gpu-frame-pieces-set! gpu-frame-jobs-set! gpu-frame-computes-set!
    gpu-frame-mode-set! gpu-frame-number gpu-frame-shown?
    ;; What core0 says of itself, in variables it sets whole: another thread
    ;; reads each whole (Chez lets no thread see an object half made), but
    ;; not in step with the others, as ARM keeps no order between stores.
    *gpu-facts* *host* *host-platform*
    ;; The same, read through procedures: the window's facts as core0's
    ;; step last read them, made again whole when they change; what became
    ;; of each frame, by its report; and the events its steps put in the
    ;; world's inbox, taken.
    host-display host-frame-ns host-hidden? host-flags host-error-text
    host-step-state host-frame-report
    host-window-sizes host-window-scale host-window-fullscreen?
    clipboard-get host-window-events host-input-ns-take!
    ;; Jobs: posted to core0's mailbox, run at its next step; safe from any
    ;; thread.
    host-window-minimum! host-window-fullscreen! host-window-icon!
    host-set-cursor! clipboard-set! host-trace-dump! host-eval!
    ;; a step of the calling thread's, on its own ring
    host-trace!
    ;; and its wake, ending core0's wait; frames published, whether the last
    ;; waits still, those given back, and what core0 read back: from any
    ;; thread
    host-wake! gpu-publish! gpu-frame-waiting? gpu-frames-back!
    gpu-take-answers!
    ;; whether core0 has a thread of its own; main's wait, and its wake from
    ;; any thread; and quitting, a job
    host-forked? host-world-wait! host-world-wake! host-quit!
    ;; and how far the world has loaded, for the boot screen
    host-loaded!
    ;; Calls into SDL or core0's own state: safe only on core0's thread.
    ;; Until core0 has a thread of its own the world steps it (host-step!),
    ;; and boots it (opening, sizing, showing the window).
    host-step! host-environment host-recorder-environment
    host-window-headless!
    host-window-open! host-window-show! host-window-close!
    host-window-resize!))

;; The world's environment, "/", once core0 has made it.
(defvar *host-world* #f)

;; Core0's own environment, where its files loaded: "/host" holds it
;; (services/env.ss), for the person to evaluate in, and core0's loop calls
;; its procedures by name, so a redefinition there takes at the next call.
(define host-environment
  (let ([e (interaction-environment)]) (lambda () e)))

;; Forms evaluated in core0's environment by core0 itself, between frames,
;; as a vat takes them: a REPL in "/host" sends them, never touching core0's
;; state from main's thread. then gets, on main, (ok text ...), what they
;; printed and their values but (void) written width wide, or (error text).
(define (host-eval! forms width then)
  (host-post! (list 'host-eval-now! forms width then)))

(define (host-eval-now! forms width then)
  (host-put! *gpu-answers*
             (cons then
                   (guard (c [#t (list 'error (condition->string c))])
                     (cons 'ok (host-eval-texts forms width)))))
  (host-world-wake!))

(define (host-eval-texts forms width)
  (let* ([chop (lambda (s)   ; its last newline off
                 (if (and (> (string-length s) 0)
                          (char=? #\newline
                                  (string-ref s (- (string-length s) 1))))
                     (substring s 0 (- (string-length s) 1))
                     s))]
         [text (lambda (v)
                 (chop (with-output-to-string (lambda () (pretty-print v)))))])
    (parameterize ([pretty-line-length width]
                   [interaction-environment (host-environment)])
      (let loop ([forms forms] [texts '()])
        (if (null? forms)
            (reverse texts)
            (let* ([vals #f]
                   [out (with-output-to-string
                         (lambda ()
                           (set! vals (call-with-values
                                        (lambda ()
                                          (eval (car forms)
                                                (host-environment)))
                                        list))))])
              (loop (cdr forms)
                    (append (reverse
                             (map text (filter (lambda (v)
                                                 (not (eq? v (void))))
                                               vals)))
                            (if (string=? out "") '() (list (chop out)))
                            texts))))))))

;; What core0 shares with "/recorder" alone, beside its interface:
;; recordings, the lists, images and frame that hold them, how far frames
;; have come back, and the calls that hand core0 writes with no frame. The
;; world never has them, so it can't name a byte core0 reads, or hand
;; core0 a recording the recorder didn't freeze.
(define host-recorder-share
  '(make-gpu-recording gpu-recording-recs gpu-recording-recs-set!
    gpu-recording-recs-n gpu-recording-recs-n-set! gpu-recording-extras
    gpu-recording-extras-set! gpu-recording-extras-n
    gpu-recording-extras-n-set! gpu-recording-runs gpu-recording-runs-set!
    gpu-recording-version gpu-recording-version-set! gpu-recording-until
    gpu-recording-until-set! gpu-recording-next gpu-recording-next-set!
    make-gpu-list gpu-list-recording gpu-list-recording-set!
    gpu-recording? gpu-image? gpu-image-loans gpu-image-loans-set!
    gpu-frame-root gpu-frame-root-set! gpu-frame-number
    gpu-frame-number-set! gpu-frame-earlier-set! gpu-frame-writes-set!
    *gpu-frame-back* gpu-drawing->bytes gpu-compute-now!
    gpu-submit-computes! gpu-buffer-download! host-post-submit!))

;; "/recorder", sealed (.work/gpu-design.md 9.14): the bytes of frames and
;; their writers, below the world, which names only its interface.
(defvar *host-recorder* #f)
(define (host-recorder-environment) *host-recorder*)

;; An identifier at environment's top level: a forwarder made from it names
;; that environment's binding. A macro there, under a name no code can type,
;; hands back the identifier it is used with.
(define (host-anchor environment)
  (let ([grab (gensym "host-anchor")] [got #f])
    (define-top-level-syntax grab
      (lambda (x)
        (syntax-case x () [(_ id) (begin (set! got #'id) #''anchor)]))
      environment)
    (eval (list grab 'host-anchor) environment)
    got))

;; A sealed environment: all of Chez and, of each (names . anchor) shared,
;; each name a read-only forwarder to the binding anchor's environment has.
(define (host-sealed shares)
  (let ([e (copy-environment (scheme-environment) #t)])
    (for-each (lambda (share)
                (for-each (lambda (name)
                            (define-top-level-syntax name
                              (forwarder-to (datum->syntax (cdr share) name))
                              e))
                          (car share)))
              shares)
    e))

(define (host-load! e root sources)
  (parameterize ([interaction-environment e])
    (for-each (lambda (f) (load (string-append root "/" f))) sources)))

;; Makes "/recorder", sealed, shared core0's interface, and loads its
;; sources there; then "/", shared core0's interface and the recorder's,
;; and loads the world's sources there, from root.
(define (host-boot! root recorder-sources sources)
  (host-load! (host-make-world! root recorder-sources sources) root sources))

;; The environments, "/recorder" loaded: => "/", empty.
(define (host-make-world! root recorder-sources sources)
  (let* ([core0 (cons host-interface #'host-boot!)]
         [recorder (host-sealed
                    (list (cons (append host-interface host-recorder-share)
                                #'host-boot!)))])
    (set! *host-recorder* recorder)
    (host-load! recorder root recorder-sources)
    (let ([world (host-sealed
                  (list core0
                        (cons (top-level-value 'recorder-interface recorder)
                              (host-anchor recorder))))])
      (define-top-level-value '*schevana-root* root world)
      (define-top-level-value '*schevana-sources* sources world)
      (set! *host-world* world)
      world)))

;; Core0 on this thread, the world on its own: with a window (mode 'sdl),
;; core0 opens it, w × h logical pixels at the desktop's scale, or full
;; screen, and clears it; with none ('headless, for the tests), its GPU
;; draws to a target. Then it makes the environments; forks main, which
;; loads the world's sources and then script into "/"; and goes on as the
;; host, on this thread, till main quits. Main asks core0 to quit when
;; script returns, or raises.
(define (host-fork! root recorder-sources sources script mode w h full?)
  (if (eq? mode 'headless)
      (host-window-headless!)
      (begin
        (host-window-open! w h full?)
        (unless full?
          (let-values ([(uw uh pw ph) (host-window-sizes)])
            (let ([s (/ (if (> (host-window-scale) 0) (host-window-scale) 1)
                        (/ pw (max uw 1)))])
              (host-resize-now! (exact (round (* w s)))
                                (exact (round (* h s)))))))
        (host-window-show!)
        (set! *gpu-booting* #t)
        (gpu-boot-screen!)))
  (let ([world (host-make-world! root recorder-sources sources)])
    (set! *host-forked* #t)
    (fork-thread
     (lambda ()
       (platform-thread-interactive!)
       (guard (c [#t (display-condition c (console-error-port))
                     (newline (console-error-port))])
         (interaction-environment world)
         (host-load! world root sources)
         (load (string-append root "/" script)))
       (host-quit!))))
  (host-loop!))

;; Moves a script that loaded the tree (main.ss, a test) into "/": its later
;; forms evaluate there, as the world's.
(define (host-enter-world!) (interaction-environment *host-world*))
