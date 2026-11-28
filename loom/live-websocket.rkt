#lang racket/base
(require net/rfc6455 net/url json web-server/http "http.rkt" "session-http.rkt" "live-channel.rkt" "live-bus.rkt" "live-registry.rkt")
(provide serve-live-websocket)
;; Dedicated loopback listener. Deploy behind a TLS reverse proxy.
(define (serve-live-websocket store registry #:origin origin #:port [port 8081]
                              #:secure? [secure? #t] #:max-connections [maximum 64]
                              #:max-bytes [limit 16384]
                              #:bus [bus #f] #:resolve-topic [resolve-topic #f])
  (unless (and (string? origin) (regexp-match? #px"^https?://[A-Za-z0-9.:-]+$" origin)
               (or (and (not bus) (not resolve-topic))
                   (and bus (procedure? resolve-topic) (procedure-arity-includes? resolve-topic 2)))
               (exact-integer? maximum) (<= 1 maximum 1024)
               (exact-integer? limit) (<= 1 limit 65536))
    (error 'serve-live-websocket "invalid transport configuration"))
  (define slots (make-semaphore maximum))
  (define (allowed? req)
    (and (request? req)
         (equal? (request-header-values req #"Origin") (list (string->bytes/utf-8 origin)))
         (equal? (map path/param-path (url-path (request-uri req))) '("live"))
         (web-session-ref store req #:secure? secure?)))
  (define (handle conn req)
    (cond
      [(not (and (ws-conn-supports-fragmentation? conn) (allowed? req)))
       (ws-close! conn #:status 1008)]
      [(not (semaphore-try-wait? slots)) (ws-close! conn #:status 1013)]
      [else
       (define subscription #f)
       (define owner #f)
       (define notifier #f)
       (define send-lock (make-semaphore 1))
       (define (lookup) (web-session-ref store req #:secure? secure?))
       (define (send result)
         (call-with-semaphore send-lock (lambda () (ws-send! conn (jsexpr->string result)))))
       (define (bind state id)
         (when bus
           (define topic (resolve-topic state id))
           (when topic
             (set! owner (web-session-csrf state))
             (set! subscription (live-subscribe! bus owner topic))
             (set! notifier
               (thread (lambda ()
                 (with-handlers ([exn:fail? (lambda (_) (void))])
                   (let loop ()
                     (when (eq? (sync (live-next-evt bus subscription)) 'changed)
                       (define current (lookup))
                       (when (and current (equal? owner (web-session-csrf current))
                                  (equal? topic (resolve-topic current id))
                                  (registry-snapshot registry owner id))
                         (send (hasheq 'type "invalidate"))
                         (loop)))))))))))
       (dynamic-wind
         void
         (lambda ()
           (define channel (make-live-channel registry
                             lookup #:on-bind bind #:max-bytes limit))
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
                    (send result)
                    (if (member (hash-ref result 'error #f) '("forbidden" "closed" "instance-not-found"))
                        (ws-close! conn #:status 1008)
                        (loop))])))))
         (lambda ()
           (when notifier (kill-thread notifier))
           (when subscription (live-unsubscribe! bus owner subscription))
           (semaphore-post slots) (ws-close! conn)))]))
  (ws-serve handle
            #:conn-headers (lambda (_line _headers req) (values '() req))
            #:port port #:listen-ip "127.0.0.1"))
