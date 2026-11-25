;;; (demo widgets overlays) — the Widgets demo's page of what opens over
;;; the rest: menus (a widget's, a right press's, a window's, one that
;;; filters as you type), the calendar, a dialog, a sheet, a window that
;;; waits over this one, a tooltip and toasts; and what a view shows about
;;; itself: a banner, and a status page for a view with nothing to show.

(library (demo widgets overlays)
  (export widgets-overlays-page)
  (import (chezscheme)
          (schevana core)
          (schevana kits ui)
          (schevana desktop menu)
          (demo widgets layout))

  ;; An editor's menu: each entry with the key that does the same, one
  ;; that can't be chosen now, and groups apart.
  (define (widgets-edit-menu win)
    (let ([say (lambda (text) (widgets-said win text))])
      (list (cons "Undo\tCtrl+Z" (say "Undo"))
            (cons "Redo\tCtrl+Shift+Z" (say "Redo"))
            'separator
            (cons "Cut\tCtrl+X" (say "Cut"))
            (cons "Copy\tCtrl+C" (say "Copy"))
            (cons "Paste\tCtrl+V" (say "Paste"))
            (cons "Paste as plain text\tCtrl+Shift+V" #f)
            'separator
            (cons "Select all\tCtrl+A" (say "Select all")))))

  ;; A menu of many entries that filters as you type, as a launcher's does.
  (define (widgets-filter-menu win)
    (map (lambda (name)
           (cons name (widgets-said win (string-append "Chose " name))))
         '("Boids" "Clock" "Environments" "Life" "Monitor" "REPL" "Settings"
           "Sketch" "Springies" "Tasks" "Widgets")))

  ;; Opens a small window that waits over win, as a file dialog does, with
  ;; a button that closes it.
  (define (widgets-open-modal! win)
    (let ([ui (make-ui)])
      (apply ui-open-modal win "Waiting over Widgets" 360 160
             'draw (lambda (child w h)
                     (let ([ch (ui-control-height)] [pad (ui-pad)])
                       (ui-begin! ui)
                       (ui-draw-surface 0 0 w h '(page))
                       (ui-draw-label pad pad (- w pad pad) (* 3 ch)
                                      '(wrap)
                                      "This window waits over the Widgets \
                                       window, which takes no input until \
                                       it closes.")
                       (ui-button ui 'close (- w pad (widgets-width "Close"))
                                  (- h pad ch) (widgets-width "Close") ch
                                  "Close"
                                  (lambda ()
                                    (close-window! child)
                                    (widgets-say! win "Closed the window"))
                                  'primary #t)
                       (ui-end! ui w h)))
             (ui-handlers ui))))

  ;; Returns (values right bottom) of the page drawn from (x, y), w wide.
  (define (widgets-overlays-page ui win x y w)
    (let* ([ch (ui-control-height)] [gap (ui-gap)]
           [get (lambda (key default) (window-ref win key default))]
           [keep (lambda (key) (widgets-keep win key))]
           [say (lambda (text) (widgets-said win text))]
           [close (lambda (key) (lambda () (window-set! win key #f)))]
           [y (widgets-heading x y w "Menus and the calendar")]
           [y (widgets-flow x y w
                (list (widgets-width "Menu…") ch
                      (lambda (x y w h)
                        (ui-button ui 'menu x y w h "Menu…"
                          (lambda ()
                            (ui-open-menu! ui x (+ y h)
                              (list (cons "Say hello" (say "Hello"))
                                    (list "With an icon" (say "An icon")
                                          (lambda (x y s flags)
                                            (ui-draw-glyph x y s s flags
                                                           'gear)))
                                    (cons "With its key\tCtrl+K"
                                          (say "Pressed Ctrl+K"))
                                    'separator
                                    (cons "Can't be chosen" #f)))))))
                (list (widgets-width "Text menu…") ch
                      (lambda (x y w h)
                        (ui-button ui 'text-menu x y w h "Text menu…"
                          (lambda ()
                            (ui-open-text-menu! ui x (+ y h) "Some text"
                              (lambda (text)
                                (widgets-say! win
                                              (format "Pasted ~s" text))))))))
                (let-values ([(dw dh) (ui-dropdown-size '("Sep 30, 2026"))])
                  (list dw dh
                        (lambda (x y w h)
                          (ui-date-field ui 'calendar x y w h
                                         (get 'calendar '(2026 9 30))
                                         (keep 'calendar)
                                         'tip "Opens the calendar")))))]
           [y (widgets-heading x y w "Pop-up menus")]
           [y (widgets-note x y w
                "A right press opens a menu where it is; a window's own \
                 menu is the one its title opens.")]
           [y (widgets-flow x y w
                (list 240 (* 2 ch)
                      (lambda (x y w h)
                        (widgets-frame x y w h)
                        (ui-draw-label x y w h '(center hint)
                                       "Right press here")
                        (ui-region! ui 'right-press x y w h
                          'on (lambda (ev)
                                (when (and (eq? (car ev) 'press)
                                           (eq? (list-ref ev 3) 'right))
                                  (ui-open-menu! ui (cadr ev) (caddr ev)
                                                 (widgets-edit-menu win)))
                                #t)
                          'doc '((R . "Menu")))))
                (list (widgets-width "Edit menu…") ch
                      (lambda (x y w h)
                        (ui-button ui 'edit-menu x y w h "Edit menu…"
                          (lambda ()
                            (ui-open-menu! ui x (+ y h)
                                           (widgets-edit-menu win))))))
                (list (widgets-width "Window menu…") ch
                      (lambda (x y w h)
                        (ui-button ui 'window-menu x y w h "Window menu…"
                          (lambda ()
                            (let-values ([(cx cy cw ch) (content-rect win)])
                              (open-window-menu win (+ cx x) (+ cy y h)))))))
                (list (widgets-width "Filter menu…") ch
                      (lambda (x y w h)
                        (ui-button ui 'filter-menu x y w h "Filter menu…"
                          (lambda ()
                            (ui-open-menu! ui x (+ y h)
                                           (widgets-filter-menu win)
                                           'filter #t))))))]
           [y (widgets-heading x y w "Dialogs and windows")]
           [y (widgets-flow x y w
                (list (widgets-width "Dialog…") ch
                      (lambda (x y w h)
                        (ui-button ui 'dialog x y w h "Dialog…"
                                   (lambda () (window-set! win 'dialog #t)))))
                (list (widgets-width "Sheet…") ch
                      (lambda (x y w h)
                        (ui-button ui 'sheet x y w h "Sheet…"
                                   (lambda () (window-set! win 'sheet #t)))))
                (list (widgets-width "Window…") ch
                      (lambda (x y w h)
                        (ui-button ui 'modal x y w h "Window…"
                                   (lambda () (widgets-open-modal! win))
                                   'tip "A window that waits over this \
                                         one"))))]
           [y (widgets-heading x y w "Tooltips and toasts")]
           [y (widgets-flow x y w
                (list (widgets-width "Rest on me") ch
                      (lambda (x y w h)
                        (ui-button ui 'tip x y w h "Rest on me"
                                   (say "Pressed the button with a tip")
                                   'tip "A tooltip: it shows once the \
                                         pointer has rested on its widget, \
                                         and wraps when it is long, as this \
                                         one is.")))
                (list (widgets-width "Toast") ch
                      (lambda (x y w h)
                        (ui-button ui 'toast x y w h "Toast"
                                   (lambda () (notify "A toast")))))
                (list (widgets-width "Error toast") ch
                      (lambda (x y w h)
                        (ui-button ui 'toast-red x y w h "Error toast"
                                   (lambda ()
                                     (notify "Something went wrong" 'red)))))
                (list (widgets-width "Done toast") ch
                      (lambda (x y w h)
                        (ui-button ui 'toast-green x y w h "Done toast"
                                   (lambda () (notify "Done" 'green))))))]
           [y (widgets-heading x y w "Banners")]
           [y (let* ([bw (min w 560)]
                     [h1 (ui-banner ui 'offline x y bw "You are offline"
                                    "Retry" (say "Retrying"))]
                     [h2 (ui-banner ui 'notice x (+ y h1 gap) bw
                                    "A banner with no button" #f #f)])
                (+ y h1 gap h2 gap))]
           [y (widgets-heading x y w "Status pages")]
           [y (let* ([pw (min (quotient (- w gap) 2) 300)] [ph 260])
                (widgets-frame x y pw ph)
                (ui-status-page ui 'empty x y pw ph 'folder "No Files"
                                "Add a file to see it here"
                                'button (list "Add a File"
                                              (say "Added a file")))
                (widgets-frame (+ x pw gap) y pw ph)
                (ui-status-page ui 'compact (+ x pw gap) y pw ph
                                (lambda (x y s flags)
                                  (ui-draw-glyph x y s s flags 'search))
                                "No Results" #f 'compact #t)
                (+ y ph gap))])
      (when (get 'dialog #f)
        (ui-dialog ui 'dialog-box "Delete the file?"
                   "It goes for good: there is no undo. Escape, or a press \
                    outside, cancels."
                   (list (list "Cancel"
                               (lambda ()
                                 ((close 'dialog))
                                 (widgets-say! win "Cancelled")))
                         (list "Delete"
                               (lambda ()
                                 ((close 'dialog))
                                 (widgets-say! win "Deleted"))
                               'danger))
                   (close 'dialog)))
      (when (get 'sheet #f)
        (let* ([rows (list (list "Name" ch
                                 (lambda (x y w)
                                   (ui-text-field ui '(sheet-box name) x y w ch
                                                  (get 'sheet-name "Untitled")
                                                  (keep 'sheet-name))))
                           (list "Copies" ch
                                 (lambda (x y w)
                                   (ui-stepper ui '(sheet-box copies) x y
                                               (get 'sheet-copies 1) 1 9
                                               (keep 'sheet-copies)))))]
               [bw 320] [bh (ui-form-height rows bw)])
          (ui-sheet ui 'sheet-box "Rename" bw bh
                    (lambda (x y w) (ui-form ui '(sheet-box form) x y w rows))
                    (list (list "Cancel" (close 'sheet))
                          (list "Rename"
                                (lambda ()
                                  ((close 'sheet))
                                  (widgets-say! win
                                                (format "Renamed to ~a"
                                                        (get 'sheet-name
                                                             "Untitled"))))
                                'primary))
                    (close 'sheet))))
      (values (+ x w) y))))
