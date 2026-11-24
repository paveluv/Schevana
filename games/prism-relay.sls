;;; (games prism-relay) — Prism Relay. Turn the mirrors to send light
;;; through every crystal and into the ring. The chambers are made from
;;; their numbers, each with more routes for the light to take than the
;;; one before: from one mirror on a small bench to dozens on a large one,
;;; with half-silvered mirrors, which split the light, from the ninth on.
;;; Each window has its own bench. The GPU paints the glass, the mirrors
;;; and the traveling light from its ray map.
;;;
;;;   click, Space, Enter     turn a mirror
;;;   arrows, Tab             select a mirror
;;;   [ ], Page Up, Page Down go back and forth among the chambers reached
;;;   R                       start the chamber over
;;;
;;; Run ./prism-relay, or choose Prism Relay in ./desktop games. At a REPL,
;;; (import (games prism-relay)) and (prism-relay) open a window.
;;;
;;; This library is the app. Its parts are libraries of their own, in
;;; games/prism-relay/: the bench and its light (board), the search a
;;; player makes (solver), the chambers (generator) and the paint (glass).

(library (games prism-relay)
  (export prism-relay prism-relay-main)
  (import (chezscheme)
          (schevana core)
          (schevana kits host)
          (games prism-relay board)
          (games prism-relay generator)
          (games prism-relay glass))

  ;; How long a mirror takes to swing. Once a chamber is solved, the
  ;; flourish runs along the light at least so many cells a second, and
  ;; reaches the ring in at most so many seconds, however long the way.
  (define prism-swing-ns 160000000)
  (define prism-surge-speed 16.0)
  (define prism-surge-most 0.6)

  ;;; ------------------------------------------------------------ chambers

  ;; Starts building chamber n in a process, unless the window has it or
  ;; is building one already. A large chamber takes a while to make, and a
  ;; process makes it a slice at a time, so the world never waits for one.
  (define (prism-build-soon! win n)
    (unless (or (window-ref win 'building)
                (hashtable-ref (window-ref win 'chambers) n #f))
      (window-set! win 'building
        (spawn (format "Prism Relay chamber ~a" (+ n 1))
               (lambda () (prism-generate n))
               (lambda (status value)
                 (unless (eq? status 'killed)
                   (window-set! win 'building #f)
                   (when (eq? status 'error) (raise value))
                   (hashtable-set! (window-ref win 'chambers) n (car value))
                   (prism-chamber-ready! win)))))))

  ;; Opens the chamber the window wants, once it is built, and starts
  ;; building the next, so that it is ready by the time this one is solved.
  (define (prism-chamber-ready! win)
    (let* ([n (window-ref win 'chamber)]
           [c (hashtable-ref (window-ref win 'chambers) n #f)])
      (cond [(not c) (prism-build-soon! win n)]
            [else
             (unless (window-ref win 'board) (prism-start! win c))
             (prism-build-soon! win (+ n 1))])))

  ;; Goes to chamber n, as it starts: at once when the window has it,
  ;; else once it is built.
  (define (prism-go! win n)
    (window-set! win 'chamber n)
    (window-set! win 'reached (max n (window-ref win 'reached)))
    (window-set! win 'board #f)
    (window-set! win 'solved? #f)
    (window-set! win 'swing-cell -1)
    (window-set! win 'surge-start #f)
    (window-set! win 'burst-start #f)
    (prism-chamber-ready! win))

  ;; Goes step chambers on, among those reached: those opened and the one
  ;; after each that is solved.
  (define (prism-go-by! win step)
    (let ([n (+ (window-ref win 'chamber) step)])
      (when (<= 0 n (window-ref win 'reached)) (prism-go! win n))))

  (define (prism-start! win c)
    (let ([board (string-copy (prism-chamber-start c))])
      (window-set! win 'board board)
      (window-set! win 'cols (prism-chamber-cols c))
      (window-set! win 'rows (prism-chamber-rows c))
      (window-set! win 'par (prism-chamber-par c))
      (window-set! win 'turns 0)
      (window-set! win 'selected (or (prism-next-optic board -1 1) -1))
      (window-set! win 'hover -1)
      (window-set! win 'swing-cell -1)
      (window-set! win 'surge-start #f)
      (window-set! win 'surge -1.0)
      (window-set! win 'ring (or (prism-ring-at board) -1))
      (window-set! win 'burst-start #f)
      (window-set! win 'burst -1.0)
      (prism-show! win (prism-update! win))))

  ;; Traces the window's board, keeps what its light reaches, and returns
  ;; the ray map.
  (define (prism-update! win)
    (let* ([board (window-ref win 'board)]
           [rays (prism-trace board (window-ref win 'cols))])
      (let-values ([(lit total ring?) (prism-tally board rays)])
        (window-set! win 'lit lit)
        (window-set! win 'total total)
        (window-set! win 'solved? (and ring? (= lit total))))
      rays))

  ;; Hands the GPU the ray map, and keeps how far the light goes, which is
  ;; where the flourish ends, and how far it goes to the ring, where the
  ;; burst starts.
  (define (prism-show! win rays)
    (let ([glass (window-ref win 'glass)] [ring (window-ref win 'ring)])
      (when (>= ring 0)
        (window-set! win 'ring-far (fxsrl (fxvector-ref rays ring) 24)))
      (let loop ([i 0] [reach 0])
        (if (= i (fxvector-length rays))
            (window-set! win 'reach reach)
            (let ([word (fxvector-ref rays i)])
              (gpu-buffer-set! glass i word)
              (loop (+ i 1)
                    (if (prism-cell-lit? word)
                        (max reach (fxsrl word 24))
                        reach)))))))

  ;; Turns the mirror at cell i, unless the chamber is solved. The game
  ;; goes by the new leaning at once; the GPU keeps the old light while
  ;; the mirror swings, and gets the new light as the swing ends.
  (define (prism-turn! win i)
    (let ([board (window-ref win 'board)])
      (when (and board (< -1 i (string-length board))
                 (prism-turnable? (string-ref board i))
                 (not (window-ref win 'solved?)))
        (prism-settle! win #f)
        (string-set! board i (prism-turned (string-ref board i)))
        (window-set! win 'swing-cell i)
        (window-set! win 'swing-start #f)
        (window-set! win 'swing 0.0)
        (window-set! win 'selected i)
        (let ([turns (+ (window-ref win 'turns) 1)])
          (window-set! win 'turns turns)
          (prism-update! win)
          ;; solving a chamber records its turns and opens the next
          (when (window-ref win 'solved?)
            (let ([n (window-ref win 'chamber)])
              (hashtable-update! (window-ref win 'best) n
                                 (lambda (best)
                                   (if best (min best turns) turns))
                                 #f)
              (window-set! win 'reached
                           (max (+ n 1) (window-ref win 'reached))))))
        (window-frame-soon! win))))

  ;; Ends a mirror's swing: the GPU gets the board's light as it is now,
  ;; and a solved chamber's flourish starts at t.
  (define (prism-settle! win t)
    (when (>= (window-ref win 'swing-cell) 0)
      (window-set! win 'swing-cell -1)
      (prism-show! win (prism-trace (window-ref win 'board)
                                    (window-ref win 'cols)))
      (when (window-ref win 'solved?) (window-set! win 'surge-start t))))

  ;; Moves the pulses, the swinging mirror, the flourish and the burst on
  ;; to the frame shown at t.
  (define (prism-frame! win t)
    (window-set! win 'phase (* 2.0 pi (/ (mod t 2000000000) 2e9)))
    (when (>= (window-ref win 'swing-cell) 0)
      (let ([start (or (window-ref win 'swing-start) t)])
        (window-set! win 'swing-start start)
        (let ([p (/ (- t start) prism-swing-ns)])
          (if (>= p 1)
              (prism-settle! win t)
              (window-set! win 'swing (prism-swing-ease (inexact p)))))))
    (let ([start (window-ref win 'surge-start)]
          [far (window-ref win 'ring-far)])
      (when start
        (let ([front (* (max prism-surge-speed (/ far prism-surge-most))
                        (/ (- t start) 1e9))])
          (when (and (>= front far) (not (window-ref win 'burst-start)))
            (window-set! win 'burst-start t))
          (if (> front (+ (window-ref win 'reach) 4))
              (begin
                (window-set! win 'surge-start #f)
                (window-set! win 'surge 1000.0))
              (window-set! win 'surge (inexact front))))))
    (let ([start (window-ref win 'burst-start)])
      (when start
        (window-set! win 'burst (inexact (/ (- t start) 1e9)))))
    (window-frame-soon! win))

  ;;; ------------------------------------------------------------ the screen

  ;; The bench keeps square cells at every size. Its origin and pitch are
  ;; the mouse's too, in logical pixels.
  (define (prism-layout w h cols rows)
    (let* ([small (font-line-height 'ui-small)]
           [top (+ 24 small (font-line-height 'title))]
           [foot (- h (+ 20 (* 2 small)))]
           [cell (max 1 (floor (min (/ (- w 24) cols)
                                    (/ (- foot top 12) rows))))])
      (values (floor (/ (- w (* cell cols)) 2))
              (+ top (floor (/ (- foot top (* cell rows)) 2)))
              cell foot)))

  ;; Returns the cell at (px, py), or #f off the bench.
  (define (prism-cell-at win px py)
    (and (window-ref win 'board)
         (let*-values ([(w h) (window-content-size win)]
                       [(cols rows) (values (window-ref win 'cols)
                                            (window-ref win 'rows))]
                       [(x y cell foot) (prism-layout w h cols rows)])
           (and (<= x px) (< px (+ x (* cell cols)))
                (<= y py) (< py (+ y (* cell rows)))
                (+ (exact (floor (/ (- px x) cell)))
                   (* cols (exact (floor (/ (- py y) cell)))))))))

  ;; Returns the line at the top right: the crystals lit and the turns.
  (define (prism-status win)
    (let ([turns (window-ref win 'turns)])
      (if (window-ref win 'board)
          (format "~a/~a crystals lit   ·   ~a ~a" (window-ref win 'lit)
                  (window-ref win 'total) turns
                  (if (= turns 1) "turn" "turns"))
          "")))

  ;; The chambers reached show as dots along the top: as many as fit
  ;; beside the status, around the one shown. Returns the first chamber
  ;; shown, the chamber after the last, and the dots' spacing.
  (define (prism-dots win w)
    (let* ([gap (* 0.8 (font-line-height 'ui-small))]
           [room (max 1 (exact (floor
                                (/ (- w 44 (text-width (prism-status win)
                                                       'ui-small))
                                   gap))))]
           [reached (window-ref win 'reached)]
           [first (max 0 (min (- (window-ref win 'chamber) (quotient room 2))
                              (- (+ reached 1) room)))])
      (values first (min (+ reached 1) (+ first room)) gap)))

  ;; Returns the chamber whose dot is at (px, py), or #f.
  (define (prism-dot-at win px py)
    (let*-values ([(w h) (window-content-size win)]
                  [(first last gap) (prism-dots win w)])
      (and (<= 7 py (+ 11 (font-line-height 'ui-small)))
           (<= 14 px)
           (let ([k (+ first (exact (floor (/ (- px 14) gap))))])
             (and (< k last) k)))))

  (define (prism-draw-dots win w)
    (let-values ([(first last gap) (prism-dots win w)])
      (let* ([small (font-line-height 'ui-small)] [cy (+ 9 (/ small 2))]
             [dot (* 0.2 small)])
        (do ([k first (+ k 1)]) ((= k last))
          (let ([cx (+ 14 (* gap (- k first)) (/ gap 2))])
            (if (hashtable-ref (window-ref win 'best) k #f)
                (fill-circle cx cy dot 'accent)
                (stroke-circle cx cy dot 'text-dim 1))
            (when (= k (window-ref win 'chamber))
              (stroke-circle cx cy (* 1.9 dot) 'text 1.2)))))))

  ;; Returns the first of texts that fits in width in font, or the last.
  (define (prism-fitting texts width font)
    (or (find (lambda (s) (<= (text-width s font) width)) texts)
        (car (last-pair texts))))

  ;; The banner shows this long after the burst starts, and takes this long
  ;; to fade in, in seconds.
  (define prism-banner-after 0.15)
  (define prism-banner-fade 0.35)

  ;; Returns how the chamber's turns compare with its par.
  (define (prism-verdict turns par)
    (cond [(= turns par) "At par"]
          [(= turns (+ par 1)) "One turn over par"]
          [else (format "~a turns over par" (- turns par))]))

  ;; Draws the banner of a solved chamber on the bench at (x, y), w by h:
  ;; in the middle of the half away from the ring, so that the burst shows,
  ;; fading in and rising into place as the burst goes on.
  (define (prism-draw-banner win x y w h)
    (let* ([n (window-ref win 'chamber)]
           [rows (window-ref win 'rows)]
           [low? (< (quotient (window-ref win 'ring) (window-ref win 'cols))
                    (/ rows 2))]
           [a (max 0.0 (min 1.0 (/ (- (window-ref win 'burst)
                                     prism-banner-after)
                                  prism-banner-fade)))]
           [title (prism-fitting (list (format "Chamber ~a complete" (+ n 1))
                                       "Complete")
                                 (- w 40) 'big)]
           [verdict (prism-verdict (window-ref win 'turns)
                                   (window-ref win 'par))]
           [big (font-line-height 'big)] [ui (font-line-height 'ui)]
           [bw (+ 48 (max (text-width title 'big) (text-width verdict 'ui)))]
           [bh (+ 30 big ui)]
           [bx (+ x (/ (- w bw) 2))]
           [by (+ y (/ (- (/ h 2) bh) 2) (if low? (/ h 2) 0)
                  (* 10 (- 1 a) (- 1 a)))])
      (fill-box bx by bw bh (alpha 'bg-0 (* 0.82 a)) 12)
      (stroke-box bx by bw bh (alpha 'orange (* 0.9 a)) 1.5 12)
      (draw-text (+ bx (/ (- bw (text-width title 'big)) 2)) (+ by 12) title
                 (alpha 'text a) 'big)
      (draw-text (+ bx (/ (- bw (text-width verdict 'ui)) 2)) (+ by 16 big)
                 verdict (alpha 'orange a) 'ui)))

  (define (prism-draw win w h)
    (let*-values ([(cols rows) (values (window-ref win 'cols)
                                       (window-ref win 'rows))]
                  [(x y cell foot) (prism-layout w h cols rows)])
      (let* ([n (window-ref win 'chamber)] [board (window-ref win 'board)]
             [par (window-ref win 'par)] [status (prism-status win)]
             [best (hashtable-ref (window-ref win 'best) n #f)]
             [done? (and board (window-ref win 'solved?))]
             [small (font-line-height 'ui-small)])
        (fill-box 0 0 w h 'bg-0)
        (prism-draw-dots win w)
        (draw-text 14 (+ 11 small) (format "Chamber ~a" (+ n 1)) 'text 'title)
        (when board
          (let ([record (if best
                            (format "par ~a   ·   best ~a" par best)
                            (format "par ~a" par))])
            (draw-text (- w 14 (text-width status 'ui-small)) 9 status 'text
                       'ui-small)
            (draw-text (- w 14 (text-width record 'ui-small)) (+ 13 small)
                       record 'text-dim 'ui-small)
            (fill-shader x y (* cell cols) (* cell rows) prism-glass
                         (window-ref win 'glass) cols rows
                         (inexact (* cell (draw-scale)))
                         (if done? -1 (window-ref win 'selected))
                         ;; nothing tells the window when the mouse
                         ;; leaves it, so a mount lights only while the
                         ;; mouse is over the content
                         (if (or done? (not (eq? (window-hover win) 'content)))
                             -1
                             (window-ref win 'hover))
                         (window-ref win 'phase) (window-ref win 'swing-cell)
                         (window-ref win 'swing) (window-ref win 'surge)
                         (if (and done? (< (window-ref win 'swing-cell) 0))
                             1
                             0)
                         (window-ref win 'ring) (window-ref win 'burst))
            (when (and done? (> (window-ref win 'burst) prism-banner-after))
              (prism-draw-banner win x y (* cell cols) (* cell rows)))))
        (cond
          [(not board)
           (draw-text 14 (+ foot 2)
                      (format "Building chamber ~a…" (+ n 1)) 'text 'ui)]
          [done?
           (fill-box 12 foot (- w 24) (- h foot 6) (mix 'bg-0 'accent 0.18) 6)
           (draw-text 22 (+ foot 3)
                      (format "Click or press Enter for chamber ~a" (+ n 2))
                      'text 'ui)
           (draw-text 22 (+ foot 5 (font-line-height 'ui))
                      (prism-fitting
                       '("R plays it again · [ ] go back to the chambers \
                          reached"
                         "R plays it again · [ ] go back"
                         "R plays it again")
                       (- w 44) 'ui-small)
                      'text-dim 'ui-small)]
          [else
           (draw-text 14 (+ foot 2)
                      (if (= n prism-splitters-from)
                          (prism-fitting
                           '("Violet mirrors are half-silvered: they let \
                              light through and turn it too."
                             "Violet mirrors let light through and turn it."
                             "Violet mirrors also let light through.")
                           (- w 28) 'ui)
                          "Light every crystal, then reach the ring.")
                      'text 'ui)
           (draw-text 14 (+ foot 4 (font-line-height 'ui))
                      (prism-fitting
                       '("Click, Space or Enter turns · arrows or Tab \
                          select · [ ] chambers · R resets"
                         "Click turns · arrows select · [ ] chambers · \
                          R resets"
                         "Click turns · [ ] chambers · R resets")
                       (- w 28) 'ui-small)
                      'text-dim 'ui-small)]))))

  ;;; ------------------------------------------------------------ input

  (define (prism-select! win i)
    (when (and i (not (window-ref win 'solved?)))
      (window-set! win 'selected i)))

  (define (prism-click! win px py button)
    (when (eq? button 'left)
      (let ([dot (prism-dot-at win px py)])
        (cond
          [dot (prism-go! win dot)]
          [(window-ref win 'solved?) (prism-go-by! win 1)]
          [(prism-cell-at win px py) => (lambda (i) (prism-turn! win i))]))))

  ;; The mirror under the mouse lights its mount, and is the one selected.
  (define (prism-hover! win px py)
    (let* ([i (prism-cell-at win px py)]
           [optic (if (and i (prism-turnable?
                              (string-ref (window-ref win 'board) i)))
                      i
                      -1)])
      (unless (= optic (window-ref win 'hover))
        (window-set! win 'hover optic)
        (when (>= optic 0) (prism-select! win optic)))))

  (define (prism-key! win key mods)
    (let ([board (window-ref win 'board)] [at (window-ref win 'selected)])
      (case key
        [(#\r) (prism-go! win (window-ref win 'chamber))]
        [(return)
         (if (window-ref win 'solved?)
             (prism-go-by! win 1)
             (prism-turn! win at))]
        [(#\space) (prism-turn! win at)]
        [(tab)
         (when board
           (prism-select! win (prism-next-optic board at
                                                (if (memq 'shift mods) -1 1))))]
        [(right down left up)
         (when board
           (prism-select! win
             (if (< at 0)
                 (prism-next-optic board -1 1)
                 (prism-optic-toward board (window-ref win 'cols) at
                                     (case key
                                       [(right) 0]
                                       [(down) 1]
                                       [(left) 2]
                                       [else 3])))))]
        [(#\[ page-up) (prism-go-by! win -1)]
        [(#\] page-down) (prism-go-by! win 1)])))

  ;;; ------------------------------------------------------------ the app

  (define (prism-draw-icon x y s flags)
    (define (ink c)
      (if (or (memq 'dim flags) (memq 'disabled flags)) (alpha c 0.5) c))
    (with-translation (x y)
      (with-scale ((/ s 24))
        (draw-line 2 18 14 18 (ink 'cyan) 2)
        (draw-line 14 18 14 6 (ink 'cyan) 2)
        (draw-line 10 22 18 14 (ink 'text) 2.5)
        (stroke-circle 14 5 3 (ink 'orange) 2))))

  (define-app (prism-relay) "Prism Relay" 'icon prism-draw-icon
    (open-window "Prism Relay"
      'size '(630 . 520)
      'min-size '(400 . 340)
      'glass (make-gpu-buffer prism-most-cells)
      'chambers (make-eqv-hashtable)
      'best (make-eqv-hashtable)
      'chamber 0
      'reached 0
      'building #f
      'board #f
      'cols 5
      'rows 4
      'par 0
      'turns 0
      'lit 0
      'total 0
      'solved? #f
      'selected -1
      'hover -1
      'phase 0.0
      'swing-cell -1
      'swing 0.0
      'surge -1.0
      'surge-start #f
      'reach 0
      'ring -1
      'ring-far 0
      'burst -1.0
      'burst-start #f
      'open (lambda (win) (prism-go! win 0) (window-frame-soon! win))
      'frame (lambda (win t) (prism-frame! win t))
      'draw (lambda (win w h) (prism-draw win w h))
      'mouse-down (lambda (win x y b n) (prism-click! win x y b))
      'mouse-move (lambda (win x y) (prism-hover! win x y))
      'key (lambda (win key mods) (prism-key! win key mods))
      'close (lambda (win)
               (let ([p (window-ref win 'building)]) (when p (kill! p)))
               (gpu-buffer-release! (window-ref win 'glass)))))

  ;; Waits for win's first chamber, solves it, reads the screen back and
  ;; tells what it drew; or, when the window has crashed or the chamber
  ;; stays unsolved, says so and fails.
  (define (prism-check win)
    (after 50
      (lambda ()
        (let ([c (hashtable-ref (window-ref win 'chambers) 0 #f)])
          (if (not (and c (window-ref win 'board)))
              (prism-check win)
              (begin
                (for-each (lambda (i) (prism-turn! win i))
                          (prism-chamber-solution c))
                (after 400
                  (lambda ()
                    (screen-bytes-then
                     (lambda (bytes)
                       (when (window-error win)
                         (display-condition (cdr (window-error win)))
                         (newline)
                         (exit 1))
                       (unless (window-ref win 'solved?)
                         (printf "Prism Relay's first chamber is unsolved \
                                  after its solution's turns~n")
                         (exit 1))
                       (printf "Prism Relay drew ~a x ~a pixels (~a bytes): \
                                chamber 1, ~a x ~a cells, solved in ~a ~a~n"
                               *canvas-pw* *canvas-ph* (bytevector-length bytes)
                               (prism-chamber-cols c) (prism-chamber-rows c)
                               (window-ref win 'turns)
                               (if (= 1 (window-ref win 'turns))
                                   "turn"
                                   "turns"))
                       (quit!)))))))))))

  ;; Runs Prism Relay as a program of its own, its window the host's
  ;; ((schevana kits host)). --headless solves the first chamber, reads
  ;; the screen back and tells what it drew.
  (define (prism-relay-main args)
    (host-main "org.schevana.PrismRelay" 680 560 args
      (lambda ()
        (let ([win (prism-relay)])
          (when (member "--headless" args) (prism-check win))
          win)))))
