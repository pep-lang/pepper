//! Pepper runtime support: C ABI functions the JIT'd/generated code links
//! against. Port of `support/Support.cpp` (POSIX paths only; the Windows
//! guard-page/VirtualAlloc machinery and `PEP_MEMTRACK` env modes are not
//! ported — no test exercises them).

use std::ffi::{c_char, c_void, CStr, CString};
use std::hint::black_box;

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

/// Trace output is off unless `PEP_TRACE` is set to a non-empty value; the
/// synthesized acquire/release/ctor/dtor bodies call these unconditionally,
/// so without the gate every struct-element array op pollutes stdout.
fn trace_enabled() -> bool {
    static ENABLED: std::sync::LazyLock<bool> =
        std::sync::LazyLock::new(|| std::env::var_os("PEP_TRACE").is_some_and(|v| !v.is_empty()));
    *ENABLED
}

/// Trace a memory region (port of `trace_region`).
#[unsafe(no_mangle)]
pub extern "C" fn trace_region(ptr: *const c_void, size: usize, name: *const c_char) {
    if !trace_enabled() {
        return;
    }
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
    if !trace_enabled() {
        return;
    }
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

/// Allocation header stored before the returned pointer: a magic word plus
/// the size, so `_pep_free` and `_pep_realloc` can deallocate with the layout
/// used at allocation time (std requires an identical layout) without a
/// global table. The magic is zeroed on free, so a double free or a foreign
/// pointer is diagnosed instead of deallocating a wild base.
const MAGIC: usize = 0x5045_5041_4C4C; // "PEPALL"
const HEADER: usize = std::mem::size_of::<usize>() * 2;
const ALIGN: usize = std::mem::align_of::<usize>();

fn layout_for(size: usize) -> std::alloc::Layout {
    std::alloc::Layout::from_size_align(size + HEADER, ALIGN).unwrap()
}

fn alloc_with_header(size: usize) -> *mut c_void {
    let base = unsafe { std::alloc::alloc(layout_for(size)) };
    unsafe {
        (base as *mut usize).write(MAGIC);
        base.add(std::mem::size_of::<usize>()).cast::<usize>().write(size);
        std::ptr::write_bytes(base.add(HEADER), 0, size);
        base.add(HEADER) as *mut c_void
    }
}

/// (allocation base, recorded size) for a pointer returned by `_pep_malloc`;
/// `None` when the magic is absent — a foreign pointer or one already freed.
fn base_and_size(ptr: *const c_void) -> Option<(*mut u8, usize)> {
    let p = ptr as *mut u8;
    unsafe {
        if (p.sub(HEADER) as *const usize).read() != MAGIC {
            return None;
        }
        let size = (p.sub(std::mem::size_of::<usize>()) as *const usize).read();
        Some((p.sub(HEADER), size))
    }
}

/// Live-allocation counter for leak tests: every `_pep_malloc` +1, every
/// successful `_pep_free` -1. `realloc` goes through the raw allocator so a
/// grow is counted exactly once (the net new block).
static LIVE_ALLOCS: std::sync::atomic::AtomicI64 = std::sync::atomic::AtomicI64::new(0);

#[unsafe(no_mangle)]
pub extern "C" fn _pep_malloc(size: usize) -> *mut c_void {
    LIVE_ALLOCS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    alloc_with_header(size)
}

/// Current live-allocation count (leak-test baseline helper).
#[unsafe(no_mangle)]
pub extern "C" fn _pep_live_allocs() -> i64 {
    LIVE_ALLOCS.load(std::sync::atomic::Ordering::Relaxed)
}

#[unsafe(no_mangle)]
pub extern "C" fn _pep_realloc(ptr: *mut c_void, prev_size: usize, new_size: usize) -> *mut c_void {
    let new_mem = alloc_with_header(new_size);
    LIVE_ALLOCS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    if !ptr.is_null() {
        match base_and_size(ptr) {
            Some((base, size)) => unsafe {
                std::ptr::copy_nonoverlapping(ptr as *const u8, new_mem.cast::<u8>(), prev_size.min(new_size));
                (base as *mut usize).write(0);
                std::alloc::dealloc(base, layout_for(size));
                LIVE_ALLOCS.fetch_sub(1, std::sync::atomic::Ordering::Relaxed);
            },
            None => eprintln!("_pep_realloc: unknown pointer {:p}", ptr),
        }
    }
    new_mem
}

#[unsafe(no_mangle)]
pub extern "C" fn _pep_free(ptr: *mut c_void) {
    if ptr.is_null() {
        return;
    }
    match base_and_size(ptr) {
        Some((base, size)) => unsafe {
            (base as *mut usize).write(0);
            std::alloc::dealloc(base, layout_for(size));
            LIVE_ALLOCS.fetch_sub(1, std::sync::atomic::Ordering::Relaxed);
        },
        None => eprintln!("_pep_free: unknown or double-freed pointer {:p}", ptr),
    }
}

/// Exchange the reference (first pointer-sized bytes) of two slots in a
/// struct-element buffer. Raw pointer moves keep both references owned by the
/// array, which per-slot release/acquire cannot express for swap.
#[unsafe(no_mangle)]
pub extern "C" fn _pep_swap_refs(p: *mut c_void, stride: usize, i: usize, j: usize) {
    if i == j {
        return;
    }
    const SLOT: usize = std::mem::size_of::<*mut c_void>();
    let len = stride.min(SLOT);
    unsafe {
        let a = p.add(i * stride).cast::<u8>();
        let b = p.add(j * stride).cast::<u8>();
        let mut tmp = [0u8; SLOT];
        std::ptr::copy_nonoverlapping(a, tmp.as_mut_ptr(), len);
        std::ptr::copy_nonoverlapping(b, a, len);
        std::ptr::copy_nonoverlapping(tmp.as_ptr(), b, len);
    }
}

/// FNV-1a 64-bit over a byte range. Same constants as the compiler's
/// `__address` lowering, so content hashes agree across both paths.
#[unsafe(no_mangle)]
pub extern "C" fn _pep_hash_bytes(data: *const c_void, length: usize) -> u64 {
    const OFFSET_BASIS: u64 = 0xcbf2_9ce4_8422_2325;
    const PRIME: u64 = 0x0000_0100_0000_01b3;
    // `from_raw_parts` needs a non-null, aligned pointer even for zero
    // length; default-constructed strings carry a null `Data`.
    if data.is_null() || length == 0 {
        return OFFSET_BASIS;
    }
    let mut h = OFFSET_BASIS;
    let bytes = unsafe { std::slice::from_raw_parts(data.cast::<u8>(), length) };
    for &b in bytes {
        h ^= b as u64;
        h = h.wrapping_mul(PRIME);
    }
    h
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

/// Byte offset of `needle` inside `haystack`, or -1. Both are raw byte spans.
#[unsafe(no_mangle)]
pub extern "C" fn _pep_utf8_find(
    haystack: *const u8,
    haystack_size: usize,
    needle: *const u8,
    needle_size: usize,
) -> isize {
    if haystack.is_null() || haystack_size == 0 {
        return -1;
    }
    let haystack = unsafe { std::slice::from_raw_parts(haystack, haystack_size) };
    if needle_size == 0 {
        return 0;
    }
    if needle.is_null() {
        return -1;
    }
    let needle = unsafe { std::slice::from_raw_parts(needle, needle_size) };
    match (std::str::from_utf8(haystack), std::str::from_utf8(needle)) {
        (Ok(h), Ok(n)) => h.find(n).map(|o| o as isize).unwrap_or(-1),
        _ => -1,
    }
}

/// Byte offset reached after `chars` characters, clamped to `size`.
#[unsafe(no_mangle)]
pub extern "C" fn _pep_utf8_char_offset(data: *const u8, size: usize, chars: usize) -> usize {
    if data.is_null() || size == 0 {
        return 0;
    }
    let bytes = unsafe { std::slice::from_raw_parts(data, size) };
    let s = match std::str::from_utf8(bytes) {
        Ok(s) => s,
        Err(_) => return size,
    };
    // take(chars) caps at the available character count, so the sum is
    // already clamped to `size` for valid UTF-8.
    s.chars().take(chars).map(|c| c.len_utf8()).sum()
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

/// Print a float (backs `print` with float args). Codegen widens every float
/// argument to f64 before the call, so this takes a double.
#[unsafe(no_mangle)]
pub extern "C" fn _pep_print_float(value: f64) {
    println!("{}", value);
}

/// Every symbol the generated code may call, paired with its address.
///
/// Two jobs. First, referencing the functions here keeps the linker from GC'ing
/// `#[no_mangle]` symbols out of this rlib, since compiled Pepper code only
/// references them at runtime. Second, the JIT needs the addresses explicitly:
/// symbols of a static rlib linked into an executable are not in the process's
/// export table (notably on Windows), so MCJIT's symbol search cannot find them
/// and calls into unresolved addresses. `pepper-codegen` binds this table into
/// the execution engine with LLVMAddGlobalMapping.
pub fn support_symbols() -> Vec<(&'static str, usize)> {
    vec![
        ("SupportInit", black_box(SupportInit as usize)),
        ("panic", black_box(panic as usize)),
        ("trace_region", black_box(trace_region as usize)),
        ("trace_ptr", black_box(trace_ptr as usize)),
        ("trace_int", black_box(trace_int as usize)),
        ("_pep_assert", black_box(_pep_assert as usize)),
        ("_pep_malloc", black_box(_pep_malloc as usize)),
        ("_pep_realloc", black_box(_pep_realloc as usize)),
        ("_pep_free", black_box(_pep_free as usize)),
        ("_pep_print", black_box(_pep_print as usize)),
        ("_pep_print_int", black_box(_pep_print_int as usize)),
        ("_pep_print_float", black_box(_pep_print_float as usize)),
        ("_pep_live_allocs", black_box(_pep_live_allocs as usize)),
        ("_pep_utf8_length", black_box(_pep_utf8_length as usize)),
        ("_pep_swap_refs", black_box(_pep_swap_refs as usize)),
        ("_pep_utf8_size", black_box(_pep_utf8_size as usize)),
        ("_pep_utf8_compare", black_box(_pep_utf8_compare as usize)),
        ("_pep_utf8_find", black_box(_pep_utf8_find as usize)),
        ("_pep_utf8_char_offset", black_box(_pep_utf8_char_offset as usize)),
        ("_pep_hash_bytes", black_box(_pep_hash_bytes as usize)),
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
    fn utf8_find_locates_needle() {
        let hay = c_string("hello world");
        let needle = c_string("world");
        assert_eq!(
            _pep_utf8_find(hay.as_ptr() as *const u8, 11, needle.as_ptr() as *const u8, 5),
            6
        );
        let missing = c_string("mars");
        assert_eq!(
            _pep_utf8_find(hay.as_ptr() as *const u8, 11, missing.as_ptr() as *const u8, 4),
            -1
        );
        // Empty needle is found at 0.
        let empty = c_string("");
        assert_eq!(
            _pep_utf8_find(hay.as_ptr() as *const u8, 11, empty.as_ptr() as *const u8, 0),
            0
        );
        // Multi-byte needle: byte offset, not character offset.
        let uni_hay = c_string("héllo");
        let accented = c_string("é");
        assert_eq!(
            _pep_utf8_find(uni_hay.as_ptr() as *const u8, 6, accented.as_ptr() as *const u8, 2),
            1
        );
    }

    #[test]
    fn utf8_char_offset_counts_chars_not_bytes() {
        let hay = c_string("héllo");
        assert_eq!(_pep_utf8_char_offset(hay.as_ptr() as *const u8, 6, 0), 0);
        assert_eq!(_pep_utf8_char_offset(hay.as_ptr() as *const u8, 6, 1), 1);
        assert_eq!(_pep_utf8_char_offset(hay.as_ptr() as *const u8, 6, 2), 3);
        // Past the end clamps to size.
        assert_eq!(_pep_utf8_char_offset(hay.as_ptr() as *const u8, 6, 99), 6);
    }

    #[test]
    fn support_symbols_are_bindable() {
        let syms = support_symbols();
        assert!(syms.iter().all(|(name, addr)| !name.is_empty() && *addr != 0));
        // Codegen looks these up by name to bind them into the JIT; a missing
        // entry means generated code calls an unresolved address. codegen_print
        // picks one per argument type, so all three print variants must be here.
        for required in [
            "_pep_malloc",
            "_pep_free",
            "trace_ptr",
            "trace_int",
            "_pep_print",
            "_pep_print_int",
            "_pep_print_float",
            "_pep_utf8_find",
            "_pep_utf8_char_offset",
        ] {
            assert!(
                syms.iter().any(|(name, _)| *name == required),
                "{required} missing from support_symbols()"
            );
        }
    }
}
