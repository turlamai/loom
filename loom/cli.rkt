#lang racket/base
(require racket/file racket/path racket/list racket/system json "db.rkt" "migrate.rkt")
(provide run-cli)
(define version "0.0.1")
(define (usage)
  (displayln "raco loom new <directory> | dev | test | doctor | inspect --json | migrate [--json]"))
(define app-source "#lang racket/base\n(require loom)\n(define app (make-app (list (route #\"GET\" \"/\" (lambda (req) (html-response '(html (head (title \"Loom\")) (body (h1 \"Hello, Loom!\")))))))))\n(module+ main (serve app))\n")
(define (write-new path content)
  (call-with-output-file path (lambda (out) (display content out)) #:exists 'error))
(define (scaffold target)
  (when (or (file-exists? target) (directory-exists? target) (link-exists? target))
    (error 'loom "target already exists"))
  (make-directory target)
  (write-new (build-path target "app.rkt") app-source)
  (write-new (build-path target "AGENTS.md") "# Application\n\nRun raco loom test before submitting changes. Keep routes and data contracts explicit.\n")
  (write-new (build-path target "loom-acceptance.rktd") "#hash((version . 1) (checks . (\"raco loom test\")))\n")
  (displayln "Created Loom application. Run raco loom dev from its directory."))
(define (project-app)
  (unless (file-exists? "app.rkt") (error 'loom "app.rkt not found in current directory"))
  (path->complete-path "app.rkt"))
;; Trusted project module exports a connection factory and an ordered plan.
(define (run-migrations json?)
  (unless (file-exists? "migrations.rkt")
    (error 'loom "migrations.rkt not found in current directory"))
  (define module-path (path->complete-path "migrations.rkt"))
  (define connect (dynamic-require module-path 'connect))
  (define plan (dynamic-require module-path 'migrations))
  (unless (and (procedure? connect) (procedure-arity-includes? connect 0))
    (error 'loom "migrations.rkt must export a zero-argument connect procedure"))
  (define applied
    (with-db connect (lambda (c) (migrate! c plan))))
  (if json?
      (begin (write-json (hasheq 'schema_version 1 'applied applied)) (newline))
      (if (null? applied)
          (displayln "Database is up to date.")
          (printf "Applied migrations: ~a\\n" applied))))
(define (run-cli args)
  (cond
    [(equal? args '("doctor"))
     (write-json (hasheq 'racket (version-string) 'loom version 'project (file-exists? "app.rkt"))) (newline)]
    [(equal? args '("inspect" "--json"))
     (write-json (hasheq 'schema_version 1 'framework "loom" 'version version
                         'project (file-exists? "app.rkt") 'entrypoint "app.rkt"
                         'acceptance (file-exists? "loom-acceptance.rktd")
                         'migrations (file-exists? "migrations.rkt"))) (newline)]
    [(and (= (length args) 2) (equal? (car args) "new")) (scaffold (cadr args))]
    [(equal? args '("dev")) (dynamic-require (list 'submod (project-app) 'main) #f)]
    [(equal? args '("migrate")) (run-migrations #f)]
    [(equal? args '("migrate" "--json")) (run-migrations #t)]
    [(equal? args '("test"))
     (define app (project-app))
     (define raco (find-executable-path "raco"))
     (unless (and raco (system* raco "test" (path->string app)))
       (error 'loom "tests failed"))]
    [(or (null? args) (equal? args '("--help"))) (usage)]
    [else (usage) (error 'loom "unknown command")]))
(define (version-string) (system-type 'vm) (racket-version))
(define racket-version (dynamic-require 'racket/base 'version))
(run-cli (vector->list (current-command-line-arguments)))
