#lang racket/base
(require racket/list web-server/http)
(provide security-headers)
;; Deliberately no HSTS: deployment must decide HTTPS policy.
(define defaults
  (list (header #"X-Content-Type-Options" #"nosniff")
        (header #"X-Frame-Options" #"DENY")
        (header #"Referrer-Policy" #"strict-origin-when-cross-origin")
        (header #"Content-Security-Policy" #"default-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")))
(define (same-name? a b)
  (string-ci=? (bytes->string/latin-1 (header-field a))
               (bytes->string/latin-1 (header-field b))))
(define (add-headers resp)
  (define existing (response-headers resp))
  (struct-copy response resp
    [headers (append existing
                     (filter (lambda (h) (not (ormap (lambda (e) (same-name? h e)) existing)))
                             defaults))]))
(define (security-headers next)
  (lambda (req) (add-headers (next req))))
(module+ test
  (require rackunit)
  (define r (add-headers (response/xexpr '(p "Hello"))))
  (check-equal? (response-code r) 200)
  (check-true (ormap (lambda (h) (bytes=? (header-field h) #"Content-Security-Policy")) (response-headers r))))
