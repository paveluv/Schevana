;;; tests/units/shadows.ss — a shadow is a record the shader fades.


(define (shadow-picture s)
  (image (* s 200) (* s 160) s
         (lambda ()
           (fill-box 0 0 200 160 #xffffff)
           (draw-shadow 50 40 100 60 8 20))))

(define (shade p s x y)
  (fxand (pixel-at p (* s x) (* s y)) 255))

(check "a shadow darkens under its box, and fades out over its size, lower \
        by a third of it"
       (let ([p (shadow-picture 1)])
         (let ([under (shade p 1 100 70)]
               [near (shade p 1 44 75)]
               [far (shade p 1 25 75)]
               [above (shade p 1 100 30)]
               [below (shade p 1 100 115)])
           (and (< under 255) (< under near) (<= near far)
                (= far 255)
                (> above below)))))

(check "a shadow is the same at any scale, its edge a little finer"
       (let ([one (shadow-picture 1)] [two (shadow-picture 2)])
         (<= (abs (- (shade one 1 100 70) (shade two 2 100 70))) 1)))

(check "a shadow of no size draws nothing"
       (same-bytes? (image 40 40 1 (lambda ()
                                     (fill-box 0 0 40 40 #xffffff)
                                     (draw-shadow 5 5 20 20 2 0)))
                    (image 40 40 1 (lambda ()
                                     (fill-box 0 0 40 40 #xffffff)))))

(check "a window's shadow is half as large unfocused, and a maximized one \
        has none"
       (let ([w (open-window "Shadow" 'size '(200 . 100))])
         (let ([reach (window-shadow-reach w)])
           (maximize-window! w)
           (let ([none (window-shadow-reach w)])
             (close-window! w)
             (and (> reach 0) (= none 0))))))

