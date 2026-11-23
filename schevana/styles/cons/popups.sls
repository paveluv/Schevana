;;; (schevana styles cons popups) — a part of the Cons style ((schevana
;;; styles cons)): tooltips, dialogs and their scrim, the calendar's days
;;; and avatars.

(library (schevana styles cons popups)
  (export
    cons-avatar cons-day cons-dialog cons-dialog-areas cons-dialog-size
    cons-scrim cons-tooltip cons-tooltip-size)
  (import (chezscheme)
          (only (schevana base) clamp library-layer)
          (only (schevana core) alpha draw-text fill-box font-line-height
                text-width title-height)
          (only (schevana kits app) app-color)
          (only (schevana kits text) text-widest text-draw-centered text-fit)
          (only (schevana kits ui) ui-initials ui-dialog-areas ui-dialog-lines
                ui-draw-panel ui-tooltip-lines)
          (schevana styles cons cells)
          (schevana styles cons widgets))

  (library-layer looks)

  ;; A tooltip is a string: a cell holding the text in quotes.
  (define (cons-tooltip x y w h flags text)
    (let* ([lines (ui-tooltip-lines text)] [sh (font-line-height 'ui-small)]
           [mh (font-line-height 'mono-small)] [dy (/ (- sh mh) 2)]
           [q (text-width "\"" 'mono-small)] [g (cons-space)] [tx (+ x g q 2)]
           [last (list-ref lines (- (length lines) 1))]
           [ly (+ y 5 (* sh (- (length lines) 1)))])
      (ui-draw-panel x y w h '(tooltip))
      (draw-text (+ x g) (+ y 5 dy) "\"" 'text-faint 'mono-small)
      (fold-left (lambda (ty line)
                   (draw-text tx ty line 'text 'ui-small)
                   (+ ty sh))
                 (+ y 5) lines)
      (draw-text (+ tx (text-width last 'ui-small) 2) (+ ly dy) "\""
                 'text-faint 'mono-small)))

  (define (cons-tooltip-size text)
    (let ([lines (ui-tooltip-lines text)])
      (values (+ 4 (* 2 (cons-space)) (* 2 (text-width "\"" 'mono-small))
                 (min 280 (text-widest lines 'ui-small)))
              (+ 10 (* (length lines) (font-line-height 'ui-small))))))

  ;; A dialog is a window-shaped list, ("Delete TASK-16?" Cancel Delete): a
  ;; chain of cells across a title strip, as a window's, in the bold
  ;; accent. Each button's cell is a car of the chain (cons-chain, set by
  ;; the dialog place), the last one's cdr holds nil, and clicking that end
  ;; of the list cancels, as closing a window does (the kit's dismiss
  ;; area). The message is in the box below the strip.
  (define (cons-dialog-car label) (+ (* 2 (cons-space)) (text-width label 'ui)))

  ;; The chain after the title's car: its cdr, then each button's pointer,
  ;; car and cdr.
  (define (cons-dialog-rest labels)
    (let ([c (cons-cell)] [a (cons-arrow)])
      (fold-left (lambda (acc l) (+ acc a (cons-dialog-car l) c)) c labels)))

  (define (cons-dialog-size title message labels)
    (let* ([lh (font-line-height 'ui)] [left (cons-left)]
           [chain (+ left (text-width title 'title) (* 4/5 (cons-cell))
                     (cons-dialog-rest labels) left)]
           [pad (* 2 (cons-space))]
           [w (clamp (max (+ pad pad (text-width message 'ui)) (ceiling chain))
                     (* 20 lh) (* 32 lh))])
      (values w
              (round (+ (title-height) pad
                        (* lh (length (ui-dialog-lines message (- w pad pad))))
                        pad)))))

  ;; ((title x y w h) (message ..) (button x y w h) ... (dismiss x y w h)):
  ;; the chain runs across the strip from the left, the title's car taking
  ;; the room the buttons leave; the dismiss area is the last cdr.
  (define (cons-dialog-areas x y w h labels)
    (let* ([c (cons-cell)] [a (cons-arrow)] [th (title-height)]
           [left (cons-left)] [cy (+ y (quotient (- th c) 2))]
           [pad (* 2 (cons-space))]
           [tw (max c (- w left left (cons-dialog-rest labels)))])
      (let loop ([ls labels] [bx (+ x left tw c)] [acc '()])
        (if (null? ls)
            (append (list (list 'title (+ x left) cy tw c)
                          (list 'message (+ x pad) (+ y th pad) (- w pad pad)
                                (- h th pad pad)))
                    (reverse acc)
                    (list (list 'dismiss (- bx c) cy c c)))
            (let ([bw (cons-dialog-car (car ls))])
              (loop (cdr ls) (+ bx a bw c)
                    (cons (list 'button (+ bx a) cy bw c) acc)))))))

  ;; flags hold (labels . the buttons' labels) and the dismiss area's
  ;; state: nil fills red under the mouse, with its slash crossed out, as
  ;; in a window's title bar.
  (define (cons-dialog x y w h flags title message)
    (let* ([c (cons-cell)] [th (title-height)] [lw 2] [ink 'accent]
           [labels (let ([l (cons-flag flags 'labels)]) (if l (cdr l) '()))]
           [areas (ui-dialog-areas x y w h labels)]
           [t (cdr (assq 'title areas))] [m (cdr (assq 'message areas))]
           [cars (map cdr (filter (lambda (a) (eq? (car a) 'button)) areas))]
           [cy (cadr t)] [tw (caddr t)]
           [close (cons-tint-of flags 'button-close)]
           [s (text-fit title (- tw (* 4/5 c)) 'title)])
      (ui-draw-panel x y w h '(dialog))
      (fill-box x (+ y th -1) w 1 'window-border)
      (cons-pair! (car t) cy tw c ink lw #f #f)
      (draw-text (+ (car t) (floor (/ (- tw (text-width s 'title)) 2)))
                 (cons-title-y cy c) s 'title-text 'title)
      ;; from each cdr, a pointer to the next car (whose cell its button
      ;; draws) and that car's cdr; the last cdr holds nil
      (let loop ([cx (+ (car t) tw)] [cars cars])
        (if (null? cars)
            (begin
              (when close
                (fill-box cx (+ cy lw) (- c lw) (- c lw lw) close))
              (cons-nil! cx cy c ink lw (and close 'window-bg)))
            (let* ([b (car cars)] [nx (+ (car b) (caddr b))])
              (cons-right! (cons-dot-x cx c lw) (cons-dot-y cy c lw) (car b) c
                           ink lw)
              (cons-ring! (- nx lw) cy (+ c lw) c ink lw)
              (loop nx (cdr cars)))))
      (fold-left (lambda (ly line) (draw-text (car m) ly line 'text-dim 'ui)
                   (+ ly (font-line-height 'ui)))
                 (cadr m) (ui-dialog-lines message (caddr m)))))

  ;; Under a dialog, the window is faintly veiled.
  (define (cons-scrim x y w h flags) (fill-box x y w h (alpha 'bg-0 0.4)))

  ;; A day is a cell: the chosen one is filled, today is bold accent, the
  ;; keyboard's day is bold in its ink, another month's days are faint, and
  ;; the one under the mouse fills with its ink.
  (define (cons-day x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [s (- (min w h) (cons-space))]
           [cx (+ x (/ (- w s) 2))] [cy (+ y (/ (- h s) 2))]
           [sel? (on? 'selected)]
           [ink (cond [(or sel? (on? 'today)) 'accent]
                      [(on? 'outside) 'text-faint]
                      [else 'cons-ink])]
           [tint (cond [sel? 'accent] [(on? 'hover) ink] [else #f])])
      (when tint (fill-box cx cy s s tint))
      (cons-ring! cx cy s s ink (if (or (on? 'today) (on? 'cursor)) 2 1))
      (text-draw-centered x y w h label
                          (cond [tint 'window-bg]
                                [(on? 'outside) 'text-faint]
                                [else 'text])
                          'ui)))

  ;; A person is a cell with the initials, in the person's color.
  (define (cons-avatar x y w h flags name)
    (let ([color (app-color (string->symbol (string-downcase name)))])
      (cons-ring! x y w w color 1)
      (text-draw-centered x y w w (ui-initials name) color 'ui-small))))
