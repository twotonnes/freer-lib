#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define std-eval (make-base-eval))
@interaction-eval[#:eval std-eval (require racket freer-lib freer-lib/effects/file-system-effect)]

@title{File System}

@defmodule[freer-lib/effects/file-system-effect]

This module provides effects for performing file system operations such as reading, writing, creating directories, and checking or deleting paths.

@section{Structs}

@defstruct[read-file-effect ([path path-string?]) #:transparent]{
  An effect descriptor that represents a file read operation.
  
  @itemlist[
    @item{@racket[path]: The path to the file to read.}
  ]
}

@defstruct[write-file-effect ([path path-string?]
                              [bytes bytes?]
                              [exists-flag (or/c 'error 'append 'update 'replace 'truncate 'truncate/replace)]) #:transparent]{
  An effect descriptor that represents a file write operation.
  
  @itemlist[
    @item{@racket[path]: The path to the file to write.}
    @item{@racket[bytes]: The bytes to write to the file.}
    @item{@racket[exists-flag]: Controls behavior if the file already exists:
      @itemlist[
        @item{@racket['error]: Raise an error if the file exists (default in Racket).}
        @item{@racket['append]: Append bytes to the existing file.}
        @item{@racket['update]: Update the file if it exists, create otherwise.}
        @item{@racket['replace]: Replace the file contents (same as @racket['truncate]).}
        @item{@racket['truncate]: Truncate and overwrite the file.}
        @item{@racket['truncate/replace]: Truncate, overwrite, and replace (Racket-specific).}
      ]}
  ]
}

@defstruct[create-folder-effect ([path path-string?]) #:transparent]{
  An effect descriptor that represents a folder creation operation.
  
  @itemlist[
    @item{@racket[path]: The path to the folder to create. Parent directories are created if necessary.}
  ]
}

@defstruct[check-path-effect ([path path-string?]) #:transparent]{
  An effect descriptor that represents a path type check operation.
  
  @itemlist[
    @item{@racket[path]: The path to check.}
  ]
}

@defstruct[delete-path-effect ([path path-string?]) #:transparent]{
  An effect descriptor that represents a path deletion operation.
  
  @itemlist[
    @item{@racket[path]: The path to the file or directory to delete.}
  ]
}

@section{Procedures}

@defproc[(read-file [path path-string?]) free?]{
  Creates an effect that reads the file at @racket[path] and returns its contents as bytes.
  
  @examples[#:eval std-eval
    (code:comment "Define a mock handler for testing")
    (define (mock-fs-handler effect k)
      (match effect
        [(read-file-effect path)
         (k (string->bytes/utf-8 "config-data"))]
        [_ (error "unhandled effect")]))
    
    (code:comment "Use the effect in a computation")
    (define (read-config-file)
      (do [content <- (read-file "config.txt")]
          (return (bytes->string/utf-8 content))))
    
    (code:comment "Run with mock handler")
    (run (read-config-file) mock-fs-handler)
  ]
}

@defproc[(write-file [path path-string?]
                     [bytes bytes?]
                     [exists-flag (or/c 'error 'append 'update 'replace 'truncate 'truncate/replace)]) free?]{
  Creates an effect that writes @racket[bytes] to the file at @racket[path]. The @racket[exists-flag] parameter controls behavior if the file already exists.
  
  @examples[#:eval std-eval
    (code:comment "Mock handler that confirms writes")
    (define (write-handler effect k)
      (match effect
        [(write-file-effect path bytes flag)
         (k (void))]
        [_ (error "unhandled effect")]))
    
    (define (save-document content)
      (do [_ <- (write-file "document.txt" 
                            (string->bytes/utf-8 content)
                            'truncate)]
          (return "Document saved!")))
    
    (run (save-document "Hello, world!") write-handler)
  ]
}

@defproc[(create-folder [path path-string?]) free?]{
  Creates an effect that creates a folder at @racket[path]. All necessary parent directories are created automatically.
  
  @examples[#:eval std-eval
    (define (folder-handler effect k)
      (match effect
        [(create-folder-effect path)
         (k (void))]
        [_ (error "unhandled effect")]))
    
    (define (setup-workspace dir-name)
      (do [_ <- (create-folder (string-append "projects/" dir-name "/src"))]
          [_ <- (create-folder (string-append "projects/" dir-name "/tests"))]
          (return (string-append "Workspace '" dir-name "' created"))))
    
    (run (setup-workspace "my-project") folder-handler)
  ]
}

@defproc[(check-path [path path-string?]) free?]{
  Creates an effect that checks the type of a path and returns a symbol indicating whether it is a file, directory, symbolic link, directory symbolic link, or does not exist.
  
  Returns one of:
  @itemlist[
    @item{@racket['file]: A regular file}
    @item{@racket['directory]: A directory}
    @item{@racket['link]: A symbolic link to a file}
    @item{@racket['directory-link]: A symbolic link to a directory}
    @item{@racket[#f]: The path does not exist}
  ]
  
  @examples[#:eval std-eval
    (define (check-handler effect k)
      (match effect
        [(check-path-effect "existing.txt") (k 'file)]
        [(check-path-effect "my-folder") (k 'directory)]
        [(check-path-effect _) (k #f)]
        [_ (error "unhandled effect")]))
    
    (define (handle-path path)
      (do [type <- (check-path path)]
          (match type
            ['file (return "It's a file")]
            ['directory (return "It's a directory")]
            [#f (return "Path does not exist")]
            [_ (return "It's a link")])))
    
    (run (handle-path "existing.txt") check-handler)
    (run (handle-path "my-folder") check-handler)
    (run (handle-path "missing.txt") check-handler)
  ]
}

@defproc[(delete-path [path path-string?]) free?]{
  Creates an effect that deletes a file or directory at @racket[path]. If the path is a directory, it and all its contents are recursively deleted. If the path does not exist, no error is raised.
  
  @examples[#:eval std-eval
    (define (delete-handler effect k)
      (match effect
        [(delete-path-effect path)
         (k (void))]
        [_ (error "unhandled effect")]))
    
    (define (cleanup)
      (do [_ <- (delete-path "temp.txt")]
          [_ <- (delete-path "old-data")]
          (return "Cleanup complete")))
    
    (run (cleanup) delete-handler)
  ]
}

@section{Default Handlers}

@defproc[(do-read-file [path path-string?]) bytes?]{
  Default handler for @racket[read-file-effect]. Reads the file at @racket[path] and returns its contents as bytes. Raises an error if the file cannot be read.
}

@defproc[(do-write-file [path path-string?]
                        [bytes bytes?]
                        [exists-flag (or/c 'error 'append 'update 'replace 'truncate 'truncate/replace)]) void?]{
  Default handler for @racket[write-file-effect]. Writes @racket[bytes] to @racket[path] with the specified @racket[exists-flag]. Raises an error if the file cannot be written.
}

@defproc[(do-create-folder [path path-string?]) void?]{
  Default handler for @racket[create-folder-effect]. Creates the folder at @racket[path] and all necessary parent directories. Raises an error if the folder cannot be created.
}

@defproc[(do-check-path [path path-string?]) (or/c 'file 'directory 'link 'directory-link #f)]{
  Default handler for @racket[check-path-effect]. Returns a symbol indicating the type of the path, or @racket[#f] if it does not exist.
}

@defproc[(do-delete-path [path path-string?]) void?]{
  Default handler for @racket[delete-path-effect]. Deletes the file or directory at @racket[path]. If the path is a directory, all its contents are recursively deleted. Does not raise an error if the path does not exist.
}

@section{Usage Example}

@examples[#:eval std-eval
  (code:comment "Example: Copy a file with path type checking")
  (define (copy-handler effect k)
    (match effect
      [(check-path-effect "source.txt") (k 'file)]
      [(read-file-effect "source.txt") 
       (k (string->bytes/utf-8 "file contents"))]
      [(write-file-effect path bytes flag) (k (void))]
      [_ (error "unhandled effect")]))
  
  (define (copy-file-if-exists src dst)
    (do [src-type <- (check-path src)]
        (if (eq? src-type 'file)
            (do [content <- (read-file src)]
                [_ <- (write-file dst content 'truncate)]
                (return "File copied successfully"))
            (return "Source file does not exist"))))
  
  (run (copy-file-if-exists "source.txt" "dest.txt") copy-handler)
]

@bold{Error Handling}: File system operations can fail due to permission issues, missing files, or other I/O errors. The default handlers wrap file system operations with exception handlers that convert Racket exceptions to more readable error messages. You can write custom handlers to implement retry logic, fallback behavior, or alternative error handling strategies.
