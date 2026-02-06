#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [log-info r:log-info] [log-debug r:log-debug] [log-error r:log-error])
             net/url
             freer-lib))

@(define http-eval (make-base-eval))
@interaction-eval[#:eval http-eval (require freer-lib freer-lib/effects/http-effect racket/match)]

@title{HTTP Requests}

@defmodule[freer-lib/effects/http-effect]

This module provides effects for performing HTTP network requests.

@defstruct[http-effect ([url url?]
                                      [method symbol?]
                                      [headers (listof string?)]
                                      [body (or/c #f bytes? string?)])
           #:transparent]{
  The descriptor containing all necessary information to perform a request.
}

@defproc[(http-get [url string?] [headers (listof string?)]) impure?]{
  Creates a GET request effect.

  @examples[#:eval http-eval
    (define (fetch-home)
      (do [(list status headers body) <- (http-get "https://racket-lang.org" '())]
          (return (format "Status: ~a, Body length: ~a" 
                          status 
                          (string-length body)))))
  ]
}

@defproc[(http-post [url string?] [headers (listof string?)] [body (or/c bytes? string?)]) impure?]{
  Creates a POST request effect.
}

@defproc[(http-put [url string?] [headers (listof string?)] [body (or/c bytes? string?)]) impure?]{
  Creates a PUT request effect.
}

@defproc[(http-patch [url string?] [headers (listof string?)] [body (or/c bytes? string?)]) impure?]{
  Creates a PATCH request effect.
}

@defproc[(http-delete [url string?] [headers (listof string?)]) impure?]{
  Creates a DELETE request effect.
}

@defproc[(perform-http-request [eff http-effect?]) (list/c number? (listof string?) string?)]{
  The default handler implementation using Racket's @racket[net/url] library.
  
  It returns a list containing:
  @racketblock['(status-code headers-list body-string)]
  
  @itemlist[
    @item{@racket[status-code]: Exact integer (e.g., 200, 404).}
    @item{@racket[headers-list]: A list of strings representing response headers.}
    @item{@racket[body-string]: The response body.}
  ]

  If an error occurs during the HTTP request (e.g., network error, malformed URL, connection timeout), an exception is raised.

  @examples[#:eval http-eval
    ;; Mocking the HTTP handler ensures documentation builds do not 
    ;; require internet access and behave deterministically.
    (run (fetch-home)
         (lambda (eff k)
           (match eff
             [(http-effect url method headers body)
              ;; Return a fake 200 OK response
              (k (list 200 '("Content-Type: text/html") "<html>Mock Body</html>"))])))
  ]
}
