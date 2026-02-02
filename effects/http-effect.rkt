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
    "../eff-monad.rkt")
  
(struct http-effect (url method headers body) #:transparent)

(define (http-get url headers)
  (effect (http-effect (string->url url) 'GET headers #f) return))

(define (http-post url headers body)
  (effect (http-effect (string->url url) 'POST headers body) return))

(define (http-put url headers body)
  (effect (http-effect (string->url url) 'PUT headers body) return))

(define (http-patch url headers body)
  (effect (http-effect (string->url url) 'PATCH headers body) return))

(define (http-delete url headers)
  (effect (http-effect (string->url url) 'DELETE headers #f) return))

(define (perform-http-request req)
    (define-values (status-line headers-bytes body-port)
      (match req
        [(http-effect url method headers body)
         (http-sendrecv/url url #:method method #:headers headers #:data body)]))

    (define status
      (match (regexp-match #px"HTTP/.+ ([0-9]{3})"
                           (bytes->string/utf-8 status-line))
        [(list _ (? string? status)) (string->number status)]))

    (define headers
      (map bytes->string/utf-8 headers-bytes))

    (define body
      (port->string body-port))
    
    (return (list status headers body)))