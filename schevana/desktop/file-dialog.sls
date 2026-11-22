;;; (schevana desktop file-dialog) — the desktop's file dialog: a window that
;;; picks a file for the window that asked, which waits on it (ui-open-modal).
;;;
;;;   (open-file-dialog parent "Load into /lab" "Load"
;;;                     (lambda (path) ...)
;;;                     'folder "~/code"
;;;                     'types '(("Scheme files" "ss" "sls" "scm")
;;;                              ("All files")))
;;;
;;; Across the top, Back, Forward and Up, the folder as crumbs (Home for
;;; your home) and a filter. Left, places (Home, Schevana's tree, your
;;; folder, the computer), past a line that drags; right, the folder's
;;; folders, then its files of the chosen type, by name, size or date. A
;;; click selects, a double click goes into a folder or picks a file.
;;; Under them the file's name, which takes a path too and suggests as you
;;; type, the types, Cancel and the action. Keys, with no field focused:
;;; arrows move, Return opens, Backspace goes up, Alt+Left and Alt+Right
;;; go back and forward, Alt+Up up, Ctrl+L to the name, Ctrl+H shows the
;;; hidden files (a dot first), Escape cancels; typing filters.

(library (schevana desktop file-dialog)
  (export
    file-dialog make-file-dialog file-dialog? file-dialog-parent
    file-dialog-on-pick file-dialog-on-cancel file-dialog-types file-dialog-ui
    file-dialog-folder file-dialog-folder-set! file-dialog-back
    file-dialog-back-set! file-dialog-forward file-dialog-forward-set!
    file-dialog-selected file-dialog-selected-set! file-dialog-name
    file-dialog-name-set! file-dialog-filter file-dialog-filter-set!
    file-dialog-type file-dialog-type-set! file-dialog-hidden?
    file-dialog-hidden?-set! file-dialog-sort file-dialog-sort-set!
    file-dialog-listing file-dialog-listing-set! file-dialog-memo
    file-dialog-memo-set! file-dialog-done? file-dialog-done?-set!
    file-dialog-entry make-file-dialog-entry file-dialog-entry?
    file-dialog-entry-name file-dialog-entry-path file-dialog-entry-dir?
    file-dialog-entry-size file-dialog-entry-changed file-dialog-join
    file-dialog-above file-dialog-home file-dialog-resolve file-dialog-clean
    file-dialog-crumbs file-dialog-size-label file-dialog-date-label
    file-dialog-size file-dialog-read file-dialog-entries file-dialog-shown
    file-dialog-go! file-dialog-show! file-dialog-back! file-dialog-forward!
    file-dialog-up! file-dialog-target file-dialog-file file-dialog-open!
    file-dialog-pick! file-dialog-cancel! file-dialog-closed!
    file-dialog-choices draw-file-dialog-icon draw-file-dialog-icon*
    draw-file-dialog-name draw-file-dialog-name* file-dialog-toolbar
    file-dialog-places file-dialog-columns file-dialog-list file-dialog-menu!
    file-dialog-footer file-dialog-draw file-dialog-key file-dialog-text
    open-file-dialog)
  (import (chezscheme)
          (only (schevana base) define-hook library-layer list-index plist-ref
                string-contains-ci? string-prefix? string-split string-suffix?)
          (only (schevana core) *schevana-root* close-window! current-window
                define-part font-line-height invalidate! text-width
                user-directory windows)
          (only (schevana kits text) text-widest)
          (only (schevana kits ui) ui-handlers ui-open-modal make-ui
                ui-table-page ui-table-step ui-end! ui-split ui-begin!
                ui-dropdown ui-label-size ui-dropdown-size ui-control-height
                ui-gap ui-open-menu! ui-draw-cell ui-table-room ui-table ui-pad
                ui-table-fit ui-nav ui-draw-surface ui-focus! ui-text-field
                ui-breadcrumbs ui-toolbar ui-button ui-text-box-size
                ui-button-size ui-draw-label ui-table-cell-inset ui-glyph-size
                ui-draw-glyph ui-forget! ui-month-names))

  (library-layer desktop)

  (define-record-type file-dialog
    (nongenerative schevana-file-dialog-1)
    (fields parent on-pick on-cancel types ui
            (mutable folder)
            (mutable back)       ; the folders before, the newest first
            (mutable forward)    ; and after, as Back left them
            (mutable selected)   ; the entry selected, or #f
            (mutable name)       ; the name field's text
            (mutable filter)     ; the filter's
            (mutable type)       ; which of types is shown
            (mutable hidden?)    ; whether the hidden files show
            (mutable sort)       ; (key . up|down)
            (mutable listing)    ; (folder hidden? . entries), the last read
            (mutable memo)       ; (key . value): the last suggestions
            (mutable done?)))    ; picked or cancelled: closing tells no more

  ;; A folder's entry: its name and path, whether it is a folder, and its
  ;; size (a file's) and when it changed, in seconds, or #f.
  (define-record-type file-dialog-entry
    (nongenerative schevana-file-dialog-entry-1)
    (fields name path dir? size changed))

  ;;; ------------------------------------------------------------------
  ;;; paths, pure

  (define (file-dialog-join folder name)
    (if (string=? folder "/")
        (string-append "/" name)
        (string-append folder "/" name)))

  (define (file-dialog-above folder)
    (let ([p (path-parent folder)]) (if (string=? p "") "/" p)))

  (define (file-dialog-home) (or (getenv "HOME") "/"))

  ;; text as a whole path: ~ and ~/x as your home's, x from folder (itself
  ;; from the current directory, if it is relative too); its . and .. worked
  ;; out, and no / at its end. Every folder the dialog shows is one.
  (define (file-dialog-resolve folder text)
    (let* ([home (file-dialog-home)]
           [base (if (string-prefix? "/" folder)
                     folder
                     (file-dialog-join (current-directory) folder))])
      (file-dialog-clean
       (cond [(string=? text "~") home]
             [(string-prefix? "~/" text)
              (string-append home (substring text 1 (string-length text)))]
             [(string-prefix? "/" text) text]
             [else (file-dialog-join base text)]))))

  ;; A whole path without its . and .., nor empty parts.
  (define (file-dialog-clean path)
    (let loop ([parts (string-split path #\/)] [acc '()])
      (cond [(null? parts)
             (if (null? acc)
                 "/"
                 (apply string-append
                        (map (lambda (s) (string-append "/" s))
                             (reverse acc))))]
            [(member (car parts) '("" ".")) (loop (cdr parts) acc)]
            [(string=? (car parts) "..")
             (loop (cdr parts) (if (pair? acc) (cdr acc) acc))]
            [else (loop (cdr parts) (cons (car parts) acc))])))

  ;; The folder as crumbs, ((label . path) ...) from the top: Home, if it
  ;; is in home, else the Computer, then each folder down to it.
  (define (file-dialog-crumbs folder home)
    (let-values ([(top rest)
                  (if (and (> (string-length home) 1)
                           (or (string=? folder home)
                               (string-prefix? (string-append home "/")
                                               folder)))
                      (values (cons "Home" home)
                              (substring folder (string-length home)
                                         (string-length folder)))
                      (values (cons "Computer" "/") folder))])
      (let loop ([names (remp (lambda (s) (string=? s ""))
                              (string-split rest #\/))]
                 [path (cdr top)] [acc (list top)])
        (if (null? names)
            (reverse acc)
            (let ([p (file-dialog-join path (car names))])
              (loop (cdr names) p (cons (cons (car names) p) acc)))))))

  ;; "512 bytes", "4.2 KB", "1.3 MB": a file's size as people read it.
  (define (file-dialog-size-label n)
    (let loop ([v n] [units '("bytes" "KB" "MB" "GB" "TB")])
      (cond [(and (< v 1000) (string=? (car units) "bytes"))
             (format "~a bytes" v)]
            [(or (< v 1000) (null? (cdr units)))
             (format "~a ~a" (/ (round (* v 10)) 10.0) (car units))]
            [else (loop (/ v 1000) (cdr units))])))

  ;; When a file changed, at the second secs, as people read it beside now:
  ;; "14:05" today, "Nov 5" this year, "Nov 5, 2024" before.
  (define (file-dialog-date-label secs now)
    (let ([d (time-utc->date (make-time 'time-utc 0 secs))]
          [n (time-utc->date (make-time 'time-utc 0 now))])
      (cond [(and (= (date-year d) (date-year n))
                  (= (date-month d) (date-month n))
                  (= (date-day d) (date-day n)))
             (format "~2,'0d:~2,'0d" (date-hour d) (date-minute d))]
            [(= (date-year d) (date-year n))
             (format "~a ~a" (vector-ref ui-month-names (- (date-month d) 1))
                     (date-day d))]
            [else (format "~a ~a, ~a" (vector-ref ui-month-names
                                                  (- (date-month d) 1))
                          (date-day d) (date-year d))])))

  ;;; ------------------------------------------------------------------
  ;;; the folder

  ;; A file's size: a regular file's, never opening anything else (a pipe
  ;; would wait for a writer).
  (define (file-dialog-size path)
    (guard (c [#t #f])
      (and (file-regular? path)
           (let* ([p (open-file-input-port path)] [n (port-length p)])
             (close-port p)
             n))))

  ;; The folder's entries, the hidden ones (a dot first) only with hidden?;
  ;; #f when it can't be read.
  (define (file-dialog-read folder hidden?)
    (guard (c [#t #f])
      (map (lambda (n)
             (let* ([path (file-dialog-join folder n)]
                    [dir? (file-directory? path)])
               (make-file-dialog-entry
                n path dir? (and (not dir?) (file-dialog-size path))
                (guard (c [#t #f])
                  (time-second (file-modification-time path))))))
           (filter (lambda (n) (or hidden? (not (string-prefix? "." n))))
                   (directory-list folder)))))

  ;; The folder's entries, read again only when it or hidden? changed.
  (define (file-dialog-entries d)
    (let ([l (file-dialog-listing d)] [f (file-dialog-folder d)]
          [h (file-dialog-hidden? d)])
      (if (and l (equal? (car l) f) (eq? (cadr l) h))
          (cddr l)
          (let ([es (file-dialog-read f h)])
            (file-dialog-listing-set! d (cons* f h es))
            es))))

  ;; What the list shows: the folders, then the files of the type shown,
  ;; that the filter leaves, as sorted. => #f when the folder can't be read
  (define (file-dialog-shown d)
    (let ([es (file-dialog-entries d)])
      (and es
           (let* ([q (file-dialog-filter d)]
                  [exts (cdr (list-ref (file-dialog-types d)
                                       (file-dialog-type d)))]
                  [s (file-dialog-sort d)] [key (car s)]
                  [less (lambda (a b)
                          (case key
                            [(size) (< (or (file-dialog-entry-size a) 0)
                                       (or (file-dialog-entry-size b) 0))]
                            [(changed) (< (or (file-dialog-entry-changed a) 0)
                                          (or (file-dialog-entry-changed b) 0))]
                            [else (string-ci<? (file-dialog-entry-name a)
                                               (file-dialog-entry-name b))]))])
             (sort (lambda (a b)
                     (let ([da (file-dialog-entry-dir? a)]
                           [db (file-dialog-entry-dir? b)])
                       (cond [(and da (not db)) #t]
                             [(and db (not da)) #f]
                             [(eq? (cdr s) 'up) (less a b)]
                             [else (less b a)])))
                   (filter (lambda (e)
                             (and (or (string=? q "")
                                      (string-contains-ci?
                                       (file-dialog-entry-name e) q))
                                  (or (file-dialog-entry-dir? e) (null? exts)
                                      (exists (lambda (x)
                                                (string-suffix?
                                                 (string-append "." x)
                                                 (file-dialog-entry-name e)))
                                              exts))))
                           es))))))

  ;;; ------------------------------------------------------------------
  ;;; going and picking

  (define (file-dialog-go! d folder)
    (unless (equal? folder (file-dialog-folder d))
      (file-dialog-back-set! d
                             (cons (file-dialog-folder d) (file-dialog-back d)))
      (file-dialog-forward-set! d '())
      (file-dialog-show! d folder)))

  ;; Shows folder, its list from the top, nothing selected or filtered.
  (define (file-dialog-show! d folder)
    (let ([ui (file-dialog-ui d)])
      (file-dialog-folder-set! d folder)
      (file-dialog-selected-set! d #f)
      (file-dialog-filter-set! d "")
      (ui-forget! ui (list '(file-dialog list) 'body))))

  (define (file-dialog-back! d)
    (let ([b (file-dialog-back d)])
      (when (pair? b)
        (file-dialog-forward-set! d (cons (file-dialog-folder d)
                                          (file-dialog-forward d)))
        (file-dialog-back-set! d (cdr b))
        (file-dialog-show! d (car b)))))

  (define (file-dialog-forward! d)
    (let ([f (file-dialog-forward d)])
      (when (pair? f)
        (file-dialog-back-set! d (cons (file-dialog-folder d)
                                       (file-dialog-back d)))
        (file-dialog-forward-set! d (cdr f))
        (file-dialog-show! d (car f)))))

  (define (file-dialog-up! d)
    (file-dialog-go! d (file-dialog-above (file-dialog-folder d))))

  ;; What the name names, as a path, or else the entry selected's.
  (define (file-dialog-target d)
    (let ([n (file-dialog-name d)] [e (file-dialog-selected d)])
      (cond [(not (string=? n ""))
             (file-dialog-resolve (file-dialog-folder d) n)]
            [e (file-dialog-entry-path e)]
            [else #f])))

  ;; The file to pick: the target, when it is a file that is there.
  (define (file-dialog-file d)
    (let ([p (file-dialog-target d)])
      (and p (file-exists? p) (not (file-directory? p)) p)))

  ;; Return, or a double click: a folder named or selected is gone into, a
  ;; file picked.
  (define (file-dialog-open! d)
    (let ([p (file-dialog-target d)])
      (cond [(and p (file-directory? p))
             (file-dialog-name-set! d "")
             (file-dialog-go! d p)]
            [(file-dialog-file d) => (lambda (f) (file-dialog-pick! d f))])))

  ;; The dialog closes, then the window that waited gets the path.
  (define (file-dialog-pick! d path)
    (file-dialog-done?-set! d #t)
    (close-window! (current-window))
    (let ([parent (file-dialog-parent d)])
      (when (memq parent (windows))
        (parameterize ([current-window parent])
          ((file-dialog-on-pick d) path))
        (invalidate! parent))))

  (define (file-dialog-cancel! d)
    (close-window! (current-window)))

  ;; Closed by Cancel, Escape or its frame: the caller's on-cancel, once.
  (define (file-dialog-closed! d)
    (unless (file-dialog-done? d)
      (file-dialog-done?-set! d #t)
      (let ([parent (file-dialog-parent d)])
        (when (and (file-dialog-on-cancel d) (memq parent (windows)))
          (parameterize ([current-window parent])
            ((file-dialog-on-cancel d)))))))

  ;; What the name may go on to: the entries of its folder that start with
  ;; its last part, folders with a / after them, then the files the type
  ;; shows.
  (define (file-dialog-choices d typed)
    (let* ([cut (let loop ([i (string-length typed)])
                  (cond [(= i 0) 0]
                        [(char=? (string-ref typed (- i 1)) #\/) i]
                        [else (loop (- i 1))]))]
           [shown (substring typed 0 cut)]
           [part (substring typed cut (string-length typed))]
           [dir (if (string=? shown "")
                    (file-dialog-folder d)
                    (file-dialog-resolve (file-dialog-folder d) shown))]
           [exts (cdr (list-ref (file-dialog-types d) (file-dialog-type d)))])
      (guard (c [#t '()])
        (let* ([names (sort string<? (directory-list dir))]
               [fits (filter (lambda (n)
                               (and (string-prefix? part n)
                                    (not (string-prefix? "." n))))
                             names)]
               [folder? (lambda (n)
                          (file-directory? (file-dialog-join dir n)))])
          (map (lambda (n) (string-append shown n (if (folder? n) "/" "")))
               (append (filter folder? fits)
                       (filter (lambda (n)
                                 (and (not (folder? n))
                                      (or (null? exts)
                                          (exists (lambda (x)
                                                    (string-suffix?
                                                     (string-append "." x) n))
                                                  exts))))
                               fits)))))))

  ;;; ------------------------------------------------------------------
  ;;; drawing

  ;; An entry's icon or a place's, s square: a folder's or a file's, home,
  ;; the tree, the computer.
  (define-part (draw-file-dialog-icon what x y s flags)
    (let-values ([(glyph ink)
                  (case what
                    [(folder) (values 'folder 'accent)]
                    [(home) (values 'home 'accent)]
                    [(tree) (values 'folder 'accent-2)]
                    [(computer) (values 'drive 'text-dim)]
                    [else (values 'file 'text-dim)])])
      (ui-draw-glyph x y s s (list (cons 'ink ink)) glyph)))

  ;; The list's first cell: the icon, then the name.
  (define-part (draw-file-dialog-name e x y w h flags)
    (let* ([g (ui-glyph-size)] [in (ui-table-cell-inset)])
      (draw-file-dialog-icon (if (file-dialog-entry-dir? e) 'folder 'file)
                             (+ x in) (+ y (/ (- h g) 2)) g flags)
      (ui-draw-label (+ x in g 8) y (max 0 (- w in g 8 in)) h flags
                     (file-dialog-entry-name e))))

  (define (file-dialog-toolbar d w)
    (let*-values ([(ui) (file-dialog-ui d)]
                  [(bw bh) (ui-button-size #f 'chevron-left)]
                  [(fw fh) (ui-text-box-size '(search) 0 1)]
                  [(crumbs) (file-dialog-crumbs (file-dialog-folder d)
                                                (file-dialog-home))])
      (define (step id glyph tip go! off?)
        (list bw bh
              (lambda (x y w h)
                (ui-button ui (list 'file-dialog id) x y w h #f
                           (lambda () (go! d))
                           'glyph glyph 'quiet #t 'disabled off? 'tip tip))))
      (ui-toolbar
       0 0 w
       (list (step 'back 'chevron-left "Back  Alt+Left" file-dialog-back!
                   (null? (file-dialog-back d)))
             (step 'forward 'chevron-right "Forward  Alt+Right"
                   file-dialog-forward! (null? (file-dialog-forward d)))
             (step 'up 'chevron-up "Up  Backspace" file-dialog-up!
                   (string=? (file-dialog-folder d) "/"))
             (list #f bh
                   (lambda (x y w h)
                     (ui-breadcrumbs ui '(file-dialog crumbs) x y w h
                                     (map car crumbs)
                                     (lambda (i)
                                       (file-dialog-go!
                                        d (cdr (list-ref crumbs i)))))))
             (list (max 160 (round (* 12 (font-line-height 'ui)))) fh
                   (lambda (x y w h)
                     (ui-text-field ui '(file-dialog filter) x y w h
                                    (file-dialog-filter d)
                                    (lambda (s) (file-dialog-filter-set! d s))
                                    'search #t 'placeholder "Filter"
                                    'on-enter (lambda () (ui-focus! ui #f))))))
       'flex '(150 . 100000))))

  ;; The places, there to go to: those that are there.
  (define (file-dialog-places d x y w h)
    (let ([ui (file-dialog-ui d)])
      (ui-draw-surface x y w h '(nav))
      (ui-nav ui '(file-dialog place) (+ x 10) (+ y 12) (- w 20)
              (filter (lambda (p) (file-directory? (car p)))
                      (list (list (file-dialog-home) "Home"
                                  (lambda (x y s f)
                                    (draw-file-dialog-icon 'home x y s f)))
                            (list (file-dialog-resolve (current-directory)
                                                       *schevana-root*)
                                  "Schevana"
                                  (lambda (x y s f)
                                    (draw-file-dialog-icon 'tree x y s f)))
                            (list user-directory "Your folder"
                                  (lambda (x y s f)
                                    (draw-file-dialog-icon 'folder x y s f)))
                            (list "/" "Computer"
                                  (lambda (x y s f)
                                    (draw-file-dialog-icon 'computer x y s
                                                           f)))))
              (file-dialog-folder d)
              (lambda (p) (file-dialog-go! d p)))))

  (define (file-dialog-columns room)
    (let ([in (* 2 (ui-table-cell-inset))])
      (ui-table-fit room
                    `((name "Name" #f)
                      (size "Size" ,(round (+ in 4 (text-widest
                                                    '("999 bytes" "999.9 KB")
                                                    'ui)))
                            right)
                      (changed "Modified"
                               ,(round (+ in (text-width "Nov 30, 2026" 'ui)))))
                    '(size changed) (* 10 (font-line-height 'ui)))))

  ;; The folder's list, or why there is none.
  (define (file-dialog-list d x y w h)
    (let* ([ui (file-dialog-ui d)] [pad (ui-pad)]
           [shown (file-dialog-shown d)]
           [lx (+ x pad)] [lw (- w pad pad)])
      (ui-draw-surface lx (+ y pad) lw (- h pad pad) '(well))
      (if (not shown)
          (ui-draw-label (+ lx 16) (+ y pad 16) (- lw 32) 0 '(hint wrap)
                         "This folder can't be read.")
          (ui-table ui '(file-dialog list) lx (+ y pad 4) lw (- h pad pad 8)
                    (file-dialog-columns (ui-table-room lw))
                    shown (file-dialog-selected d)
                    (lambda (e)
                      (file-dialog-selected-set! d e)
                      (file-dialog-name-set!
                       d (if (file-dialog-entry-dir? e)
                             ""
                             (file-dialog-entry-name e))))
                    (lambda (e key cx cy cw ch flags)
                      (case key
                        [(name) (draw-file-dialog-name e cx cy cw ch flags)]
                        [(size)
                         (ui-draw-cell cx cy cw ch flags
                                       (let ([n (file-dialog-entry-size e)])
                                         (if n (file-dialog-size-label n) "")))]
                        [else
                         (ui-draw-cell cx cy cw ch flags
                                       (let ([t (file-dialog-entry-changed e)])
                                         (if t
                                             (file-dialog-date-label
                                              t (time-second (current-time)))
                                             "")))]))
                    'sort (file-dialog-sort d)
                    'on-sort (lambda (key)
                               (let ([s (file-dialog-sort d)])
                                 (file-dialog-sort-set!
                                  d (cons key (if (and (eq? (car s) key)
                                                       (eq? (cdr s) 'up))
                                                  'down
                                                  'up)))))
                    'on-open (lambda (e) (file-dialog-open! d))
                    'on-menu (lambda (e mx my) (file-dialog-menu! d mx my))
                    'reveal #t))))

  (define (file-dialog-menu! d x y)
    (ui-open-menu! (file-dialog-ui d) x y
                   (list (cons (if (file-dialog-hidden? d)
                                   "Hide hidden files  Ctrl+H"
                                   "Show hidden files  Ctrl+H")
                               (lambda () (file-dialog-hidden?-set!
                                           d (not (file-dialog-hidden? d)))))
                         (cons "Up  Backspace" (lambda ()
                                                 (file-dialog-up! d))))))

  ;; The name, the types, Cancel and the action, in a row from (x, y).
  (define (file-dialog-footer d action x y w h)
    (let*-values ([(ui) (file-dialog-ui d)] [(pad gap) (values (ui-pad)
                                                               (ui-gap))]
                  [(ch) (ui-control-height)] [(cy) (+ y (/ (- h ch) 2))]
                  [(types) (file-dialog-types d)]
                  [(tw th) (ui-dropdown-size (map car types))]
                  [(cw chh) (ui-button-size "Cancel" #f)]
                  [(aw ah) (ui-button-size action #f)]
                  [(aw) (max aw 88)] [(cw) (max cw 88)]
                  [(bx) (- (+ x w) pad aw)] [(cx) (- bx gap cw)]
                  [(tx) (- cx gap gap tw)]
                  [(lw lh) (ui-label-size '(dim) "Name" 0)]
                  [(fx) (+ x pad lw gap)])
      (ui-draw-surface x y w h '(footer))
      (ui-draw-label (+ x pad) cy lw ch '(dim) "Name")
      (ui-text-field ui '(file-dialog name) fx cy (max 0 (- tx gap fx)) ch
                     (file-dialog-name d)
                     (lambda (s) (file-dialog-name-set! d s))
                     'placeholder "A file's name, or a path"
                     'on-enter (lambda () (file-dialog-open! d))
                     'suggest (lambda (typed)
                                (let ([m (file-dialog-memo d)])
                                  (if (equal? (car m) typed)
                                      (cdr m)
                                      (let ([l (file-dialog-choices d typed)])
                                        (file-dialog-memo-set!
                                         d (cons typed l))
                                        l)))))
      (ui-dropdown ui '(file-dialog type) tx cy tw ch
                   (map (lambda (t i) (cons (car t) i)) types
                        (iota (length types)))
                   (file-dialog-type d)
                   (lambda (i) (file-dialog-type-set! d i)))
      (ui-button ui '(file-dialog cancel) cx cy cw ch "Cancel"
                 (lambda () (file-dialog-cancel! d)) 'tip "Escape")
      (ui-button ui '(file-dialog pick) bx cy aw ch action
                 (lambda () (let ([f (file-dialog-file d)])
                              (when f (file-dialog-pick! d f))))
                 'primary #t 'disabled (not (file-dialog-file d)))))

  (define (file-dialog-draw d action w h)
    (let* ([ui (file-dialog-ui d)]
           [fh (+ (ui-control-height) (* 2 (ui-pad)))])
      (ui-begin! ui)
      (ui-draw-surface 0 0 w h '(page))
      (let* ([top (file-dialog-toolbar d w)]
             [bh (max 0 (- h top fh))]
             [sw (ui-split ui '(file-dialog split) 0 top w bh
                           (max 150 (round (* 12 (font-line-height 'ui))))
                           120 280)])
        (file-dialog-places d 0 top sw bh)
        (file-dialog-list d sw top (- w sw) bh)
        (file-dialog-footer d action 0 (+ top bh) w fh))
      (ui-end! ui w h)))

  ;;; ------------------------------------------------------------------
  ;;; keys

  ;; With no field focused; true when it acted.
  (define (file-dialog-key d key mods)
    (let ([ui (file-dialog-ui d)])
      (cond
        [(equal? mods '(alt))
         (case key
           [(left) (file-dialog-back! d) #t]
           [(right) (file-dialog-forward! d) #t]
           [(up) (file-dialog-up! d) #t]
           [else #f])]
        [(and (equal? mods '(ctrl)) (eqv? key #\l))
         (ui-focus! ui '(file-dialog name) #t)
         #t]
        [(and (equal? mods '(ctrl)) (eqv? key #\h))
         (file-dialog-hidden?-set! d (not (file-dialog-hidden? d)))
         #t]
        [(pair? mods) #f]
        [(eq? key 'escape) (file-dialog-cancel! d) #t]
        [(eq? key 'return) (file-dialog-open! d) #t]
        [(eq? key 'backspace) (file-dialog-up! d) #t]
        [else
         (let* ([shown (or (file-dialog-shown d) '())]
                [i (list-index (lambda (e) (eq? e (file-dialog-selected d)))
                               shown)]
                [j (ui-table-step i (length shown)
                                  (ui-table-page ui '(file-dialog list)) key)])
           (and j
                (let ([e (list-ref shown j)])
                  (file-dialog-selected-set! d e)
                  (file-dialog-name-set! d (if (file-dialog-entry-dir? e)
                                               ""
                                               (file-dialog-entry-name e)))
                  #t)))])))

  ;; Typing with no field focused filters.
  (define (file-dialog-text d str)
    (let ([ui (file-dialog-ui d)])
      (file-dialog-filter-set! d (string-append (file-dialog-filter d) str))
      (ui-focus! ui '(file-dialog filter))
      #t))

  ;;; ------------------------------------------------------------------
  ;;; the window

  ;; Opens the dialog over parent, which waits on it, its title title and
  ;; its action's button action; a file picked calls (on-pick path) as
  ;; parent's handler. opts: 'folder (where it opens: the current
  ;; directory's by default), 'types (((label ext ...) ...), the first
  ;; shown; one with no ext shows every file: All files by default), and
  ;; 'on-cancel (a thunk). => the dialog's window
  (define (open-file-dialog parent title action on-pick . opts)
    (let* ([ui (make-ui)]
           [folder (file-dialog-resolve (current-directory)
                                        (plist-ref opts 'folder
                                                   (current-directory)))]
           [d (make-file-dialog parent on-pick (plist-ref opts 'on-cancel #f)
                                (plist-ref opts 'types '(("All files")))
                                ui (if (file-directory? folder)
                                       folder
                                       (file-dialog-home))
                                '() '() #f "" "" 0 #f '(name . up) #f
                                (cons #f '()) #f)]
           [lh (font-line-height 'ui)])
      (apply ui-open-modal parent title
             (max 720 (round (* 50 lh))) (max 460 (round (* 31 lh)))
             'min-size (cons (round (* 34 lh)) (round (* 20 lh)))
             'app #f
             'state d
             'draw (lambda (win w h) (file-dialog-draw d action w h))
             'close (lambda (win) (file-dialog-closed! d))
             (ui-handlers ui
                          'key (lambda (win key mods)
                                 (file-dialog-key d key mods))
                          'text (lambda (win str) (file-dialog-text d str)))))))
