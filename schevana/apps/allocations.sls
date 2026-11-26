;;; (schevana apps allocations) — Allocations: what the heap is doing, as a
;;; picture that moves. Bytes are born at the top of the Column, in the
;;; young generation; most are gone at the next collection, and the few
;;; that are kept sink a generation at a time to where the world rests. The
;;; Flow, along the bottom, has a bar for each tick, as tall as what the
;;; tick allocated and banded by who, with the collections over it. Who
;;; lists who allocates, Where shows which procedures do (the tap's call
;;; paths as a flame, a table, and the source), and Collections has the
;;; log of collections.
;;;
;;; All of it is the profiler's and the allocation service's data
;;; ((schevana services profile), (schevana services allocation)), which a
;;; REPL reads too. While the window is open, the allocation tap records.

(library (schevana apps allocations)
  (export allocations)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) alpha collector-generation-bytes define-app
                draw-line draw-text fill-box font-char-width font-line-height
                invalidate! now-ms now-ns open-window pacer-period
                window-frame-soon!)
          (only (schevana kits ui) make-ui ui-bar-chart-bar ui-begin!
                ui-button ui-button-size ui-checkbox ui-checkbox-size
                ui-draw-cell ui-draw-label ui-draw-legend ui-draw-sparkline
                ui-draw-surface ui-end! ui-flame ui-frame ui-handlers
                ui-icon-grid
                ui-icon-ink ui-legend-size ui-pad ui-source ui-stream
                ui-stream-new ui-stream-release! ui-stream-send! ui-table
                ui-table-room
                ui-table-row-height ui-tabs ui-tabs-size ui-text-y
                ui-toolbar ui-treemap)
          (only (schevana services allocation) allocation-census
                allocation-census! allocation-census-grown
                allocation-census-mark! allocation-collection
                allocation-collection-count allocation-hours
                allocation-hours-count allocation-hours-slope
                allocation-paths allocation-places allocation-record!
                allocation-recording? allocation-young)
          (only (schevana services profile) profile-newest-tick profile-ns-label
                profile-oldest-tick profile-on? profile-subject-label
                profile-subject? profile-tick-kept? profile-tick-late?
                profile-tick-ns profile-tick-ref profile-tick-uses
                profile-total-bytes profile-total-calls profile-total-what
                profile-totals profile-use-bytes profile-use-subject))

  (library-layer apps)

  ;; Returns a count of bytes as a person reads it: "812 B", "12.4 KB".
  (define (allocations-bytes-text n)
    (cond [(< n 1024) (format "~a B" n)]
          [(< n 1048576) (format "~,1f KB" (/ n 1024.0))]
          [(< n 1073741824) (format "~,1f MB" (/ n 1048576.0))]
          [else (format "~,2f GB" (/ n 1073741824.0))]))

  ;; Returns a span as a person reads it, key and part as the tap has
  ;; them: a window's title or a process's name, a surface's name, and
  ;; the part where it is a name.
  (define (allocations-span-label key part)
    (string-append
     (cond [(not key) "outside a span"]
           [(fixnum? key)
            (profile-subject-label
             (cons (if (eq? part #t) 'process 'window) key))]
           [(profile-subject? key) (profile-subject-label key)]
           [else (format "~a" key)])
     (if (and part (symbol? part)) (format ", ~a" part) "")))

  ;; Returns the label of a node of the tap's tree (allocation-paths).
  (define (allocations-node-label node)
    (let ([what (car node)])
      (cond [(not what) "all"]
            [(symbol? what) "…"]
            [(eq? (car what) 'span)
             (allocations-span-label (cadr what) (cddr what))]
            [else (or (car what) "(no name)")])))

  ;; Returns the tap's tree with each span's ways in cut short: under a
  ;; span, the callers that only lead on (one callee each, and no sample
  ;; of their own: the loop, the guards, a handler's call) are left out,
  ;; down to the first procedure that allocates or calls two. A flame's
  ;; few rows then begin where the paths part.
  (define (allocations-trim tree)
    (define (lead node)
      (if (and (= (cadr node) 0) (pair? (cddddr node))
               (null? (cdr (cddddr node))))
          (lead (car (cddddr node)))
          node))
    (cons* (car tree) (cadr tree) (caddr tree) (cadddr tree)
           (map (lambda (span)
                  (cons* (car span) (cadr span) (caddr span) (cadddr span)
                         (map lead (cddddr span))))
                (cddddr tree))))

  ;; Returns a file's name and a line as "draw.sls:670", or "" for none.
  (define (allocations-place-text file line)
    (cond [(not file) ""]
          [line (format "~a:~a" (path-last file) line)]
          [else (path-last file)]))

  ;; Returns the lines of file as a vector, or #f when it can't be read.
  (define (allocations-file-lines file)
    (guard (c [#t #f])
      (call-with-input-file file
        (lambda (port)
          (let loop ([acc '()])
            (let ([line (get-line port)])
              (if (eof-object? line)
                  (list->vector (reverse acc))
                  (loop (cons line acc)))))))))

  ;; Returns a change of bytes as a person reads it, signed: "+2.0 MB",
  ;; "−812 B", or "–" for none.
  (define (allocations-change-text n)
    (cond [(or (not n) (= n 0)) "–"]
          [(> n 0) (string-append "+" (allocations-bytes-text n))]
          [else (string-append "−" (allocations-bytes-text (- n)))]))

  ;; Returns how long ago ns, on now-ns's clock, was: "12 s ago".
  (define (allocations-ago ns)
    (let ([s (quotient (max 0 (- (now-ns) ns)) 1000000000)])
      (cond [(< s 60) (format "~a s ago" s)]
            [(< s 3600) (format "~a min ago" (quotient s 60))]
            [else (format "~a h ago" (quotient s 3600))])))

  ;; Returns the leaves of a census's tree of owners as ((path . node) ...),
  ;; the heaviest first, a path being the labels from the heap down.
  (define (allocations-owner-leaves tree)
    (sort (lambda (a b) (> (cadr (cdr a)) (cadr (cdr b))))
          (let walk ([node tree] [path '()])
            (let ([path (append path (list (car node)))])
              (if (null? (cddr node))
                  (list (cons path node))
                  (apply append
                         (map (lambda (c) (walk c path)) (cddr node))))))))

  ;; Returns a census's kinds as a tree, for the treemap: the heap, and
  ;; under it a node (name bytes) for each kind.
  (define (allocations-kind-tree census)
    (let ([kinds (cdr (assq 'kinds census))])
      (cons* "heap" (apply + (map caddr kinds))
             (map (lambda (k) (list (format "~a" (car k)) (caddr k)))
                  kinds))))

  ;; Returns at most n of values, evenly picked, the first and the last
  ;; among them.
  (define (allocations-thin values n)
    (let ([len (length values)])
      (if (<= len n)
          values
          (let ([v (list->vector values)])
            (map (lambda (i) (vector-ref v (quotient (* i (- len 1)) (- n 1))))
                 (iota n))))))

  ;; The rows of Hours: a field of the hours, its name, and what it counts.
  (define allocations-hours-rows
    '((0 "young" bytes)
      (1 "generation 1" bytes)
      (2 "generation 2" bytes)
      (3 "generation 3" bytes)
      (4 "generation 4" bytes)
      (memory "what Chez holds" bytes)
      (process "the process" bytes)
      (gpu "GPU bytes made" bytes)
      (pause "the longest pause" ns)))

  ;; The Flow's bands, from the bottom up: who allocated a tick's bytes.
  (define allocations-draw-bands
    '((chart-1 . "windows")
      (chart-3 . "processes")
      (chart-5 . "surfaces")
      (chart-8 . "the loop and the rest")))

  ;; The Flow's strips: a collection, the stronger the longer its pause; a
  ;; request for one held off till the frame was out; a tick that came
  ;; late.
  (define allocations-draw-strips
    '(("collected" chart-level-1 chart-level-2 chart-level-3 chart-level-4
                   chart-level-5 chart-level-6 chart-level-7 chart-level-8)
      ("held" chart-mark)
      ("late" chart-flag)))

  ;; A collection's level on its strip, 1 to 8: faint however short, and
  ;; the strongest from 2 ms on.
  (define (allocations-pause-level ns)
    (+ 1 (quotient (* 7 (min (max ns 0) 2000000)) 2000000)))

  ;; How many ticks the Flow keeps, and the most a bar can stand for.
  (define allocations-flow-rows 4096)
  (define allocations-bar-most 100000000)

  ;; Returns which band a use's subject is in: a window 0, a process 1, a
  ;; surface 2, and #f for the loop's own spans and the collector, whose
  ;; bytes go with the rest.
  (define (allocations-band subject)
    (cond [(and (pair? subject) (eq? (car subject) 'window)) 0]
          [(and (pair? subject) (eq? (car subject) 'process)) 1]
          [(and (profile-subject? subject) (not (eq? subject 'gc))) 2]
          [else #f]))

  ;; Fills row, a vector of four, with the bytes of tick seq by band; the
  ;; last has what no window, process or surface was charged.
  (define (allocations-tick-bands! row seq)
    (vector-fill! row 0)
    (for-each (lambda (use)
                (let ([band (allocations-band (profile-use-subject use))])
                  (when band
                    (vector-set! row band (+ (vector-ref row band)
                                             (profile-use-bytes use))))))
              (profile-tick-uses seq))
    (vector-set! row 3
                 (max 0 (- (profile-tick-ref seq 'allocated)
                           (vector-ref row 0) (vector-ref row 1)
                           (vector-ref row 2)))))

  ;; Returns the ticks from seq back, at most n of them, the newest first.
  (define (allocations-ticks seq n)
    (let loop ([seq seq] [n n] [acc '()])
      (if (and (> n 0) seq (profile-tick-kept? seq))
          (loop (- seq 1) (- n 1) (cons seq acc))
          (reverse acc))))

  ;; Returns the top of a chart of the numbers ns: the least power of two,
  ;; 64 KB at least, that all but the largest twentieth of them fit under
  ;; with a quarter to spare. So it stays put while bars come and go, and
  ;; one huge bar among them is cut off and doesn't flatten the rest.
  (define (allocations-top ns)
    (let* ([sorted (sort < ns)]
           [n (if (null? sorted)
                  0
                  (list-ref sorted (quotient (* 19 (- (length sorted) 1))
                                             20)))])
      (let loop ([top 65536])
        (if (>= top (quotient (* 5 n) 4)) top (loop (* 2 top))))))

  ;; Places the collections logged from seq cursor on on the ticks they
  ;; ended in, up to tick newest: marks gets, by tick, the longest pause
  ;; (ns) of its collections and how many requests they had held off,
  ;; (pause . held). A collection goes to the first tick whose end is not
  ;; before its own. Returns the next collection to place: one that ended
  ;; after newest waits for its tick.
  (define (allocations-place! marks cursor newest)
    (let ([count (allocation-collection-count)])
      (let next ([cursor cursor])
        (let ([c (and (< cursor count) (allocation-collection cursor))])
          (cond
            [(>= cursor count) cursor]
            [(not c) (next (+ cursor 1))]
            [(> (cdr (assq 'at c)) (profile-tick-ns newest 'end)) cursor]
            [else
             (let find ([seq newest])
               (if (and (profile-tick-kept? (- seq 1))
                        (>= (profile-tick-ns (- seq 1) 'end)
                            (cdr (assq 'at c))))
                   (find (- seq 1))
                   (let ([m (hashtable-ref marks seq '(0 . 0))])
                     (hashtable-set!
                      marks seq
                      (cons (max (car m) (cdr (assq 'pause c)))
                            (+ (cdr m) (cdr (assq 'held c))))))))
             (next (+ cursor 1))])))))

  ;; The heap's layers, from the top down: its name, and its color, the
  ;; older the stronger.
  (define allocations-draw-layers
    '(("young" . chart-level-2)
      ("1" . chart-level-3)
      ("2" . chart-level-4)
      ("3" . chart-level-5)
      ("4" . chart-level-7)
      ("static" . chart-level-8)))

  ;; Draws the heap as strata: the young generation at the top, a tank
  ;; that fills to the line at which the collector is asked (held, while
  ;; a frame turn holds its collection off), then generations 1 to 4 and
  ;; the static one, each as thick as the root of its bytes, so that 2 MB
  ;; and 200 MB both show.
  (define (allocations-draw-column x y w h)
    (let* ([young (allocation-young)]
           [bytes (cdr (assq 'bytes young))]
           [limit (cdr (assq 'limit young))]
           [static (let ([b (bytes-allocated 'static)])
                     (if (fixnum? b) b 0))]
           [sizes (append (list bytes)
                          (map collector-generation-bytes '(1 2 3 4))
                          (list static))]
           ;; the tank is as tall as its limit, or as what it holds past it
           [rooms (cons (max bytes (or limit 0)) (cdr sizes))]
           [line (font-line-height 'ui-small)]
           [least (+ (* 2 line) 6)]
           [free (max 0 (- h (* 6 least)))]
           [roots (map (lambda (n) (sqrt (max n 1))) rooms)]
           [all (apply + roots)]
           [lw (quotient w 2)] [sx (+ x lw)] [sw (- w lw)])
      (let each ([layers allocations-draw-layers] [sizes sizes]
                 [rooms rooms] [roots roots] [ly y])
        (unless (null? layers)
          (let* ([lh (+ least (exact (floor (/ (* free (car roots)) all))))]
                 [color (cdar layers)])
            (draw-text x (ui-text-y (+ ly 2) 'ui-small)
                       (if (and (eq? layers allocations-draw-layers)
                                (not limit))
                           "young, held"
                           (caar layers))
                       'text-dim 'ui-small)
            (draw-text x (ui-text-y (+ ly 2 line) 'ui-small)
                       (allocations-bytes-text (car sizes)) 'text 'ui-small)
            (if (eq? layers allocations-draw-layers)
                ;; the tank: its level, and its limit as its top edge
                (let ([level (if (> (car rooms) 0)
                                 (quotient (* (- lh 2) (car sizes))
                                           (car rooms))
                                 0)])
                  (fill-box sx (- (+ ly lh) 1 level) sw level color)
                  (draw-line sx (+ ly 0.5) (+ sx sw) (+ ly 0.5)
                             (if limit 'chart-rule 'chart-flag)))
                (fill-box sx (+ ly 1) sw (- lh 1) color))
            (each (cdr layers) (cdr sizes) (cdr rooms) (cdr roots)
                  (+ ly lh)))))))

  ;; The app's icon: strata, the deeper the denser.
  (define (allocations-draw-icon x y s flags)
    (define (ink c) (ui-icon-ink flags c))
    (ui-icon-grid (x y s)
      (fill-box 4 4 16 4 (ink (alpha 'cyan 0.25)))
      (fill-box 4 9 16 4 (ink (alpha 'cyan 0.5)))
      (fill-box 4 14 16 6 (ink 'cyan))
      (draw-line 4 3.5 20 3.5 (ink 'text) 1.25)))

  (define-app (allocations) "Allocations" 'icon allocations-draw-icon
    (let ([ui (make-ui)]
          [tab 'who]          ; the view shown: who, where, collections
          [paths '(#f 0 0 0)] ; Where's tree, as allocation-paths gives it
          [places '()]        ; Where's rows, as allocation-places does
          [place #f]          ; the procedure chosen: (name file line)
          [files (make-hashtable string-hash string=?)]   ; a file's lines
          [held #f]           ; the tick the app is held at (seq), or #f
          [selected #f]       ; Who's row chosen: a subject
          [opened #f]         ; Collections' row chosen: a seq
          [last 0]            ; when Who's numbers were last made (ms),
          [last-tick #f]      ; and the newest tick then
          [who '()]           ; Who's rows: (subject bytes calls)
          [who-span 1]        ; the ms those bytes were allocated in
          [who-all 1]         ; all that was allocated then, bytes
          [who-ticks 1]       ; how many ticks that was
          [cursor 0]          ; the next collection to place on the Flow
          [marks (make-eqv-hashtable)]    ; tick -> (pause ns . held)
          [shares (make-hashtable equal-hash equal?)]   ; (tick . subject)
          [rows (make-eqv-hashtable)]     ; a collection's alist, by seq
          [rows-count -1]
          [band-row (make-vector 4 0)] [band-seq #f]
          [flow (ui-stream-new allocations-flow-rows 4
                               allocations-draw-strips)]
          [by 'owner]         ; Heap's view: by owner or by kind
          [heap-row #f]       ; Heap's row chosen: a node, or a kind
          [census #f]         ; the census shown, as allocation-census was
          [grown #f]          ; what grew from the mark to that census
          [leaves '()]        ; Heap's rows by owner: ((path . node) ...)
          [hours-seen -1]     ; the hours' count when Hours' rows were made
          [hours '()]         ; Hours' rows: (row now hour day values)
          [ours? #f])         ; whether this window turned the tap on
      ;; the newest tick shown
      (define (newest-tick) (or held (profile-newest-tick)))
      ;; A number of tick seq's row in the Flow: a band's bytes, then its
      ;; strips' words.
      (define (flow-word period)
        (lambda (seq j)
          (cond
            [(< j 4)
             (unless (eqv? band-seq seq)
               (allocations-tick-bands! band-row seq)
               (set! band-seq seq))
             (min allocations-bar-most (vector-ref band-row j))]
            [(= j 4)
             (let ([m (hashtable-ref marks seq #f)])
               (if m (allocations-pause-level (car m)) 0))]
            [(= j 5)
             (let ([m (hashtable-ref marks seq #f)])
               (if (and m (> (cdr m) 0)) 1 0))]
            [else (if (profile-tick-late? seq period) 1 0)])))
      ;; What subject allocated in tick seq, bytes, computed once.
      (define (share-of seq subject)
        (let ([key (cons seq subject)])
          (or (hashtable-ref shares key #f)
              (let ([n (fold-left
                        (lambda (sum use)
                          (if (equal? (profile-use-subject use) subject)
                              (+ sum (profile-use-bytes use))
                              sum))
                        0
                        (if (profile-tick-kept? seq)
                            (profile-tick-uses seq)
                            '()))])
                (when (> (hashtable-size shares) 20000)
                  (hashtable-clear! shares))
                (hashtable-set! shares key n)
                n))))
      ;; Makes Who's rows anew: the subjects of the last two seconds'
      ;; ticks, or of the tick held, the heaviest first.
      (define (who-renew!)
        (let* ([newest (newest-tick)]
               [ticks (if held
                          (allocations-ticks held 1)
                          (allocations-ticks newest 120))])
          (set! who
            (map (lambda (t)
                   (list (profile-total-what t) (profile-total-bytes t)
                         (profile-total-calls t)))
                 (sort (lambda (a b)
                         (> (profile-total-bytes a) (profile-total-bytes b)))
                       (filter (lambda (t)
                                 (profile-subject? (profile-total-what t)))
                               (profile-totals ticks #t)))))
          (set! who-ticks (max 1 (length ticks)))
          (set! who-span
            (max 1 (apply + (map (lambda (seq) (profile-tick-ref seq 'ms))
                                 ticks))))
          (set! who-all
            (max 1 (apply + (map (lambda (seq)
                                   (profile-tick-ref seq 'allocated))
                                 ticks))))
          (when (eq? tab 'where)
            (set! paths (allocations-trim (allocation-paths)))
            (set! places
              (let ([all (allocation-places)])
                (list-head all (min 200 (length all))))))
          (set! last-tick newest)
          (set! last (now-ms))))
      ;; Whether Who's numbers are due again: twice a second, or after 30
      ;; ticks, whichever comes first, and at once when a hold changes.
      (define (who-due?)
        (let ([newest (newest-tick)])
          (and newest
               (or (not last-tick)
                   (= last 0)
                   (and (not (eqv? newest last-tick))
                        (or (> (- (now-ms) last) 500)
                            (>= (abs (- newest last-tick)) 30)))))))
      (define (toolbar w)
        (let-values ([(tw th) (ui-tabs-size '("Who" "Where" "Collections"
                                              "Heap" "Hours"))]
                     [(kw kh) (ui-checkbox-size "Record")]
                     [(bw bh) (ui-button-size "Resume" #f)])
          (ui-toolbar
           0 0 w
           (list
            (list tw th
                  (lambda (x y w h)
                    (ui-tabs ui 'tab x y h
                             '(("Who" . who) ("Where" . where)
                               ("Collections" . collections) ("Heap" . heap)
                               ("Hours" . hours))
                             tab
                             (lambda (t) (set! tab t) (set! last 0)))))
            (list kw kh
                  (lambda (x y w h)
                    (ui-checkbox ui 'record x y w h "Record"
                                 (allocation-recording?)
                                 (lambda (on?)
                                   (set! ours? on?)
                                   (allocation-record! on?))
                                 'tip "Sample the stack as the world \
                                       allocates, to tell which procedures \
                                       do: (allocation-record! #t), then \
                                       (allocation-report)")))
            (list bw bh
                  (lambda (x y w h)
                    (ui-button ui 'hold x y w h (if held "Resume" "Hold")
                               (lambda ()
                                 (set! held (and (not held)
                                                 (profile-newest-tick)))
                                 (set! last 0))
                               'disabled (not (profile-newest-tick))
                               'tip (if held
                                        (format "Held at tick ~a; the \
                                                 profiler goes on" held)
                                        "Hold the picture where it is; \
                                         the profiler goes on"))))))))
      ;; Who allocates: a row a subject, with what it allocated a second
      ;; and a tick, its share of all that was allocated, and its calls.
      (define (draw-who x y w h)
        (ui-table
         ui 'who x y w h
         (let ([w (ui-table-room w)])
           `((who "Who" ,(* w 0.40))
             (rate "KB/s" ,(* w 0.15) right
                   "What it allocated a second, over the last two seconds")
             (tick "KB/tick" ,(* w 0.15) right "What it allocated a tick")
             (share "Share" ,(* w 0.15) right
                    "Its part of all that was allocated then")
             (calls "Calls" ,(* w 0.15) right)))
         who
         (find (lambda (row) (equal? (car row) selected)) who)
         (lambda (row)
           (set! selected (and (not (equal? (car row) selected)) (car row))))
         (lambda (row key cx cy cw ch flags)
           (let ([bytes (cadr row)])
             (case key
               [(who)
                (ui-draw-cell cx cy cw ch flags
                              (profile-subject-label (car row)))]
               [(rate)
                (ui-draw-cell cx cy cw ch flags
                              (format "~,1f" (/ (* bytes 1000.0) 1024
                                                who-span)))]
               [(tick)
                (ui-draw-cell cx cy cw ch flags
                              (format "~,1f" (/ bytes 1024.0 who-ticks)))]
               [(share)
                (ui-draw-cell cx cy cw ch flags
                              (format "~,1f%" (/ (* 100.0 bytes) who-all)))]
               [else
                (ui-draw-cell cx cy cw ch flags
                              (number->string (caddr row)))])))
         'tip (lambda (row)
                (format "~a: ~a in ~a ms~a" (profile-subject-label (car row))
                        (allocations-bytes-text (cadr row))
                        (exact (round who-span))
                        (if (equal? (car row) selected)
                            "; its share is drawn over the Flow's bars"
                            "")))))
      ;; Where the bytes are allocated: the tap's call paths as a flame
      ;; (a span, then the procedures from the outermost caller in); the
      ;; procedures by what their samples come down to; and the source of
      ;; the one chosen, its first line marked.
      (define (draw-where x y w h)
        (let* ([all (max 1 (caddr paths))]
               [row-h (ui-table-row-height)]
               [chosen (and place
                            (find (lambda (row)
                                    (equal? place
                                            (list (cdr (assq 'name row))
                                                  (cdr (assq 'file row))
                                                  (cdr (assq 'line row)))))
                                  places))]
               [lines (and place (cadr place) (caddr place)
                           (or (hashtable-ref files (cadr place) #f)
                               (let ([v (allocations-file-lines
                                         (cadr place))])
                                 (hashtable-set! files (cadr place) v)
                                 v)))]
               [source-h (if lines (* 10 (font-line-height 'mono-small)) 0)]
               [flame-h (quotient (- h source-h) 2)]
               [table-h (- h flame-h source-h 16)])
          (if (= (caddr paths) 0)
              (ui-draw-label x y w 0 '(hint wrap)
                             "No samples yet: the tap records while Record \
                              is checked, a sample every 64 KB or so.")
              (ui-flame
               ui 'flame x y w flame-h paths
               allocations-node-label caddr cddddr
               'tip (lambda (node)
                      (let ([what (car node)])
                        (format "~a: ~a, ~,1f%~a"
                                (allocations-node-label node)
                                (allocations-bytes-text (caddr node))
                                (/ (* 100.0 (caddr node)) all)
                                (if (and (pair? what)
                                         (not (eq? (car what) 'span))
                                         (cadr what))
                                    (format " (~a)"
                                            (allocations-place-text
                                             (cadr what) (caddr what)))
                                    ""))))
               'on-pick (lambda (node)
                          (let ([what (car node)])
                            (when (and (pair? what)
                                       (not (eq? (car what) 'span)))
                              (set! place what))))))
          (ui-table
           ui 'places x (+ y flame-h 8) w table-h
           (let ([w (ui-table-room w)])
             `((name "Procedure" ,(* w 0.32))
               (place "Source" ,(* w 0.26))
               (own "Own" ,(* w 0.14) right
                    "The bytes of the samples where it is the innermost \
                     procedure that has a source: the place in a \
                     program's own code that they come down to")
               (self "Self" ,(* w 0.14) right
                     "The bytes of the samples whose innermost procedure \
                      it is")
               (total "Total" ,(* w 0.14) right
                      "The bytes of the samples it is anywhere in")))
           places chosen
           (lambda (row)
             (let ([it (list (cdr (assq 'name row)) (cdr (assq 'file row))
                             (cdr (assq 'line row)))])
               (set! place (and (not (equal? it place)) it))))
           (lambda (row key cx cy cw ch flags)
             (let ([ref (lambda (name) (cdr (assq name row)))])
               (ui-draw-cell
                cx cy cw ch flags
                (case key
                  [(name) (or (ref 'name) "(no name)")]
                  [(place) (allocations-place-text (ref 'file) (ref 'line))]
                  [else (allocations-bytes-text (ref key))]))))
           'tip (lambda (row)
                  (format "~a: ~a, ~,1f% of the bytes sampled"
                          (or (cdr (assq 'name row)) "(no name)")
                          (allocations-bytes-text (cdr (assq 'own row)))
                          (/ (* 100.0 (cdr (assq 'own row))) all))))
          (when lines
            ;; from two lines above the procedure's first on
            (let* ([line (caddr place)]
                   [from (max 1 (- line 2))]
                   [to (min (vector-length lines) (+ from 40))])
              (ui-source ui 'source x (+ y flame-h 8 table-h 8) w source-h
                         (map (lambda (i) (vector-ref lines (- i 1)))
                              (map (lambda (k) (+ from k))
                                   (iota (max 0 (- to from -1)))))
                         'first from 'marked (- line from))))))
      ;; What the log has of collection seq, read once.
      (define (collection seq)
        (or (hashtable-ref rows seq #f)
            (let ([c (allocation-collection seq)])
              (hashtable-set! rows seq c)
              c)))
      ;; The log of collections, the newest first, and under it the one
      ;; chosen, generation by generation.
      (define (draw-collections x y w h)
        (let* ([count (allocation-collection-count)]
               [line (font-line-height 'ui)]
               [th (- h line line 8)]
               [me (if (threaded?) (get-thread-id) 0)]
               [seqs (filter collection
                             (map (lambda (i) (- count 1 i))
                                  (iota (min count 500))))]
               [ref (lambda (seq name)
                      (let ([c (collection seq)])
                        (and c (cdr (assq name c)))))])
          (unless (= count rows-count)
            (hashtable-clear! rows)
            (set! rows-count count))
          (ui-table
           ui 'collections x y w th
           (let ([w (ui-table-room w)])
             `((seq "#" ,(* w 0.08) right)
               (pass "Pass" ,(* w 0.10)
                     "young: generation 0 into 1; middle: 1 into 2; old: 3 \
                      into itself; settle: all into 4")
               (pause "Pause" ,(* w 0.11) right)
               (allocated "Allocated" ,(* w 0.13) right
                          "Since the collection before")
               (survived "Kept" ,(* w 0.12) right
                         "What the generations above the young one grew by")
               (rate "Kept %" ,(* w 0.09) right)
               (held "Held" ,(* w 0.12) right
                     "How long its request was held off, till a frame \
                      was out")
               (by "By" ,(* w 0.10)
                   "The thread that performed it; loose: another thread, \
                    while a span other than the collector's was open, \
                    whose bytes are then off by some KB")
               (span "Asked from" ,(* w 0.15))))
           seqs opened
           (lambda (seq) (set! opened (and (not (eqv? seq opened)) seq)))
           (lambda (seq key cx cy cw ch flags)
             (ui-draw-cell
              cx cy cw ch flags
              (case key
                [(seq) (number->string seq)]
                [(pass) (symbol->string (ref seq 'pass))]
                [(pause) (profile-ns-label (ref seq 'pause))]
                [(allocated)
                 (let ([n (ref seq 'allocated)])
                   (if n (allocations-bytes-text n) "–"))]
                [(survived) (allocations-bytes-text (ref seq 'survived))]
                [(rate)
                 (let ([n (ref seq 'allocated)])
                   (if (and n (> n 0))
                       (format "~,1f%" (/ (* 100.0 (ref seq 'survived)) n))
                       "–"))]
                [(held)
                 (if (> (ref seq 'held) 0)
                     (profile-ns-label (ref seq 'held-ns))
                     "–")]
                [(by)
                 (string-append (if (eqv? (ref seq 'thread) me)
                                    "core1"
                                    "core0")
                                (if (ref seq 'loose) ", loose" ""))]
                [else
                 (let ([span (ref seq 'span)])
                   (cond [(not (car span)) "–"]
                         [(eq? (car span) 'gc) "the collector"]
                         [else (format "~a~a" (car span)
                                       (if (symbol? (cdr span))
                                           (format " ~a" (cdr span))
                                           ""))]))])))
           'tip (lambda (seq)
                  (format "#~a: ~a, ~a kept of ~a" seq (ref seq 'pass)
                          (allocations-bytes-text (ref seq 'survived))
                          (let ([n (ref seq 'allocated)])
                            (if n (allocations-bytes-text n) "–")))))
          (when (and opened (collection opened))
            (let ([before (ref opened 'before)] [after (ref opened 'after)])
              (ui-draw-label
               x (+ y th 8) w line '(dim)
               (apply string-append
                      (format "#~a, by generation: " opened)
                      (map (lambda (g b a)
                             (format "~a: ~a to ~a~a" g
                                     (allocations-bytes-text b)
                                     (allocations-bytes-text a)
                                     (if (= g 4) "" "; ")))
                           '(0 1 2 3 4) before after)))))))
      ;; The heap as the last census found it: by owner (the code and
      ;; names, each layer's libraries and their states, the windows, the
      ;; processes) or by kind, as a treemap and as a table, with what
      ;; grew since the mark.
      (define (draw-heap x y w h)
        (unless (eq? census (allocation-census))
          (set! census (allocation-census))
          (set! grown (allocation-census-grown))
          (set! heap-row #f)
          (set! leaves (if census
                           (allocations-owner-leaves
                            (cdr (assq 'owners census)))
                           '())))
        (let*-values
            ([(cw ch) (ui-button-size "Take a census" #f)]
             [(mw mh) (ui-button-size "Mark" #f)]
             [(tw th) (ui-tabs-size '("By owner" "By kind"))]
             [(bar)
              (ui-toolbar
               x y w
               (list
                (list cw ch
                      (lambda (x y w h)
                        (ui-button ui 'census x y w h "Take a census"
                                   (lambda () (allocation-census!))
                                   'tip "A full collection that counts the \
                                         live heap by kind and by owner: \
                                         the world stops for it, some \
                                         100 ms. (allocation-census!) at a \
                                         REPL")))
                (list mw mh
                      (lambda (x y w h)
                        (ui-button ui 'mark x y w h "Mark"
                                   (lambda ()
                                     (allocation-census-mark!)
                                     (set! grown #f))
                                   'disabled (not census)
                                   'tip "Keep this census, so that the next \
                                         one shows what grew since")))
                (list tw th
                      (lambda (x y w h)
                        (ui-tabs ui 'by x y h
                                 '(("By owner" . owner) ("By kind" . kind))
                                 by
                                 (lambda (b)
                                   (set! by b)
                                   (set! heap-row #f)))))))]
             [(line) (font-line-height 'ui)]
             [(top) (+ y bar 4)])
          (if (not census)
              (ui-draw-label x top w 0 '(hint wrap)
                             "No census yet: Take a census counts the live \
                              heap by owner (the code, each library's \
                              states, each window and process) and by \
                              kind.")
              (let* ([all (max 1 (cdr (assq 'bytes census)))]
                     [map-h (quotient (* 11 (- h bar line 12)) 20)]
                     [table-y (+ top line 4 map-h 8)]
                     [table-h (- (+ y h) table-y)]
                     [what-kind (if (eq? by 'owner) 'owners 'kinds)]
                     [since (lambda (what)
                              (and grown
                                   (let ([x (assoc what
                                                   (cdr (assq what-kind
                                                              grown)))])
                                     (and x (cdr x)))))]
                     [since-text (lambda (what)
                                   (let ([n (since what)])
                                     (if n
                                         (format ", ~a since the mark"
                                                 (allocations-change-text n))
                                         "")))])
                (ui-draw-label
                 x top w line '(dim)
                 (format "A census ~a: ~a live; a pause of ~a, and ~a to \
                          charge the owners~a"
                         (allocations-ago (cdr (assq 'at census)))
                         (allocations-bytes-text (cdr (assq 'bytes census)))
                         (profile-ns-label (cdr (assq 'pause census)))
                         (profile-ns-label (cdr (assq 'charge census)))
                         (if grown
                             (format "; ~a since the mark, ~a"
                                     (allocations-change-text
                                      (- (cdr (assq 'bytes census))
                                         (cdr (assq 'bytes grown))))
                                     (allocations-ago (cdr (assq 'at grown))))
                             "")))
                (ui-treemap
                 ui (list 'heap by) x (+ top line 4) w map-h
                 (if (eq? by 'owner)
                     (cdr (assq 'owners census))
                     (allocations-kind-tree census))
                 (lambda (node)
                   (format "~a  ~a" (car node)
                           (allocations-bytes-text (cadr node))))
                 cadr cddr
                 'key car
                 'selected (and (pair? heap-row) heap-row)
                 'tip (lambda (node)
                        (format "~a: ~a, ~,1f% of the heap" (car node)
                                (allocations-bytes-text (cadr node))
                                (/ (* 100.0 (cadr node)) all))))
                (if (eq? by 'owner)
                    (ui-table
                     ui 'owners x table-y w table-h
                     (let ([w (ui-table-room w)])
                       `((owner "Owner" ,(* w 0.34))
                         (in "In" ,(* w 0.26)
                             "The library whose state it is, or windows, \
                              or processes")
                         (bytes "Bytes" ,(* w 0.14) right
                                "What it alone reaches")
                         (share "Share" ,(* w 0.12) right)
                         (since "Since mark" ,(* w 0.14) right)))
                     leaves
                     (find (lambda (l) (eq? (cdr l) heap-row)) leaves)
                     (lambda (l)
                       (set! heap-row (and (not (eq? (cdr l) heap-row))
                                           (cdr l))))
                     (lambda (l key cx cy cw ch flags)
                       (let ([path (car l)] [node (cdr l)])
                         (ui-draw-cell
                          cx cy cw ch flags
                          (case key
                            [(owner) (car node)]
                            [(in) (let ([p (cdr (reverse path))])
                                    (if (or (null? p) (null? (cdr p)))
                                        ""
                                        (car p)))]
                            [(bytes) (allocations-bytes-text (cadr node))]
                            [(share) (format "~,1f%" (/ (* 100.0 (cadr node))
                                                        all))]
                            [else (allocations-change-text (since path))]))))
                     'tip (lambda (l)
                            (format "~a: ~a~a" (car (cdr l))
                                    (allocations-bytes-text (cadr (cdr l)))
                                    (since-text (car l)))))
                    (let ([kinds (cdr (assq 'kinds census))])
                      (ui-table
                       ui 'kinds x table-y w table-h
                       (let ([w (ui-table-room w)])
                         `((kind "Kind" ,(* w 0.36))
                           (count "Count" ,(* w 0.16) right)
                           (bytes "Bytes" ,(* w 0.16) right)
                           (share "Share" ,(* w 0.14) right)
                           (since "Since mark" ,(* w 0.18) right)))
                       kinds
                       (find (lambda (k) (eq? (car k) heap-row)) kinds)
                       (lambda (k)
                         (set! heap-row (and (not (eq? (car k) heap-row))
                                             (car k))))
                       (lambda (k key cx cy cw ch flags)
                         (ui-draw-cell
                          cx cy cw ch flags
                          (case key
                            [(kind) (format "~a" (car k))]
                            [(count) (number->string (cadr k))]
                            [(bytes) (allocations-bytes-text (caddr k))]
                            [(share) (format "~,1f%" (/ (* 100.0 (caddr k))
                                                        all))]
                            [else (allocations-change-text
                                   (since (car k)))])))
                       'tip (lambda (k)
                              (format "~a: ~a objects, ~a~a" (car k) (cadr k)
                                      (allocations-bytes-text (caddr k))
                                      (since-text (car k)))))))))))
      ;; Makes Hours' rows anew: each field's value now, its slope over
      ;; the last hour and over all the rows kept, and its line.
      (define (hours-renew!)
        (set! hours-seen (allocation-hours-count))
        (set! hours
          (map (lambda (row)
                 (let ([values (allocation-hours (car row))])
                   (list row
                         (if (null? values) 0 (car (reverse values)))
                         (allocation-hours-slope (car row) 60)
                         (allocation-hours-slope (car row))
                         (allocations-thin values 240))))
               allocations-hours-rows)))
      ;; What the heap held a minute at a time over the last two days: each
      ;; generation, what Chez and the process hold, the GPU's bytes and
      ;; the longest pause, with how fast each grew.
      (define (draw-hours x y w h)
        (unless (= hours-seen (allocation-hours-count)) (hours-renew!))
        (let* ([count (allocation-hours-count)]
               [line (font-line-height 'ui)]
               [per-day (lambda (n)
                          (if n
                              (string-append
                               (allocations-change-text (exact (round n)))
                               " a day")
                              "–"))])
          (ui-draw-label
           x y w line '(dim)
           (if (< count 2)
               "A row a minute; how fast each grows shows from the second \
                row on."
               (format "~a rows, a minute apart, the newest ~a"
                       (min count 2880)
                       (allocations-ago
                        (car (reverse (allocation-hours 'at)))))))
          (ui-table
           ui 'hours x (+ y line 8) w (- h line 8)
           (let ([w (ui-table-room w)])
             `((what "What" ,(* w 0.20))
               (now "Now" ,(* w 0.13) right)
               (hour "Last hour" ,(* w 0.17) right
                     "How fast it grew over the last hour, a day")
               (day "Two days" ,(* w 0.17) right
                    "How fast it grew over the rows kept, a day")
               (line "Over the rows kept" ,(* w 0.33))))
           hours #f (lambda (row) (void))
           (lambda (row key cx cy cw ch flags)
             (let ([bytes? (eq? (caddr (car row)) 'bytes)])
               (if (eq? key 'line)
                   (ui-draw-sparkline (+ cx 4) (+ cy 3) (- cw 8) (- ch 6)
                                      flags (list-ref row 4))
                   (ui-draw-cell
                    cx cy cw ch flags
                    (case key
                      [(what) (cadr (car row))]
                      [(now) (if bytes?
                                 (allocations-bytes-text (cadr row))
                                 (profile-ns-label (cadr row)))]
                      [(hour) (if bytes? (per-day (caddr row)) "–")]
                      [else (if bytes? (per-day (cadddr row)) "–")])))))
           'tip (lambda (row)
                  (format "~a: ~a" (cadr (car row))
                          (if (eq? (caddr (car row)) 'bytes)
                              (allocations-bytes-text (cadr row))
                              (profile-ns-label (cadr row))))))))
      ;; The Flow: a bar a tick, its bytes banded by who, the collections,
      ;; the requests held and the late ticks over it, and the chosen
      ;; row's share over its bars. A press holds the app at that tick.
      (define (draw-flow x y w h)
        (let*-values
            ([(newest) (newest-tick)]
             [(oldest) (profile-oldest-tick)]
             [(period) (pacer-period)]
             [(keys) (append allocations-draw-bands
                             (if selected
                                 (list (cons 'chart-share
                                             (profile-subject-label
                                              selected)))
                                 '()))]
             [(kw kh) (ui-legend-size keys)]
             [(gh) (- h kh 4)]
             [(top) (allocations-top
                     (map (lambda (seq)
                            (min allocations-bar-most
                                 (profile-tick-ref seq 'allocated)))
                          (allocations-ticks newest 240)))])
          (when newest
            (set! cursor (allocations-place! marks cursor newest))
            (ui-stream-send! flow oldest newest (flow-word period))
            (ui-stream
             ui 'flow flow x y w gh newest oldest top
             (list (cons (quotient top 2)
                         (allocations-bytes-text (quotient top 2))))
             (map (lambda (j band) (cons j (car band)))
                  '(0 1 2 3) allocations-draw-bands)
             3
             'tip (lambda (seq)
                    (and (profile-tick-kept? seq)
                         (let ([m (hashtable-ref marks seq #f)])
                           (format "tick ~a: ~a allocated~a" seq
                                   (allocations-bytes-text
                                    (profile-tick-ref seq 'allocated))
                                   (if m
                                       (format "; a collection of ~a"
                                               (profile-ns-label (car m)))
                                       "")))))
             'on-pick (lambda (seq) (set! held seq) (set! last 0))
             'doc '((L . "Hold here"))
             'marked (if held (list held) '())
             'over
             (lambda (areas count)
               (when selected
                 (let-values ([(px py pw ph)
                               (apply values (cdr (assq 'bars areas)))])
                   (do ([i 0 (+ i 1)]) ((= i count))
                     (let-values ([(bx bw) (ui-bar-chart-bar areas count i)])
                       (let* ([n (share-of (+ newest (- i count -1))
                                           selected)]
                              [high (div (* ph (min n top)) top)])
                         (when (and (>= bx px) (> high 0))
                           (fill-box bx (- (+ py ph) high)
                                     (- bw (if (>= bw 3) 1 0)) high
                                     'chart-share))))))))))
          (ui-draw-legend x (+ y gh 4) w kh '() keys)))
      (define (draw win w h)
        (ui-begin! ui)
        (ui-draw-surface 0 0 w h '(page))
        (let* ([pad (ui-pad)]
               [y (+ (toolbar w) pad)]
               [column-w (* 22 (font-char-width 'ui-small))]
               [flow-h (max 96 (quotient (- h y) 3))]
               [view-w (- w pad pad column-w pad)]
               [view-h (- h y flow-h pad pad)])
          (cond
            ;; the census and the hours need no profiler
            [(eq? tab 'heap) (draw-heap pad y view-w view-h)]
            [(eq? tab 'hours) (draw-hours pad y view-w view-h)]
            [(not (profile-on?))
             (ui-draw-label pad y view-w 0 '(hint wrap)
                            "Profiling is off: type (profile-on! #t) in a \
                             REPL, or check Profiling in Monitor, to see \
                             what allocates.")]
            [else
             (when (who-due?) (who-renew!))
             (case tab
               [(who) (draw-who pad y view-w view-h)]
               [(where) (draw-where pad y view-w view-h)]
               [else (draw-collections pad y view-w view-h)])])
          (allocations-draw-column (+ pad view-w pad) y column-w view-h)
          (when (profile-on?)
            (draw-flow pad (+ y view-h pad) (- w pad pad) flow-h)))
        (ui-end! ui w h))
      (apply open-window "Allocations"
             'size (cons (max 720 (* 96 (font-char-width 'ui)))
                         (max 560 (* 22 (ui-table-row-height))))
             'min-size '(480 . 400)
             'draw (lambda (win w h) (draw win w h))
             'close (lambda (win)
                      (ui-stream-release! flow)
                      (when ours? (allocation-record! #f)))
             (append
              (ui-handlers ui)
              ;; while the window is seen, it is drawn again at each tick;
              ;; and the tap records from its opening, unless one records
              ;; already
              (list 'open (lambda (win)
                            (unless (allocation-recording?)
                              (set! ours? #t)
                              (allocation-record! #t))
                            (window-frame-soon! win))
                    'frame (lambda (win t)
                             (window-frame-soon! win)
                             (ui-frame ui win)
                             (unless held (invalidate! win)))))))))
