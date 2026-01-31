327
((3) 0 () 1 ((q lib "effect-lib/main.rkt")) () (h ! (equal) ((c def c (c (? . 0) q >>=)) q (576 . 4)) ((c def c (c (? . 0) q effect)) q (345 . 4)) ((c def c (c (? . 0) q effect-desc)) q (0 . 5)) ((c def c (c (? . 0) q return)) q (439 . 3)) ((c def c (c (? . 0) q pure)) q (214 . 4)) ((c def c (c (? . 0) q run)) q (488 . 4))))
value
effect-desc
 : "The base descriptor for effects. This is an extensible struct that
serves as the parent type for specific effect descriptors. Subclass this
struct to represent particular types of effects."
value
pure
 : "Represents a pure value in the effects monad—a computation that has
no effects and directly produces a result."
value
effect
 : "Represents an effect waiting to be handled. An effect structure
contains:"
procedure
(return v) -> any/c
  v : any/c
procedure
(run m handle) -> any/c
  m : any/c
  handle : (-> any/c any/c)
procedure
(>>= m f) -> any/c
  m : any/c
  f : (-> any/c any/c)
