(module debug (info-port info)
(import scheme chicken extras)

(define info-port (make-parameter (current-error-port)))

(cond-expand
      (debug (define (info fmt . args)
               (fprintf (info-port) "~?~%" fmt args)
               (flush-output (info-port))))
      (else (define-syntax info
              (syntax-rules ()
                ((info . rest) (void))))))
) ;; debug module
