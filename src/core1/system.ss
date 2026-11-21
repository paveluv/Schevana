;;; system.ss — core1's loop, boot and reload.

(defvar *running* #f)
(defvar *injected* '())   ; synthetic events waiting to be handled
;; events that came while a reload held the world, newest first
(defvar *held-events* '())
;; whether this step handled events: work that can wait (a text's rows
;; for its scroll bar) waits, so that input's frame comes first
(defvar *input-step?* #f)
(defvar *boot-ms* (now-ms))

;; (post-core1! thunk), from any thread: thunk runs on core1 at its next
;; step, after the events, in the order each thread posted it,
;; under safely (so a service's thunk calls an app's code under
;; safe-call). Lock-free: neither a post nor the step ever waits. The
;; fences hand core1 what the poster wrote before it posted: box-cas!
;; orders no memory, and ARM keeps no order of its own.
(defvar *core1-mail* (box '()))   ; thunks, the newest first

(define (post-core1! thunk)
  (memory-order-release)
  (let loop ()
    (let ([mail (unbox *core1-mail*)])
      (unless (box-cas! *core1-mail* mail (cons thunk mail)) (loop))))
  (core0-world-wake!))

(define (run-core1-mail!)
  (let loop ()
    (let ([mail (unbox *core1-mail*)])
      (cond [(null? mail)]
            [(box-cas! *core1-mail* mail '())
             (memory-order-acquire)
             (for-each (lambda (t) (safely 'jobs t)) (reverse mail))]
            [else (loop)]))))

;; Feed a synthetic event into the world, exactly as if core0 sent it:
;; (inject! '(mouse-down 100 100 left 1))
(define (inject! . events)
  (set! *injected* (append *injected* events)))

;; An event of the screen's, to the windows and the surfaces
;; (src/core1/wm.ss sets it); till then nothing takes it. Quitting is
;; the loop's own.
(define-hook (wm-event! ev) (void))

(define (handle-event! ev)
  (if (eq? (car ev) 'quit) (quit!) (wm-event! ev)))

;; A reload that failed or was killed: the world goes on as far as it got.
(define (reload-ended! msg)
  (set! *reloading* #f)
  (safely 'reload (lambda () (request-redraw!) (notify msg 'red))))

;; While a process loads the sources (*reloading*, set by load-sources!),
;; the world holds still: no event, timer, tick, frame or other process
;; runs half-loaded code, and the screen stays as it was. A reload whose
;; process was killed ends here.
(define (reload-holding?)
  (when (and *reloading* (not (memq (car *reloading*) *procs*)))
    (reload-ended! (format "Reload stopped while loading ~a"
                           (cdr *reloading*))))
  (and *reloading* #t))

;; Ctrl+C kills the reload and quitting quits; other events wait for it.
(define (hold-event! ev)
  (cond
    [(and (eq? (car ev) 'key-down) (eqv? (cadr ev) #\c)
          (memq 'ctrl (caddr ev)))
     (kill! (car *reloading*))]
    [(eq? (car ev) 'quit) (quit!)]
    [else (set! *held-events* (cons ev *held-events*))]))

;; Core0's events, the wait for them no work.
(define (pacer-screen-events wait-ms)
  (let* ([t (now-ns)] [events (screen-events wait-ms)])
    (pacer-waited! t)
    events))

;; One turn of the world, and what it took but its waits. Kept with
;; profiling off too, at a few clock reads a step: it says whether a user
;; of the desktop will see a tick missed.
(define (schevana-step! wait-ms . paced)
  (let ([start (now-ns)])
    (set! *pacer-waits* 0)
    (schevana-turn! wait-ms paced)
    (pacer-step-done! (- (now-ns) start))))

;; One turn of the world: events, mail (post-core1!), timers, a tick,
;; processes, and on a tick a frame if something asked for one. Paced
;; (core1's loop's), it ticks only when a tick is wanted (pacer-wanted?) and
;; due, and its processes run until the frame must be drawn for the next
;; tick; else (a test's) it always ticks, and its processes run 10 ms. The
;; profiler sums the steps between ticks into the next tick.
(define (schevana-turn! wait-ms paced)
  (with-profile-span 'step #f
    (let* ([hold? (reload-holding?)]
           [evs (append (if hold? '() (reverse *held-events*))
                        (pacer-screen-events (if (pair? *injected*) 0 wait-ms))
                        *injected*)])
      (unless hold? (set! *held-events* '()))
      (set! *injected* '())
      (set! *input-step?* (pair? evs))
      ;; input may change what's shown: the next tick looks
      (when (pair? evs) (frame-turn-soon!))
      (let each ([evs evs])
        (unless (null? evs)
          (let ([ev (car evs)])
            (safely 'event
                    (lambda () (if hold? (hold-event! ev) (handle-event! ev)))))
          (each (cdr evs)))))
    ;; frames core0 gave back, on its own thread since; with one thread,
    ;; they come back as they're published, and what it read back as it
    ;; was asked. One sent, the collections its turn held off.
    (if (core0-forked?)
        (safely 'render render-frames-back!)
        (render-answers!))
    (collector-after-sent!)
    (let ([ticked?
           (and (not (reload-holding?))
                (begin
                  (run-core1-mail!)
                  (safely 'timers run-timers!)
                  ;; reads asked for, before a tick publishes a frame: a
                  ;; tick comes only once none waits, so they go, however
                  ;; fast frames flow
                  (when (pair? *gpu-reads*) (safely 'readback gpu-reads-send!))
                  (let ([now (and (pair? paced) (now-ns))])
                    (and (or (not now)
                             (and (pacer-wanted?) (>= now (pacer-start))
                                  (not (gpu-frame-waiting?))))
                         (begin
                           (core0-trace! 22 0)
                           (collector-hold!)
                           (pacer-tick! now)
                           (frame-ticked! now)
                           #t)))))])
      ;; a step leads up to a tick only while one is wanted; one in a quiet
      ;; spell is its own, as a tick nothing asked for once was
      (set! *pacer-between?* (and (pair? paced) (not ticked?) (pacer-wanted?)))
      (unless (or ticked? (pacer-wanted?) *collector-after*)
        (collector-tick!))
      (safely 'procs
              (lambda () (run-procs! (if (null? paced) 10 (pacer-procs-ms)))))
      ;; a frame a tick at most
      ;; a tick nothing asked a frame of goes on with no guard
      ;; a frame drawn may have moved what's under a still pointer: the next
      ;; tick looks
      (when (and ticked? *dirty* (not (reload-holding?)))
        (set! *dirty* #f)
        (safely 'render render-frame!)
        (frame-turn-soon!))
      ;; the frame is out: the collections it held off, and the older
      ;; generations' passes, once core0 has sent it; input that asked for
      ;; no frame shows in none
      (when ticked?
        (collector-frame-out!)
        (unless *dirty* (frame-input-drop!)))
      ;; handles nothing holds any more are let go of, and compute runs and
      ;; writes no frame took go on their own
      (gpu-held-sweep!)
      (when (and (gpu-asks-pending?) (not (reload-holding?)))
        (safely 'render gpu-computes-send!))
      ;; reads asked for, guarded only then: a quiet step's guards are four
      (when (pair? *gpu-reads*) (safely 'readback gpu-reads-send!)))))

(define (schevana-run!)
  (set! *running* #t)
  (let loop ()
    (when *running*
      (schevana-step! (pacer-wait-ms) #t)
      (loop)))
  (screen-shutdown!))

(define (quit!) (set! *running* #f))

;; The run is over, and the process ends: at once on one thread; with core0
;; on its own, once it has closed the window, core1 waiting for it.
(define (schevana-end!)
  (if (core0-forked?)
      (let wait () (core0-world-wait! 1000) (wait))
      (exit 0)))

(define (uptime-ms) (- (now-ms) *boot-ms*))

;;; ------------------------------------------------------------------ boot

(define user-init-file
  (format "~a/.schevana.ss" (or (getenv "HOME") ".")))

(define (load-user-init!)
  (when (file-exists? user-init-file)
    (safely 'init (lambda () (load-file! user-init-file)))))

;; The user's own folder: lib for libraries, and kits, desktop, styles,
;; palettes, wallpapers and apps like the tree's (see source-folders).
(define user-directory (format "~a/.schevana.d" (or (getenv "HOME") ".")))

;; (import (acme math)) also finds acme/math.sls here.
(define user-library-directory (string-append user-directory "/lib"))

;; Make import search dir before Chez's own library directories. It need
;; not exist yet.
(define (add-library-directory! dir)
  (let ([dir (if (string-prefix? "~/" dir)
                 (string-append (or (getenv "HOME") "")
                                (substring dir 1 (string-length dir)))
                 dir)])
    (unless (exists (lambda (e) (equal? (if (pair? e) (car e) e) dir))
                    (library-directories))
      (library-directories (cons (cons dir dir) (library-directories))))
    dir))

;; (schevana-boot! 'sdl 1280 800 #t) starts full screen.
(define (schevana-boot! mode w h . fullscreen?)
  (apply screen-init! mode w h fullscreen?)
  (request-redraw!)
  (collector-settle!))

;;; ------------------------------------------------------------------ collector
;;; A pause is what survived since the last one, whatever the heap holds:
;;; whoever asks, only the young generation is collected, and the world
;;; waits in the oldest. Older ones are collected when core1 decides, while
;;; nobody is typing or, past a limit on their growth, anyway.

(define collector-young-quiet (* 8 1024 1024))
(define collector-young-limit (* 64 1024 1024))
(define collector-old-quiet (* 64 1024 1024))
(define collector-old-limit (* 512 1024 1024))

;; What the next rendezvous collects, (generation . target); #f, the young.
(defvar *collector-pass* #f)
;; A frame turn, from its tick till core0 has sent its frame, holds the
;; young generation's collections off: one asked for then waits till after,
;; where its pause costs the frame nothing, the heap growing meanwhile by
;; what the turn allocates. A collection stops core0 too: right at the
;; publish, a long one held the frame past its latch. Whether a turn holds
;; them, whether one was asked for, and the frame they wait to see sent
;; (#f, none).
(defvar *collector-holding?* #f)
(defvar *collector-held?* #f)
(defvar *collector-after* #f)
(defvar *collector-check-ms* 0)
(defvar *collector-input-ms* 0)
;; generations 2 and 3, and the GPU bytes made, when last collected
(defvar *collector-old-kept* 0)

(define (collector-collect!)
  (if (collector-declining?)
      (set! *collector-held?* #t)
      (let ([pass *collector-pass*])
        (set! *collector-pass* #f)
        ;; every thread waits for it: traced, by the generation collected
        (core0-trace! 28 (if pass (car pass) 0))
        (if pass (collect (car pass) (cdr pass)) (collect 0 1))
        (core0-trace! 29 0))))

;; A request now is held off: a frame turn's, and no pass of core1's asked.
(define (collector-declining?)
  (and *collector-holding?* (not *collector-pass*)))

(define (collector-hold!) (set! *collector-holding?* #t))

;; A frame turn ended: what it held off waits for its frame, the one drawn
;; last, to be sent; for the earliest such, if one waits already, so that
;; frames sent always behind the next turn hold nothing off for long.
(define (collector-frame-out!)
  (unless *collector-after* (set! *collector-after* *frame-number*))
  (collector-after-sent!))

;; That frame sent (core0 gave it back; with one thread, as it was
;; published): what its turn held off, now.
(define (collector-after-sent!)
  (when (and *collector-after* (>= *frame-back* *collector-after*))
    (set! *collector-after* #f)
    (core0-trace! 25 0)
    (collector-after-frame!)
    (core0-trace! 26 0)))

;; After a frame turn: the collection it held off, if one was asked for,
;; then the older generations' passes.
(define (collector-after-frame!)
  (set! *collector-holding?* #f)
  (when *collector-held?*
    (set! *collector-held?* #f)
    (collect-rendezvous))
  (collector-tick!))

(defvar *collector-handler*
  (let ([handler (lambda () (collector-collect!))])
    (collect-trip-bytes (* 2 1024 1024))
    (collect-request-handler handler)
    handler))

(define (collector-pass! generation target)
  (set! *collector-pass* (cons generation target))
  (collect-rendezvous))

(define (collector-old) (+ (bytes-allocated 2) (bytes-allocated 3)))

;; The old generations with the GPU bytes made: a dropped buffer or image is
;; let go of only once its handle's generation is collected, and its bytes,
;; which the collector doesn't see, bring that on as old growth would.
(define (collector-grown) (+ (collector-old) *gpu-bytes-made*))

;; The world into the oldest generation, at boot and after a reload. Not
;; static: each reload would then leak the world it replaced.
(define (collector-settle!)
  (collector-pass! 4 4)
  (set! *collector-old-kept* (collector-grown)))

;; On a tick: twice a second, an older generation if it has grown enough.
(define (collector-tick!)
  (let ([now (now-ms)])
    (when *input-step?* (set! *collector-input-ms* now))
    (when (>= now *collector-check-ms*)
      (set! *collector-check-ms* (+ now 500))
      (let ([quiet? (>= (- now *collector-input-ms*) 1000)])
        (cond
          [(>= (- (collector-grown) *collector-old-kept*)
               (if quiet? collector-old-quiet collector-old-limit))
           (collector-pass! 3 3)
           (set! *collector-old-kept* (collector-grown))]
          [(>= (bytes-allocated 1)
               (if quiet? collector-young-quiet collector-young-limit))
           (collector-pass! 1 2)])))))

;;; ------------------------------------------------------------------ sources
;;; The core is main.ss's list, in "/core1". The world, in "/", is a copy
;;; of src/base.ss and the folders, one definition per file, each folder's
;;; files in file-name order: drop a file in and it loads at the next boot
;;; or (reload!). A real session then loads the same folders from
;;; ~/.schevana.d.

;; The folders after the core, in load order.
(define source-folders
  '("kits" "services" "desktop" "styles" "palettes" "wallpapers" "apps"))

;; main.ss turns this on: a real session loads the user's folders too, at
;; boot and at every (reload!). The tests never do.
(defvar *user-folders?* #f)

;; A file name relative to the tree, or an absolute one (the user's).
(define (source-path f)
  (if (path-absolute? f) f (string-append *schevana-root* "/" f)))

;; The .ss files in the folder dir, by name; none if it does not exist.
;; Names starting with a dot (editors' lock files) are left out.
(define (folder-sources dir)
  (let ([path (source-path dir)])
    (if (file-directory? path)
        (map (lambda (f) (string-append dir "/" f))
             (sort string<?
                   (filter (lambda (f)
                             (and (string-suffix? ".ss" f)
                                  (not (string-prefix? "." f))))
                           (directory-list path))))
        '())))

(define (user-folder-files)
  (if *user-folders?*
      (apply append
             (map (lambda (d)
                    (folder-sources (string-append user-directory "/" d)))
                  source-folders))
      '()))

(define (folder-files)
  (append (apply append (map folder-sources source-folders))
          (user-folder-files)))

;; The world's own files, in load order: a copy of the basics, then the
;; folders.
(define (world-sources) (cons "src/base.ss" (folder-files)))

;; Every source file, the core's and the world's, in load order. The REPL's
;; docs and the tests read this list.
(define (source-files) (append *schevana-core1-sources* (world-sources)))

;; The text of every source as it was loaded (or, from a REPL, evaluated),
;; by its name: a file's path, or what the REPL calls its input. What reads
;; the sources (the REPL's descriptions) reads these, not the files as they
;; are now, so that it tells of the code that runs. (serial . text), the
;; serial counting the texts kept.
(defvar *source-texts* (make-hashtable string-hash string=?))
(defvar *source-serial* 0)

(define (keep-source-text! name text)
  (set! *source-serial* (+ *source-serial* 1))
  (hashtable-set! *source-texts* name (cons *source-serial* text)))

(define (file-text path) (call-with-input-file path get-string-all))

;; Loads a file, keeping its text (read just before load reads it).
(define (load-file! path)
  (keep-source-text! path (file-text path))
  (load path))

;; Loads an app's file (one in an apps folder, the tree's or the user's):
;; into the world, until services/grant.ss sets it to give each app a
;; sandbox of its own.
(define-hook (app-load! path) (load-file! path))

(define (load-source f)
  (let ([path (source-path f)])
    (if (equal? (path-last (path-parent path)) "apps")
        (app-load! path)
        (load-file! path))))

;; Loads files into the world (from a private REPL too), or into env
;; ("/core1", the core's). Run as a process (the launcher's "Reload
;; sources", (reload!) in a REPL), it names itself and the file in
;; *reloading* until it ends, so the world holds still meanwhile
;; (schevana-step!), yet it is still preempted and Ctrl+C kills it. Not
;; with dynamic-wind: an engine runs its exits at every preemption.
(define (load-sources! files . env)
  (let* ([p (current-proc)]
         [outer? (and p (not (and *reloading* (eq? (car *reloading*) p))))])
    (parameterize ([interaction-environment
                    (if (pair? env) (car env) *world-env*)])
      (guard (c [outer? (reload-ended!
                         (format "Reload failed in ~a: ~a"
                                 (cdr *reloading*) (condition->string c)))
                        (raise c)])
        (for-each (lambda (f i)
                    (when p (set! *reloading* (cons p f)))
                    (load-source f)
                    ;; the boot screen's bar
                    (core0-world-loaded! (+ i 1) (length files)))
                  files (iota (length files)))
        (when outer? (set! *reloading* #f))))))

;; The user's folders, after the built-in ones (main.ss, before the saved
;; theme, which may name a user's style or palette). One file at a time, so
;; that one which raises is named in its toast and the rest still load.
(define (load-user-folders!)
  (set! *user-folders?* #t)
  (add-library-directory! user-library-directory)
  (for-each (lambda (f) (safely f (lambda () (load-sources! (list f)))))
            (user-folder-files)))

;; The core's source files main.ss lists, read from the file itself so
;; that a reload picks up new ones.
(define (read-source-list)
  (guard (c [#t *schevana-core1-sources*])
    (call-with-input-file (string-append *schevana-root* "/main.ss")
      (lambda (p)
        (let loop ()
          (let ([x (read p)])
            (cond
              [(eof-object? x) *schevana-core1-sources*]
              [(and (list? x) (= (length x) 3) (eq? (car x) 'define)
                    (eq? (cadr x) '*schevana-core1-sources*)
                    (pair? (caddr x)) (eq? (car (caddr x)) 'quote)
                    (list? (cadr (caddr x))))
               (cadr (caddr x))]
              [else (loop)])))))))

;; Re-read every source file: the core's into "/core1", then the world's
;; into "/", given first what the core exports that it wasn't before; what
;; it was keeps its forwarder. Code changes take effect; state declared
;; with defvar (windows, theme, processes...) survives.
(define (reload!)
  (let ([files (read-source-list)] [before (core1-exported)])
    (set! *schevana-core1-sources* files)
    (load-sources! files *core1-env*)
    (exports-install! (map (lambda (clause)
                             (cons (car clause)
                                   (remp (lambda (e) (memq (car e) before))
                                         (cdr clause))))
                           core1-exports)
                      *core1-env* 'world *world-env*))
  (load-world!)
  (request-redraw!)
  (collector-settle!)
  (notify "Sources reloaded" 'green))

;; Core0 loads the core before this file can keep its texts: kept now,
;; moments after (a reload keeps them as it loads them).
(at-load
 (for-each (lambda (f)
             (let ([path (source-path f)])
               (unless (hashtable-contains? *source-texts* path)
                 (keep-source-text! path (file-text path)))))
           *schevana-core1-sources*))

;; The world's files into "/" (core1-boot!, reload!). The folders may
;; import the libraries shipped in lib/.
(define (load-world!)
  (add-library-directory! (string-append *schevana-root* "/lib"))
  (load-sources! (world-sources)))
