;;; (demo life) — Conway's Game of Life. It shows mouse input, animation
;;; and the crew: a generation runs on as many threads as it is given, and
;;; the controls beside the grid push it as far as the machine can go,
;;; down to one pixel per cell in a maximized window, and up to a
;;; generation every frame, or as many as fit in one. The grid has as many
;;; cells as the window has room for; when the window changes size, the
;;; grid keeps what still fits and seeds the new space at random.
;;; Space: pause · R: randomize · C: clear · N: single step · H: the controls
;;; (as does the button at the end of the status line) · Click/drag: draw

(library (demo life)
  (export life)
  (import (chezscheme)
          (schevana core)
          (schevana kits text)
          (schevana kits ui)
          (schevana services crew)
          (schevana kits pixmap)
          (only (schevana kits color) color->pixel))

  (define (life-bar-height)
    (max 26 (round (+ (font-line-height 'ui-small) 13))))

  ;; Returns the text of the status line under the grid.
  (define (life-status-text generation running? cols rows rate)
    (format "generation ~a   ~a   ~a × ~a   ~a a second   space pause · \
             r random · c clear · n step · h controls"
            generation (if running? "▶" "❚❚") cols rows (exact (round rate))))

  ;; Returns the pixel of a live cell in each row, top to bottom
  ;; (color->pixel reads the theme).
  (define (life-row-pixels rows)
    (let ([v (make-fxvector rows)])
      (do ([y 0 (fx+ y 1)]) ((fx= y rows) v)
        (fxvector-set! v y (color->pixel (mix 'green 'cyan (/ y rows)))))))

  ;;; ----------------------------------------------------------------- worklets
  ;;; What the crew runs, each call on rows of its own. The worklets touch
  ;;; only their arguments and allocate nothing.

  ;; Writes rows [y0, y1) of the next generation, on a torus, into next,
  ;; and one pixel per cell into pix, the pixmap's pixels (pixmap-rows!).
  ;; It uses fixnum operations with at most three arguments to fx+: a + or
  ;; fx+ of four or more allocates its arguments (an 8-argument + took
  ;; 300 KB a generation).
  (define-worklet (life-step-rows! y0 y1 pix grid next row-px dead cols rows)
    (let ([last-x (fx- cols 1)] [last-y (fx- rows 1)])
      (do ([y y0 (fx+ y 1)]) ((fx= y y1))
        (let* ([mid (fx* y cols)]
               [up (if (fx= y 0) (fx* last-y cols) (fx- mid cols))]
               [dn (if (fx= y last-y) 0 (fx+ mid cols))]
               [live (fxvector-ref row-px y)])
          (define (col x)   ; live cells in column x of rows y-1, y, y+1
            (fx+ (bytevector-u8-ref grid (fx+ up x))
                 (bytevector-u8-ref grid (fx+ mid x))
                 (bytevector-u8-ref grid (fx+ dn x))))
          (let loop ([x 0] [left (col last-x)] [here (col 0)])
            (when (fx< x cols)
              (let* ([right (col (if (fx= x last-x) 0 (fx+ x 1)))]
                     [i (fx+ mid x)]
                     [self (bytevector-u8-ref grid i)]
                     [n (fx- (fx+ left here right) self)]
                     [alive (if (or (fx= n 3) (and (fx= n 2) (fx= self 1)))
                                1
                                0)])
                (bytevector-u8-set! next i alive)
                (bytevector-u32-native-set! pix (fx* 4 i)
                                            (if (fx= alive 1) live dead))
                (loop (fx+ x 1) here right))))))))

  ;; Fills rows [y0, y1) of grid at random, about 22% alive, each row from
  ;; its own seed. The generator is a linear congruential one on 32 bits,
  ;; read by its high bits, which are the good ones.
  (define-worklet (life-seed-rows! y0 y1 grid seeds cols)
    (do ([y y0 (fx+ y 1)]) ((fx= y y1))
      (let ([mid (fx* y cols)])
        (let loop ([x 0] [s (fxvector-ref seeds y)])
          (when (fx< x cols)
            (bytevector-u8-set! grid (fx+ mid x)
                                (if (fx< (fxsrl s 16) 14418) 1 0))
            (loop (fx+ x 1) (fxlogand (fx+ (fx* s 69069) 1) #xffffffff)))))))

  ;; Writes each cell's pixel into rows [y0, y1) of pix, the pixmap's
  ;; pixels.
  (define-worklet (life-paint-rows! y0 y1 pix grid row-px dead cols)
    (do ([y y0 (fx+ y 1)]) ((fx= y y1))
      (let ([mid (fx* y cols)] [live (fxvector-ref row-px y)])
        (do ([x 0 (fx+ x 1)]) ((fx= x cols))
          (let ([i (fx+ mid x)])
            (bytevector-u32-native-set! pix (fx* 4 i)
                                        (if (fx= 1 (bytevector-u8-ref grid i))
                                            live
                                            dead)))))))

  ;; The rows each call of the crew gets: at least 8,000 cells, about
  ;; 80 µs of a generation. So a small grid runs on the caller alone,
  ;; where waking the crew would cost more than it saves.
  (define (life-chunk-rows cols) (max 1 (quotient 8000 cols)))

  ;;; ------------------------------------------------------------------ drawing

  ;; Draws the cells (a pixmap, one pixel each) scaled up at (ox, oy),
  ;; then the one-pixel gaps between them when the cells are big enough to
  ;; spare them (5 screen pixels or more).
  (define (draw-life-cells pixels cols rows cell ox oy)
    (pixmap-draw pixels ox oy (* cell cols) (* cell rows))
    (when (>= (* cell (screen-scale)) 5)
      (do ([x 0 (+ x 1)]) ((= x cols))
        (fill-box (+ ox (* x cell)) oy 1 (* cell rows) 'bg-0))
      (do ([y 0 (+ y 1)]) ((= y rows))
        (fill-box ox (+ oy (* y cell)) (* cell cols) 1 'bg-0))))

  ;;; ----------------------------------------------------------------- controls

  ;; The sizes a cell can have, in the screen's own pixels.
  (define life-cell-stops '(1 2 3 4 5 6 8 10 12 16 20 24 32 40))

  ;; How often a generation comes: the ms between two generations, 0 for
  ;; one every frame, or flat for as many as fit in life-flat-ns.
  (define life-speeds
    '(("1 a second" . 1000)
      ("2 a second" . 500)
      ("5 a second" . 200)
      ("12 a second" . 80)
      ("30 a second" . 33)
      ("every frame" . 0)
      ("flat out" . flat)))

  (define life-default-speed 3)

  ;; Flat out, each frame steps generations for this long (at least one).
  ;; The rest of a 60 Hz frame is left for drawing, so the desktop stays
  ;; usable.
  (define life-flat-ns 10000000)

  ;; The tooltips of the panel's sliders, made once, since a tooltip is
  ;; asked for at every draw.
  (define life-cell-tip
    "The side of a cell, in the screen's own pixels: at 1 px, a cell is a \
     pixel")
  (define life-speed-tip
    (format "How often a generation comes. Flat out: as many as ~a ms of each \
             frame holds" (quotient life-flat-ns 1000000)))
  (define life-threads-tip
    "The threads a generation runs on: the crew's, which every app shares")

  ;; How often the numbers change, in ns, so that they stay readable.
  (define life-meter-ns 500000000)

  ;; Returns the index of the stop nearest to px.
  (define (life-nearest-stop px)
    (let loop ([stops life-cell-stops] [i 0] [best 0] [gap +inf.0])
      (if (null? stops)
          best
          (let ([d (abs (- (car stops) px))])
            (if (< d gap)
                (loop (cdr stops) (+ i 1) i d)
                (loop (cdr stops) (+ i 1) best gap))))))

  ;; Formats a rate in thousands, millions or billions.
  (define (life-amount n)
    (cond [(>= n 1e9) (format "~,2f G" (/ n 1e9))]
          [(>= n 1e6) (format "~,1f M" (/ n 1e6))]
          [(>= n 1e3) (format "~,1f K" (/ n 1e3))]
          [else (number->string (exact (round n)))]))

  (define (life-ms ns) (format "~,2f ms" (/ ns 1e6)))

  (define life-buttons
    '("Pause"
      "Step"
      "Random"
      "Clear"))

  (define life-labels
    '("Cell size"
      "Speed"
      "Threads"
      "A generation"
      "Drawing it"
      "Cells a second"
      "Per thread"))

  ;; The panel's width, with room for a label and its widest value on one
  ;; line, and for two buttons side by side.
  (define (life-panel-width)
    (let ([pad (ui-pad)] [gap (ui-gap)])
      (+ pad pad
         (max (+ gap gap (text-widest life-labels 'ui)
                 (text-widest '("every frame" "1234.56 ms" "12.34 G") 'ui))
              (+ gap (* 2 (apply max
                                 (map (lambda (label)
                                        (let-values
                                            ([(w h) (ui-button-size label #f)])
                                          w))
                                      life-buttons))))))))

  (define (life-line-height) (+ 6 (font-line-height 'ui)))

  ;; The panel's height, as the app's draw-panel lays it out.
  (define (life-panel-height)
    (let ([pad (ui-pad)] [gap (ui-gap)] [ch (ui-control-height)]
          [line (life-line-height)])
      (+ pad (* 2 (+ ch gap))
         gap (* 3 (+ line (ui-slider-height) gap))
         gap (* 4 line) pad)))

  ;; The least width the grid needs beside the panel; in a narrower window
  ;; there is no panel.
  (define life-grid-least 200)

  ;;; ------------------------------------------------------------------ the app

  ;; The app's icon: a glider, on its three by three cells.
  (define (life-draw-icon x y s flags)
    (define (ink c) (ui-icon-ink flags c))
    (ui-icon-grid (x y s)
      (do ([i 0 (+ i 1)]) ((= i 9))
        (fill-box (+ 2.5 (* 6.5 (mod i 3))) (+ 2.5 (* 6.5 (quotient i 3))) 6 6
                  (ink (if (memv i '(1 5 6 7 8)) 'green (alpha 'green 0.15)))
                  1.25))))

  (define-app (life) "Life" 'icon life-draw-icon
    (let* ([cols 0] [rows 0]
           [grid (make-bytevector 0)]    ; a byte per cell, 1 if alive
           [next (make-bytevector 0)]
           [pixels #f]                   ; the pixmap shown, a pixel per cell
           [row-px #f] [dead 0] [palette-key #f]
           [running? #t] [generation 0] [last-step 0]
           [speed life-default-speed]    ; an index into life-speeds
           [cell-px (exact (round (* 10 (screen-scale))))]
           [painting #f]                 ; #f, 'fresh or the value being painted
           [painted #f]                  ; the last cell painted, or #f
           [cell 10] [ox 0] [oy 0]       ; the last draw's layout
           [ui (make-ui)]
           ;; the meter: the counts since meter-from, and the numbers it
           ;; showed last
           [meter-from (now-ns)] [gens 0] [step-ns 0] [draws 0] [draw-ns 0]
           [shown-rate 0] [shown-step 0] [shown-draw 0])
      (define (index x y) (+ x (* y cols)))
      (define (pixel-of i)
        (if (fx= 1 (bytevector-u8-ref grid i))
            (fxvector-ref row-px (fxquotient i cols))
            dead))
      (define (repaint-pixels!)
        (pixmap-rows! pixels 0 rows life-paint-rows! grid row-px dead cols))
      ;; Makes every row's colors again, but only when a theme color they
      ;; use has changed (by any means, a raw hashtable-set! of *theme*
      ;; included).
      (define (palette!)
        (let ([key (list (theme 'green) (theme 'cyan) (theme 'bg-0))])
          (unless (equal? key palette-key)
            (set! row-px (life-row-pixels rows))
            (set! dead (color->pixel 'bg-0))
            (set! palette-key key)
            (repaint-pixels!))))
      (define (seed! g c r)
        (let ([seeds (make-fxvector r)])
          (do ([y 0 (fx+ y 1)]) ((fx= y r))
            (fxvector-set! seeds y (random 4294967296)))
          (crew-for* (life-chunk-rows c) 0 r life-seed-rows! g seeds c)))
      ;; Makes a grid of c × r cells, which keeps what fits of the old one
      ;; and seeds the rest at random.
      (define (regrid! c r)
        (let ([g (make-bytevector (* c r) 0)])
          (seed! g c r)
          (do ([y 0 (+ y 1)]) ((= y (min r rows)))
            (bytevector-copy! grid (* y cols) g (* y c) (min c cols)))
          (set! cols c)
          (set! rows r)
          (set! grid g)
          (set! next (make-bytevector (* c r) 0))
          (set! pixels (make-pixmap c r))
          (set! palette-key #f)
          (palette!)))
      ;; Fits the grid to a field fw × fh: sets a cell's logical size and
      ;; the grid's place, centered from side to side in what whole cells
      ;; leave over.
      (define (fit! fw fh)
        (let* ([c (/ cell-px (exact (screen-scale)))]
               [nc (max 1 (exact (floor (/ fw c))))]
               [nr (max 1 (exact (floor (/ fh c))))])
          (set! cell c)
          (unless (and (= nc cols) (= nr rows)) (regrid! nc nr))
          (set! ox (floor (/ (- fw (* c cols)) 2)))
          (set! oy 0)))
      (define (step!)
        (let ([t0 (now-ns)])
          (pixmap-rows! pixels 0 rows life-step-rows! grid next row-px dead
                        cols rows)
          (set! step-ns (+ step-ns (- (now-ns) t0))))
        (let ([t grid]) (set! grid next) (set! next t))
        (set! gens (+ gens 1))
        (set! generation (+ generation 1)))
      ;; Steps the generations the speed asks for in this frame.
      (define (run! win)
        (let ([delay (cdr (list-ref life-speeds speed))])
          (cond
            [(eq? delay 'flat)
             (let ([until (+ (now-ns) life-flat-ns)])
               (let loop () (step!) (when (< (now-ns) until) (loop))))
             (invalidate! win)]
            [(>= (- (now-ms) last-step) delay)
             (set! last-step (now-ms))
             (step!)
             (invalidate! win)])))
      (define (meter! win)
        (let ([t (now-ns)])
          (when (>= (- t meter-from) life-meter-ns)
            (let ([rate (/ (* 1e9 gens) (- t meter-from))])
              (unless (and (= rate 0) (= shown-rate 0)) (invalidate! win))
              (set! shown-rate rate))
            (when (> gens 0) (set! shown-step (/ step-ns gens)))
            (when (> draws 0) (set! shown-draw (/ draw-ns draws)))
            (set! meter-from t)
            (set! gens 0)
            (set! step-ns 0)
            (set! draws 0)
            (set! draw-ns 0))))
      (define (randomize!)
        (seed! grid cols rows)
        (set! generation 0)
        (repaint-pixels!))
      (define (clear!)
        (bytevector-fill! grid 0)
        (set! generation 0)
        (repaint-pixels!))
      (define (run-or-pause!) (set! running? (not running?)))
      (define (cell-at x y)
        (let ([cx (exact (floor (/ (- x ox) cell)))]
              [cy (exact (floor (/ (- y oy) cell)))])
          (and (>= cx 0) (< cx cols) (>= cy 0) (< cy rows) (cons cx cy))))
      (define (paint-cell! x y)
        (bytevector-u8-set! grid (index x y) painting)
        (pixmap-set-pixel! pixels x y (pixel-of (index x y))))
      ;; Paints each cell from the last one painted to the one under the
      ;; pointer, so that a fast drag over small cells leaves no holes.
      (define (paint! x y)
        (let ([c (cell-at x y)])
          (when c
            (when (eq? painting 'fresh)
              (set! painting
                (if (= 1 (bytevector-u8-ref grid (index (car c) (cdr c)))) 0 1))
              (set! painted c))
            (let* ([from (or painted c)]
                   [dx (- (car c) (car from))] [dy (- (cdr c) (cdr from))]
                   [n (max 1 (abs dx) (abs dy))])
              (do ([i 0 (+ i 1)]) ((> i n))
                (paint-cell! (+ (car from) (round (/ (* i dx) n)))
                             (+ (cdr from) (round (/ (* i dy) n))))))
            (set! painted c))))
      ;; Draws the controls and the numbers in a panel at x, w wide.
      (define (draw-panel x w h)
        (let* ([pad (ui-pad)] [gap (ui-gap)] [ch (ui-control-height)]
               [line (life-line-height)] [sh (ui-slider-height)]
               [lx (+ x pad)] [lw (- w pad pad)]
               [bw (/ (- lw gap) 2)] [cpus (max 2 (platform-cpu-count))]
               [threads (+ 1 (crew-size))]
               ;; one thread alone, while a generation is a single call
               [used (if (<= rows (life-chunk-rows cols)) 1 threads)]
               [cells-a-second (if (> shown-step 0)
                                   (/ (* 1e9 cols rows) shown-step)
                                   0)])
          (define (button! id bx y label act!)
            (ui-button ui id bx y bw ch label act!))
          (define (numbers! y label value)
            (ui-draw-label lx y lw line '(dim) label)
            (ui-draw-label lx y lw line '(right) value)
            (+ y line))
          (define (slider! y id label value at lo hi on-change tip)
            (let ([y (numbers! y label value)])
              (ui-slider ui id (+ lx 8) y (- lw 16) at lo hi
                         (lambda (v) (on-change (exact (round v)))) #f
                         'tip tip)
              (+ y sh gap)))
          (let* ([y pad]
                 [y (begin
                      (button! 'run lx y (if running? "Pause" "Run")
                               run-or-pause!)
                      (button! 'step (+ lx bw gap) y "Step" step!)
                      (+ y ch gap))]
                 [y (begin
                      (button! 'random lx y "Random" randomize!)
                      (button! 'clear (+ lx bw gap) y "Clear" clear!)
                      (+ y ch gap gap))]
                 [y (slider! y 'cell "Cell size" (format "~a px" cell-px)
                             (life-nearest-stop cell-px)
                             0 (- (length life-cell-stops) 1)
                             (lambda (i)
                               (set! cell-px (list-ref life-cell-stops i)))
                             life-cell-tip)]
                 [y (slider! y 'speed "Speed" (car (list-ref life-speeds speed))
                             speed 0 (- (length life-speeds) 1)
                             (lambda (i) (set! speed i))
                             life-speed-tip)]
                 [y (slider! y 'threads "Threads"
                             (if (= used threads)
                                 (number->string threads)
                                 (format "~a of ~a" used threads))
                             threads 1 cpus
                             (lambda (n) (crew-size-set! (- n 1)))
                             life-threads-tip)]
                 [y (+ y gap)]
                 [y (numbers! y "A generation" (life-ms shown-step))]
                 [y (numbers! y "Drawing it" (life-ms shown-draw))]
                 [y (numbers! y "Cells a second" (life-amount cells-a-second))]
                 [y (numbers! y "Per thread"
                              (life-amount (/ cells-a-second used)))])
            y)))
      ;; Draws the grid in w × h.
      (define (draw-grid w h)
        (fit! w h)
        (palette!)
        ;; the margins around the grid (the grid covers the rest)
        (fill-box 0 0 w oy 'bg-0)
        (fill-box 0 oy ox (* cell rows) 'bg-0)
        (fill-box (+ ox (* cell cols)) oy (- w ox (* cell cols))
                  (* cell rows) 'bg-0)
        (fill-box 0 (+ oy (* cell rows)) w (- h oy (* cell rows)) 'bg-0)
        (let ([t0 (now-ns)])
          (draw-life-cells pixels cols rows cell ox oy)
          (set! draw-ns (+ draw-ns (- (now-ns) t0)))
          (set! draws (+ draws 1)))
        (ui-area ui 'life-cells 0 0 w h
                 (lambda () (set! painting 'fresh))
                 paint!
                 'cursor 'crosshair
                 'doc '((L . "Draw or erase cells"))))
      ;; Draws the status line at y, as wide as the window, with the
      ;; panel's button at its end: there it is clear of the grid and of a
      ;; style's resize grip, and stays in place whether the panel shows or
      ;; not.
      (define (draw-status w y bar)
        (let* ([bh (- bar 6)] [bw (+ bh 6)] [bx (- w bw 14)])
          (fill-box 0 y w bar 'bg-1)
          (draw-text 10 (+ y 5)
                     (text-fit (life-status-text generation running? cols rows
                                                 shown-rate)
                               (- bx 20) 'ui-small)
                     'text-faint 'ui-small)
          (ui-side-panel-button ui 'life-controls bx (+ y 3) bw bh 'right)))
      (regrid! 72 44)
      (apply open-window "Life"
        'size (cons (* 10 cols)
                    (+ (life-bar-height) (max (* 10 rows) (life-panel-height))))
        'draw (lambda (win w h)
                (let* ([bar (life-bar-height)] [fh (max 1 (- h bar))])
                  (ui-begin! ui)
                  (ui-side-panel ui 'life-controls 0 0 w fh 'right
                                 (life-panel-width) life-grid-least
                                 (lambda (x y w h) (draw-grid w h))
                                 (lambda (x y w h) (draw-panel x w h))
                                 'floating #t)
                  (draw-status w fh bar)
                  (ui-end! ui w h)))
        (append
         (ui-handlers ui 'key (lambda (win key mods)
                                (case key
                                  [(#\space) (run-or-pause!)]
                                  [(#\r) (randomize!)]
                                  [(#\c) (clear!)]
                                  [(#\n) (step!)]
                                  [(#\h)
                                   (ui-side-panel-toggle! ui 'life-controls)])
                                (invalidate! win)
                                #t))
         ;; the generations and the meter, run while the window is seen
         (list 'open (lambda (win) (window-frame-soon! win))
               'frame (lambda (win t)
                        (window-frame-soon! win)
                        (ui-frame ui win)
                        (when running? (run! win))
                        (meter! win))))))))
