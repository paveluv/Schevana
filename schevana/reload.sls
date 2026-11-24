;;; (schevana reload) — reloads libraries in place. A library whose file
;;; changed is evaluated again from its source, and so is every library
;;; that imports it, after it, since Chez links each library to the
;;; instance it was evaluated against. Then each environment that imported
;;; one of them through reload-import! (the world, and a REPL's, whose
;;; env-eval imports so) imports it again, since the old instance would
;;; raise an error there. A library's states stay
;;; (define-state), its made values and hooks are made again, and the
;;; library that sets a hook sets it again, since it imports the hook. A
;;; closure made before the reload keeps the code it was made with.
;;;
;;; The libraries that run on a thread of their own (core0's) stay as they
;;; were booted, with everything they import: they are what
;;; reload-libraries! is given as held.

(library (schevana reload)
  (export reload-import! reload-mark! reload-libraries! reload-facts
          reload-source)
  (import (chezscheme)
          (only (schevana base) define-made define-state library-layer))

  (library-layer foundation)

  ;; Each library's file text as it was when first seen or last evaluated,
  ;; by name: a library whose file now differs has changed.
  (define-state *reload-texts* (make-hashtable equal-hash equal?))

  ;; What reload-import! imported, each as an ephemeron pair of the
  ;; environment and (library . import set), so that an environment nobody
  ;; holds is let go.
  (define-state *reload-imports* '())

  ;; What the last reload evaluated again, in order.
  (define-state *reload-last* '())

  ;; Where a library's file is evaluated again: an environment with Chez's
  ;; names. A library form defines a library from any environment that can
  ;; hold a definition, so this one serves whatever the caller's is.
  (define-made reload-environment (copy-environment (scheme-environment)))

  ;; Returns the file a library is evaluated from, as Chez's library
  ;; manager finds it (library-directories, library-extensions), or #f for
  ;; a library that has none (Chez's own).
  (define (reload-source name)
    (let ([path (fold-left (lambda (acc part)
                             (string-append acc "/" (symbol->string part)))
                           ""
                           (filter symbol? name))])
      (let loop ([dirs (library-directories)])
        (and (pair? dirs)
             (or (exists (lambda (ext)
                           (let ([f (string-append (caar dirs) path
                                                   (car ext))])
                             (and (file-regular? f) f)))
                         (library-extensions))
                 (loop (cdr dirs)))))))

  (define (reload-text file)
    (call-with-input-file file get-string-all))

  ;; Returns the library name in a reference, in Chez's form (without its
  ;; version).
  (define (reload-name ref) (filter symbol? ref))

  ;; Returns the libraries that name imports. It asks what Chez keeps for
  ;; expansion, which a library loaded compiled has before it runs (as does
  ;; one that never runs, which gives other libraries' names as its own).
  (define (reload-requires name)
    (map reload-name
         (library-requirements name (library-requirements-options import))))

  ;; Returns names and everything they import.
  (define (reload-closure names)
    (let loop ([todo names] [seen '()])
      (cond [(null? todo) seen]
            [(member (car todo) seen) (loop (cdr todo) seen)]
            [else (loop (append (reload-requires (car todo)) (cdr todo))
                        (cons (car todo) seen))])))

  ;; Returns the loaded libraries that come from a file, except those held
  ;; and everything they import.
  (define (reload-candidates held)
    (let ([held (reload-closure held)])
      (filter (lambda (name)
                (and (not (member name held)) (reload-source name)))
              (map reload-name (library-list)))))

  ;; Keeps the text of each library named (by default every loaded library
  ;; that comes from a file) that hasn't been seen yet, as it reads when
  ;; first seen.
  (define (reload-mark! . names)
    (for-each (lambda (name)
                (unless (hashtable-contains? *reload-texts* name)
                  (let ([file (reload-source name)])
                    (when file
                      (hashtable-set! *reload-texts* name
                                      (reload-text file))))))
              (if (null? names)
                  (map reload-name (library-list))
                  names)))

  ;; Imports set, an import set that names library, into environment, as
  ;; an import form does there, and keeps it, so that a reload that
  ;; evaluates library again imports set there again. The library is
  ;; marked as it reads now, so that a reload sees a later change, and so is
  ;; what loaded with it, so that a reload sees a change to a part of its
  ;; (a library's own, in the folder of its name): the walk stops at a
  ;; library marked before, whose imports were marked with it.
  (define (reload-import! environment library set)
    (eval `(import ,set) environment)
    (let mark ([name library])
      (unless (hashtable-contains? *reload-texts* name)
        (reload-mark! name)
        (for-each mark (reload-requires name))))
    (set! *reload-imports*
          (cons (ephemeron-cons environment (cons library set))
                (filter (lambda (e) (not (bwp-object? (car e))))
                        *reload-imports*))))

  ;; Returns changed and the candidates that import one of them, directly
  ;; or not, each after the libraries of that set it imports.
  (define (reload-order changed candidates)
    (let grow ([set changed])
      (let ([more (filter (lambda (name)
                            (and (not (member name set))
                                 (exists (lambda (r) (member r set))
                                         (reload-requires name))))
                          candidates)])
        (if (pair? more)
            (grow (append set more))
            (let sort ([left set] [done '()])
              (if (null? left)
                  (reverse done)
                  (let ([ready (filter (lambda (name)
                                         (for-all (lambda (r)
                                                    (or (not (member r left))
                                                        (equal? r name)))
                                                  (reload-requires name)))
                                       left)])
                    (when (null? ready)
                      (errorf 'reload-libraries! "libraries in a ring: ~s"
                              left))
                    (sort (remp (lambda (name) (member name ready)) left)
                          (append (reverse ready) done)))))))))

  ;; Evaluates again and runs, in order, the libraries whose files changed
  ;; since they were evaluated (and those in forced, as if their files had
  ;; changed) and the libraries that import them; then imports them again
  ;; into the environments that had them. held names libraries that stay as
  ;; they are, with everything they import. The new texts are kept only
  ;; once every library has gone in, so a reload stopped by an error tries
  ;; the whole set again. Returns the libraries evaluated again.
  (define (reload-libraries! held . forced)
    (let* ([candidates (reload-candidates held)]
           [changed (begin
                      (apply reload-mark! candidates)
                      (filter (lambda (name)
                                (or (member name forced)
                                    (not (string=? (reload-text
                                                    (reload-source name))
                                                   (hashtable-ref
                                                    *reload-texts* name
                                                    "")))))
                              candidates))]
           [order (reload-order changed candidates)])
      (for-each (lambda (name)
                  (load (reload-source name)
                        (lambda (x) (eval x reload-environment)))
                  (invoke-library name))
                order)
      (for-each (lambda (name)
                  (hashtable-set! *reload-texts* name
                                  (reload-text (reload-source name))))
                order)
      (for-each (lambda (e)
                  (unless (or (bwp-object? (car e))
                              (not (member (cadr e) order)))
                    (eval `(import ,(cddr e)) (car e))))
                *reload-imports*)
      (set! *reload-last* order)
      order))

  ;; What this library keeps, for whoever looks (inspect-reload): how many
  ;; libraries' texts it holds, how many environments it imports into, and
  ;; what the last reload evaluated again.
  (define (reload-facts)
    `((libraries . ,(length (vector->list
                             (hashtable-keys *reload-texts*))))
      (environments . ,(length (remp (lambda (e) (bwp-object? (car e)))
                                     *reload-imports*)))
      (last . ,*reload-last*))))
