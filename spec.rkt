#lang typed/racket/base

(provide (all-defined-out))
(provide (rename-out [spec-begin example-begin]))
(provide spec-feature? spec-behavior? spec-feature-brief default-spec-issue-handler)
(provide make-spec-behavior make-spec-feature spec-behaviors-fold)
(provide define-feature define-scenario describe Spec-Summary Spec-Behavior Spec-Feature)

(provide (all-from-out "digitama/spec/issue.rkt"))
(provide (all-from-out "digitama/spec/expectation.rkt"))

(require "digitama/spec/issue.rkt")
(require "digitama/spec/prompt.rkt")
(require "digitama/spec/seed.rkt")

(require "digitama/spec/expectation.rkt")
(require "digitama/spec/behavior.rkt")
(require "digitama/spec/dsl.rkt")

(require "format.rkt")
(require "echo.rkt")

(require racket/string)

(require (for-syntax racket/base))

(define-syntax (spec-begin stx)
  (syntax-case stx [:]
    [(_ id expr ...)
     #'(begin (define-feature id expr ...)

              (void ((default-spec-handler) 'id id)))]))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-type Spec-Behavior-Prove (-> String (Listof String) (-> Void) Spec-Issue))
(define-type Spec-Issue-Fgcolor (-> Spec-Issue-Type Symbol))
(define-type Spec-Issue-Symbol (-> Spec-Issue-Type (U Char String)))
(define-type Spec-Prove-Pattern (U String Regexp '*))
(define-type Spec-Prove-Selector (Listof Spec-Prove-Pattern))

(define spec-behavior-prove : Spec-Behavior-Prove
  (lambda [brief namepath evaluation]
    ((inst spec-story Spec-Issue Spec-Issue)
     (gensym brief)
     (λ [] (parameterize ([default-spec-issue-brief brief])
             (with-handlers ([exn:fail? spec-misbehave])
               (evaluation)
               (make-spec-issue 'pass))))
     values)))

(define default-spec-handler : (Parameterof (-> Symbol Spec-Feature Any)) (make-parameter (λ [[id : Symbol] [spec : Spec-Feature]] (spec-prove spec))))
(define default-spec-behavior-prove : (Parameterof Spec-Behavior-Prove) (make-parameter spec-behavior-prove))
(define default-spec-issue-fgcolor : (Parameterof Spec-Issue-Fgcolor) (make-parameter spec-issue-fgcolor))
(define default-spec-issue-symbol : (Parameterof Spec-Issue-Symbol) (make-parameter spec-issue-moji))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define spec-summary-fold
  : (All (s) (-> (U Spec-Feature Spec-Behavior) s
                 #:downfold (-> String Index s s) #:upfold (-> String Index s s s) #:herefold (-> String Spec-Issue Index Natural Natural Natural s s)
                 [#:selector Spec-Prove-Selector]
                 (Pairof Spec-Summary s)))
  (lambda [feature seed:datum #:downfold downfold #:upfold upfold #:herefold herefold #:selector [selector null]]
    (define prove : Spec-Behavior-Prove (default-spec-behavior-prove))
    (define selectors : (Vectorof Spec-Prove-Pattern) (list->vector selector))
    (define selcount : Index (vector-length selectors))
    
    (parameterize ([current-custodian (make-custodian)]) ;;; Prevent test routines from shutting down the current custodian accidently.
      (define (downfold-feature [name : String] [pre-action : (-> Any)] [post-action : (-> Any)] [seed : (Spec-Seed s)]) : (Option (Spec-Seed s))
        (define namepath : (Listof String) (spec-seed-namepath seed))
        (define cursor : Index (length namepath))

        (and (or (>= cursor selcount)
                 (let ([pattern (vector-ref selectors cursor)])
                   (cond [(eq? pattern '*)]
                         [(string? pattern) (string=? pattern name)]
                         [else (regexp-match? pattern name)])))

             (let ([maybe-exn (with-handlers ([exn:fail? (λ [[e : exn:fail]] e)]) (pre-action) #false)])
               (spec-seed-copy seed (downfold name (length namepath) (spec-seed-datum seed)) (cons name namepath)
                               #:exceptions (cons maybe-exn (spec-seed-exceptions seed))))))
      
      (define (upfold-feature [name : String] [pre-action : (-> Any)] [post-action : (-> Any)] [seed : (Spec-Seed s)] [children-seed : (Spec-Seed s)]) : (Spec-Seed s)
        (with-handlers ([exn:fail? (λ [[e : exn]] (eprintf "[#:after] ~a" (exn-message e)))]) (post-action))
        (spec-seed-copy children-seed
                        (upfold name (length (spec-seed-namepath children-seed)) (spec-seed-datum seed) (spec-seed-datum children-seed))
                        (cdr (spec-seed-namepath children-seed))
                        #:exceptions (cdr (spec-seed-exceptions children-seed))))
      
      (define (fold-behavior [name : String] [action : (-> Void)] [seed : (Spec-Seed s)]) : (Spec-Seed s)
        (define fixed-action : (-> Void)
          (cond [(findf exn? (spec-seed-exceptions seed))
                 => (lambda [[e : exn:fail]] (λ [] (spec-misbehave e)))]
                [else action]))
        (define namepath : (Listof String) (spec-seed-namepath seed))
        (define-values (&issue cpu real gc) (time-apply (λ [] (prove name namepath fixed-action)) null))

        (spec-seed-copy seed (herefold name (car &issue) (length namepath) cpu real gc (spec-seed-datum seed)) namepath
                        #:summary (hash-update (spec-seed-summary seed) (spec-issue-type (car &issue)) add1 (λ [] 0))))

      (let ([s (spec-behaviors-fold downfold-feature upfold-feature fold-behavior (make-spec-seed seed:datum) feature)])
        (cons (spec-seed-summary s) (spec-seed-datum s))))))

(define spec-prove : (-> (U Spec-Feature Spec-Behavior) [#:selector Spec-Prove-Selector] Void)
  (lambda [feature #:selector [selector null]]
    (define ~fgcolor : Spec-Issue-Fgcolor (default-spec-issue-fgcolor))
    (define ~symbol : Spec-Issue-Symbol (default-spec-issue-symbol))
    
    (parameterize ([default-spec-issue-handler void])
      (define (downfold-feature [name : String] [indent : Index] [seed:orders : (Listof Natural)]) : (Listof Natural)
        (cond [(= indent 0) (echof #:fgcolor 'darkgreen #:attributes '(dim underline) "~a~n" name)]
              [else (echof "~a~a ~a~n" (~space (+ indent indent)) (string-join (map number->string (reverse seed:orders)) ".") name)])
        (cons 1 seed:orders))
      
      (define (upfold-feature [name : String] [indent : Index] [who-cares : (Listof Natural)] [children:orders : (Listof Natural)]) : (Listof Natural)
        (cond [(< indent 2) null]
              [else (cons (add1 (cadr children:orders))
                          (cddr children:orders))]))
      
      (define (fold-behavior [name : String] [issue : Spec-Issue] [indent : Index]
                             [cpu : Natural] [real : Natural] [gc : Natural] [seed:orders : (Listof Natural)]) : (Listof Natural)
        (define type : Spec-Issue-Type (spec-issue-type issue))
        (define headline : String (format "~a~a ~a - " (~space (+ indent indent)) (~symbol type) (if (null? seed:orders) 1 (car seed:orders))))
        (define headspace : String (~space (string-length headline)))

        (echof #:fgcolor (~fgcolor type) "~a~a" headline (spec-issue-brief issue))

        (case type
          [(pass) (echof #:fgcolor 'darkgrey " [~a real time, ~a gc time]~n" real gc)]
          [(misbehaved) (newline) (spec-issue-misbehavior-display issue #:indent headspace)]
          [(todo) (newline) (spec-issue-todo-display issue #:indent headspace)]
          [(skip) (newline) (spec-issue-skip-display issue #:indent headspace)]
          [(panic) (newline) (spec-issue-error-display issue #:indent headspace)])
        
        (if (null? seed:orders) null (cons (add1 (car seed:orders)) (cdr seed:orders))))

      (define-values (&summary cpu real gc)
        (time-apply (λ [] ((inst spec-summary-fold (Listof Natural))
                           feature null
                           #:downfold downfold-feature #:upfold upfold-feature #:herefold fold-behavior
                           #:selector selector))
                    null))

      (define summary : Spec-Summary (caar &summary))
      (define population : Natural (apply + (hash-values summary)))

      (if (positive? population)
          (let ([~s (λ [[ms : Natural]] : String (~r (* ms 0.001) #:precision '(= 3)))]
                [success (hash-ref summary 'pass (λ [] 0))]
                [misbehavior (hash-ref summary 'misbehaved (λ [] 0))]
                [panic (hash-ref summary 'panic (λ [] 0))]
                [todo (hash-ref summary 'todo (λ [] 0))]
                [skip (hash-ref summary 'skip (λ [] 0))])
            (echof #:fgcolor 'lightcyan "~nFinished in ~a wallclock seconds (~a task + ~a gc = ~a CPU).~n"
                   (~s real) (~s (max (- cpu gc) 0)) (~s gc) (~s cpu))
            (echof #:fgcolor 'lightcyan "~a, ~a, ~a, ~a, ~a, ~a% Okay.~n"
                   (~n_w population "sample") (~n_w misbehavior "misbehavior")
                   (~n_w panic "panic") (~n_w skip "skip") (~n_w todo "TODO")
                   (~r #:precision '(= 2) (/ (* (+ success skip) 100) population))))
          (echof #:fgcolor 'darkcyan "~nNo particular sample!~n")))))