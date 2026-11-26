#lang racket/base
(require racket/list)
(provide field field? make-model model? model-name model-fields define-model validate-model model-schema)
(struct field (name type required?) #:transparent)
(struct model (name fields) #:transparent)
(define types '(string integer boolean number))
(define (make-model name fields)
  (unless (and (symbol? name) (list? fields)
               (andmap (lambda (f) (and (field? f) (symbol? (field-name f))
                                       (memq (field-type f) types)
                                       (boolean? (field-required? f)))) fields))
    (error 'make-model "invalid model declaration"))
  (define names (map field-name fields))
  (unless (= (length names) (length (remove-duplicates names)))
    (error 'make-model "duplicate field"))
  (model name fields))
(define-syntax-rule (define-model name [key type required?] ...)
  (define name (make-model 'name (list (field 'key 'type required?) ...))))
(define (matches? type v)
  (case type
    [(string) (string? v)]
    [(integer) (exact-integer? v)]
    [(boolean) (boolean? v)]
    [(number) (or (exact-integer? v) (and (inexact-real? v) (< -inf.0 v +inf.0)))]
    [else #f]))
;; Input is a symbol-keyed hash. Return an ordered list of structured errors.
(define (validate-model m values)
  (unless (hash? values) (raise-argument-error 'validate-model "hash?" values))
  (define fields (model-fields m))
  (append
   (filter-map
    (lambda (f)
      (define name (field-name f))
      (cond [(not (hash-has-key? values name))
             (and (field-required? f) (hasheq 'field (symbol->string name) 'code "required"))]
            [(not (matches? (field-type f) (hash-ref values name)))
             (hasheq 'field (symbol->string name) 'code "invalid-type")]
            [else #f])) fields)
   (for/list ([key (in-list (sort (filter (lambda (k) (not (memq k (map field-name fields)))) (hash-keys values))
                                  string<? #:key (lambda (k) (format "~s" k))))])
     (hasheq 'field (format "~a" key) 'code "unknown-field"))))
(define (model-schema m)
  (hasheq 'type "object"
          'title (symbol->string (model-name m))
          'additionalProperties #f
          'properties (for/hasheq ([f (in-list (model-fields m))])
                        (values (field-name f) (hasheq 'type (symbol->string (field-type f)))))
          'required (for/list ([f (in-list (model-fields m))] #:when (field-required? f))
                      (symbol->string (field-name f)))))
(module+ test
  (require rackunit)
  (define-model user [name string #t] [age integer #f] [active boolean #t])
  (check-equal? (validate-model user (hasheq 'name "Alice" 'active #f)) '())
  (check-equal? (validate-model user (hasheq 'name 1 'extra "x"))
                (list (hasheq 'field "name" 'code "invalid-type")
                      (hasheq 'field "active" 'code "required")
                      (hasheq 'field "extra" 'code "unknown-field")))
  (check-equal? (hash-ref (model-schema user) 'required) '("name" "active"))
  (check-exn exn:fail? (lambda () (make-model 'x (list (field 'a 'string #t) (field 'a 'integer #f)))))
  (check-exn exn:fail? (lambda () (make-model 'x (list (field 'a 'unsupported #t)))))
  (define-model sample [amount number #t])
  (check-not-equal? (validate-model sample (hasheq 'amount +nan.0)) '()))
