;;; tests/units/tasks.ss — Tasks' own procedures, tested with no window, and
;;; its window.

;; Tasks' tasks: the demos' backlog.
(test-backlog!)

(define (mk id title status kind priority who tags due . description)
  (make-task id title (if (pair? description) (car description) "") status
             kind priority who tags due '() '() 0 id))
(define t1 (mk 1 "Fix the menu" 'todo 'bug 'high "Pavel" '("ui") '(2026 11 2)))
(define t2 (mk 2 "Style system" 'doing 'feature 'urgent #f '("style" "kit") #f
               "parts and derived styles"))
(define t3 (mk 3 "Threads spec" 'todo 'chore 'low "Claude" '() '(2026 10 30)))
(define t4 (mk 4 "Old one" 'done 'feature 'normal "Pavel" '("ui") #f))
(define ts (list t1 t2 t3 t4))
(define (ids l) (map task-id l))

(check "tasks-sorted by every key both ways, stable, the empty last"
       (equal? (map (lambda (k)
                      (list (ids (tasks-sorted ts k 'up))
                            (ids (tasks-sorted ts k 'down))))
                    '(id title status kind priority assignee due updated))
               '(((1 2 3 4) (4 3 2 1)) ((1 4 2 3) (3 2 4 1))
                 ((1 3 2 4) (4 2 1 3)) ((1 2 4 3) (3 2 4 1))
                 ((2 1 4 3) (3 4 1 2)) ((3 1 4 2) (1 4 3 2))
                 ((3 1 2 4) (1 3 2 4)) ((1 2 3 4) (4 3 2 1)))))

(check "tasks-words: lowercase, each once, at most 16, each cut to 64 \
        characters"
       (and (equal? (tasks-words " B a  b C ") '("b" "a" "c"))
            (equal? (tasks-words (apply string-append
                                        (map (lambda (i) (format "w~a " i))
                                             (iota 40))))
                    (map (lambda (i) (format "w~a" i)) (iota 16)))
            (equal? (tasks-words (string-append (make-string 100 #\A) " "
                                                (make-string 70 #\a)))
                    (list (make-string 64 #\a)))))

(check "tasks-match?: near misses of 64 and 1,001 characters looked for in \
        a 100,000-character title within a handler's fuel"
       (let ([t (mk 5 (make-string 100000 #\a) 'todo 'bug 'low #f '() #f)])
         (for-all (lambda (n)
                    (let ([words (tasks-words
                                  (string-append (make-string (- n 1) #\a)
                                                 "b"))])
                      (within-fuel?
                       (lambda () (tasks-match? t words #f #f #f #f #t)))))
                  '(64 1001))))

(define (matching words . filters)
  (ids (filter (lambda (t) (apply tasks-match? t (tasks-words words) filters))
               ts)))
(check "tasks-match?: by id, title, description, tag and assignee; each \
        filter; words all match; done tasks hidden"
       (and (equal? (matching "task-1" #f #f #f #f #t) '(1))
            (equal? (matching "4" #f #f #f #f #t) '(4))
            (equal? (matching "MENU" #f #f #f #f #t) '(1))
            (equal? (matching "derived" #f #f #f #f #t) '(2))
            (equal? (matching "kit" #f #f #f #f #t) '(2))
            (equal? (matching "claude" #f #f #f #f #t) '(3))
            (equal? (matching "" 'bug #f #f #f #t) '(1))
            (equal? (matching "" #f 'low #f #f #t) '(3))
            (equal? (matching "" #f #f "pavel" #f #t) '(1 4))
            (equal? (matching "" #f #f 'none #f #t) '(2))
            (equal? (matching "" #f #f #f "ui" #t) '(1 4))
            (equal? (matching "fix menu" #f #f #f #f #t) '(1))
            (equal? (matching "fix style" #f #f #f #f #t) '())
            (equal? (matching "" #f #f #f #f #f) '(1 2 3))))

(check "tasks-move: across columns, up and down a column, to the end, into \
        an empty column"
       (and (equal? (ids (tasks-move ts t1 'doing #f)) '(2 1 3 4))
            (equal? (ids (tasks-move ts t3 'todo t1)) '(3 1 2 4))
            (equal? (ids (tasks-move ts t1 'todo #f)) '(2 3 1 4))
            (equal? (ids (tasks-move ts t1 'done #f)) '(2 3 4 1))
            (equal? (ids (tasks-move ts t2 'review #f)) '(1 3 4 2))))

(check "tasks-slot: above the first card, between cards, past the last, \
        with none"
       (and (equal? (map (lambda (py) (tasks-slot '(8 60 120) '(40 40 40) py))
                         '(10 70 500))
                    '(0 1 3))
            (= 0 (tasks-slot '() '() 100))))

(check "an assignee is one name whatever its case and the spaces around \
        it: the filter lists it once and finds every spelling"
       (let ([t5 (mk 5 "Typed" 'todo 'bug 'low "pavel " '() #f)])
         (and (equal? (tasks-names (list t1 t5 t3)) '("Claude" "Pavel"))
              (equal? (tasks-names (list t5 t1)) '("pavel"))
              (tasks-match? t5 '() #f #f "Pavel" #f #t)
              (tasks-match? t1 '() #f #f " pavel" #f #t))))

(check "a card's tags: as many chips as fit beside \"+k\" for the rest, the \
        first cut when even it does not fit, never past the card's edge"
       (let* ([pad (ui-card-pad)]
              [chip (lambda (tag)
                      (let-values ([(w h) (ui-chip-size tag #f)]) w))]
              [more (lambda (k) (+ 4 (text-width (format "+~a" k) 'ui-small)))]
              ;; the width of a card with room inside it
              [card (lambda (room) (+ room (* 2 pad)))]
              [long "abcdefghijklmnopqrstuvwx"]
              [fits?
               (lambda (w tags)
                 (let-values ([(ws k)
                               (tasks-card-tags
                                w (mk 6 "x" 'todo 'bug 'low #f tags #f))])
                   (and (pair? ws) (= (+ (length ws) k) (length tags))
                        (<= (+ (apply + ws) (* 4 (- (length ws) 1))
                               (if (> k 0) (more k) 0))
                            (- w (* 2 pad)))
                        (list (length ws) k))))])
         (and (equal? (fits? (card (+ (chip "ui") 4 (chip "kit")))
                             '("ui" "kit"))
                      '(2 0))
              (equal? (fits? (card (+ (chip "abcdefghijkl") (more 2)))
                             '("abcdefghijkl" "abcdefgh" "b"))
                      '(1 2))
              ;; room for the chip, but not for "+1" beside it
              (equal? (fits? (card (chip long)) (list long "b")) '(1 1))
              (equal? (fits? (card (- (chip long) 10)) (list long)) '(1 0)))))

(check "tasks-neighbor, tasks-tag, ui-initials"
       (and (eq? (tasks-neighbor ts t2) t3) (eq? (tasks-neighbor ts t4) t3)
            (not (tasks-neighbor (list t1) t1))
            (equal? (map tasks-tag '("  My Tag " "a,b" "" "   "))
                    '("my-tag" "ab" #f #f))
            (= 24 (string-length (tasks-tag (make-string 30 #\a))))
            ;; a space at the cut would end it in "-"
            (equal? (tasks-tag "dÜnï Cödé Long Tag Name Here")
                    "dünï-cödé-long-tag-name")
            (equal? (tasks-tag "ends-in-") "ends-in-")
            (equal? (map ui-initials '("Pavel Uvarov" "Claude"
                                       "ada lovelace byron"))
                    '("PU" "C" "AB"))))

(check "a task's tags: made by tasks-tag, each once, in the order given, \
        at most 64"
       (let ([names (lambda (n) (map (lambda (i) (format "t~a" i)) (iota n)))])
         (and (equal? (tasks-normalize 'set-task! 'tags
                                       '(" UI" "perf" "ui" "" "," "Perf "))
                      '("ui" "perf"))
              (equal? (tasks-normalize 'set-task! 'tags (names 100))
                      (names 64)))))

(check "tasks-due-label and tasks-overdue?"
       (let ([today '(2026 10 31)])
         (and (equal? (map (lambda (d) (tasks-due-label d today))
                           '((2026 10 31) (2026 11 1) (2026 10 30)
                             (2026 11 15) (2027 1 2)))
                      '("Today" "Tomorrow" "Yesterday" "Nov 15" "Jan 2, 2027"))
              (tasks-overdue? t3 today) (not (tasks-overdue? t1 today))
              (not (tasks-overdue? (mk 5 "x" 'done 'bug 'low #f '()
                                       '(2026 1 1))
                                   today)))))

(check "ids are never reused, and the REPL's procedures name what is valid"
       (let* ([a (add-task! "first")] [_ (delete-task! a)]
              [b (add-task! "second")])
         (delete-task! b)
         (and (> (task-id b) (task-id a))
              (equal? (guard (c [#t (condition->string c)])
                        (set-task! (car *tasks*) 'priority 'hgih))
                      "Exception in set-task!: priority must be one of \
                       urgent high normal low, not hgih"))))

(check "the REPL's edges: a blank name finds no task; an assignee filter \
        that is not a name says so; a description is cleaned as typing \
        cleans it; an assignee is trimmed, but the details' field keeps a \
        space typed after a name; a blank one is nobody; a name is at most \
        64 characters"
       (let ([t (add-task! "Edges" 'description "a\r\nb\tc"
                           'assignee "  Ada  ")]
             [v (tasks-view-new (make-ui))])
         (let ([ok (and (not (find-task "")) (not (find-task "  "))
                        (equal? (guard (c [#t (condition->string c)])
                                  (tasks-list 'assignee 'pavel))
                                "Exception in tasks-list: assignee must be \
                                 a name or none, not pavel")
                        (list? (tasks-list 'assignee 'none))
                        (equal? (task-description t) "a\nb c")
                        (equal? (task-assignee t) "Ada")
                        (equal? (task-assignee (set-task! t 'assignee " B "))
                                "B")
                        (begin (task-set! v t 'assignee " Ada ")
                               (equal? (task-assignee t) "Ada "))
                        (not (task-assignee (set-task! t 'assignee "  ")))
                        (let ([long (make-string 99 #\a)])
                          (= 64 (string-length
                                 (task-assignee
                                  (set-task! t 'assignee long))))))])
           (delete-task! t)
           ok)))

(check "a description holds at most 65,536 characters: what the REPL \
        gives is cut to them"
       (let ([t (add-task! "Long" 'description (make-string 70000 #\a))])
         (let ([n (string-length (task-description t))])
           (set-task! t 'description (make-string 65536 #\b))
           (let ([ok (and (= n 65536)
                          (= 65536 (string-length (task-description t))))])
             (delete-task! t)
             ok))))

(check "a tooltip and a dialog show at most six lines of a long text, the \
        last cut with …"
       (let ([long (apply string-append (make-list 300 "words "))])
         (let-values ([(lines cut?) (ui-wrap-lines long 100 'ui 3)]
                      [(all whole?) (ui-wrap-lines "a b" 100 'ui 3)]
                      [(tw th) (ui-tooltip-size long)]
                      [(dw dh) (ui-dialog-size "Delete?" long '("OK"))]
                      [(dw1 dh1) (ui-dialog-size "Delete?" "short" '("OK"))])
           (and (= 3 (length lines)) cut?
                (string=? "…" (substring (caddr lines)
                                         (- (string-length (caddr lines)) 1)
                                         (string-length (caddr lines))))
                (equal? all '("a b")) (not whole?)
                (= th (+ 10 (* 6 (font-line-height 'ui-small))))
                (< (abs (- dh dh1 (* 5 (font-line-height 'ui)))) 1)))))

(check "blocked-by: ids, each once, of tasks named any way; whom a task \
        blocks worked out; a cycle refused, the error naming it, and the \
        task unchanged; a deleted task blocks nothing"
       (let* ([a (add-task! "Dep A")]
              [b (add-task! "Dep B" 'blocked-by (list a))]
              [c (add-task! "Dep C" 'blocked-by (list (task-id b) (task-label a)
                                                      (task-id b)))]
              [refused (lambda (x ids)
                         (guard (e [#t (condition->string e)])
                           (set-task! x 'blocked-by ids)))]
              [cycle (lambda ts
                       (format "Exception in set-task!: ~a would wait for \
                                itself: ~a (each waits for the next)"
                               (task-label (car ts))
                               (string-join (map task-label ts) " → ")))])
         (let ([ok (and (equal? (task-blocked-by c) (map task-id (list b a)))
                        (equal? (task-blockers c) (list b a))
                        (equal? (task-blocks a) (list b c))
                        (null? (task-blocks c))
                        (equal? (refused a (list c)) (cycle a c b a))
                        (equal? (refused a (list a)) (cycle a a))
                        (null? (task-blocked-by a))
                        (raises? (lambda () (set-task! a 'blocked-by '(0))))
                        (raises? (lambda () (set-task! a 'blocked-by 3)))
                        (begin (delete-task! b)
                               (and (equal? (task-blocked-by c)
                                            (list (task-id a)))
                                    (equal? (task-blocks a) (list c)))))])
           (for-each delete-task! (list a c))
           ok)))

;; Makes up tasks, each from a spec of its id followed by the ids it waits
;; for.
(define (linked . specs)
  (map (lambda (s)
         (let ([t (mk (car s) (format "T~a" (car s)) 'todo 'bug 'low #f '()
                      #f)])
           (task-blocked-by-set! t (cdr s))
           t))
       specs))

(check "tasks-forest: the roots are the tasks nothing waits for, then any \
        cycle left over; a blocker shared by several shows its own under \
        the first, depth first; tasks-cycle finds the path back"
       (let ([ts (linked '(1 2 3) '(2) '(3 5) '(4 3) '(5) '(6) '(7 8) '(8 7))])
         (let-values ([(roots homes order) (tasks-forest ts)])
           (let ([by-id (tasks-id-table ts)])
             (and (equal? roots '(1 4 6 7))
                  (equal? order '(1 2 3 5 4 6 7 8))
                  (equal? (map (lambda (id) (hashtable-ref homes id 'none))
                               '(1 2 3 5 4 6 7 8))
                          '(#f 1 1 3 #f #f #f 7))
                  (equal? (ids (tasks-cycle by-id (list-ref ts 2) '(4)))
                          '(3 4 3))
                  (equal? (ids (tasks-cycle by-id (list-ref ts 4) '(1)))
                          '(5 1 3 5))
                  (not (tasks-cycle by-id (car ts) '(6)))
                  (equal? (sort < (vector->list
                                   (hashtable-keys
                                    (tasks-waiters (tasks-inverse ts)
                                                   (list-ref ts 4)))))
                          '(1 3 4))
                  (equal? (ids (hashtable-ref (tasks-inverse ts) 3 '()))
                          '(1 4)))))))

(check "the backlog's links: no cycle; (tasks-tree) nests what each task waits \
        for, a shared blocker under its first waiter and its id under the \
        others; Add offers what would make no cycle, nor is done"
       (let ([tree (tasks-tree)] [choices (map task-id (tasks-blocker-choices
                                                       (find-task 14)))])
         (let-values ([(roots homes order)
                       (tasks-forest (tasks-board-order *tasks*))])
           (and (= (length order) (length *tasks*))
                (for-all (lambda (id) (null? (task-blocks id))) roots)
                (equal? (assv 11 tree) '(11 (9)))
                (equal? (assv 13 tree) '(13 (31) (10)))
                (equal? (assv 17 tree) '(17 31))
                (equal? (assv 22 tree) '(22 (14 (33 9))))
                (equal? (assv 15 tree) '(15 (32)))
                (not (find (lambda (id) (memv id '(14 22 33 1 32))) choices))
                (memv 9 choices) (memv 16 choices) #t))))

(check "what is worked out from which tasks there are, their order, \
        statuses and links is kept while only a title or a description \
        changes, and worked out again when a link or a status does"
       (let* ([forest (tasks-whole-forest)] [order (tasks-ordered)]
              [kept? (begin (set-task! 13 'title "Kept" 'description "x")
                            (and (eq? forest (tasks-whole-forest))
                                 (eq? order (tasks-ordered))))]
              [linked (begin (set-task! 16 'blocked-by '(12))
                             (tasks-whole-forest))]
              [blocks (task-blocks 12)])
         (set-task! 16 'blocked-by '())
         (let* ([moved (begin (set-task! 16 'status 'review) (tasks-ordered))]
                [ok (and kept? (not (eq? linked forest))
                         (memq (find-task 16) blocks) (not (eq? moved order))
                         (eq? (find-task 16)
                              (car (last-pair (tasks-in 'review moved)))))])
           (test-backlog!)
           ok)))

(check "Add's menu: the choices whose id or title holds what was typed, \
        the one it names by id first, as many as there is room for, the \
        last saying how many more"
       (let* ([cs (map (lambda (i)
                         (mk (+ 1 i) (format "Chain ~a" (- 30 i)) 'todo
                             'feature 'normal #f '() #f))
                       (iota 30))]
              [picked #f]
              [labels (lambda (f room)
                        (map car (tasks-blocker-entries
                                  cs f room (lambda (c) (set! picked c)))))])
         (and (equal? (labels "" 4)
                      '("TASK-1  Chain 30" "TASK-2  Chain 29" "TASK-3  Chain 28"
                        "… 27 more: type to narrow"))
              (equal? (labels "chain 2" 3)
                      '("TASK-2  Chain 29" "TASK-3  Chain 28"
                        "… 9 more: type to narrow"))
              (equal? (labels "task-12" 30) '("TASK-12  Chain 19"))
              (equal? (labels "20" 3)
                      '("TASK-20  Chain 11" "TASK-11  Chain 20"))
              (null? (labels "zz" 5))
              (let ([pick (cdar (tasks-blocker-entries
                                 cs "TASK-7" 5 (lambda (c) (set! picked c))))])
                (pick)
                (eq? picked (list-ref cs 6))))))

;; Returns what thunk draws as text, as ((x . string) ...), in order.
(define (texts-drawn thunk)
  (let ([drawn '()] [plain draw-text])
    (dynamic-wind
      (lambda ()
        (set! draw-text (lambda (x y s . more)
                          (set! drawn (cons (cons x s) drawn))
                          (apply plain x y s more))))
      (lambda () (image 400 40 1 thunk))
      (lambda () (set! draw-text plain)))
    (reverse drawn)))
(define (strings-drawn thunk) (map cdr (texts-drawn thunk)))

(check "four-digit ids keep clear of the titles in the Tree, three digits \
        wide at least"
       (let ([next *tasks-next-id*] [t (find-task 31)])
         (define (room)   ; from the id's start to the title's
           (let ([texts (texts-drawn
                         (lambda () (tasks-draw-node 0 0 400 30 '() t #f)))])
             (- (car (cadr texts)) (car (car texts)))))
         (let ([two (room)])
           (set! *tasks-next-id* 1234)
           (let* ([new (add-task! "Four digits")] [wide (room)])
             (delete-task! new)
             (set! *tasks-next-id* next)
             (and (= two (+ 8 (text-width "TASK-000" 'mono-small)))
                  (>= wide (+ 8 (text-width "TASK-1234" 'mono-small)))
                  (= (room) two))))))

(check "a later row's title keeps at least half its room: the note where \
        its own row is gets shorter, then goes, as the cell narrows"
       (let* ([t (find-task 31)] [title (tasks-shown-title t)]
              [long (text-width "↑ under TASK-13" 'ui-small)]
              [short (text-width "↑ TASK-13" 'ui-small)]
              [w (lambda (room)   ; the cell's width for that room
                   (+ room (* 2 (ui-table-cell-inset)) 8
                      (text-width "TASK-100" 'mono-small)))]   ; the backlog's
              [shown (lambda (room)   ; returns (title-shown note ...)
                       (cdr (strings-drawn
                             (lambda ()
                               (tasks-draw-node 0 0 (w room) 30 '(reference)
                                                t "TASK-13")))))]
              [rooms (list 1000 (+ long short 16) (+ short 8))]
              [all (map shown rooms)])
         (and (equal? (map cdr all)
                      '(("↑ under TASK-13") ("↑ TASK-13") ()))
              (> (text-width title 'ui) (/ (+ long short 16) 2))
              (for-all (lambda (s room)   ; short by at most what a cut takes
                         (>= (+ (text-width (car s) 'ui) (text-width "W…" 'ui))
                             (min (text-width title 'ui) (/ room 2))))
                       all rooms))))

(check "a record of task's from before a reload that changed its fields is \
        carried over by name, a new field empty"
       (let ([rtd (make-record-type-descriptor
                   'task #f 'units-old-task #f #f
                   '#((immutable id) (immutable title) (immutable checklist)
                      (immutable created)))])
         (let ([t (tasks-carried ((record-constructor
                                   (make-record-constructor-descriptor
                                    rtd #f #f))
                                  7 "Kept" '(("a" . #t)) 99))])
           (and (task? t) (= 7 (task-id t)) (equal? "Kept" (task-title t))
                (equal? '(("a" . #t)) (task-checklist t))
                (null? (task-blocked-by t)) (= 99 (task-created t))
                (eq? 'todo (task-status t)) (eq? t (tasks-carried t))))))

;; The calendar and the view's layout, at 13 and 24 px fonts.

(let ([at (lambda (key)
            (cdr (assq key (ui-calendar-areas 0 0 230 0))))])
  (set-theme! 'ui-font-size 24)
  (let-values ([(cw ch) (ui-calendar-size)])
    (let ([prev (at 'prev)] [week (at 'week)] [today (at 'today)])
      (set-theme! 'ui-font-size 13)
      (check "the calendar at 24 px fonts: the weekdays below its arrows, \
              Today inside it"
             (and (>= (cadr week) (+ (cadr prev) (cadddr prev)))
                  (<= (+ (cadr today) (cadddr today)) ch))))))

(let ([v (tasks-view-new (make-ui))])
  (define (mode w) (call-with-values (lambda () (tasks-layout v w 700 44))
                     (lambda (m view details) m)))
  ;; returns (wide-width wide-at-it? narrow-below?)
  (define (layout)
    (let ([w (tasks-wide-width v)])
      (list w (eq? (mode w) 'wide) (eq? (mode (- w 1)) 'narrow))))
  (let* ([board (layout)]
         [list-view (begin (tasks-view-mode-set! v 'list) (layout))]
         [at-24 (begin (tasks-view-mode-set! v 'board)
                       (set-theme! 'ui-font-size 24)
                       (layout))])
    (set-theme! 'ui-font-size 13)
    (check "tasks-layout: the details beside the view from tasks-wide-width \
            on, narrow below it; the List's narrower than the Board's, and \
            both greater at 24 px fonts than at 13"
           (and (for-all (lambda (l) (and (cadr l) (caddr l)))
                         (list board list-view at-24))
                (< (car list-view) (car board))
                (> (car at-24) (car board))))))

;; A keystroke in TASK-13's description, with Tasks maximized and a long
;; title on TASK-10, which 13 and others wait for (cards, rows and tooltips
;; fit its title): the number of characters it measures does not grow with
;; that title.
(let* ([w (tasks)] [v (window-ref w 'state)] [ui (window-ref w 'ui)])
  (define (measured mode title)
    (set-task! 10 'title title)
    (set-task! 13 'description "")
    (tasks-view-mode-set! v mode)
    (tasks-select! v (find-task 13))
    (ui-focus! ui 'description 0)
    (invalidate! w)
    (steps 3)
    (characters-measured (lambda () (inject! '(text "a")) (steps 1))))
  (maximize-window! w)
  (steps 2)
  (let ([counts (map (lambda (mode)
                       (map (lambda (make) (measured mode (make 10000)))
                            (list words-of (lambda (n) (make-string n #\W))
                                  (lambda (n) (words-of (* 10 n)))
                                  (lambda (n) (make-string (* 10 n) #\W)))))
                     '(board list tree))])
    (test-backlog!)
    (close-window! w)
    (steps 2)
    (check (format "a keystroke in Tasks measures as many characters with a \
                    100,000-character title on a task others wait for as \
                    with one of 10,000, in the Board, the List and the Tree, \
                    words or one long word: ~a" counts)
           (for-all (lambda (c) (and (= (car c) (caddr c))
                                     (= (cadr c) (cadddr c))))
                    counts))))

;;; The view's keys and commands, with no window: a view of the test's own
;;; over the backlog.

(test-backlog!)
(let ([v (tasks-view-new (make-ui))])
  (define (key! k . mods) (tasks-key v k mods))
  (define (column status) (tasks-in status (tasks-visible v)))
  (define (rows) (tasks-rows v (tasks-visible v)))
  (define (place t) (tasks-index t (column (task-status t))))

  (check "the Board's keys: Down selects the next card of its column; \
          Shift+Right moves the selected task to the next status, Shift+Up \
          up its column; Escape lets go of it"
         (let* ([t (find-task 13)]
                [next (cadr (memq t (column 'todo)))])
           (tasks-select! v t)
           (key! 'down)
           (let ([down (tasks-view-selected v)])
             (key! 'right 'shift)
             (let ([status (task-status next)] [before (place next)])
               (key! 'up 'shift)
               (let ([after (place next)])
                 (key! 'escape)
                 (and (eq? down next) (eq? status 'doing)
                      (= after (max 0 (- before 1)))
                      (not (tasks-view-selected v))))))))

  (check "v goes from the Board to the List, the Tree and the Board again; \
          a heading sorts the List by it, then the other way, then in board \
          order; Down twice selects its second row"
         (begin
           (tasks-text v "v")
           (let* ([listed (tasks-view-mode v)]
                  [up (begin (tasks-sort-by! v 'priority)
                             (task-priority (car (rows))))]
                  [down (begin (tasks-sort-by! v 'priority)
                               (task-priority (car (rows))))]
                  [board (begin (tasks-sort-by! v 'priority)
                                (tasks-view-sort v))])
             (key! 'down)
             (key! 'down)
             (let ([second (tasks-view-selected v)])
               (tasks-select! v #f)
               (tasks-text v "v")
               (let ([tree (tasks-view-mode v)])
                 (tasks-text v "v")
                 (and (eq? listed 'list) (eq? up 'urgent) (eq? down 'low)
                      (not board) (eq? second (cadr (rows)))
                      (eq? tree 'tree) (eq? (tasks-view-mode v) 'board)))))))

  (check "Clear leaves no search or filter; with Show done off there is no \
          Done column, and Shift+Right into it selects the task next to \
          the one moved"
         (begin
           (tasks-view-query-set! v "sdl")
           (tasks-view-kind-set! v 'bug)
           (let ([some (length (tasks-visible v))])
             (tasks-clear-filters! v)
             (let ([all (length (tasks-visible v))])
               (tasks-view-done?-set! v #f)
               (let* ([columns (map car (tasks-columns v (tasks-visible v)))]
                      [review (column 'review)]
                      [t (car review)] [beside (cadr review)])
                 (tasks-select! v t)
                 (key! 'right 'shift)
                 (let ([status (task-status t)] [sel (tasks-view-selected v)])
                   (tasks-clear-filters! v)
                   (tasks-select! v #f)
                   (and (< some all) (= all (length *tasks*))
                        (not (tasks-filtered? v))
                        (not (memq 'done columns)) (memq 'todo columns)
                        (eq? status 'done) (eq? sel beside))))))))

  (check "Duplicate: a copy right after it, waiting for what it waits for; \
          Delete asks first, and deleting it selects the task next to it"
         (let* ([t (find-task 13)] [n (length *tasks*)]
                [c (tasks-duplicate! t)])
           (tasks-select! v c)
           (key! 'delete)
           (let ([asked (eq? (tasks-view-confirm v) c)]
                 [after (eq? (cadr (memq t *tasks*)) c)])
             (tasks-delete! v c)
             (let ([sel (tasks-view-selected v)])
               (tasks-select! v #f)
               (and after asked
                    (equal? (task-title c)
                            (string-append (task-title t) " (copy)"))
                    (equal? (task-blocked-by c) (task-blocked-by t))
                    (= (length *tasks*) n) (not (memq c *tasks*))
                    (not (tasks-view-confirm v))
                    sel (eq? (task-status sel) (task-status t)))))))

  (check "a task done while it still waits for others says so in a toast, \
          naming them, and so does one added done; one that waits for \
          nothing says nothing"
         (let ([said (lambda (thunk)
                       (set! *toasts* '())
                       (thunk)
                       (let ([texts (map (lambda (x) (vector-ref x 1))
                                         *toasts*)])
                         (set! *toasts* '())
                         texts))])
           (let* ([moved (said (lambda () (move-task! 22 'done)))]
                  [born #f]
                  [added (said (lambda ()
                                 (set! born (add-task! "Born done" 'status 'done
                                                       'blocked-by '(10)))))]
                  [free (said (lambda () (move-task! 16 'done)))])
             (and (equal? moved
                          '("TASK-22 is done, though it waits for TASK-14"))
                  (equal? added
                          (list (format "~a is done, though it waits for \
                                         TASK-10"
                                        (task-label born))))
                  (null? free))))))
(test-backlog!)

;;; What the view shows of a task, with no window: its tips, its cut
;;; titles, the toolbar's widths, a filter's label, the empty states.

;; Draws thunk into a w × h image as a window's draw would, laying out v's
;; ui.
(define (tasks-test-draw v w h thunk)
  (let ([ui (tasks-view-ui v)])
    (picture-free!
     (image w h 1 (lambda () (ui-begin! ui) (thunk) (ui-end! ui w h))))))

(let* ([v (tasks-view-new (make-ui))] [ui (tasks-view-ui v)])
  (check "a card's title is at most three rows, cut past them; a tip is the \
          title when it's cut, what the task waits for while it's blocked, \
          both then, else none; a row's title is cut by its room, measured"
         (let* ([w 200] [room (- w (* 2 (ui-card-pad)))]
                [long (let grow ([s "W"])
                        (if (> (text-width s 'ui) (* 4 room))
                            s
                            (grow (string-append s "W"))))]
                [cut (mk 900 (string-append "A " long) 'todo 'bug 'low #f '()
                         #f)]
                [short (mk 901 "Short" 'todo 'bug 'low #f '() #f)]
                [blocked (find-task 13)]
                [waits (tasks-tip blocked #f)]
                [wide (text-width (task-title cut) 'ui)])
           (let-values ([(lines cut?) (tasks-card-title w cut)]
                        [(lines1 cut1?) (tasks-card-title w short)])
             (and (= (length lines) 3) cut? (= (length lines1) 1) (not cut1?)
                  (equal? (tasks-tip cut #t) (task-title cut))
                  (not (tasks-tip short #f))
                  (string-prefix? "Blocked by TASK-31 " waits)
                  (string-contains-ci? waits ", TASK-10 ")
                  (equal? (tasks-tip blocked #t)
                          (string-append (task-title blocked) "\n" waits))
                  (not (tasks-tip (find-task 12) #f))
                  (tasks-title-cut? cut (quotient wide 2))
                  (not (tasks-title-cut? cut (+ wide 1)))))))

  (check "what a task holds moves nothing in the toolbar: its items are as \
          wide with a long tag and a long name as without; a name quoted in \
          a menu or a message is 20 line heights wide at most"
         (let* ([widths (lambda ()
                          (map car (tasks-toolbar-items v (tasks-visible v))))]
                [before (widths)]
                [name (apply string-append (make-list 20 "Grace Hopper "))])
           (set-task! 13 'tags '("render" "a-much-longer-tag-name"))
           (set-task! 9 'assignee name)
           (let ([long (widths)])
             (test-backlog!)
             (and (equal? before long)
                  (<= (text-width (tasks-quoted name) 'ui)
                      (* 20 (font-line-height 'ui)))
                  (<= (text-width (tasks-quoted (make-string 150 #\q)) 'ui)
                      (* 20 (font-line-height 'ui)))
                  (equal? (tasks-quoted "Ada") "Ada")))))

  (check "a filter whose value no task has any more still shows it"
         (let ([shown #f] [plain ui-draw-dropdown])
           (fluid-let ([ui-draw-dropdown
                        (lambda (x y w h flags label)
                          (set! shown label)
                          (plain x y w h flags label))])
             (tasks-test-draw v 300 60
               (lambda ()
                 (tasks-filter v 10 10 160 30 'tag "Tag" "gone"
                               (lambda (v new) #f)
                               '(("Any tag" . #f)) '(("ui" . "ui"))))))
           (equal? shown "gone")))

  (check "another task selected starts from its top, its drafts empty; the \
          same one keeps where it was"
         (begin
           (tasks-select! v (find-task 13))
           (ui-memo! ui 'description 120)
           (tasks-view-tag-draft-set! v "dra")
           (tasks-select! v (find-task 13))
           (let ([kept (list (ui-memo ui 'description 0)
                             (tasks-view-tag-draft v))])
             (tasks-select! v (find-task 14))
             (let ([fresh (list (ui-memo ui 'description 0)
                                (tasks-view-tag-draft v))])
               (tasks-select! v #f)
               (and (equal? kept '(120 "dra")) (equal? fresh '(0 "")))))))

  (check "the empty states: a search that matches nothing offers to clear \
          it; no tasks at all, to make one"
         (let ([offers (lambda ()
                         (tasks-test-draw
                          v 600 400 (lambda () (tasks-empty v 0 0 600 400)))
                         (list (and (ui-find ui 'empty-clear) #t)
                               (and (ui-find ui 'empty-new) #t)))])
           (tasks-view-query-set! v "nothing-like-this")
           (let ([none-match (offers)])
             (tasks-clear-filters! v)
             (for-each delete-task! (map task-id *tasks*))
             (let ([none (offers)])
               (test-backlog!)
               (and (equal? none-match '(#t #f)) (equal? none '(#f #t))))))))

;;; The Tree's selection, with no window.

(let ([v (tasks-view-new (make-ui))])
  (tasks-view-mode-set! v 'tree)
  (check "the Tree's selection: a later row picked is where it is, and \
          opened there it goes to the task's own row; a later row a change \
          takes away falls back to the task's own"
         (begin
           (tasks-pick! v '(17 . 31))
           (let ([picked (list (task-id (tasks-view-selected v))
                               (tasks-tree-node v))])
             (tasks-tree-open! v '(17 . 31))
             (let ([opened (list (task-id (tasks-view-selected v))
                                 (tasks-tree-node v))])
               (tasks-pick! v '(17 . 31))
               ;; with 17 first in board order, 31's own row is under it
               (move-task! 13 'doing)
               (let ([fell (tasks-tree-node v)])
                 (tasks-select! v #f)
                 (test-backlog!)
                 (and (equal? picked '(31 (17 . 31)))
                      (equal? opened '(31 31))
                      (equal? fell 31)))))))

  (check "a task deleted in the Tree: what waited for it waits no more, and \
          the row after it is selected"
         (let* ([shared (add-task! "Shared" 'status 'todo)]
                [a (add-task! "Waits A" 'blocked-by (list shared))]
                [b (add-task! "Waits B" 'blocked-by (list shared))])
           (tasks-select! v shared)
           (tasks-delete! v shared)
           (let ([sel (tasks-view-selected v)])
             (tasks-select! v #f)
             (let ([ok (and (not (memq shared *tasks*))
                            (null? (task-blocked-by a))
                            (null? (task-blocked-by b)) (eq? sel b))])
               (test-backlog!)
               ok)))))
