;;; (schevana boot) — what the top level's boot defines for the core's
;;; files (main.ss, src/core1/boot.ss), as a library has it: which thread
;;; is the world's, where the tree is, and the names of a world of
;;; environments, which a library has none of.

(library (schevana boot)
  (export core1-thread? core1-thread! world-value core1-exported
          core1-exports *schevana-root*)
  (import (chezscheme) (schevana layer))

  ;; Whether this is core1, the world's thread: the one that said so
  ;; (core1-thread!, as schevana-main runs the world); till then, the one
  ;; that imported the library.
  (define core1-thread-id (box (get-thread-id)))
  (define (core1-thread?) (fx= (get-thread-id) (unbox core1-thread-id)))
  (define (core1-thread!) (set-box! core1-thread-id (get-thread-id)))

  ;; The top level's environments, "/core1" and "/": a library has
  ;; neither.
  (defvar *core1-env* #f)
  (defvar *world-env* #f)

  ;; A procedure by its name, which the top level looks up in "/": a
  ;; library is handed the procedure itself.
  (define (world-value name)
    (errorf 'world-value
            "~s: a library is handed the procedure, not its name" name))

  ;; What the top level's core1 gives the world, by its export.ss: a
  ;; library's exports are its own.
  (define core1-exports '())
  (define (core1-exported) '())

  ;; What the top level's main.ss says: where the tree is, the core's
  ;; sources (none to load again), what the command line asked.
  (define *schevana-root* (tree-root))
  (defvar *schevana-core1-sources* '())
  (defvar *schevana-options* '())

  (define-exports boot-exports
    (export (world)
      *core1-env* *world-env* *schevana-options*
      (settable *schevana-core1-sources*))))
