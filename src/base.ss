;;; base.ss — small utilities shared by everything else.

;; The thread that loads the core is the main thread. The world's state is
;; its alone, and so is SDL: a worker runs only worklets
;; (proc.ss), where neither can be named.
(define main-thread?
  (if (threaded?)
      (let ([id (get-thread-id)]) (lambda () (fx= (get-thread-id) id)))
      (lambda () #t)))

;; State variables that must survive (reload!) are declared with defvar,
;; like in Emacs: the initial value is only used if the name is unbound.
(define-syntax defvar
  (syntax-rules ()
    [(_ name init)
     (define name (if (top-level-bound? 'name) (top-level-value 'name) init))]))

;; The environment the world lives in. Lookups by name go here, not to
;; (interaction-environment), which a private REPL rebinds.
(defvar *world-env* (interaction-environment))

;; The monotonic clock in ns, a fixnum: what the profiler times with.
(define (now-ns) (sdl-get-ticks-ns))

;; The same clock in ms: what apps and timers go by. It reads the clock
;; itself, so a test can fake either without moving the other.
(define (now-ms) (quotient (sdl-get-ticks-ns) 1000000))

(define (clamp x lo hi) (max lo (min hi x)))

(define (string-split str ch)
  (let loop ([i 0] [start 0] [acc '()])
    (cond
      [(= i (string-length str)) (reverse (cons (substring str start i) acc))]
      [(char=? (string-ref str i) ch)
       (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))]
      [else (loop (+ i 1) start acc)])))

(define (string-join strs sep)
  (if (null? strs)
      ""
      (apply string-append (car strs)
             (map (lambda (s) (string-append sep s)) (cdr strs)))))

(define (string-prefix? prefix str)
  (and (<= (string-length prefix) (string-length str))
       (string=? prefix (substring str 0 (string-length prefix)))))

(define (string-suffix? suffix str)
  (let ([n (string-length str)] [m (string-length suffix)])
    (and (<= m n) (string=? suffix (substring str (- n m) n)))))

;; map, keeping only the true results.
(define (filter-map f l)
  (fold-right (lambda (x acc) (let ([y (f x)]) (if y (cons y acc) acc))) '() l))

;; Compared in place, a character at a time: a long str costs no copies.
(define (string-contains-ci? str sub)
  (let ([n (string-length str)] [m (string-length sub)])
    (define (at? i j)   ; sub from j on is in str at i + j
      (or (= j m)
          (and (char-ci=? (string-ref str (+ i j)) (string-ref sub j))
               (at? i (+ j 1)))))
    (let loop ([i 0]) (and (<= (+ i m) n) (or (at? i 0) (loop (+ i 1)))))))

(define (truncate-string s n)
  (if (<= (string-length s) n)
      s
      (string-append (substring s 0 (max 0 (- n 1))) "…")))

;; Property lists: '(key val key val ...)
(define (plist-ref plist key default)
  (cond
    [(or (null? plist) (null? (cdr plist))) default]
    [(eq? (car plist) key) (cadr plist)]
    [else (plist-ref (cddr plist) key default)]))

(define (plist-keys plist)
  (if (or (null? plist) (null? (cdr plist)))
      '()
      (cons (car plist) (plist-keys (cddr plist)))))

(define (condition->string c)
  (call-with-string-output-port
   (lambda (p)
     (if (condition? c)
         (display-condition c p)
         (fprintf p "non-condition raised: ~s" c)))))

(define (list-index pred lst)
  (let loop ([l lst] [i 0])
    (cond [(null? l) #f] [(pred (car l)) i] [else (loop (cdr l) (+ i 1))])))

;; A registry (apps, styles, palettes, wallpapers) is a list in
;; first-registration order. An entry whose name is already there replaces
;; that entry in place. name-of gives an entry's name.
(define (registry-add entries entry name-of)
  (let ([name (name-of entry)])
    (if (exists (lambda (e) (eq? (name-of e) name)) entries)
        (map (lambda (e) (if (eq? (name-of e) name) entry e)) entries)
        (append entries (list entry)))))

;; The CPU time this thread has had, in ns: a number, read into memory
;; kept for it, so that reading it allocates nothing. The clock's number is
;; the system's.
(define thread-cpu-clock
  (if (string-contains-ci? (symbol->string (machine-type)) "osx") 16 3))
(define thread-cpu-time (foreign-alloc 16))   ; a timespec
(define (thread-cpu-ns)
  (c-clock-gettime thread-cpu-clock thread-cpu-time)
  (+ (* 1000000000 (foreign-ref 'long thread-cpu-time 0))
     (foreign-ref 'long thread-cpu-time 8)))
