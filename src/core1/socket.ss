;;; socket.ss — local sockets, for what talks to the world from outside (the
;;; Debug REPL's): a Unix socket at a path only this user can reach. Nothing
;;; here waits: a read or a write asks poll first and does no more than will
;;; go at once. A socket is its file descriptor.

;; sockaddr_un, as Linux and macOS share it: on macOS the first byte is the
;; length and the second the family, which family below folds into one.
(define-ftype socket-sockaddr
  (struct [family unsigned-16] [path (array 104 unsigned-8)]))
(define-ftype socket-pollfd (struct [fd int] [events short] [revents short]))
(defvar *socket-memory*
  (foreign-alloc (+ (ftype-sizeof socket-sockaddr)
                    (ftype-sizeof socket-pollfd))))
(define socket-sockaddr* (make-ftype-pointer socket-sockaddr *socket-memory*))
(define socket-pollfd*
  (make-ftype-pointer socket-pollfd
                      (+ *socket-memory*
                         (ftype-sizeof socket-sockaddr))))
;; a write's most at once: poll's "writable" means this much goes unblocked
(define socket-chunk 2048)
(defvar *socket-chunk* (make-bytevector socket-chunk))

;; The address of path, in the memory above. => its length
(define (socket-address! path)
  (let* ([bytes (string->utf8 path)] [n (bytevector-length bytes)]
         [length (+ n 3)] [a socket-sockaddr*])
    (unless (< n 104) (errorf 'socket-address! "too long a path: ~a" path))
    (ftype-set! socket-sockaddr (family) a
                (if (platform-mac?)
                    (+ 256 length)
                    1))
    (do ([i 0 (+ i 1)]) ((= i n))
      (ftype-set! socket-sockaddr (path i) a (bytevector-u8-ref bytes i)))
    (ftype-set! socket-sockaddr (path n) a 0)
    length))

;; A socket listening at path, which only this user can reach; what was there
;; before goes, unless it's a plain file. A client that goes away must fail a
;; write, not end the world: SIGPIPE is ignored from now on.
(define (socket-listen path)
  (c-signal 13 1)
  (when (file-exists? path)
    (when (file-regular? path)
      (errorf 'socket-listen "there's a file at ~a" path))
    (delete-file path))
  (let ([fd (c-socket 1 1 0)]   ; AF_UNIX, SOCK_STREAM
        [length (socket-address! path)])
    (when (< fd 0) (errorf 'socket-listen "no socket"))
    (unless (and (zero? (c-bind fd (ftype-pointer-address socket-sockaddr*)
                                length))
                 (begin (chmod path #o600) (zero? (c-listen fd 8))))
      (c-close fd)
      (errorf 'socket-listen "can't listen at ~a" path))
    fd))

;; A socket connected to path, or #f.
(define (socket-connect path)
  (let* ([length (socket-address! path)] [fd (c-socket 1 1 0)])
    (if (and (>= fd 0)
             (zero? (c-connect fd (ftype-pointer-address socket-sockaddr*)
                               length)))
        fd
        (begin (when (>= fd 0) (c-close fd)) #f))))

;; Would events (poll's: 1, in; 4, out) go at once, or has it ended?
(define (socket-ready? fd events)
  (let ([p socket-pollfd*])
    (ftype-set! socket-pollfd (fd) p fd)
    (ftype-set! socket-pollfd (events) p events)
    (ftype-set! socket-pollfd (revents) p 0)
    (and (> (c-poll (ftype-pointer-address p) 1 0) 0)
         (not (zero? (ftype-ref socket-pollfd (revents) p))))))

;; A client waiting at listening socket fd, as a socket of its own, or #f.
(define (socket-accept fd)
  (and (socket-ready? fd 1)
       (let ([c (c-accept fd 0 0)]) (and (>= c 0) c))))

;; What's there into bytes: how many; 0, it has ended; #f, nothing yet.
(define (socket-read fd bytes)
  (and (socket-ready? fd 1)
       (max 0 (c-recv fd bytes (bytevector-length bytes) 0))))

;; bytes from at on, as much as goes now. => where that leaves it, or #f once
;; the other end has gone
(define (socket-write fd bytes at)
  (let loop ([at at] [left 32])
    (if (or (= at (bytevector-length bytes)) (= left 0)
            (not (socket-ready? fd 4)))
        at
        (let ([n (min socket-chunk (- (bytevector-length bytes) at))])
          (bytevector-copy! bytes at *socket-chunk* 0 n)
          (let ([sent (c-send fd *socket-chunk* n 0)])
            (and (> sent 0) (loop (+ at sent) (- left 1))))))))

;; No more will be written to fd: the other end reads to its end.
(define (socket-end-writing fd) (c-shutdown fd 1))

(define (socket-close fd) (c-close fd))
