// That’s the same test as in the main file. It’s here just to prove that it works outside of the
// main crate.

extern crate const_deref_specialization as c;

static DEFAULT: u8 = c::read_conf!();

mod foo {
    c::set_conf_value!(24);
    pub(super) static CONF: u8 = c::read_conf!();
}

mod bar {
    pub(super) static STILL_DEFAULT: u8 = c::read_conf!();
}

#[test]
fn check_static_values() {
    assert_eq!(DEFAULT, 42);
    assert_eq!(foo::CONF, 24);
    assert_eq!(bar::STILL_DEFAULT, 42);
}
