;;; (schevana core loop) — core1's loop: its step and run, the screen's boot,
;;; and the collector's passes, which it times.

(library (schevana core loop)
  (export
    *input-step?* post-core1! wm-event! loop-stepped! reload-ended!
    schevana-run! quit! schevana-end! uptime-ms user-directory
    user-library-directory path-full add-library-directory! schevana-boot!
    collector-declining? collector-settle! collector-tick! core1-run loop-main
    inject!)
  (import (chezscheme)
          (only (schevana base) define-hook define-made define-state
                library-layer set-hook! string-prefix? string-split)
          (only (schevana core0) core0-forked? core0-run! core0-trace!
                core0-world-wait-ns! core0-world-wake! gpu-frame-waiting?)
          (only (schevana core platform) now-ms now-ns)
          (only (schevana core processes) *dirty* *procs* *reloading*
                core1-thread! kill! notify request-redraw! run-procs!
                run-timers! safely with-profile-span)
          (only (schevana core gpu) *gpu-bytes-made* *gpu-reads*
                gpu-asks-pending? gpu-computes-send! gpu-held-sweep!
                gpu-reads-send! gpu-wakes)
          (only (schevana core pacer) *frame-back* *frame-number*
                *pacer-between?* *pacer-waits* frame-input-drop! frame-ticked!
                frame-turn-soon! pacer-procs-ms pacer-start pacer-step-done!
                pacer-tick! pacer-wait-ms pacer-waited! pacer-wanted?
                pacer2? render-answers! render-frame! render-frames-back!
                wm-tick!)
          (only (schevana core pacer2) pacer2-begin? pacer2-procs-ms
                pacer2-wait-ns)
          (only (schevana core screen) fullscreen? screen-events screen-init!
                screen-shutdown!))

  (library-layer core)

  (define-state *running* #f)
  (define-state *injected* '())   ; synthetic events waiting to be handled
  ;; events that came while a reload held the world, newest first
  (define-state *held-events* '())
  ;; whether this step handled events: then work that can wait (a text's
  ;; rows for its scroll bar) waits, so that the input's frame comes first
  (define-state *input-step?* #f)
  (define-state *boot-ms* (now-ms))

  ;; (post-core1! thunk), from any thread: thunk runs on core1 at its next
  ;; step, after the events, in the order each thread posted it, under
  ;; safely (so a service's thunk must call an app's code under safe-call
  ;; itself). It is lock-free: neither a post nor the step ever waits. The
  ;; fences hand core1 what the poster wrote before it posted, since
  ;; box-cas! orders no memory, and ARM keeps no order of its own.
  (define-state *core1-mail* (box '()))   ; thunks, the newest first

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

  ;; Feeds a synthetic event into the world, exactly as if core0 sent it:
  ;; (inject! '(mouse-down 100 100 left 1))
  (define (inject! . events)
    (set! *injected* (append *injected* events)))

  ;; Hands an event of the screen's to the windows and the surfaces.
  ;; (schevana core windows) sets it; until then nothing takes the event.
  ;; Quitting is the loop's own.
  (define-hook (wm-event! ev) (void))

  ;; Told at each step's end whether the step was quiet: it drew no frame
  ;; and none is wanted. (schevana core sources) sets it, to load the parts
  ;; of the world that wait for such a step; until then it does nothing.
  (define-hook (loop-stepped! quiet?) (void))

  (define (handle-event! ev)
    (if (eq? (car ev) 'quit) (quit!) (wm-event! ev)))

  ;; Ends a reload that failed or was killed: the world goes on as far as
  ;; the reload got.
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

  ;; Returns core0's events; the time spent waiting for them (wait, in ns,
  ;; or #f for until woken) doesn't count as work (pacer-waited!).
  (define (pacer-screen-events wait)
    (let* ([t (now-ns)] [events (screen-events wait)])
      (pacer-waited! t)
      events))

  ;; Runs one turn of the world, after waiting up to wait ns for core0's
  ;; events (#f: until it is woken), and records what it took, apart from
  ;; its waits (pacer-step-done!). This is kept even with profiling off, at
  ;; the cost of a few clock reads a step, because it tells whether a user
  ;; of the desktop will see a tick missed.
  (define (schevana-step! wait)
    (let ([start (now-ns)])
      (set! *pacer-waits* 0)
      (schevana-turn! wait)
      (pacer-step-done! (- (now-ns) start))))

  ;; One turn of the world: events, mail (post-core1!), timers, a tick,
  ;; processes, and on a tick a frame if something asked for one. It ticks
  ;; only when the pacer in use says (pacer2?): a tick wanted (pacer-wanted?)
  ;; and due, or the second pacer's begin (pacer2-begin?); and its
  ;; processes run until the frame must be drawn for the next tick. The
  ;; profiler sums the steps between ticks into the next tick.
  (define (schevana-turn! wait)
    (with-profile-span 'step #f
      (let* ([hold? (reload-holding?)]
             [evs (append (if hold? '() (reverse *held-events*))
                          (pacer-screen-events
                           (if (pair? *injected*) 0 wait))
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
                      (lambda ()
                        (if hold? (hold-event! ev) (handle-event! ev)))))
            (each (cdr evs)))))
      ;; the frames core0 gave back since, from its own thread; with one
      ;; thread, frames come back as they are published, and what core0 read
      ;; back comes as it was asked for. Once a frame is sent, the
      ;; collections its turn held off run.
      (if (core0-forked?)
          (safely 'render render-frames-back!)
          (render-answers!))
      (collector-after-sent!)
      (let ([ticked?
             (and (not (reload-holding?))
                  (begin
                    (run-core1-mail!)
                    (safely 'timers run-timers!)
                    ;; the reads asked for go before a tick publishes a
                    ;; frame: a tick comes only once no frame waits, so they
                    ;; go however fast frames flow
                    (when (pair? *gpu-reads*)
                      (safely 'readback gpu-reads-send!))
                    (let ([now (now-ns)])
                      (if (pacer2?)
                          (and (pacer2-begin? now)
                               (begin
                                 (collector-hold!)
                                 (safely 'tick wm-tick!)
                                 (frame-ticked! now)
                                 #t))
                          (and (pacer-wanted?) (>= now (pacer-start))
                               (not (gpu-frame-waiting?))
                               (begin
                                 (core0-trace! 22 0)
                                 (collector-hold!)
                                 (pacer-tick! now)
                                 (frame-ticked! now)
                                 #t))))))])
        ;; a step leads up to a tick only while a tick is wanted; a step in a
        ;; quiet spell counts on its own
        (set! *pacer-between?* (and (not ticked?) (pacer-wanted?)))
        (unless (or ticked? (pacer-wanted?) *collector-after*)
          (collector-tick!))
        (loop-stepped! (not (or ticked? (pacer-wanted?))))
        (safely 'procs
                (lambda ()
                  (run-procs!
                   (if (pacer2?) (pacer2-procs-ms) (pacer-procs-ms)))))
        ;; at most one frame per tick; a tick that nothing asked a frame of
        ;; goes on without a guard. A frame drawn may have moved what is
        ;; under a still pointer, so the next tick looks.
        (when (and ticked? *dirty* (not (reload-holding?)))
          (set! *dirty* #f)
          (safely 'render render-frame!)
          (frame-turn-soon!))
        ;; the frame is out: the collections it held off, and the older
        ;; generations' passes, run once core0 has sent it; input that asked
        ;; for no frame shows in none
        (when ticked?
          (collector-frame-out!)
          (unless *dirty* (frame-input-drop!)))
        ;; handles that nothing holds any more are let go of, and compute
        ;; runs and writes that no frame took go on their own
        (gpu-held-sweep!)
        (when (and (gpu-asks-pending?) (not (reload-holding?)))
          (safely 'render gpu-computes-send!))
        ;; the reads asked for, guarded only when there are some, to keep a
        ;; quiet step's guards few
        (when (pair? *gpu-reads*) (safely 'readback gpu-reads-send!)))))

  (define (schevana-run!)
    (set! *running* #t)
    (let loop ()
      (when *running*
        (schevana-step! (if (pacer2?)
                            (pacer2-wait-ns)
                            (* 1000000 (pacer-wait-ms))))
        (loop)))
    (screen-shutdown!))

  (define (quit!) (set! *running* #f))

  ;; Ends the process once the run is over: at once on one thread; with
  ;; core0 on a thread of its own, once core0 has closed the window, while
  ;; core1 waits for it.
  (define (schevana-end!)
    (if (core0-forked?)
        (let wait () (core0-world-wait-ns! #f) (wait))
        (exit 0)))

  (define (uptime-ms) (- (now-ms) *boot-ms*))

  ;;; ---------------------------------------------------------------- boot

  ;; The user's own folder: lib for libraries, and kits, services, styles,
  ;; palettes, wallpapers, desktop and apps like the tree's (see
  ;; source-folders).
  (define-made user-directory
    (format "~a/.schevana.d" (or (getenv "HOME") ".")))

  ;; (import (acme math)) also finds acme/math.sls here.
  (define-made user-library-directory (string-append user-directory "/lib"))

  ;; Returns path in full, as a path is kept once it is given: ~ stands for
  ;; the home folder, a relative path starts from the current folder, . and
  ;; .. are resolved, and there is no slash at the end.
  (define (path-full path)
    (let* ([p (cond [(string-prefix? "~/" path)
                     (string-append (or (getenv "HOME") "")
                                    (substring path 1 (string-length path)))]
                    [(path-absolute? path) path]
                    [else (string-append (current-directory) "/" path)])]
           [parts (let loop ([ps (string-split p #\/)] [acc '()])
                    (cond [(null? ps) (reverse acc)]
                          [(member (car ps) '("" ".")) (loop (cdr ps) acc)]
                          [(equal? (car ps) "..")
                           (loop (cdr ps) (if (pair? acc) (cdr acc) acc))]
                          [else (loop (cdr ps) (cons (car ps) acc))]))])
      (if (null? parts)
          "/"
          (apply string-append (map (lambda (s) (string-append "/" s))
                                    parts)))))

  ;; Makes import search dir, in full, before Chez's own library
  ;; directories, and returns dir in full. It need not exist yet.
  (define (add-library-directory! dir)
    (let ([dir (path-full dir)])
      (unless (exists (lambda (e) (equal? (path-full (if (pair? e) (car e) e))
                                          dir))
                      (library-directories))
        (library-directories (cons (cons dir dir) (library-directories))))
      dir))

  ;; (schevana-boot! 'sdl 1280 800 #t) starts full screen.
  (define (schevana-boot! mode w h . fullscreen?)
    (apply screen-init! mode w h fullscreen?)
    (request-redraw!)
    (collector-settle!))

  ;;; ---------------------------------------------------------------- collector
  ;;; A pause costs what survived since the last one, whatever the heap
  ;;; holds: whoever asks, only the young generation is collected, and the
  ;;; world waits in the oldest. Older generations are collected when core1
  ;;; decides: while nobody is typing, or anyway once their growth passes a
  ;;; limit.

  (define-made collector-young-quiet (* 8 1024 1024))
  (define-made collector-young-limit (* 64 1024 1024))
  (define-made collector-old-quiet (* 64 1024 1024))
  (define-made collector-old-limit (* 512 1024 1024))

  ;; What the next rendezvous collects, (generation . target), or #f for the
  ;; young generation.
  (define-state *collector-pass* #f)
  ;; A frame turn, from its tick until core0 has sent its frame, holds off
  ;; the young generation's collections: one asked for then waits until
  ;; after, where its pause costs the frame nothing, while the heap grows by
  ;; what the turn allocates. A collection stops core0 too, so a long one
  ;; right at the publish would hold the frame past its latch. These say
  ;; whether a turn holds collections off, whether one was asked for, and
  ;; which frame they wait to see sent (#f for none).
  (define-state *collector-holding?* #f)
  (define-state *collector-held?* #f)
  (define-state *collector-after* #f)
  (define-state *collector-check-ms* 0)
  (define-state *collector-input-ms* 0)
  ;; the size of generations 2 and 3, plus the GPU bytes made, when they
  ;; were last collected
  (define-state *collector-old-kept* 0)

  (define (collector-collect!)
    (if (collector-declining?)
        (set! *collector-held?* #t)
        (let ([pass *collector-pass*])
          (set! *collector-pass* #f)
          ;; every thread waits for it, so it is traced, with the generation
          ;; collected
          (core0-trace! 28 (if pass (car pass) 0))
          (if pass (collect (car pass) (cdr pass)) (collect 0 1))
          (core0-trace! 29 0))))

  ;; Whether a request now is held off: during a frame turn, when core1
  ;; asked for no pass.
  (define (collector-declining?)
    (and *collector-holding?* (not *collector-pass*)))

  (define (collector-hold!) (set! *collector-holding?* #t))

  ;; Returns whether the frame a turn publishes should ask core0 to wake
  ;; core1 as it gives the frame back: a collection waits for that, or the
  ;; older generations' check is due, and runs while the GPU works.
  ;; Otherwise the second pacer hears of the frame at its GPU-done.
  (define (collector-waiting?)
    (or *collector-held?* (>= (now-ms) *collector-check-ms*)))

  ;; The wakes that core1 asks of core0 with each frame it publishes: the
  ;; first pacer's tick waits for core0 to take the last frame, and hears of
  ;; it then and as it comes back; the second's turn waits for the last
  ;; frame's GPU work to be seen done, and hears of the frame's way back
  ;; only when a collection waits for it.
  (set-hook! (gpu-wakes)
    (cond [(not (pacer2?)) '(taken back)]
          [(collector-waiting?) '(done back)]
          [else '(done)]))

  ;; A frame turn ended: what it held off waits for its frame, the one drawn
  ;; last, to be sent. If something already waits for an earlier frame, it
  ;; keeps waiting for that one, so that frames always sent behind the next
  ;; turn don't hold anything off for long.
  (define (collector-frame-out!)
    (unless *collector-after* (set! *collector-after* *frame-number*))
    (collector-after-sent!))

  ;; Once that frame is sent (core0 gave it back; with one thread, as it was
  ;; published), runs what its turn held off.
  (define (collector-after-sent!)
    (when (and *collector-after* (>= *frame-back* *collector-after*))
      (set! *collector-after* #f)
      (core0-trace! 25 0)
      (collector-after-frame!)
      (core0-trace! 26 0)))

  ;; After a frame turn, runs the collection it held off, if one was asked
  ;; for, then the older generations' passes.
  (define (collector-after-frame!)
    (set! *collector-holding?* #f)
    (when *collector-held?*
      (set! *collector-held?* #f)
      (collect-rendezvous))
    (collector-tick!))

  (define-state *collector-handler*
    (let ([handler (lambda () (collector-collect!))])
      (collect-trip-bytes (* 2 1024 1024))
      (collect-request-handler handler)
      handler))

  (define (collector-pass! generation target)
    (set! *collector-pass* (cons generation target))
    (collect-rendezvous))

  (define (collector-old) (+ (bytes-allocated 2) (bytes-allocated 3)))

  ;; The old generations' size plus the GPU bytes made. A dropped buffer or
  ;; image is let go of only once its handle's generation is collected, and
  ;; its bytes, which the collector doesn't see, bring that collection on as
  ;; old growth would.
  (define (collector-grown) (+ (collector-old) *gpu-bytes-made*))

  ;; Moves the world into the oldest generation, at boot and after a
  ;; reload. Not into the static generation: then each reload would leak the
  ;; world it replaced.
  (define (collector-settle!)
    (collector-pass! 4 4)
    (set! *collector-old-kept* (collector-grown)))

  ;; Checks at most twice a second whether an older generation has grown
  ;; enough to collect: by the quiet limits when no input came for a
  ;; second, else by the higher ones. The loop checks as it steps, and the
  ;; loader after each source it loads (load-sources!), since a boot loads
  ;; the world before the loop's first step.
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

  ;; Runs thunk on core1, the world's thread. With a window, core0 opens the
  ;; window first (w × h, or full screen) and keeps this thread, the
  ;; process's first, for the screen, while the world runs on a thread of
  ;; its own. Headless, one thread plays both, unless fork? asks for two
  ;; threads with no window.
  (define (core1-run mode w h full? fork? thunk)
    (define (run) (core1-thread!) (thunk))
    (if (or (eq? mode 'sdl) fork?)
        (core0-run! mode w h full? run)
        (run)))

  ;; Boots the screen on core1 (core1-run), in mode sdl (a window of w × h
  ;; logical pixels, or full screen) or headless. Then it calls world, a
  ;; thunk that opens what the program shows, runs the world until it
  ;; quits, and ends the process.
  (define (loop-main mode w h full? world . fork?)
    (core1-run mode w h full? (and (pair? fork?) (car fork?))
               (lambda ()
                 (schevana-boot! mode w h full?)
                 (world)
                 (schevana-run!)
                 (schevana-end!)))))
