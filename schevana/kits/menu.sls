;;; (schevana kits menu) — a menu as data: where it was asked to open, its
;;; items, the entry chosen, the text typed to filter them, whether it
;;; filters, and its tag, which says what the menu belongs to (launcher,
;;; (window . win), or a dropdown's). An entry is (label . thunk), (label
;;; thunk icon) with an icon (a procedure (x y s flags) that draws it in an
;;; s-square, as an app's icon is drawn), or 'separator; a label may end in
;;; a tab and the key that does the same thing: "Close\tCtrl+Shift+W". The
;;; desktop shows one menu at a time ((schevana desktop menu)): it opens the
;;; menu and takes its keys and the pointer. A style lays a menu out and
;;; draws it (menu-areas, draw-menu), reading it with the procedures here.

(library (schevana kits menu)
  (export
    menu make-menu menu-x menu-y menu-sel menu-sel-set! menu-filter
    menu-filter-set! menu-filter? menu-tag menu-label-text menu-label-key
    menu-label-width menu-entries menu-entry-action menu-entry-icon
    menu-icon-size)
  (import (chezscheme)
          (only (schevana base) at-load library-layer string-contains-ci?)
          (only (schevana core) font-line-height text-width theme
                theme-default!))

  (library-layer kits)

  ;; Whether a style's menus show their entries' icons: the Lisp machines'
  ;; and OPEN LOOK's menus are words alone, and so are a terminal's.
  (at-load
   (theme-default! 'menu-icons #t))

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

  ;; An entry's action, the thunk its choice runs, and its icon or #f.
  (define (menu-entry-action e)
    (if (pair? (cdr e)) (cadr e) (cdr e)))

  (define (menu-entry-icon e)
    (and (pair? (cdr e)) (caddr e)))

  ;; Returns the side of the icons that m's entries show in font: its line
  ;; height, or 0 when none of them has an icon or the style shows none
  ;; (menu-icons). An entry's text then starts that much and a gap further
  ;; in, so that the texts line up whether or not an entry has an icon.
  (define (menu-icon-size m font)
    (if (and (theme 'menu-icons)
             (exists (lambda (e) (and (pair? e) (menu-entry-icon e)))
                     (menu-entries m)))
        (round (font-line-height font))
        0))

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
