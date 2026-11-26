#lang racket/base
(require web-server/http "http.rkt" "live.rkt" "live-registry.rkt" "session-http.rkt")
(provide make-live-event-handler live-result-json)
;; JSON tree, not executable HTML. Browser adapters must create text nodes
;; and validate tags/attributes rather than assigning innerHTML.
(define (tree-json node)
  (if (string? node) node
      (hasheq 'tag (symbol->string (car node))
              'attrs (for/hasheq ([a (in-list (cadr node))]) (values (car a) (cadr a)))
              'children (map tree-json (cddr node)))))
(define (live-result-json result)
  (hasheq 'status (symbol->string (live-result-status result))
          'version (live-result-version result)
          'view (tree-json (live-result-view result))))
(define (reply data code)
  (define resp (json-response data #:code code))
  (struct-copy response resp
    [headers (cons (header #"Cache-Control" #"no-store") (response-headers resp))]))
(define (failure code message) (reply (hasheq 'error message) code))
(define (valid-message? m)
  (and (hash? m) (= (hash-count m) 4)
       (andmap (lambda (k) (hash-has-key? m k)) '(id version event payload))
       (string? (hash-ref m 'id))
       (= (string-length (hash-ref m 'id)) 64)
       (regexp-match? #rx"^[0-9a-f]+$" (hash-ref m 'id))
       (exact-nonnegative-integer? (hash-ref m 'version))
       (<= (hash-ref m 'version) 9007199254740991)
       (string? (hash-ref m 'event))
       (<= 1 (string-length (hash-ref m 'event)) 64)
       (regexp-match? #rx"^[a-z][a-z0-9_-]*$" (hash-ref m 'event))))
;; The session's random CSRF secret is also its internal registry owner key.
;; Never accept an owner supplied by the client. Mount with web-session-csrf.
(define (make-live-event-handler store registry #:secure? [secure? #t] #:max-bytes [limit 16384])
  (lambda (req)
    (define state (web-session-ref store req #:secure? secure?))
    (define tokens (map bytes->string/latin-1 (request-header-values req #"X-Loom-CSRF")))
    (cond
      [(not (bytes=? (request-method req) #"POST")) (failure 405 "method-not-allowed")]
      [(not (web-session-valid-csrf? state tokens)) (failure 403 "forbidden")]
      [else
       (define msg (with-handlers ([exn:fail? (lambda (_) #f)])
                     (request-json req #:max-bytes limit)))
       (cond
         [(not (valid-message? msg)) (failure 400 "invalid-event")]
         [else
          (define result
            (registry-dispatch! registry (web-session-csrf state) (hash-ref msg 'id)
                                (hash-ref msg 'version) (hash-ref msg 'event) (hash-ref msg 'payload)))
          (if result
              (reply (live-result-json result)
                     (case (live-result-status result) [(ok) 200] [(stale) 409] [else 422]))
              (failure 404 "instance-not-found"))])])))
(module+ test
  (require rackunit net/url racket/promise json "html.rkt" "session.rkt")
  (define sessions (make-session-store))
  (define instances (make-live-registry))
  (define-values (sid state cookie) (start-web-session sessions 'guest))
  (define-values (sid2 state2 cookie2) (start-web-session sessions 'guest))
  (define component (make-live-component #:initial (lambda () 0)
    #:render (lambda (n) (element 'p n))
    #:events (hash "inc" (lambda (n p) (add1 n)))))
  (define id (registry-mount! instances (web-session-csrf state) component))
  (define handler (make-live-event-handler sessions instances))
  (define (req sid token version [event "inc"])
    (request #"POST" (string->url "/live")
      (list (header #"Cookie" (string->bytes/utf-8 (string-append "__Host-loom-session=" sid)))
            (header #"Content-Type" #"application/json")
            (header #"X-Loom-CSRF" (string->bytes/utf-8 token)))
      (delay '()) (jsexpr->bytes (hasheq 'id id 'version version 'event event 'payload 'null))
      "localhost" 8080 "127.0.0.1"))
  (check-equal? (response-code (handler (req sid2 (web-session-csrf state2) 0))) 404)
  (check-equal? (response-code (handler (req sid (web-session-csrf state2) 0))) 403)
  (check-equal? (response-code (handler (req sid (web-session-csrf state) 0))) 200)
  (check-equal? (response-code (handler (req sid (web-session-csrf state) 0))) 409)
  (check-equal? (response-code (handler (req sid (web-session-csrf state) 1 "missing"))) 422)
  (check-equal? (response-code (handler (req sid (web-session-csrf state) -1))) 400)
  (check-equal? (hash-ref (live-result-json (registry-snapshot instances (web-session-csrf state) id)) 'version) 1))
