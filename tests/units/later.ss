;;; tests/units/later.ss — what of the world loads after the screen shows
;;; ((schevana core sources)): the desktop's apps wait (desktop-later?); one
;;; loads a step that is quiet, or after a second of steps that weren't;
;;; one asked for loads at once, and only once.

(check "the desktop's apps wait, libraries and files; the rest loads first"
       (and (desktop-later? '(schevana apps tasks))
            (desktop-later? "apps/boids.ss")
            (not (desktop-later? '(schevana kits ui)))
            (not (desktop-later? '(schevana desktop topbar)))
            (not (desktop-later? "src/base.ss"))))

;; Two files of the test's own, each counting its loads in "/".
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

(let ([a (later-file "a")] [b (later-file "b")])
  (fluid-let ([*world-later* (list a b)] [*world-later-ms* (now-ms)])
    (steps 2)
    (let ([early (later-loads)])
      ;; steps that draw are never quiet: a second after the last, one loads
      (set! *world-later-ms* (- (now-ms) 2000))
      (steps 1)
      (let ([after-second (later-loads)] [waiting *world-later*])
        (world-load-now! b)
        (let ([now (later-loads)] [again (world-load-now! b)])
          (check (format "a waiting entry loads a second after the last while \
                          frames flow, one asked for at once, once ~s"
                         (list early after-second waiting now again))
                 (and (null? early)
                      (equal? after-second '(a))
                      (equal? waiting (list b))
                      (equal? now '(b a))
                      (not again)
                      (null? *world-later*))))))))

;; A folder of any libraries: a kit and a look load first, as Schevana's
;; do, an app's library waits; one that declares no layer loads first.
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

;; What runs once all of the world has loaded waits for the entries that
;; wait, then runs once; with none waiting, at once.
(let ([a (later-file "c")] [ran '()])
  (fluid-let ([*world-later* (list a)] [*world-later-ms* (now-ms)])
    (world-after-load! (lambda () (set! ran (cons 'after ran))))
    (let ([before ran])
      (set! *world-later-ms* (- (now-ms) 2000))
      (steps 2)
      (world-after-load! (lambda () (set! ran (cons 'now ran))))
      (check (format "world-after-load! waits for the world, then runs \
                      once; with nothing waiting, at once ~s"
                     (list before ran))
             (and (null? before) (equal? ran '(now after)))))))
