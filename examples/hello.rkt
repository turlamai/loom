#lang racket/base
(require loom)
(define app (make-app (list (route #"GET" "/" (lambda (req) (html-response '(html (head (title "Loom")) (body (h1 "Hello, Loom!")))))))))
(module+ main (serve app))
