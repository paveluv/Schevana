;;; tests/units/reload.ss — what (reload!) reads, and what it leaves.

(check "reload reads the source list from load.ss"
       (and (equal? (read-source-list) *schevana-sources*)
            (member "src/wm.ss" *schevana-sources*)
            #t))

(check "reload leaves core0 as it booted: none of its files is the world's \
        to load, and its procedures stay the same"
       (let ([present gpu-present!])
         (reload!)
         (and (not (exists (lambda (f) (string-prefix? "src/host/" f))
                           *schevana-sources*))
              (eq? gpu-present! present))))
