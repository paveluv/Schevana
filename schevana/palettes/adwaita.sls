;;; (schevana palettes adwaita) — GNOME's light style, in the colors
;;; libadwaita 1.7.6 and GNOME Shell 48.7 give it (paths are under
;;; libadwaita's src/stylesheet/ or, when marked shell, under GNOME Shell's
;;; data/theme/gnome-shell-sass/). The window is #fafafb (bg-1), views and
;;; cards are white (bg-0), header bars are white, and sidebars are #ebebed
;;; (_defaults.scss:40-84). Text is rgb(0 0 6 / 80%), which is #323237 over
;;; the window; dimmed text is that color at 55 % (_colors.scss:117), and
;;; faint text is at the 40 % of a column's heading
;;; (widgets/_column-view.scss:28); a border is the text at 15 %
;;; (_colors.scss:1, 77). The accent is the blue GNOME chooses by default,
;;; #3584e4 (_colors.scss:7); the named colors are GNOME's palette
;;; (_palette.scss:1-45), and red is the destructive red (_defaults.scss:12).
;;; The top bar is the Shell's, black: the Shell stays dark unless the person
;;; prefers light (shell _colors.scss:24-25, js/ui/sessionMode.js:25). The
;;; desktop uses GNOME's fallback blues for its wallpaper, #5789ca over
;;; #023c88 (org.gnome.desktop.background).

(library (schevana palettes adwaita)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette adwaita "Adwaita"
     '(bg-0 #xffffff
       bg-1 #xfafafb
       bg-2 #xffffff
       bg-3 #xe6e6e7
       text #x323237
       text-dim #x8c8c8f
       text-faint #xaaaaad
       accent #x3584e4
       accent-2 #x9141ac
       red #xe01b24
       orange #xe66100
       yellow #xe5a50a
       green #x2ec27e
       cyan #x0f9ac8
       teal #x2190a4
       magenta #xc061cb
       desktop-top #x5789ca
       desktop-bottom #x023c88
       watermark #xffffff
       panel #x000000
       panel-text #xffffff
       panel-dim #x8c8c8c
       panel-hover #x2b2b2b
       window-border #xdcdcde
       window-border-focus #xdbdbdb
       title-bg #xfafafb
       title-bg-focus #xfafafb
       title-text #x323237
       title-text-dim #x969699
       selection #xc2daf7
       adwaita-headerbar #xffffff
       adwaita-sidebar #xebebed
       adwaita-card #xffffff
       adwaita-popover #xffffff
       adwaita-dialog #xfafafb
       adwaita-slider #xffffff
       adwaita-destructive #xe01b24))))
