use std::{mem::MaybeUninit, sync::Mutex};

use rand_chacha::ChaCha20Rng;

#[cfg(not(target_os = "linux"))]
compile_error!("only Linux is currently supported");

mod error;
pub use error::Error;
use rand_core::{RngCore, SeedableRng};

mod real {
    use std::ffi::{c_int, c_void};

    extern "C" {
        pub(crate) fn getentropy(buf: *mut c_void, buflen: usize) -> c_int;
    }
}

static RNG: Mutex<Option<ChaCha20Rng>> = Mutex::new(None);

pub fn _seed_random() -> [u8; 32] {
    let mut buf = [0_u8; 32];
    // SAFETY: we're passing a valid buffer.
    let res = unsafe { real::getentropy(buf.as_mut_ptr().cast(), 32) };
    if res != 0 {
        let err = std::io::Error::last_os_error();
        panic!("failed to call getentropy(): {err}");
    }
    *RNG.lock().unwrap() = Some(ChaCha20Rng::from_seed(buf));
    buf
}

pub fn _seed(seed: [u8; 32]) {
    *RNG.lock().unwrap() = Some(ChaCha20Rng::from_seed(seed));
}

pub fn getrandom_uninit(dest: &mut [MaybeUninit<u8>]) -> Result<&mut [u8], Error> {
    dest.fill(MaybeUninit::new(0));
    let dest = unsafe { std::slice::from_raw_parts_mut(dest.as_mut_ptr().cast(), dest.len()) };
    getrandom(&mut *dest)?;
    Ok(dest)
}

pub fn getrandom(dest: &mut [u8]) -> Result<(), Error> {
    RNG.lock()
        .unwrap()
        .as_mut()
        .expect("fake getrandom RNG is not initialized")
        .fill_bytes(dest);
    Ok(())
}
