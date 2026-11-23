;;; (demo backlog) — a backlog for Tasks to show, Schevana's own as it
;;; once stood, entered with Tasks' own procedures, as you would enter it
;;; at a REPL: each task added in the order of its id, then the tasks it
;;; waits for, then the board put in order. It is entered once, when the
;;; world first loads it (with the demos' folder: ./desktop demo), and a
;;; reload adds nothing. Four tasks hold long descriptions, made from the
;;; tree's own files, which show Tasks at its largest.

(library (demo backlog)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load-once)
          (schevana core)
          (schevana kits ui)
          (schevana apps tasks))

  ;; Returns the date n days from today, as Tasks takes a due date.
  (define (backlog-in-days n)
    (ui-day->date (+ (ui-date->day (ui-today)) n)))

  ;; Returns the text of file f, a path from the tree's root.
  (define (backlog-file f)
    (call-with-input-file (string-append *schevana-root* "/" f)
      get-string-all))

  ;; Returns the titles of the tasks so far as one paragraph, over and over,
  ;; until it holds the most that a description holds.
  (define (backlog-paragraph)
    (let ([titles (apply string-append
                         (map (lambda (t) (string-append (task-title t) ". "))
                              (tasks-list)))])
      (let loop ([s titles])
        (if (>= (string-length s) tasks-description-max)
            s
            (loop (string-append s titles))))))

  ;; Returns the start of the widget kit's source in base64, a word with no
  ;; space as long as a description holds.
  (define (backlog-blob)
    (let ([bv (string->utf8
               (substring (backlog-file "schevana/kits/ui.sls")
                          0 (* 3/4 tasks-description-max)))]
          [abc "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz\
                0123456789+/"]
          [o (open-output-string)])
      (do ([i 0 (+ i 3)]) ((>= i (bytevector-length bv)) (get-output-string o))
        (let ([v (fold-left (lambda (v k)
                              (+ (* v 256)
                                 (if (< (+ i k) (bytevector-length bv))
                                     (bytevector-u8-ref bv (+ i k))
                                     0)))
                            0 '(0 1 2))])
          (for-each (lambda (k)   ; six bits per digit, = past the end
                      (write-char
                       (if (<= k (- (bytevector-length bv) i))
                           (string-ref abc (fxand 63 (fxsra v (- 18 (* 6 k)))))
                           #\=)
                       o))
                    '(0 1 2 3))))))

  (at-load-once
   (add-task! "Switch from SDL2 to SDL3"
              'status 'done
              'kind 'chore
              'assignee "Claude"
              'tags '("sdl" "core0")
              'description "Fractional wheel steps add up to whole ones, and \
                            the app id names the window for the desktop.")
   (add-task! "Add nine window styles"
              'status 'done
              'assignee "Claude"
              'tags '("style")
              'description "Cons, Curses, Draft, Fold, Halo, Lambda, Reticle, \
                            Slab and Spine, one file each in styles/.")
   (add-task! "Redraw only what changed"
              'status 'done
              'priority 'high
              'assignee "Claude"
              'tags '("render" "perf")
              'description "A change says where it shows; a frame draws only \
                            that box, compares its rows with the screen and \
                            uploads the ones that differ.")
   (add-task! "Split the world into folders, at 80 columns"
              'status 'done
              'kind 'chore
              'assignee "Claude"
              'tags '("structure")
              'description "Kits, styles, palettes, wallpapers and apps are \
                            folders, one definition per file, loaded in \
                            file-name order.")
   (add-task! "HiDPI: draw from outlines at any scale"
              'status 'done
              'priority 'high
              'assignee "Claude"
              'tags '("render")
              'description "Everything is drawn from outlines at the scale, so \
                            text and shapes stay sharp at 125, 150 or 200%.")
   (add-task! "REPL completion with docs"
              'status 'done
              'assignee "Claude"
              'tags '("repl")
              'description "Tab lists the names that fit where the cursor is, \
                            with each one's arguments and the comment above \
                            its definition.")
   (add-task! "Check SDL3 in a real window"
              'status 'review
              'kind 'chore
              'priority 'urgent
              'assignee "Pavel"
              'tags '("sdl" "core0")
              'due (backlog-in-days 1)
              'checklist '("HiDPI at 200% on GNOME" "Typing with an IME"
                           ("Clipboard both ways" . #t) "Full screen and back"
                           ("Resize while drawing" . #t))
              'description "Everything SDL3 does was tried against a stand-in. \
                            Try it on a real desktop before trusting it.")
   (add-task! "Match Genera's margins to the 1986 manuals"
              'status 'review
              'kind 'chore
              'priority 'low
              'assignee "Pavel"
              'tags '("style" "genera")
              'description "Check the margins and the label in the bottom-left \
                            corner against the manuals' figures.")
   (add-task! "Tasks app and its widget kit"
              'status 'doing
              'priority 'high
              'assignee "Claude"
              'tags '("apps" "kit")
              'due (backlog-in-days 5)
              'checklist '(("Focus and Tab" . #t) ("Text editing" . #t)
                           "Dropdowns and the calendar" "Drag and drop"
                           "Tests and screenshots")
              'description "A task manager that gathers the widgets the style \
                            system must cover: text fields, dropdowns, tables, \
                            chips, a calendar, dialogs and tooltips.")
   (add-task! "Threads spec: worker pool, jobs, parallel-for"
              'status 'doing
              'priority 'high
              'assignee "Pavel"
              'tags '("threads")
              'due (backlog-in-days 14)
              'description "Jobs on a pool of workers, results handed back to \
                            core1, pixmaps filled in parallel. Threads only \
                            when measured.")
   (add-task! "Style system: one look for windows, bars, menus and widgets"
              'priority 'high
              'tags '("style" "kit")
              'due (backlog-in-days 21)
              'checklist '("List every drawing procedure"
                           "Parts and derived styles" "Port Settings"
                           "Restyle Tasks under every style")
              'description "Styles change only the windows today. One look \
                            should reach the top bar, the taskbar, menus, \
                            toasts and every widget, and a derived style \
                            should take a few lines.")
   (add-task! "Persistence: keep tasks, windows and app state across restarts"
              'assignee "Pavel"
              'tags '("persistence")
              'description "No persistence yet: everything lives on the heap. \
                            fasl-write of app state is a natural first step.")
   (add-task! "GPU composer: per-window images composed on the GPU"
              'tags '("render" "gpu")
              'checklist '("Each window in its own image" "Compose on the CPU"
                           "Compose on the GPU"
                           "(set-compositor! 'gpu) at the REPL")
              'description "Every window drawn into an image of its own, only \
                            when it changes, and the images composed: on the \
                            CPU first, then on the GPU.")
   (add-task! "Inspector app: browse any live value"
              'assignee "Claude"
              'tags '("apps")
              'description "Click through records, hashtables, procedures and \
                            their sources, windows and processes.")
   (add-task! "REPL: selection and copy"
              'tags '("repl")
              'description "The transcript cannot be selected or copied yet. \
                            The kit's text editing could serve it.")
   (add-task! "Theme change takes 67 ms at 200%"
              'kind 'bug
              'priority 'high
              'assignee "Claude"
              'tags '("perf" "render")
              'due (backlog-in-days -2)
              'description "Every theme change paints the wallpaper again, so \
                            dragging a color slider in Settings shows about 15 \
                            frames a second at 200%.")
   (add-task! "Menus and toasts redraw the whole screen"
              'kind 'bug
              'tags '("perf" "render")
              'description "While a menu or a toast shows, every frame is the \
                            whole screen; their own extents would be enough.")
   (add-task! "Tiled windows redraw with the clock every second"
              'kind 'bug
              'priority 'low
              'tags '("perf")
              'description "Windows whose extent reaches into the top bar are \
                            drawn again with the clock: 30 tiled Life windows \
                            take 7.5 ms a second at 200%.")
   (add-task! "Fractal explorer"
              'priority 'low
              'tags '("apps" "threads")
              'description "Deep zoom into the Mandelbrot set on every core, \
                            refined progressively, with a flight mode and a \
                            Julia inset.")
   (add-task! "Smoke: stable fluids you push with the mouse"
              'priority 'low
              'tags '("apps" "threads")
              'description "A stable-fluids solver on all cores; drag to push \
                            the smoke around.")
   (add-task! "Galaxies on all cores"
              'priority 'low
              'tags '("apps" "threads")
              'description "Thousands of stars pulling at each other, the \
                            forces computed in parallel.")
   (add-task! "AI agent app that reads window contents"
              'tags '("apps")
              'description "An assistant in a window that reads what the other \
                            windows show and acts through the REPL.")
   (add-task! "Try the macOS and Windows libraries"
              'kind 'chore
              'priority 'low
              'tags '("portability")
              'description "Their names are in ffi.ss but have not been tried. \
                            macOS needs the loop on the process's first \
                            thread, which it already is.")
   (add-task! "Namespaces for apps"
              'priority 'low
              'tags '("repl")
              'description "Apps all share one environment. REPLs can be \
                            private or pure; apps could be kept apart the same \
                            way.")
   (add-task! "Namespaces for apps, again")
   (delete-task! 25)   ; a duplicate of TASK-24
   (add-task! "A text editor app"
              'priority 'low
              'tags '("apps")
              'description "Open, edit and save files in a window, on the \
                            kit's text area.")
   (add-task! "Proofread the README"
              'kind 'chore
              'priority 'low
              'assignee "Pavel"
              'tags '("docs")
              'description (backlog-file "README.md"))
   (add-task! "Read the widget kit through, comments first"
              'kind 'chore
              'priority 'low
              'tags '("kit" "docs")
              'description (backlog-file "schevana/kits/ui.sls"))
   (add-task! "Changelog: the backlog as one long paragraph"
              'kind 'chore
              'priority 'low
              'assignee "Claude"
              'tags '("docs")
              'description (backlog-paragraph))
   (add-task! "Find out what the pasted base64 is"
              'kind 'bug
              'tags '("perf")
              'description (backlog-blob))
   (add-task! "Each window drawn into an image of its own"
              'tags '("render")
              'description "A window draws into its own picture, only when it \
                            changes; a frame then composes the pictures, on \
                            the CPU, instead of drawing every window under its \
                            rectangle again.")
   (add-task! "Edit kit: text that costs nothing to type into"
              'status 'done
              'priority 'high
              'assignee "Claude"
              'tags '("kit" "perf")
              'description "Text editing is a kit of its own, and a text's \
                            rows are computed only as far as they show: a \
                            keystroke in 64k characters costs what one in an \
                            empty box does.")
   (add-task! "Task dependencies and a tree widget"
              'status 'doing
              'priority 'high
              'assignee "Claude"
              'tags '("apps" "kit")
              'due (backlog-in-days 3)
              'description "Tasks wait for other tasks, never in a cycle, and \
                            a Tree view shows what each one waits for, on a \
                            tree widget in the kit that a file browser or the \
                            Inspector can use too.")
   ;; what waits for what
   (set-task! 11 'blocked-by '(9))
   (set-task! 13 'blocked-by '(31 10))
   (set-task! 14 'blocked-by '(33))
   (set-task! 15 'blocked-by '(32))
   (set-task! 17 'blocked-by '(31))
   (set-task! 18 'blocked-by '(31))
   (set-task! 19 'blocked-by '(10))
   (set-task! 20 'blocked-by '(10))
   (set-task! 21 'blocked-by '(10))
   (set-task! 22 'blocked-by '(14))
   (set-task! 23 'blocked-by '(7))
   (set-task! 26 'blocked-by '(32))
   (set-task! 33 'blocked-by '(9))
   ;; the board in order: each task moved before another in its column
   (move-task! 16 'todo 11)
   (move-task! 31 'todo 14)
   (move-task! 22 'todo 15)
   (move-task! 26 'todo 23)
   (move-task! 33 'doing 10)))
