#lang racket/base
(require loom loom/model loom/openapi loom/security)
(define-model task-input [title string #t])
(define-model task-output [id string #t] [title string #t])
(define app
  (make-api-app
    (list (api-operation #"POST" "/tasks/:id" "createTask"
            (lambda (req data) (hash-set data 'id (route-param "id")))
            #:input task-input #:output task-output #:status 201))
    #:title "Loom JSON API example" #:middleware (list security-headers)))
(module+ main
  (serve app #:port 8080))
