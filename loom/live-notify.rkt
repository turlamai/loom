#lang racket/base
(require web-server/http "http.rkt" "live-bus.rkt" "session-http.rkt")
(provide make-live-notification-handler)
;; resolve-topic: trusted application authorization (session instance-id -> topic or #f).
;; Notifications are not durable; refresh authoritative state on timeout too.
(define (make-live-notification-handler store bus resolve-topic
                                        #:secure? [secure? #t] #:timeout [timeout 15])
  (unless (and (real? timeout) (<= 0 timeout 25))
    (error 'make-live-notification-handler "timeout must be between 0 and 25 seconds"))
  (define (reply code data)
    (define resp (json-response data #:code code))
    (struct-copy response resp
      [headers (cons (header #"Cache-Control" #"no-store") (response-headers resp))]))
  (define (failure code msg) (reply code (hasheq 'error msg)))
  (lambda (req)
    (define state (web-session-ref store req #:secure? secure?))
    (define tokens (map bytes->string/latin-1 (request-header-values req #"X-Loom-CSRF")))
    (cond
      [(not (bytes=? (request-method req) #"POST")) (failure 405 "method-not-allowed")]
      [(not (web-session-valid-csrf? state tokens)) (failure 403 "forbidden")]
      [else
       (define msg (with-handlers ([exn:fail? (lambda (_) #f)])
                     (request-json req #:max-bytes 1024)))
       (define id (and (hash? msg) (= (hash-count msg) 1) (hash-ref msg 'id #f)))
       (cond
         [(not (and (string? id) (= (string-length id) 64)
                    (regexp-match? #rx"^[0-9a-f]+$" id))) (failure 400 "invalid-instance")]
         [else
          (define topic (resolve-topic state id))
          (cond
            [(not topic) (failure 404 "instance-not-found")]
            [else
             (define owner (web-session-csrf state))
             (define subscription #f)
             (dynamic-wind
               void
               (lambda ()
                 (set! subscription
                   (with-handlers ([exn:fail? (lambda (_) #f)])
                     (live-subscribe! bus owner topic)))
                 (cond
                   [(not subscription) (failure 503 "subscription-unavailable")]
                   [else
                    (define notification (sync/timeout timeout (live-next-evt bus subscription)))
                    (define current (web-session-ref store req #:secure? secure?))
                    (cond
                      [(not (eq? state current)) (failure 403 "forbidden")]
                      [(or (eq? notification 'closed)
                           (not (equal? topic (resolve-topic current id))))
                       (failure 404 "instance-not-found")]
                      [else (reply 200 (hasheq 'status (if (eq? notification 'changed) "changed" "timeout")))])]))
               (lambda () (when subscription (live-unsubscribe! bus owner subscription))))])])])))
(module+ test
  (require rackunit net/url racket/promise json "session.rkt" "csrf.rkt")
  (define store (make-session-store))
  (define bus (make-live-bus #:capacity 1 #:per-owner 1))
  (define-values (sid state cookie) (start-web-session store 'guest))
  (define-values (sid2 other cookie2) (start-web-session store 'guest))
  (define id (csrf-token))
  (define (resolve s i) (and (eq? s state) (equal? i id) "tasks"))
  (define handler (make-live-notification-handler store bus resolve #:timeout 0))
  (define (req session token instance)
    (request #"POST" (string->url "/notify")
      (list (header #"Cookie" (string->bytes/utf-8 (string-append "__Host-loom-session=" session)))
            (header #"Content-Type" #"application/json")
            (header #"X-Loom-CSRF" (string->bytes/utf-8 token)))
      (delay '()) (jsexpr->bytes (hasheq 'id instance)) "localhost" 8080 "127.0.0.1"))
  (define valid (req sid (web-session-csrf state) id))
  (check-equal? (response-code (handler valid)) 200)
  (check-equal? (response-code (handler valid)) 200)
  (check-equal? (response-code (handler (req sid2 (web-session-csrf other) id))) 404)
  (check-equal? (response-code (handler (req sid (web-session-csrf other) id))) 403)
  (check-equal? (response-code (handler (req sid (web-session-csrf state) "invalid"))) 400)
  (define occupied (live-subscribe! bus "someone" "other"))
  (check-equal? (response-code (handler valid)) 503)
  (check-true (live-unsubscribe! bus "someone" occupied))
  (check-equal? (response-code (handler valid)) 200)
  (define waiting (make-live-notification-handler store bus resolve #:timeout 2))
  (define result (make-channel))
  (thread (lambda () (channel-put result (waiting valid))))
  (let loop ([n 100])
    (when (and (positive? n) (zero? (live-publish! bus "tasks")))
      (sleep 0.01) (loop (sub1 n))))
  (define response (sync/timeout 3 result))
  (check-true (response? response))
  (when (response? response)
    (define out (open-output-bytes))
    ((response-output response) out)
    (check-equal? (bytes->jsexpr (get-output-bytes out)) (hasheq 'status "changed")))
  (check-equal? (live-publish! bus "tasks") 0))
