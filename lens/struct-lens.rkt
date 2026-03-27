#lang racket/base

(provide
 struct/lens
 struct/lens-out)

(require
  "lens.rkt"
  racket/provide-syntax
  (for-syntax racket/base
              racket/list
              racket/struct-info
              racket/syntax))

(define-syntax (struct/lens stx)
  (syntax-case stx ()
    ;; Match the struct name, fields, and any optional arguments.
    [(_ name (field ...) option ...)
     (with-syntax ([(lens-name ...)
                    ;; Create lens names, e.g., 'person', 'name' -> 'person->name'
                    (map (lambda (f) (format-id f "~a->~a" #'name f))
                         (syntax->list #'(field ...)))]
                   [(accessor-name ...)
                    ;; Create accessor names, e.g., 'person', 'name' -> 'person-name'
                    (map (lambda (f) (format-id f "~a-~a" #'name f))
                         (syntax->list #'(field ...)))])
       #'(begin
           ;; First, define the struct, passing along any options like #:transparent.
           (struct name (field ...) option ...)

           ;; Then, for each field, define a corresponding lens.
           (define lens-name
             (lens
              ;; The 'get' function for the lens is the struct's standard accessor.
              accessor-name
              ;; The 'set' function creates a new struct with the updated field value.
              (lambda (new-value instance)
                (struct-copy name instance [field new-value]))))
           ...))]))

(define-provide-syntax struct/lens-out
  (lambda (stx)
    (syntax-case stx ()
        [(_ struct-type)
         (let* ([struct-val (syntax-local-value #'struct-type)]
                [info (extract-struct-info struct-val)]
                [struct-name-sym (first info)]
                [struct-name-str (substring (symbol->string (syntax->datum struct-name-sym)) (string-length "struct:"))]
                [field-accessors (fourth info)]
                [field-name-syms (for/list ([accessor (in-list field-accessors)])
                                   (define accessor-str (symbol->string (syntax->datum accessor)))
                                   (define prefix (string-append struct-name-str "-"))
                                   (define field-str (substring accessor-str (string-length prefix)))
                                   (string->symbol field-str))]
                [lens-stx (for/list ([field-sym (in-list field-name-syms)])
                            (format-id #'struct-type "~a->~a" struct-name-str field-sym))])
           #`(combine-out (struct-out struct-type)
                          #,@lens-stx))])))
