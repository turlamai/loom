#lang racket/base
(require web-server/http "session-http.rkt" "forms.rkt" "http.rkt")
(provide form-csrf-protection current-verified-form)
(define current-verified-form (make-parameter #f))
;; Opt-in for URL-encoded browser applications. Safe methods must not mutate.
(define (form-csrf-protection store #:secure? [secure? #t] #:max-bytes [limit 65536])
  (lambda (next)
    (lambda (req)
      (parameterize ([current-verified-form #f])
        (cond
          [(member (request-method req) '(#"GET" #"HEAD" #"OPTIONS")) (next req)]
          [else
           (define state (web-session-ref store req #:secure? secure?))
           (define fields (with-handlers ([exn:fail? (lambda (_) #f)])
                            (request-form req #:max-bytes limit)))
           (cond [(not state) (json-response (hasheq 'error "forbidden") #:code 403)]
                 [(not fields) (json-response (hasheq 'error "invalid-form") #:code 400)]
                 [(not (web-session-valid-csrf? state (form-values fields "csrf")))
                  (json-response (hasheq 'error "forbidden") #:code 403)]
                 [else (parameterize ([current-verified-form fields]) (next req))])])))))
