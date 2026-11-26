#lang racket/base
(require racket/random)
(provide csrf-token csrf-valid?)
(define (csrf-token)
  (define digits "0123456789abcdef")
  (list->string
   (for*/list ([b (in-bytes (crypto-random-bytes 32))]
               [n (in-list (list (quotient b 16) (remainder b 16)))])
     (string-ref digits n))))
(define (token-format? v)
  (and (string? v) (= (string-length v) 64)
       (regexp-match? #rx"^[0-9a-f]+$" v)))
;; Fixed-length comparison; Racket does not promise machine-level constant time.
(define (csrf-valid? expected submitted)
  (and (token-format? expected) (token-format? submitted)
       (zero? (for/fold ([diff 0]) ([a (in-string expected)] [b (in-string submitted)])
                (bitwise-ior diff (bitwise-xor (char->integer a) (char->integer b)))))))
(module+ test
  (require rackunit)
  (define a (csrf-token))
  (check-equal? (string-length a) 64)
  (check-true (csrf-valid? a a))
  (check-false (csrf-valid? a (csrf-token)))
  (check-false (csrf-valid? a #f))
  (check-false (csrf-valid? a "short")))
