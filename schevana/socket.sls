;;; (schevana socket) — local sockets, for programs that talk to the
;;; world from outside (the Debug REPL): a Unix socket at a path only this
;;; user can reach. Nothing here waits: a read or a write asks poll first
;;; and does no more than can go at once. A socket is its file descriptor.

(library (schevana socket)
  (export
    socket-listen socket-accept socket-read socket-write socket-close)
  (import (chezscheme)
          (schevana base)
          (schevana ffi))

  (library-layer foundation)

  ;; The C library's socket calls come with the process, already loaded.
  (define-foreign c-socket "socket" (int int int) int)
  (define-foreign c-bind "bind" (int uptr unsigned-32) int)
  (define-foreign c-listen "listen" (int int) int)
  (define-foreign c-accept "accept" (int uptr uptr) int)
  (define-foreign c-connect "connect" (int uptr unsigned-32) int)
  (define-foreign c-shutdown "shutdown" (int int) int)
  (define-foreign c-recv "recv" (int u8* size_t int) ssize_t)
  (define-foreign c-send "send" (int u8* size_t int) ssize_t)
  (define-foreign c-poll "poll" (uptr unsigned-long int) int)
  (define-foreign c-signal "signal" (int uptr) uptr)

  ;; sockaddr_un, in the layout Linux and macOS share: on macOS the first
  ;; byte is the length and the second the family, which the 16-bit family
  ;; below holds together.
  (define-ftype socket-sockaddr
    (struct [family unsigned-16] [path (array 104 unsigned-8)]))
  (define-ftype socket-pollfd (struct [fd int] [events short] [revents short]))
  (define-made *socket-memory*
    (foreign-alloc (+ (ftype-sizeof socket-sockaddr)
                      (ftype-sizeof socket-pollfd))))
  (define-made socket-sockaddr*
    (make-ftype-pointer socket-sockaddr *socket-memory*))
  (define-made socket-pollfd*
    (make-ftype-pointer socket-pollfd
                        (+ *socket-memory*
                           (ftype-sizeof socket-sockaddr))))
  ;; the most a write sends at once: "writable" from poll means this much
  ;; goes without blocking
  (define socket-chunk 2048)
  (define-made *socket-chunk* (make-bytevector socket-chunk))

  ;; Writes the address of path into the memory above. Returns its length.
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

  ;; Returns a socket listening at path, which only this user can reach.
  ;; Whatever was at path before is deleted, unless it's a plain file. A
  ;; client that goes away must make a write fail, not end the world, so
  ;; SIGPIPE is ignored from now on.
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

  ;; Returns a socket connected to path, or #f.
  (define (socket-connect path)
    (let* ([length (socket-address! path)] [fd (c-socket 1 1 0)])
      (if (and (>= fd 0)
               (zero? (c-connect fd (ftype-pointer-address socket-sockaddr*)
                                 length)))
          fd
          (begin (when (>= fd 0) (c-close fd)) #f))))

  ;; Whether events (poll's: 1 for in, 4 for out) would go at once, or the
  ;; socket has ended.
  (define (socket-ready? fd events)
    (let ([p socket-pollfd*])
      (ftype-set! socket-pollfd (fd) p fd)
      (ftype-set! socket-pollfd (events) p events)
      (ftype-set! socket-pollfd (revents) p 0)
      (and (> (c-poll (ftype-pointer-address p) 1 0) 0)
           (not (zero? (ftype-ref socket-pollfd (revents) p))))))

  ;; Returns a client waiting at the listening socket fd, as a socket of
  ;; its own, or #f.
  (define (socket-accept fd)
    (and (socket-ready? fd 1)
         (let ([c (c-accept fd 0 0)]) (and (>= c 0) c))))

  ;; Reads what's there into bytes. Returns how many bytes it read, 0 when
  ;; the socket has ended, or #f when nothing has come yet.
  (define (socket-read fd bytes)
    (and (socket-ready? fd 1)
         (max 0 (c-recv fd bytes (bytevector-length bytes) 0))))

  ;; Writes bytes from at on, as much as goes now. Returns the position it
  ;; reached, or #f once the other end has gone.
  (define (socket-write fd bytes at)
    (let loop ([at at] [left 32])
      (if (or (= at (bytevector-length bytes)) (= left 0)
              (not (socket-ready? fd 4)))
          at
          (let ([n (min socket-chunk (- (bytevector-length bytes) at))])
            (bytevector-copy! bytes at *socket-chunk* 0 n)
            (let ([sent (c-send fd *socket-chunk* n 0)])
              (and (> sent 0) (loop (+ at sent) (- left 1))))))))

  ;; Says that no more will be written to fd, so the other end reads to
  ;; the end.
  (define (socket-end-writing fd) (c-shutdown fd 1))

  (define (socket-close fd) (c-close fd)))
