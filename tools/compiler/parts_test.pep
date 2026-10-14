# The parts of a program's code compiled into objects (`driver/parts.pep`).

import compiler.codegen;
import compiler.driver;
import compiler.incremental;
import [Directory, File, Path] from io;
import compiler.link;
import llvm;
import [TempFolder] from testing;

# A module defining `value`, which returns `n`.
_module(context: llvm.Context, n: ulong): llvm.Module {
    var module = llvm.Module(context, "part");
    var i32 = context.int32_type();
    var function = module.add_function("value", llvm.Type.function(i32, Array<llvm.Type>()));
    var builder = llvm.Builder(context);
    builder.position_at_end(context.append_block(function, "entry"));
    builder.return_value(i32.const_int(n));
    return module;
}

# Compiles `_module(n)` as part 0 into `object`, its objects cached in
# `cache` under `part`.
_compile(cache: incremental.Cache, object: Path, n: ulong) {
    codegen.initialize_backends();
    var triple = codegen.target_triple(link.Target());
    var cpu = codegen.Cpu.default_for(triple);
    var machine = llvm.TargetMachine.create(triple, cpu.name, cpu.features, llvm.OptLevel.O0);
    expect_true(machine.is_ok());
    var context = llvm.Context();
    var ir = _module(context, n);
    var part_of = HashMap<String, uint>();
    part_of["value"] = 0;
    var compiled = driver.compile_parts(
        ir,
        codegen.Partition(part_of),
        [driver.PartJob(0, object)],
        machine.value(),
        cpu,
        0,
        object.parent().value(),
        false,
        true,
        false,
        false,
        false,
        Optional<driver.PartCache>.Value(driver.PartCache(cache, "part"))
    );
    expect_true(compiled.is_ok());
}

# A part whose code is the same as one compiled before copies the object
# the cache keeps; a part whose code changed is compiled.
[Test]
reuses_the_object_of_a_part_whose_code_is_the_same() {
    var folder = TempFolder("part_cache");
    var cache = incremental.Cache(folder.path.join(Path("cache")));
    var object = folder.path.join(Path("value.o"));
    _compile(cache, object, 7);
    var keys = Directory.open(cache.dir.join(Path("units")).join(Path("part#0")));
    expect_true(keys.is_ok());
    var listed = keys.value().entries();
    expect_true(listed.is_ok() and listed.value().count == 1);
    var kept = cache.dir.join(Path("units")).join(Path("part#0")).join(Path(listed.value()[0].name));
    # Stands in for the object, to tell a copy from a compile.
    expect_true(File.write_text(kept.join(Path("object")), "kept").is_ok());

    _compile(cache, object, 7);
    expect_equal(File.read_to_string(object).value(), "kept");
    _compile(cache, object, 8);
    var compiled = File.read_to_string(object);
    expect_true(compiled.is_err() or compiled.value() != "kept");
}
