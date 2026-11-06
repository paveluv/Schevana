;;; tests/units/tasks.ss — Tasks' own procedures with no window, and its
;;; window.

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
       (let ([fits?
              (lambda (w tags)
                (let-values ([(ws k) (tasks-card-tags
                                      w (mk 6 "x" 'todo 'bug 'low #f tags #f))])
                  (and (pair? ws) (= (+ (length ws) k) (length tags))
                       (<= (+ (apply + ws) (* 4 (- (length ws) 1))
                              (if (> k 0)
                                  (+ 4 (text-width (format "+~a" k)
                                                   'ui-small))
                                  0))
                           (- w 20))
                       (list (length ws) k))))])
         (and (equal? (fits? 200 '("ui" "kit")) '(2 0))
              (equal? (fits? 145 '("abcdefghijkl" "abcdefgh" "b")) '(1 2))
              (equal? (fits? 200 '("abcdefghijklmnopqrstuvwx" "b")) '(1 1))
              (equal? (fits? 100 '("abcdefghijklmnopqrstuvwx")) '(1 0)))))

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

(check "the seed's long descriptions: the README and the kit's source \
        cut to the most, the backlog as one paragraph and a base64 \
        blob with no spaces, the same at every seeding; with the files \
        gone, the paragraph"
       (let* ([text (lambda (what) (tasks-seed-text what))]
              [readme (call-with-input-file
                        (string-append *schevana-root* "/README.md")
                        get-string-all)]
              [has? (lambda (s c)
                      (exists (lambda (i) (char=? (string-ref s i) c))
                              (iota (string-length s))))]
              [blob (text 'blob)] [paragraph (text 'changelog)]
              [gone (fluid-let ([*schevana-root* "/no/such/tree"])
                      (text 'readme))])
         (and (equal? (text 'readme)
                      (substring readme 0 (min (string-length readme)
                                               tasks-description-max)))
              (= 65536 (string-length (text 'kit-source)))
              (= 65536 (string-length paragraph) (string-length blob))
              (not (has? paragraph #\newline)) (not (has? blob #\space))
              (string-prefix? "Ozs7IGtpdHMvdWkuc3M" blob)   ; ";;; kits/ui.ss"
              (equal? blob (text 'blob)) (equal? gone paragraph)
              (for-all (lambda (id)
                         (<= (string-length (task-description (find-task id)))
                             tasks-description-max))
                       '(27 28 29 30)))))

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

;; Made-up tasks: id, then the ids it waits for.
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

(check "the seed's links: no cycle; (tasks-tree) nests what each task waits \
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
           (tasks-reset!)
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

;; What a draw by thunk shows as text: ((x . string) ...), in order.
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
         (let ([seed (room)])
           (set! *tasks-next-id* 1234)
           (let* ([new (add-task! "Four digits")] [wide (room)])
             (delete-task! new)
             (set! *tasks-next-id* next)
             (and (= seed (+ 8 (text-width "TASK-000" 'mono-small)))
                  (>= wide (+ 8 (text-width "TASK-1234" 'mono-small)))
                  (= (room) seed))))))

(check "a later row's title keeps at least half its room: the note where \
        its own row is gets shorter, then goes, as the cell narrows"
       (let* ([t (find-task 31)] [title (tasks-shown-title t)]
              [long (text-width "↑ under TASK-13" 'ui-small)]
              [short (text-width "↑ TASK-13" 'ui-small)]
              [w (lambda (room)   ; the cell's width for that room
                   (+ room (* 2 (ui-table-cell-inset)) 8
                      (text-width "TASK-100" 'mono-small)))]   ; the seed's
              [shown (lambda (room)   ; => (title-shown note ...)
                       (cdr (strings-drawn
                             (lambda ()
                               (tasks-draw-node 0 0 (w room) 30 '(reference)
                                                t "TASK-13")))))]
              [rooms (list 1000 (+ long short 16) (+ short 8))]
              [all (map shown rooms)])
         (and (equal? (map cdr all)
                      '(("↑ under TASK-13") ("↑ TASK-13") ()))
              (> (text-width title 'ui) (/ (+ long short 16) 2))
              (for-all (lambda (s room)   ; less at most what a cut takes
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

;; A tree of symbols: what each has under it.

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
  (let ([at-13 (list (mode 1205) (mode 760))])
    (set-theme! 'ui-font-size 24)
    (let ([at-24 (list (mode 1205) (mode 2400))])
      (set-theme! 'ui-font-size 13)
      (check "tasks-layout: the details beside the view when they fit, at 13 \
              and 24 px fonts"
             (equal? (list at-13 at-24) '((wide narrow) (narrow wide)))))))

;; A keystroke in 13's description, Tasks maximized, with a long title on
;; TASK-10, which 13 and others wait for (cards, rows and tooltips fit its
;; title): the characters it measures do not grow with that title.
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
    (tasks-reset!)
    (close-window! w)
    (steps 2)
    (check (format "a keystroke in Tasks measures as many characters with a \
                    100,000-character title on a task others wait for as \
                    with one of 10,000, in the Board, the List and the Tree, \
                    words or one long word: ~a" counts)
           (for-all (lambda (c) (and (= (car c) (caddr c))
                                     (= (cadr c) (cadddr c))))
                    counts))))
