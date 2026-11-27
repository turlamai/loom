#lang racket/base
(require net/rfc6455 net/url json web-server/http "http.rkt" "session-http.rkt" "live-channel.rkt")
(provide serve-live-websocket)
;; Dedicated loopback listener. Deploy behind a TLS reverse proxy.
(define (serve-live-websocket store registry #:origin origin #:port [port 8081]
                              #:secure? [secure? #t] #:max-connections [maximum 64]
                              #:max-bytes [limit 16384])
  (unless (and (string? origin) (regexp-match? #px"^https?://[A-Za-z0-9.:-]+$" origin)
               (exact-integer? maximum) (<= 1 maximum 1024)
               (exact-integer? limit) (<= 1 limit 65536))
    (error 'serve-live-websocket "invalid transport configuration"))
  (define slots (make-semaphore maximum))
  (define (allowed? req)
    (and (equal? (request-header-values req #"Origin") (list (string->bytes/utf-8 origin)))
         (equal? (map path/param-path (url-path (request-uri req))) '("live"))
         (web-session-ref store req #:secure? secure?)))
  (define (handle conn req)
    (cond
      [(not (and (ws-conn-supports-fragmentation? conn) (allowed? req)))
       (ws-close! conn #:status 1008)]
      [(not (semaphore-try-wait? slots)) (ws-close! conn #:status 1013)]
      [else
       (dynamic-wind
         void
         (lambda ()
           (define channel (make-live-channel registry
                             (lambda () (web-session-ref store req #:secure? secure?))
                             #:max-bytes limit))
           (with-handlers ([exn:fail? (lambda (_) (ws-close! conn #:status 1011))])
             (let loop ()
               (unless (ws-conn-closed? conn)
                 (define in (ws-recv-stream conn))
                 (define raw (read-bytes (add1 limit) in))
                 (cond
                   [(or (eof-object? raw) (ws-conn-closed? conn)) (ws-close! conn)]
                   [(> (bytes-length raw) limit) (ws-close! conn #:status 1009)]
                   [else
                    (close-input-port in)
                    (define result (channel raw))
                    (ws-send! conn (jsexpr->string result))
                    (if (member (hash-ref result 'error #f) '("forbidden" "closed" "instance-not-found"))
                        (ws-close! conn #:status 1008)
                        (loop))])))))
         (lambda () (semaphore-post slots) (ws-close! conn)))]))
  (ws-serve handle #:port port #:listen-ip "127.0.0.1"))
