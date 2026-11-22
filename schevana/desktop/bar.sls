;;; (schevana desktop bar) — what the two bars share. A bar's areas, ((what x y
;;; w h) ...) from its part (topbar-areas, taskbar-areas), are where it draws
;;; each thing and where that thing takes the pointer, so a style that moves
;;; one moves its clicks too. what: launcher, title, hint, windows (a list of
;;; them), or a window. Both are computed in the bars' place, bar, as the bars
;;; draw.

(library (schevana desktop bar)
  (export
    bar-at bar-mouse)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) *focus* *windows* close-window! focus-window!
                minimize-window! point-in? visible? window-title window?)
          (only (schevana desktop menu) open-window-menu open-menu!
                toggle-launcher!))

  (library-layer desktop)

  ;; What of areas is at (x, y); the bar takes every other point of its
  ;; strip.
  (define (bar-at areas x y)
    (let ([a (find (lambda (a) (apply point-in? x y (cdr a))) areas)])
      (if a (car a) 'bar)))

  ;; A press on a bar's area: the launcher opens or closes; windows lists
  ;; them to choose from; a window is focused or minimized (left), closed
  ;; (middle) or given its menu at the area's top (right).
  (define (bar-mouse areas kind what x y button clicks)
    (when (eq? kind 'down)
      (cond
        [(eq? what 'launcher) (toggle-launcher!)]
        [(eq? what 'windows)
         (open-menu! x y (map (lambda (w)
                                (cons (window-title w)
                                      (lambda () (focus-window! w))))
                              (reverse *windows*)))]
        [(window? what)
         (case button
           [(left) (if (and (eq? what *focus*) (visible? what))
                       (minimize-window! what)
                       (focus-window! what))]
           [(middle) (close-window! what)]
           [(right) (open-window-menu what x (caddr (assq what areas)))])]))))
