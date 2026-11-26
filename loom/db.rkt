#lang racket/base
(require db)
(provide open-sqlite open-postgres with-db with-transaction
         query-exec query-row query-rows query-value query-maybe-row query-maybe-value
         disconnect)
(define (open-sqlite path #:mode [mode 'create])
  (sqlite3-connect #:database path #:mode mode))
(define (open-postgres #:database database #:user user #:password password
                       #:server [server "localhost"] #:port [port 5432] #:ssl [ssl 'yes])
  (postgresql-connect #:database database #:user user #:password password
                      #:server server #:port port #:ssl ssl))
(define (with-db connect proc)
  (define conn (connect))
  (dynamic-wind void (lambda () (proc conn)) (lambda () (disconnect conn))))
(define (with-transaction conn proc)
  (call-with-transaction conn (lambda () (proc conn))))
(module+ test
  (require rackunit)
  (with-db (lambda () (open-sqlite 'memory))
    (lambda (conn)
      (query-exec conn "CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL)")
      (with-transaction conn (lambda (c) (query-exec c "INSERT INTO tasks (title) VALUES (?)" "one")))
      (check-equal? (query-value conn "SELECT title FROM tasks WHERE id = ?" 1) "one")
      (check-exn exn:fail? (lambda ()
        (with-transaction conn (lambda (c)
          (query-exec c "INSERT INTO tasks (title) VALUES (?)" "rollback")
          (error 'test "abort")))))
      (check-equal? (query-value conn "SELECT count(*) FROM tasks") 1))))
