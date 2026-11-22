;;; (schevana palettes adwaita-dark) — GNOME's dark style, as libadwaita 1.7.6
;;; colors it (paths under its src/stylesheet/): the window #222226 (bg-1),
;;; views #1d1d20 (bg-0), header bars and sidebars #2e2e32, popovers and
;;; dialogs #36363a, cards white at 8 % over the window, #333337
;;; (_defaults.scss:40-84). Text is white; dimmed text white at 55 % over the
;;; window, #9c9c9d (_colors.scss:117); faint, at 40 % (widgets/
;;; _column-view.scss:28); a border white at 15 % (_colors.scss:1, 77). The
;;; accent is GNOME's blue, #3584e4, the same in both styles (_colors.scss:7);
;;; the named colors are GNOME's palette's light tones, which read on the dark
;;; (_palette.scss:1-45), and the destructive red its #c01c28
;;; (_defaults.scss:12). The top bar is the Shell's, black (shell
;;; _colors.scss:24). The desktop is the dark wallpaper's blues, #2e4a7b over
;;; #06194b (gnome-backgrounds 48's adwaita-d, its average and its darkest).

(library (schevana palettes adwaita-dark)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette adwaita-dark "Adwaita Dark"
     '(bg-0 #x1d1d20
       bg-1 #x222226
       bg-2 #x333337
       bg-3 #x38383c
       text #xffffff
       text-dim #x9c9c9d
       text-faint #x7a7a7d
       accent #x3584e4
       accent-2 #xc061cb
       red #xf66151
       orange #xffa348
       yellow #xf8e45c
       green #x57e389
       cyan #x7ad9f1
       teal #x78e9ab
       magenta #xdc8add
       desktop-top #x2e4a7b
       desktop-bottom #x06194b
       watermark #xffffff
       panel #x000000
       panel-text #xffffff
       panel-dim #x8c8c8c
       panel-hover #x2b2b2b
       window-border #x434347
       window-border-focus #x2e2e32
       title-bg #x222226
       title-bg-focus #x222226
       title-text #xffffff
       title-text-dim #x919193
       selection #x243c5b
       adwaita-headerbar #x2e2e32
       adwaita-sidebar #x2e2e32
       adwaita-card #x333337
       adwaita-popover #x36363a
       adwaita-dialog #x36363a
       adwaita-slider #xd2d2d3
       adwaita-destructive #xc01c28))))
