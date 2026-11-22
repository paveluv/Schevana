;;; tests/units/ui-toolbar.ss — the kit's toolbar ((schevana kits ui)), by
;;; itself: its items in a row a gap apart, the one of no width taking what the
;;; others leave, a row filled exactly still one row, wrapping past it, and its
;;; end item at the right of the first row.

;; Where each item of a toolbar w wide was drawn, (x y w h), in order, and
;; then its end's, of width end if given; flex as ui-toolbar takes it.
(define (ui-toolbar-test-places w widths flex . end)
  (let ([placed '()])
    (define (item width)
      (list width (ui-control-height)
            (lambda (x y w h) (set! placed (cons (list x y w h) placed)))))
    (let ([img (image 10 10 1
                      (lambda ()
                        (apply ui-toolbar 0 0 w (map item widths)
                               'flex flex
                               (if (pair? end) (list 'end (item (car end)))
                                   '()))))])
      (picture-free! img)
      (reverse placed))))

(check "a toolbar's items go left to right a gap apart from its pad, and \
        the one of no width takes what the others leave of the row"
       (let* ([pad (ui-pad)] [gap (ui-gap)] [w 600]
              [places (ui-toolbar-test-places w '(100 #f 60) '(0 . 10000))]
              [xs (map car places)] [ws (map caddr places)])
         (printf "  ~s\n" places)
         (and (= (car xs) pad)
              (= (cadr xs) (+ pad 100 gap))
              (= (caddr xs) (+ (cadr xs) (cadr ws) gap))
              (= (cadr ws) (floor (- w pad pad 100 60 gap gap)))
              (apply = (map cadr places)))))

(check "a row its items fill exactly, fractions and all, is still one row; \
        an item more wraps to the next"
       (let* ([pad (ui-pad)] [gap (ui-gap)]
              [widths '(100.5 70.25 80.25)]
              [w (+ pad pad (apply + widths) gap gap)]
              [one (ui-toolbar-test-places w widths '(150 . 300))]
              [two (ui-toolbar-test-places w (append widths '(40))
                                           '(150 . 300))])
         (and (apply = (map cadr one))
              (> (cadr (list-ref two 3)) (cadr (car two))))))

(check "its end item goes at the right of its first row, which the others \
        leave room for"
       (let* ([pad (ui-pad)] [gap (ui-gap)] [w 600]
              [places (ui-toolbar-test-places w '(100 #f) '(0 . 10000) 80)]
              [end (car (last-pair places))] [flex (cadr places)])
         (and (= (car end) (- w pad 80))
              (= (cadr end) (cadr (car places)))
              (<= (+ (car flex) (caddr flex)) (- (car end) gap)))))
