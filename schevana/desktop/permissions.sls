;;; (schevana desktop permissions) — asking the person what an app in a sandbox
;;; may do (services/grant.ss). The launcher opens an app that requests what no
;;; one decided yet only once they answer: a window lists its requests, ticked,
;;; to allow or not. Settings' Permissions page and Environments' Permissions…
;;; change the answers later; a crashed window says which one it lacked.

(library (schevana desktop permissions)
  (export
    launch-app-asking! open-permissions-dialog permissions-key
    permissions-dialog-height permissions-names permissions-dialog-draw
    permissions-decide!)
  (import (chezscheme)
          (only (schevana base) library-layer string-join)
          (only (schevana core) app app-name close-window! font-line-height
                new-window-position open-window safely screen-h screen-w
                window-ref window-set! windows)
          (only (schevana kits app) app-launch!)
          (only (schevana kits ui) ui-end! ui-button ui-button-size
                ui-checkbox-box ui-checkbox ui-draw-label ui-draw-surface
                ui-begin! ui-control-height ui-gap ui-pad ui-open-modal
                ui-handlers make-ui)
          (only (schevana services grant) grant-decide! grant-bundle-title
                grant-app-title grant-bundle-names grant-of grant-requested
                grant-undecided))

  (library-layer desktop)

  ;; Launches the app a from the launcher, asking first.
  (define (launch-app-asking! a)
    (let ([app (app-name a)])
      (if (pair? (grant-undecided app))
          ;; by name: deciding makes its sandbox, and its launcher, again
          (open-permissions-dialog app (lambda () (app-launch! app)))
          (app-launch! app))))

  ;; A window asking what app may do: its requests, ticked but for those
  ;; denied before. Allow decides them as ticked and runs then; Don't Allow
  ;; denies them all; closing it decides nothing, so the next launch asks
  ;; again. Given a parent, it waits over that window (ui-open-modal).
  ;; => the window
  (define (open-permissions-dialog app then . parent)
    (let* ([ui (make-ui)]
           [asked (grant-requested app)]
           [denied (let-values ([(ok no) (grant-of app)]) no)]
           [w (max 400 (round (* 30 (font-line-height 'ui))))]
           [h (permissions-dialog-height (length asked))]
           [old (find (lambda (win) (eq? (window-ref win 'permissions #f) app))
                      (windows))]
           [opts (append
                  (list 'min-size (cons w h)
                        'app #f
                        'permissions app
                        'ticked (remp (lambda (b) (memq b denied)) asked)
                        'draw (lambda (win w h)
                                (permissions-dialog-draw win ui app then w h)))
                  (ui-handlers ui
                               'key (lambda (win key mods)
                                      (permissions-key win app then key
                                                       mods))))])
      (when old (close-window! old))   ; one a time, with this one's then
      (if (pair? parent)
          (apply ui-open-modal (car parent) "Permissions" w h opts)
          (parameterize ([new-window-position
                          (cons (max 0 (exact (round (/ (- (screen-w) w) 2))))
                                (max 0
                                     (exact (round (/ (- (screen-h) h) 3)))))])
            (apply open-window "Permissions" 'size (cons w h) opts)))))

  (define (permissions-key win app then key mods)
    (and (null? mods)
         (case key
           [(return) (permissions-decide! win app then #t) #t]
           [(escape) (close-window! win) #t]
           [else #f])))

  ;; Tall enough for n requests, each a checkbox and the names it holds.
  (define (permissions-dialog-height n)
    (let ([pad (ui-pad)] [gap (ui-gap)])
      (round (+ pad (font-line-height 'heading) gap
                (* n (+ (ui-control-height) (font-line-height 'ui-small) gap))
                (font-line-height 'ui-small) gap
                (ui-control-height) pad pad))))

  ;; The first names a bundle holds, for the person who knows them.
  (define (permissions-names b)
    (let ([ns (map symbol->string (grant-bundle-names b))])
      (if (> (length ns) 4)
          (format "~a, and ~a more" (string-join (list-head ns 3) ", ")
                  (- (length ns) 3))
          (string-join ns ", "))))

  (define (permissions-dialog-draw win ui app then w h)
    (let* ([pad (ui-pad)] [gap (ui-gap)] [ch (ui-control-height)]
           [lw (- w pad pad)] [sh (font-line-height 'ui-small)]
           [ticked (window-ref win 'ticked '())]
           [foot (+ ch pad pad)])
      (ui-begin! ui)
      (ui-draw-surface 0 0 w h '(page))
      (let* ([y (ui-draw-label pad pad lw 0 '(heading)
                               (format "~a asks to" (grant-app-title app)))]
             [y (fold-left
                 (lambda (y b)
                   (let ([y (+ y gap)])
                     (ui-checkbox ui (list 'permissions b) pad y lw ch
                                  (grant-bundle-title b) (memq b ticked)
                                  (lambda (on)
                                    (window-set! win 'ticked
                                                 (if on
                                                     (cons b ticked)
                                                     (remq b ticked)))))
                     (ui-draw-label (+ pad (ui-checkbox-box) 8) (+ y ch)
                                    (- lw (ui-checkbox-box) 8) sh '(hint)
                                    (permissions-names b))
                     (+ y ch sh)))
                 y (grant-requested app))])
        (ui-draw-label pad (+ y gap) lw sh '(hint)
                       "Settings, Permissions changes this later."))
      (ui-draw-surface 0 (- h foot) w foot '(footer))
      (let*-values ([(aw ah) (ui-button-size "Allow" #f)]
                    [(dw dh) (ui-button-size "Don't Allow" #f)]
                    [(aw dw) (values (max aw 88) (max dw 88))]
                    [(by) (- h pad ch)])
        (ui-button ui '(permissions deny) (- w pad aw gap dw) by dw ch
                   "Don't Allow"
                   (lambda () (permissions-decide! win app then #f)))
        (ui-button ui '(permissions allow) (- w pad aw) by aw ch "Allow"
                   (lambda () (permissions-decide! win app then #t))
                   'primary #t))
      (ui-end! ui w h)))

  ;; Allowed: what is ticked approved, the rest denied, and then runs if
  ;; any was allowed. Not: all denied.
  (define (permissions-decide! win app then allow?)
    (let* ([asked (grant-requested app)]
           [ticked (window-ref win 'ticked '())]
           [yes (if allow? (filter (lambda (b) (memq b ticked)) asked) '())])
      (close-window! win)
      (grant-decide! app yes (remp (lambda (b) (memq b yes)) asked))
      (when (pair? yes) (safely app then)))))
