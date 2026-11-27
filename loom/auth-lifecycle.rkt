#lang racket/base
(require web-server/http "http.rkt" "session-http.rkt" "live-registry.rkt" "live-bus.rkt" "login-limit.rkt")
(provide make-login-handler make-logout-handler)
;; The verifier is application-owned, receives credential JSON, and returns
;; trusted session data or #f. It must enforce secure password
;; verification; this layer never stores or logs credentials.
(define (reply code data [cookie #f])
  (define resp (json-response data #:code code))
  (struct-copy response resp [headers
    (append (list (header #"Cache-Control" #"no-store"))
            (if cookie (list cookie) '()) (response-headers resp))]))
(define (reject code message) (reply code (hasheq 'error message)))
(define (tokens req)
  (map bytes->string/latin-1 (request-header-values req #"X-Loom-CSRF")))
(define (revoke-live state registry bus)
  (define owner (web-session-csrf state))
  (when registry (registry-revoke-owner! registry owner))
  (when bus (live-revoke-owner! bus owner)))
(define (make-login-handler store verify #:secure? [secure? #t]
                            #:registry [registry #f] #:bus [bus #f]
                            #:attempt-policy [attempt-policy (lambda (req body) #t)])
  (unless (and (procedure? attempt-policy) (procedure-arity-includes? attempt-policy 2))
    (raise-argument-error 'make-login-handler "two-argument attempt policy" attempt-policy))
  (unless (and (procedure? verify) (procedure-arity-includes? verify 1))
    (raise-argument-error 'make-login-handler "one-argument verifier" verify))
  (lambda (req)
    (define state (web-session-ref store req #:secure? secure?))
    (cond
      [(not (bytes=? (request-method req) #"POST")) (reject 405 "method-not-allowed")]
      [(not (web-session-valid-csrf? state (tokens req))) (reject 403 "forbidden")]
      [else
       (define body (with-handlers ([exn:fail? (lambda (_) #f)])
                      (request-json req #:max-bytes 8192)))
       (cond
         [(not (hash? body)) (reject 400 "invalid-credentials")]
         [else
          (define permit (attempt-policy req body))
          (cond
            [(exact-positive-integer? permit)
             (define resp (reject 429 "too-many-attempts"))
             (struct-copy response resp [headers (cons (header #"Retry-After" (string->bytes/utf-8 (number->string permit))) (response-headers resp))])]
            [(not (eq? permit #t)) (reject 403 "forbidden")]
            [else
             (define data (verify body))
             (cond
            [(not data) (reject 401 "invalid-credentials")]
            [else
             (define transition (transition-web-session store req state data #:secure? secure?))
             (cond
               [(not transition) (reject 409 "session-changed")]
               [else
                (revoke-live state registry bus)
                (reply 200 (hasheq 'csrf (web-session-csrf (cadr transition)))
                       (caddr transition))])])])])])))
(define (make-logout-handler store #:secure? [secure? #t]
                             #:registry [registry #f] #:bus [bus #f])
  (lambda (req)
    (define state (web-session-ref store req #:secure? secure?))
    (cond
      [(not (bytes=? (request-method req) #"POST")) (reject 405 "method-not-allowed")]
      [(not (web-session-valid-csrf? state (tokens req))) (reject 403 "forbidden")]
      [else
       (define cookie (end-web-session store req #:secure? secure?))
       (revoke-live state registry bus)
       (reply 200 (hasheq 'ok #t) cookie)])))
(module+ test
  (require rackunit net/url racket/promise json "session.rkt" "live.rkt" "html.rkt")
  (define store (make-session-store))
  (define registry (make-live-registry))
  (define bus (make-live-bus))
  (define-values (sid guest cookie) (start-web-session store 'guest))
  (define owner (web-session-csrf guest))
  (define instance (registry-mount! registry owner
    (make-live-component #:initial (lambda () 0)
      #:render (lambda (n) (element 'p n)) #:events (hash))))
  (define sub (live-subscribe! bus owner "private"))
  (define calls 0)
  (define login (make-login-handler store
    (lambda (body) (set! calls (add1 calls))
      (and (equal? (hash-ref body 'proof #f) "test-only") "alice"))
    #:registry registry #:bus bus))
  (define logout (make-logout-handler store #:registry registry #:bus bus))
  (define (req id csrf body [method #"POST"])
    (request method (string->url "/auth")
      (list (header #"Cookie" (string->bytes/utf-8 (string-append "__Host-loom-session=" id)))
            (header #"X-Loom-CSRF" (string->bytes/utf-8 csrf))
            (header #"Content-Type" #"application/json"))
      (delay '()) (jsexpr->bytes body) "localhost" 8080 "127.0.0.1"))
  (define good (hasheq 'proof "test-only"))
  (check-equal? (response-code (login (req sid owner good #"GET"))) 405)
  (check-equal? (response-code (login (req sid "wrong" good))) 403)
  (check-equal? calls 0)
  (check-equal? (response-code (login (req sid owner (hasheq)))) 401)
  (define res (login (req sid owner good)))
  (check-equal? (response-code res) 200)
  (check-false (web-session-ref store (req sid owner good)))
  (check-false (registry-snapshot registry owner instance))
  (check-equal? (sync/timeout 0 (live-next-evt bus sub)) 'closed)
  (define new-cookie (for/first ([h (in-list (response-headers res))]
    #:when (bytes=? (header-field h) #"Set-Cookie")) (header-value h)))
  (define new-id (bytes->string/utf-8 (cadr (regexp-match #rx#"__Host-loom-session=([0-9a-f]+)" new-cookie))))
  (define current (web-session-ref store (req new-id owner good)))
  (check-equal? (web-session-data current) "alice")
  (define csrf (web-session-csrf current))
  (check-equal? (response-code (logout (req new-id owner good))) 403)
  (check-equal? (response-code (logout (req new-id csrf good))) 200)
  (check-false (web-session-ref store (req new-id csrf good)))
  (define-values (limited-id limited-state limited-cookie) (start-web-session store 'guest))
  (define limiter (make-login-limiter #:limit 1 #:window 60 #:clock (lambda () 0)))
  (define verified 0)
  (define limited-login (make-login-handler store
    (lambda (_) (set! verified (add1 verified)) #f)
    #:attempt-policy (lambda (req body) (login-attempt! limiter "test-account"))))
  (define limited-request (req limited-id (web-session-csrf limited-state) good))
  (check-equal? (response-code (limited-login limited-request)) 401)
  (define blocked (limited-login limited-request))
  (check-equal? (response-code blocked) 429)
  (check-equal? verified 1)
  (check-equal? (for/first ([h (in-list (response-headers blocked))]
    #:when (bytes=? (header-field h) #"Retry-After")) (header-value h)) #"60"))
