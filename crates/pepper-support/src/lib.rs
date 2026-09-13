//! Pepper runtime support: C ABI functions the JIT'd/generated code links
//! against. Port of `support/Support.cpp` (POSIX paths only; the Windows
//! guard-page/VirtualAlloc machinery and `PEP_MEMTRACK` env modes are not
//! ported — no test exercises them).

use std::ffi::{c_char, c_void, CStr, CString};
use std::hint::black_box;
use std::sync::OnceLock;

type AssertFn = unsafe extern "C" fn(bool, *const c_char);

static ASSERT_FN: std::sync::OnceLock<usize> = std::sync::OnceLock::new();

/// Store the assert callback used by `_pep_assert` (port of `SupportInit`).
#[unsafe(no_mangle)]
pub extern "C" fn SupportInit(assert_fn: AssertFn) {
    let _ = ASSERT_FN.set(assert_fn as usize);
}

/// Print a panic message and abort (port of `panic`).
#[unsafe(no_mangle)]
pub extern "C" fn panic(msg: *const c_char) {
    let msg = if msg.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(msg) }.to_string_lossy().into_owned()
    };
    if !msg.is_empty() {
        eprintln!("{}", msg);
    } else {
        eprintln!("Assertion failed with no additional information");
    }
    std::process::abort();
}

/// Trace a memory region (port of `trace_region`).
#[unsafe(no_mangle)]
pub extern "C" fn trace_region(ptr: *const c_void, size: usize, name: *const c_char) {
    let name = if name.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(name) }.to_string_lossy().into_owned()
    };
    let base = ptr as *const u64;
    let word = size / std::mem::size_of::<u64>();
    // Print the header; remember printed width for body indentation.
    let header = if base.is_null() {
        println!("{}: 0x0 -> {:016X}", name, 0usize);
        0usize
    } else {
        let line = format!("{}: {:p} -> {:016X}", name, base, unsafe { *base });
        println!("{}", line);
        line.len()
    };
    if !base.is_null() {
        for idx in 0..word {
            let addr = unsafe { base.add(idx) };
            let value = unsafe { *addr };
            let bytes = value.to_le_bytes();
            let bytes = &bytes[..size.min(std::mem::size_of::<u64>())];
            print!("{:>width$} {:016X} ", ' ', value, width = header.saturating_sub(18));
            for (i, b) in bytes.iter().enumerate() {
                print!("{}", if i < size { if *b == 0 { '0' } else { *b as char } } else { '.' });
            }
            println!();
        }
    }
    use std::io::Write;
    let _ = std::io::stdout().flush();
}

/// Trace a single pointer word (port of `trace_ptr`).
#[unsafe(no_mangle)]
pub extern "C" fn trace_ptr(ptr: *const c_void, name: *const c_char) {
    trace_region(ptr, std::mem::size_of::<u64>(), name);
}

/// Trace an integer (port of `trace_int`).
#[unsafe(no_mangle)]
pub extern "C" fn trace_int(value: i64, name: *const c_char) {
    let name = if name.is_null() { "".to_string() } else { unsafe { CStr::from_ptr(name) }.to_string_lossy().into_owned() };
    println!("{}: {}", name, value);
}

/// Assert hook (port of `_pep_assert`).
#[unsafe(no_mangle)]
pub extern "C" fn _pep_assert(condition: bool, message: *const c_char) {
    if let Some(&fnptr) = ASSERT_FN.get() {
        let f: AssertFn = unsafe { std::mem::transmute(fnptr) };
        unsafe { f(condition, message) };
        return;
    }
    let message = if message.is_null() { "".to_string() } else { unsafe { CStr::from_ptr(message) }.to_string_lossy().into_owned() };
    eprintln!("assert failed: {}", message);
    debug_assert!(condition);
}

/// Zero-initialized allocation (port of `_pep_malloc`, tracking off).
#[unsafe(no_mangle)]
pub extern "C" fn _pep_malloc(size: usize) -> *mut c_void {
    let alloc_size = size.max(1);
    unsafe {
        let layout = std::alloc::Layout::from_size_align(alloc_size, 1).unwrap();
        let ptr = std::alloc::alloc(layout);
        std::ptr::write_bytes(ptr, 0, alloc_size);
        ptr as *mut c_void
    }
}

/// Manual realloc: copy min(prev, new), zero the tail (port of `_pep_realloc`).
#[unsafe(no_mangle)]
pub extern "C" fn _pep_realloc(ptr: *mut c_void, prev_size: usize, new_size: usize) -> *mut c_void {
    let new_mem = _pep_malloc(new_size);
    if !ptr.is_null() {
        unsafe {
            std::ptr::copy_nonoverlapping(ptr as *const u8, new_mem as *mut u8, prev_size.min(new_size));
            let layout = std::alloc::Layout::from_size_align(prev_size.max(1), 1).unwrap();
            std::alloc::dealloc(ptr as *mut u8, layout);
        }
    }
    new_mem
}

/// Free (port of `_pep_free`, tracking off).
#[unsafe(no_mangle)]
pub extern "C" fn _pep_free(ptr: *mut c_void) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        // Size is not recoverable without tracking; allocate/unfree deallocation
        // is done via the same 1-aligned layout used by _pep_malloc.
        let layout = std::alloc::Layout::from_size_align(1, 1).unwrap();
        std::alloc::dealloc(ptr as *mut u8, layout);
    }
}

/// UTF-8 character count; invalid UTF-8 returns 0 (port of `_pep_utf8_length`).
#[unsafe(no_mangle)]
pub extern "C" fn _pep_utf8_length(s: *const c_char) -> usize {
    let bytes = unsafe { CStr::from_ptr(s) }.to_bytes();
    let s = match std::str::from_utf8(bytes) {
        Ok(s) => s,
        Err(_) => return 0,
    };
    s.chars().count()
}

/// Byte size of the first `chars` characters (port of `_pep_utf8_size`).
#[unsafe(no_mangle)]
pub extern "C" fn _pep_utf8_size(s: *const c_char, chars: u32) -> usize {
    let bytes = unsafe { CStr::from_ptr(s) }.to_bytes();
    if chars == 0 {
        return bytes.len();
    }
    let s = match std::str::from_utf8(bytes) {
        Ok(s) => s,
        Err(_) => return 0,
    };
    s.chars().take(chars as usize).map(|c| c.len_utf8()).sum()
}

/// Equality compare with optional length cap (port of `_pep_utf8_compare`).
#[unsafe(no_mangle)]
pub extern "C" fn _pep_utf8_compare(a: *const c_char, b: *const c_char, size: usize) -> bool {
    let a = unsafe { CStr::from_ptr(a) }.to_bytes();
    let b = unsafe { CStr::from_ptr(b) }.to_bytes();
    if size == 0 {
        a == b
    } else {
        a.len() >= size && b.len() >= size && a[..size] == b[..size]
    }
}

/// Print a UTF-8 string followed by a newline (backs the `print` builtin).
#[unsafe(no_mangle)]
pub extern "C" fn _pep_print(s: *const c_char) {
    if s.is_null() {
        return;
    }
    let s = unsafe { CStr::from_ptr(s) }.to_string_lossy();
    println!("{}", s);
}

/// Print an integer (backs `print` with int args).
#[unsafe(no_mangle)]
pub extern "C" fn _pep_print_int(value: i64) {
    println!("{}", value);
}

/// Force retention of every exported symbol: the linker GCs `#[no_mangle]`
/// symbols in an rlib unless referenced, but the JIT'd module references them
/// only at runtime. Returns the addresses (kept opaque) for callers.
pub fn retain_support_symbols() -> [usize; 12] {
    [
        black_box(SupportInit as usize),
        black_box(panic as usize),
        black_box(trace_region as usize),
        black_box(trace_ptr as usize),
        black_box(trace_int as usize),
        black_box(_pep_assert as usize),
        black_box(_pep_malloc as usize),
        black_box(_pep_realloc as usize),
        black_box(_pep_free as usize),
        black_box(_pep_utf8_length as usize),
        black_box(_pep_utf8_size as usize),
        black_box(_pep_utf8_compare as usize),
    ]
}

/// Format a Rust string as a C string for callers that need to pass literals
/// into the C ABI.
pub fn c_string(s: &str) -> CString {
    CString::new(s).expect("interior NUL byte")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf8_length_counts_chars() {
        assert_eq!(_pep_utf8_length(c_string("héllo").as_ptr()), 5);
        assert_eq!(_pep_utf8_length(c_string("hello").as_ptr()), 5);
        assert_eq!(_pep_utf8_length(c_string("").as_ptr()), 0);
    }

    #[test]
    fn utf8_length_rejects_invalid_utf8() {
        // 0xFF is never valid in UTF-8.
        let bytes = [0xFFu8, 0x00];
        assert_eq!(_pep_utf8_length(bytes.as_ptr() as *const c_char), 0);
    }

    #[test]
    fn utf8_size_reports_byte_size() {
        assert_eq!(_pep_utf8_size(c_string("héllo").as_ptr(), 0), 6);
        assert_eq!(_pep_utf8_size(c_string("héllo").as_ptr(), 2), 3);
        assert_eq!(_pep_utf8_size(c_string("hello").as_ptr(), 3), 3);
    }

    #[test]
    fn malloc_realloc_free_roundtrip() {
        let mem = _pep_malloc(16);
        assert!(!mem.is_null());
        // Zero-initialized.
        for i in 0..16 {
            assert_eq!(unsafe { *(mem as *const u8).add(i) }, 0);
        }
        unsafe {
            *(mem as *mut u8).add(0) = 42;
            *(mem as *mut u8).add(15) = 7;
        }
        let grown = _pep_realloc(mem, 16, 32);
        assert!(!grown.is_null());
        unsafe {
            assert_eq!(*(grown as *const u8).add(0), 42);
            assert_eq!(*(grown as *const u8).add(15), 7);
            // Tail zeroed.
            assert_eq!(*(grown as *const u8).add(16), 0);
            assert_eq!(*(grown as *const u8).add(31), 0);
        }
        let shrunk = _pep_realloc(grown, 32, 8);
        unsafe {
            assert_eq!(*(shrunk as *const u8).add(0), 42);
        }
        _pep_free(shrunk);
    }

    #[test]
    fn utf8_compare() {
        let a = c_string("abc");
        let b = c_string("abc");
        let c = c_string("abd");
        assert!(_pep_utf8_compare(a.as_ptr(), b.as_ptr(), 0));
        assert!(_pep_utf8_compare(a.as_ptr(), c.as_ptr(), 2));
        assert!(!_pep_utf8_compare(a.as_ptr(), c.as_ptr(), 0));
    }

    #[test]
    fn retain_covers_all_exports() {
        let addrs = retain_support_symbols();
        assert!(addrs.iter().all(|a| *a != 0));
    }
}
