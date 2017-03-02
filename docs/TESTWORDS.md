# Words to Test Liara Forth with
Scot W. Stevenson <scot.stevenson@gmail.com>
First version 15. March 2014
This version 28. Feb 2017

This list is adapted from [Tali Forth](https://github.com/scotws/TaliForth)

## Text interpreter

### >IN tests

From
[https://www.complang.tuwien.ac.at/forth/gforth/Docs-html/The-Text-Interpreter.html](https://www.complang.tuwien.ac.at/forth/gforth/Docs-html/The-Text-Interpreter.html):
```
: lat ." <foo>" ;
: flat ." <bar>" >in dup @ 3 - swap ! ; 
```
With this, `flat` prints "<bar><foo>" if same input area is used.

```
char & parse jack& type                 \ should print "jack" 
```

### LITERAL test

```
: aaa \[ 1 \] literal ;         \ should put 1 on the stack during runtime
```


### POSTPONE test

Based on https://www.forth.com/starting-forth/11-forth-compiler-defining-words/
```
: say-hello ." Hello" ; immediate
: greet postpone say-hello ." I speak Forth" ; \ won't print "Hello" right away
```

Basic uses (captured output): 
```
: ws ." normal" ;   ok
: wsi ." immediate" ; immediate  ok
: a postpone ws ;   ok
a  ok
: b postpone wsi ;   ok
b immediate ok
: c postpone wsi ; immediate  ok
c immediate ok
```


### FIND-NAME test

```
s" words" find-name name>string type
``` 
should print `words`


### WORD vs PARSE test 

Taken from Conklin & Rather p. 160
```
: test1 ( "name" -- )  32 word  count type ; 
: test2 ( "name" -- )  32 parse  type ; 
```

Results of calls with "ABC" should give identical result if there are no
leading spaces. However, with leading spaces, TEST2 will find an empty string
and abort, then throw an error because ABC will not be found in the dictionary.


## LOOP testing

Test normal loop:
```
: aaa 11 1 do i . loop ;        
```
Should produce numbers 1 - 10

Then, try this as multi-line loop because that can be tricky:
```
: bbb 11 1 do 
  i . loop ; 
```

Put IF in the loop:
```
: ccc 11 1 do  i 5 > if i . then loop ; 
```
should produce "6 7 8 9 10"

Test nested loops [https://www.forth.com/starting-forth/6-forth-do-loops/](see https://www.forth.com/starting-forth/6-forth-do-loops/):
```
: ddd cr 11 1 do
    11 1 do 
        i j * 5 u.r 
    loop cr loop ;
```
should produce math table from 1x1 to 10x10

Test EXIT:
```
: eee1 true if exit then ." true" ; 
: eee2 false if exit then ."false" ; 
```
First word should just return with "ok", second word prints "false".

Test UNLOOP: 
```
: fff 11 1 do i dup 8 = if drop unloop exit then . loop ." Done" ; 
```
should produce "1 2 3 4 5 6 7" (no "Done" printed)

Test LEAVE
```
: ggg 11 1 do i dup 8 = if leave then . loop ." Done" drop ; 
```
should produce "1 2 3 4 5 6 7 Done" (note "Done" printed)

The Data Stack should be empty after all of these words, check with .S

## Mandelbrot Set (ex Martin-H1)

See
[https://github.com/Martin-H1/Forth-CS-101/blob/master/mandlebrot.fs](https://github.com/Martin-H1/Forth-CS-101/blob/master/mandlebrot.fs)


### Stack Stuff

For 2R@
```
: t 1 >r 2 >r 2r@ .s r> r> 2drop 2drop ;  ok
t <2> 1 2  ok
```

### TEST MOVE, CMOVE and CMOVE>

Move is based on MVP and MVN instructions of the 65816

## Simple MOVE tests
```
hex
1000 10 erase           \ clean area to test in
800 8 00ff fill         \ bytes to test with, source lower (MVP)
800 1001 8 move         \ actual MOVE instruction
1000 10 dump            \ see what happened

1000 10 erase           \ next test
1100 8 00ee fill        \ bytes to test with, source higher (MVN)
1100 1001 8 move        \ actual move instruction
1000 10 dump            \ see what happened
```

### Overlapping MOVE tests 



### TEST MATH STUFF

For examples of interger divsion, see
[http://www.forth200x.org/documents/html/usage.html#usage:div](http://www.forth200x.org/documents/html/usage.html#usage:div)

For **FM/MOD**
```
: fm swap s>d rot fm/mod swap . . ; 
```
Should give you: 
10 7 --> 3 1
-10 7 --> 4 -2 
10 -7 --> -4 -2
-10 -7 --> -3 1

For **SM/REM**
```
: sm swap s>d rot sm/rem swap . . ; 
```
Should give you: 
10 7 --> 3 1
-10 7 --> -3 -1 
10 -7 --> 3 -1
-10 -7 --> -3 1


