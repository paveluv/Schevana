;;; (schevana reload) — libraries reloaded in place: a library whose file
;;; changed is evaluated again from its source, and so is every library
;;; that imports it, after it, as Chez links each to the instance it was
;;; evaluated against; then each environment that imported one of them
;;; through reload-import! imports it again, where the old one would
;;; raise. Its states stay (define-state), its made values and hooks are
;;; made again, and what sets a hook sets it again, since it imports it.
;;; A closure made before keeps the code it was made with.
;;;
;;; The libraries a thread of its own runs (core0's) stay as they were
;;; booted, with all they import: what reload-libraries! is given as held.

(library (schevana reload)
  (export reload-import! reload-mark! reload-libraries! reload-facts
          reload-source)
  (import (chezscheme)
          (schevana base))

  (library-layer foundation)

  ;; Each library's file text as it was evaluated last, by name: a
  ;; library whose file differs has changed.
  (define-state *reload-texts* (make-hashtable equal-hash equal?))

  ;; The environments reload-import! imported libraries into, each an
  ;; ephemeron pair of the environment and its libraries: an environment
  ;; dropped is let go.
  (define-state *reload-imports* '())

  ;; What the last reload evaluated again, in order.
  (define-state *reload-last* '())

  ;; Where a library's file is evaluated again: Chez's names, and a
  ;; library form defines a library from any environment that can hold a
  ;; definition, whatever the caller's.
  (define-made reload-environment (copy-environment (scheme-environment)))

  ;; The file a library is evaluated from, as Chez's library manager
  ;; finds it (library-directories, library-extensions), or #f for one
  ;; that has none (Chez's own).
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

  ;; The library names, Chez's form of each (versions dropped).
  (define (reload-name ref) (filter symbol? ref))

  ;; What name imports: asked of what Chez keeps to expand with, which a
  ;; library loaded compiled has before it runs (or one that never runs,
  ;; giving others' names as its own).
  (define (reload-requires name)
    (map reload-name
         (library-requirements name (library-requirements-options import))))

  ;; names, and all they import.
  (define (reload-closure names)
    (let loop ([todo names] [seen '()])
      (cond [(null? todo) seen]
            [(member (car todo) seen) (loop (cdr todo) seen)]
            [else (loop (append (reload-requires (car todo)) (cdr todo))
                        (cons (car todo) seen))])))

  ;; The libraries loaded from a file, but those held and what they
  ;; import.
  (define (reload-candidates held)
    (let ([held (reload-closure held)])
      (filter (lambda (name)
                (and (not (member name held)) (reload-source name)))
              (map reload-name (library-list)))))

  ;; The texts of the libraries named (by default all loaded from a file),
  ;; for those not seen yet: how they read when first seen.
  (define (reload-mark! . names)
    (for-each (lambda (name)
                (let ([file (reload-source name)])
                  (when (and file
                             (not (hashtable-contains? *reload-texts* name)))
                    (hashtable-set! *reload-texts* name (reload-text file)))))
              (if (null? names)
                  (map reload-name (library-list))
                  names)))

  ;; Imports the libraries into environment, as an import form does
  ;; there, and keeps them, so that a reload imports them again.
  (define (reload-import! environment . names)
    (eval `(import ,@names) environment)
    (apply reload-mark! names)
    (set! *reload-imports*
          (cons (ephemeron-cons environment names)
                (filter (lambda (e) (not (bwp-object? (car e))))
                        *reload-imports*))))

  ;; changed, and the libraries among candidates that import one of them,
  ;; each after what it imports of them.
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

  ;; The libraries whose files changed since they were evaluated (and
  ;; those of forced, as if theirs had), and the libraries that import them,
  ;; evaluated again in order and run; then the environments' imports
  ;; again. held: libraries that stay as they are, with all they import.
  ;; Their texts are kept only once all went in, so a reload stopped on an
  ;; error tries the whole set again. => the libraries evaluated again
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
                  (unless (bwp-object? (car e))
                    (let ([names (filter (lambda (n) (member n order))
                                         (cdr e))])
                      (unless (null? names)
                        (eval `(import ,@names) (car e))))))
                *reload-imports*)
      (set! *reload-last* order)
      order))

  ;; What it keeps, for whoever looks (inspect-reload): the libraries
  ;; whose texts it holds, how many environments it imports into, and
  ;; what the last reload evaluated again.
  (define (reload-facts)
    `((libraries . ,(length (vector->list
                             (hashtable-keys *reload-texts*))))
      (environments . ,(length (remp (lambda (e) (bwp-object? (car e)))
                                     *reload-imports*)))
      (last . ,*reload-last*))))
