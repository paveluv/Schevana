;;; tests/units/reload.ss — what (reload!) reads, and what it leaves.

(check "reload reads the source list from main.ss"
       (and (equal? (read-source-list) *schevana-sources*)
            (member "src/wm.ss" *schevana-sources*)
            #t))

(check "reload leaves core0 as it booted: none of its files is the world's \
        to load, and its procedures stay the same"
       (let ([present gpu-publish!])
         (reload!)
         (and (not (exists (lambda (f) (string-prefix? "src/core0/" f))
                           *schevana-sources*))
              (eq? gpu-publish! present))))
