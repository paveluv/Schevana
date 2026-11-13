;;; tests/units/reload.ss — what (reload!) reads, and what it leaves.

(check "reload reads the source list from main.ss"
       (and (equal? (read-source-list) *schevana-core1-sources*)
            (member "src/core1/wm.ss" *schevana-core1-sources*)
            #t))

(check "reload leaves core0 as it booted: none of its files is the core's \
        to load, and its procedures stay the same; the core's load into \
        /core1, the world given what it exports again"
       (let ([present gpu-publish!] [theme-was (top-level-value 'theme
                                                               core1-env)])
         (reload!)
         (and (not (exists (lambda (f) (string-prefix? "src/core0/" f))
                           *schevana-core1-sources*))
              (eq? gpu-publish! present)
              (not (eq? (top-level-value 'theme core1-env) theme-was))
              (not (top-level-bound? 'theme *world-env*))
              (for-all (lambda (n) (top-level-syntax? n *world-env*))
                       (core1-exported)))))
