#!/usr/bin/env python3
# Generates tools/compiler/sema/record_codec.pep: a binary writer and reader
# for every type the sema model's `Module` reaches, the AST nodes it holds
# included, so a checked module can be saved and loaded again (a checked
# unit's record). The model's types come from `crates/pepper-sema` through
# gen-sema-model.py; the AST's from tools/compiler/ast/ast.pep. Run it after
# changing either, then format the result:
#
#   python3 scripts/gen-sema-record.py tools/compiler/sema/record_codec.pep
#   target/release/pep-fmt -w tools/compiler/sema/record_codec.pep

import importlib.util, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('gen_sema_model', os.path.join(HERE, 'gen-sema-model.py'))
model = importlib.util.module_from_spec(spec)
saved = sys.argv
sys.argv = [saved[0]]
spec.loader.exec_module(model)
sys.argv = saved

# ---- The AST's types, read from ast.pep.

AST_PATH = os.path.join(HERE, '..', 'tools', 'compiler', 'ast', 'ast.pep')

def split_params(text):
    return model.split_top(text)

def read_ast(path):
    lines = open(path).read().split('\n')
    items = {}
    i = 0
    while i < len(lines):
        m = re.match(r'^export (struct|enum) (\w+)\s*\{', lines[i])
        if not m:
            i += 1
            continue
        kind, name = m.group(1), m.group(2)
        j = i + 1
        fields = []
        ctor = None
        variants = []
        while not lines[j].startswith('}'):
            line = lines[j]
            if kind == 'struct':
                fm = re.match(r'^    var (\w+): (.+?)(\s*=\s*.*)?;$', line)
                if fm:
                    fields.append((fm.group(1), fm.group(2).strip(), fm.group(3) is not None))
                cm = re.match(r'^    construct\((.*)\)\s*\{', line)
                if cm and ctor is None:
                    ctor = split_params(cm.group(1))
            else:
                vm = re.match(r'^    ([A-Z]\w*)(\((.*)\))?,?$', line)
                if vm:
                    params = []
                    if vm.group(3) is not None:
                        for part in split_params(vm.group(3)):
                            pn, pt = part.split(':', 1)
                            params.append((pn.strip(), pt.strip()))
                    variants.append((vm.group(1), params))
            j += 1
        items[name] = {'kind': kind, 'fields': fields, 'ctor': ctor or [], 'variants': variants}
        i = j + 1
    return items

AST = read_ast(AST_PATH)

PEP_PRIM = {'String', 'bool', 'ulong', 'uint', 'long', 'int', 'double', 'u8', 'ushort', 'short'}

def ast_type(t):
    """A Pepper type as written in ast.pep, as a type tree."""
    t = t.strip()
    if t.endswith('?'):
        return ('opt', ast_type(t[:-1]))
    if t.endswith('[]'):
        return ('vec', ast_type(t[:-2]))
    m = re.match(r'^(\w+)<(.*)>$', t)
    if m:
        args = [ast_type(a) for a in model.split_top(m.group(2))]
        if m.group(1) == 'Optional':
            return ('opt', args[0])
        if m.group(1) == 'Array':
            return ('vec', args[0])
        raise Exception('ast type ' + t)
    if t in PEP_PRIM:
        return ('prim', t)
    if t == 'Span':
        return ('span',)
    if t not in AST:
        raise Exception('unknown ast type ' + t)
    return ('ast', t)

RUST_PRIM = {'String': 'String', 'bool': 'bool', 'usize': 'ulong', 'u32': 'uint', 'u64': 'ulong', 'i64': 'long', 'i128': 'long', 'i32': 'int', 'f64': 'double', 'u8': 'u8'}

def rust_type(t):
    return rust_tree(model.parse_type(t))

def rust_tree(tp):
    n, args = tp
    if n == 'tuple':
        return ('tuple', [rust_tree(a) for a in args])
    if n == 'Box':
        return rust_tree(args[0])
    if n == 'Option':
        return ('opt', rust_tree(args[0]))
    if n == 'Vec':
        return ('vec', rust_tree(args[0]))
    if n == 'HashSet':
        return ('set', rust_tree(args[0]))
    if n == 'HashMap':
        return ('map', rust_tree(args[0]), rust_tree(args[1]), 'HashMap')
    if n == 'BTreeMap':
        return ('map', rust_tree(args[0]), rust_tree(args[1]), 'Map')
    if n in RUST_PRIM:
        return ('prim', RUST_PRIM[n])
    if n == 'Loc':
        return ('loc',)
    if n == 'ast::Span':
        return ('span',)
    if n == 'ast::LoopBreakKind':
        return ('model', 'LoopBreakKind')
    if n.startswith('ast::'):
        return ('ast', n[5:])
    return ('model', n)

def pep(tree):
    k = tree[0]
    if k == 'prim':
        return tree[1]
    if k == 'opt':
        return f'Optional<{pep(tree[1])}>'
    if k == 'vec':
        return f'Array<{pep(tree[1])}>'
    if k == 'set':
        return f'HashSet<{pep(tree[1])}>'
    if k == 'map':
        return f'{tree[3]}<{pep(tree[1])}, {pep(tree[2])}>'
    if k == 'tuple':
        return '(' + ', '.join(pep(a) for a in tree[1]) + ')'
    if k == 'loc':
        return 'Loc'
    if k == 'span':
        return 'ast.Span'
    if k == 'ast':
        return 'ast.' + tree[1]
    return tree[1]

def fn(tree):
    return ('_a_' if tree[0] == 'ast' else '_m_') + tree[1]

COUNT = [0]

def fresh(prefix):
    COUNT[0] += 1
    return f'{prefix}{COUNT[0]}'

def write(expr, tree):
    """Lines that write `expr` to `out`."""
    k = tree[0]
    if k == 'prim':
        t = tree[1]
        if t == 'String':
            return [f'out.text({expr});']
        if t == 'bool':
            return [f'out.flag({expr});']
        if t == 'double':
            return [f'out.number({expr});']
        if t in ('long', 'int', 'short'):
            return [f'out.signed({expr} as long);']
        if t == 'ulong':
            return [f'out.unsigned({expr});']
        return [f'out.unsigned({expr} as ulong);']
    if k == 'opt':
        inner = write(f'{expr}.value()', tree[1])
        return [f'if ({expr}.is_value()) {{', '    out.unsigned(1);'] + ['    ' + l for l in inner] + ['} else {', '    out.unsigned(0);', '}']
    if k in ('vec', 'set'):
        item = fresh('_item')
        inner = write(item, tree[1])
        return [f'out.unsigned({expr}.count);', f'for (var {item} in {expr}) {{'] + ['    ' + l for l in inner] + ['}']
    if k == 'map':
        key = fresh('_key')
        item = fresh('_item')
        inner = write(key, tree[1]) + write(item, tree[2])
        return [f'out.unsigned({expr}.count);', f'for (var ({key}, {item}) in {expr}) {{'] + ['    ' + l for l in inner] + ['}']
    if k == 'tuple':
        names = [fresh('_t') for _ in tree[1]]
        out = [f'var ({", ".join(names)}) = {expr};']
        for name, a in zip(names, tree[1]):
            out += write(name, a)
        return out
    if k == 'loc':
        return [f'out.loc({expr});']
    if k == 'span':
        return [f'out.unsigned({expr}.start);', f'out.unsigned({expr}.end);']
    return [f'{fn(tree)}_write(out, {expr});']

def read(tree):
    """(lines, expression) that read a value of `tree` from `input`."""
    k = tree[0]
    if k == 'prim':
        t = tree[1]
        if t == 'String':
            return [], 'input.text()'
        if t == 'bool':
            return [], 'input.flag()'
        if t == 'double':
            return [], 'input.number()'
        if t == 'long':
            return [], 'input.signed()'
        if t in ('int', 'short'):
            return [], f'input.signed() as {t}'
        if t == 'ulong':
            return [], 'input.unsigned()'
        return [], f'input.unsigned() as {t}'
    if k == 'opt':
        v = fresh('_o')
        lines, val = read(tree[1])
        t = pep(tree[1])
        return [f'var {v} = Optional<{t}>.Empty;', 'if (input.unsigned() == 1) {'] + ['    ' + l for l in lines] + [f'    {v} = Optional<{t}>.Value({val});', '}'], v
    if k in ('vec', 'set'):
        v = fresh('_v')
        n = fresh('_n')
        lines, val = read(tree[1])
        add = 'append' if k == 'vec' else 'insert'
        return [f'var {v} = {pep(tree)}();', f'var {n} = input.count();', f'for (var _ in 0..{n}) {{'] + ['    ' + l for l in lines] + [f'    {v}.{add}({val});', '}'], v
    if k == 'map':
        v = fresh('_v')
        n = fresh('_n')
        kl, kv = read(tree[1])
        key = fresh('_k')
        il, iv = read(tree[2])
        return [f'var {v} = {pep(tree)}();', f'var {n} = input.count();', f'for (var _ in 0..{n}) {{'] + ['    ' + l for l in kl] + [f'    var {key} = {kv};'] + ['    ' + l for l in il] + [f'    {v}[{key}] = {iv};', '}'], v
    if k == 'tuple':
        out = []
        vals = []
        for a in tree[1]:
            lines, val = read(a)
            name = fresh('_t')
            out += lines + [f'var {name} = {val};']
            vals.append(name)
        return out, '(' + ', '.join(vals) + ')'
    if k == 'loc':
        return [], 'input.loc()'
    if k == 'span':
        a = fresh('_s')
        return [f'var {a} = input.unsigned();'], f'ast.Span({a}, input.unsigned())'
    return [], f'{fn(tree)}_read(input)'

def default_of(rust_t):
    return model.default_of(model.parse_type(rust_t))

def model_struct(name, fields):
    live = [f for f in fields if not f['skip']]
    w = [f'{fn(("model", name))}_write(out: RecordOut, value: {name}) {{']
    for f in live:
        w += ['    ' + l for l in write(f'value.{model.fname(f["name"])}', rust_type(f['type']))]
    w.append('}')
    r = [f'{fn(("model", name))}_read(input: RecordIn): {name} {{']
    names = {}
    for f in live:
        lines, val = read(rust_type(f['type']))
        local = fresh('_f')
        r += ['    ' + l for l in lines] + [f'    var {local} = {val};']
        names[f['name']] = local
    # The generated constructor takes the fields without a default first.
    required = [f for f in live if default_of(f['type']) is None]
    optional = [f for f in live if default_of(f['type']) is not None]
    r.append(f'    return {name}({", ".join(names[f["name"]] for f in required + optional)});')
    r.append('}')
    return w + [''] + r

def variant_types(vv):
    if vv['kind'] == 'tuple':
        return [rust_type(t) for t in vv['types']]
    return []

def ast_struct(name, item):
    t = ('ast', name)
    w = [f'{fn(t)}_write(out: RecordOut, value: ast.{name}) {{']
    for fname, ftype, _ in item['fields']:
        w += ['    ' + l for l in write(f'value.{fname}', ast_type(ftype))]
    w.append('}')
    r = [f'{fn(t)}_read(input: RecordIn): ast.{name} {{']
    locals_ = {}
    for fname, ftype, _ in item['fields']:
        lines, val = read(ast_type(ftype))
        local = fresh('_f')
        r += ['    ' + l for l in lines] + [f'    var {local} = {val};']
        locals_[fname] = local
    args = []
    for param in item['ctor']:
        param = param.strip()
        if param.startswith('this.'):
            continue  # defaulted: the field is assigned below
        pn = param.split(':', 1)[0].strip()
        args.append(locals_[pn])
    r.append(f'    var value = ast.{name}({", ".join(args)});')
    for fname, _, _ in item['fields']:
        r.append(f'    value.{fname} = {locals_[fname]};')
    r += ['    return value;', '}']
    return w + [''] + r

def ast_enum(name, item):
    t = ('ast', name)
    w = [f'{fn(t)}_write(out: RecordOut, value: ast.{name}) {{', '    match (value) {']
    r = [f'{fn(t)}_read(input: RecordIn): ast.{name} {{', '    var tag = input.unsigned();']
    for i, (vname, params) in enumerate(item['variants']):
        if not params:
            w += [f'        {vname} => {{', f'            out.unsigned({i});', '        }']
            r += [f'    if (tag == {i}) {{', f'        return ast.{name}.{vname};', '    }']
            continue
        ns = [f'p{j}' for j in range(len(params))]
        w += [f'        {vname}({", ".join(ns)}) => {{', f'            out.unsigned({i});']
        r += [f'    if (tag == {i}) {{']
        vals = []
        for nn, (_, pt) in zip(ns, params):
            tt = ast_type(pt)
            w += ['            ' + l for l in write(nn, tt)]
            lines, val = read(tt)
            local = fresh('_f')
            r += ['        ' + l for l in lines] + [f'        var {local} = {val};']
            vals.append(local)
        w.append('        }')
        r += [f'        return ast.{name}.{vname}({", ".join(vals)});', '    }']
    w += ['    }', '}']
    r += [f'    input.fail("{name}", tag);']
    # Unreachable: `fail` stops the read. A value of the first variant
    # keeps the function's return well-formed.
    vname, params = item['variants'][0]
    if params:
        r.append(f'    return {fn(t)}_read(input);')
    else:
        r.append(f'    return ast.{name}.{vname};')
    r.append('}')
    return w + [''] + r

def model_enum_fallback(name, variants):
    vv = variants[0]
    if vv['kind'] == 'unit':
        return f'return {name}.{vv["name"]};'
    return f'return {fn(("model", name))}_read(input);'

# Which types are reached, from Module.
blocks = []
seen = set()
stack = [('model', 'Module')]

def reach(tree):
    k = tree[0]
    if k in ('opt', 'vec', 'set'):
        reach(tree[1])
    elif k == 'map':
        reach(tree[1])
        reach(tree[2])
    elif k == 'tuple':
        for a in tree[1]:
            reach(a)
    elif k in ('model', 'ast'):
        stack.append(tree)

while stack:
    t = stack.pop()
    if t in seen:
        continue
    seen.add(t)
    kind, name = t
    if kind == 'model':
        it = model.items[name]
        if it['kind'] == 'struct':
            for f in it['fields']:
                if not f['skip']:
                    reach(rust_type(f['type']))
            blocks.append(model_struct(name, it['fields']))
        elif it['kind'] == 'enum':
            for vv in it['variants']:
                if vv['kind'] == 'tuple':
                    for tt in variant_types(vv):
                        reach(tt)
                elif vv['kind'] == 'struct':
                    for f in vv['fields']:
                        if not f['skip']:
                            reach(rust_type(f['type']))
            blocks.append(('enum', name, it['variants']))
        else:
            raise Exception('model type ' + name + ' ' + it['kind'])
    else:
        it = AST[name]
        if it['kind'] == 'struct':
            for fname, ftype, _ in it['fields']:
                reach(ast_type(ftype))
            blocks.append(ast_struct(name, it))
        else:
            for _, params in it['variants']:
                for _, pt in params:
                    reach(ast_type(pt))
            blocks.append(ast_enum(name, it))

out_blocks = []
for b in blocks:
    if isinstance(b, tuple) and b[0] == 'enum':
        _, name, variants = b
        t = ('model', name)
        w = [f'{fn(t)}_write(out: RecordOut, value: {name}) {{', '    match (value) {']
        r = [f'{fn(t)}_read(input: RecordIn): {name} {{', '    var tag = input.unsigned();']
        for i, vv in enumerate(variants):
            if vv['kind'] == 'unit':
                w += [f'        {vv["name"]} => {{', f'            out.unsigned({i});', '        }']
                r += [f'    if (tag == {i}) {{', f'        return {name}.{vv["name"]};', '    }']
            elif vv['kind'] == 'tuple':
                ns = ['v'] if len(vv['types']) == 1 else [f'v{j}' for j in range(len(vv['types']))]
                w += [f'        {vv["name"]}({", ".join(ns)}) => {{', f'            out.unsigned({i});']
                r += [f'    if (tag == {i}) {{']
                vals = []
                for nn, tt in zip(ns, variant_types(vv)):
                    w += ['            ' + l for l in write(nn, tt)]
                    ls, val = read(tt)
                    local = fresh('_f')
                    r += ['        ' + l for l in ls] + [f'        var {local} = {val};']
                    vals.append(local)
                w.append('        }')
                r += [f'        return {name}.{vv["name"]}({", ".join(vals)});', '    }']
            else:
                sname = vv['name'] + name
                w += [f'        {vv["name"]}(node) => {{', f'            out.unsigned({i});', f'            {fn(("model", sname))}_write(out, node);', '        }']
                r += [f'    if (tag == {i}) {{', f'        return {name}.{vv["name"]}({fn(("model", sname))}_read(input));', '    }']
                fields = vv['fields']
                out_blocks.append(model_struct(sname, fields))
        w += ['    }', '}']
        r += [f'    input.fail("{name}", tag);', '    ' + model_enum_fallback(name, variants), '}']
        out_blocks.append(w + [''] + r)
    else:
        out_blocks.append(b)

header = '''## Saving and loading a checked module: a binary writer and reader for
## every type `Module` reaches, the AST nodes it holds included. Generated
## by `scripts/gen-sema-record.py`; do not edit.

import compiler.ast;
import [Loc] from "loc";
import [RecordIn, RecordOut] from "record";

## Writes `module` to `out`.
##
## @param out the record
## @param module the module
export write_module(out: RecordOut, module: Module) {
    _m_Module_write(out, module);
}

## Reads a module from `input`, as `write_module` wrote it.
##
## @param input the record
## @returns the module
export read_module(input: RecordIn): Module {
    return _m_Module_read(input);
}

## Writes a type alias to `out`.
##
## @param out the record
## @param alias the alias
export write_type_alias(out: RecordOut, alias: TypeAliasDef) {
    _m_TypeAliasDef_write(out, alias);
}

## Reads a type alias from `input`, as `write_type_alias` wrote it.
##
## @param input the record
## @returns the alias
export read_type_alias(input: RecordIn): TypeAliasDef {
    return _m_TypeAliasDef_read(input);
}

'''
text = header + '\n\n'.join('\n'.join(b) for b in out_blocks) + '\n'
open(sys.argv[1], 'w').write(text)
print(len(out_blocks), 'blocks', file=sys.stderr)
