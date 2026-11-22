;;; tests/units/reload.ss — what (reload!) reads, and what it leaves.

(check "reload leaves core0 as it booted, its procedures the same; a \
        library of the core's whose file didn't change stays as it was, \
        and the world still has what the core gives it"
       (let ([present gpu-publish!]
             [theme-was (eval 'theme core-env)])
         (reload!)
         (and (eq? gpu-publish! present)
              (eq? (eval 'theme core-env) theme-was)
              (eq? (eval 'theme *world-env*) theme-was)
              (for-all (lambda (n)
                         (guard (c [#t #f])
                           (or (top-level-bound? n *world-env*)
                               (top-level-syntax? n *world-env*))))
                       (core1-exported)))))

;;; Reloading as a process.

;; Reloading as a process (the launcher's "Reload sources", a REPL) holds
;; the world still until it ends, but stays a process. These reload a copy
;; of the tree with a folder of its own that auto-loads, apps/, its one
;; file apps/zz-last.ss holding form, the last to load. The copy holds
;; what the world loads as files, src/ (the basics); its libraries are
;; found by their names. tree-copy-done! puts the tree back.
(define tree-copy-auto-loads '())

(define (tree-copy-with name form)
  (let ([dir (string-append out-dir "/" name)])
    (system (format "rm -rf '~a' && mkdir -p '~a/apps' && cp -r '~a' '~a'"
                    dir dir (string-append *schevana-root* "/src") dir))
    (let ([p (open-output-file (string-append dir "/apps/zz-last.ss") 'append)])
      (write form p)
      (newline p)
      (close-port p))
    (set! tree-copy-auto-loads *auto-loads*)
    (set! *auto-loads* (list (path-full (string-append dir "/apps"))))
    dir))

(define (tree-copy-done! root)
  (set! *schevana-root* root)
  (set! *auto-loads* tree-copy-auto-loads))

;; A long load: until it ends no frame, timer, tick, handler or other
;; process runs, and events that come meanwhile are handled after it, in
;; order. The slow form notes what had run before and after its 0.6 s;
;; a process that comes after the reload in each round counts its slices
;; during it.
(define probe-counts (lambda () '()))
(define probe-seen '())
(let* ([root *schevana-root*] [ticks 0] [draws 0] [timers 0] [slices 0]
       [keys '()] [sent '()] [n 0] [done? #f] [late-held 0]
       [probe (open-window "Probe" 'size '(200 . 100)
                           'open window-frame-soon!
                           'frame (lambda (win at)
                                    (window-frame-soon! win)
                                    (set! ticks (+ ticks 1)))
                           'draw (lambda (win w h) (set! draws (+ draws 1)))
                           'key (lambda (win key mods)
                                  (set! keys (cons key keys))))]
       [bystander (spawn "bystander"
                         (lambda ()
                           (let loop ()
                             (set! slices (+ slices 1))
                             (yield)
                             (loop))))])
  (set! probe-counts (lambda () (list ticks draws timers slices (length keys))))
  (let again ()
    (after 5 (lambda () (set! timers (+ timers 1)) (unless done? (again)))))
  (steps 2)
  (set! *schevana-root*
    (tree-copy-with "slow-tree"
      '(begin (set! probe-seen (list (probe-counts)))
              (let ([t (+ (real-time) 600)])
                (let loop () (when (< (real-time) t) (loop))))
              (set! probe-seen (cons (probe-counts) probe-seen)))))
  (let* ([p (spawn "reload" reload!)]
         [late (spawn "late"
                      (lambda ()
                        (let loop ()
                          (when *reloading* (set! late-held (+ late-held 1)))
                          (yield)
                          (loop))))])
    (let loop ()
      (when (and (memq p (procs)) (< n 5000))
        (let ([k (integer->char (+ 97 (mod n 26)))])
          (inject! (list 'key-down k '()))
          (set! sent (cons k sent)))
        (set! n (+ n 1))
        (schevana-step! 0)
        (loop)))
    (kill! late))
  (tree-copy-done! root)
  (steps 3)
  (check (format "a long reload run as a process holds the world still (~a \
                  steps; ticks, draws, timers, other process, keys before and \
                  after: ~s; slices of a later process during it: ~a)"
                 n (reverse probe-seen) late-held)
         (and (> n 10) (= (length probe-seen) 2)
              (equal? (car probe-seen) (cadr probe-seen)) (= late-held 0)
              (> (length keys) 0) (equal? keys sent)
              (> ticks (car (car probe-seen)))))
  (set! done? #t)
  (kill! bystander)
  (close-window! probe)
  (set! *toasts* '())
  (steps 1))

;; A source whose top level loops: the world does not freeze (its steps go
;; on, the reload alive; the longest is printed, not bounded: how long a
;; step may take is the bench's), Ctrl+C kills the reload, a toast names
;; the file, and the world goes on.
(define reload-reached #f)
(let ([root *schevana-root*] [worst 0] [n 0] [ticks 0])
  (set! *schevana-root*
    (tree-copy-with "loop-tree"
      '(begin (set! reload-reached #t) (let loop () (loop)))))
  (let ([p (spawn "reload" reload!)]
        [w (open-window "Ticks" 'open window-frame-soon!
                                'frame (lambda (win at)
                                         (window-frame-soon! win)
                                         (set! ticks (+ ticks 1))))])
    (define (step!)
      (let ([t0 (real-time)])
        (schevana-step! 0)
        (set! n (+ n 1))
        (set! worst (max worst (- (real-time) t0)))))
    (let loop () (unless (or reload-reached (> n 3000)) (step!) (loop)))
    (do ([i 0 (+ i 1)]) ((= i 20)) (step!))
    (let ([alive? (and (memq p (procs)) #t)] [t0 ticks])
      (test-press! #\c 'ctrl)
      (steps 3)
      (tree-copy-done! root)
      (check (format "a reload whose source loops does not freeze the world \
                      (~a steps, the longest ~a ms), Ctrl+C kills it and a \
                      toast names the file"
                     n worst)
             (and reload-reached alive? (not (memq p (procs)))
                  (not *reloading*) (> ticks t0)
                  (exists (lambda (t)
                            (string-contains-ci? (vector-ref t 1)
                                                 "apps/zz-last.ss"))
                          *toasts*))))
    (close-window! w)
    (set! *toasts* '())
    (steps 1)))

;; A source that raises: the reload ends there and a toast names the file,
;; also when the process catches the error and carries on.
(let ([root *schevana-root*] [caught? #f])
  (set! *schevana-root*
    (tree-copy-with "error-tree" '(error 'smoke "on purpose")))
  (let ([p (spawn "reload"
                  (lambda ()
                    (guard (c [#t (set! caught? #t)]) (reload!))
                    (let loop () (yield) (loop))))])
    (let loop ([n 0])
      (unless (or caught? (> n 3000)) (schevana-step! 0) (loop (+ n 1))))
    (steps 2)
    (tree-copy-done! root)
    (check "a reload whose source raises ends there, and a toast names the file"
           (and caught? (memq p (procs)) (not (reload-holding?))
                (exists (lambda (t)
                          (string-contains-ci? (vector-ref t 1)
                                               "failed in apps/zz-last.ss"))
                        *toasts*)))
    (kill! p)
    (set! *toasts* '())
    (steps 1)))

;; The hold ends when the loading does, not when the process does: a
;; process that goes on after (reload!) lets the world run.
(let ([state 'unset] [ticks 0])
  (let ([p (spawn "reload+work"
                  (lambda ()
                    (reload!)
                    (set! state *reloading*)
                    (let loop () (yield) (loop))))]
        [w (open-window "Ticks" 'open window-frame-soon!
                                'frame (lambda (win at)
                                         (window-frame-soon! win)
                                         (set! ticks (+ ticks 1))))])
    (let loop ([n 0])
      (when (and (eq? state 'unset) (< n 3000))
        (schevana-step! 0)
        (loop (+ n 1))))
    (let ([t0 ticks])
      (steps 3)
      (let ([alive? (and (memq p (procs)) #t)] [ran (- ticks t0)])
        (kill! p)
        (steps 2)
        (check (format "a process that goes on after (reload!) does not hold \
                        the world (*reloading* ~s, ~a ticks, toasts ~s)"
                       state ran (map (lambda (t) (vector-ref t 1)) *toasts*))
               (and (not state) alive? (> ran 0) (not *reloading*)
                    (exists (lambda (t)
                              (equal? (vector-ref t 1) "Sources reloaded"))
                            *toasts*)
                    (not (exists (lambda (t)
                                   (string-contains-ci? (vector-ref t 1)
                                                        "stopped"))
                                 *toasts*))))))
    (close-window! w)
    (set! *toasts* '())
    (steps 1)))

;; (reload!) in a world REPL reloads the world, not the REPL: its toast
;; says it did.
(let ([p (repl 'world)])
  (set! *toasts* '())
  (steps 2)
  (test-type! "(reload!)")
  (test-press! 'return)
  (let ([reloaded?
         (test-wait 10000
           (lambda ()
             (exists (lambda (t) (equal? (vector-ref t 1) "Sources reloaded"))
                     *toasts*)))])
    (test-wait 10000 (lambda () (not (repl-proc (window-ref p 'state)))))
    ;; the REPL's own: the world's styles must not see it
    (test-type! "(define (title-height) 99)")
    (test-press! 'return)
    (test-wait 10000 (lambda () (not (repl-proc (window-ref p 'state)))))
    (let ([w (open-window "Plain" 'size '(260 . 120) 'pos '(300 . 200))])
      (let-values ([(l t r b) (frame-insets w)])
        (check "(reload!) in a world REPL reloads the world, whose \
                styles keep the world's names"
               (and reloaded? (= t (title-height)) (not (= t 99)))))
      (close-window! w)))
  (close-window! p)
  (set! *toasts* '())
  (steps 1))

;; The edition's reload of the libraries: the library edition's, or the
;; hacker edition's, which splices them again (src/hacker.ss).
(define (test-reload-libraries! held)
  (if test-hacker?
      ((eval 'hacker-reload-libraries!) held)
      (reload-libraries! held)))

;;; Libraries reloaded in place (reload-libraries!, which reload! runs
;;; first): one whose file changed is evaluated again, then each that
;;; imports it, and an environment that imported them imports them again.
;;; Its states stay; its made values and hooks are made again, and what
;;; sets a hook sets it again; one held stays as it was. Three libraries of
;;; the test's own, in a folder of out/.
(let* ([dir (string-append out-dir "/reload-libraries")]
       [file (lambda (name)
               (string-append dir "/units/reload/" name ".sls"))]
       [write! (lambda (name form)
                 (call-with-output-file (file name)
                   (lambda (p) (write form p) (newline p))
                   'replace))]
       [a (lambda (value)
            `(library (units reload a)
               (export ura-val *ura-count* ura-bump! ura-hook ura-made)
               (import (chezscheme) (schevana base))
               (define-state *ura-count* 0)
               (define-made ura-made (list 'made))
               (define-hook (ura-hook) 'default)
               (define (ura-val) ',value)
               (define (ura-bump!) (set! *ura-count* (+ *ura-count* 1)))))]
       [c (lambda (value)
            `(library (units reload c)
               (export urc-val)
               (import (chezscheme))
               (define (urc-val) ',value)))]
       [e (copy-environment (scheme-environment) #t)]
       [in-e (lambda (form) (eval form e))]
       [held '((units reload c))])
  (system (format "rm -rf '~a' && mkdir -p '~a/units/reload'" dir dir))
  (write! "a" (a 'old))
  (write! "b" '(library (units reload b)
                 (export urb-val)
                 (import (chezscheme) (schevana base) (units reload a))
                 (set-hook! (ura-hook) 'from-b)
                 (define (urb-val) (list (ura-val) *ura-count*))))
  (write! "c" (c 'held))
  (parameterize ([library-directories (cons (cons dir dir)
                                            (library-directories))])
    (reload-import! e '(units reload a) '(units reload b) '(units reload c))
    (in-e '(begin (ura-bump!) (ura-bump!)))
    (let* ([before (in-e '(urb-val))]
           [made (in-e 'ura-made)]
           [none (test-reload-libraries! held)])
      (write! "a" (a 'new))
      (write! "c" (c 'changed))
      (let ([order (test-reload-libraries! held)])
        (check "a library whose file changed is evaluated again, then the \
                one that imports it; the environment that imported them \
                has the new ones, the state as it was, the made value made \
                again and the hook set again; the held one stays, and \
                nothing changed reloads nothing"
               (and (equal? before '(old 2))
                    (null? none)
                    (equal? order '((units reload a) (units reload b)))
                    (equal? (in-e '(urb-val)) '(new 2))
                    (equal? (in-e '(ura-val)) 'new)
                    (eq? (in-e '(ura-hook)) 'from-b)
                    (not (eq? (in-e 'ura-made) made))
                    (eq? (in-e '(urc-val)) 'held)
                    (equal? (cdr (assq 'last (inspect-reload))) order)))))))
