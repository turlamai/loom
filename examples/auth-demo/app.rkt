#lang racket/base
(require loom loom/http loom/session loom/session-http loom/auth loom/auth-lifecycle
         loom/password loom/login-limit loom/security web-server/http)
(provide make-auth-demo)
;; Loopback-only demonstration; account provisioning is external.
(define (make-auth-demo password)
  (define passwords (make-password-service))
  (define credential (password-hash passwords password))
  (define dummy (password-hash passwords #"dummy-not-an-account"))
  (define store (make-session-store))
  (define (account body)
    (define name (hash-ref body 'username #f))
    (and (string? name) (<= 1 (string-length name) 64)
         (string-downcase name)))
  (define (verify body)
    (define name (account body))
    (define supplied (hash-ref body 'password #f))
    (define known? (equal? name "alice"))
    (and (string? supplied)
         (password-verify passwords (string->bytes/utf-8 supplied)
                          (if known? credential dummy))
         known? "alice"))
  (define policy
    (make-login-attempt-policy
     #:account-key (lambda (req body) (or (account body) "invalid-account"))
     #:source-key (lambda (req body) (request-client-ip req))))
  (define (session-response state [cookie #f])
    (define resp (json-response (hasheq 'csrf (web-session-csrf state))))
    (struct-copy response resp [headers
      (append (list (header #"Cache-Control" #"no-store"))
              (if cookie (list cookie) '()) (response-headers resp))]))
  (define (bootstrap req)
    (define state (web-session-ref store req #:secure? #f))
    (if state (session-response state)
        (let-values ([(id guest cookie) (start-web-session store 'guest #:secure? #f)])
          (session-response guest cookie))))
  (define (resolve data)
    (and (equal? data "alice") (make-principal "alice" #:roles '(member))))
  (make-app
   (list (route #"GET" "/session" bootstrap)
         (route #"POST" "/login" (make-login-handler store verify #:secure? #f #:attempt-policy policy))
         (route #"POST" "/logout" (make-logout-handler store #:secure? #f))
         (route #"GET" "/account"
                (require-role 'member
                  (lambda (req)
                    (define resp (json-response (hasheq 'user (principal-id (current-principal)))))
                    (struct-copy response resp [headers
                      (cons (header #"Cache-Control" #"no-store") (response-headers resp))])))))
   #:middleware (list security-headers (authentication-middleware store resolve #:secure? #f))))
(module+ main
  (define secret (getenv "LOOM_DEMO_PASSWORD"))
  (unless (and secret (>= (string-length secret) 12))
    (error 'auth-demo "set LOOM_DEMO_PASSWORD to a local test password of at least 12 characters"))
  (define port (or (and (getenv "LOOM_AUTH_PORT") (string->number (getenv "LOOM_AUTH_PORT"))) 8080))
  (serve (make-auth-demo (string->bytes/utf-8 secret)) #:port port))
