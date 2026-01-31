#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval
                  (require typed/racket effect-lib)]

@title{HTTP Effect}

The HTTP effect allows you to make HTTP requests (GET, POST, PUT, PATCH, DELETE) in a purely functional way. This separates the description of HTTP requests from their execution, making it easy to test and mock network code.

@section{Purpose}

The HTTP effect is designed for:
@itemlist[
  @item{Making HTTP requests to web services}
  @item{Separating request intent from network execution}
  @item{Testing code that makes HTTP requests with mock handlers}
  @item{Building composable network operations}
]

@section{API}

@defproc[(http-get [url String] [headers (Listof String)]) (Eff Any)]{
  Creates an HTTP GET request effect.
  
  @itemlist[
    @item{@racket[url]: The URL to request (as a string)}
    @item{@racket[headers]: List of header strings (e.g., @racket["Content-Type: application/json"])}
  ]
  
  Returns an @racket[Eff] that produces a list: @racket[(List Integer (Listof String) String)]
  where the elements are: status code, response headers, and response body.
}

@defproc[(http-post [url String] [headers (Listof String)] [body String]) (Eff Any)]{
  Creates an HTTP POST request effect.
  
  @itemlist[
    @item{@racket[url]: The URL to request}
    @item{@racket[headers]: Request headers}
    @item{@racket[body]: The request body}
  ]
}

@defproc[(http-put [url String] [headers (Listof String)] [body String]) (Eff Any)]{
  Creates an HTTP PUT request effect for replacing resources.
}

@defproc[(http-patch [url String] [headers (Listof String)] [body String]) (Eff Any)]{
  Creates an HTTP PATCH request effect for partial updates.
}

@defproc[(http-delete [url String] [headers (Listof String)]) (Eff Any)]{
  Creates an HTTP DELETE request effect.
}

@defproc[(perform-http-request [req http-effect]) (Eff (List Integer (Listof String) String))]{
  A built-in handler that executes the HTTP request immediately. This is the standard way to perform network requests.
}

@section{Example: GET Request}

@codeblock{
  (with-effect-handlers
    ([(http-effect url method headers body)
      (perform-http-request (http-effect url method headers body))])
    (do [response <- (http-get "https://api.example.com/data" '())]
        (match response
          [(list status headers body)
           (printf "Status: ~a~nBody: ~a~n" status body)
           (return body)])))
}

@section{Example: POST Request}

@codeblock{
  (do [response <- (http-post 
                     "https://api.example.com/create"
                     (list "Content-Type: application/json")
                     "{\"name\": \"test\"}")]
      (match response
        [(list status headers body)
         (if (< 200 status 300)
             (return body)
             (error (format "HTTP error: ~a" status)))]))
}

@section{Mock Testing}

Mock HTTP handlers for testing without network access:

@codeblock{
  (: mock-http-handler (All (A) (-> http-effect (Eff (List Integer (Listof String) String)))))
  (define (mock-http-handler req)
    (match req
      [(http-effect url 'GET _ _)
       (cond
         [(string-contains? (url->string url) "users")
          (return (list 200 (list "Content-Type: application/json")
                        "[{\"id\": 1, \"name\": \"Alice\"}]"))]
         [else
          (return (list 404 (list) "Not Found"))])]
      [(http-effect url 'POST headers body)
       (return (list 201 (list "Content-Type: application/json")
                      (format "{\"created\": ~a}" body)))]
      [_ (return (list 500 (list) "Internal Server Error"))]))
  
  (with-effect-handlers
    ([(http-effect url method headers body)
      (mock-http-handler (http-effect url method headers body))])
    my-computation)
}

@section{Error Handling}

Always check the status code to detect errors:

@codeblock{
  (do [response <- (http-get "https://api.example.com/data" '())]
      (match response
        [(list status headers body)
         (cond
           [(< 200 status 300)
            (return body)]
           [(= status 404)
            (error "Not found")]
           [(= status 500)
            (error "Server error")]
           [else
            (error (format "HTTP error: ~a" status))])]))
}

@section{Working with Headers}

Headers are represented as a list of strings in the format @racket["Header-Name: value"]:

@codeblock{
  (do [response <- (http-post
                     "https://api.example.com/data"
                     (list "Content-Type: application/json"
                           "Authorization: Bearer token123")
                     "{\"key\": \"value\"}")]
      (return response))
}

@section{Building Request Helpers}

Create helper functions for common patterns:

@codeblock{
  (: json-post (-> String String (Eff (List Integer (Listof String) String))))
  (define (json-post url body)
    (http-post url
               (list "Content-Type: application/json")
               body))
  
  (: api-get (-> String (Eff (List Integer (Listof String) String))))
  (define (api-get url)
    (http-get url
              (list "Accept: application/json")))
  
  ;; Now use these in your computations
  (do [response <- (json-post "https://api.example.com/create" data)]
      (return response))
}

@section{Timeouts and Network Errors}

Network errors may raise exceptions. Handle them in effect handlers:

@codeblock{
  (with-handlers ([exn:fail:network?
                   (lambda (e)
                     (with-effect-handlers
                       ([(http-effect url method headers body)
                        (return (list 0 (list) "Network error"))])
                       computation))])
    computation)
}
