//! Build cache keys with early cutoff (phase 2c; see INTERNALS.md §4.3).
//!
//! A unit's key hashes its own files' text, and each of its other inputs
//! (`Program::unit_inputs`) by that file's **interface hash**
//! (`pepper_sema::interface`) rather than its text, so editing a body
//! rebuilds only the edited file's unit. An input in a unit that depends
//! back on this one (an import cycle through the prelude, a file declaring
//! an override that the prelude instantiates) is hashed by its text instead:
//! its interface can depend on this unit, so it cannot be known first.
//!
//! Before sema, a unit's key is known once every other unit it reads through
//! interfaces is a cache hit, whose record holds its files' interface
//! hashes: units resolve bottom-up. After sema every file's interface hash
//! is known (recorded for the units whose bodies sema skipped, computed for
//! the rest), so every key is.

use pepper_sema::program::{Program, Unit};

/// How each unit's key reads its inputs.
pub struct Keys<'p> {
    program: &'p Program,
    pub units: Vec<Unit>,
    /// Per unit, its inputs (`Program::unit_inputs`).
    pub inputs: Vec<Vec<usize>>,
    /// Per file, its unit.
    pub unit_of_file: Vec<usize>,
    /// Per unit, its strongly connected component in the graph of units
    /// reading each other's files: inputs in the same one are hashed by
    /// text.
    component: Vec<usize>,
    source_hashes: Vec<blake3::Hash>,
}

impl<'p> Keys<'p> {
    pub fn new(program: &'p Program) -> Self {
        let units = program.units();
        let mut unit_of_file = vec![0; program.files.len()];
        for (index, unit) in units.iter().enumerate() {
            for &file in &unit.files {
                unit_of_file[file] = index;
            }
        }
        let inputs: Vec<Vec<usize>> = units.iter().map(|u| program.unit_inputs(u)).collect();
        // Which units each unit reaches through its inputs (a handful of
        // units: a plain closure is enough).
        let n = units.len();
        let mut reaches = vec![vec![false; n]; n];
        for (u, files) in inputs.iter().enumerate() {
            reaches[u][u] = true;
            for &file in files {
                reaches[u][unit_of_file[file]] = true;
            }
        }
        for k in 0..n {
            for i in 0..n {
                if reaches[i][k] {
                    for j in 0..n {
                        reaches[i][j] |= reaches[k][j];
                    }
                }
            }
        }
        let component = (0..n).map(|u| (0..n).find(|&v| reaches[u][v] && reaches[v][u]).unwrap_or(u)).collect();
        let source_hashes = program.files.iter().map(|f| blake3::hash(f.source.as_bytes())).collect();
        Keys { program, units, inputs, unit_of_file, component, source_hashes }
    }

    /// Whether `unit`'s key reads `file` by its interface hash.
    pub fn reads_interface(&self, unit: usize, file: usize) -> bool {
        self.component[self.unit_of_file[file]] != self.component[unit]
    }

    /// The key of unit `unit` (a hash of the compiler, the unit's files and
    /// its inputs), given the interface hashes known so far; `None` while
    /// one it reads is unknown.
    pub fn key<'a>(&self, compiler: &str, unit: usize, interface: impl Fn(usize) -> Option<&'a str>) -> Option<String> {
        let program = self.program;
        let mut hasher = blake3::Hasher::new();
        let mut field = |bytes: &[u8]| {
            hasher.update(&(bytes.len() as u64).to_le_bytes());
            hasher.update(bytes);
        };
        field(b"pepper unit key 2");
        field(compiler.as_bytes());
        field(self.units[unit].name.as_bytes());
        for &file in &self.units[unit].files {
            field(program.files[file].name.as_bytes());
        }
        for &file in &self.inputs[unit] {
            let f = &program.files[file];
            field(f.name.as_bytes());
            field(f.namespace.as_bytes());
            field(&[f.prelude as u8, f.prelude_part as u8]);
            if self.reads_interface(unit, file) {
                field(b"interface");
                field(interface(file)?.as_bytes());
            } else {
                field(b"source");
                field(self.source_hashes[file].as_bytes());
            }
        }
        Some(hasher.finalize().to_hex().to_string())
    }
}
