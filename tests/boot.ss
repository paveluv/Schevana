;;; tests/boot.ss — the world a suite or the bench looks into: loaded as
;;; the desktop loads it, headless, but not started, and the tests' reach
;;; into the core (tests/reach.ss). The library edition's, or with
;;; SCHEVANA_HACKER set the hacker edition's (src/hacker.ss).
;;;
;;;   (load (string-append *schevana-root* "/tests/boot.ss"))

;; The tree's libraries, as a launcher has them (src/launch.ss).
(load (string-append *schevana-root* "/src/launch.ss"))
(define test-hacker? (schevana-hacker? '()))
(schevana-libraries! (schevana-launch-root *schevana-root*) test-hacker?)

;; The basics, a copy of the tests' own (the hacker edition's are here
;; already, the libraries' forms' top-level sense with them).
(unless test-hacker? (load (string-append *schevana-root* "/src/base.ss")))

;; Core0's libraries whole, which the tests look into and stand in for,
;; as the boot has them, and how a library reloads.
(eval '(import (schevana ffi) (schevana sdl) (schevana shader)
               (schevana core0 mail) (schevana core0 trace)
               (schevana core0 renderer) (schevana core0 present)
               (schevana core0 platform) (schevana core0 trace-file)
               (schevana core0 gpu) (schevana core0 window) (schevana reload)))

;; The world, loaded as the desktop loads it, headless, with the demos
;; (./schevana-desktop --headless schevana-demo), here on this thread; this
;; environment stays the tests' (tests/reach.ss), but in the hacker
;; edition, where it is the world.
(define test-options
  (schevana-call test-hacker? '(schevana desktop main) 'desktop-options
                 '("--headless")))
(schevana-call test-hacker? '(schevana core sources) 'auto-load!
               (string-append *schevana-root* "/schevana-demo"))
(parameterize ([interaction-environment (interaction-environment)])
  (schevana-call test-hacker? '(schevana core sources) 'core1-boot!
                 test-options))
(load (string-append *schevana-root* "/tests/reach.ss"))
