;;; (schevana kits menu) — a menu as data: where it was asked to open, its
;;; items, the entry chosen, the text typed to filter them, whether it
;;; filters, and its tag, which says what the menu belongs to (launcher,
;;; (window . win), or a dropdown's). An entry is (label . thunk) or
;;; 'separator; a label may end in a tab and the key that does the same
;;; thing: "Close\tCtrl+Shift+W". The desktop shows one menu at a time
;;; ((schevana desktop menu)): it opens the menu and takes its keys and the
;;; pointer. A style lays a menu out and draws it (menu-areas, draw-menu),
;;; reading it with the procedures here.

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

  ;; An entry's label, split at its tab: menu-label-text returns the text,
  ;; menu-label-key the key or #f.
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

  ;; Returns the width of an entry's text and key, with a gap between them.
  (define (menu-label-width label font)
    (let ([key (menu-label-key label)])
      (+ (text-width (menu-label-text label) font)
         (if key (+ 24 (text-width key font)) 0))))

  ;; Returns the entries m shows: its items, or those whose text contains
  ;; what is typed. Items may also be a procedure, (lambda (filter)
  ;; entries), that makes the entries from what is typed.
  (define (menu-entries m)
    (let ([f (menu-filter m)] [items (menu-items m)])
      (cond [(procedure? items) (items f)]
            [(string=? f "") items]
            [else (filter (lambda (e)
                            (and (pair? e)
                                 (string-contains-ci? (menu-label-text (car e))
                                                      f)))
                          items)]))))
