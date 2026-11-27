#lang racket/base
(require json racket/port "session-http.rkt" "live-registry.rkt" "live-http.rkt")
(provide make-live-channel)
;; Transport-neutral message processor. The adapter must validate the
;; handshake Origin and supply a fresh session lookup on every message.
;; No client-supplied owner, no replay, one mounted instance per channel.
(define (id? x)
  (and (string? x) (= (string-length x) 64) (regexp-match? #rx"^[0-9a-f]+$" x)))
(define (parse raw limit)
  (and (bytes? raw) (<= (bytes-length raw) limit)
       (with-handlers ([exn:fail? (lambda (_) #f)])
         (define in (open-input-bytes raw))
         (define msg (read-json in))
         (and (hash? msg) (regexp-match? #rx#"^[ \t\r\n]*$" (port->bytes in)) msg))))
(define (shape? msg keys)
  (and (hash? msg) (= (hash-count msg) (length keys))
       (andmap (lambda (k) (hash-has-key? msg k)) keys)))
(define (err name) (hasheq 'status "error" 'error name))
(define (make-live-channel registry lookup #:max-bytes [limit 16384])
  (unless (and (procedure? lookup) (procedure-arity-includes? lookup 0)
               (exact-integer? limit) (<= 1 limit 65536))
    (error 'make-live-channel "invalid channel configuration"))
  (define owner #f)
  (define instance #f)
  (define closed? #f)
  (define lock (make-semaphore 1))
  (define (close! name) (set! closed? #t) (err name))
  (lambda (raw)
    (call-with-semaphore lock
      (lambda ()
        (define state (and (not closed?) (lookup)))
        (define msg (and (web-session? state) (parse raw limit)))
        (cond
          [closed? (err "closed")]
          [(not (web-session? state)) (close! "forbidden")]
          [(and owner (not (equal? owner (web-session-csrf state)))) (close! "forbidden")]
          [(not owner)
           (cond
             [(not (and (shape? msg '(type id csrf))
                        (equal? (hash-ref msg 'type) "bind")
                        (id? (hash-ref msg 'id))
                        (string? (hash-ref msg 'csrf))
                        (web-session-valid-csrf? state (list (hash-ref msg 'csrf)))))
              (close! "forbidden")]
             [else
              (define id (hash-ref msg 'id))
              (define result (registry-snapshot registry (web-session-csrf state) id))
              (if result
                  (begin (set! owner (web-session-csrf state)) (set! instance id)
                         (live-result-json result))
                  (close! "instance-not-found"))])]
          [(and (shape? msg '(type)) (equal? (hash-ref msg 'type) "snapshot"))
           (define result (registry-snapshot registry owner instance))
           (if result (live-result-json result) (close! "instance-not-found"))]
          [(and (shape? msg '(type version event payload))
                (equal? (hash-ref msg 'type) "event")
                (exact-nonnegative-integer? (hash-ref msg 'version))
                (<= (hash-ref msg 'version) 9007199254740991)
                (string? (hash-ref msg 'event))
                (<= 1 (string-length (hash-ref msg 'event)) 64)
                (regexp-match? #rx"^[a-z][a-z0-9_-]*$" (hash-ref msg 'event)))
           (define result (registry-dispatch! registry owner instance
                            (hash-ref msg 'version) (hash-ref msg 'event) (hash-ref msg 'payload)))
           (if result (live-result-json result) (close! "instance-not-found"))]
          [else (err "invalid-message")])))))
(module+ test
  (require rackunit "session.rkt" "live.rkt" "html.rkt")
  (define store (make-session-store))
  (define registry (make-live-registry))
  (define-values (sid state cookie) (start-web-session store 'guest))
  (define-values (other-id other other-cookie) (start-web-session store 'guest))
  (define comp (make-live-component #:initial (lambda () 0)
    #:render (lambda (n) (element 'p n))
    #:events (hash "inc" (lambda (n p) (add1 n)))))
  (define id (registry-mount! registry (web-session-csrf state) comp))
  (define (bind s) (jsexpr->bytes (hasheq 'type "bind" 'id id 'csrf (web-session-csrf s))))
  (define ch (make-live-channel registry (lambda () (session-ref store sid))))
  (define stranger (make-live-channel registry (lambda () other)))
  (check-equal? (hash-ref (stranger (bind other)) 'error) "instance-not-found")
  (check-equal? (hash-ref (ch (bind state)) 'version) 0)
  (define event (jsexpr->bytes (hasheq 'type "event" 'version 0 'event "inc" 'payload 'null)))
  (check-equal? (hash-ref (ch event) 'version) 1)
  (check-equal? (hash-ref (ch event) 'status) "stale")
  (check-equal? (hash-ref (ch (jsexpr->bytes (hasheq 'type "snapshot"))) 'version) 1)
  (check-equal? (hash-ref (ch (make-bytes 16385)) 'error) "invalid-message")
  (define invalid (make-live-channel registry (lambda () state)))
  (check-equal? (hash-ref (invalid (jsexpr->bytes (hasheq 'type "bind" 'id id 'csrf 42))) 'error) "forbidden")
  (check-equal? (hash-ref (invalid (bind state)) 'error) "closed")
  (check-equal? (hash-ref (ch #"{} {}") 'error) "invalid-message")
  (session-delete! store sid)
  (check-equal? (hash-ref (ch event) 'error) "forbidden")
  (check-equal? (hash-ref (ch event) 'error) "closed"))
