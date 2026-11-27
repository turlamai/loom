#lang racket/base
(provide make-login-limiter login-attempt! login-limiter-reset!)
(struct bucket (count deadline) #:transparent)
(struct limiter (entries lock limit window capacity clock) #:transparent)
;; Fixed windows, process local. Keys must be derived by trusted application
;; code from canonical account identifiers or verified client addresses.
(define (make-login-limiter #:limit [limit 5] #:window [window 60]
                            #:capacity [capacity 10000] #:clock [clock current-inexact-monotonic-milliseconds])
  (unless (and (exact-positive-integer? limit) (exact-positive-integer? window)
               (exact-positive-integer? capacity) (procedure? clock))
    (error 'make-login-limiter "invalid limits"))
  (limiter (make-hash) (make-semaphore 1) limit (* window 1000) capacity clock))
(define (valid-key? key)
  (and (string? key) (<= 1 (string-length key) 512)))
;; Consume a permit before expensive credential verification. Return #t for
;; permission, or a positive retry delay in seconds. Exhausted capacity
;; fails closed instead of evicting live buckets and bypassing throttling.
(define (login-attempt! l key)
  (unless (valid-key? key) (raise-argument-error 'login-attempt! "bounded nonempty string" key))
  (call-with-semaphore (limiter-lock l)
    (lambda ()
      (define now ((limiter-clock l)))
      (define entries (limiter-entries l))
      (define b (hash-ref entries key #f))
      (when (and b (<= (bucket-deadline b) now))
        (hash-remove! entries key)
        (set! b #f))
      (cond
        [b
         (cond [(>= (bucket-count b) (limiter-limit l))
                (max 1 (inexact->exact (ceiling (/ (- (bucket-deadline b) now) 1000))))]
               [else
                (hash-set! entries (string->immutable-string key)
                  (bucket (add1 (bucket-count b)) (bucket-deadline b)))
                #t])]
        [else
         (when (>= (hash-count entries) (limiter-capacity l))
           (for ([k (in-list (hash-keys entries))])
             (when (<= (bucket-deadline (hash-ref entries k)) now)
               (hash-remove! entries k))))
         (if (>= (hash-count entries) (limiter-capacity l))
             (max 1 (inexact->exact (ceiling (/ (limiter-window l) 1000))))
             (begin
               (hash-set! entries (string->immutable-string key)
                          (bucket 1 (+ now (limiter-window l))))
               #t))]))))
;; Explicit administrative reset only; automatic reset on successful login
;; would allow successful credentials to replenish shared source quotas.
(define (login-limiter-reset! l key)
  (unless (valid-key? key) (raise-argument-error 'login-limiter-reset! "bounded nonempty string" key))
  (call-with-semaphore (limiter-lock l)
    (lambda () (hash-remove! (limiter-entries l) key))))
(module+ test
  (require rackunit)
  (define now 0)
  (define l (make-login-limiter #:limit 2 #:window 10 #:capacity 2 #:clock (lambda () now)))
  (check-eq? (login-attempt! l "alice") #t)
  (check-eq? (login-attempt! l "alice") #t)
  (check-equal? (login-attempt! l "alice") 10)
  (check-eq? (login-attempt! l "bob") #t)
  (check-equal? (login-attempt! l "other") 10)
  (set! now 9500)
  (check-equal? (login-attempt! l "alice") 1)
  (set! now 10000)
  (check-eq? (login-attempt! l "other") #t)
  (check-eq? (login-attempt! l "alice") #t)
  (login-limiter-reset! l "alice")
  (check-eq? (login-attempt! l "alice") #t)
  (define concurrent (make-login-limiter #:limit 1))
  (define ch (make-channel))
  (for ([i (in-range 8)])
    (thread (lambda () (channel-put ch (login-attempt! concurrent "same")))))
  (check-equal? (for/sum ([i (in-range 8)]) (if (eq? (channel-get ch) #t) 1 0)) 1)
  (check-exn exn:fail? (lambda () (login-attempt! l ""))))
