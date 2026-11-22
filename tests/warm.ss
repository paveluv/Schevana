;;; tests/warm.ss — compiles the tree's libraries into a cache once, before
;;; a suite starts its runs side by side, since each run would otherwise
;;; compile them itself. Without arguments it fills the launcher's cache
;;; (src/launch.ss), which the launchers that a test runs use; with "tests"
;;; it fills the cache of the tests' build (tests/build.ss), which the
;;; suites use. The hacker edition compiles nothing to a file.
;;;
;;;   scheme --script tests/warm.ss [tests]

(define *schevana-root*
  (let ([dir (path-parent (path-parent (car (command-line))))])
    (if (string=? dir "") "." dir)))

(load (string-append *schevana-root* "/src/launch.ss"))
(load (string-append *schevana-root* "/tests/build.ss"))

;; The names of the world's libraries, the demos' and the game's, taken
;; from their files.
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
                "schevana/apps" "demo" "games")
              '((schevana kits) (schevana services) (schevana styles)
                (schevana palettes) (schevana wallpapers) (schevana desktop)
                (schevana apps) (demo) (games)))))

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
