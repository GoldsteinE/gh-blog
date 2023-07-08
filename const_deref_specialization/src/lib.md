This file is a [literate Rust] program that you can run tests on with usual Cargo commands.

Before we start, let’s get some boilerplate out of the way:

```rust
// examples are not dead, they’re for the reader
#![allow(dead_code, unused_variables, unused_macros, unused_imports)]
// assertions on constants are useful for illustrative purposes
#![allow(clippy::assertions_on_constants)]
// we’re gonna need `Deref` for deref specialization
use std::ops::Deref; 
```

[literate Rust]: https://en.wikipedia.org/wiki/Literate_programming

# Deref specialization in const contexts

There is one useful trick in Rust that’s usually called “autoref specialization”.
It allows to select a method implementation based on traits some type implements.
If you’re not familiar with the technique itself, [dtolnay described it nicely here][autoref].
This post is going to be using a variation of this idea that uses auto*de*ref instead of autoref, but
the principle is the same: (ab)use the method resolution to select behaviour based on a trait bound.

[autoref]: https://github.com/dtolnay/case-studies/blob/master/autoref-specialization/README.md

## Our case: trait bound to boolean

Let’s say you want to know whether some type implements `Send`. You want to get the result as a nice const bool,
so you can use it in const expressions or const generics. Our end goal is the following:

```rust
async fn this_one_send() {}
async fn this_one_not() {
    let s: *const () = std::ptr::null();
    this_one_send().await;
    let _ = s;
}

#[test] // this test actually passes: it uses the macro we’ll define later
fn is_send_works() {
    const R1: bool = is_send!(this_one_send());
    const R2: bool = is_send!(this_one_not());
    assert!(R1);
    assert!(!R2);
}
```

One way to achieve this would be by using deref specialization:

```rust
struct Checker<T>(T);
struct CheckerFalse;

impl<T: Send> Checker<T> {
    // this function only exists for `T: Send`
    fn check_nonconst(&self) -> bool { true }
}

impl<T> Deref for Checker<T> {
    type Target = CheckerFalse;
    fn deref(&self) -> &Self::Target { &CheckerFalse }
}

impl CheckerFalse {
    // this function exists for every `T`
    fn check_nonconst(&self) -> bool { false }
}

// We can’t use a function, because generics prevent deref specialization from working.
macro_rules! is_send_nonconst {
    ($e:expr) => { Checker($e).check_nonconst() }
}

#[test]
fn is_send_nonconst_works() {
    assert!(is_send_nonconst!(this_one_send()));
    assert!(!is_send_nonconst!(this_one_not()));
}
```

`Deref` doesn’t work in const contexts though (because it’s a trait, and calling trait methods in const
contexts is not supported on stable). Autoref wouldn’t work for similar reasons: it requires
calling a trait method on a reference (inherent impls on references are not allowed).

To achieve the same trick in a const context, we’ll need to lift our logic to the type level.

### Lifting our logic to the type level

We may think of a boolean as an enum made of two variants:

```rust
enum Bool {
    False,
    True,
}
```

Similarly, a type-level boolean is made of two types:

```rust
// type enum Bool {
struct False;
struct True;
// }
```

We’ll also want a “function” to translate our type-level boolean to a regular one. Traits are type-level functions,
so let’s write a trait:

```rust
trait TypeBool {
    const VALUE: bool;
}

impl TypeBool for False {
    const VALUE: bool = false;
}

impl TypeBool for True {
    const VALUE: bool = true;
}
```

(We could also define a trait to do a backwards translation, but that won’t be neccessary).

With this helper we can now tweak our checker to return type-level booleans instead of regular ones:

```rust
impl<T: Send> Checker<T> {
    fn check(&self) -> True { True }
}

impl CheckerFalse {
    fn check(&self) -> False { False }
}

#[test]
fn checker_works_with_type_bools() {
    fn type_bool_value<B: TypeBool>(_: B) -> bool { B::VALUE }

    assert!(type_bool_value(Checker(this_one_send()).check()));
    assert!(!type_bool_value(Checker(this_one_not()).check()));
}
```

You may wonder why we’re doing this: after all, returning different types doesn’t allow us to do
deref coercion in const contexts. This leads us to the following observation:

### Closure return types are inferred

(I’m going to open a function for this section so we can write `let` bindings)

```rust
fn closures_type_inference() {
```

Consider this closure:

```rust
let closure1 = || Checker(this_one_send()).check();
```

Were we to fully write out its type, it would look like this:

```rust
let closure2 = || -> True { Checker(this_one_send()).check() };
```

We’re not actually required to do this though, compiler can infer the return type for us.
Furthermore, we can create closures in const expressions:

```rust
// We can’t accept `T` by-value, because it would require us to drop it, which isn’t currently
// possible in const functions.
const fn accepts_something<T>(_: &T) {}
//           note this reference ^

const UNIT: () = accepts_something(&|| Checker(this_one_send()).check());
```

We can’t *call* them, but we can pass references to them to const functions, which allows us to employ
our next trick:

```rust
}  // right after we close this brace...
```

### The witness pattern

Const functions can have trait bounds. They’re not allowed to call trait methods (because trait methods can’t be const),
but they can use other trait items, like associated consts. This is enough to extract the boolean we want from the return
type of a closure, which we’ll call a *witness*, because we only use the closure itself as a witness for its type:

```rust
const fn extract_bool_from_closure<B: TypeBool>(_witness: &impl FnOnce() -> B) -> bool {
    B::VALUE
}
```

With this function as our last instrument, building the macro we want is easy:

```rust
#[macro_export] // so we can use it in a test in the beginning
macro_rules! is_send {
    ($e:expr) => {
        // We extract a boolean...
        extract_bool_from_closure(
            // From the type returned by a closure...
            &|| {
                // That calls our deref-specialization-based checker.
                Checker($e).check()
            }
        )
    }
}
```

We actually already checked that it works (since the test in the beginning passes), but let’s replicate it here
for ease of reference:

```rust
#[test]
fn is_send_still_works() {
    const R1: bool = is_send!(this_one_send());
    const R2: bool = is_send!(this_one_not());
    assert!(R1);
    assert!(!R2);
}
```

## Conclusion?

* We’ve seen how we can use deref (or autoref) specialization and possibly other patterns that require method resolution in const contexts.
* The basic idea is to use the fact that the body of a closure is never const, even if the closure itself is in a const context, combined with type inference.
* To take advantage of this we lifted our logic to the type level by using a type-level boolean and then extracted info back to values via the witness pattern.

## Bonus case study: per-module static configuration

Let’s say we have some macro which expansion needs a bit of configuration available to it. This configuration is the same
for most modules, but we want to be able to override it for some specific modules. In other words, we want to be
able to express the following API:

```rust
static DEFAULT: u8 = read_conf!();

mod foo {
    crate::set_conf_value!(24);
    pub(super) static CONF: u8 = crate::read_conf!();
}

mod bar {
    pub(super) static STILL_DEFAULT: u8 = crate::read_conf!();
}

#[test]
fn check_static_values() {
    assert_eq!(DEFAULT, 42);
    assert_eq!(foo::CONF, 24);
    assert_eq!(bar::STILL_DEFAULT, 42);
}
```

We can achieve this by using deref-based approach. First let’s lift our configuration value to the type level.
Since manually defining a type for each value of a `u8` is inconvenient, we’ll only define types for the values that are actually used:

```rust
// This is analogous to the `TypeBool` trait from above.
pub trait HasConfValue {
    const VALUE: u8;
}

// `42` lifted to the type level. That’s analogous to `struct True;` or `struct False;` from above.
pub struct DefaultConfValue;
impl HasConfValue for DefaultConfValue {
    const VALUE: u8 = 42;
}
```

We’ll get the actual conf value by calling a method on the `ConfHolder` struct:

```rust
pub struct ConfHolder;
pub struct DefaultConfHolder;

impl Deref for ConfHolder {
    type Target = DefaultConfHolder;
    fn deref(&self) -> &Self::Target { &DefaultConfHolder }
}

impl DefaultConfHolder {
    pub fn get_conf_value(&self) -> DefaultConfValue { DefaultConfValue }
}

#[test]
fn conf_holder_default() {
    fn extract_value<C: HasConfValue>(_: C) -> u8 { C::VALUE }
    assert_eq!(extract_value(ConfHolder.get_conf_value()), 42);
}
```

We’ll now need a way to define a `.get_conf_value()` method on the `ConfHolder` that’s only visible inside
of a current module. That’s easy enough: trait methods are only visible when trait is in scope.

```rust
#[macro_export]
macro_rules! set_conf_value {
    ($e:expr) => {
        struct LocalConfValue;
        impl $crate::HasConfValue for LocalConfValue {
            const VALUE: u8 = $e;
        }

        trait OverrideGetConfValue {
            fn get_conf_value(&self) -> LocalConfValue { LocalConfValue }
        }

        impl OverrideGetConfValue for $crate::ConfHolder {}
    }
}
```

Note that both impls used involve local types, so they’re not subject to the orphan rules.
This macro is fully usable outside of a current crate (which you can check by looking at [tests/conf.rs]).

The only thing remaining is to read the value, which we can easily do by employing the witness pattern:

```rust
pub const fn read_conf_inner<C: HasConfValue>(_witness: &impl FnOnce() -> C) -> u8 {
    C::VALUE
}

#[macro_export]
macro_rules! read_conf {
    () => {
        $crate::read_conf_inner(&|| $crate::ConfHolder.get_conf_value())
    }
}
```

[tests/conf.rs]: ../tests/conf.rs

## Bonus bonus case study: doing cursed things because we can

One may notice a problem with the implementation above: it’s possible to accidentally import
the override trait (with `use super::*;`) and inherit the override with it:

```rust
mod outer {
    crate::set_conf_value!(123);
    mod inner {
        use super::*;

        // Can’t set conf value here: we inherited one from the parent.
        #[test]
        fn inherited_value() {
            assert_eq!(crate::read_conf!(), 123);
        }
    }
}
```

This may or may not be desirable, depending on your exact use case. One way to suppress this inheriting
behaviour would be to ensure that each module uses a different type to get configuration. We still
want a single type to set a default though. Luckily, this contradiction is easily solved by having one
generic type with different parameters for each module.

There’s one small problem left: how do we get this unique-per-module parameter? We can’t define it in the
`set_conf_value!()` expansion, since `read_conf!()` needs to use it even if `set_conf_value!()` was never called
in this module. A simple solution would be to use the path to the current module as a const generic parameter.
Unfortunately, `&str` const generics are not supported. We’ll do the next best thing and use a hash of the module
path instead:

```rust
pub const fn digest(module_path: &str) -> u128 {
    // We could use some better algorithm if we were worried about collisions.
    // There’s `const-sha1` on crates.io that should be good enough, unless you’re trying
    // to deal with adversary who maliciously chooses module names for some reason.
    const_fnv1a_hash::fnv1a_hash_str_128(module_path)
}

pub struct Module<const HASH: u128>;
pub struct ModuleDefault;

impl<const HASH: u128> Deref for Module<HASH> {
    type Target = ModuleDefault;
    fn deref(&self) -> &Self::Target { &ModuleDefault }
}

impl ModuleDefault {
    pub fn get_conf_value(&self) -> DefaultConfValue { DefaultConfValue }
}
```

Both overriding and reading are done only for the current module:

```rust
#[macro_export]
macro_rules! set_conf_value_exact {
    ($e:expr) => {
        struct LocalConfValue;
        impl $crate::HasConfValue for LocalConfValue {
            const VALUE: u8 = $e;
        }

        trait OverrideGetConfValue {
            fn get_conf_value(&self) -> LocalConfValue { LocalConfValue }
        }

        impl OverrideGetConfValue for $crate::Module<{ $crate::digest(module_path!()) }> {}
        // new: specify hash when overriding         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    }
}

#[macro_export]
macro_rules! read_conf_exact {
    () => {
        $crate::read_conf_inner(&|| {
            $crate::Module::<{ $crate::digest(module_path!()) }>.get_conf_value()
        })
    }
}
```

Now `use super::*;` doesn’t inherit configuration values:

```rust
mod outer_new {
    crate::set_conf_value_exact!(123);

    mod inner1 {
        use super::*;

        #[test]
        fn value_not_inherited() {
            assert_eq!(crate::read_conf_exact!(), 42);
        }
    }

    mod inner2 {
        use super::*;
        crate::set_conf_value_exact!(69);

        #[test]
        fn override_works() {
            assert_eq!(crate::read_conf_exact!(), 69);
        }
    }
}
```

You can check that this still works outside of the crate by looking at [tests/conf_exact.rs].

[tests/conf_exact.rs]: ../tests/conf_exact.rs

## Thanks

* To [@kanashimia] and [@Kolsky] for proofreading this post.
* To [@cpud36] for suggesting a local trait technique for the bonus part.

[@kanashimia]: https://github.com/kanashimia
[@Kolsky]: https://github.com/Kolsky
[@cpud36]: https://github.com/cpud36
