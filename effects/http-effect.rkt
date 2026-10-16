#lang racket/base

(provide
  (struct-out http-effect)
  http-get
  http-post
  http-put
  http-patch
  http-delete
  perform-http-request)

(require
    net/url
    racket/match
    racket/port
    racket/exn
    "../freer-monad.rkt")
  
(struct http-effect (url method headers data) #:transparent)

;; Type: (-> String (Listof String) Free)
(define (http-get url headers)
  (perform (http-effect (string->url url) 'GET headers #f)))

;; Type: (-> String (Listof String) (U Bytes String) Free)
(define (http-post url headers data)
  (perform (http-effect (string->url url) 'POST headers data)))

;; Type: (-> String (Listof String) (U Bytes String) Free)
(define (http-put url headers data)
  (perform (http-effect (string->url url) 'PUT headers data)))

;; Type: (-> String (Listof String) (U Bytes String) Free)
(define (http-patch url headers data)
  (perform (http-effect (string->url url) 'PATCH headers data)))

;; Type: (-> String (Listof String) Free)
(define (http-delete url headers)
  (perform (http-effect (string->url url) 'DELETE headers #f)))

;; Type: (-> Http-effect (List Integer (Listof String) String))
(define (perform-http-request req)
  (with-handlers ([exn:fail? (lambda (exn) (error (format "error performing http request '~a': ~a" req (exn->string exn))))])
    (define-values (status-line headers-bytes data-port)
      (match req
        [(http-effect url method headers data)
          (http-sendrecv/url url #:method method #:headers headers #:data data)]))

    (define status
      (match (regexp-match #px"HTTP/.+ ([0-9]{3})"
                            (bytes->string/utf-8 status-line))
        [(list _ (? string? status)) (string->number status)]))

    (define headers
      (map bytes->string/utf-8 headers-bytes))

    (define data
      (port->string data-port))

    (list status headers data)))


(module+ test
  (require
    rackunit
    "../freer-monad.rkt")

  (test-case "http-get: should perform a GET http-effect with no data"
    (check-match (http-get "http://example.com/a" '("Accept: text/plain"))
                 (impure (http-effect _ 'GET '("Accept: text/plain") #f) _)))

  (test-case "http-delete: should perform a DELETE http-effect with no data"
    (check-match (http-delete "http://example.com/a" '())
                 (impure (http-effect _ 'DELETE '() #f) _)))

  (test-case "http-post: should perform a POST http-effect with the data"
    (check-match (http-post "http://example.com/a" '() "body")
                 (impure (http-effect _ 'POST '() "body") _)))

  (test-case "http-put: should perform a PUT http-effect with the data"
    (check-match (http-put "http://example.com/a" '() #"body")
                 (impure (http-effect _ 'PUT '() #"body") _)))

  (test-case "http-patch: should perform a PATCH http-effect with the data"
    (check-match (http-patch "http://example.com/a" '() "body")
                 (impure (http-effect _ 'PATCH '() "body") _))))
