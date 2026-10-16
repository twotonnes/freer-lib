#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             net/url
             freer-lib))

@(define http-eval (make-base-eval))
@interaction-eval[#:eval http-eval (require freer-lib freer-lib/effects/http-effect racket/match)]

@title{HTTP Requests}

@defmodule[freer-lib/effects/http-effect]

This module provides effects for performing HTTP network requests.

@defstruct*[http-effect ([url url?]
                         [method (or/c 'GET 'POST 'PUT 'PATCH 'DELETE)]
                         [headers (listof string?)]
                         [data (or/c #f bytes? string?)])
           #:transparent]{
  The descriptor containing all necessary information to perform a request.
  @itemlist[
    @item{@racket[url]: The parsed request URL (see @racket[string->url]).}
    @item{@racket[method]: The HTTP method.}
    @item{@racket[headers]: Request headers, each formatted as @racket["Name: value"].}
    @item{@racket[data]: The request body, or @racket[#f] for @racket['GET] and @racket['DELETE] requests.}
  ]
}

@defproc[(http-get [url string?] [headers (listof string?)]) free?]{
  Creates a GET request effect for @racket[url]. The @racket[url] string is parsed with @racket[string->url] when the effect is created.

  @examples[#:eval http-eval
    (define (fetch-home)
      (do-m [(list status headers body) <- (http-get "https://racket-lang.org" '())]
          (return (format "Status: ~a, Body length: ~a" 
                          status 
                          (string-length body)))))
  ]
}

@defproc[(http-post [url string?] [headers (listof string?)] [data (or/c bytes? string?)]) free?]{
  Creates a POST request effect for @racket[url] with @racket[data] as the request body.
}

@defproc[(http-put [url string?] [headers (listof string?)] [data (or/c bytes? string?)]) free?]{
  Creates a PUT request effect for @racket[url] with @racket[data] as the request body.
}

@defproc[(http-patch [url string?] [headers (listof string?)] [data (or/c bytes? string?)]) free?]{
  Creates a PATCH request effect for @racket[url] with @racket[data] as the request body.
}

@defproc[(http-delete [url string?] [headers (listof string?)]) free?]{
  Creates a DELETE request effect for @racket[url].
}

@defproc[(perform-http-request [req http-effect?]) (list/c number? (listof string?) string?)]{
  The default handler for @racket[http-effect], implemented with @racket[http-sendrecv/url] from Racket's @racketmodname[net/url] library.
  
  It returns a list containing:
  @racketblock['(status-code headers-list body-string)]
  
  @itemlist[
    @item{@racket[status-code]: Exact integer (e.g., 200, 404).}
    @item{@racket[headers-list]: A list of strings representing response headers.}
    @item{@racket[body-string]: The response body, decoded as a string.}
  ]

  Non-2xx status codes are @emph{not} treated as errors. If an error occurs while performing the request (e.g., a network error or connection timeout), an exception is raised whose message includes the request.

  A handler that uses @racket[perform-http-request] looks like this:

  @racketblock[
    (run (fetch-home)
         (lambda (eff k)
           (match eff
             [(? http-effect?) (k (perform-http-request eff))])))
  ]

  @examples[#:eval http-eval
    (code:comment "Mocking the HTTP handler lets tests run without network access.")
    (run (fetch-home)
         (lambda (eff k)
           (match eff
             [(http-effect url method headers data)
              (code:comment "Return a fake 200 OK response")
              (k (list 200 '("Content-Type: text/html") "<html>Mock Body</html>"))])))
  ]
}
