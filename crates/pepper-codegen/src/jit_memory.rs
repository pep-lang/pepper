//! The JIT's memory on Windows: every section of a module in one reserved
//! region, code first, then read-only data, then read-write data.
//!
//! MCJIT resolves `IMAGE_REL_AMD64_ADDR32NB` relocations (the `.pdata`
//! unwind entries that point into `.text` and `.xdata`) as 32-bit offsets
//! from a fake `__ImageBase`: the lowest section address. A target below it,
//! or more than 4 GB above it, aborts the process ("IMAGE_REL_AMD64_ADDR32NB
//! relocation requires an ordered section layout"). LLVM's default memory
//! manager allocates each section on its own, so under load the sections can
//! land far apart. One reservation, in this order, keeps every section within
//! `ARENA_SIZE * 3` of the code.

use inkwell::memory_manager::McjitMemoryManager;

/// Address space for each kind of section. Reserving is free; pages are
/// committed as sections are allocated.
const ARENA_SIZE: usize = 256 << 20;

/// Committed in steps of this many bytes (the allocation granularity).
const COMMIT_STEP: usize = 64 << 10;

const PAGE: usize = 4096;

const MEM_COMMIT: u32 = 0x1000;
const MEM_RESERVE: u32 = 0x2000;
const MEM_RELEASE: u32 = 0x8000;
const PAGE_NOACCESS: u32 = 0x01;
const PAGE_READONLY: u32 = 0x02;
const PAGE_READWRITE: u32 = 0x04;
const PAGE_EXECUTE_READ: u32 = 0x20;

#[link(name = "kernel32")]
unsafe extern "system" {
    fn VirtualAlloc(address: *mut u8, size: usize, allocation_type: u32, protect: u32) -> *mut u8;
    fn VirtualFree(address: *mut u8, size: usize, free_type: u32) -> i32;
    fn VirtualProtect(address: *mut u8, size: usize, protect: u32, old_protect: *mut u32) -> i32;
    fn FlushInstructionCache(process: isize, address: *const u8, size: usize) -> i32;
    fn GetCurrentProcess() -> isize;
}

/// One kind of section's part of the region: allocated from `start` up,
/// committed up to `committed`, and given its final protection up to
/// `finalized`.
#[derive(Debug)]
struct Arena {
    start: usize,
    next: usize,
    committed: usize,
    finalized: usize,
    /// The protection `finalize_memory` gives its sections.
    protect: u32,
}

impl Arena {
    fn new(start: usize, protect: u32) -> Self {
        Arena { start, next: start, committed: start, finalized: start, protect }
    }

    fn allocate(&mut self, size: usize, alignment: usize) -> *mut u8 {
        let at = self.next.next_multiple_of(alignment.max(1));
        let end = at + size;
        if end > self.start + ARENA_SIZE {
            return std::ptr::null_mut();
        }
        if end > self.committed {
            let to = end.next_multiple_of(COMMIT_STEP).min(self.start + ARENA_SIZE);
            let committed = unsafe { VirtualAlloc(self.committed as *mut u8, to - self.committed, MEM_COMMIT, PAGE_READWRITE) };
            if committed.is_null() {
                return std::ptr::null_mut();
            }
            self.committed = to;
        }
        self.next = end;
        at as *mut u8
    }

    /// Give the sections allocated since the last call their protection.
    /// Later sections start on the next page, which stays writable.
    fn finalize(&mut self) -> Result<(), String> {
        let end = self.next.next_multiple_of(PAGE);
        if end > self.finalized {
            let (at, size) = (self.finalized as *mut u8, end - self.finalized);
            let mut old = 0;
            if unsafe { VirtualProtect(at, size, self.protect, &mut old) } == 0 {
                return Err(format!("cannot protect JIT memory: error {}", std::io::Error::last_os_error()));
            }
            if self.protect == PAGE_EXECUTE_READ {
                unsafe { FlushInstructionCache(GetCurrentProcess(), at, size) };
            }
        }
        self.finalized = end;
        self.next = end;
        Ok(())
    }
}

/// A module's sections, in one reserved region (see the module docs).
#[derive(Debug)]
pub struct JitMemory {
    base: *mut u8,
    code: Arena,
    read_only: Arena,
    read_write: Arena,
}

impl JitMemory {
    pub fn new() -> Result<Self, String> {
        let base = unsafe { VirtualAlloc(std::ptr::null_mut(), ARENA_SIZE * 3, MEM_RESERVE, PAGE_NOACCESS) };
        if base.is_null() {
            return Err(format!("cannot reserve JIT memory: {}", std::io::Error::last_os_error()));
        }
        let start = base as usize;
        Ok(JitMemory {
            base,
            code: Arena::new(start, PAGE_EXECUTE_READ),
            read_only: Arena::new(start + ARENA_SIZE, PAGE_READONLY),
            read_write: Arena::new(start + 2 * ARENA_SIZE, PAGE_READWRITE),
        })
    }
}

impl McjitMemoryManager for JitMemory {
    fn allocate_code_section(&mut self, size: usize, alignment: u32, _section_id: u32, _section_name: &str) -> *mut u8 {
        self.code.allocate(size, alignment as usize)
    }

    fn allocate_data_section(&mut self, size: usize, alignment: u32, _section_id: u32, _section_name: &str, is_read_only: bool) -> *mut u8 {
        let arena = if is_read_only { &mut self.read_only } else { &mut self.read_write };
        arena.allocate(size, alignment as usize)
    }

    fn finalize_memory(&mut self) -> Result<(), String> {
        self.code.finalize()?;
        self.read_only.finalize()?;
        self.read_write.finalize()
    }

    fn destroy(&mut self) {
        if !self.base.is_null() {
            unsafe { VirtualFree(self.base, 0, MEM_RELEASE) };
            self.base = std::ptr::null_mut();
        }
    }
}

impl Drop for JitMemory {
    fn drop(&mut self) {
        self.destroy();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sections_are_ordered_code_read_only_read_write_within_range() {
        let mut memory = JitMemory::new().unwrap();
        let code = memory.allocate_code_section(100, 16, 1, ".text") as usize;
        let read_write = memory.allocate_data_section(100, 8, 2, ".data", false) as usize;
        let read_only = memory.allocate_data_section(100, 8, 3, ".rdata", true) as usize;
        let pdata = memory.allocate_data_section(100, 4, 4, ".pdata", true) as usize;
        assert!(code != 0 && read_only != 0 && read_write != 0 && pdata != 0);
        assert!(code < read_only && read_only < read_write && read_only < pdata);
        // What an ADDR32NB relocation needs: every target within 4 GB above
        // the lowest section.
        assert!(read_write + 100 - code <= u32::MAX as usize);
        assert_eq!(code % 16, 0);
    }

    #[test]
    #[cfg(target_arch = "x86_64")]
    fn finalized_code_runs_and_later_sections_stay_writable() {
        let mut memory = JitMemory::new().unwrap();
        // mov eax, 42; ret
        let bytes = [0xB8, 42, 0, 0, 0, 0xC3];
        let code = memory.allocate_code_section(bytes.len(), 16, 1, ".text");
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), code, bytes.len()) };
        memory.finalize_memory().unwrap();
        let f: extern "C" fn() -> i32 = unsafe { std::mem::transmute(code) };
        assert_eq!(f(), 42);
        // A second module's sections, after the first is finalized.
        let data = memory.allocate_data_section(8, 8, 2, ".data", false);
        unsafe { data.write(7) };
        let more = memory.allocate_code_section(bytes.len(), 16, 3, ".text");
        assert!(more as usize >= code as usize + PAGE);
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), more, bytes.len()) };
        memory.finalize_memory().unwrap();
        let g: extern "C" fn() -> i32 = unsafe { std::mem::transmute(more) };
        assert_eq!(g(), 42);
    }

    #[test]
    fn an_arena_that_is_full_fails_the_allocation() {
        let mut memory = JitMemory::new().unwrap();
        assert!(memory.allocate_code_section(ARENA_SIZE + 1, 16, 1, ".text").is_null());
        assert!(!memory.allocate_code_section(16, 16, 1, ".text").is_null());
    }
}
