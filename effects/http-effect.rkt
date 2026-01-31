#lang typed/racket

(provide
  (struct-out http-effect)
  http-get
  http-post
  http-put
  http-patch
  http-delete
  perform-http-request)

(require
    typed/net/url
    "../eff-monad.rkt")
  
(struct http-effect effect-desc ([url : URL]
                                 [method : Symbol]
                                 [headers : (Listof String)]
                                 [body : (U String #f)]) #:transparent)

(: http-get (-> String (Listof String) (Eff Any)))
(define (http-get url headers)
  (effect (http-effect (string->url url) 'GET headers #f) (inst return Any)))

(: http-post (-> String (Listof String) String (Eff Any)))
(define (http-post url headers body)
  (effect (http-effect (string->url url) 'POST headers body) (inst return Any)))

(: http-put (-> String (Listof String) String (Eff Any)))
(define (http-put url headers body)
  (effect (http-effect (string->url url) 'PUT headers body) (inst return Any)))

(: http-patch (-> String (Listof String) String (Eff Any)))
(define (http-patch url headers body)
  (effect (http-effect (string->url url) 'PATCH headers body) (inst return Any)))

(: http-delete (-> String (Listof String) (Eff Any)))
(define (http-delete url headers)
  (effect (http-effect (string->url url) 'DELETE headers #f) (inst return Any)))

(: perform-http-request (-> http-effect (Eff (List Integer (Listof String) String))))
(define (perform-http-request req)
    (define-values (status-line headers-bytes body-port)
      (match req
        [(http-effect url method headers body)
         (http-sendrecv/url url #:method method #:headers headers #:data body)]))

    (define status
      (match (regexp-match #px"HTTP/.+ ([0-9]{3})"
                           (bytes->string/utf-8 status-line))
        [(list _ (? string? status)) (assert (string->number status) exact-integer?)]))

    (define headers
      (map bytes->string/utf-8 headers-bytes))

    (define body
      (port->string body-port))
    
    (return (list status headers body)))