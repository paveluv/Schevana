;;; apps/envs.ss — Environments: the tree of environments (services/env.ss),
;;; what each holds, and what can be done with it.
;;;
;;; Left, the tree (the line beside it drags, and a double click puts it
;;; back): each environment's icon and name, its kind, how many names it
;;; was shared and holds of its own, and its thread's jobs.
;;; Right, the one selected: what it is (its kind, base, parent and
;;; children, what it forks, its thread), then its names: those shared
;;; with it, each with the parent's name it forwards to, whether its set!
;;; goes through a setter and where it is bound; or its own. For an app's
;;; sandbox, the bundles it requests, as each stands, and each name's;
;;; /apps lists every bundle (services/grant.ss). The toolbar
;;; acts on the one selected, as the menu of a right press on a row does:
;;;   Fork…    a child of a kind its fork makes, named, shared names
;;;   REPL     a REPL in it (Return, a double click)
;;;   Share…   more of its parent's names
;;;   Load…    a file evaluated in it (env-load), picked in the desktop's
;;;            file dialog, which Environments waits on
;;;   Drop…    it, its children and their threads
;;; The pool's threads, /worklets', are set here too. Keys, with no field
;;; focused: arrows move in the tree, Return opens a REPL, F forks, /
;;; filters, Delete drops.

(define-record-type envs-view
  (nongenerative schevana-envs-view-2)
  (fields ui
          (mutable selected)     ; the environment shown
          (mutable query)        ; the tree's filter
          (mutable names)        ; shared or own: what the names show
          (mutable names-query)  ; their filter
          (mutable sheet)        ; #f, or fork, share, load or drop
          (mutable kind)         ; the fork's kind
          (mutable name)         ; its name, as typed
          (mutable shares)       ; the fork's or share's chips
          (mutable draft)        ; the chip being typed
          (mutable folder)       ; where Load… last picked a file, or #f
          (mutable repl?)        ; a REPL in the child, once forked (off
                                 ; each time the sheet opens)
          (mutable error)        ; what the sheet's last try raised, or #f
          (mutable memo)         ; (key . value): the last suggestions
          facts))                ; env -> (ms shared own), a second's

;;; ------------------------------------------------------------------
;;; what an environment is

(define (envs-label e)
  (if (env-parent e) (symbol->string (env-name e)) "/"))

;; What the kind means, under its title.
(define (envs-kind-doc e)
  (case (env-kind e)
    [(root) "The world itself: the folders' names, Chez's, and what the \
             core gives it (/core1). What is defined here changes the \
             running world; the core's own are redefined in /core1."]
    [(worklets) "Where the worklets live (define-worklet); the pool's \
                 threads run them."]
    [(#f) (format "Made by code (env-child): ~a, and what is shared with it"
                  (case (env-base e)
                    [(core) "Scheme's pure core"]
                    [(confined) "what is always safe"]
                    [else "all of Chez"]))]
    [else (env-kind-ref (env-kind e) 'doc "")]))

(define (envs-base-words e)
  (case (env-base e)
    [(chez) "chez: all of Chez Scheme"]
    [(confined) "confined: what is always safe, without files, C or \
                 threads; the console its log"]
    [(core) "core: the pure part of Scheme, without files, C or threads"]
    [else "The world's own"]))

;; The names e was shared and holds of its own, and those of the world's
;; its next sync brings, kept for a second: (values shared own new), own #f
;; for a vat's sandbox, its thread's to read.
(define (envs-facts v e)
  (let ([f (hashtable-ref (envs-view-facts v) e #f)])
    (if (and f (< (- (now-ms) (car f)) 1000))
        (apply values (cdr f))
        (let* ([vat? (and (vat-of e) #t)]
               [shared (env-shared-names e (not vat?))]
               [own (and (not vat?) (env-own-names e))]
               [new (env-unsynced e)])
          (hashtable-set! (envs-view-facts v) e
                          (list (now-ms) shared own new))
          (values shared own new)))))

;; Where a name e was shared is bound: the path, as env-holder finds it,
;; but in a vat's sandbox from its parent on.
(define (envs-holder e name target)
  (let-values ([(h n) (if (vat-of e)
                          (env-holder (env-parent e) target)
                          (env-holder e name))])
    (env-path h)))

;; Every environment, depth first.
(define (envs-all)
  (let walk ([e (env-root)])
    (cons e (apply append (map walk (env-children e))))))

;;; ------------------------------------------------------------------
;;; what can be done with it

;; Why what (fork, repl, share, load, drop) is not for e, or #f when it
;; is.
(define (envs-why-not e what)
  (let ([vat? (and (vat-of e) #t)] [kind (env-kind e)])
    (case what
      [(fork) (and (null? (env-forks e))
                   (format "~a forks nothing: the world, world namespaces \
                            and sandboxes fork" (env-path e)))]
      [(repl) (and (eq? kind 'worklets)
                   "No REPL in /worklets: the pool's threads run there")]
      [(share load)
       (cond [(eq? kind 'worklets)
              "/worklets holds worklets only: define-worklet puts them there"]
             [(and (eq? what 'share) (memq kind '(apps app)))
              "An app holds the bundles it is allowed, and no more"]
             [(and (eq? what 'share) (memq kind '(core0 recorder core1)))
              "It names nothing of the world's: it sits below it"]
             [vat? "Its sandbox is its vat's: share and load before its \
                    thread starts"]
             [(and (eq? what 'share) (not (env-parent e)))
              "The world has no parent to share with it"]
             [else #f])]
      [(drop) (cond [(not (env-parent e)) "The world is not dropped"]
                    [(eq? kind 'worklets)
                     "/worklets is not dropped: the worklets live there"]
                    [(env-kind-ref kind 'kept #f)
                     => (lambda (why)
                          (format "~a is not dropped: ~a" (env-path e) why))]
                    [(eq? kind 'app)
                     "An app's sandbox goes with the app: it is made again \
                      as the app loads"]
                    [else #f])])))

;; The actions on e: ((what label glyph tip) ...), in the toolbar's order.
(define envs-actions
  '((fork "Fork…" plus "A child of a kind this environment forks  F")
    (repl "REPL" prompt "A REPL in this environment  Return")
    (share "Share…" #f "More of its parent's names, shared with it")
    (load "Load…" #f "A file's forms, evaluated in it")
    (drop "Drop…" #f "It, its children and their threads  Delete")))

(define (envs-act! v what)
  (let ([e (envs-view-selected v)])
    (unless (envs-why-not e what)
      (case what
        [(repl) (repl e)]
        [(fork) (envs-open-fork! v (car (env-forks e)))]
        [(load) (envs-open-load! v)]
        [(share) (envs-open-share! v)]
        [else (envs-open-sheet! v what)]))))

;; The share dialog, over Environments, for more of the parent's names.
(define (envs-open-share! v)
  (let* ([e (envs-view-selected v)] [p (env-parent e)])
    (envs-open-picker!
     (format "Share with ~a" (env-path e)) p e "Share" '()
     (lambda (picked)
       (let-values ([(shares setters) (envs-picked-shares picked)])
         (env-shares-check 'share p shares setters)
         (env-share! e shares)
         (for-each (lambda (s) (env-share-setter! e (car s) (cdr s)))
                   setters)
         (hashtable-delete! (envs-view-facts v) e))))))

;; The file dialog, over Environments, for a file to load into the one
;; selected, where the last was picked.
(define (envs-open-load! v)
  (let ([e (envs-view-selected v)])
    (open-file-dialog (current-window) (format "Load into ~a" (env-path e))
                      "Load"
                      (lambda (path)
                        (envs-view-folder-set! v (path-parent path))
                        (envs-load! v e path))
                      'folder (or (envs-view-folder v) (current-directory))
                      'types '(("Scheme files" "ss" "sls" "scm")
                               ("All files")))))

(define (envs-open-sheet! v what)
  (envs-view-sheet-set! v what)
  (envs-view-shares-set! v '())
  (envs-view-draft-set! v "")
  (envs-view-error-set! v #f)
  (ui-focus! (envs-view-ui v)
             (case what
               [else #f])))

(define (envs-open-fork! v kind)
  (envs-open-sheet! v 'fork)
  (envs-view-kind-set! v kind)
  (envs-view-name-set! v "")
  (envs-view-repl?-set! v #f)
  (ui-focus! (envs-view-ui v) '(envs-sheet name)))

;; value-of's value, kept while key stays the same: what a field suggests,
;; asked at every draw.
(define (envs-memo v key value-of)
  (let ([m (envs-view-memo v)])
    (if (equal? (car m) key)
        (cdr m)
        (let ([value (value-of)])
          (envs-view-memo-set! v (cons key value))
          value))))

(define (envs-select! v e)
  (envs-view-selected-set! v e)
  (envs-view-names-query-set! v "")
  (ui-forget! (envs-view-ui v) 'inspector))

;; A share as typed: "name", "name as alias", either then "via setter".
;; => (values share setter): share a name or (alias . name), setter #f or
;; a name; #f when it reads as none of these.
(define (envs-share-words text)
  (let ([words (remp (lambda (w) (string=? w ""))
                     (string-split text #\space))])
    (define (sym s) (string->symbol s))
    (cond
      [(= (length words) 1) (values (sym (car words)) #f)]
      [(and (= (length words) 3) (string=? (cadr words) "as"))
       (values (cons (sym (caddr words)) (sym (car words))) #f)]
      [(and (= (length words) 3) (string=? (cadr words) "via"))
       (values (sym (car words)) (sym (caddr words)))]
      [(and (= (length words) 5) (string=? (cadr words) "as")
            (string=? (cadddr words) "via"))
       (values (cons (sym (caddr words)) (sym (car words)))
               (sym (list-ref words 4)))]
      [else (values #f #f)])))

;; The chips, and the draft being typed, as fork and env-share! take them:
;; (values shares setters).
(define (envs-sheet-shares v)
  (envs-shares (append (envs-view-shares v)
                       (let ([d (envs-trim (envs-view-draft v))])
                         (if (string=? d "") '() (list d))))))

(define (envs-shares chips)
  (let loop ([cs chips] [shares '()] [setters '()])
    (if (null? cs)
        (values (reverse shares) (reverse setters))
        (let-values ([(share setter) (envs-share-words (car cs))])
          (cond
            [(not share)
             (errorf 'share "~s reads as no share: a name, “name as alias”, \
                             either then “via setter”" (car cs))]
            [setter (loop (cdr cs) shares (cons (cons share setter) setters))]
            [else (loop (cdr cs) (cons share shares) setters)])))))

;; The fork sheet's Fork: a child of the selected environment, through
;; the same rules its own fork keeps.
(define (envs-fork! v)
  (let ([e (envs-view-selected v)] [kind (envs-view-kind v)]
        [typed (envs-trim (envs-view-name v))])
    (guard (c [#t (envs-view-error-set! v (condition->string c))])
      (let-values ([(shares setters) (envs-sheet-shares v)])
        (let ([c (apply env-fork e kind
                        (append (if (string=? typed "")
                                    '()
                                    (list 'name (string->symbol typed)))
                                (list 'share shares 'setters setters)))])
          (envs-view-sheet-set! v #f)
          (envs-select! v c)
          (when (and (envs-view-repl? v) (not (envs-why-not c 'repl)))
            (repl c)))))))

;; The file's forms evaluated in e, in a process; a toast says how it
;; went.
(define (envs-load! v e path)
  (spawn "load"
         (lambda () (env-load e path))
         (lambda (status value)
           (hashtable-delete! (envs-view-facts v) e)
           (case status
             [(error) (report-error! 'env-load value)]
             [(killed) (notify (format "Loading ~a stopped" path))]
             [else (notify (format "Loaded ~a into ~a" path
                                   (env-path e)))]))))

(define (envs-drop! v)
  (let ([e (envs-view-selected v)])
    (envs-view-sheet-set! v #f)
    (envs-select! v (env-parent e))
    (vat-drop-env! e)))

(define (envs-trim s)
  (let loop ([a 0] [b (string-length s)])
    (cond [(and (< a b) (char-whitespace? (string-ref s a))) (loop (+ a 1) b)]
          [(and (< a b) (char-whitespace? (string-ref s (- b 1))))
           (loop a (- b 1))]
          [else (substring s a b)])))

;;; ------------------------------------------------------------------
;;; drawing: the icons and the tree's cells

(define (envs-draw-icon e x y s flags)
  (ui-draw-env-icon x y s flags (vat-env-kind e)))

;; The tree's first cell: the icon under the heading's first letter, then
;; the name.
(define (envs-draw-name-cell e x y w h flags)
  (let* ([gs (ui-glyph-size)] [in (ui-table-cell-inset)] [gap 6])
    (envs-draw-icon e (+ x in) (+ y (/ (- h gs) 2)) gs '())
    (ui-draw-label (+ x in gs gap) y (max 0 (- w in gs gap)) h flags
                   (envs-label e))))

;; The inspector's head: a big icon, the name, the path and kind.
(define (envs-draw-head e x y w)
  (let* ([s (* 2 (ui-glyph-size))] [hh (font-line-height 'heading)]
         [tx (+ x s 12)])
    (envs-draw-icon e x (+ y 2) s '())
    (ui-draw-label tx y (- w s 12) hh '(heading) (envs-label e))
    (ui-draw-label tx (+ y hh 2) (- w s 12) (font-line-height 'ui-small)
                   '(hint)
                   (if (env-parent e)
                       (format "~a  ·  ~a" (env-path e) (env-title e))
                       (env-title e)))
    (+ y (max s (+ hh 2 (font-line-height 'ui-small))))))

;;; ------------------------------------------------------------------
;;; the tree

;; The tree's columns in room: the kind as wide as the widest title, the
;; counts as their headings, the environment the rest; as the room runs
;; out, Jobs, Own, Shared and Kind leave, in that order.
(define (envs-columns room)
  (let* ([in (* 2 (ui-table-cell-inset))]
         [kw (exact (ceiling (+ in 4 (text-widest
                                      (map env-kind-title
                                           (cons* 'root 'worklets (env-kinds)))
                                      'ui))))]
         ;; a heading keeps room for a sort mark
         [nw (exact (ceiling (+ in (ui-small-glyph-size) 4
                                (text-widest '("Shared" "Own" "Jobs")
                                             'ui-small))))])
    (ui-table-fit room
                  `((env "Environment" #f)
                    (kind "Kind" ,kw)
                    (shared "Shared" ,nw right
                            "Names its parent shared with it")
                    (own "Own" ,nw right "Names it defined itself")
                    (jobs "Jobs" ,nw right
                          "Its thread's jobs, waiting or running"))
                  '(jobs own shared kind)
                  (* 9 (font-line-height 'ui)))))

(define (envs-matches? v e)
  (let ([q (envs-trim (envs-view-query v))])
    (or (string=? q "")
        (string-contains-ci? (env-path e) q)
        (string-contains-ci? (env-title e) q))))

(define (envs-tree v x y w h)
  (let ([ui (envs-view-ui v)] [pad (ui-pad)])
    (ui-draw-surface (+ x pad) (+ y pad) (- w pad pad) (- h pad pad) '(well))
    (ui-tree ui 'tree (+ x pad) (+ y pad 4) (- w pad pad) (- h pad pad 8)
             (envs-columns (ui-table-room (- w pad pad)))
             (list (env-root)) env-children (envs-view-selected v)
             (lambda (e) (envs-select! v e))
             (lambda (e key cx cy cw ch flags)
               (if (eq? key 'env)
                   (envs-draw-name-cell e cx cy cw ch flags)
                   (ui-draw-cell cx cy cw ch flags (envs-cell-text v e key))))
             'expanded #t 'generation (env-generation)
             'dim (lambda (e) (not (envs-matches? v e)))
             'on-open (lambda (e) (envs-act! v 'repl))
             'on-menu (lambda (e mx my)
                        (envs-select! v e)
                        (envs-menu! v mx my))
             'tip (lambda (e cw) (env-path e)))))

(define (envs-cell-text v e key)
  (case key
    [(kind) (env-title e)]
    [(shared own)
     (let-values ([(shared own new) (envs-facts v e)])
       (let ([l (if (eq? key 'shared) shared own)])
         (cond [(and (eq? key 'shared) (not (env-parent e))) ""]
               [l (number->string (length l))]
               [else "—"])))]
    [(jobs) (let ([vat (vat-of e)])
              (if vat (number->string (length (vat-jobs-of vat))) ""))]
    [else ""]))

;; The menu of a right press: what can be done with the one selected.
(define (envs-menu! v x y)
  (let ([e (envs-view-selected v)])
    (ui-open-menu! (envs-view-ui v) x y
                   (filter-map (lambda (a)
                                 (and (not (envs-why-not e (car a)))
                                      (cons (cadr a)
                                            (lambda () (envs-act! v (car a))))))
                               envs-actions))))

;;; ------------------------------------------------------------------
;;; the inspector

;; The selected environment's facts, as form rows.
(define (envs-fact-rows v e)
  (let* ([ui (envs-view-ui v)] [ch (ui-control-height)]
         [vat (vat-of e)]
         [chips-row
          (lambda (label key labels press . opts)
            (list label
                  (lambda (w) (ui-chips-height w labels #f #f))
                  (lambda (x y w)
                    (apply ui-chips ui (list 'envs key) x y w labels press
                           opts))))]
         [top (/ (- ch (font-line-height 'ui)) 2)]   ; a line in a control
         [words-row (lambda (label words . opts)
                      (cons* label
                             (lambda (w)
                               (let-values ([(lw lh) (ui-label-size
                                                      '(wrap) words w)])
                                 (max ch (+ top lh))))
                             (lambda (x y w)
                               (ui-draw-label x (+ y top) w 0 '(wrap) words))
                             opts))]
         [children (env-children e)] [forks (env-forks e)])
    (append
     (list (words-row "Kind" (env-title e) 'hint (envs-kind-doc e))
           (words-row "Base" (envs-base-words e)))
     (if (env-parent e)
         (list (chips-row "Parent" 'parent (list (envs-label (env-parent e)))
                          (lambda (i) (envs-select! v (env-parent e)))
                          'tip (lambda (i) (env-path (env-parent e)))))
         '())
     (list (chips-row "Children" 'children (map envs-label children)
                      (lambda (i) (envs-select! v (list-ref children i)))
                      'tip (lambda (i) (env-path (list-ref children i))))
           (chips-row "Forks" 'forks (map env-kind-title forks)
                      (lambda (i) (envs-open-fork! v (list-ref forks i)))
                      'empty "Nothing"
                      'tip (lambda (i) (format "Fork a ~a"
                                               (env-kind-title
                                                (list-ref forks i))))))
     (if (env-world? e) (list (envs-follows-row v e)) '())
     (cond
       [(eq? (env-kind e) 'worklets) (envs-pool-rows v)]
       [(envs-bundled? e) (envs-bundle-rows v e)]
       [vat (envs-vat-rows v vat)]
       [else '()]))))

;; A world namespace's: Sync, and whether the world gained names since
;; its last, which come at its next evaluation, or now.
(define (envs-follows-row v e)
  (let*-values ([(ui) (envs-view-ui v)] [(ch) (ui-control-height)]
                [(shared own new) (envs-facts v e)] [(n) (length new)]
                [(bw bh) (ui-button-size "Sync" #f)] [(gap) (ui-gap)])
    (list "Follows" ch
          (lambda (x y w)
            (ui-button ui '(envs sync) x y bw ch "Sync"
                       (lambda ()
                         (env-sync! e)
                         (hashtable-delete! (envs-view-facts v) e))
                       'disabled (= n 0)
                       'tip "Share it the names the world gained since: \
                             (env-sync! e)")
            (ui-draw-label (+ x bw gap) y (max 0 (- w bw gap)) ch
                           (if (= n 0) '(dim) '())
                           (if (= n 0)
                               "Up to date with the world"
                               (format "~a name~a of the world's not here yet"
                                       n (if (= n 1) "" "s")))))
          'hint "Every name of the world's, those it gains later too: at \
                 its next evaluation, or now with Sync")))

;; /worklets: the pool's threads, and its jobs.
(define (envs-pool-rows v)
  (let ([ui (envs-view-ui v)] [ch (ui-control-height)])
    (list (list "Pool" ch
                (lambda (x y w)
                  (ui-stepper ui '(envs pool) x y (vat-pool-size) 1 64
                              (lambda (n) (vat-pool-size-set! n))
                              'tip "How many threads run the pool's \
                                    worklets: (vat-pool-size-set! n)"))
                'hint (let ([v (vat-of (env-worklets))])
                        (if v
                            (format "~a running, ~a jobs"
                                    (vat-threads-of v)
                                    (length (vat-jobs-of v)))
                            "Not started: it starts with its first job"))))))

;; A thread's vat: its threads, and its jobs, each a chip whose × kills
;; it.
(define (envs-vat-rows v vat)
  (let* ([ui (envs-view-ui v)] [jobs (vat-jobs-of vat)]
         [labels (map (lambda (j)
                        (let ([w (vat-job-window j)])
                          (format "~a~a" (vat-job-kind j)
                                  (if w (format " · ~a" (window-title w)) ""))))
                      jobs)])
    (list (list "Thread" (ui-control-height)
                (lambda (x y w)
                  (ui-draw-label x y w (ui-control-height) '()
                                 (format "~a thread, its vat's"
                                         (vat-threads-of vat)))))
          (cons* "Jobs" (lambda (w) (ui-chips-height w labels #t #f))
                 (lambda (x y w)
                   (ui-chips ui '(envs jobs) x y w labels #f
                             'on-remove (lambda (i)
                                          (vat-job-kill! (list-ref jobs i)))
                             'empty "None waiting"))
                 (if (pair? jobs) '(hint "× stops one") '())))))

;;; ------------------------------------------------------------------
;;; apps' bundles

;; Is e /apps, or an app's sandbox: does it hold what bundles hold?
(define (envs-bundled? e) (and (memq (env-kind e) '(apps app)) #t))

;; The title of the bundle a name came in. What no bundle holds, every
;; app holds (define-app).
(define (envs-bundle-title name)
  (let ([b (grant-bundle-of name)])
    (if b (grant-bundle-title b) "Every app's")))

;; A bundle's chip: for an app, how its request stands; for /apps, how much
;; it holds.
(define (envs-bundle-label app b)
  (let ([title (grant-bundle-title b)])
    (if app
        (case (grant-state app b)
          [(denied) (format "~a · denied" title)]
          [(undecided) (format "~a · not decided" title)]
          [else title])
        (format "~a · ~a" title (length (grant-bundle-names b))))))

;; Only the names of bundle b, by the names' filter; pressed again, all.
(define (envs-show-bundle! v b)
  (let ([title (grant-bundle-title b)])
    (envs-view-names-set! v 'shared)
    (envs-view-names-query-set!
     v (if (equal? (envs-view-names-query v) title) "" title))
    (ui-forget! (envs-view-ui v) (list '(envs names-table) 'body))))

;; What an app's sandbox requests, or on /apps what any may; a press shows
;; a bundle's names. Then an app's: who decides, and the person's way to.
(define (envs-bundle-rows v e)
  (let* ([ui (envs-view-ui v)] [app (grant-app-in e)]
         [bundles (if app (grant-requested app) (map car grant-bundles))]
         [labels (map (lambda (b) (envs-bundle-label app b)) bundles)])
    (cons
     (list "Bundles" (lambda (w) (ui-chips-height w labels #f #f))
           (lambda (x y w)
             (ui-chips ui '(envs bundles) x y w labels
                       (lambda (i) (envs-show-bundle! v (list-ref bundles i)))
                       'keys bundles
                       'empty "It requests none"
                       'tip (lambda (i)
                              (format "Only the names of ~a, or all again"
                                      (grant-bundle-title
                                       (list-ref bundles i))))))
           'hint (if app
                     "What it requests, of the world's names"
                     "What an app may request: its sandbox is shared what \
                      it is allowed from here"))
     (if app (list (envs-permissions-row v app)) '()))))

(define (envs-permissions-row v app)
  (let*-values ([(ui) (envs-view-ui v)] [(ch) (ui-control-height)]
                [(gap) (ui-gap)] [(asks?) (grant-asks? app)]
                [(n) (length (grant-undecided app))]
                [(bw bh) (ui-button-size "Permissions…" #f)])
    (list "Decided by" ch
          (lambda (x y w)
            (ui-button ui '(envs permissions) x y bw ch "Permissions…"
                       (lambda ()
                         (open-permissions-dialog app void (current-window)))
                       'disabled (not asks?)
                       'tip (if asks?
                                "Change what it may do: it loads again"
                                "Built in: Schevana's table allows it"))
            (ui-draw-label (+ x bw gap) y (max 0 (- w bw gap)) ch '(dim)
                           (cond [(not asks?) "Schevana's table"]
                                 [(= n 0) "You"]
                                 [else (format "You: ~a not decided yet" n)])))
          'hint (if asks?
                    (format "Kept in ~a" *grant-file-path*)
                    "grant-tree-apps, in services/grant.ss"))))

(define (envs-names-columns e which room)
  (let ([third (round (/ room 3))] [quarter (round (/ room 4))])
    (cond
      [(not (eq? which 'shared))
       `((name "Name" ,(- room third quarter))
         (what "Kind" ,quarter)
         (value "Value" ,third))]
      [(envs-bundled? e)
       `((name "Name" ,(- room third third))
         (bundle "Bundle" ,third "The bundle it came in")
         (held "What" ,third
               "The world's own, read-only; or what was made for this app"))]
      [else
       `((name "Name" ,(- room third quarter quarter))
         (from "Parent's" ,quarter
               "The parent's name it forwards to, where it is renamed; \
                or what the parent made for it")
         (set "Set!" ,quarter "Refused, or through the parent's setter")
         (holder "Bound in" ,third
                 "Where its binding is: double click to go there"))])))

(define (envs-names-text e which row key)
  (if (eq? which 'shared)
      (case key
        [(name) (symbol->string (car row))]
        [(bundle) (envs-bundle-title (car row))]
        [(held) (or (cadddr row) "the world's")]
        [(from) (cond [(cadddr row)]   ; given: what it is
                      [(eq? (car row) (cadr row)) ""]
                      [else (symbol->string (cadr row))])]
        [(set) (cond [(cadddr row) "its own"]
                     [(caddr row) (format "via ~a" (caddr row))]
                     [else "read-only"])]
        [else (envs-holder e (car row) (cadr row))])
      (let ([env (env-environment e)])
        (case key
          [(name) (symbol->string row)]
          [(what) (cond [(not (top-level-bound? row env)) "syntax"]
                        [(worklet? (top-level-value row env)) "worklet"]
                        [(procedure? (top-level-value row env)) "procedure"]
                        [else "value"])]
          [else (if (and (top-level-bound? row env)
                         (not (procedure? (top-level-value row env))))
                    (parameterize ([print-length 6] [print-level 3])
                      (let ([s (format "~s" (top-level-value row env))])
                        (substring s 0 (min 120 (string-length s)))))
                    "")]))))

;; The names: Shared or Own, a filter, and their table, at least rows
;; high. => the y below
(define (envs-names v e x y w rows)
  (let*-values ([(ui) (envs-view-ui v)] [(gap) (ui-gap)]
                [(shared own new) (envs-facts v e)]
                [(which) (if (and (eq? (envs-view-names v) 'own) own)
                             'own
                             'shared)]
                [(all) (if (eq? which 'own) own shared)]
                [(q) (envs-trim (envs-view-names-query v))]
                [(shown) (if (string=? q "")
                             all
                             (filter (lambda (r)
                                       (let ([n (if (pair? r) (car r) r)])
                                         (or (string-contains-ci?
                                              (symbol->string n) q)
                                             (and (pair? r) (envs-bundled? e)
                                                  (string-contains-ci?
                                                   (envs-bundle-title n)
                                                   q)))))
                                     all))]
                [(sw sh) (ui-label-size '(section) "Names" w)]
                [(ch) (ui-control-height)]
                [(segs) (list (cons (format "Shared ~a" (length shared))
                                    'shared)
                              (cons (if own
                                        (format "Own ~a" (length own))
                                        "Own")
                                    'own))]
                [(segw) (* 2 (+ 34 (text-widest (map car segs) 'ui)))]
                [(fw) (max 120 (- w segw gap))]
                [(th) (+ (ui-table-header-height)
                         (* rows (ui-table-row-height)))])
    (ui-draw-label x y w sh '(section) "Names")
    (let ([y (+ y sh 6)])
      (ui-segmented ui '(envs names) x y segw ch segs which
                    (lambda (n)
                      (envs-view-names-set! v n)
                      (ui-forget! ui (list '(envs names-table) 'body))))
      (ui-text-field ui '(envs names-query) (+ x segw gap) y (- w segw gap) ch
                     (envs-view-names-query v)
                     (lambda (s) (envs-view-names-query-set! v s))
                     'search #t 'placeholder "Filter names"
                     'on-enter (lambda () (ui-focus! ui #f)))
      (let ([ty (+ y ch gap)])
        (if (and (eq? (envs-view-names v) 'own) (not own))
            (ui-draw-label x ty w 0 '(hint wrap)
                           "Its own names are its thread's: its vat's \
                            sandbox is read there, not here.")
            (let ([room (ui-table-room w)])
              (ui-draw-surface x ty w th '(well))
              (ui-table ui '(envs names-table) x (+ ty 4) w (- th 8)
                        (envs-names-columns e which room) shown #f
                        (lambda (row) #f)
                        (lambda (row key cx cy cw ch flags)
                          (ui-draw-cell cx cy cw ch flags
                                        (envs-names-text e which row key)))
                        'on-open
                        (lambda (row)
                          (when (pair? row)
                            (let ([h (env-find (envs-holder e (car row)
                                                            (cadr row)))])
                              (when h (envs-select! v h))))))))
        (+ ty th)))))

(define (envs-inspector v x y w h)
  (let* ([ui (envs-view-ui v)] [e (envs-view-selected v)] [p (ui-pad)]
         [l (max p (ui-scrollbar-inset 'left))]
         [r (max p (ui-scrollbar-inset 'right))])
    (ui-draw-surface x y w h '(side))
    (ui-scroll ui 'inspector x y w h
      (lambda (top)
        (let* ([cx (+ x l)] [cw (- w l r)]
               [y (envs-draw-head e cx (+ top p) cw)]
               [y (ui-form ui 'envs-facts cx (+ y (ui-gap) 8) cw
                           (envs-fact-rows v e))])
          ;; the names fill what the view leaves, scrolled or not
          (+ p (envs-names v e cx (+ y 20) cw
                           (max 6 (exact
                                   (floor (/ (- h (- y top) 120)
                                             (ui-table-row-height))))))))))))

;;; ------------------------------------------------------------------
;;; the sheets

(define (envs-sheet-width) (round (* 30 (font-line-height 'ui))))

;; A row of the sheet's error, when its last try raised one.
(define (envs-error-rows v)
  (let ([err (envs-view-error v)])
    (if err
        (list (list #f
                    (lambda (w)
                      (let-values ([(ew eh) (ui-label-size '(wrap) err w)])
                        eh))
                    (lambda (x y w) (ui-draw-label x y w 0 '(error wrap) err))))
        '())))

;; The share field: the chips, and what is typed, suggested from the names
;; holder holds; and Choose…, the share dialog for them.
(define (envs-share-row v holder hint)
  (let*-values ([(ui) (envs-view-ui v)]
                [(bw bh) (ui-button-size "Choose…" #f)] [(gap) (ui-gap)])
    (list "Share"
          (lambda (w) (ui-chip-input-size (- w bw gap) (envs-view-shares v)))
          (lambda (x y w)
            (ui-button ui '(envs-sheet choose) (- (+ x w) bw) y bw bh
                       "Choose…"
                       (lambda ()
                         (envs-open-picker!
                          (format "Share from ~a" (env-path holder)) holder #f
                          "Choose"
                          (filter values (map envs-chip-picked
                                              (envs-view-shares v)))
                          (lambda (picked)
                            (envs-view-shares-set!
                             v (map envs-picked-chip picked)))))
                       'tip "Pick them from the list of its names")
            (ui-chip-input ui '(envs-sheet shares) x y (- w bw gap)
                           (envs-view-shares v)
                           (envs-view-draft v)
                           (lambda (s) (envs-view-draft-set! v s))
                           (lambda (ss)
                             (envs-view-shares-set!
                              v (append (envs-view-shares v)
                                        (filter (lambda (s)
                                                  (not (string=?
                                                        (envs-trim s) "")))
                                                (map envs-trim ss)))))
                           (lambda (i)
                             (envs-view-shares-set!
                              v (let ([l (envs-view-shares v)])
                                  (append (list-head l i)
                                          (list-tail l (+ i 1))))))
                           'placeholder "A name…"
                           'suggest
                           (lambda (typed)   ; the first word's
                             (if (memv #\space (string->list typed))
                                 '()
                                 (envs-memo v (list 'share holder typed)
                                   (lambda ()
                                     (ui-suggestions
                                      typed
                                      (map symbol->string
                                           (remp gensym?
                                                 (environment-symbols
                                                  (env-environment holder))))
                                      8)))))))
          'hint hint)))

(define (envs-close-sheet! v) (envs-view-sheet-set! v #f))

;; Fork: the kinds, those its fork does not make off; its name, and the
;; path it will have; what it is shared; a REPL in it.
(define (envs-fork-sheet v)
  (let* ([ui (envs-view-ui v)] [e (envs-view-selected v)]
         [kind (envs-view-kind v)] [forks (env-forks e)]
         ;; what may be forked by hand at all: those code makes (an app's
         ;; sandbox) or core0 does ("/core0", "/recorder") aren't offered
         [kinds (filter (lambda (k) (env-kind-ref k 'fork #t)) (env-kinds))]
         [bw (envs-sheet-width)] [ch (ui-control-height)]
         [radio-h (lambda (w k)   ; and 2 below
                    (let-values ([(rw rh) (ui-radio-size
                                           (env-kind-title k)
                                           (env-kind-ref k 'doc #f) #t w)])
                      (+ rh 2)))]
         [typed (envs-trim (envs-view-name v))]
         [child (env-child-name e (if (string=? typed "")
                                      kind
                                      (string->symbol typed)))]
         [path (if (env-parent e)
                   (format "~a/~a" (env-path e) child)
                   (format "/~a" child))]
         [rows
          (append
           (list
            (list #f (lambda (w) (apply + (map (lambda (k) (radio-h w k))
                                               kinds)))
                  (lambda (x y w)
                    (fold-left
                     (lambda (y k)
                       (let ([h (radio-h w k)] [ok? (memq k forks)])
                         (ui-radio ui (list 'envs-sheet 'kind k) x y w (- h 2)
                                   (env-kind-title k) (eq? k kind)
                                   (lambda () (envs-view-kind-set! v k))
                                   'hint (env-kind-ref k 'doc #f)
                                   'icon (lambda (ix iy s flags)
                                           (ui-draw-env-icon ix iy s flags
                                                             k))
                                   'disabled (not ok?)
                                   'tip (and (not ok?)
                                             (format "~a forks ~a only"
                                                     (env-path e)
                                                     (string-join
                                                      (map env-kind-title
                                                           forks)
                                                      ", "))))
                         (+ y h)))
                     y kinds)))
            (list "Name" ch
                  (lambda (x y w)
                    (ui-text-field ui '(envs-sheet name) x y w ch
                                   (envs-view-name v)
                                   (lambda (s) (envs-view-name-set! v s))
                                   'placeholder (symbol->string kind)))
                  'hint (format "It will be ~a" path))
            (envs-share-row
             v e
             (string-append
              (format "Names of ~a's. “now-ms as clock” renames one; \
                       “size via size-set!” sets it through the setter."
                      (env-path e))
              (if (eq? kind 'thread)
                  " What a thread is shared runs on its thread: share \
                   worklets, or what is safe there."
                  "")))
            (list #f ch
                  (lambda (x y w)
                    (ui-checkbox ui '(envs-sheet repl) x y w ch
                                 "Open a REPL in it" (envs-view-repl? v)
                                 (lambda (on?) (envs-view-repl?-set! v on?))))))
           (envs-error-rows v))])
    (ui-sheet ui 'envs-sheet (format "Fork ~a" (env-path e)) bw
              (ui-form-height rows bw)
              (lambda (x y w) (ui-form ui '(envs-sheet form) x y w rows))
              (list (list "Cancel" (lambda () (envs-close-sheet! v)))
                    (list "Fork" (lambda () (envs-fork! v)) 'primary))
              (lambda () (envs-close-sheet! v)))))

(define (envs-drop-dialog v)
  (let* ([e (envs-view-selected v)]
         [under (let walk ([e e])
                  (apply append (map (lambda (c) (cons c (walk c)))
                                     (env-children e))))]
         [threads (filter vat-of (cons e under))])
    (ui-dialog (envs-view-ui v) 'envs-sheet (format "Drop ~a?" (env-path e))
               (format "It goes~a~a. REPLs in them evaluate nowhere after."
                       (case (length under)
                         [(0) ""]
                         [(1) ", with the environment under it"]
                         [else (format ", with the ~a environments under it"
                                       (length under))])
                       (if (null? threads)
                           ""
                           ", and its threads' jobs stop"))
               (list (list "Cancel" (lambda () (envs-close-sheet! v)))
                     (list "Drop" (lambda () (envs-drop! v)) 'danger))
               (lambda () (envs-close-sheet! v)))))

;;; ------------------------------------------------------------------
;;; the share dialog
;;; A window over Environments, which waits on it. Left, the names the
;;; holder holds (the parent of what they are shared with), each with a
;;; box to check, its kind, and, shared there already, its box checked
;;; and off; right, those checked, in the order checked, and under them
;;; the options of the one chosen: As (a rename) and Set! via (a setter
;;; of the holder's). Its action shares them (Share…), or hands them
;;; back (the Fork sheet's Choose…). Keys, with no field focused: Up and
;;; Down choose a name, Space checks it, Return acts, Escape cancels;
;;; typing filters.

(define-record-type envs-picker
  (nongenerative schevana-envs-picker-1)
  (fields holder target action on-done ui
          (mutable picked)    ; ((name alias setter) ...), as checked:
                              ; alias and setter as typed, "" for none
          (mutable current)   ; the name chosen, or #f
          (mutable filter)
          (mutable scope)     ; own (shared and its own) or all
          (mutable kind)      ; the kind shown, or #f for any
          (mutable error)     ; what the last try raised, or #f
          (mutable listed)    ; (scope . names), the last listed
          kinds))             ; name -> its kind, as found

;; Opens the dialog over the window of the handler that calls it: names of
;; holder's, for target (#f: one to be forked), picked already the
;; ((name alias setter) ...) of picked; action its button's word. Its
;; action calls (on-done picked), which may raise, as the dialog's
;; error. => its window
(define (envs-open-picker! title holder target action picked on-done)
  (let* ([ui (make-ui)] [lh (font-line-height 'ui)]
         [p (make-envs-picker holder target action on-done ui picked
                              (and (pair? picked) (caar picked)) "" 'own #f
                              #f #f (make-eq-hashtable))])
    (apply ui-open-modal (current-window) title
           (max 820 (round (* 58 lh))) (max 520 (round (* 35 lh)))
           'min-size (cons (round (* 40 lh)) (round (* 24 lh)))
           'app #f
           'state p
           'draw (lambda (win w h) (envs-picker-draw p w h))
           (ui-handlers ui
                        'key (lambda (win key mods)
                               (envs-picker-key p key mods))
                        'text (lambda (win str) (envs-picker-text p str))))))

;; The holder's names in scope, by name: its own and those it was shared
;; (the world's own, for the world), or every one, its base's too.
(define (envs-picker-names p)
  (let ([l (envs-picker-listed p)] [scope (envs-picker-scope p)])
    (if (and l (eq? (car l) scope))
        (cdr l)
        (let* ([h (envs-picker-holder p)]
               [names (if (eq? scope 'all)
                          (remp gensym? (environment-symbols
                                         (env-environment h)))
                          (append (map car (env-shared-names h))
                                  (env-own-names h)))]
               [sorted (sort (lambda (a b)
                               (string-ci<? (symbol->string a)
                                            (symbol->string b)))
                             names)])
          (envs-picker-listed-set! p (cons scope sorted))
          sorted))))

;; A name's kind, as its binding is, wherever it is bound.
(define (envs-name-kind holder name)
  (let-values ([(h n) (env-holder holder name)])
    (let ([env (env-environment h)])
      (cond [(not (top-level-bound? n env)) "syntax"]
            [(worklet? (top-level-value n env)) "worklet"]
            [(procedure? (top-level-value n env)) "procedure"]
            [else "variable"]))))

;; A name's kind, found once: the list asks at every draw.
(define (envs-picker-kind-of p n)
  (let ([t (envs-picker-kinds p)])
    (or (hashtable-ref t n #f)
        (let ([k (envs-name-kind (envs-picker-holder p) n)])
          (hashtable-set! t n k)
          k))))

;; What the list shows: the names the filter and kind leave.
(define (envs-picker-shown p)
  (let ([q (envs-trim (envs-picker-filter p))] [k (envs-picker-kind p)])
    (filter (lambda (n)
              (and (or (string=? q "")
                       (string-contains-ci? (symbol->string n) q))
                   (or (not k) (string=? k (envs-picker-kind-of p n)))))
            (envs-picker-names p))))

;; The holder's names the target forwards to already, under any name.
(define (envs-picker-shared p)
  (let ([t (envs-picker-target p)])
    (if t (map cadr (env-shared-names t)) '())))

(define (envs-picker-toggle! p name)
  (let ([picked (envs-picker-picked p)])
    (envs-picker-error-set! p #f)
    (if (assq name picked)
        (envs-picker-picked-set! p (remp (lambda (e) (eq? (car e) name))
                                         picked))
        (unless (memq name (envs-picker-shared p))
          (envs-picker-picked-set! p (append picked (list (list name "" ""))))
          (envs-picker-current-set! p name)))))

;; Sets the chosen one's alias or setter (field 1 or 2) to s.
(define (envs-picker-set! p field s)
  (let ([name (envs-picker-current p)])
    (envs-picker-error-set! p #f)
    (envs-picker-picked-set!
     p (map (lambda (e)
              (if (eq? (car e) name)
                  (if (= field 1)
                      (list (car e) s (caddr e))
                      (list (car e) (cadr e) s))
                  e))
            (envs-picker-picked p)))))

;; picked as env-share! and env-share-setter! take them: (values shares
;; setters), what does not read as a name refused.
(define (envs-picked-shares picked)
  (let loop ([es picked] [shares '()] [setters '()])
    (if (null? es)
        (values (reverse shares) (reverse setters))
        (let* ([name (caar es)]
               [word (lambda (what s)
                       (let ([s (envs-trim s)])
                         (cond [(string=? s "") #f]
                               [(exists (lambda (c) (or (char-whitespace? c)
                                                        (char=? c #\/)))
                                        (string->list s))
                                (errorf 'share "~a's ~a is a name, not ~s"
                                        name what s)]
                               [else (string->symbol s)])))]
               [alias (word "As" (cadar es))]
               [setter (word "Set! via" (caddar es))]
               [n (if alias (cons alias name) name)])
          (if setter
              (loop (cdr es) shares (cons (cons n setter) setters))
              (loop (cdr es) (cons n shares) setters))))))

;; A picked one as the Fork sheet's chip says it, and back.
(define (envs-picked-chip e)
  (string-append (symbol->string (car e))
                 (if (string=? (envs-trim (cadr e)) "")
                     ""
                     (string-append " as " (envs-trim (cadr e))))
                 (if (string=? (envs-trim (caddr e)) "")
                     ""
                     (string-append " via " (envs-trim (caddr e))))))

(define (envs-chip-picked chip)
  (let-values ([(share setter) (envs-share-words chip)])
    (and share
         (list (if (pair? share) (cdr share) share)
               (if (pair? share) (symbol->string (car share)) "")
               (if setter (symbol->string setter) "")))))

(define (envs-picker-done! p)
  (guard (c [#t (envs-picker-error-set! p (condition->string c))])
    ((envs-picker-on-done p) (envs-picker-picked p))
    (close-window! (current-window))))

;;; drawing

(define (envs-picker-names-columns room)
  (ui-table-fit room
                `((name "Name" #f)
                  (kind "Kind" ,(round (+ (* 2 (ui-table-cell-inset)) 4
                                          (text-widest '("procedure"
                                                         "variable" "worklet"
                                                         "syntax")
                                                       'ui)))))
                '(kind) (* 8 (font-line-height 'ui))))

(define (envs-picker-list p x y w h)
  (let* ([ui (envs-picker-ui p)] [shared (envs-picker-shared p)])
    (ui-draw-surface x y w h '(well))
    (ui-table ui '(envs-picker names) x (+ y 4) w (- h 8)
              (envs-picker-names-columns (ui-table-room w))
              (envs-picker-shown p) (envs-picker-current p)
              (lambda (n) (envs-picker-current-set! p n))
              (lambda (n key cx cy cw ch flags)
                (let ([dim (if (memq n shared) (cons 'dim flags) flags)])
                  (ui-draw-cell cx cy cw ch dim
                                (if (eq? key 'name)
                                    (symbol->string n)
                                    (string-append
                                     (envs-picker-kind-of p n)
                                     (if (memq n shared) " · shared" ""))))))
              'checked (lambda (n)
                         (cond [(memq n shared) 'fixed]
                               [(assq n (envs-picker-picked p)) #t]
                               [else #f]))
              'on-check (lambda (n) (envs-picker-toggle! p n))
              'on-open (lambda (n) (envs-picker-toggle! p n))
              'tip (lambda (n)
                     (and (memq n shared)
                          (format "~a is shared with ~a already"
                                  n (env-path (envs-picker-target p)))))
              'reveal #t)))

;; Those checked, and the options of the one chosen.
(define (envs-picker-side p x y w h)
  (let*-values ([(ui) (envs-picker-ui p)] [(gap) (ui-gap)]
                [(picked) (envs-picker-picked p)]
                [(sw sh) (ui-label-size '(section) "To share" w)]
                [(ch) (ui-control-height)]
                [(e) (assq (envs-picker-current p) picked)]
                [(rows)
                 (if e
                     (list (list "As" ch
                                 (lambda (fx fy fw)
                                   (ui-text-field ui '(envs-picker as) fx fy fw
                                                  ch (cadr e)
                                                  (lambda (s)
                                                    (envs-picker-set! p 1 s))
                                                  'placeholder
                                                  (symbol->string (car e))))
                                 'hint "Its name there; its own by default")
                           (list "Set! via" ch
                                 (lambda (fx fy fw)
                                   (ui-text-field ui '(envs-picker via) fx fy
                                                  fw ch (caddr e)
                                                  (lambda (s)
                                                    (envs-picker-set! p 2 s))
                                                  'placeholder "read-only"
                                                  'suggest
                                                  (lambda (typed)
                                                    (envs-picker-setters
                                                     p (car e) typed))))
                                 'hint "A procedure of the holder's that its \
                                        set! calls; read-only when none"))
                     '())]
                [(fh) (if e (+ (ui-form-height rows w) sh 6 16) 0)]
                [(th) (max (* 3 (ui-table-row-height)) (- h sh 6 fh gap))])
    (ui-draw-label x y w sh '(section)
                   (format "To share (~a)" (length picked)))
    (ui-draw-surface x (+ y sh 6) w th '(well))
    (ui-table ui '(envs-picker picked) x (+ y sh 10) w (- th 8)
              (let ([room (ui-table-room w)])
                (ui-table-fit room
                              `((name "Name" #f)
                                (as "As" ,(round (* room 0.3)))
                                (via "Set! via" ,(round (* room 0.3))))
                              '(via as) (* 6 (font-line-height 'ui))))
              picked e
              (lambda (r) (envs-picker-current-set! p (car r)))
              (lambda (r key cx cy cw ch flags)
                (ui-draw-cell cx cy cw ch flags
                              (case key
                                [(name) (symbol->string (car r))]
                                [(as) (cadr r)]
                                [else (caddr r)])))
              'on-open (lambda (r) (envs-picker-toggle! p (car r))))
    (when e
      (let ([fy (+ y sh 6 th 16)])
        (ui-draw-label x fy w sh '(group) (symbol->string (car e)))
        (ui-form ui '(envs-picker form) x (+ fy sh 6) w rows)))))

;; The holder's procedures typed may name, name-set! first.
(define (envs-picker-setters p name typed)
  (let ([own (string->symbol (format "~a-set!" name))])
    (append (if (and (string=? typed "")
                     (memq own (envs-picker-names p)))
                (list (symbol->string own))
                '())
            (ui-suggestions
             typed
             (map symbol->string
                  (filter (lambda (n)
                            (string=? (envs-picker-kind-of p n) "procedure"))
                          (filter (lambda (n)
                                    (string-contains-ci? (symbol->string n)
                                                         typed))
                                  (envs-picker-names p))))
             8))))

(define (envs-picker-draw p w h)
  (let*-values ([(ui) (envs-picker-ui p)] [(pad gap) (values (ui-pad) (ui-gap))]
                [(ch) (ui-control-height)]
                [(scopes) (list (cons (if (env-parent (envs-picker-holder p))
                                          "Its own and shared"
                                          "The world's own")
                                      'own)
                                (cons "All, Chez's too" 'all))]
                [(kinds) '(("Any kind" . #f) ("Procedures" . "procedure")
                           ("Syntax" . "syntax") ("Variables" . "variable")
                           ("Worklets" . "worklet"))]
                [(dw dh) (ui-dropdown-size (map car (append scopes kinds)))]
                [(fw fh) (ui-text-box-size '(search) 0 1)]
                [(n) (length (envs-picker-picked p))]
                [(action) (format "~a ~a" (envs-picker-action p)
                                  (if (= n 1) "1 name" (format "~a names" n)))]
                [(aw ah) (ui-button-size action #f)]
                [(cw chh) (ui-button-size "Cancel" #f)]
                [(foot) (+ ch pad pad)])
    (ui-begin! ui)
    (ui-draw-surface 0 0 w h '(page))
    (let* ([top (ui-toolbar
                 0 0 w
                 (list (list #f fh
                             (lambda (x y w h)
                               (ui-text-field ui '(envs-picker filter) x y w h
                                              (envs-picker-filter p)
                                              (lambda (s)
                                                (envs-picker-filter-set! p s))
                                              'search #t
                                              'placeholder
                                              (format "Filter ~a's names"
                                                      (env-path
                                                       (envs-picker-holder p)))
                                              'on-enter
                                              (lambda () (ui-focus! ui #f)))))
                       (list dw dh
                             (lambda (x y w h)
                               (ui-dropdown ui '(envs-picker scope) x y w h
                                            scopes (envs-picker-scope p)
                                            (lambda (s)
                                              (envs-picker-scope-set! p s)))))
                       (list dw dh
                             (lambda (x y w h)
                               (ui-dropdown ui '(envs-picker kind) x y w h
                                            kinds (envs-picker-kind p)
                                            (lambda (k)
                                              (envs-picker-kind-set! p k))))))
                 'flex '(150 . 100000))]
           [bh (max 0 (- h top foot))]
           [lw (ui-split ui '(envs-picker split) 0 top w bh
                         (round (* w 0.52)) 260 300)])
      (envs-picker-list p pad (+ top pad) (- lw pad pad) (- bh pad pad))
      (envs-picker-side p (+ lw pad) (+ top pad) (- w lw pad pad)
                        (- bh pad pad))
      (let ([fy (+ top bh)] [by (+ top bh pad)])
        (ui-draw-surface 0 fy w foot '(footer))
        (let ([err (envs-picker-error p)])
          (when err
            (ui-draw-label pad by (- w pad pad aw cw gap gap) ch '(error)
                           err)))
        (ui-button ui '(envs-picker cancel) (- w pad aw gap cw) by cw ch
                   "Cancel" (lambda () (close-window! (current-window)))
                   'tip "Escape")
        (ui-button ui '(envs-picker done) (- w pad aw) by aw ch action
                   (lambda () (envs-picker-done! p))
                   'primary #t
                   'disabled (and (= n 0) (envs-picker-target p) #t))))
    (ui-end! ui w h)))

;;; keys

(define (envs-picker-key p key mods)
  (and (null? mods)
       (case key
         [(escape) (close-window! (current-window)) #t]
         [(return) (envs-picker-done! p) #t]
         [(#\space)
          (when (envs-picker-current p)
            (envs-picker-toggle! p (envs-picker-current p)))
          #t]
         [else
          (let* ([shown (envs-picker-shown p)]
                 [i (list-index (lambda (n) (eq? n (envs-picker-current p)))
                                shown)]
                 [j (ui-table-step i (length shown)
                                   (ui-table-page (envs-picker-ui p)
                                                  '(envs-picker names))
                                   key)])
            (and j (begin (envs-picker-current-set! p (list-ref shown j))
                          #t)))])))

;; Typing filters; a blank is Space's, which the key took.
(define (envs-picker-text p str)
  (unless (string=? (envs-trim str) "")
    (envs-picker-filter-set! p (string-append (envs-picker-filter p) str))
    (ui-focus! (envs-picker-ui p) '(envs-picker filter)))
  #t)

;;; ------------------------------------------------------------------
;;; the window

(define (envs-toolbar v w)
  (let*-values
      ([(ui) (envs-view-ui v)] [(e) (envs-view-selected v)]
       [(all) (envs-all)]
       [(threads) (length (filter vat-of all))]
       [(count) (format "~a environments · ~a thread~a" (length all) threads
                        (if (= threads 1) "" "s"))]
       [(cw ch) (ui-label-size '(dim) count 0)]
       [(sw sh) (ui-text-box-size '(search) 0 1)])
    (ui-toolbar
     0 0 w
     (append
      (map (lambda (a)
             (let-values ([(bw bh) (ui-button-size (cadr a) (caddr a))])
               (list bw bh
                     (lambda (x y w h)
                       (let ([why (envs-why-not e (car a))])
                         (ui-button ui (list 'envs (car a)) x y w h (cadr a)
                                    (lambda () (envs-act! v (car a)))
                                    'glyph (caddr a)
                                    'primary (eq? (car a) 'fork)
                                    'danger (eq? (car a) 'drop)
                                    'disabled (and why #t)
                                    'tip (or why (cadddr a))))))))
           envs-actions)
      (list (list #f sh
                  (lambda (x y w h)
                    (ui-text-field ui '(envs query) x y w h
                                   (envs-view-query v)
                                   (lambda (s) (envs-view-query-set! v s))
                                   'search #t 'placeholder "Filter"
                                   'tip "Filter the tree  /"
                                   'on-enter (lambda () (ui-focus! ui #f)))))))
     'end (list (ceiling cw) sh
                (lambda (x y w h)
                  (ui-draw-label x y w h '(dim right) count))))))

(define (envs-draw v w h)
  (let ([ui (envs-view-ui v)])
    ;; dropped elsewhere (a REPL closed, say): the one made again where it
    ;; was (an app's), or its nearest that is not
    (let up ([e (envs-view-selected v)])
      (if (env-dropped? e)
          (up (or (env-find (env-path e)) (env-parent e)))
          (unless (eq? e (envs-view-selected v)) (envs-select! v e))))
    (ui-begin! ui)
    (ui-draw-surface 0 0 w h '(page))
    ;; the tree and the inspector share what is left, as the line between
    ;; them is dragged
    (let* ([top (envs-toolbar v w)]
           [tw (ui-split ui 'split 0 top w (- h top)
                         (max 300 (min (- w 380) (round (* w 0.55))))
                         280 320)])
      (envs-tree v 0 top tw (- h top))
      (envs-inspector v tw top (- w tw) (- h top)))
    (case (envs-view-sheet v)
      [(fork) (envs-fork-sheet v)]
      [(drop) (envs-drop-dialog v)])
    (ui-due! ui (+ (now-ms) 1000))   ; jobs and names come and go
    (ui-end! ui w h)))

;; With no field focused and no sheet open: arrows in the tree, Return a
;; REPL, Delete drops; F forks, / filters.
(define (envs-key v win key mods)
  (let ([ui (envs-view-ui v)])
    (and (not (envs-view-sheet v)) (not (ui-focused ui))
         (cond
           [(ui-tree-key ui 'tree key mods (envs-view-selected v)
                         (lambda (e) (envs-select! v e))
                         (lambda (e) (envs-act! v 'repl)))]
           [(and (eq? key 'delete) (null? mods)) (envs-act! v 'drop) #t]
           [else #f]))))

(define (envs-text v win str)
  (let ([ui (envs-view-ui v)])
    (and (not (envs-view-sheet v)) (not (ui-focused ui))
         (cond [(member str '("f" "F")) (envs-act! v 'fork) #t]
               [(string=? str "/") (ui-focus! ui '(envs query)) #t]
               [else #f]))))

(define (envs-natural-size)
  (let ([lh (font-line-height 'ui)])
    (cons (max 1080 (round (* 72 lh))) (max 660 (round (* 37 lh))))))

(define-app (envs) "Environments"
  (let ([existing (find-window 'envs)])
    (if (and existing (envs-view? (window-ref existing 'state #f)))
        (begin (focus-window! existing) existing)
        (let* ([ui (make-ui)]
               [v (make-envs-view ui (env-root) "" 'shared "" #f 'sandbox ""
                                  '() "" #f #f #f (cons #f #f)
                                  (make-weak-eq-hashtable))])
          ;; one opened by code from before a (reload!) that changed
          ;; envs-view can't draw any more: replace it
          (when existing (close-window! existing))
          (apply open-window "Environments"
                 'size (envs-natural-size)
                 'min-size '(640 . 420)
                 'state v
                 'draw (lambda (win w h) (envs-draw v w h))
                 (ui-handlers ui
                              'key (lambda (win key mods)
                                     (envs-key v win key mods))
                              'text (lambda (win str)
                                      (envs-text v win str))))))))
