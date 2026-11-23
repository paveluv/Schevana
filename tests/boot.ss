;;; tests/boot.ss — loads the world that a suite or the bench looks
;;; into: loaded as the desktop loads it, headless but not started, along
;;; with the tests' reach into the core (tests/reach.ss). It loads the
;;; library edition, or the hacker edition (src/hacker.ss) when
;;; SCHEVANA_HACKER is set.
;;;
;;;   (load (string-append *schevana-root* "/tests/boot.ss"))

;; The tree's libraries, set up as a launcher sets them up
;; (src/launch.ss); in the library edition the tests build them
;; themselves (tests/build.ss).
(load (string-append *schevana-root* "/src/launch.ss"))
(load (string-append *schevana-root* "/tests/build.ss"))
(define test-hacker? (schevana-hacker? '()))
(schevana-libraries! (schevana-launch-root *schevana-root*) test-hacker?)
(unless test-hacker? (test-build! (schevana-launch-root *schevana-root*)))

;; The basics (src/base.ss), as the tests' own copy. The hacker edition
;; has loaded them already, together with what the libraries' own forms
;; mean at the top level (src/strip.ss).
(unless test-hacker? (load (string-append *schevana-root* "/src/base.ss")))

;; Core0's libraries, imported whole as the boot has them, so that the
;; tests can look into them and stand in for them; and (schevana reload),
;; which reloads a library.
(eval '(import (schevana ffi) (schevana sdl) (schevana shader)
               (schevana core0 mail) (schevana core0 trace)
               (schevana core0 renderer) (schevana core0 present)
               (schevana core0 platform) (schevana core0 trace-file)
               (schevana core0 gpu) (schevana core0 window) (schevana reload)))

;; The world, loaded as the desktop loads it when headless
;; (./desktop --headless), here on this thread. This environment stays
;; the tests' own (tests/reach.ss), except in the hacker edition, where it
;; is the world. A demo is loaded only where a test uses it (test-demos!,
;; test-library). The desktop's options come from its main library, which
;; keeps them to itself: in the library edition the tests' build gives
;; them as test:desktop-options (tests/build.ss).
(define test-options
  (schevana-call test-hacker? '(schevana desktop main)
                 (if test-hacker? 'desktop-options 'test:desktop-options)
                 '("--headless")))
(parameterize ([interaction-environment (interaction-environment)])
  (schevana-call test-hacker? '(schevana core sources) 'core1-boot!
                 test-options))
(load (string-append *schevana-root* "/tests/reach.ss"))
