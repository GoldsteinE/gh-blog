// That’s the same test as in the main file. It’s here just to prove that it works outside of the
// main crate.

extern crate const_deref_specialization as c;

#[allow(unused_imports)]
mod outer_new {
    c::set_conf_value_exact!(123);

    mod inner1 {
        use super::*;

        #[test]
        fn value_not_inherited() {
            assert_eq!(c::read_conf_exact!(), 42);
        }
    }

    mod inner2 {
        use super::*;
        c::set_conf_value_exact!(69);

        #[test]
        fn override_works() {
            assert_eq!(c::read_conf_exact!(), 69);
        }
    }
}
