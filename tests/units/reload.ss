;;; tests/units/reload.ss — what (reload!) reads.

(check "reload reads the source list from load.ss"
       (and (equal? (read-source-list) *schevana-sources*)
            (member "src/wm.ss" *schevana-sources*)
            #t))
