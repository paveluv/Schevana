;;; tests/chez.ss — a suite's own run of Chez, through /bin/sh: a units
;;; topic, a forked world, the sources' suite again. It leans on nothing of
;;; the tree, so a suite loads it before the world, right after it has
;;; found the tree's root:
;;;
;;;   (load (string-append *schevana-root* "/tests/chez.ss"))
;;;   (system (test-chez '(("NAME" . "value")) script arg ...))

;; s as one word of /bin/sh's, whatever it holds.
(define (test-sh-word s)
  (let ([o (open-output-string)])
    (put-char o #\')
    (string-for-each
      (lambda (c) (if (char=? c #\') (put-string o "'\\''") (put-char o c)))
      s)
    (put-char o #\')
    (get-output-string o)))

;; The loader's variables that macOS drops on the way into /bin/sh: set
;; here, they're handed on by name.
(define test-loader-variables
  '("DYLD_LIBRARY_PATH" "DYLD_FALLBACK_LIBRARY_PATH"))

;; /bin/sh's command that becomes a run of Chez on script with args, with
;; env's variables, (name . value), and the loader's set. Chez is "chez"
;; where Homebrew installs it, else "scheme".
(define (test-chez env script . args)
  (format "exec env~{ ~a~} \"$(command -v chez || echo scheme)\" \
           --script~{ ~a~}"
          (map (lambda (v)
                 (string-append (car v) "=" (test-sh-word (cdr v))))
               (append env
                       (filter cdr
                               (map (lambda (name) (cons name (getenv name)))
                                    test-loader-variables))))
          (map test-sh-word (cons script args))))

;;; ------------------------------------------------------------------ at once
;;; Runs of their own, as many at once as the machine allows: its CPUs
;;; (those this process may use), less two, and its memory, each run
;;; taking what its caller says it takes at its peak, out of what the
;;; system has free (Linux's MemAvailable, within this process's cgroup's
;;; limit: a container's; half a Mac's memory), less 1 GB for the rest of
;;; the machine. SCHEVANA_TEST_JOBS says how many instead.

;; command's exit status, or 137 if it still ran after seconds and was
;; killed, lest a hang hold up the suite. GNU's timeout isn't everywhere (a
;; Mac has none), so this is plain sh; command execs, so the process killed
;; is its own. It looks every 50 ms: a command that ends at once isn't held
;; a second.
(define (test-system-within seconds command)
  (system
    (format "(~a) & p=$!; i=0; while kill -0 $p 2> /dev/null; do \
             if [ $i -ge ~a ]; then kill -9 $p; break; fi; \
             sleep 0.05; i=$((i + 1)); done; wait $p 2> /dev/null"
            command (* seconds 20))))

;; What /bin/sh's command prints first, read as a datum; #f for none.
(define (test-sh-read command)
  (let* ([p (process command)] [x (read (car p))])
    (close-port (car p))
    (close-port (cadr p))
    (and (not (eof-object? x)) x)))

;; The CPUs this process may use.
(define (test-cpus)
  (let ([n (test-sh-read "nproc 2> /dev/null || getconf _NPROCESSORS_ONLN")])
    (if (and (fixnum? n) (> n 0)) n 1)))

;; Whether s starts with prefix.
(define (test-prefix? prefix s)
  (and (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

;; A file's first datum, or #f where it can't be read.
(define (test-file-read path)
  (guard (c [#t #f])
    (and (file-exists? path)
         (let ([x (call-with-input-file path read)])
           (and (not (eof-object? x)) x)))))

;; Linux's memory available, in MB: MemAvailable, and the room under the
;; limit of this process's cgroup and of each one it is in. #f elsewhere.
(define (test-linux-free-mb)
  (let ([available
         (guard (c [#t #f])
           (call-with-input-file "/proc/meminfo"
             (lambda (p)
               (let loop ()
                 (let ([l (get-line p)])
                   (cond [(eof-object? l) #f]
                         [(test-prefix? "MemAvailable:" l)
                          (let ([kb (read (open-input-string
                                           (substring l 13
                                                      (string-length l))))])
                            (and (fixnum? kb) (quotient kb 1024)))]
                         [else (loop)]))))))]
        [group (guard (c [#t #f])
                 (call-with-input-file "/proc/self/cgroup"
                   (lambda (p)
                     (let loop ()
                       (let ([l (get-line p)])
                         (cond [(eof-object? l) #f]
                               [(test-prefix? "0::" l)
                                (substring l 3 (string-length l))]
                               [else (loop)]))))))])
    (and available
         (let loop ([dir (and group (string-append "/sys/fs/cgroup" group))]
                    [free available])
           (if (or (not dir) (< (string-length dir) 15))
               free
               (let ([most (test-file-read (string-append dir "/memory.max"))]
                     [now (test-file-read
                           (string-append dir "/memory.current"))])
                 (loop (let ([up (path-parent dir)])
                         (and (not (string=? up dir)) up))
                       (if (and (number? most) (number? now))
                           (min free (quotient (- most now) (* 1024 1024)))
                           free))))))))

;; The memory free for runs, in MB: Linux's, else half a Mac's, else 4 GB.
(define (test-free-mb)
  (or (test-linux-free-mb)
      (let ([bytes (test-sh-read "sysctl -n hw.memsize 2> /dev/null")])
        (and (number? bytes) (quotient bytes (* 2 1024 1024))))
      4096))

;; How many runs of mb at their peak go at once; one where Chez has no
;; threads.
(define (test-jobs mb)
  (let ([given (string->number (or (getenv "SCHEVANA_TEST_JOBS") ""))])
    (cond
      [(not (threaded?)) 1]
      [(and (fixnum? given) (> given 0)) given]
      [else (max 1 (min (- (test-cpus) 2)
                        (quotient (- (test-free-mb) 1024) mb)))])))

;; Each of commands run as test-system-within runs one, given seconds, as
;; many at once as jobs. report, if given, has each one's index and status
;; in order, as soon as it and those before it are done. => the statuses,
;; in order.
(define (test-system-all jobs seconds commands . report)
  (let* ([v (list->vector commands)] [n (vector-length v)]
         [status (make-vector n #f)] [next 0]
         [m (make-mutex)] [done (make-condition)])
    (define (work!)
      (let ([i (with-mutex m (let ([i next]) (set! next (+ i 1)) i))])
        (when (< i n)
          (let ([s (test-system-within seconds (vector-ref v i))])
            (with-mutex m
              (vector-set! status i s)
              (condition-broadcast done)))
          (work!))))
    (if (= jobs 1)
        (work!)
        (do ([k 0 (+ k 1)]) ((= k (min jobs n)))
          (fork-thread work!)))
    (let loop ([i 0])
      (when (< i n)
        (let ([s (with-mutex m
                   (let wait ()
                     (or (vector-ref status i)
                         (begin (condition-wait done m) (wait)))))])
          (when (pair? report) ((car report) i s))
          (loop (+ i 1)))))
    (vector->list status)))

;; The tree's libraries compiled once into the cache a suite's runs use,
;; and the launcher's, which the launchers they run use, before the runs
;; start at once (tests/warm.ss): both at once.
(define (test-warm!)
  (test-system-all
   2 1800
   (map (lambda (args)
          (format "~a > /dev/null 2>&1"
                  (apply test-chez '()
                         (string-append *schevana-root* "/tests/warm.ss")
                         args)))
        '(() ("tests")))))
