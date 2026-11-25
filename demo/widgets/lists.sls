;;; (demo widgets lists) — the Widgets demo's page of lists: a table and a
;;; tree, a box of rows, a list of places, a form and a toolbar.

(library (demo widgets lists)
  (export widgets-lists-page)
  (import (chezscheme)
          (schevana core)
          (schevana kits ui)
          (demo widgets layout))

  ;; The table's rows: a planet, its distance from the Sun in AU, and its
  ;; moons.
  (define widgets-planets
    '(("Mercury" 0.39 0)
      ("Venus" 0.72 0)
      ("Earth" 1.0 1)
      ("Mars" 1.52 2)
      ("Jupiter" 5.2 95)
      ("Saturn" 9.54 146)
      ("Uranus" 19.2 28)
      ("Neptune" 30.1 16)))

  ;; Returns the planets sorted by sort, (key . up|down).
  (define (widgets-planets-sorted sort)
    (let* ([field (case (car sort) [(au) cadr] [(moons) caddr] [else car])]
           [less (lambda (a b)
                   (let ([x (field a)] [y (field b)])
                     (if (string? x) (string<? x y) (< x y))))]
           [up (list-sort less widgets-planets)])
      (if (eq? (cdr sort) 'up) up (reverse up))))

  ;; Draws a planet's cell.
  (define (widgets-planet-cell row key x y w h flags)
    (ui-draw-cell x y w h flags
                  (case key
                    [(name) (car row)]
                    [(au) (number->string (cadr row))]
                    [else (number->string (caddr row))])))

  ;; The tree's roots: a node is a name, or (name child ...).
  (define widgets-tree-roots
    '(("schevana"
       ("core0" "window" "gpu" "trace")
       ("core" "theme" "draw" "fonts" "windows")
       ("kits" "ui" "edit" "text" "menu")
       ("styles" "mac" "genera" "cons"))
      ("demo" "widgets" "life" "boids")))

  (define (widgets-tree-name node) (if (pair? node) (car node) node))

  (define (widgets-tree-children node) (if (pair? node) (cdr node) '()))

  ;; Returns (values right bottom) of the page drawn from (x, y), w wide.
  (define (widgets-lists-page ui win x y w)
    (let* ([ch (ui-control-height)] [gap (ui-gap)]
           [get (lambda (key default) (window-ref win key default))]
           [keep (lambda (key) (widgets-keep win key))]
           [say (lambda (text) (widgets-said win text))]
           [tw (min w 560)]
           [y (widgets-heading x y w "Table")]
           [y (widgets-note x y tw
                "A press on a heading sorts by it, a double click opens a \
                 row, a right click opens its menu, and a heading's edge \
                 resizes its column. The boxes check rows; Earth's stays \
                 checked.")]
           [y (let* ([sort (get 'planet-sort '(name . up))]
                     [checked (get 'planet-checked '("Earth" "Mars"))]
                     [th (+ (ui-table-header-height)
                            (* 6 (ui-table-row-height)))])
                (ui-table ui 'planets x y tw th
                          (ui-table-fit (ui-table-room tw)
                                        '((name "Planet" #f "Its name")
                                          (au "AU" 90 right
                                              "How far it is from the Sun")
                                          (moons "Moons" 90 right))
                                        '() 0)
                          (widgets-planets-sorted sort)
                          (get 'planet #f) (keep 'planet) widgets-planet-cell
                          'sort sort
                          'on-sort (lambda (key)
                                     ((keep 'planet-sort)
                                      (cons key
                                            (if (equal? sort (cons key 'up))
                                                'down
                                                'up))))
                          'on-open (lambda (row)
                                     (widgets-say! win
                                                   (format "Opened ~a"
                                                           (car row))))
                          'on-menu (lambda (row mx my)
                                     (ui-open-menu! ui mx my
                                       (list (cons "Open"
                                                   (say (format "Opened ~a"
                                                                (car row))))
                                             'separator
                                             (cons "Can't be chosen" #f))))
                          'checked (lambda (row)
                                     (cond [(equal? (car row) "Earth") 'fixed]
                                           [(member (car row) checked) #t]
                                           [else #f]))
                          'on-check (lambda (row)
                                      ((keep 'planet-checked)
                                       (if (member (car row) checked)
                                           (remove (car row) checked)
                                           (cons (car row) checked))))
                          'tip (lambda (row)
                                 (format "~a: ~a AU from the Sun"
                                         (car row) (cadr row))))
                (+ y th gap))]
           [y (widgets-heading x y w "Tree")]
           [y (let ([th (+ (ui-table-header-height)
                           (* 7 (ui-table-row-height)))])
                (ui-tree ui 'layers x y tw th
                         (ui-table-fit (ui-table-room tw)
                                       '((name "Name" #f)
                                         (kind "Kind" 120))
                                       '() 0)
                         widgets-tree-roots widgets-tree-children
                         (get 'layer #f) (keep 'layer)
                         (lambda (node key x y w h flags)
                           (ui-draw-cell x y w h flags
                                         (if (eq? key 'name)
                                             (widgets-tree-name node)
                                             (if (pair? node)
                                                 "folder"
                                                 "library"))))
                         'expanded #t
                         'dim (lambda (node) (equal? node "trace"))
                         'on-open (lambda (node)
                                    (widgets-say!
                                     win
                                     (format "Opened ~a"
                                             (widgets-tree-name node))))
                         'tip (lambda (node w) (widgets-tree-name node)))
                (+ y th gap))]
           [y (widgets-heading x y w "Rows")]
           [y (+ gap
                 (ui-rows ui 'net x y tw
                   (list (ui-switch-row ui 'wifi "Wi-Fi" (get 'wifi #t)
                                        (keep 'wifi) 'subtitle "Connected")
                         (ui-check-row ui 'metered "Metered"
                                       (get 'metered #f) (keep 'metered)
                                       'subtitle "Less data in the background")
                         (ui-entry-row ui 'proxy "Proxy" (get 'proxy "")
                                       (keep 'proxy))
                         (list "Details" "A row that a press opens" 0 #f
                               'on-press (say "Opened the details"))
                         (list "Version" #f 80
                               (lambda (x y w h)
                                 (ui-draw-label x y w h '(dim right) "2.0")))
                         (list "Disabled" "A row that can't be used now" 0 #f
                               'on-press (say "A disabled row did something")
                               'disabled #t)
                         (list "Selected" #f 0 #f 'selected #t))
                   'title "Network"
                   'description "How this machine connects"
                   'add (list "Add a network" (say "Added a network"))))]
           [y (+ gap
                 (ui-rows ui 'empty-rows x y tw '()
                          'title "No rows"
                          'add (list "Add the first" (say "Added one"))))]
           [y (widgets-heading x y w "Places")]
           [y (ui-nav ui 'places x y (min tw 220)
                      (map (lambda (place label glyph)
                             (list place label
                                   (lambda (x y s flags)
                                     (ui-draw-glyph x y s s flags glyph))))
                           '(home files drive trash)
                           '("Home" "Files" "Drive" "Trash")
                           '(home file drive cross))
                      (get 'place 'home) (keep 'place))]
           [y (widgets-heading x y w "Form")]
           [y (let* ([fw (min tw 480)]
                     [notes (get 'form-notes "Notes that wrap at the \
                                               form's width")]
                     [rows
                      (list
                       (list 'section "Account")
                       (list "Name" ch
                             (lambda (x y w)
                               (ui-text-field ui 'form-name x y w ch
                                              (get 'form-name "")
                                              (keep 'form-name)
                                              'placeholder "Your name"))
                             'tip "What others see")
                       (list "Copies" ch
                             (lambda (x y w)
                               (ui-stepper ui 'form-copies x y
                                           (get 'form-copies 1) 1 99
                                           (keep 'form-copies)))
                             'hint "How many to print, from 1 to 99")
                       (list "Volume" (ui-slider-height)
                             (lambda (x y w)
                               (ui-slider ui 'form-volume x y w
                                          (get 'form-volume 50) 0 100
                                          (lambda (v)
                                            ((keep 'form-volume)
                                             (exact (round v)))))))
                       (list "Notes"
                             (lambda (w)
                               (let-values ([(aw ah)
                                             (ui-text-area-size
                                              ui 'form-notes '(lines) w notes
                                              2 4)])
                                 ah))
                             (lambda (x y w)
                               (let-values ([(aw ah)
                                             (ui-text-area-size
                                              ui 'form-notes '(lines) w notes
                                              2 4)])
                                 (ui-text-area ui 'form-notes x y w ah notes
                                               (keep 'form-notes)))))
                       (list 'section "Options")
                       (list #f ch
                             (lambda (x y w)
                               (ui-checkbox ui 'form-sound x y w ch "Sound"
                                            (get 'form-sound #t)
                                            (keep 'form-sound)))))])
                (+ gap (ui-form ui 'form x y fw rows)))]
           [y (widgets-heading x y w "Toolbar")]
           [y (let-values ([(dw dh) (ui-dropdown-size '("Newest first"))])
                (+ y gap
                   (ui-toolbar x y tw
                     (list (list (widgets-width #f 'plus) ch
                                 (lambda (x y w h)
                                   (ui-button ui 'tb-add x y w h #f
                                              (say "Pressed Add") 'glyph 'plus
                                              'quiet #t 'tip "Add")))
                           (list #f ch
                                 (lambda (x y w h)
                                   (ui-text-field ui 'tb-filter x y w h
                                                  (get 'tb-filter "")
                                                  (keep 'tb-filter)
                                                  'search #t
                                                  'placeholder "Filter")))
                           (list dw ch
                                 (lambda (x y w h)
                                   (ui-dropdown ui 'tb-order x y w h
                                                '(("Newest first" . new)
                                                  ("Oldest first" . old))
                                                (get 'tb-order 'new)
                                                (keep 'tb-order)))))
                     'end (list (widgets-width "8 items") ch
                                (lambda (x y w h)
                                  (ui-draw-label x y w h '(dim right)
                                                 "8 items")))
                     'flex '(120 . 260))))])
      (values (+ x w) y))))
