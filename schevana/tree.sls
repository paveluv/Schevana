;;; (schevana tree) — where the tree is: the folder schevana/ is in, two
;;; up from this file, as it was read when the library was compiled. What the
;;; tree keeps beside its code (.work, the files a world loads) is found
;;; from it.

(library (schevana tree)
  (export *schevana-root*)
  (import (chezscheme) (only (schevana base) library-layer define-state))

  (library-layer foundation)

  (define-syntax tree-root
    (lambda (x)
      (syntax-case x ()
        [(k)
         (let* ([a (syntax->annotation x)]
                [file (if a
                          (source-file-descriptor-path
                           (source-object-sfd (annotation-source a)))
                          "schevana/tree.sls")]
                [file (if (path-absolute? file)
                          file
                          (string-append (current-directory) "/" file))])
           (datum->syntax #'k
             (path-parent (path-parent file))))])))

  ;; A state, which a test sets to a copy of the tree.
  (define-state *schevana-root* (tree-root)))
