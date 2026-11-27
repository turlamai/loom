#lang racket/base
(require loom loom/live loom/html loom/session loom/session-http loom/live-registry
         loom/live-websocket loom/http web-server/http)
(define sessions (make-session-store))
(define registry (make-live-registry))
(define counter (make-live-component #:initial (lambda () 0)
  #:render (lambda (n) (element 'p n))
  #:events (hash "inc" (lambda (n payload) (add1 n)))))
(define (bootstrap req)
  (define-values (sid state cookie) (start-web-session sessions 'guest #:secure? #f))
  (define id (registry-mount! registry (web-session-csrf state) counter))
  (define resp (json-response (hasheq 'id id 'csrf (web-session-csrf state))))
  (struct-copy response resp [headers (cons cookie (response-headers resp))]))
(module+ main
  (define stop (serve-live-websocket sessions registry #:origin "http://127.0.0.1:18884"
                                    #:port 18885 #:secure? #f))
  (dynamic-wind void
    (lambda () (serve (make-app (list (route #"GET" "/" bootstrap))) #:port 18884))
    (lambda () (stop))))
