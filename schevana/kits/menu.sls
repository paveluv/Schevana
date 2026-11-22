;;; (schevana kits menu) — a menu as data: where it was asked to open, its
;;; items, the entry chosen, what is typed to filter them, whether it
;;; filters, and what it is of, its tag (launcher, (window . win), a
;;; dropdown's). An entry is (label . thunk) or 'separator; a label may end
;;; in a tab and the key that does the same: "Close\tCtrl+Shift+W". The
;;; desktop's one menu at a time is one ((schevana desktop menu)), which
;;; opens it and takes its keys and the pointer; a style lays one out and
;;; draws it (menu-areas, draw-menu), reading it here.

(library (schevana kits menu)
  (export
    menu make-menu menu? menu-x menu-y menu-items menu-sel menu-sel-set!
    menu-filter menu-filter-set! menu-filter? menu-tag menu-label-text
    menu-label-key menu-label-tab menu-label-width menu-entries)
  (import (chezscheme)
          (only (schevana base) library-layer string-contains-ci?)
          (only (schevana core) text-width))

  (library-layer kits)

  (define-record-type menu
    (nongenerative schevana-menu)
    (fields x y items (mutable sel) (mutable filter) filter? tag))

  ;; An entry's label: => its text, or the key or #f.
  (define (menu-label-text label)
    (let ([i (menu-label-tab label)]) (if i (substring label 0 i) label)))

  (define (menu-label-key label)
    (let ([i (menu-label-tab label)])
      (and i (substring label (+ i 1) (string-length label)))))

  (define (menu-label-tab label)
    (let ([n (string-length label)])
      (let loop ([i 0])
        (cond [(= i n) #f]
              [(char=? (string-ref label i) #\tab) i]
              [else (loop (+ i 1))]))))

  ;; As wide as an entry's text and key, a gap between.
  (define (menu-label-width label font)
    (let ([key (menu-label-key label)])
      (+ (text-width (menu-label-text label) font)
         (if key (+ 24 (text-width key font)) 0))))

  ;; The entries m shows: its items, those whose text has what is typed, or
  ;; what its items make of it ((lambda (filter) entries)).
  (define (menu-entries m)
    (let ([f (menu-filter m)] [items (menu-items m)])
      (cond [(procedure? items) (items f)]
            [(string=? f "") items]
            [else (filter (lambda (e)
                            (and (pair? e)
                                 (string-contains-ci? (menu-label-text (car e))
                                                      f)))
                          items)]))))
