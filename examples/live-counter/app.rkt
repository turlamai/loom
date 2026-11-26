#lang racket/base
(require loom loom/html loom/live loom/live-registry loom/live-http loom/session loom/session-http loom/security
         web-server/http racket/runtime-path racket/file)
(define-runtime-path browser-runtime "../../loom/assets/live.mjs")
(define-runtime-path bootstrap "boot.mjs")
(define counter
  (make-live-component #:initial (lambda () 0)
    #:render (lambda (n)
      (element 'section
        (element 'p #:attrs '((id "count")) n)
        (element 'button #:attrs '((type "button") (data-live-event "inc")) "Increment")
        (element 'button #:attrs '((type "button") (data-live-event "dec")) "Decrement")))
    #:events (hash "inc" (lambda (n p) (add1 n)) "dec" (lambda (n p) (sub1 n)))))
(define sessions (make-session-store))
(define instances (make-live-registry))
(define (asset path)
  (lambda (req)
    (response/full 200 #f (current-seconds) #"text/javascript; charset=utf-8"
      (list (header #"Cache-Control" #"no-store")) (list (file->bytes path)))))
(define (home req)
  (define old (web-session-ref sessions req #:secure? #f))
  (define-values (state cookie)
    (if old (values old #f)
      (let-values ([(id state cookie) (start-web-session sessions 'guest #:secure? #f)])
        (values state cookie))))
  (define owner (web-session-csrf state))
  (define id (registry-mount! instances owner counter))
  (define result (registry-snapshot instances owner id))
  ;; Script is trusted static application markup, not a dynamic component.
  (define resp
    (html-response
      `(html ((lang "en"))
         (head (meta ((charset "utf-8"))) (title "Loom Live Counter")
               (script ((type "module") (src "/boot.mjs")) ""))
         (body (h1 "Live Counter")
               (div ((id "live") (data-id ,id) (data-csrf ,owner) (data-version "0"))
                    ,(live-result-view result))
               (p ((id "error") (role "status")) "")))))
  (struct-copy response resp
    [headers (append (response-headers resp) (list (header #"Cache-Control" #"no-store"))
                     (if cookie (list cookie) '()))]))
(define app
  (make-app (list (route #"GET" "/" home)
                  (route #"GET" "/live.mjs" (asset browser-runtime))
                  (route #"GET" "/boot.mjs" (asset bootstrap))
                  (route #"POST" "/live" (make-live-event-handler sessions instances #:secure? #f)))
            #:middleware (list security-headers)))
(module+ main
  (serve app #:port (string->number (or (getenv "LOOM_LIVE_PORT") "8080"))))
