#lang racket/base

(provide
 w3-max-depth
 w1-inputs w1-monadic w1-plain w1-case
 w2-inputs w2-monadic w2-plain-box w2-plain-threaded w2-case
 w3-inputs w3-monadic w3-plain w3-case
 w4-inputs w4-monadic w4-plain w4-case
 w5-inputs w5-monadic w5-plain w5-case)

(require
 "case.rkt"
 "handlers.rkt"
 "../main.rkt")

;; ============================================================
;; Shared helpers
;; ============================================================

;; Wraps a log sink so that the calls per level are counted.
;; Type: (-> (-> Any Void) (Values (-> Any Void) HashEq))
(define (counting-sink sink)
  (define counts (make-hasheq))
  (values (lambda (e)
            (hash-update! counts (log-effect-level e) add1 0)
            (sink e))
          counts))

;; Type: (-> HashEq (Listof (Pair Symbol Natural)))
(define (level-counts counts)
  (for/list ([level (in-list '(DEBUG INFO ERROR))])
    (cons level (hash-ref counts level 0))))

;; Type: (-> Natural Natural)
(define (identity-ops n) n)

;; ============================================================
;; W1 request-handling pipeline (env, log, failure)
;; ============================================================

(struct request (id amount text))
(struct invalid ())

(define w1-limit 1000)

;; Type: (-> Natural (Values (Listof request) HashEq))
(define (w1-inputs n)
  (values (for/list ([i (in-range n)])
            (request i
                     (if (= 7 (modulo i 8))
                         (+ w1-limit 1 (modulo i 50))
                         (modulo (* i 37) w1-limit))
                     (format "item-~a" i)))
          (hasheq 'limit w1-limit 'mode 'strict 'label "w1")))

;; Type: (->* (Natural) ((-> Any Void)) (-> Any))
(define (w1-monadic n [sink null-log-sink])
  (define-values (requests config) (w1-inputs n))
  (lambda ()
    (define-values (counted counts) (counting-sink sink))
    (define responses
      (run (map-m w1-request-m requests)
           (bench-handler '(env log failure) config counted)))
    (list responses (level-counts counts))))

;; Type: (-> request Free)
(define (w1-request-m req)
  (do-m [response <- (catch (w1-answer-m req))]
        (if (eq? (cadr response) 'ok)
            (log-inf "request ~a ok" (request-id req))
            (log-err "request ~a rejected" (request-id req)))
        (return response)))

;; Type: (-> request Free)
(define (w1-answer-m req)
  (do-m [limit <- (read-env 'limit)]
        [mode <- (read-env 'mode)]
        [label <- (read-env 'label)]
        (try (if (<= (request-amount req) limit)
                 (return #t)
                 (failure "invalid request"))
             (return (list (request-id req) 'error)))
        (return (w1-ok-response req mode label))))

;; Type: (-> request Symbol String (Listof Any))
(define (w1-ok-response req mode label)
  (define amount (+ (request-amount req) (string-length (request-text req))))
  (list (request-id req) 'ok (if (eq? mode 'strict) amount (* 2 amount)) label))

;; Type: (->* (Natural) ((-> Any Void)) (-> Any))
(define (w1-plain n [sink null-log-sink])
  (define-values (requests config) (w1-inputs n))
  (lambda ()
    (define-values (counted counts) (counting-sink sink))
    (define responses
      (for/list ([req (in-list requests)])
        (w1-plain-request req config counted)))
    (list responses (level-counts counts))))

;; Type: (-> request HashEq (-> Any Void) (Listof Any))
(define (w1-plain-request req config sink)
  (define response
    (with-handlers ([invalid? (lambda (e) (list (request-id req) 'error))])
      (let ([limit (hash-ref config 'limit)]
            [mode (hash-ref config 'mode)]
            [label (hash-ref config 'label)])
        (when (> (request-amount req) limit)
          (raise (invalid)))
        (w1-ok-response req mode label))))
  (if (eq? (cadr response) 'ok)
      (sink (log-effect 'INFO (format "request ~a ok" (request-id req))))
      (sink (log-effect 'ERROR (format "request ~a rejected" (request-id req)))))
  response)

;; Type: (-> (Listof bench-case))
(define (w1-case)
  (list (bench-case 'w1 'default pilot-sizes identity-ops w1-monadic w1-plain equal?)))

;; ============================================================
;; W2 stateful ledger (state, log)
;; ============================================================

(struct txn (source target amount))

(define w2-account-count 16)
(define w2-opening-balance 1000)

;; Type: (-> (Listof Symbol))
(define (w2-account-names)
  (for/list ([i (in-range w2-account-count)])
    (string->symbol (format "a~a" (if (< i 10) (format "0~a" i) i)))))

;; Type: (-> Natural (Values (Listof (Pair Symbol Natural)) (Listof txn)))
(define (w2-inputs n)
  (define names (list->vector (w2-account-names)))
  (values (for/list ([name (in-vector names)]) (cons name w2-opening-balance))
          (for/list ([i (in-range n)])
            (txn (vector-ref names (modulo i 16))
                 (vector-ref names (modulo (+ 3 (* 5 i)) 16))
                 (if (= 19 (modulo i 20))
                     100000
                     (+ 1 (modulo (* i 13) 20)))))))

;; Type: (->* (Natural) ((-> Any Void)) (-> Any))
(define (w2-monadic n [sink null-log-sink])
  (define-values (accounts transactions) (w2-inputs n))
  (lambda ()
    (define store (make-state-store (cons (cons 'rejected 0) accounts)))
    (run (w2-loop-m transactions 0)
         (bench-handler '(state log) store sink))
    (w2-result (map car accounts) (hash-ref store 'rejected) (lambda (a) (hash-ref store a)))))

;; Type: (-> (Listof txn) Natural Free)
(define (w2-loop-m transactions i)
  (if (null? transactions)
      (return (void))
      (>>= (w2-txn-m i (car transactions))
           (lambda (_) (w2-loop-m (cdr transactions) (add1 i))))))

;; Type: (-> Natural txn Free)
(define (w2-txn-m i t)
  (do-m [balance <- (read-state (txn-source t))]
        (if (< balance (txn-amount t))
            (do-m (update-state 'rejected add1)
                  (log-inf "rejected ~a" i))
            (do-m [target-balance <- (read-state (txn-target t))]
                  (write-state (txn-source t) (- balance (txn-amount t)))
                  (write-state (txn-target t) (+ target-balance (txn-amount t)))))
        (if (= 63 (modulo i 64))
            (log-inf "processed ~a" (add1 i))
            (return (void)))))

;; Type: (-> (Listof Symbol) Natural (-> Symbol Natural) (Listof Any))
(define (w2-result names rejected balance-of)
  (list (for/list ([a (in-list names)]) (cons a (balance-of a))) rejected))

;; Applies one transaction to an immutable ledger that also holds 'rejected.
;; Type: (-> HashEq Natural txn (-> Any Void) HashEq)
(define (w2-apply ledger i t sink)
  (define balance (hash-ref ledger (txn-source t)))
  (define after
    (cond [(< balance (txn-amount t))
           (sink (log-effect 'INFO (format "rejected ~a" i)))
           (hash-update ledger 'rejected add1)]
          [else
           (define target-balance (hash-ref ledger (txn-target t)))
           (hash-set (hash-set ledger (txn-source t) (- balance (txn-amount t)))
                     (txn-target t) (+ target-balance (txn-amount t)))]))
  (when (= 63 (modulo i 64))
    (sink (log-effect 'INFO (format "processed ~a" (add1 i)))))
  after)

;; Type: (-> (Listof (Pair Symbol Natural)) HashEq)
(define (w2-opening-ledger accounts)
  (for/fold ([ledger (hasheq 'rejected 0)]) ([a (in-list accounts)])
    (hash-set ledger (car a) (cdr a))))

;; Type: (-> (Listof (Pair Symbol Natural)) HashEq (Listof Any))
(define (w2-ledger-result accounts ledger)
  (w2-result (map car accounts) (hash-ref ledger 'rejected) (lambda (a) (hash-ref ledger a))))

;; Type: (->* (Natural) ((-> Any Void)) (-> Any))
(define (w2-plain-box n [sink null-log-sink])
  (define-values (accounts transactions) (w2-inputs n))
  (lambda ()
    (define state (box (w2-opening-ledger accounts)))
    (for ([t (in-list transactions)] [i (in-naturals)])
      (set-box! state (w2-apply (unbox state) i t sink)))
    (w2-ledger-result accounts (unbox state))))

;; Type: (->* (Natural) ((-> Any Void)) (-> Any))
(define (w2-plain-threaded n [sink null-log-sink])
  (define-values (accounts transactions) (w2-inputs n))
  (lambda ()
    (define ledger
      (for/fold ([ledger (w2-opening-ledger accounts)])
                ([t (in-list transactions)] [i (in-naturals)])
        (w2-apply ledger i t sink)))
    (w2-ledger-result accounts ledger)))

;; Type: (-> (Listof bench-case))
(define (w2-case)
  (list (bench-case 'w2 'box pilot-sizes identity-ops w2-monadic w2-plain-box equal?)
        (bench-case 'w2 'threaded pilot-sizes identity-ops w2-monadic w2-plain-threaded equal?)))

;; ============================================================
;; W3 parser with backtracking (env, failure)
;; ============================================================

;; Parse results are (vector tree position backtracks), or #f when nothing matches.
;; Grammar: program = expr (';' expr)* [';'], expr = term (('+'|'-') term)*,
;; term = factor (('*'|'/') factor)*, factor = call | ident | number | paren,
;; call = ident '(' expr ')', paren = '(' expr ')'.

(define w3-max-depth 64)

(define w3-templates
  '("12+34*x" "foo(7)-2" "(a+b)*(c-d)" "f(g(h(1)))" "x*(y+(z-3))" "abc" "(1)"
    "fn(a+b*2)/3" "7*8-9" "val+(2)" "k(k(k(5)))+y"))

;; A parenthesised number nested depth levels deep.
;; Type: (-> Natural String)
(define (w3-nested depth)
  (string-append (make-string depth #\() "1" (make-string depth #\))))

;; Type: (-> Natural Natural String)
(define (w3-piece i budget)
  (define nested (w3-nested (add1 (modulo (* i 7) w3-max-depth))))
  (define plain (list-ref w3-templates (modulo i (length w3-templates))))
  (cond [(and (zero? (modulo i 5)) (<= (add1 (string-length nested)) budget)) nested]
        [(<= (add1 (string-length plain)) budget) plain]
        [else "1"]))

;; The text has exactly n characters.
;; Type: (-> Natural String)
(define (w3-inputs n)
  (let loop ([i 0] [remaining n] [pieces '()])
    (cond [(zero? remaining) (apply string-append (reverse pieces))]
          [(= remaining 1) (apply string-append (reverse (cons "1" pieces)))]
          [else
           (define piece (w3-piece i remaining))
           (define chunk (string-append piece ";"))
           (loop (add1 i) (- remaining (string-length chunk)) (cons chunk pieces))])))

;; --- monadic parser ---

;; Type: (-> Natural Free)
(define (m-peek pos)
  (do-m [text <- (read-env 'text)]
        (return (and (< pos (string-length text)) (string-ref text pos)))))

;; Type: (-> (-> Char Boolean) Natural Free)
(define (m-span pred pos)
  (do-m [c <- (m-peek pos)]
        (if (and c (pred c))
            (m-span pred (add1 pos))
            (return pos))))

;; Aborts to the nearest catch, which then yields #f.
;; Type: (-> Free)
(define (m-fail)
  (try (failure "no match") (return #f)))

;; Type: (-> (-> Char Boolean) (-> Char Boolean) Natural Free)
(define (m-token start? continue? pos)
  (do-m [c <- (m-peek pos)]
        (if (and c (start? c))
            (do-m [end <- (m-span continue? (add1 pos))]
                  [text <- (read-env 'text)]
                  (return (vector (substring text pos end) end)))
            (m-fail))))

;; Type: (-> Char Natural Free)
(define (m-lit ch pos)
  (do-m [c <- (m-peek pos)]
        (if (eqv? c ch) (return (add1 pos)) (m-fail))))

;; Type: (-> (Listof procedure) Natural Natural Free)
(define (m-first alts pos bt)
  (if (null? alts)
      (return #f)
      (do-m [r <- (catch ((car alts) pos bt))]
            (if r
                (return r)
                (m-first (cdr alts) pos (add1 bt))))))

;; Type: (-> (-> Natural Natural Free) (Listof Char) Natural Natural Free)
(define (m-chain sub ops pos bt)
  (do-m [first-result <- (sub pos bt)]
        (if first-result
            (m-chain-rest sub ops (vector-ref first-result 0)
                          (vector-ref first-result 1) (vector-ref first-result 2))
            (return #f))))

;; Type: (-> (-> Natural Natural Free) (Listof Char) Any Natural Natural Free)
(define (m-chain-rest sub ops left pos bt)
  (do-m [c <- (m-peek pos)]
        (if (and c (memv c ops))
            (do-m [right <- (sub (add1 pos) bt)]
                  (if right
                      (m-chain-rest sub ops
                                    (list c left (vector-ref right 0))
                                    (vector-ref right 1) (vector-ref right 2))
                      (return #f)))
            (return (vector left pos bt)))))

;; Type: (-> Natural Natural Free)
(define (m-expr pos bt) (m-chain m-term '(#\+ #\-) pos bt))

;; Type: (-> Natural Natural Free)
(define (m-term pos bt) (m-chain m-factor '(#\* #\/) pos bt))

;; Type: (-> Natural Natural Free)
(define (m-factor pos bt)
  (m-first (list m-call m-ident m-number m-paren) pos bt))

;; Type: (-> Natural Natural Free)
(define (m-call pos bt)
  (do-m [name <- (m-token char-alphabetic? char-alphabetic-or-numeric? pos)]
        [open <- (m-lit #\( (vector-ref name 1))]
        [inner <- (m-expr open bt)]
        (if inner
            (do-m [close <- (m-lit #\) (vector-ref inner 1))]
                  (return (vector (list 'call (string->symbol (vector-ref name 0)) (vector-ref inner 0))
                                  close (vector-ref inner 2))))
            (m-fail))))

;; Type: (-> Natural Natural Free)
(define (m-ident pos bt)
  (do-m [name <- (m-token char-alphabetic? char-alphabetic-or-numeric? pos)]
        (return (vector (string->symbol (vector-ref name 0)) (vector-ref name 1) bt))))

;; Type: (-> Natural Natural Free)
(define (m-number pos bt)
  (do-m [digits <- (m-token char-numeric? char-numeric? pos)]
        (return (vector (string->number (vector-ref digits 0)) (vector-ref digits 1) bt))))

;; Type: (-> Natural Natural Free)
(define (m-paren pos bt)
  (do-m [open <- (m-lit #\( pos)]
        [inner <- (m-expr open bt)]
        (if inner
            (do-m [close <- (m-lit #\) (vector-ref inner 1))]
                  (return (vector (vector-ref inner 0) close (vector-ref inner 2))))
            (m-fail))))

;; Type: (-> Natural Natural (Listof Any) Free)
(define (m-program pos bt trees)
  (do-m [r <- (m-expr pos bt)]
        (if (not r)
            (return (cons (cons 'program (reverse trees)) bt))
            (do-m [c <- (m-peek (vector-ref r 1))]
                  (if (eqv? c #\;)
                      (m-program (add1 (vector-ref r 1)) (vector-ref r 2) (cons (vector-ref r 0) trees))
                      (return (cons (cons 'program (reverse (cons (vector-ref r 0) trees)))
                                    (vector-ref r 2))))))))

;; Type: (-> Char Boolean)
(define (char-alphabetic-or-numeric? c)
  (or (char-alphabetic? c) (char-numeric? c)))

;; Type: (-> Natural (-> Any))
(define (w3-monadic n)
  (define text (w3-inputs n))
  (lambda ()
    (run (m-program 0 0 '())
         (bench-handler '(env failure) (hasheq 'text text)))))

;; --- plain parser ---

(struct no-match ())

;; Type: (-> HashEq Natural (U Char #f))
(define (p-peek config pos)
  (define text (hash-ref config 'text))
  (and (< pos (string-length text)) (string-ref text pos)))

;; Type: (-> HashEq (-> Char Boolean) (-> Char Boolean) Natural (Values String Natural))
(define (p-token config start? continue? pos)
  (define c (p-peek config pos))
  (unless (and c (start? c))
    (raise (no-match)))
  (define end
    (let loop ([p (add1 pos)])
      (define d (p-peek config p))
      (if (and d (continue? d)) (loop (add1 p)) p)))
  (values (substring (hash-ref config 'text) pos end) end))

;; Type: (-> HashEq Char Natural Natural)
(define (p-lit config ch pos)
  (if (eqv? (p-peek config pos) ch)
      (add1 pos)
      (raise (no-match))))

;; Type: (-> (Listof procedure) Natural Natural (U (Vectorof Any) #f))
(define (p-first alts pos bt)
  (cond [(null? alts) #f]
        [else
         (define r (with-handlers ([no-match? (lambda (e) #f)])
                     ((car alts) pos bt)))
         (or r (p-first (cdr alts) pos (add1 bt)))]))

;; Type: (-> HashEq (-> Natural Natural Any) (Listof Char) Natural Natural Any)
(define (p-chain config sub ops pos bt)
  (define first-result (sub pos bt))
  (and first-result
       (let loop ([left (vector-ref first-result 0)]
                  [pos (vector-ref first-result 1)]
                  [bt (vector-ref first-result 2)])
         (define c (p-peek config pos))
         (cond [(and c (memv c ops))
                (define right (sub (add1 pos) bt))
                (and right
                     (loop (list c left (vector-ref right 0))
                           (vector-ref right 1) (vector-ref right 2)))]
               [else (vector left pos bt)]))))

;; Type: (-> HashEq (-> (Listof Any) Natural Natural Any))
(define (p-parse-program config)
  (define (expr pos bt) (p-chain config term '(#\+ #\-) pos bt))
  (define (term pos bt) (p-chain config factor '(#\* #\/) pos bt))
  (define (factor pos bt) (p-first (list call ident number paren) pos bt))
  (define (name-token pos)
    (p-token config char-alphabetic? char-alphabetic-or-numeric? pos))
  (define (call pos bt)
    (define-values (name end) (name-token pos))
    (define open (p-lit config #\( end))
    (define inner (expr open bt))
    (unless inner (raise (no-match)))
    (define close (p-lit config #\) (vector-ref inner 1)))
    (vector (list 'call (string->symbol name) (vector-ref inner 0)) close (vector-ref inner 2)))
  (define (ident pos bt)
    (define-values (name end) (name-token pos))
    (vector (string->symbol name) end bt))
  (define (number pos bt)
    (define-values (digits end) (p-token config char-numeric? char-numeric? pos))
    (vector (string->number digits) end bt))
  (define (paren pos bt)
    (define open (p-lit config #\( pos))
    (define inner (expr open bt))
    (unless inner (raise (no-match)))
    (define close (p-lit config #\) (vector-ref inner 1)))
    (vector (vector-ref inner 0) close (vector-ref inner 2)))
  (lambda (trees pos bt)
    (let loop ([pos pos] [bt bt] [trees trees])
      (define r (expr pos bt))
      (cond [(not r) (cons (cons 'program (reverse trees)) bt)]
            [(eqv? (p-peek config (vector-ref r 1)) #\;)
             (loop (add1 (vector-ref r 1)) (vector-ref r 2) (cons (vector-ref r 0) trees))]
            [else (cons (cons 'program (reverse (cons (vector-ref r 0) trees)))
                        (vector-ref r 2))]))))

;; Type: (-> Natural (-> Any))
(define (w3-plain n)
  (define text (w3-inputs n))
  (lambda ()
    ((p-parse-program (hasheq 'text text)) '() 0 0)))

;; Type: (-> (Listof bench-case))
(define (w3-case)
  (list (bench-case 'w3 'default pilot-sizes identity-ops w3-monadic w3-plain equal?)))

;; ============================================================
;; W4 recursive tree traversal (state, log)
;; ============================================================

;; An empty tree is #f.
(struct tnode (label left right))

;; The node count for a complete tree: the 2^k - 1 nearest to n.
;; Type: (-> Natural Natural)
(define (w4-node-count n)
  (let loop ([k 0])
    (define here (sub1 (expt 2 k)))
    (define next (sub1 (expt 2 (add1 k))))
    (if (<= (- n here) (- next n))
        here
        (loop (add1 k)))))

;; Type: (-> Natural Natural)
(define (w4-label i) (modulo (* 31 i) 97))

;; Type: (->* (Natural) (#:variant Symbol) (U tnode #f))
(define (w4-inputs n #:variant [variant 'complete])
  (if (eq? variant 'degenerate)
      (for/fold ([tree #f]) ([i (in-range n 0 -1)])
        (tnode (w4-label i) #f tree))
      (let ([counter (box 0)])
        (let build ([count (w4-node-count n)])
          (cond [(zero? count) #f]
                [else
                 (define left (build (quotient (sub1 count) 2)))
                 (set-box! counter (add1 (unbox counter)))
                 (define label (w4-label (unbox counter)))
                 (tnode label left (build (quotient (sub1 count) 2)))])))))

;; Type: (-> (U tnode #f) Free)
(define (w4-visit-m tree)
  (if (not tree)
      (return (void))
      (do-m (update-state 'total (lambda (total) (+ total (tnode-label tree))))
            (log-inf "visit ~a" (tnode-label tree))
            (w4-visit-m (tnode-left tree))
            (w4-visit-m (tnode-right tree))
            (update-state 'count add1))))

;; Type: (->* (Natural) ((-> Any Void) #:variant Symbol) (-> Any))
(define (w4-monadic n [sink null-log-sink] #:variant [variant 'complete])
  (define tree (w4-inputs n #:variant variant))
  (lambda ()
    (define store (make-state-store '((total . 0) (count . 0))))
    (define-values (counted counts) (counting-sink sink))
    (run (w4-visit-m tree) (bench-handler '(state log) store counted))
    (list (hash-ref store 'total) (hash-ref store 'count) (level-counts counts))))

;; Type: (->* (Natural) ((-> Any Void) #:variant Symbol) (-> Any))
(define (w4-plain n [sink null-log-sink] #:variant [variant 'complete])
  (define tree (w4-inputs n #:variant variant))
  (lambda ()
    (define total (box 0))
    (define count (box 0))
    (define-values (counted counts) (counting-sink sink))
    (let visit ([t tree])
      (when t
        (set-box! total (+ (unbox total) (tnode-label t)))
        (counted (log-effect 'INFO (format "visit ~a" (tnode-label t))))
        (visit (tnode-left t))
        (visit (tnode-right t))
        (set-box! count (add1 (unbox count)))))
    (list (unbox total) (unbox count) (level-counts counts))))

;; Type: (-> (Listof bench-case))
(define (w4-case)
  (list (bench-case 'w4 'complete pilot-sizes w4-node-count
                    (lambda (n [sink null-log-sink]) (w4-monadic n sink #:variant 'complete))
                    (lambda (n [sink null-log-sink]) (w4-plain n sink #:variant 'complete))
                    equal?)
        (bench-case 'w4 'degenerate pilot-sizes identity-ops
                    (lambda (n [sink null-log-sink]) (w4-monadic n sink #:variant 'degenerate))
                    (lambda (n [sink null-log-sink]) (w4-plain n sink #:variant 'degenerate))
                    equal?)))

;; ============================================================
;; W5 Monte Carlo (rnd, state)
;; ============================================================

(define w5-seed 42)
(define w5-range 1000)

;; The fixed seed of the draws.
;; Type: (-> Natural Natural)
(define (w5-inputs n) w5-seed)

;; Type: (-> Natural Natural Boolean)
(define (inside? x y)
  (< (+ (* x x) (* y y)) (* w5-range w5-range)))

;; Type: (-> Natural Natural Free)
(define (w5-loop-m i n)
  (if (= i n)
      (return (void))
      (do-m [x <- (rnd 0 w5-range)]
            [y <- (rnd 0 w5-range)]
            (update-state 'inside (lambda (count) (if (inside? x y) (add1 count) count)))
            (w5-loop-m (add1 i) n))))

;; Type: (-> Natural (-> Any))
(define (w5-monadic n)
  (define seed (w5-inputs n))
  (lambda ()
    (define store (make-state-store (list (cons 'inside 0) (cons 'seed seed))))
    (run (w5-loop-m 0 n) (bench-handler '(rnd state) store))
    (hash-ref store 'inside)))

;; Type: (-> Natural (-> Any))
(define (w5-plain n)
  (define seed (w5-inputs n))
  (lambda ()
    (define generator (vector->pseudo-random-generator (vector (add1 seed) 2 3 4 5 6)))
    (define count (box 0))
    (for ([i (in-range n)])
      (define x (random 0 w5-range generator))
      (define y (random 0 w5-range generator))
      (set-box! count (if (inside? x y) (add1 (unbox count)) (unbox count))))
    (unbox count)))

;; Type: (-> (Listof bench-case))
(define (w5-case)
  (list (bench-case 'w5 'default pilot-sizes identity-ops w5-monadic w5-plain equal?)))

(module+ test
  (require rackunit)

  ;; A sink that counts its calls and keeps the messages it was given.
  (define (make-counting-sink)
    (define messages '())
    (values (lambda (m) (set! messages (cons m messages)))
            (lambda () messages)))

  ;; The case cut to its smallest size.
  (define (cut c)
    (struct-copy bench-case c [sizes (list (car (bench-case-sizes c)))]))

  (define (case-by-variant cases variant)
    (for/first ([c (in-list cases)] #:when (eq? (bench-case-variant c) variant)) c))

  (define (run-thunk build n . args) ((apply build n args)))

  (define (request->list r) (list (request-id r) (request-amount r) (request-text r)))
  (define (invalid-request? r) (> (request-amount r) w1-limit))

  ;; ------------------------------------------------------------
  ;; W1 request pipeline
  ;; ------------------------------------------------------------

  (test-case "w1-inputs: should give n requests and the configuration, deterministically"
    (define-values (requests-1 config-1) (w1-inputs 64))
    (define-values (requests-2 config-2) (w1-inputs 64))
    (check-equal? (length requests-1) 64)
    (check-equal? (map request->list requests-1) (map request->list requests-2))
    (check-equal? config-1 config-2)
    (check-true (and (hash-has-key? config-1 'limit)
                     (hash-has-key? config-1 'mode)
                     (hash-has-key? config-1 'label))))

  (test-case "w1-inputs: should make about one request in eight invalid"
    (define-values (requests config) (w1-inputs 1024))
    (define invalid-count (length (filter invalid-request? requests)))
    (check-true (<= 96 invalid-count 160) (format "invalid: ~a" invalid-count)))

  (test-case "w1-inputs: should give no requests when n is 0 and one when n is 1"
    (define-values (none config-0) (w1-inputs 0))
    (define-values (one config-1) (w1-inputs 1))
    (check-equal? (length none) 0)
    (check-equal? (length one) 1))

  (test-case "w1-monadic: should not call the log sink when only built"
    (define-values (sink messages) (make-counting-sink))
    (w1-monadic 64 sink)
    (check-equal? (length (messages)) 0))

  (test-case "w1-monadic: should call the log sink once per request when run"
    (define-values (sink messages) (make-counting-sink))
    (run-thunk w1-monadic 64 sink)
    (check-equal? (length (messages)) 64)
    (check-true (log-effect? (car (messages)))))

  (test-case "w1-plain: should call the log sink once per request"
    (define-values (sink messages) (make-counting-sink))
    (run-thunk w1-plain 64 sink)
    (check-equal? (length (messages)) 64)
    (check-true (log-effect? (car (messages)))))

  (test-case "w1: should give equal responses and per-level log counts when monadic and plain run at the smallest size"
    (check-equal? (case-check (cut (car (w1-case)))) 1))

  (test-case "w1: should answer invalid requests with an error response and not abort when failures occur"
    ;; Given
    (define-values (requests config) (w1-inputs 64))
    (define invalid-count (length (filter invalid-request? requests)))
    ;; When
    (define result (run-thunk w1-monadic 64))
    ;; Then
    (define responses (car result))
    (check-equal? (length responses) 64)
    (check-true (> invalid-count 0))
    (check-equal? (length (filter (lambda (r) (eq? (cadr r) 'error)) responses)) invalid-count))

  (test-case "w1: should give empty responses and no log calls when n is 0"
    ;; Given
    (define-values (sink-m messages-m) (make-counting-sink))
    (define-values (sink-p messages-p) (make-counting-sink))
    ;; When
    (define monadic (run-thunk w1-monadic 0 sink-m))
    (define plain (run-thunk w1-plain 0 sink-p))
    ;; Then
    (check-equal? (car monadic) '())
    (check-equal? (length (messages-m)) 0)
    (check-equal? (length (messages-p)) 0)
    (check-equal? monadic plain))

  (test-case "w1-case: should return one bench-case with id 'w1, sizes from 64 to 131072 in powers of two, and ops n"
    (define cases (w1-case))
    (check-equal? (length cases) 1)
    (check-eq? (bench-case-id (car cases)) 'w1)
    (check-equal? (bench-case-sizes (car cases)) (for/list ([k (in-range 6 18)]) (expt 2 k)))
    (check-equal? ((bench-case-ops (car cases)) 64) 64))

  (test-case "w1-monadic: should write nothing to the output port when no sink is given"
    (define out (open-output-string))
    (parameterize ([current-output-port out])
      (run-thunk w1-monadic 64))
    (check-equal? (get-output-string out) ""))

  ;; ------------------------------------------------------------
  ;; W2 ledger
  ;; ------------------------------------------------------------

  (define (txn->list t) (list (txn-source t) (txn-target t) (txn-amount t)))

  (test-case "w2-inputs: should give 16 accounts and n transactions deterministically"
    (define-values (accounts-1 txns-1) (w2-inputs 64))
    (define-values (accounts-2 txns-2) (w2-inputs 64))
    (check-equal? (length accounts-1) 16)
    (check-equal? (length txns-1) 64)
    (check-equal? accounts-1 accounts-2)
    (check-equal? (map txn->list txns-1) (map txn->list txns-2))
    (define names (map car accounts-1))
    (for ([t (in-list txns-1)])
      (check-not-false (memq (txn-source t) names))
      (check-not-false (memq (txn-target t) names))))

  (test-case "w2-inputs: should give no transactions when n is 0"
    (define-values (accounts txns) (w2-inputs 0))
    (check-equal? (length accounts) 16)
    (check-equal? txns '()))

  (test-case "w2: should give equal final ledger and rejected count when monadic, plain-box and plain-threaded run at the smallest size"
    (define cases (w2-case))
    (check-equal? (case-check (cut (car cases))) 1)
    (check-equal? (case-check (cut (cadr cases))) 1)
    (define monadic (run-thunk w2-monadic 64))
    (check-equal? (run-thunk w2-plain-box 64) monadic)
    (check-equal? (run-thunk w2-plain-threaded 64) monadic))

  (test-case "w2: should reject about one transaction in twenty"
    (define rejected (cadr (run-thunk w2-plain-box 1024)))
    (check-true (<= 25 rejected 80) (format "rejected: ~a" rejected)))

  (test-case "w2: should keep the sum of balances when transactions are applied"
    (for ([build (in-list (list w2-monadic w2-plain-box w2-plain-threaded))])
      (define result (run-thunk build 256))
      (check-equal? (apply + (map cdr (car result))) (* 16 w2-opening-balance))))

  (test-case "w2-monadic: should give equal results when the same thunk runs twice"
    (define thunk (w2-monadic 64))
    (check-equal? (thunk) (thunk)))

  (test-case "w2: should return the opening ledger and 0 rejected when n is 0"
    (define-values (accounts txns) (w2-inputs 0))
    (define expected (list accounts 0))
    (check-equal? (run-thunk w2-monadic 0) expected)
    (check-equal? (run-thunk w2-plain-box 0) expected)
    (check-equal? (run-thunk w2-plain-threaded 0) expected))

  (test-case "w2-case: should return two bench-cases with variants 'box and 'threaded"
    (define cases (w2-case))
    (check-equal? (length cases) 2)
    (check-equal? (map bench-case-id cases) '(w2 w2))
    (check-equal? (map bench-case-variant cases) '(box threaded))
    (for ([c (in-list cases)])
      (check-equal? ((bench-case-ops c) 64) 64)))

  (test-case "w2-monadic: should log once per rejected transaction and once per 64 transactions"
    (define-values (sink messages) (make-counting-sink))
    (define result (run-thunk w2-monadic 128 sink))
    (check-equal? (length (messages)) (+ (cadr result) 2)))

  ;; ------------------------------------------------------------
  ;; W3 parser
  ;; ------------------------------------------------------------

  (define (max-paren-depth text)
    (for/fold ([depth 0] [best 0] #:result best) ([c (in-string text)])
      (case c
        [(#\() (values (add1 depth) (max best (add1 depth)))]
        [(#\)) (values (sub1 depth) best)]
        [else (values depth best)])))

  (test-case "w3-inputs: should give a text of exactly n characters"
    (check-equal? (string-length (w3-inputs 64)) 64)
    (check-equal? (string-length (w3-inputs 100)) 100))

  (test-case "w3-inputs: should be deterministic"
    (check-equal? (w3-inputs 1024) (w3-inputs 1024)))

  (test-case "w3-inputs: should give lengths 1 and 0 when n is 1 and 0"
    (check-equal? (string-length (w3-inputs 1)) 1)
    (check-equal? (string-length (w3-inputs 0)) 0))

  (test-case "w3-inputs: should contain numbers, identifiers, parentheses and operators"
    (define text (w3-inputs 1024))
    (check-regexp-match #rx"[0-9]" text)
    (check-regexp-match #rx"[a-z]" text)
    (check-regexp-match #rx"[(]" text)
    (check-regexp-match #rx"[+*/-]" text))

  (test-case "w3-inputs: should keep nesting depth bounded when n is large"
    (check-true (<= (max-paren-depth (w3-inputs 16384)) w3-max-depth))
    (check-equal? w3-max-depth 64))

  (test-case "w3: should give an equal parse tree and backtrack count when monadic and plain run at the smallest size"
    (check-equal? (case-check (cut (car (w3-case)))) 1))

  (test-case "w3: should backtrack in both versions when the text has shared prefixes"
    (define monadic (run-thunk w3-monadic 1024))
    (define plain (run-thunk w3-plain 1024))
    (check-equal? monadic plain)
    (check-true (> (cdr monadic) 0)))

  (test-case "w3: should give equal results without raising when n is 1 and 0"
    (for ([n (in-list '(1 0))])
      (check-equal? (run-thunk w3-monadic n) (run-thunk w3-plain n))))

  (test-case "w3-case: should return one bench-case with id 'w3 and sizes from 64 to 131072"
    (define cases (w3-case))
    (check-equal? (length cases) 1)
    (check-eq? (bench-case-id (car cases)) 'w3)
    (check-equal? (bench-case-sizes (car cases)) (for/list ([k (in-range 6 18)]) (expt 2 k))))

  ;; ------------------------------------------------------------
  ;; W4 tree traversal
  ;; ------------------------------------------------------------

  (define (count-nodes t)
    (if t (+ 1 (count-nodes (tnode-left t)) (count-nodes (tnode-right t))) 0))

  (define (tree-labels t)
    (if t (append (list (tnode-label t)) (tree-labels (tnode-left t)) (tree-labels (tnode-right t))) '()))

  (test-case "w4-inputs: should round n to the nearest 2^k - 1 for the complete tree"
    (check-equal? (map (lambda (n) (count-nodes (w4-inputs n))) '(100 64 127 1))
                  '(127 63 127 1)))

  (test-case "w4-inputs: should give a right-shaped list of exactly n nodes for the degenerate tree"
    (define tree (w4-inputs 64 #:variant 'degenerate))
    (check-equal? (count-nodes tree) 64)
    (let loop ([t tree])
      (when t
        (check-false (tnode-left t))
        (loop (tnode-right t)))))

  (test-case "w4-inputs: should give integer labels deterministically"
    (define labels-1 (tree-labels (w4-inputs 63)))
    (define labels-2 (tree-labels (w4-inputs 63)))
    (check-equal? labels-1 labels-2)
    (check-true (andmap exact-integer? labels-1)))

  (test-case "w4: should give equal total, visit counter and log count when monadic and plain run on both variants at the smallest size"
    (define cases (w4-case))
    (check-equal? (case-check (cut (case-by-variant cases 'complete))) 1)
    (check-equal? (case-check (cut (case-by-variant cases 'degenerate))) 1))

  (test-case "w4: should count one visit per node and total equal to the label sum"
    (define result (run-thunk w4-plain 63))
    (check-equal? (cadr result) 63)
    (check-equal? (car result) (apply + (tree-labels (w4-inputs 63)))))

  (test-case "w4: should give ops equal to the actual node count when n is rounded"
    (define c (case-by-variant (w4-case) 'complete))
    (check-equal? ((bench-case-ops c) 100) 127))

  (test-case "w4-case: should return two bench-cases with variants 'complete and 'degenerate"
    (define cases (w4-case))
    (check-equal? (length cases) 2)
    (check-equal? (map bench-case-id cases) '(w4 w4))
    (check-equal? (map bench-case-variant cases) '(complete degenerate)))

  (test-case "w4-monadic: should finish without error when the degenerate tree has 16384 nodes"
    (define monadic ((w4-monadic 16384 #:variant 'degenerate)))
    (define plain ((w4-plain 16384 #:variant 'degenerate)))
    (check-equal? monadic plain))

  (test-case "w4: should make exactly one log call per node in both versions when the sink counts"
    (for ([variant (in-list '(complete degenerate))])
      (define-values (sink-m messages-m) (make-counting-sink))
      (define-values (sink-p messages-p) (make-counting-sink))
      ((w4-monadic 15 sink-m #:variant variant))
      ((w4-plain 15 sink-p #:variant variant))
      (check-equal? (length (messages-m)) 15)
      (check-equal? (length (messages-p)) 15)))

  ;; ------------------------------------------------------------
  ;; W5 Monte Carlo
  ;; ------------------------------------------------------------

  (test-case "w5-plain: should give the same count when run twice"
    (define thunk (w5-plain 64))
    (check-equal? (thunk) (thunk)))

  (test-case "w5: should give equal counts when monadic and plain run at the smallest size"
    (check-equal? (case-check (cut (car (w5-case)))) 1))

  (test-case "w5: should give a count in [0, n] and near pi/4 of n when n is large"
    (define count (run-thunk w5-plain 1024))
    (check-true (<= 700 count 870) (format "count: ~a" count))
    (check-equal? (run-thunk w5-monadic 1024) count))

  (test-case "w5-monadic: should give the same count when its thunk runs twice"
    (define thunk (w5-monadic 64))
    (check-equal? (thunk) (thunk)))

  (test-case "w5: should give count 0 when n is 0 and 0 or 1 when n is 1, equal in both versions"
    (check-equal? (run-thunk w5-monadic 0) 0)
    (check-equal? (run-thunk w5-plain 0) 0)
    (check-not-false (memv (run-thunk w5-monadic 1) '(0 1)))
    (check-equal? (run-thunk w5-monadic 1) (run-thunk w5-plain 1)))

  (test-case "w5-case: should return one bench-case with id 'w5 and ops n"
    (define cases (w5-case))
    (check-equal? (length cases) 1)
    (check-eq? (bench-case-id (car cases)) 'w5)
    (check-equal? ((bench-case-ops (car cases)) 64) 64)))
