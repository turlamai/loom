#lang racket/base
(require loom loom/live loom/html loom/session loom/session-http loom/live-registry
         loom/live-websocket loom/live-bus loom/http web-server/http racket/runtime-path racket/file)
(define-runtime-path assets "../../loom/assets")
(define (asset name)
  (lambda (req)
    (response/full 200 #f (current-seconds) #"text/javascript; charset=utf-8"
      (list (header #"Cache-Control" #"no-store"))
      (list (file->bytes (build-path assets name))))))
(define sessions (make-session-store))
(define registry (make-live-registry))
(define bus (make-live-bus))
(define shared (box 0))
(define shared-counter (make-live-component #:initial (lambda () 0)
  #:render (lambda (_) (element 'p (unbox shared)))
  #:events (hash "publish" (lambda (n payload)
    (set-box! shared (add1 (unbox shared)))
    (live-publish! bus "shared-counter")
    (add1 n)))))
(define counter (make-live-component #:initial (lambda () 0)
  #:render (lambda (n) (element 'p n))
  #:events (hash "inc" (lambda (n payload) (add1 n)))))
(define (bootstrap req #:shared? [shared? #f])
  (define-values (sid state cookie) (start-web-session sessions (if shared? 'shared 'guest) #:secure? #f))
  (define id (registry-mount! registry (web-session-csrf state) (if shared? shared-counter counter)))
  (define resp (json-response (hasheq 'id id 'csrf (web-session-csrf state))))
  (struct-copy response resp [headers (cons cookie (response-headers resp))]))
(module+ main
  (define stop (serve-live-websocket sessions registry #:origin "http://127.0.0.1:18884"
                                    #:port 18885 #:secure? #f #:bus bus
                                    #:resolve-topic (lambda (state id)
                                      (and (eq? (web-session-data state) 'shared) "shared-counter"))))
  (dynamic-wind void
    (lambda () (serve (make-app (list (route #"GET" "/" bootstrap)
      (route #"GET" "/shared" (lambda (req) (bootstrap req #:shared? #t)))
      (route #"GET" "/assets/live.mjs" (asset "live.mjs"))
      (route #"GET" "/assets/live-socket.mjs" (asset "live-socket.mjs"))
      (route #"GET" "/assets/live-socket-dom.mjs" (asset "live-socket-dom.mjs")))) #:port 18884))
    (lambda () (stop))))
