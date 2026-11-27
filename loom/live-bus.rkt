#lang racket/base
(require "csrf.rkt")
(provide make-live-bus live-subscribe! live-unsubscribe! live-publish!
         live-subscription? live-next-evt live-revoke-owner!)
;; Bounded, coalescing invalidation notifications, not a durable message queue.
;; Topics are application-defined strings. The trusted application authorizes
;; topic membership before subscribing. No callbacks run under the bus lock.
(struct bus (entries lock capacity per-owner) #:transparent)
(struct live-subscription (id owner topic ready active pending) #:mutable)
(define (make-live-bus #:capacity [capacity 1024] #:per-owner [per-owner 16])
  (unless (and (exact-positive-integer? capacity) (exact-positive-integer? per-owner))
    (error 'make-live-bus "positive limits required"))
  (bus (make-hash) (make-semaphore 1) capacity per-owner))
(define (locked b proc) (call-with-semaphore (bus-lock b) proc))
(define (valid-name? s) (and (string? s) (<= 1 (string-length s) 256)))
(define (live-subscribe! b owner topic)
  (unless (and (valid-name? owner) (valid-name? topic))
    (error 'live-subscribe! "invalid owner or topic"))
  (locked b
    (lambda ()
      (define entries (bus-entries b))
      (when (or (>= (hash-count entries) (bus-capacity b))
                (>= (for/sum ([s (in-hash-values entries)]
                              #:when (equal? owner (live-subscription-owner s))) 1)
                    (bus-per-owner b)))
        (error 'live-subscribe! "subscription capacity reached"))
      (define id (let loop () (define candidate (csrf-token))
                   (if (hash-has-key? entries candidate) (loop) candidate)))
      (define s (live-subscription id (string->immutable-string owner)
                                  (string->immutable-string topic) (make-semaphore 0) #t #f))
      (hash-set! entries id s)
      s)))
(define (close/locked! b s)
  (when (live-subscription-active s)
    (set-live-subscription-active! s #f)
    (hash-remove! (bus-entries b) (live-subscription-id s))
    (unless (live-subscription-pending s)
      (semaphore-post (live-subscription-ready s)))))
(define (live-unsubscribe! b owner s)
  (locked b
    (lambda ()
      (and (eq? s (hash-ref (bus-entries b) (live-subscription-id s) #f))
           (equal? owner (live-subscription-owner s))
           (begin (close/locked! b s) #t)))))
(define (live-revoke-owner! b owner)
  (locked b
    (lambda ()
      (for ([s (in-list (hash-values (bus-entries b)))]
            #:when (equal? owner (live-subscription-owner s)))
        (close/locked! b s)))))
(define (live-publish! b topic)
  (unless (valid-name? topic) (error 'live-publish! "invalid topic"))
  (locked b
    (lambda ()
      (for/sum ([s (in-hash-values (bus-entries b))]
                #:when (equal? topic (live-subscription-topic s)))
        (unless (live-subscription-pending s)
          (set-live-subscription-pending! s #t)
          (semaphore-post (live-subscription-ready s)))
        1))))
;; A single consumer per subscription. Returns 'changed or 'closed.
;; Peek then consume under the lock to avoid losing concurrent notifications.
(define (live-next-evt b s)
  (wrap-evt (semaphore-peek-evt (live-subscription-ready s))
    (lambda (_)
      (locked b
        (lambda ()
          (cond
            [(not (live-subscription-active s)) 'closed]
            [(not (eq? s (hash-ref (bus-entries b) (live-subscription-id s) #f)))
             (error 'live-next-evt "subscription belongs to another bus")]
            [(live-subscription-pending s)
             (semaphore-try-wait? (live-subscription-ready s))
             (set-live-subscription-pending! s #f)
             'changed]
            [else 'idle]))))))
(module+ test
  (require rackunit)
  (define b (make-live-bus #:capacity 3 #:per-owner 1))
  (define a (live-subscribe! b "alice" "tasks"))
  (define c (live-subscribe! b "bob" "tasks"))
  (define d (live-subscribe! b "carol" "other"))
  (check-exn exn:fail? (lambda () (live-subscribe! b "alice" "other")))
  (check-exn exn:fail? (lambda () (live-subscribe! b "dan" "other")))
  (check-false (sync/timeout 0 (live-next-evt b a)))
  (for ([i (in-range 100)]) (check-equal? (live-publish! b "tasks") 2))
  (check-equal? (sync/timeout 0 (live-next-evt b a)) 'changed)
  (check-false (sync/timeout 0 (live-next-evt b a)))
  (check-equal? (sync/timeout 0 (live-next-evt b c)) 'changed)
  (check-false (sync/timeout 0 (live-next-evt b d)))
  (check-false (live-unsubscribe! b "bob" a))
  (check-true (live-unsubscribe! b "alice" a))
  (check-equal? (sync/timeout 0 (live-next-evt b a)) 'closed)
  (live-revoke-owner! b "bob")
  (check-equal? (sync/timeout 0 (live-next-evt b c)) 'closed)
  (check-equal? (live-publish! b "tasks") 0)
  (check-true (live-subscription? (live-subscribe! b "alice" "tasks"))))
