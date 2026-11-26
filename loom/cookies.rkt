#lang racket/base
(require racket/list racket/string web-server/http "http.rkt")
(provide cookie-values set-cookie-header clear-cookie-header)
(define (cookie-name? s)
  (and (string? s) (regexp-match? #px"^[A-Za-z0-9!#$%&'*+.^_`|~-]+$" s)))
(define (cookie-value? s)
  (and (string? s)
       (for/and ([c (in-string s)])
         (define n (char->integer c))
         (or (= n 33) (<= 35 n 43) (<= 45 n 58) (<= 60 n 91) (<= 93 n 126)))))
(define (cookie-values req name)
  (unless (cookie-name? name) (error 'cookie-values "invalid cookie name"))
  (for*/list ([raw (in-list (request-header-values req #"Cookie"))]
              [part (in-list (string-split (bytes->string/latin-1 raw) ";"))]
              #:do [(define pair (regexp-match #rx"^([^=]+)=(.*)$" (string-trim part)))]
              #:when (and pair (string=? (cadr pair) name) (cookie-value? (caddr pair))))
    (caddr pair)))
(define (set-cookie-header name value #:path [path "/"] #:secure? [secure? #t]
                           #:http-only? [http-only? #t] #:same-site [same-site 'lax]
                           #:max-age [max-age #f])
  (unless (and (cookie-name? name) (cookie-value? value)) (error 'set-cookie-header "invalid cookie name or value"))
  (unless (and (string? path) (string-prefix? path "/")
               (for/and ([c (in-string path)]) (and (<= 32 (char->integer c) 126) (not (char=? c #\;)))))
    (error 'set-cookie-header "invalid path"))
  (unless (memq same-site '(strict lax none)) (error 'set-cookie-header "invalid SameSite"))
  (unless (or (not max-age) (exact-nonnegative-integer? max-age)) (error 'set-cookie-header "invalid Max-Age"))
  (when (and (eq? same-site 'none) (not secure?)) (error 'set-cookie-header "SameSite=None requires Secure"))
  (when (and (string-prefix? name "__Secure-") (not secure?)) (error 'set-cookie-header "invalid __Secure- cookie"))
  (when (and (string-prefix? name "__Host-") (or (not secure?) (not (string=? path "/")))) (error 'set-cookie-header "invalid __Host- cookie"))
  (header #"Set-Cookie"
          (string->bytes/utf-8
           (string-join (append (list (string-append name "=" value) (string-append "Path=" path)
                                      (string-append "SameSite=" (string-titlecase (symbol->string same-site))))
                                (if secure? '("Secure") '()) (if http-only? '("HttpOnly") '())
                                (if max-age (list (format "Max-Age=~a" max-age)) '())) "; "))))
(define (clear-cookie-header name #:path [path "/"] #:secure? [secure? #t])
  (set-cookie-header name "" #:path path #:secure? secure? #:max-age 0))
(module+ test
  (require rackunit)
  (check-equal? (header-value (set-cookie-header "sid" "abc")) #"sid=abc; Path=/; SameSite=Lax; Secure; HttpOnly")
  (check-equal? (header-value (clear-cookie-header "sid")) #"sid=; Path=/; SameSite=Lax; Secure; HttpOnly; Max-Age=0")
  (check-exn exn:fail? (lambda () (set-cookie-header "sid" "a;b")))
  (check-exn exn:fail? (lambda () (set-cookie-header "sid" "a" #:secure? #f #:same-site 'none)))
  (check-exn exn:fail? (lambda () (set-cookie-header "__Host-sid" "a" #:path "/other")))
  (check-exn exn:fail? (lambda () (set-cookie-header "sid" "a" #:path "/x\r\nX:1"))))
