;;; tests/units/later.ss — the parts of the world that load after the screen
;;; shows ((schevana core sources)): the desktop's apps wait
;;; (desktop-later?), and load in a process of their own, one after another,
;;; while the world goes on; one asked for loads at once, and only once.
;;; Once none waits or loads, a quiet step settles the world.

(check "the desktop's apps wait, libraries and files; the rest loads first"
       (and (desktop-later? '(schevana apps tasks))
            (desktop-later? "/home/me/.schevana.d/apps/weather.ss")
            (not (desktop-later? '(schevana kits ui)))
            (not (desktop-later? '(schevana desktop topbar)))
            (not (desktop-later? "src/base.ss"))))

;; (later-file name) writes a file of the test's own, which adds name to
;; later-counted in "/" each time it loads.
(define later-dir (string-append out-dir "/later"))
(unless (file-directory? later-dir) (mkdir later-dir))
(define (later-file name)
  (let ([path (string-append later-dir "/" name ".ss")])
    (call-with-output-file path
      (lambda (p)
        (write `(set! later-counted
                  (cons ',(string->symbol name) later-counted))
               p))
      'replace)
    path))
(eval '(define later-counted '()) *world-env*)
(define (later-loads) (eval 'later-counted *world-env*))

;; The waiting entries load in a process of their own, one after another;
;; one asked for before its turn loads at once, and once.
(let ([a (later-file "a")] [b (later-file "b")] [ab (later-file "ab")])
  (fluid-let ([*world-later* (list a b ab)] [*world-loading* #f]
              [*world-loader* #f])
    (world-later-start!)
    (let ([started (and (memq *world-loader* *procs*) #t)])
      (world-load-now! ab)
      (let ([now (later-loads)])
        (test-wait 10000 (lambda () (not *world-loader*)))
        (let ([after (later-loads)] [again (world-load-now! ab)])
          (check (format "the waiting entries load in a process of their \
                          own, one after another; one asked for loads at \
                          once, and once ~s"
                         (list started now after again))
                 (and started
                      (equal? now '(ab))
                      (equal? after '(b a ab))
                      (not again)
                      (null? *world-later*)
                      (not *world-loading*))))))))

;; An entry that takes a while to load, 300 ms of the machine's clock.
(define later-slow
  (let ([path (string-append later-dir "/slow.ss")])
    (call-with-output-file path
      (lambda (p)
        (write '(let ([end (+ (real-time) 300)])
                  (let loop () (when (< (real-time) end) (loop))))
               p))
      'replace)
    path))

;; The process is switched out as any is: while an entry loads, the world
;; goes on, its turns and frames too.
(fluid-let ([*world-later* (list later-slow)] [*world-loading* #f]
            [*world-loader* #f])
  (world-later-start!)
  (steps 1)
  (let ([ticks (pacer-ticks)])
    (do ([k 0 (+ k 1)]) ((= k 3)) (request-frame!) (steps 1))
    (let ([loading *world-loading*] [turns (- (pacer-ticks) ticks)])
      (test-wait 10000 (lambda () (not *world-loader*)))
      (check (format "while an entry loads, the world goes on: ~a turns, \
                      the entry still loading (~a)"
                     turns loading)
             (and (equal? loading later-slow) (>= turns 3)
                  (not *world-loading*))))))

;; A folder of other libraries: a kit and a look load first, as Schevana's
;; do, while an app's library waits; one that declares no layer loads
;; first.
(let ([dir (string-append out-dir "/third-party")])
  (system (format "rm -rf '~a' && mkdir -p '~a/third-party'" dir dir))
  (for-each
   (lambda (name layer)
     (call-with-output-file (format "~a/third-party/~a.sls" dir name)
       (lambda (p)
         (write `(library (third-party ,name)
                   (export)
                   (import (chezscheme)
                           (only (schevana base) library-layer))
                   ,@(if layer (list `(library-layer ,layer)) '()))
                p))
       'replace))
   '(my-kit my-look my-app plain)
   '(kits looks apps #f))
  (let ([entries (auto-load-entries dir)])
    (check (format "an added folder's libraries wait by the layer each \
                    declares: an app's after the screen, a kit's and a \
                    look's first, and one with none first ~s"
                   (map (lambda (e) (list e (desktop-later? e))) entries))
           (equal? (map desktop-later? entries) '(#t #f #f #f)))))

;; A thunk to run once all of the world has loaded waits for the waiting
;; entries and for the one that loads now, then runs once; with none
;; waiting or loading, it runs at once.
(let ([a (later-file "c")] [ran '()])
  (fluid-let ([*world-later* (list a)] [*world-loading* #f]
              [*world-loader* #f])
    (world-after-load! (lambda () (set! ran (cons 'after ran))))
    (let ([before ran])
      (world-later-start!)
      (test-wait 10000 (lambda () (pair? ran)))
      (set! *world-loading* "elsewhere.ss")
      (world-after-load! (lambda () (set! ran (cons 'loading ran))))
      (let ([while-loading ran])
        (set! *world-loading* #f)
        (steps 1)
        (world-after-load! (lambda () (set! ran (cons 'now ran))))
        (check (format "world-after-load! waits for the world, an entry \
                        that loads now too, then runs once; with nothing \
                        waiting, at once ~s"
                       (list before while-loading ran))
               (and (null? before) (equal? while-loading '(after))
                    (equal? ran '(now loading after))))))))

;; Once the last waiting entry has loaded, the next quiet step settles the
;; world, once; a step that isn't quiet never does, since a settle takes
;; longer than a frame, nor one while an entry loads. The steps are the
;; loop's report of each step, so that the test decides which is quiet.
(let ([settled 0])
  (fluid-let ([*world-later* '()] [*world-loading* "elsewhere.ss"]
              [*world-unsettled?* #t]
              [collector-settle! (lambda () (set! settled (+ settled 1)))])
    (loop-stepped! #t)
    (let ([loading settled])
      (set! *world-loading* #f)
      (loop-stepped! #f)
      (let ([busy settled])
        (loop-stepped! #t)
        (let ([quiet settled])
          (loop-stepped! #t)
          (check (format "once nothing waits or loads, a quiet step settles \
                          the world, once ~s"
                         (list loading busy quiet settled))
                 (and (= loading 0) (= busy 0) (= quiet 1)
                      (= settled 1))))))))
