# Poking MoonBit with a stick (part 1?)

Recently a new language started appearing on my various content feeds. Its name is MoonBit and it’s
described by its authors as “the fast, compact & user friendly language for WebAssembly”.

I’m quite interested in languages targeting WASM. A big problem to solve here is binary sizes:
WASM as a target is oftenly used in place of scripts (e.g. [helix] is thinking about adopting WASM
[for their plugin ecosystem][helix-plugins], not to speak of the obvious Web usage), so small bundles
are desired and even expected. But because WASM currently doesn’t offer a native GC, every bundle
must contain a language runtime, which can take a lot of space. For example, full Go compiler
[seems to produce][go-wasm] minimal binary sizes of about 1-2 MiB, and even TinyGo gives
more than a hundred KiB for a simple program. A big selling point for MoonBit is small binary sizes:
their benchmark was compiled to 253 _bytes_, which is quite impressive.

Before we go further, I recommend you to read their [announcement post]. It’s not very long and
I don’t want to repeat its contents here.

To be clear, the point of this post is _not_ to say that MoonBit is a bad project or that they’re
underselling on their promises. It’s currently alpha stage, and it’s very normal for an alpha stage
software to miss some features. I’m hopeful to see a future development of this language.

[helix]: https://helix-editor.com
[helix-plugins]: https://github.com/helix-editor/helix/issues/122
[go-wasm]: https://elewis.dev/are-we-wasm-yet-part-1
[announcement post]: https://moonbitlang.com/blog/first-announce/

## So what’s up with these benchmarks?

253 bytes binary and “as fast as Rust” seems to be a very impressive result. Let’s dig into this
benchmark some more.

They’re measuring binary size and performance of the following code:

```
func fib(num : Int) -> Int {
  fn aux(n, acc1, acc2) {
    match n {
      0 => acc1
      1 => acc2
      _ => aux(n - 1, acc2, acc1 + acc2)
    }
  }

  aux(num, 0, 1)
}
```

(Implementations in Rust and Go are very similar, so I won’t show them here)

This snippet showcases support for eliminating tail calls: that’s why an auxillary function is used.
MoonBit apparently guarantees this optimization (unfortunately, the source code isn’t available, so
I was unable to check), Rust is [able to perform it][rust-fib-wasm] by relying on LLVM and
Go [doesn’t do it on x86_64][go-fib-x86], but seems to be able to perform it on WASM.
I’m not totally sure, because Go codegen is kinda horrifying, but I think that the recursive call
got translated into [this one br on line 622806][go-fib-wasm]. Unsurprisingly, Go produces a giant
binary and Rust generates something quite readable thanks to its minimal runtime.

MoonBit codegen is actually nice enough to include the full snippet here:

```wat
(module (memory $rael.memory (export "memory") 1)
 (table $rael.global funcref (elem))
 ;; The inner function got inlined.
 (func $fib.fn/2 (export "moonapp/lib::fib") (param $num/1 i32) (result i32)
  ;; Readable variable names!
  (local $n/3 i32) (local $acc1/4 i32) (local $acc2/5 i32) (local $x/6 i32)
  (block $join:2 (local.get $num/1) (i32.const 0) (i32.const 1)
   (local.set $acc2/5) (local.set $acc1/4) (local.set $n/3) (br $join:2))
  ;; Recursion got compiled into a nice loop.
  (loop $join:2 (result i32) (local.get $n/3) (local.set $x/6)
   (block $join:7
    (block $join:8
     (block $join:9 (local.get $x/6) (i32.const 0) (i32.eq)
      ;; First match branch
      (if (result i32) (then (br $join:9))
       (else (local.get $x/6) (i32.const 1) (i32.eq)
        ;; Second match branch
        (if (result i32) (then (br $join:8)) (else (br $join:7)))))
      (return))
     (local.get $acc1/4) (return))
    (local.get $acc2/5) (return))
   (local.get $n/3) (i32.const 1) (i32.sub) (local.get $acc2/5)
   (local.get $acc1/4) (local.get $acc2/5) (i32.add) (local.set $acc2/5)
   ;; Recursion step: jump to the beginning of the loop.
   (local.set $acc1/4) (local.set $n/3) (br $join:2)))
 (func $run.fn/1 (export "moonapp/lib::run") (result i32) (i32.const 0))
 (func $*init*/3 (call $run.fn/1) (drop)) (export "_start" (func $*init*/3)))
```

Its binary size is 211 bytes (interestingly, MoonBit compiler actually generates WAT, not WASM).
I was able to verify the benchmark results.

There’s one thing missing here though...

[rust-fib-wasm]: fib-rust.wat#L32
[go-fib-x86]: fib-go.asm#L57
[go-fib-wasm]: fib-go.wat#L246

## What’s up with memory management?

The Fibonacci numbers benchmark showcases tail-call optimization and control flow. What it doesn’t
showcase is memory management: nothing gets allocated on the heap, so there’s nothing to clean up.

Memory management is what interested me though, so I’ve written my own benchmark:

```
// I want to generate and then consume some binary trees.
enum IntTree {
  // This is a leaf node with no children...
  Leaf
  // ...and this is a normal node with two children.
  Node(Int, IntTree, IntTree)
}

// It’s not really important how the tree itself looks.
// The important part is that generating it is allocation-heavy:
// every node except root must be allocated somewhere.
pub func gen_tree(n : Int) -> IntTree {
  match n {
    0 => Leaf
    1 => Node(1, gen_tree(0), Leaf)
    _ => Node(n, gen_tree(n - 1), gen_tree(n - 2))
  }
}

// To make sure that tree is actually generating, we try to print it
// in this nice emoji-based format.
pub func print_tree(self : IntTree) {
  match self {
    Leaf => "🍁".print()
    Node(n, l, r) => {
      "🌳(".print();
      n.print();
      ", ".print();
      print_tree(l);
      ", ".print();
      print_tree(r);
      ")".print()
    }
  }
}

pub func run() {
  while (true) {
    gen_tree(10).print_tree();
    "\n".print();
  }
}
```

Now we can compile and run this simple code:

```
; wasmtime run compiled.wasm
Error: failed to run main module `compiled.wasm`

Caused by:
    0: failed to instantiate "compiled.wasm"
    1: command export 'rael_heap_base' is not a function
```

### wait what.

Okay, maybe it’s not WASI-compatible or something. Maybe it’s meant to be run in a browser. After all,
their demo runs in a browser, so surely it must work here.

Let’s just write a simple JS script to start it:

```javascript
window.onload = async function() {
  const wasm = await fetch('compiled.wasm').then((res) => res.arrayBuffer());
  const result = await WebAssembly.instantiate(wasm, {});
  result.instance.exports._start();
}
```

Now we open the page in browser and we see clear and nice:

```
Uncaught (in promise) TypeError: import object field 'spectest' is not an Object
```

That’s interesting. Let’s take a look on the [generated WASM][tree-moon-wasm] (no need to click the link,
I’ll include all the relevant snippets here):

```wat
(module
 ;; ...
 (import "spectest" "print_i32" (func $printi (param $i i32)))
 (import "spectest" "print_char" (func $printc (param $i i32)))
 ;; ...
 )
```

Okay, so it looks like it needs `spectest.print_i32` and `spectest.print_char` to actually function.
I think `print_i32` originates from WABT, where it’s [included as a part of some test][wabt-print],
and `print_char` is MoonBit’s own invention. Their benchmark code worked because it never actually
used the standard output (that actually shows quite nice dead code elimination). Anyway, I verified
with `moon run` that the code actually prints nice little trees and just stubbed these functions:

```javascript
const result = await WebAssembly.instantiate(wasm, {
  spectest: {
    print_i32: () => {},
    print_char: () => {},
  },
});
```

I was not sure whether it was intended, so I [filed an issue][spectest-issue]. It was promptly
replied to (thanks!) and then closed.

One interesting thing to note here is that there’s no `print_str` or similar. Indeed, strings
are printed charwise:

```wat
(func $rael.output_string (param $str i32) (local $counter i32)
 (loop $loop
  (if
   (i32.lt_s (local.get $counter)
    (call $rael.string_length (local.get $str)))
   (then
    (call $printc
     (call $rael.string_item (local.get $str) (local.get $counter)))
    (local.set $counter (i32.add (local.get $counter) (i32.const 1)))
    (br $loop))
   (else))))
```

That’s Not Great for performance, so probably this spectest-based output is temporary and will be
replaced by something better in the future.

[tree-moon-wasm]: tree-moon.wat
[wabt-print]: https://github.com/WebAssembly/wabt/blob/e7c03091ccc9f53c84299aed08fa963e121afd80/src/tools/spectest-interp.cc#L1277
[spectest-issue]: https://github.com/moonbitlang/moonbit-docs/issues/50

### Back to the memory management

I started the code again and this time it worked. My browsers performance tab had shown that
the memory usage was steadily going up. I closed the tab when it reached 3 GiB and returned to the
WAT listing. What happened?

Here’s our `print_tree` function (with some irrelevant parts cut for brevity). It receives a tree
as an input, so it has to drop it if no one else wants it.

```
(func $print_tree.fn/2
 ;; ...
 (block $join:8
  (block $join:12 (local.get $x/7) (call $rael.get_tag) (local.set $tag/21)
   (if (result i32) (i32.eq (local.get $tag/21) (i32.const 0))
    (then (br $join:12))
    (else (local.get $x/7) (i32.load offset=4) (local.tee $x/13)
     ;; ...
     (local.set $l/9) (br $join:8)))
   (return))
  (i32.const 10008) (call $rael.output_string) (i32.const 0) (return))
 (i32.const 10056) (call $rael.output_string) (local.get $n/10)
 (call $printi) (i32.const 10040) (call $rael.output_string)
 (local.get $l/9) (call $print_tree.fn/2) (drop) (i32.const 10040)
 (call $rael.output_string) (local.get $r/11) (call $print_tree.fn/2) 
 (drop) (i32.const 10024) (call $rael.output_string) (i32.const 0))
```

That’s weird. It doesn’t seem to actually drop anything (the `(drop)` thingy is just a pop from the
WASM stack, it doesn’t execute any destructors). In fact, there’re `$rael.gc.malloc` and `$rael.malloc`
functions defined, but no `$rael.free` or similar. I [filed an issue][gc-issue] and received a reply
that GC is not ready yet. Welp. It’s the one thing I’ll be eager to check out when it’s ready.

Given that this code doesn’t ever deallocate memory, I didn’t benchmark it, since a comparison with
a version that actually does memory management wouldn’t be fair anyway.

[gc-issue]: https://github.com/moonbitlang/moonbit-docs/issues/51

### Conclusions?

1. MoonBit’s compiler (apparently fully hand-written in OCaml: I wasn’t able to find LLVM or similar
   symbols anywhere in the binary) is good at dead code elimination, is able to perform TCO
   and produces surprisingly concise and readable WAT.

2. Their benchmark results are reproducible. I don’t particularly like Fibonacci as a benchmark though,
   so I’ll make some more and check them. If you have any ideas (that don’t involve allocating memory),
   please write me to [root@goldstein.rs], Telegram [@goldsteinq] or tag me in fedi at [@goldstein@im-in.space].

3. The most interesting for me part wasn’t implemented yet. I’ll make a follow-up post when GC is available.

4. Go codegen is weird. I know that’s not about MoonBit, but it bothers me so much. I knew that Go
   doesn’t really inline functions unless they’re just a few lines, but the generated code is really
   huge and all the calls are made dynamic for some reason. If someone knows why that happens, please
   get in touch.

[root@goldstein.rs]: mailto:root@goldstein.rs
[@goldsteinq]: https://t.me/goldsteinq
[@goldstein@im-in.space]: https://im-in.space/@goldstein

### License stuff

WAT code snippets include functions that are probably a part of MoonBit’s standard library. MoonBit
didn’t clarify their license. I believe my usage is fair-use (and I’m ready to take it down if MoonBit
reaches out), but I can’t license you to use it.

All of my code is MIT OR Unlicense, all of my text is CC BY-SA 4.0.
