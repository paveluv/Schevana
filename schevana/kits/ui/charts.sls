;;; (schevana kits ui charts) — a part of the ui kit ((schevana kits ui)),
;;; which gives its names: charts: bar and line charts, sparklines and
;;; legends, flames, treemaps, source and streams.

(library (schevana kits ui charts)
  (export
    ui-bar-chart ui-bar-chart-areas* ui-bar-chart-bar ui-draw-bar-chart*
    ui-draw-flame-box* ui-flame ui-draw-treemap-box* ui-treemap
    ui-draw-source-surface* ui-draw-source-line* ui-source ui-stream-rows
    ui-stream-sent ui-stream-new ui-stream-restart! ui-stream-resend!
    ui-stream-release! ui-stream-send! ui-stream-lane* ui-stream-room
    ui-stream-areas* ui-stream-count ui-stream-layout ui-draw-stream* ui-stream
    ui-draw-sparkline ui-draw-sparkline* ui-draw-line-chart ui-draw-line-chart*
    ui-draw-legend ui-draw-legend* ui-legend-size ui-legend-size*)
  (import (chezscheme)
          (only (schevana base) at-load define-hook library-layer plist-ref)
          (only (schevana core) alpha color-default! color-word current-window
                define-paint define-part define-shader-constant
                define-shader-layout draw-line draw-polyline draw-scale
                draw-text fill-box fill-shader font-line-height
                gpu-buffer-release! gpu-buffer-set! make-gpu-buffer point-in?
                stipple stipple? stroke-box text-width theme window-hover)
          (only (schevana kits text) text-widest text-fit)
          (schevana kits ui base))

  (library-layer kits)


  ;;; ------------------------------------------------------------------
  ;;; charts: stacked bars, lines, a sparkline, a legend
  ;;; A series is drawn in the color the app gives it. The kit's chart-1 to
  ;;; chart-8 are settings made from the palette's hues, so that a style can
  ;;; give its own (Genera, which has no color, stipples), and chart-muted-1
  ;;; and chart-muted-2 are two quiet ones for what is not work (time
  ;;; waited, say): a flat gray and a lined one, told apart by their texture
  ;;; in any palette. A mark behind a bar, a share of the bars, the
  ;;; reference lines and a flag over a bar are chart-mark, chart-share,
  ;;; chart-rule and chart-flag; a mark that says all is well is chart-ok, a
  ;;; quiet color, so that a flag stands out from it. A mark that says how
  ;;; much (how long a collection took, say) is chart-level-1, the faintest,
  ;;; to chart-level-8: chart-7 from a fifth to the whole of it.

  (at-load
   (color-default! 'chart-1 'yellow))
  (at-load
   (color-default! 'chart-2 'orange))
  (at-load
   (color-default! 'chart-3 'magenta))
  (at-load
   (color-default! 'chart-4 'green))
  (at-load
   (color-default! 'chart-5 'cyan))
  (at-load
   (color-default! 'chart-6 'teal))
  (at-load
   (color-default! 'chart-7 'red))
  (at-load
   (color-default! 'chart-8 'accent-2))
  (at-load
   (color-default! 'chart-muted-1 (alpha 'text 0.2)))
  (at-load
   (color-default! 'chart-muted-2
                   (stipple (alpha 'text 0.5) (alpha 'text 0.12) "#" "." ".")))
  (at-load
   (color-default! 'chart-mark (alpha 'text 0.12)))
  (at-load
   (color-default! 'chart-share 'accent))
  (at-load
   (color-default! 'chart-rule 'text-faint))
  (at-load
   (color-default! 'chart-flag 'red))
  (at-load
   (color-default! 'chart-ok (alpha 'green 0.55)))
  (at-load
   (color-default! 'chart-level-1 (alpha 'chart-7 7/35)))
  (at-load
   (color-default! 'chart-level-2 (alpha 'chart-7 11/35)))
  (at-load
   (color-default! 'chart-level-3 (alpha 'chart-7 15/35)))
  (at-load
   (color-default! 'chart-level-4 (alpha 'chart-7 19/35)))
  (at-load
   (color-default! 'chart-level-5 (alpha 'chart-7 23/35)))
  (at-load
   (color-default! 'chart-level-6 (alpha 'chart-7 27/35)))
  (at-load
   (color-default! 'chart-level-7 (alpha 'chart-7 31/35)))
  (at-load
   (color-default! 'chart-level-8 (alpha 'chart-7 1)))

  ;; A stacked bar chart, one bar per value (a step, say), the newest at the
  ;; right. bars, oldest first, are (segments . share): segments are ((color
  ;; . value) ...) from the bottom up, and share is how much of the bar to
  ;; show in chart-share (#f for none). Values are exact integers (ns, say),
  ;; so the bars' pixels are worked out in integers. top is the value at the
  ;; chart's top; rules are ((value . label) ...), reference lines labeled
  ;; in a scale at the left. The bar marked (its index, or #f) and the one
  ;; under the pointer show a mark; a left press on a bar calls (on-press
  ;; index). opts: 'tip, a procedure of a bar's index that returns its
  ;; tooltip (asked only for the bar under the pointer), or #f; 'flagged, a
  ;; procedure of a bar's index, true for a bar to flag at the chart's top
  ;; (a late step, say). Returns the index of the bar under the pointer, or
  ;; #f.
  ;; ui-bar-chart-under returns the bar of n that the pointer is over, by
  ;; where the bars are, or #f.
  (define (ui-bar-chart-under ui areas n)
    (let ([plot (cdr (assq 'plot areas))] [win (current-window)]
          [mx (ui-state-mx ui)] [my (ui-state-my ui)])
      (and win (eq? (window-hover win) 'content)
           (point-in? mx my (car plot) (cadr plot) (caddr plot) (cadddr plot))
           (let ([i (- n 1 (exact (floor (/ (- (+ (car plot) (caddr plot)) mx)
                                            (cadr (assq 'bar areas))))))])
             (and (<= 0 i) i)))))

  (define (ui-bar-chart ui id x y w h bars top rules marked on-press . opts)
    (let* ([n (length bars)] [areas (ui-bar-chart-areas x y w h n rules)]
           [plot (cdr (assq 'plot areas))] [win (current-window)]
           [tip-of (plist-ref opts 'tip #f)]
           [flagged? (plist-ref opts 'flagged (lambda (i) #f))]
           [under (and tip-of (ui-bar-chart-under ui areas n))])
      (for-each (lambda (i)
                  (let-values ([(bx bw) (ui-bar-chart-bar areas n i)])
                    (when (>= bx (car plot))
                      (ui-region! ui (list id i) bx (cadr plot) bw (cadddr plot)
                        'doc '((L . "Select"))
                        'tip (and (eqv? i under) (tip-of i))
                        'on (lambda (ev)
                              (and (eq? (car ev) 'press)
                                   (eq? (list-ref ev 3) 'left)
                                   (begin (on-press i) #t)))))))
                (iota n))
      (let* ([r (ui-region-at ui (ui-state-mx ui) (ui-state-my ui))]
             [rid (and r (ui-region-id r))]
             [hover (and win (eq? (window-hover win) 'content) (pair? rid)
                         (equal? (car rid) id) (pair? (cdr rid)) (cadr rid))])
        (ui-draw-bar-chart x y w h '()
                           (map (lambda (b i)
                                  (list (car b) (cdr b)
                                        (cond [(eqv? i hover) 'hover]
                                              [(eqv? i marked) 'marked]
                                              [else #f])
                                        (and (flagged? i) #t)))
                                bars (iota n))
                           top rules)
        hover)))

  ;; A bar chart's pieces, as ((plot x y w h) (bar w)): the plot, right of
  ;; the scale's labels and 4 clear of the top and right edges, on whole
  ;; pixels, and the bars' width for n bars, in whole pixels, at least 1 and
  ;; at most 6.
  (define-part (ui-bar-chart-areas x y w h n rules)
    (let* ([px (exact (ceiling (+ x 12 (text-widest (map cdr rules)
                                                     'ui-small))))]
           [py (exact (ceiling (+ y 4)))]
           [pw (max 0 (exact (floor (- (+ x w) 4 px))))]
           [ph (max 0 (exact (floor (- (+ y h) py))))])
      (list (list 'plot px py pw ph)
            (list 'bar (max 1 (min 6 (quotient pw (max n 1))))))))

  ;; Returns bar i of n by the areas, as (values x w): the newest is at the
  ;; plot's right, and a bar left of the plot does not fit.
  (define (ui-bar-chart-bar areas n i)
    (let ([plot (cdr (assq 'plot areas))] [bw (cadr (assq 'bar areas))])
      (values (+ (car plot) (- (caddr plot) (* bw (- n i)))) bw)))

  ;; bars: each is (segments share mark flag), with mark hover, marked or
  ;; #f, and flag true for a strip at the plot's top over the bar. The
  ;; segments of one color are filled together. A segment's top is where
  ;; the sum up to it rounds down to, in whole pixels, so that a bar's
  ;; segments meet.
  (define-part (ui-draw-bar-chart x y w h flags bars top rules)
    (let* ([n (length bars)] [areas (ui-bar-chart-areas x y w h n rules)]
           [plot (cdr (assq 'plot areas))] [px (car plot)] [py (cadr plot)]
           [pw (caddr plot)] [ph (cadddr plot)] [bottom (+ py ph)]
           [high (lambda (v) (if (> top 0) (div (* ph (min v top)) top) 0))]
           [rects (make-eq-hashtable)]   ; color -> ((x y w h) ...)
           [colors '()])                 ; the series' colors, in order
      (define (rect! color r)
        (unless (or (hashtable-contains? rects color)
                    (memq color '(chart-mark chart-share chart-flag)))
          (set! colors (cons color colors)))
        (hashtable-update! rects color (lambda (rs) (cons r rs)) '()))
      (ui-draw-surface x y w h '(well))
      (for-each
       (lambda (bar i)
         (let-values ([(bx bw) (ui-bar-chart-bar areas n i)])
           (when (>= bx px)
             (let ([gap (if (>= bw 3) 1 0)])
               (when (caddr bar) (rect! 'chart-mark (list bx py bw ph)))
               (fold-left (lambda (sum s)
                            (let* ([below (high sum)]
                                   [above (high (+ sum (cdr s)))])
                              (when (> above below)
                                (rect! (car s)
                                       (list bx (- bottom above) (- bw gap)
                                             (- above below))))
                              (+ sum (cdr s))))
                          0 (car bar))
               (when (cadr bar)
                 (let ([sh (high (cadr bar))])
                   (rect! 'chart-share
                          (list bx (- bottom sh) (- bw gap) sh))))
               (when (cadddr bar)
                 (rect! 'chart-flag (list bx py (- bw gap) 3)))))))
       bars (iota n))
      ;; The marks go under the series, and the share and the flags over
      ;; them.
      (for-each (lambda (c)
                  (let ([rs (hashtable-ref rects c '())])
                    (for-each (lambda (r)
                                (fill-box (car r) (cadr r) (caddr r) (cadddr r)
                                          c))
                              rs)))
                (append '(chart-mark) (reverse colors)
                        '(chart-share chart-flag)))
      (ui-draw-bar-chart-rules x areas top rules)))

  ;; Draws a chart's reference lines over its bars, and their labels in its
  ;; scale. A rule at #f only widens the labels' room, so that charts
  ;; stacked one over another can line their bars up.
  (define (ui-draw-bar-chart-rules x areas top rules)
    (let* ([plot (cdr (assq 'plot areas))] [px (car plot)] [pw (caddr plot)]
           [ph (cadddr plot)] [bottom (+ (cadr plot) ph)])
      (for-each (lambda (r)
                  (let ([ly (+ (- bottom (if (> top 0)
                                             (div (* ph (min (car r) top)) top)
                                             0))
                               0.5)])
                    (draw-line px ly (+ px pw) ly 'chart-rule)
                    (draw-text (+ x 6)
                               (ui-text-y (- ly (/ (font-line-height 'ui-small)
                                                   2))
                                          'ui-small)
                               (cdr r) 'text-faint 'ui-small)))
                (filter car rules))))

  ;;; ------------------------------------------------------------------
  ;;; flames: where a total goes, level by level. A tree is drawn as boxes
  ;;; in rows, the root across the top and each node's children under it,
  ;;; a box as wide as its value's share of the root shown. A press on a
  ;;; box makes it the root shown, and a press on the root shown goes back
  ;;; out one level.
  ;;;
  ;;;   (ui-flame ui 'id x y w h tree label value children 'tip tip)
  ;;;
  ;;; tree is the app's own value, and label, value and children read a
  ;;; node of it: a string, a number no less than its children's together,
  ;;; and a list.

  ;; A flame's box: an outline and a name, so that it reads in one bit too,
  ;; and filled while the pointer is over it or it is selected. flags may
  ;; have hover and selected; depth counts from the root shown. The label
  ;; is drawn where it fits.
  (define-part (ui-draw-flame-box x y w h flags label depth)
    (when (or (memq 'selected flags) (memq 'hover flags))
      (fill-box x y (max 1 (- w 1)) (- h 1)
                (if (memq 'selected flags) 'chart-level-4 'chart-level-2)
                2))
    (when (>= w 3)
      (stroke-box (+ x 0.5) (+ y 0.5) (- w 2) (- h 2) 'chart-rule 1 2))
    (when (>= w (+ 10 (text-width label 'ui-small)))
      (draw-text (+ x 5) (+ y (/ (- h 1 (font-line-height 'ui-small)) 2))
                 label 'text 'ui-small)))

  (define (ui-flame-row-height) (+ (font-line-height 'ui-small) 7))

  ;; opts: 'tip (node), a box's tooltip or #f; 'on-pick (node), called on a
  ;; left press on a box; 'selected, the node drawn as selected (eq?);
  ;; 'key (node), what tells a node from its siblings, its label by
  ;; default. The root shown is kept as the keys on the way to it, so it
  ;; stays the same node while the tree is made anew around it. Rows past
  ;; the height and boxes under two pixels are left out. Returns the node
  ;; under the pointer, or #f.
  (define (ui-flame ui id x y w h tree label value children . opts)
    (define (opt name) (let ([o (memq name opts)]) (and o (cadr o))))
    (let* ([tip (opt 'tip)] [on-pick (opt 'on-pick)]
           [selected (opt 'selected)] [key (or (opt 'key) label)]
           [rh (ui-flame-row-height)] [under #f]
           ;; the root shown, and the keys that still lead somewhere
           [way (let walk ([node tree] [keys (ui-memo ui (list id 'way) '())]
                           [taken '()])
                  (let ([next (and (pair? keys)
                                   (find (lambda (c)
                                           (equal? (key c) (car keys)))
                                         (children node)))])
                    (if next
                        (walk next (cdr keys) (cons (car keys) taken))
                        (cons node (reverse taken)))))]
           [root (car way)] [keys (cdr way)])
      (ui-memo! ui (list id 'way) keys)
      (let draw ([node root] [depth 0] [bx x] [bw w] [path keys])
        (when (and (>= bw 2) (<= (* (+ depth 1) rh) h))
          (let* ([by (+ y (* depth rh))]
                 [hover? (ui-hover? ui bx by bw rh)]
                 [text (and tip (tip node))])
            (when hover? (set! under node))
            (ui-draw-flame-box bx by bw rh
                               (append (if hover? '(hover) '())
                                       (if (eq? node selected)
                                           '(selected)
                                           '()))
                               (label node) depth)
            (ui-pressable! ui (list id 'box path) bx by bw rh
                           (lambda ()
                             (when on-pick (on-pick node))
                             (ui-memo! ui (list id 'way)
                                       (if (and (= depth 0) (pair? path))
                                           (reverse (cdr (reverse path)))
                                           path)))
                           '()
                           (append '(focus keep)
                                   (if text (list 'tip text) '())))
            (let ([total (value node)])
              (when (> total 0)
                (let each ([cs (children node)] [cx bx])
                  (unless (null? cs)
                    (let ([cw (inexact (/ (* bw (value (car cs))) total))])
                      (draw (car cs) (+ depth 1) cx cw
                            (append path (list (key (car cs)))))
                      (each (cdr cs) (+ cx cw))))))))))
      under))

  ;;; ------------------------------------------------------------------
  ;;; treemaps: where a total goes, as areas. A tree is drawn as boxes,
  ;;; each as big as its value's share of its parent's, laid out
  ;;; squarified (Bruls, Huizing and van Wijk, 2000: rows along the
  ;;; shorter side, each as long as keeps its boxes nearest to squares),
  ;;; and each box's children inside it, under its name. The root shown is
  ;;; a strip across the top, its children below it, and theirs inside
  ;;; them. A press on a box makes it the root shown, and a press on the
  ;;; strip goes back out one level.
  ;;;
  ;;;   (ui-treemap ui 'id x y w h tree label value children 'tip tip)
  ;;;
  ;;; tree, label, value and children are as a flame has them.

  ;; A treemap's box: an outline and a name, as a flame's box, filled while
  ;; the pointer is over it and none of its children, or it is selected.
  ;; flags may have hover and selected; depth is 0 for the root shown's
  ;; strip, 1 for its children and 2 for theirs. The name goes at the top
  ;; left, cut to fit.
  (define-part (ui-draw-treemap-box x y w h flags label depth)
    (when (or (memq 'selected flags) (memq 'hover flags))
      (fill-box x y (max 1 (- w 1)) (max 1 (- h 1))
                (if (memq 'selected flags) 'chart-level-4 'chart-level-2)
                2))
    (when (and (>= w 3) (>= h 3))
      (stroke-box (+ x 0.5) (+ y 0.5) (- w 2) (- h 2) 'chart-rule 1 2))
    (when (and (>= w 24) (>= h (+ (font-line-height 'ui-small) 2)))
      (draw-text (+ x 5) (+ y 2) (text-fit label (- w 10) 'ui-small)
                 'text 'ui-small)))

  ;; The height of a box's name, which its children lie under.
  (define (ui-treemap-header-height) (+ (font-line-height 'ui-small) 4))

  ;; Returns boxes for areas, the largest first, laid in x y w h in rows
  ;; along its shorter side: (x y w h) each, in the areas' order. Areas
  ;; that add up to less than the room leave the rest of it empty.
  (define (ui-treemap-layout areas x y w h)
    (define (worst row side)
      (let ([s (apply + row)] [hi (apply max row)] [lo (apply min row)])
        (max (/ (* side side hi) (* s s)) (/ (* s s) (* side side lo)))))
    (let loop ([areas areas] [x x] [y y] [w w] [h h] [acc '()])
      (if (or (null? areas) (<= w 0) (<= h 0))
          (append (reverse acc) (map (lambda (a) (list x y 0 0)) areas))
          (let* ([side (min w h)]
                 [row (let grow ([row (list (car areas))] [rest (cdr areas)])
                        (if (and (pair? rest)
                                 (<= (worst (cons (car rest) row) side)
                                     (worst row side)))
                            (grow (cons (car rest) row) (cdr rest))
                            (reverse row)))]
                 [thick (/ (apply + row) side)]
                 [rest (list-tail areas (length row))])
            (if (>= w h)
                ;; a column at the left, its boxes down it
                (let place ([r row] [at y] [acc acc])
                  (if (null? r)
                      (loop rest (+ x thick) y (- w thick) h acc)
                      (let ([len (/ (car r) thick)])
                        (place (cdr r) (+ at len)
                               (cons (list x at thick len) acc)))))
                ;; a row at the top, its boxes along it
                (let place ([r row] [at x] [acc acc])
                  (if (null? r)
                      (loop rest x (+ y thick) w (- h thick) acc)
                      (let ([len (/ (car r) thick)])
                        (place (cdr r) (+ at len)
                               (cons (list at y len thick) acc))))))))))

  ;; opts: 'tip (node), a box's tooltip or #f; 'on-pick (node), called on a
  ;; left press on a box; 'selected, the node drawn as selected (eq?);
  ;; 'key (node), what tells a node from its siblings, its label by
  ;; default. The root shown is kept as a flame keeps it. Boxes under two
  ;; pixels are left out. Returns the node under the pointer, or #f.
  (define (ui-treemap ui id x y w h tree label value children . opts)
    (define (opt name) (let ([o (memq name opts)]) (and o (cadr o))))
    (let* ([tip (opt 'tip)] [on-pick (opt 'on-pick)]
           [selected (opt 'selected)] [key (or (opt 'key) label)]
           [hh (ui-treemap-header-height)] [under #f]
           [way (let walk ([node tree] [keys (ui-memo ui (list id 'way) '())]
                           [taken '()])
                  (let ([next (and (pair? keys)
                                   (find (lambda (c)
                                           (equal? (key c) (car keys)))
                                         (children node)))])
                    (if next
                        (walk next (cdr keys) (cons (car keys) taken))
                        (cons node (reverse taken)))))]
           [root (car way)] [keys (cdr way)])
      ;; the boxes of node's children in bx by bw bh, the largest first,
      ;; as ((child x y w h) ...) in whole pixels, those under two left out
      (define (lay node bx by bw bh)
        (let* ([kids (sort (lambda (a b) (> (value a) (value b)))
                           (filter (lambda (c) (> (value c) 0))
                                   (children node)))]
               [total (max (value node) (apply + (map value kids)))])
          (if (or (null? kids) (<= total 0) (< bw 4) (< bh 4))
              '()
              (filter
               (lambda (b) (and (>= (caddr (cdr b)) 2) (>= (cadddr (cdr b)) 2)))
               (map (lambda (c box)
                      (let ([x0 (round (car box))] [y0 (round (cadr box))])
                        (list c (exact x0) (exact y0)
                              (exact (- (round (+ (car box) (caddr box))) x0))
                              (exact (- (round (+ (cadr box) (cadddr box)))
                                        y0)))))
                    kids
                    (ui-treemap-layout
                     (map (lambda (c) (inexact (/ (* bw bh (value c)) total)))
                          kids)
                     bx by bw bh))))))
      ;; draws node's box at bx by bw bh, and its children inside it until
      ;; depth 2
      (define (draw node depth bx by bw bh path)
        (let* ([inside (if (< depth 2)
                           (lay node (+ bx 2) (+ by hh) (- bw 4) (- bh hh 2))
                           '())]
               [over? (and (ui-hover? ui bx by bw bh)
                           (not (exists (lambda (b)
                                          (apply ui-hover? ui (cdr b)))
                                        inside)))]
               [text (and tip (tip node))])
          (when over? (set! under node))
          (ui-draw-treemap-box bx by bw bh
                               (append (if over? '(hover) '())
                                       (if (eq? node selected)
                                           '(selected)
                                           '()))
                               (label node) depth)
          (ui-pressable! ui (list id 'box path) bx by bw bh
                         (lambda ()
                           (when on-pick (on-pick node))
                           (ui-memo! ui (list id 'way) path))
                         '()
                         (append '(focus keep) (if text (list 'tip text) '())))
          (for-each (lambda (b)
                      (apply draw (car b) (+ depth 1)
                             (append (cdr b)
                                     (list (append path
                                                   (list (key (car b))))))))
                    inside)))
      (ui-memo! ui (list id 'way) keys)
      ;; the root shown: a strip whose press goes back out
      (let ([over? (ui-hover? ui x y w hh)] [text (and tip (tip root))])
        (when over? (set! under root))
        (ui-draw-treemap-box x y w hh
                             (append (if over? '(hover) '())
                                     (if (eq? root selected) '(selected) '()))
                             (label root) 0)
        (ui-pressable! ui (list id 'box keys) x y w hh
                       (lambda ()
                         (when on-pick (on-pick root))
                         (ui-memo! ui (list id 'way)
                                   (if (pair? keys)
                                       (reverse (cdr (reverse keys)))
                                       keys)))
                       '()
                       (append '(focus keep) (if text (list 'tip text) '()))))
      (for-each (lambda (b)
                  (apply draw (car b) 1
                         (append (cdr b)
                                 (list (append keys (list (key (car b))))))))
                (lay root x (+ y hh 2) w (- h hh 2)))
      under))

  ;;; ------------------------------------------------------------------
  ;;; source: lines of a program's text in the mono font, scrolling, with
  ;;; their numbers at the left when the first one's is given, and one line
  ;;; marked.

  ;; What the lines lie on.
  (define-part (ui-draw-source-surface x y w h flags)
    (fill-box x y w h 'bg-1 3))

  ;; A line of source at x, y, w wide: its number, or #f for none; its
  ;; note, or #f, ending at x + note-end; and its text, from x + gutter.
  ;; flags may have marked.
  (define-part (ui-draw-source-line x y w h flags number note note-end gutter
                                    text)
    (when (memq 'marked flags) (fill-box x y w h (alpha 'accent 0.25) 2))
    (when number
      (draw-text x y (number->string number) 'text-faint 'mono-small))
    (when note
      (draw-text (- (+ x note-end) (text-width note 'mono-small)) y note
                 'text-dim 'mono-small))
    (draw-text (+ x gutter) y text 'text 'mono-small))

  ;; opts: 'first, the number of the first line, which gives the lines
  ;; their numbers; 'marked, the index of the line marked, from 0; 'notes,
  ;; a note for each line (a string, or #f for none), in a column of its
  ;; own after the numbers: how often the line ran, say.
  (define (ui-source ui id x y w h lines . opts)
    (define (opt name) (let ([o (memq name opts)]) (and o (cadr o))))
    (let* ([lh (font-line-height 'mono-small)]
           [left (+ x (max 8 (ui-scrollbar-inset 'left)))]
           [first (opt 'first)] [marked (opt 'marked)]
           [notes (or (opt 'notes) (map (lambda (l) #f) lines))]
           [numbers (if first
                        (+ 12 (text-width (number->string
                                           (+ first (length lines)))
                                          'mono-small))
                        0)]
           [note-w (fold-left (lambda (most n)
                                (if n (max most (text-width n 'mono-small))
                                    most))
                              0 notes)]
           [gutter (+ numbers (if (> note-w 0) (+ note-w 12) 0))])
      (ui-draw-source-surface x y w h '())
      (ui-scroll ui id x y w h
        (lambda (top)
          (for-each (lambda (line note k)
                      (let ([ly (+ top 6 (* k lh))])
                        (when (and (> (+ ly lh) y) (< ly (+ y h)))
                          (ui-draw-source-line
                           left ly (- (+ x w) left 8) lh
                           (if (eqv? k marked) '(marked) '())
                           (and first (+ first k)) note (+ numbers note-w)
                           gutter line))))
                    lines notes (iota (length lines)))
          (+ top 12 (* lh (length lines)))))))

  ;;; ------------------------------------------------------------------
  ;;; streams: a chart of what keeps coming, one bar per moment, the newest
  ;;; at the right. Its rows are on the GPU and a paint draws them, so a new
  ;;; moment costs a row of numbers, and the chart costs one record, however
  ;;; many bars flow past. A moment is named by its seq, which only grows.
  ;;;
  ;;;   (define s (ui-stream-new 2048 columns '(("late" chart-flag))))
  ;;;   (ui-stream-send! s oldest newest (lambda (seq j) ...))
  ;;;   (ui-stream ui 'id s x y w h newest oldest top rules stack bar ...)
  ;;;   (ui-stream-release! s)    when its window closes, to free at once
  ;;;
  ;;; A row is its columns' numbers, then one word per strip. A strip is a
  ;;; thin lane over the bars, (label color ...), with the label #f for none;
  ;;; its word says which of its colors a moment has, counting from 1, or 0
  ;;; for none.

  ;; The record has a name of its own, since ui-stream names the widget.
  (define-record-type (ui-stream-record make-ui-stream ui-stream?)
    (nongenerative schevana-ui-stream)
    (fields (immutable rows ui-stream-rows)
            (immutable columns ui-stream-columns)
            (immutable strips ui-stream-strips)
            ;; the rows, made when first sent
            (mutable buffer ui-stream-buffer ui-stream-buffer-set!)
            ;; what the paint colors them with
            (mutable palette ui-stream-palette ui-stream-palette-set!)
            ;; the newest moment the rows have
            (mutable sent ui-stream-sent ui-stream-sent-set!)))

  (define (ui-stream-new rows columns strips)
    (make-ui-stream rows columns strips #f #f -1))

  ;; The largest a column's number can be, since the paint adds up a row in
  ;; 32 bits.
  (define ui-stream-most 100000000)

  (define (ui-stream-words s)
    (+ (ui-stream-columns s) (length (ui-stream-strips s))))

  (define (ui-stream-colors s)
    (fold-left (lambda (n strip) (+ n (length (cdr strip)))) 0
               (ui-stream-strips s)))

  ;; The moments begin again: the next send sends all it is given, whatever
  ;; was sent before.
  (define (ui-stream-restart! s) (ui-stream-sent-set! s -1))

  ;; The moments from seq on are sent again at the next send, with their
  ;; words read again: for moments still changing.
  (define (ui-stream-resend! s seq)
    (when (>= (ui-stream-sent s) seq) (ui-stream-sent-set! s (- seq 1))))

  (define (ui-stream-release! s)
    (when (ui-stream-buffer s)
      (gpu-buffer-release! (ui-stream-buffer s))
      (gpu-buffer-release! (ui-stream-palette s))
      (ui-stream-buffer-set! s #f)
      (ui-stream-palette-set! s #f)
      (ui-stream-sent-set! s -1)))

  ;; Sends the rows of the moments after those already sent, up to newest:
  ;; as many as the stream holds, and none before oldest. (word-of seq j)
  ;; gives word j of a moment's row. A newest behind what was sent means the
  ;; history began again.
  (define (ui-stream-send! s oldest newest word-of)
    (unless (ui-stream-buffer s)
      (ui-stream-buffer-set! s (make-gpu-buffer (* (ui-stream-rows s)
                                                   (ui-stream-words s))))
      (ui-stream-palette-set! s (make-gpu-buffer
                                 (ui-stream-color-at
                                  s (+ (ui-stream-columns s)
                                       (ui-stream-colors s))))))
    (when (< newest (ui-stream-sent s)) (ui-stream-sent-set! s -1))
    (let ([rows (ui-stream-rows s)] [words (ui-stream-words s)]
          [columns (ui-stream-columns s)] [buffer (ui-stream-buffer s)]
          ;; What each strip's words start from, among the strips' colors.
          [bases (let loop ([ss (ui-stream-strips s)] [at 0])
                   (if (null? ss)
                       '()
                       (cons at (loop (cdr ss) (+ at (length (cdar ss)))))))])
      (do ([seq (max (+ (ui-stream-sent s) 1) (- newest rows -1) oldest)
                (+ seq 1)])
          ((> seq newest) (ui-stream-sent-set! s newest))
        (let ([at (* words (modulo seq rows))])
          (do ([j 0 (+ j 1)]) ((= j words))
            (let ([v (word-of seq j)])
              (gpu-buffer-set!
               buffer (+ at j)
               (cond [(< j columns) (max 0 (min ui-stream-most v))]
                     [(eqv? v 0) 0]
                     [else (+ v (list-ref bases (- j columns)))]))))))))

  ;; The palette is what the bars are drawn in: the stack, from the bottom
  ;; up, as its columns' numbers, with room for every column; then the
  ;; colors, the stack's in its order, again with room for every column, and
  ;; after them the strips'.
  ;; A color is its word; or, for a stipple, its ink's word, its paper's,
  ;; how many cells it has across and down (none for a plain color), and a
  ;; word for each of its rows, the row's first cell in the lowest bit.
  (define-shader-layout ui-stream-color palette (ink paper across down))
  (define ui-stream-color-most-rows 16)
  (define ui-stream-color-most-across 32)
  (define-shader-constant ui-stream-color-room
    (+ ui-stream-color-words ui-stream-color-most-rows))

  ;; Returns where the palette's color i is.
  (define (ui-stream-color-at s i)
    (+ (ui-stream-columns s) (* i ui-stream-color-room)))

  ;; Sets the palette's color i: a color, or #f, which draws nothing. A
  ;; stipple of more cells than there is room for is drawn as the gray it
  ;; comes to.
  (define (ui-stream-color! s i color)
    (let* ([c (let given ([c color]) (if (symbol? c) (given (theme c)) c))]
           [rows (if (stipple? c) (cdddr c) '())]
           [cells? (and (pair? rows)
                        (<= (length rows) ui-stream-color-most-rows)
                        (<= (string-length (car rows))
                            ui-stream-color-most-across))]
           [at (ui-stream-color-at s i)]
           [set (lambda (j v)
                  (gpu-buffer-set! (ui-stream-palette s) (+ at j) v))]
           [word (lambda (c) (if c (color-word c) 0))])
      (set ui-stream-color-ink (word (if cells? (cadr c) c)))
      (set ui-stream-color-across (if cells? (string-length (car rows)) 0))
      (when cells?
        (set ui-stream-color-paper (word (caddr c)))
        (set ui-stream-color-down (length rows))
        (for-each (lambda (row j)
                    (set (+ ui-stream-color-words j)
                         (fold-right (lambda (cell bits)
                                       (+ bits bits
                                          (if (char=? cell #\#) 1 0)))
                                     0 (string->list row))))
                  rows (iota (length rows))))))

  ;; From the right, one bar per moment; up each bar, its columns as the
  ;; palette stacks them; over the bars, the strips. A stipple's cells are
  ;; logical pixels, counted from the box's corner.
  (define-paint (ui-stream-bars x y)
    ([moments fx-buffer]
     [palette fx-buffer]
     [stacked fixnum]      ; how many entries the stack holds
     [columns fixnum]      ; the numbers a row starts with
     [rows fixnum]         ; the ring's rows
     [row-words fixnum]
     [newest fixnum]       ; the moment of the bar at the right
     [shown fixnum]        ; how many moments there are to show
     [w fixnum]
     [h fixnum]
     [top fixnum]          ; the number the bars' top stands for
     [bar flonum]          ; a bar's width, in device pixels
     [gap flonum]          ; the space clear at its right
     [strips fixnum]
     [strip-h fixnum]      ; a strip's height, its gap included
     [strip-gap fixnum]
     [bars-at fixnum]      ; where the bars' room starts, under the strips
     [cell flonum])        ; a stipple's cell, in device pixels
    (let* ([d (fl- (fl- (fixnum->flonum w) 0.5) (fixnum->flonum x))]
           [col (flonum->fixnum (flfloor (fl/ d bar)))]
           [within (fl- d (fl* (fixnum->flonum col) bar))]
           [row (fx* (fxmod (fx- newest col) rows) row-words)]
           [lanes (fx* strips strip-h)])
      (define (spent k)
        (fx-ref moments (fx+ row (fx-ref palette k))))
      ;; which of a stipple's n cells device pixel d is in, as the core's
      ;; tiles have it
      (define (cell-at d n)
        (fxmod (fx- (flonum->fixnum
                     (flceiling (fl/ (fl+ (fixnum->flonum d) 0.5) cell)))
                    1)
               n))
      (let* ([color   ; which of the palette's, -1 for none
              (cond
                [(or (fx>= col shown) (fl< within gap)) -1]
                [(fx< y bars-at)
                 (if (fx< y lanes)
                     (let ([mark (fx-ref moments
                                         (fx+ row columns
                                              (fxquotient y strip-h)))])
                       (if (or (fx= mark 0)
                               (fx>= (fxmod y strip-h)
                                     (fx- strip-h strip-gap)))
                           -1
                           (fx+ columns (fx- mark 1))))
                     -1)]
                [else
                 (let ([at (fl* (fl/ (fl- (fixnum->flonum (fx- h y)) 0.5)
                                     (fixnum->flonum (fx- h bars-at)))
                                (fixnum->flonum top))])
                   (do-bounded 12
                       ([k 0 (fx+ k 1)]
                        [sum (spent 0) (fx+ sum (spent (fx+ k 1)))])
                     ((or (fx>= k stacked) (fl> (fixnum->flonum sum) at))
                      (if (fx>= k stacked) -1 k))))])]
             [at (fx+ columns (fx* color ui-stream-color-room))])
        (cond
          [(fx< color 0) 0]
          [(or (fx= (ui-stream-color-across at) 0)
               (fx= 1
                    (fxand 1
                           (fxsrl (fx-ref palette
                                          (fx+ at ui-stream-color-words
                                               (cell-at
                                                y
                                                (ui-stream-color-down at))))
                                  (cell-at x (ui-stream-color-across at))))))
           (ui-stream-color-ink at)]
          [else (ui-stream-color-paper at)]))))

  ;; Returns a strip's height and the space clear under it: a labeled strip
  ;; takes a line.
  (define-part (ui-stream-lane strips)
    (if (exists car strips)
        (values (font-line-height 'ui-small) 3)
        (values 3 0)))

  ;; Returns how far down the bars' room starts: labeled strips leave half a
  ;; line more, for the label of a rule at the bars' top.
  (define (ui-stream-room strips)
    (let-values ([(lane-h lane-gap) (ui-stream-lane strips)])
      (+ (* lane-h (length strips))
         (if (exists car strips)
             (quotient (font-line-height 'ui-small) 2)
             0))))

  ;; A stream's pieces, as ((plot x y w h) (bar w) (bars x y w h) (lane h
  ;; gap)): a bar chart's, with room left for the strips' labels too, and the
  ;; bars' part of the plot, under the strips.
  (define-part (ui-stream-areas s x y w h n rules)
    (let*-values
        ([(strips) (ui-stream-strips s)]
         [(lane-h lane-gap) (ui-stream-lane strips)]
         [(areas) (ui-bar-chart-areas
                   x y w h n
                   (append rules
                           (map (lambda (strip) (cons 0 (car strip)))
                                (filter car strips))))]
         [(plot) (cdr (assq 'plot areas))]
         [(room) (ui-stream-room strips)])
      (append areas
              (list (list 'bars (car plot) (+ (cadr plot) room) (caddr plot)
                          (max 0 (- (cadddr plot) room)))
                    (list 'lane lane-h lane-gap)))))

  ;; Returns how many moments there are to show: as many bars bar wide as
  ;; fit, or, with no bar, as many as the rows hold.
  (define (ui-stream-count s x y w h newest oldest rules bar)
    (if newest
        (max 0 (min (if bar
                        (quotient (cadddr (assq 'plot
                                                (ui-stream-areas s x y w h 1
                                                                       rules)))
                                  bar)
                        (ui-stream-rows s))
                    (+ 1 (- newest oldest))))
        0))

  ;; Returns (values count areas). With fit? true, every moment goes across
  ;; the width, with bars as narrow as that takes; with fit? 'whole, the bars
  ;; are whole device pixels, so that all are as wide, and the oldest
  ;; moments that do not fit are left out.
  (define (ui-stream-layout s x y w h newest oldest rules bar fit?)
    (let* ([count (ui-stream-count s x y w h newest oldest rules
                                   (and (not fit?) bar))]
           [areas (ui-stream-areas s x y w h count rules)]
           [room (cadddr (assq 'plot areas))])
      (cond
        [(eq? fit? 'whole)
         (let* ([scale (draw-scale)]
                [pixels (exact (floor (* scale room)))]
                [px (max 1 (exact (ceiling (/ pixels (max count 1)))))])
           (values (min count (quotient pixels px))
                   (cons (list 'bar (/ px scale)) areas)))]
        [fit? (values count (cons (list 'bar (/ room (max count 1))) areas))]
        [else (values count areas)])))

  ;; Returns the moment at x, or the nearest of those shown when x is off
  ;; either end.
  (define (ui-stream-seq-at areas x newest count)
    (let ([plot (cdr (assq 'plot areas))] [bw (cadr (assq 'bar areas))])
      (- newest
         (max 0 (min (- count 1)
                     (exact (floor (/ (- (+ (car plot) (caddr plot)) x)
                                      bw))))))))

  ;; rules and top are in the columns' numbers; marked lists the moments
  ;; marked; over, a procedure (over areas count) or #f, draws over the bars
  ;; and under the rules.
  (define-part (ui-draw-stream x y w h flags s areas count newest top rules
                               stack
                               marked over)
    (let*-values
        ([(plot) (cdr (assq 'plot areas))]
         [(px py pw ph) (apply values plot)]
         [(bw) (cadr (assq 'bar areas))]
         [(lane-h lane-gap) (apply values (cdr (assq 'lane areas)))]
         [(strips) (ui-stream-strips s)]
         [(columns) (ui-stream-columns s)])
      (ui-draw-surface x y w h '(well))
      (when newest
        (for-each (lambda (seq)
                    (let-values ([(bx bx-w)
                                  (ui-bar-chart-bar areas count
                                                    (- count 1
                                                       (- newest seq)))])
                      (when (>= bx px)
                        (fill-box bx py bx-w ph 'chart-mark))))
                  marked))
      (when (and newest (ui-stream-buffer s))
        (let ([palette (ui-stream-palette s)] [scale (draw-scale)])
          (for-each (lambda (entry k)
                      (gpu-buffer-set! palette k (car entry))
                      (ui-stream-color! s k (cdr entry)))
                    stack (iota (length stack)))
          (for-each (lambda (color i) (ui-stream-color! s (+ columns i) color))
                    (apply append (map cdr strips))
                    (iota (ui-stream-colors s)))
          (fill-shader px py pw ph ui-stream-bars
                       (ui-stream-buffer s) palette (length stack) columns
                       (ui-stream-rows s) (ui-stream-words s)
                       (modulo newest (ui-stream-rows s)) count
                       (exact (round (* scale pw))) (exact (round (* scale ph)))
                       top
                       (inexact (* scale bw)) (if (>= bw 3) (inexact scale) 0.0)
                       (length strips)
                       (exact (round (* scale lane-h)))
                       (exact (round (* scale lane-gap)))
                       (exact (round (* scale (ui-stream-room strips))))
                       (inexact scale))))
      (when over (over areas count))
      (ui-draw-bar-chart-rules x (list (cons 'plot (cdr (assq 'bars areas))))
                               top rules)
      (fold-left (lambda (ly strip)
                   (when (car strip)
                     (draw-text (+ x 6) (ui-text-y ly 'ui-small) (car strip)
                                'text-faint 'ui-small))
                   (+ ly lane-h))
                 py strips)))

  ;; stack: from the bottom up, (column . color), with the color #f for a
  ;; clear entry that lifts the rest; bar: a bar's least width. opts: 'tip
  ;; (seq), a moment's tooltip or #f; 'on-pick (seq), called on a left press
  ;; and as the press is dragged; 'marked, the moments marked; 'over, as the
  ;; part takes it; 'doc; 'strip-tips, a tooltip for each strip's label;
  ;; 'fit, true to show every moment from oldest to newest across the
  ;; width, ignoring bar, or 'whole to show as many as fit as bars of whole
  ;; pixels (ui-stream-layout). A bar under the pointer is marked too.
  ;; Returns the moment under the pointer, or #f.
  (define (ui-stream ui id s x y w h newest oldest top rules stack bar . opts)
    (let-values ([(count areas)
                  (ui-stream-layout s x y w h newest oldest rules bar
                                    (plist-ref opts 'fit #f))])
      (let* ([plot (cdr (assq 'plot areas))]
             [under (ui-bar-chart-under ui areas count)]
             [hover (and newest under (< under count)
                         (+ newest (- under count -1)))]
             [tip-of (plist-ref opts 'tip #f)]
             [on-pick (plist-ref opts 'on-pick #f)]
             [pick! (lambda (at)
                      (and on-pick newest (> count 0)
                           (begin
                             (on-pick (ui-stream-seq-at areas at newest count))
                             #t)))])
        (ui-region! ui (list id) (car plot) (cadr plot) (caddr plot)
                    (cadddr plot)
          'doc (plist-ref opts 'doc '((L . "Select")))
          'follow (and newest (> count 0)
                       (lambda (mx my)
                         (ui-stream-seq-at areas mx newest count)))
          'tip (and hover tip-of (tip-of hover))
          'on (lambda (ev)
                (case (car ev)
                  [(press) (and (eq? (list-ref ev 3) 'left) (pick! (cadr ev)))]
                  [(drag) (pick! (cadr ev))]
                  [else #f])))
        (let-values ([(lane-h lane-gap) (ui-stream-lane (ui-stream-strips s))])
          (for-each (lambda (tip i)
                      (ui-region! ui (list id 'strip i)
                                  x (+ (cadr plot) (* i lane-h))
                                  (- (car plot) x) lane-h 'tip tip))
                    (plist-ref opts 'strip-tips '())
                    (iota (length (plist-ref opts 'strip-tips '())))))
        (ui-draw-stream x y w h '() s areas count newest top rules stack
                        (append (if hover (list hover) '())
                                (plist-ref opts 'marked '()))
                        (plist-ref opts 'over #f))
        hover)))

  ;; Returns values, oldest first, as points ((x . y) ...) across x y w h,
  ;; scaled so that top reaches the box's top (1 pixel clear of the top and
  ;; of the bottom).
  (define (ui-chart-points x y w h values top)
    (let ([n (length values)])
      (map (lambda (v i)
             (cons (+ x (* w (/ i (max 1 (- n 1)))))
                   (- (+ y h) 1 (* (- h 2) (if (> top 0) (/ (min v top) top)
                                               0)))))
           values (iota n))))

  ;; values, oldest first, as a line scaled to their largest; with the flag
  ;; selected (its row is selected), in chart-share.
  (define-part (ui-draw-sparkline x y w h flags values)
    (when (> (length values) 1)
      (draw-polyline (ui-chart-points x y w h values (apply max 0 values))
                     (if (memq 'selected flags) 'chart-share 'text-dim) 1)))

  ;; series: ((color value ...) ...), each oldest first over one span and
  ;; scaled to its own largest value, drawn in a well.
  (define-part (ui-draw-line-chart x y w h flags series)
    (ui-draw-surface x y w h '(well))
    (for-each (lambda (s)
                (when (> (length (cdr s)) 1)
                  (draw-polyline (ui-chart-points (+ x 4) (+ y 4) (- w 8)
                                                  (- h 8)
                                                  (cdr s)
                                                  (apply max 0 (cdr s)))
                                 (car s) 1)))
              series))

  ;; A legend in a row: keys are ((color . label) ...), each drawn as a
  ;; swatch and its label, as many as fit in w.
  (define-part (ui-draw-legend x y w h flags keys)
    (let ([lh (font-line-height 'ui-small)] [end (+ x w)])
      (fold-left (lambda (lx k)
                   (let ([kw (ui-legend-key-width (cdr k))])
                     (if (> (+ lx kw) end)
                         lx
                         (begin
                           (fill-box lx (+ y (/ (- h lh) 2) 2) (- lh 4) (- lh 4)
                                     (car k))
                           (draw-text (+ lx lh)
                                      (ui-text-y (+ y (/ (- h lh) 2)) 'ui-small)
                                      (cdr k) 'text-dim 'ui-small)
                           (+ lx kw 12)))))
                 x keys)))

  (define (ui-legend-key-width label)
    (+ (font-line-height 'ui-small) 4 (text-width label 'ui-small)))

  ;; Returns (values w h) for all of its keys in a row.
  (define-part (ui-legend-size keys)
    (values (+ (apply + (map (lambda (k) (ui-legend-key-width (cdr k))) keys))
               (* 12 (max 0 (- (length keys) 1))))
            (font-line-height 'ui-small))))
