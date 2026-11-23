;;; (schevana desktop launcher) — the launcher: every registered app, and a
;;; few of the desktop's actions. The style's launcher-form says what F1 and
;;; a bar's launcher open: a menu ((schevana desktop menu)) under the top
;;; bar, or the app grid ((schevana desktop app-grid)), which shows the apps
;;; and finds the actions as you type, as GNOME's overview does. A right
;;; click on the desktop always opens the menu, whose apps open where the
;;; click was.

(library (schevana desktop launcher)
  (export
    launcher-open? open-launcher! toggle-launcher!)
  (import (chezscheme)
          (only (schevana base) at-load filter-map library-layer
                string-contains-ci?)
          (only (schevana core) *apps* app-name app-title desktop-rect
                fullscreen? new-window-position quit! reload! spawn theme
                theme-default! toggle-fullscreen!)
          (only (schevana kits app) app-launch!)
          (only (schevana kits menu) menu-label-text)
          (only (schevana kits ui) ui-draw-app-icon ui-menu-open-tag)
          (only (schevana desktop app-grid) app-grid-open? close-app-grid!
                open-app-grid!)
          (only (schevana desktop arrange) cascade-windows! tile-windows!)
          (only (schevana desktop menu) close-menu! open-menu!)
          (only (schevana desktop screenshot) save-screenshot!))

  (library-layer desktop)

  ;; What the launcher is: menu, or grid.
  (at-load
   (theme-default! 'launcher-form 'menu))

  (define (launcher-apps)
    (sort (lambda (a b) (string<? (app-title a) (app-title b))) *apps*))

  ;; The desktop's actions, as a menu's entries.
  (define (launcher-actions)
    (list (cons "Tile windows\tCtrl+Shift+T" (lambda () (tile-windows!)))
          (cons "Cascade windows" (lambda () (cascade-windows!)))
          (cons (if (fullscreen?) "Leave full screen\tF11" "Full screen\tF11")
                (lambda () (toggle-fullscreen!)))
          (cons "Screenshot\tF12" (lambda () (save-screenshot!)))
          (cons "Reload sources" (lambda () (spawn "reload" reload!)))
          (cons "Quit Schevana" (lambda () (quit!)))))

  ;; The menu's entries: the apps, each with its icon, then the actions.
  ;; at: where the apps' windows open (see new-window-position), or #f.
  (define (launcher-items at)
    (append
     (map (lambda (a)
            (let ([name (app-name a)])
              (list (app-title a)
                    (lambda ()
                      (parameterize ([new-window-position at])
                        (app-launch! name)))
                    (lambda (x y s flags)
                      (ui-draw-app-icon x y s flags name)))))
          (launcher-apps))
     (cons 'separator (launcher-actions))))

  ;; The grid's entries for what is typed, f: each app whose title holds f,
  ;; and, once something is typed, each action whose text holds it, as GNOME
  ;; finds its system actions. Each is (label app . thunk), where app is the
  ;; app's name, or #f for an action.
  (define (launcher-grid-entries f)
    (append
     (filter-map (lambda (a)
                   (and (string-contains-ci? (app-title a) f)
                        (cons* (app-title a) (app-name a)
                               (lambda () (app-launch! (app-name a))))))
                 (launcher-apps))
     (if (string=? f "")
         '()
         (filter-map (lambda (e)
                       (let ([text (menu-label-text (car e))])
                         (and (string-contains-ci? text f)
                              (cons* text #f (cdr e)))))
                     (launcher-actions)))))

  ;; Returns the launcher's form while it is open, menu or grid, else #f.
  (define (launcher-open?)
    (cond [(app-grid-open?) 'grid]
          [(eq? (ui-menu-open-tag) 'launcher) 'menu]
          [else #f]))

  ;; Opens the launcher's menu at (x, y); at, if given, is where the apps'
  ;; windows open.
  (define (open-launcher! x y . at)
    (open-menu! x y (launcher-items (and (pair? at) (car at)))
                'filter #t 'tag 'launcher))

  (define (toggle-launcher!)
    (case (launcher-open?)
      [(menu) (close-menu!)]
      [(grid) (close-app-grid!)]
      [else
       (if (eq? (theme 'launcher-form) 'grid)
           (begin (close-menu!)
                  (open-app-grid! (lambda (f) (launcher-grid-entries f))))
           ;; just under the strips at the screen's top (the top bar)
           (let-values ([(l t w h) (desktop-rect)])
             (open-launcher! 6 (+ 2 t))))])))
