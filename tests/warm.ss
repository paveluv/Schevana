;;; tests/warm.ss — the tree's libraries compiled into a cache, once,
;;; before a suite starts its runs at once, each of which would compile
;;; them itself: the launcher's cache (src/launch.ss), which the launchers
;;; a test runs use, or with "tests" the tests' build's (tests/build.ss),
;;; which the suites use. The hacker edition compiles none to a file.
;;;
;;;   scheme --script tests/warm.ss [tests]

(define *schevana-root*
  (let ([dir (path-parent (path-parent (car (command-line))))])
    (if (string=? dir "") "." dir)))

(load (string-append *schevana-root* "/src/launch.ss"))
(load (string-append *schevana-root* "/tests/build.ss"))

;; The world's libraries and the demos', by their files.
(define (warm-world-libraries)
  (apply append
         (map (lambda (dir name)
                (let ([path (string-append *schevana-root* "/" dir)])
                  (map (lambda (f)
                         (append name (list (string->symbol (path-root f)))))
                       (sort string<?
                             (filter (lambda (f)
                                       (equal? (path-extension f) "sls"))
                                     (directory-list path))))))
              '("schevana/kits" "schevana/services" "schevana/styles"
                "schevana/palettes" "schevana/wallpapers" "schevana/desktop"
                "schevana/apps" "schevana-demo")
              '((schevana kits) (schevana services) (schevana styles)
                (schevana palettes) (schevana wallpapers) (schevana desktop)
                (schevana apps) (schevana-demo)))))

(unless (schevana-hacker? '())
  (let ([root (schevana-launch-root *schevana-root*)])
    (schevana-libraries! root #f)
    (when (member "tests" (command-line-arguments)) (test-build! root))
    (for-each (lambda (lib)
                (eval `(import ,lib) (copy-environment (scheme-environment))))
              (append '((schevana core) (schevana core sources)
                        (schevana desktop main) (schevana core0 for-recorder)
                        (schevana recorder bytes) (schevana socket))
                      (warm-world-libraries)))))
