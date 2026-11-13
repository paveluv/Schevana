;;; icon.ss — the app icon: core0's window's icon in the taskbar or dock,
;;; the wallpaper's λ on the desktop gradient, in the current theme.
;;; Redefine draw-app-icon and call (update-app-icon!) to change it.

(define-part (draw-app-icon size)
  (let* ([m (* size 0.06)] [s (- size m m)] [r (* s 0.22)])
    (with-clip (m m s s r)
      (fill-gradient m m s s 'desktop-top 'desktop-bottom)
      (fill-glow (+ m (* s 0.8)) (+ m (* s 0.2)) (* s 0.9)
                 (alpha 'accent-2 0.30))
      (fill-glow (+ m (* s 0.15)) (+ m (* s 0.9)) (* s 0.8)
                 (alpha 'accent 0.25)))
    (stroke-box (+ m 0.5) (+ m 0.5) (- s 1) (- s 1) (alpha 'text 0.18) 1 r)
    (text-draw-centered m m s s "λ" 'text
                        (make-font* "serif" (* s 0.72) 'bold))))

(define (update-app-icon!) (screen-set-icon! 256 draw-app-icon))

;;; Desktops like GNOME don't use the icon a window sets: they show the
;;; icon of the app's .desktop file, which they match to the window by its
;;; app id (core0-app-id; the class under X11). (install-desktop-entry!)
;;; writes that file and the icon under ~/.local/share; ./schevana
;;; --install-desktop does the same.

(define (desktop-data-home)
  (or (getenv "XDG_DATA_HOME")
      (string-append (or (getenv "HOME") ".") "/.local/share")))

(define (desktop-entry-files)
  (let ([data (desktop-data-home)])
    ;; named after the app id, which Wayland desktops look it up by
    (values (string-append data "/applications/" core0-app-id ".desktop")
            (string-append data "/icons/hicolor/256x256/apps/schevana.png"))))

(define (make-directories! path)
  (unless (or (string=? path "") (file-exists? path))
    (make-directories! (path-parent path))
    (mkdir path)))

;; The app icon as a PNG file, size pixels square.
(define (write-app-icon! path size)
  (png-write-drawing path size size (lambda () (draw-app-icon size))))

;; Returns the files it wrote.
(define (install-desktop-entry!)
  (let-values ([(entry icon) (desktop-entry-files)])
    (let* ([root (cond [(path-absolute? *schevana-root*) *schevana-root*]
                       [(member *schevana-root* '("." "")) (current-directory)]
                       [else (string-append (current-directory) "/"
                                            *schevana-root*)])]
           [exec (string-append root "/schevana")])
      (make-directories! (path-parent entry))
      (make-directories! (path-parent icon))
      (write-app-icon! icon 256)
      (call-with-output-file entry
        (lambda (p)
          (fprintf p "[Desktop Entry]~%Type=Application~%Name=Schevana~%")
          (fprintf p
            "Comment=A Lisp Machine-style desktop written in Chez Scheme~%")
          (fprintf p "Exec=\"~a\"~%Icon=schevana~%Terminal=false~%\
                      Categories=Development;~%" exec)
          (fprintf p "StartupWMClass=~a~%" core0-app-id))
        'replace)
      ;; let the desktop notice; harmless where these tools are missing
      (system (format
               "update-desktop-database -q '~a' 2>/dev/null; \
                gtk-update-icon-cache -q -t '~a/icons/hicolor' 2>/dev/null"
               (path-parent entry) (desktop-data-home)))
      (list entry icon))))

(define (uninstall-desktop-entry!)
  (let-values ([(entry icon) (desktop-entry-files)])
    (for-each (lambda (f) (when (file-exists? f) (delete-file f)))
              (list entry icon))
    (system (format "update-desktop-database -q '~a' 2>/dev/null"
                    (path-parent entry)))
    (list entry icon)))

(defvar *icon-update-pending* #f)
;; the theme the icon follows
(defvar *icon-version* *theme-version*)

;; At the desktop's tick: a newer theme repaints the icon, soon after.
(define (icon-follow-theme!)
  (unless (eqv? *icon-version* *theme-version*)
    (set! *icon-version* *theme-version*)
    (update-app-icon-soon!)))

;; Follow theme changes, once things settle.
(define (update-app-icon-soon!)
  (unless *icon-update-pending*
    (set! *icon-update-pending* #t)
    (after 500 (lambda ()
                 (set! *icon-update-pending* #f)
                 (update-app-icon!)))))
