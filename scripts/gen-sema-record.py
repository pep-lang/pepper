#!/usr/bin/env python3
# Generates tools/compiler/sema/record_codec.pep: a binary writer and reader
# for every type the sema model's `Module` reaches, the AST nodes it holds
# included, so a checked module can be saved and loaded again (a checked
# unit's record). The model's types come from tools/compiler/sema/model.pep
# through gen-sema-model.py; the AST's from tools/compiler/ast/ast.pep. Run
# it after changing either, then format the result:
#
#   python3 scripts/gen-sema-record.py tools/compiler/sema/record_codec.pep
#   pep-fmt -w tools/compiler/sema/record_codec.pep

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

def write_to(o, expr, tree):
    """Lines that write `expr` to the record `o`."""
    return [l.replace('out.', f'{o}.').replace('(out,', f'({o},') for l in write(expr, tree)]

def write(expr, tree):
    """Lines that write `expr` to `out`."""
    k = tree[0]
    if k in ('set', 'map'):
        # In the order of their keys' records, so a set or map writes the
        # same bytes whatever order its slots hold its entries in.
        key = fresh('_key')
        keys = fresh('_keys')
        sk = fresh('_scratch')
        bk = fresh('_bytes')
        kt = pep(tree[1])
        loop = f'for (var {key} in {expr}) {{' if k == 'set' else f'for (var ({key}, _) in {expr}) {{'
        sv = fresh('_vscratch')
        lines = [f'var {keys} = Array<(u8[], u8[], {kt})>();', loop,
                 f'    var {sk} = out.scratch();']
        lines += ['    ' + l for l in write_to(sk, key, tree[1])]
        # Entries whose keys write the same (locations left out of an
        # interface) go in the order of their values.
        lines += [f'    var {sv} = out.scratch();']
        if k == 'map':
            lines += ['    ' + l for l in write_to(sv, f'{expr}[{key}]', tree[2])]
        lines += [f'    {keys}.append(({sk}.finish(), {sv}.finish(), {key}));', '}',
                  f'{keys}.sort((a, b) => {{', '    var (x, xv, _) = a;', '    var (y, yv, _) = b;',
                  '    var by_key = compare_bytes(x, y);', '    return by_key != 0 ? by_key : compare_bytes(xv, yv);', '});',
                  f'out.unsigned({keys}.count);',
                  f'for (var ({bk}, _, {key}) in {keys}) {{']
        inner = write(key, tree[1])
        if k == 'map':
            inner = inner + write(f'{expr}[{key}]', tree[2])
        lines += ['    ' + l for l in inner] + ['}']
        return lines
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
        return [f'out.unsigned(out.blank_locs ? 0 : {expr}.start);', f'out.unsigned(out.blank_locs ? 0 : {expr}.end);']
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

# A read of the module's own structs or functions, lazily.
def _lazy(line):
    return line.replace('_m_StructDef_read(input)', '_m_StructDef_read_lazy(input)').replace('_m_FunctionDef_read(input)', '_m_FunctionDef_read_lazy(input)')

def model_struct(name, fields):
    live = [f for f in fields if not f['skip']]
    w = [f'{fn(("model", name))}_write(out: RecordOut, value: {name}) {{']
    for f in live:
        lines = write(f'value.{model.fname(f["name"])}', rust_type(f['type']))
        if name == 'FunctionDef' and f['name'] == 'body':
            # An interface leaves out the bodies of functions that are not
            # generic: they are not what other units check against. A body
            # is written behind its size, so a reader can skip it
            # (`RecordIn.lazy_bodies`); one skipped is decoded to be written.
            lines = ['if (out.blank_bodies and !value.is_generic_func and value.generic_params.count == 0) {',
                     '    out.unsigned(0);',
                     '} else if (out.pending_as_bytes and value.body_origin.is_value()) {',
                     '    # Hashed for a delta or an own interface: a body read from',
                     '    # a record is as the record wrote it, decoded or not.',
                     '    out.unsigned(2);',
                     '    out.pending(value.body_origin.value());',
                     '} else {',
                     '    var _body = value.body;',
                     '    if (value.pending_body.is_value()) {',
                     '        _body = Optional<Block>.Value(decode_body(value.pending_body.value()));',
                     '    }',
                     '    if (_body.is_value()) {',
                     '        out.unsigned(1);',
                     '        var _mark = out.size_mark();',
                     '        _m_Block_write(out, _body.value());',
                     '        out.size_fill(_mark);',
                     '    } else {',
                     '        out.unsigned(0);',
                     '    }',
                     '}']
        elif (name == 'Module' and f['name'] == 'recorded_summaries') or (name == 'Checked' and f['name'] == 'summaries'):
            # A summary names where its error would point: no part of an
            # interface.
            helper = 'write_interface_summaries' if name == 'Module' else 'write_interface_checked_summaries'
            lines = ['if (out.blank_locs) {', f'    {helper}(out, value.{model.fname(f["name"])});', '} else {'] + ['    ' + l for l in lines] + ['}']
        elif name == 'Module' and f['name'] in ('literal_args', 'call_targets', 'argument_names', 'stripped', 'summaries_to_record', 'cached_files'):
            # What the bodies hold is no part of an interface.
            lines = ['if (out.blank_bodies) {', '    out.unsigned(0);', '} else {'] + ['    ' + l for l in lines] + ['}']
        elif name == 'Module' and f['name'] == 'templates':
            # Generic bodies are, though: other units specialize them.
            lines = ['var _blank = out.blank_bodies;', 'out.blank_bodies = false;'] + lines + ['out.blank_bodies = _blank;']
        w += ['    ' + l for l in lines]
    w.append('}')
    # A checked function's body, and a checked struct's members' bodies,
    # can be read lazily: the stash (`stash_bodies`) holds them, which
    # decodes one when asked. Elsewhere a body is read whole.
    lazy_capable = name in ('FunctionDef', 'StructDef')
    if lazy_capable:
        r = [f'{fn(("model", name))}_read(input: RecordIn): {name} {{',
             f'    return {fn(("model", name))}_read_with(input, false);',
             '}',
             '',
             f'{fn(("model", name))}_read_lazy(input: RecordIn): {name} {{',
             f'    return {fn(("model", name))}_read_with(input, input.lazy_bodies);',
             '}',
             '',
             f'{fn(("model", name))}_read_with(input: RecordIn, lazy: bool): {name} {{']
    else:
        r = [f'{fn(("model", name))}_read(input: RecordIn): {name} {{']
    names = {}
    for f in live:
        if name == 'FunctionDef' and f['name'] == 'body':
            local = fresh('_f')
            r += ['    var _pending = Optional<PendingBody>.Empty;',
                  f'    var {local} = Optional<Block>.Empty;',
                  '    if (input.unsigned() == 1) {',
                  '        var _size = input.size();',
                  '        if (lazy) {',
                  '            # Present, as an empty block, until decoded.',
                  '            _pending = Optional<PendingBody>.Value(input.skip(_size));',
                  f'            {local} = Optional<Block>.Value(Block());',
                  '        } else {',
                  f'            {local} = Optional<Block>.Value(_m_Block_read(input));',
                  '        }',
                  '    }']
            names[f['name']] = local
            continue
        lines, val = read(rust_type(f['type']))
        if name == 'StructDef' and f['name'] in ('method_members', 'constructors', 'destructor', 'acquire', 'release'):
            lines = [l.replace('_m_FunctionDef_read(input)', '_m_FunctionDef_read_with(input, lazy)') for l in lines]
            val = val.replace('_m_FunctionDef_read(input)', '_m_FunctionDef_read_with(input, lazy)')
        if name == 'Module' and f['name'] in ('structs', 'functions'):
            lines = [_lazy(l) for l in lines]
            val = _lazy(val)
        local = fresh('_f')
        r += ['    ' + l for l in lines] + [f'    var {local} = {val};']
        names[f['name']] = local
    # The generated constructor takes the fields without a default first.
    required = [f for f in live if default_of(f['type']) is None]
    optional = [f for f in live if default_of(f['type']) is not None]
    made = f'{name}({", ".join(names[f["name"]] for f in required + optional)})'
    if name == 'FunctionDef':
        # A generic function's body is decoded now: specializing it reads
        # it on any compilation unit.
        r += [f'    var _function = {made};',
              '    if (_pending.is_value()) {',
              '        if (_function.is_generic_func or _function.generic_params.count > 0) {',
              '            _function.body = Optional<Block>.Value(decode_body(_pending.value()));',
              '        } else {',
              '            _function.pending_body = _pending;',
              '            _function.body_origin = _pending;',
              '        }',
              '    }',
              '    return _function;']
    else:
        r.append(f'    return {made};')
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

# Module's delta writer, reader and base indexer. Each element of a list
# field of a model or AST type is written as a reference to an element of
# the base module whose own record is the same (an odd tag: twice its place
# plus one), or in full (tag 0). A struct, in `structs` or the templates,
# that the base declares under its name but that changed is written as a
# patch on it (tag 2): its member lists element by element the same way.

# The fields an interface leaves out (`module_interface_fields`): what the
# passes record for codegen and the build, not declarations. A compilation unit
# that reads another is checked against its declarations alone, so these stay
# out of its own interface too, and an edit that changes only them keeps the
# keys of the compilation units that read it (early cutoff). A field that can
# change what a reader checks or generates must not be listed here.
NOT_INTERFACE = ('literal_args', 'call_targets', 'argument_names', 'stripped', 'summaries_to_record', 'cached_files')
# The fields an own interface leaves out besides: the link summaries of the
# bodies the build cache skipped, which only that build's codegen reads.
NOT_OWN = NOT_INTERFACE + ('recorded_summaries',)

def own_lines(label, expr, tree, blank_bodies='true'):
    """Lines that add `expr`, of type `tree`, to the compilation unit's own interface
    (`DeltaBase.own`): its interface hash, under `label`."""
    o = fresh('_own')
    return (['{', f'    var {o} = RecordOut();', f'    {o}.blank_bodies = {blank_bodies};', f'    {o}.blank_locs = true;',
             f'    {o}.pending_as_bytes = true;']
            + ['    ' + l for l in write_to(o, expr, tree)]
            + [_own_call(label, expr, f'interface_text({o})'), '}'])

def _own_call(label, element, hash_expr):
    """The call adding `element`'s entry to the own interface: a function
    only its module sees goes under its name (`DeltaBase.own_function`)."""
    if label == 'functions':
        return f'    base.own_function("{label}", {element}, {hash_expr});'
    if label in ('private_functions', 'file_private_functions'):
        return f'    base.own_at("{label}", {element}, {hash_expr});'
    return f'    base.own("{label}", {hash_expr});'

def _list_delta(expr, et, key, base_list, category=None, merge=False, named=False, own=None, own_bodies='true', ref=None):
    """Write, read and index lines for list `expr` of element type `et`,
    whose elements are referred to by `key` (a Pepper string expression)
    in the base's list `base_list`. `category` names the list in the
    stats of base elements a delta does not refer to. With `merge`, a
    list that holds the base's elements in order is written as its other
    elements and their places (mode 2), which reading puts back among the
    base's: no reference into the base but its order. With `named`, a base
    element the compilation unit changed is written with its name, which merging
    finds it by. With `ref`, the base's elements themselves (a Pepper
    expression), a merged list finds the base's by identity, not hash, and
    the index keeps no hashes of them unless `base.verifying`."""
    item = fresh('_item')
    ch = fresh('_changed'); sn = fresh('_seqn'); nc = fresh('_nc')
    hits = fresh('_hits')
    w = []
    if merge and ref:
        seq = fresh('_seq'); bj = fresh('_bj'); news = fresh('_news'); i = fresh('_i')
        w += [f'var {seq} = {ref};',
              f'ulong {bj} = 0;',
              f'var {news} = Array<ulong>();']
        if named:
            w += [f'var {ch} = Array<(ulong, ulong)>();']
        w += [f'for (var {i} in 0..{expr}.count) {{',
              f'    if ({bj} < {seq}.count and {expr}[{i}] === {seq}[{bj}]) {{',
              '        if (base.verifying) {',
              '            var scratch = base.scratch();',
              f'            {fn(et)}_write(scratch, {expr}[{i}]);',
              f'            base.verify_same({key}, {bj}, scratch);',
              '        }',
              f'        {bj} += 1;',
              f'    }} else if ({bj} < {seq}.count and _same{fn(et)}({expr}[{i}], {seq}[{bj}], base)) {{',
              '        if (base.verifying) {',
              '            var scratch = base.scratch();',
              f'            {fn(et)}_write(scratch, {expr}[{i}]);',
              f'            base.verify_same({key}, {bj}, scratch);',
              '        }',
              f'        {bj} += 1;']
        SAME_TYPES.add(et)
        if named:
            w += [f'    }} else if ({bj} < {seq}.count and {expr}[{i}].name == {seq}[{bj}].name) {{',
                  f'        {ch}.append(({i}, {bj}));',
                  f'        {bj} += 1;']
        w += ['    } else {',
              f'        {news}.append({i});',
              '    }',
              '}']
    elif merge:
        hs = fresh('_hs'); seq = fresh('_seq'); bj = fresh('_bj'); news = fresh('_news'); i = fresh('_i')
        w += [f'var {hs} = Array<String>();',
              f'for (var {item} in {expr}) {{',
              '    var scratch = base.scratch();',
              f'    {fn(et)}_write(scratch, {item});',
              f'    {hs}.append(base.hash_of(scratch));',
              '}',
              f'var {seq} = base.sequence({key});',
              f'ulong {bj} = 0;',
              f'var {news} = Array<ulong>();']
        if named:
            w += [f'var {ch} = Array<(ulong, ulong)>();', f'var {sn} = base.sequence({key} + "#");']
        w += [f'for (var {i} in 0..{hs}.count) {{',
              f'    if ({bj} < {seq}.count and {hs}[{i}] == {seq}[{bj}]) {{',
              f'        {bj} += 1;']
        if named:
            w += [f'    }} else if ({bj} < {sn}.count and {expr}[{i}].name == {sn}[{bj}]) {{',
                  f'        {ch}.append(({i}, {bj}));',
                  f'        {bj} += 1;']
        w += ['    } else {',
              f'        {news}.append({i});',
              '    }',
              '}']
    if merge:
        w += [f'if ({bj} == {seq}.count) {{',
              '    out.unsigned(2);']
        if named:
            w += [f'    out.unsigned({ch}.count);',
                  f'    for (var ({i}, _b) in {ch}) {{',
                  f'        out.text({expr}[{i}].name);',
                  '        out.unsigned(_b);',
                  f'        {fn(et)}_write(out, {expr}[{i}]);']
            if own:
                w += ['        ' + l for l in own_lines(own, f'{expr}[{i}]', et, own_bodies)]
            w += ['    }',
                  f'    base.count({category or key} + " changed", {ch}.count);']
        w += [
              f'    out.unsigned({news}.count);',
              f'    for (var {i} in {news}) {{',
              f'        out.unsigned({i});',
              f'        {fn(et)}_write(out, {expr}[{i}]);']
        if own:
            w += ['        ' + l for l in own_lines(own, f'{expr}[{i}]', et, own_bodies)]
        w += ['    }',
              f'    base.count({category or key} + " merged", 0);',
              '} else {',
              '    # Not the base\'s elements in order: whole, which reading takes',
              '    # in place of the base\'s, whatever the base.',
              '    out.unsigned(3);',
              f'    base.count({category or key} + " whole", 0);',
              f'    out.unsigned({expr}.count);',
              f'    for (var {i} in 0..{expr}.count) {{',
              f'        {fn(et)}_write(out, {expr}[{i}]);']
        if own:
            w += ['        ' + l for l in own_lines(own, f'{expr}[{i}]', et, own_bodies)]
        w += ['    }',
              '}']
    else:
        w += [f'var {hits} = HashSet<long>();',
             f'out.unsigned({expr}.count);',
             f'for (var {item} in {expr}) {{',
             '    var scratch = base.scratch();',
             f'    {fn(et)}_write(scratch, {item});',
             '    var hash = base.hash_of(scratch);',
             f'    var at = base.find_hashed({key}, hash);']
        w += ['    if (at >= 0) {',
             f'        {hits}.insert(at);',
             '        out.unsigned((at as ulong) * 2 + 1);',
             '    } else {',
             '        out.unsigned(0);',
             f'        {fn(et)}_write(out, {item});',
             '    }',
             '}',
             f'base.missed({category or key}, {key}, {hits}.count);']
    local = fresh('_f'); count = fresh('_n'); tag = fresh('_tag')
    # Merging (`RecordIn.merging`), the base is not the one the delta was
    # written on: a list written by place cannot merge, and a list
    # `resume_checked` replaces keeps the base's.
    refs = [f'var {count} = input.count();']
    if merge:
        refs += ['if (input.merging) {', f'    input.error = {category or key} + " written by place";', '}']
    else:
        refs += ['if (input.merging) {', f'    for (var _b in {base_list}) {{', f'        {local}.append(_b);', '    }', '}']
    refs += [f'for (var _ in 0..{count}) {{',
         f'    var {tag} = input.unsigned();',
         f'    if ({tag} & 1 == 1) {{',
         '        if (!input.merging) {',
         f'            {local}.append({base_list}[{tag} >> 1]);',
         '        }',
         '    } else {',
         f'        var _read = {fn(et)}_read(input);',
         '        if (!input.merging or ' + ('true' if merge else 'false') + ') {',
         f'            {local}.append(_read);',
         '        }',
         '    }',
         '}']
    r = [f'var {local} = Array<{model_type_name(et)}>();']
    if merge:
        mode = fresh('_mode'); bi = fresh('_bi'); at = fresh('_at')
        r += [f'var {mode} = input.unsigned();',
              f'if ({mode} == 2) {{',
              f'    var {ch} = HashMap<ulong, {model_type_name(et)}>();']
        if named:
            r += [f'    var {nc} = input.count();',
                  f'    for (var _ in 0..{nc}) {{',
                  '        var _name = input.text();',
                  '        var _slot = input.unsigned();',
                  '        if (input.merging) {',
                  f'            _slot = {base_list}.count;',
                  f'            for (var _k in 0..{base_list}.count) {{',
                  f'                if ({base_list}[_k].name == _name) {{',
                  '                    _slot = _k;',
                  '                    break;',
                  '                }',
                  '            }',
                  '        }',
                  f'        var _el = {fn(et)}_read(input);',
                  f'        if (_slot < {base_list}.count) {{',
                  f'            {ch}[_slot] = _el;',
                  '        } else {',
                  f'            input.error = $"no {{_name}} to change";',
                  '        }',
                  '    }']
        r += [f'    ulong {bi} = 0;',
              f'    var {count} = input.count();',
              f'    for (var _ in 0..{count}) {{',
              f'        var {at} = input.unsigned();',
              f'        while ({local}.count < {at} or (input.merging and {bi} < {base_list}.count)) {{',
              f'            var _c = {ch}.try_get({bi});',
              f'            {local}.append(_c.is_value() ? _c.value() : {base_list}[{bi}]);',
              f'            {bi} += 1;',
              '        }',
              f'        {local}.append({fn(et)}_read(input));',
              '    }',
              f'    while ({bi} < {base_list}.count) {{',
              f'        var _c = {ch}.try_get({bi});',
              f'        {local}.append(_c.is_value() ? _c.value() : {base_list}[{bi}]);',
              f'        {bi} += 1;',
              '    }',
              f'}} else if ({mode} == 3) {{',
              f'    var {count} = input.count();',
              f'    for (var _ in 0..{count}) {{',
              f'        {local}.append({fn(et)}_read(input));',
              '    }',
              '} else {']
        r += ['    ' + l for l in refs] + ['}']
    else:
        r += refs
    j = fresh('_j')
    x = [f'ulong {j} = 0;',
         f'for (var {item} in {expr}) {{',
         '    var scratch = base.scratch();',
         f'    {fn(et)}_write(scratch, {item});',
         f'    base.add({key}, scratch, {j});']
    if named:
        x += [f'    base.name({key}, {item}.name, {j});']
    x += [f'    {j} += 1;',
         '}']
    if merge and ref:
        x = ['if (base.verifying) {'] + ['    ' + l for l in x] + ['}']
    return w, r, x, local

def _prefix_delta(fname, tree):
    """A list that grows at its end: when its first elements are the
    base's list, written as how many those are (tag 1) and the rest;
    else in full (tag 0)."""
    et = tree[1]
    item = fresh('_item'); sc = fresh('_scratch'); n = fresh('_n'); i = fresh('_i')
    w = [f'var {n} = base.size("{fname}");',
         f'var {sc} = base.scratch();',
         f'if (value.{fname}.count >= {n}) {{',
         f'    for (var {i} in 0..{n}) {{']
    w += ['        ' + l for l in write_to(sc, f'value.{fname}[{i}]', et)]
    w += ['    }', '}',
          f'if (value.{fname}.count >= {n} and base.same_list("{fname}", {sc})) {{',
          '    out.unsigned(1);',
          f'    out.unsigned({n});',
          f'    out.unsigned(value.{fname}.count - {n});',
          f'    for (var {i} in {n}..value.{fname}.count) {{']
    w += ['        ' + l for l in write(f'value.{fname}[{i}]', et)]
    if fname not in NOT_INTERFACE:
        w += ['        ' + l for l in own_lines(fname, f'value.{fname}[{i}]', et)]
    w += ['    }', '} else {', '    out.unsigned(0);']
    w += ['    ' + l for l in write(f'value.{fname}', tree)]
    if fname not in NOT_INTERFACE:
        w += [f'    for (var {i} in 0..value.{fname}.count) {{'] + ['        ' + l for l in own_lines(fname, f'value.{fname}[{i}]', et)] + ['    }']
    w += [f'    base.count("{fname} whole", 0);', '}']
    local = fresh('_f'); tag = fresh('_tag'); keep = fresh('_keep'); more = fresh('_more')
    el, ev = read(et)
    whole_lines, whole_val = read(tree)
    r = [f'var {local} = {pep(tree)}();',
         f'var {tag} = input.unsigned();',
         f'if ({tag} == 1) {{',
         # The base's whole list, as the base is now: the delta was written
         # on a base with the same interface, whose body-derived lists may
         # have changed since.
         f'    input.unsigned();',
         f'    for (var {i} in 0..base.{fname}.count) {{',
         f'        {local}.append(base.{fname}[{i}]);',
         '    }',
         f'    var {more} = input.count();',
         f'    for (var _ in 0..{more}) {{']
    r += ['        ' + l for l in el] + [f'        {local}.append({ev});', '    }', '} else {']
    r += ['    ' + l for l in whole_lines] + [f'    {local} = {whole_val};', '}']
    xs = fresh('_xscratch'); xi = fresh('_xitem')
    x = [f'var {xs} = base.scratch();', f'for (var {xi} in value.{fname}) {{']
    x += ['    ' + l for l in write_to(xs, xi, et)]
    x += ['}', f'base.keep_list("{fname}", value.{fname}.count, {xs});']
    return w, r, x, local

def _sorted_delta(fname, tree):
    """A list `argument_names` keeps sorted by place, without repeats:
    when it holds every element of the base's, written as the elements
    the base lacks (tag 1), which reading merges in as the pass sorts;
    else in full (tag 0)."""
    et = tree[1]
    item = fresh('_item'); es = fresh('_escratch'); kept = fresh('_kept'); news = fresh('_news')
    w = [f'ulong {kept} = 0;',
         f'var {news} = {pep(tree)}();',
         f'for (var {item} in value.{fname}) {{',
         f'    var {es} = base.scratch();']
    w += ['    ' + l for l in write_to(es, item, et)]
    w += [f'    if (base.entry("{fname}", {es}, base.scratch()) >= 0) {{',
          f'        {kept} += 1;',
          '    } else {',
          f'        {news}.append({item});',
          '    }',
          '}',
          f'if ({kept} == base.size("{fname}")) {{',
          '    out.unsigned(1);']
    w += ['    ' + l for l in write(news, tree)]
    w += ['} else {', '    out.unsigned(0);']
    w += ['    ' + l for l in write(f'value.{fname}', tree)]
    w += [f'    base.count("{fname} whole", 0);', '}']
    local = fresh('_f'); tag = fresh('_tag')
    added_lines, added_val = read(tree)
    whole_lines, whole_val = read(tree)
    r = [f'var {local} = {pep(tree)}();',
         f'var {tag} = input.unsigned();',
         f'if ({tag} == 1) {{']
    r += ['    ' + l for l in added_lines]
    r += [f'    {local} = merge_by_place(base.{fname}, {added_val});']
    r += ['} else {'] + ['    ' + l for l in whole_lines] + [f'    {local} = {whole_val};', '}']
    x = [f'for (var {item} in value.{fname}) {{', f'    var {es} = base.scratch();']
    x += ['    ' + l for l in write_to(es, item, et)]
    x += [f'    base.keep_entry("{fname}", {es}, base.scratch());', '}']
    return w, r, x, local

def _own_entries(label, expr, tree):
    """Lines that add each entry of set or map `expr` to the own interface."""
    key = fresh('_okey'); o = fresh('_own')
    loop = f'for (var {key} in {expr}) {{' if tree[0] == 'set' else f'for (var ({key}, _) in {expr}) {{'
    lines = [loop, f'    var {o} = RecordOut();', f'    {o}.blank_bodies = true;', f'    {o}.blank_locs = true;', f'    {o}.pending_as_bytes = true;']
    lines += ['    ' + l for l in write_to(o, key, tree[1])]
    if tree[0] == 'map':
        lines += ['    ' + l for l in write_to(o, f'{expr}[{key}]', tree[2])]
    lines += [_own_call(label, key, f'interface_text({o})'), '}']
    return lines

def _additions_delta(fname, tree):
    """A set or map that only gains entries: when every key of the
    base's is still there, written as the entries added or changed since
    (tag 1); else in full (tag 0)."""
    is_map = tree[0] == 'map'
    kt = tree[1]
    key = fresh('_key'); ks = fresh('_kscratch'); vs = fresh('_vscratch'); kept = fresh('_kept'); news = fresh('_news')
    loop = f'for (var {key} in value.{fname}) {{' if not is_map else f'for (var ({key}, _) in value.{fname}) {{'
    w = [f'ulong {kept} = 0;',
         f'var {news} = {pep(tree)}();',
         loop,
         f'    var {ks} = base.scratch();']
    w += ['    ' + l for l in write_to(ks, key, kt)]
    w += [f'    var {vs} = base.scratch();']
    if is_map:
        w += ['    ' + l for l in write_to(vs, f'value.{fname}[{key}]', tree[2])]
    w += [f'    var _had = base.entry("{fname}", {ks}, {vs});',
          '    if (_had >= 0) {',
          f'        {kept} += 1;',
          '    }',
          '    if (_had != 1) {']
    w += [f'        {news}[{key}] = value.{fname}[{key}];' if is_map else f'        {news}.insert({key});']
    w += ['    }', '}',
          f'if ({kept} == base.size("{fname}")) {{',
          '    out.unsigned(1);']
    w += ['    ' + l for l in write(news, tree)]
    if fname not in NOT_OWN:
        w += ['    ' + l for l in _own_entries(fname, news, tree)]
    w += ['} else {', '    out.unsigned(0);']
    w += ['    ' + l for l in write(f'value.{fname}', tree)]
    if fname not in NOT_OWN:
        w += ['    ' + l for l in _own_entries(fname, f'value.{fname}', tree)]
    w += [f'    base.count("{fname} whole", 0);', '}']
    local = fresh('_f'); tag = fresh('_tag'); bk = fresh('_bk')
    added_lines, added_val = read(tree)
    whole_lines, whole_val = read(tree)
    r = [f'var {local} = {pep(tree)}();',
         f'var {tag} = input.unsigned();',
         f'if ({tag} == 1) {{']
    if is_map:
        r += [f'    for (var ({bk}, _bv) in base.{fname}) {{', f'        {local}[{bk}] = _bv;', '    }']
    else:
        r += [f'    for (var {bk} in base.{fname}) {{', f'        {local}.insert({bk});', '    }']
    r += ['    ' + l for l in added_lines]
    if is_map:
        r += [f'    for (var ({bk}, _av) in {added_val}) {{', f'        {local}[{bk}] = _av;', '    }']
    else:
        r += [f'    for (var {bk} in {added_val}) {{', f'        {local}.insert({bk});', '    }']
    r += ['} else {'] + ['    ' + l for l in whole_lines] + [f'    {local} = {whole_val};', '}']
    x = [loop, f'    var {ks} = base.scratch();']
    x += ['    ' + l for l in write_to(ks, key, kt)]
    x += [f'    var {vs} = base.scratch();']
    if is_map:
        x += ['    ' + l for l in write_to(vs, f'value.{fname}[{key}]', tree[2])]
    x += [f'    base.keep_entry("{fname}", {ks}, {vs});', '}']
    return w, r, x, local

def _struct_fields():
    return [f for f in model.items['StructDef']['fields'] if not f['skip']]

# The `DeltaBase` list each struct list's base structs are found in by
# identity, and the one (`REF_PARTS`) of its member lists as indexed.
REF_LISTS = {'s': 'ref_structs', 't': 'ref_templates'}
# The element types a delta compares by record when identity misses
# (`_same_<Type>`).
SAME_TYPES = {('model', 'StructDef')}

def same_functions():
    out = []
    for et in sorted(SAME_TYPES):
        t = model_type_name(et)
        out += [f'# Whether `a`, not the base\'s element `b` itself, has the same record:',
                '# a copy a pass made of it.',
                f'_same{fn(et)}(a: {t}, b: {t}, base: DeltaBase): bool {{',
                '    var x = base.scratch();',
                f'    {fn(et)}_write(x, a);',
                '    var y = base.scratch();',
                f'    {fn(et)}_write(y, b);',
                '    return base.hash_of(x) == base.hash_of(y);',
                '}', '']
    return out
REF_PARTS = {'s': 'ref_struct_parts', 't': 'ref_template_parts'}

def struct_shallow():
    """`_m_StructDef_shallow`: a struct with the same fields and copies of
    its member lists, which an extension of the struct leaves as they are."""
    fields = _struct_fields()
    args = {}
    for f in fields:
        fname = model.fname(f['name'])
        tree = rust_type(f['type'])
        args[f['name']] = f'value.{fname}.clone()' if tree[0] == 'vec' else f'value.{fname}'
    required = [f for f in fields if default_of(f['type']) is None]
    optional = [f for f in fields if default_of(f['type']) is not None]
    return ['_m_StructDef_shallow(value: StructDef): StructDef {',
            f'    return StructDef({", ".join(args[f["name"]] for f in required + optional)});',
            '}']

def struct_list_delta(expr, list_key, base_list, own=None, own_bodies='true'):
    """Lines for a list of StructDef, with the patch form. A list that
    holds the base's structs in order, some patched, is written as the
    patches and the new structs with their places (mode 2); else each
    struct as kept, patched or new (mode 1)."""
    st = ('model', 'StructDef')
    item = fresh('_item')
    sh = fresh('_struct_hits')
    seq = fresh('_seq'); bj = fresh('_bj'); slots = fresh('_slots')
    news = fresh('_news'); patches = fresh('_patches'); i = fresh('_i')
    ref = REF_LISTS[list_key]
    # The base's structs by identity (`DeltaBase.ref_structs`): one still there
    # is the base's as it was, unless the compilation unit extended it, which
    # patches it, its member lists found by identity in turn.
    w = [f'var {seq} = base.{ref};',
         f'ulong {bj} = 0;',
         f'var {news} = Array<ulong>();',
         f'var {patches} = Array<(ulong, ulong)>();',
         f'for (var {i} in 0..{expr}.count) {{',
         f'    if ({bj} < {seq}.count and {expr}[{i}] === {seq}[{bj}] and !value.extended_checked.contains({expr}[{i}].name)) {{',
         '        if (base.verifying) {',
         '            var scratch = base.scratch();',
         f'            {fn(st)}_write(scratch, {expr}[{i}]);',
         f'            base.verify_same("{list_key}", {bj}, scratch, {expr}[{i}].name);',
         '        }',
         f'        {bj} += 1;',
         f'    }} else if ({bj} < {seq}.count and !({expr}[{i}] === {seq}[{bj}]) and _same_m_StructDef({expr}[{i}], {seq}[{bj}], base)) {{',
         '        if (base.verifying) {',
         '            var scratch = base.scratch();',
         f'            {fn(st)}_write(scratch, {expr}[{i}]);',
         f'            base.verify_same("{list_key}", {bj}, scratch, {expr}[{i}].name);',
         '        }',
         f'        {bj} += 1;',
         f'    }} else if ({bj} < {seq}.count and {expr}[{i}].name == {seq}[{bj}].name) {{',
         f'        {patches}.append(({i}, {bj}));',
         f'        {bj} += 1;',
         '    } else {',
         f'        {news}.append({i});',
         '    }',
         '}',
         f'if ({bj} == {seq}.count) {{',
         '    out.unsigned(2);',
         f'    out.unsigned({patches}.count);',
         f'    for (var ({i}, _b) in {patches}) {{',
         '        ulong _before = out.values.count;',
         f'        out.text({expr}[{i}].name);',
         '        out.unsigned(_b);',
         f'        _patch_{list_key}_write(out, {expr}[{i}], base, _b);',
         f'        base.count("{list_key} patched", out.values.count - _before);']
    if own:
        w += ['        ' + l for l in own_lines(own, f'{expr}[{i}]', st, own_bodies)]
    w += ['    }',
         f'    out.unsigned({news}.count);',
         f'    for (var {i} in {news}) {{',
         '        ulong _before = out.values.count;',
         f'        out.unsigned({i});',
         f'        {fn(st)}_write(out, {expr}[{i}]);',
         f'        base.count("{list_key} new", out.values.count - _before);']
    if own:
        w += ['        ' + l for l in own_lines(own, f'{expr}[{i}]', st, own_bodies)]
    w += ['    }',
         f'    base.count("{list_key} merged", 0);',
         '} else {',
         '    out.unsigned(1);',
         f'    base.count("{list_key} by place", 0);',
         f'    var {sh} = HashSet<long>();',
         f'    var {slots} = HashMap<String, long>();',
         f'    for (var {i} in 0..{seq}.count) {{',
         f'        if (!{slots}.contains({seq}[{i}].name)) {{',
         f'            {slots}[{seq}[{i}].name] = {i} as long;',
         '        }',
         '    }',
         f'    out.unsigned({expr}.count);',
         f'    for (var {i} in 0..{expr}.count) {{',
         f'        var {item} = {expr}[{i}];',
         f'        var _slot = {slots}.try_get({item}.name);',
         '        long named = _slot.is_value() ? _slot.value() : -1;',
         '        long at = -1;',
         f'        if (named >= 0 and {seq}[named as ulong] === {item} and !value.extended_checked.contains({item}.name)) {{',
         '            at = named;',
         '        }',
         '        ulong _before = out.values.count;',
         '        if (at >= 0) {',
         f'            {sh}.insert(at);',
         '            out.unsigned((at as ulong) * 2 + 1);',
         '        } else if (named >= 0) {',
         f'            {sh}.insert(named);',
         '            out.unsigned(2);',
         '            out.unsigned(named as ulong);',
         f'            _patch_{list_key}_write(out, {item}, base, named as ulong);',
         f'            base.count("{list_key} patched", out.values.count - _before);',
         '        } else {',
         '            out.unsigned(0);',
         f'            {fn(st)}_write(out, {item});',
         f'            base.count("{list_key} new", out.values.count - _before);',
         '        }',
         '    }',
         f'    base.missed("{list_key}", "{list_key}", {sh}.count);',
         '}']
    local = fresh('_f'); count = fresh('_n'); tag = fresh('_tag'); mode = fresh('_mode')
    bi = fresh('_bi'); at = fresh('_at'); patched = fresh('_patched')
    r = [f'var {local} = Array<StructDef>();',
         f'var {mode} = input.unsigned();',
         f'if ({mode} == 2) {{',
         f'    var {patched} = HashMap<ulong, StructDef>();',
         f'    var {count} = input.count();',
         f'    for (var _ in 0..{count}) {{',
         '        var _name = input.text();',
         f'        var _slot = input.unsigned();',
         '        if (input.merging) {',
         f'            _slot = struct_named({base_list}, _name);',
         '        }',
         f'        if (_slot >= {base_list}.count) {{',
         f'            input.error = $"no struct {{_name}} to patch";',
         '            break;',
         '        }',
         f'        {patched}[_slot] = _patch_{list_key}_read(input, {base_list}[_slot]);',
         '    }',
         f'    ulong {bi} = 0;',
         f'    var _added = input.count();',
         f'    for (var _ in 0.._added) {{',
         f'        var {at} = input.unsigned();',
         f'        while ({local}.count < {at} or (input.merging and {bi} < {base_list}.count)) {{',
         f'            var _p = {patched}.try_get({bi});',
         f'            {local}.append(_p.is_value() ? _p.value() : {base_list}[{bi}]);',
         f'            {bi} += 1;',
         '        }',
         f'        {local}.append({fn(st)}_read(input));',
         '    }',
         f'    while ({bi} < {base_list}.count) {{',
         f'        var _p = {patched}.try_get({bi});',
         f'        {local}.append(_p.is_value() ? _p.value() : {base_list}[{bi}]);',
         f'        {bi} += 1;',
         '    }',
         '} else {',
         '    if (input.merging) {',
         '        input.error = "structs written by place";',
         '    }',
         f'    var {count} = input.count();',
         f'    for (var _ in 0..{count}) {{',
         f'        var {tag} = input.unsigned();',
         f'        if ({tag} & 1 == 1) {{',
         f'            {local}.append({base_list}[({tag} >> 1) < {base_list}.count ? {tag} >> 1 : 0]);',
         f'        }} else if ({tag} == 2) {{',
         f'            var _was = {base_list}[input.unsigned()];',
         f'            {local}.append(_patch_{list_key}_read(input, _was));',
         '        } else {',
         f'            {local}.append({fn(st)}_read(input));',
         '        }',
         '    }',
         '}']
    j = fresh('_j')
    x = [f'ulong {j} = 0;',
         f'for (var {item} in {expr}) {{',
         '    var scratch = base.scratch();',
         f'    {fn(st)}_write(scratch, {item});',
         f'    base.add("{list_key}", scratch, {j});',
         f'    base.name("{list_key}", {item}.name, {j});',
         f'    _patch_{list_key}_index({item}, base, {j});',
         f'    {j} += 1;',
         '}']
    x = ['if (base.verifying) {'] + ['    ' + l for l in x] + ['}',
         f'base.{ref} = {expr}.clone();',
         f'base.{REF_PARTS[list_key]} = Array<StructDef>();',
         f'for (var {item} in {expr}) {{',
         f'    base.{REF_PARTS[list_key]}.append(_m_StructDef_shallow({item}));',
         '}']
    return w, r, x, local

def struct_patch(list_key):
    """The patch writer, reader and indexer of a StructDef in `list_key`."""
    fields = _struct_fields()
    w = [f'_patch_{list_key}_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {{']
    r = [f'_patch_{list_key}_read(input: RecordIn, was: StructDef): StructDef {{']
    x = [f'_patch_{list_key}_index(value: StructDef, base: DeltaBase, slot: ulong) {{']
    names = {}
    for f in fields:
        fname = model.fname(f['name'])
        tree = rust_type(f['type'])
        if tree[0] == 'vec' and tree[1][0] in ('model', 'ast'):
            key = f'$"{list_key}.{{slot}}.{fname}"'
            lw, lr, lx, local = _list_delta(f'value.{fname}', tree[1], key, f'was.{fname}', f'"{list_key}.*.{fname}"', merge=True, ref=f'base.{REF_PARTS[list_key]}[slot].{fname}')
            w += ['    ' + l for l in lw]
            r += ['    ' + l for l in lr]
            x += ['    ' + l for l in lx]
            names[f['name']] = local
        else:
            w += ['    ' + l for l in write(f'value.{fname}', tree)]
            lines, val = read(tree)
            local = fresh('_f')
            r += ['    ' + l for l in lines] + [f'    var {local} = {val};']
            names[f['name']] = local
    w.append('}'); x.append('}')
    required = [f for f in fields if default_of(f['type']) is None]
    optional = [f for f in fields if default_of(f['type']) is not None]
    r.append(f'    return StructDef({", ".join(names[f["name"]] for f in required + optional)});')
    r.append('}')
    return w + [''] + r + [''] + x

def module_delta():
    fields = [f for f in model.items['Module']['fields'] if not f['skip']]
    w = ['_m_Module_write_delta(out: RecordOut, value: Module, base: DeltaBase) {', '    ulong _mark = out.values.count;']
    # The fields `resume_checked` replaces after the write: indexed again
    # from the module it resumes.
    resumed = ('type_aliases', 'recorded_summaries', 'summaries_to_record')
    xr = ['_m_Module_index_resumed(value: Module, base: DeltaBase) {']
    r = ['_m_Module_read_delta(input: RecordIn, base: Module): Module {']
    x = ['_m_Module_index(value: Module, base: DeltaBase) {']
    names = {}
    for f in fields:
        fname = model.fname(f['name'])
        tree = rust_type(f['type'])
        if fname == 'structs':
            lw, lr, lx, local = struct_list_delta('value.structs', 's', 'base.structs', own='structs')
            lr = [_lazy(l) for l in lr]
        elif fname == 'templates':
            tw, tr, tx, tlocal = struct_list_delta('value.templates.structs', 't', 'base.templates.structs', own='templates structs', own_bodies='false')
            fw, fr, fx, flocal = _list_delta('value.templates.functions', ('model', 'FunctionDef'), '"tf"', 'base.templates.functions', merge=True, named=True, own='templates functions', own_bodies='false', ref='base.ref_template_functions')
            fx += ['base.ref_template_functions = value.templates.functions.clone();']
            local = fresh('_f')
            lw = ['out.flag(value.templates.frozen);'] + tw + fw
            # The flag is written first, so it is read first.
            lr = [f'var _frozen = input.flag();'] + tr + fr + [f'var {local} = Templates(_frozen, {tlocal}, {flocal});']
            lx = tx + fx
        elif fname == 'checked':
            local = fresh('_f')
            lw = ['base.write_checked(out, value.checked);']
            lr = [f'var {local} = DeltaBase.read_checked(input, base.checked);']
            lx = ['base.keep_checked(value.checked);']
        elif fname == 'conversions':
            # Rebuilt by each compilation unit's `convert_to_traits`: written
            # whole; its own interface is the conversions the base lacks.
            lw = write(f'value.{fname}', tree)
            ci = fresh('_conv'); co = fresh('_own'); cj = fresh('_cj')
            lw += [f'for (var {ci} in value.conversions) {{', f'    var {co} = RecordOut();', f'    {co}.blank_locs = true;']
            lw += ['    ' + l for l in write_to(co, ci, tree[1])]
            lw += [f'    var _h = interface_text({co});', '    if (base.find_hashed("conversions", _h) < 0) {', '        base.own("conversions", _h);', '    }', '}']
            lines, val = read(tree)
            local = fresh('_f')
            lr = lines + [f'var {local} = {val};']
            lx = [f'ulong {cj} = 0;', f'for (var {ci} in value.conversions) {{', f'    var {co} = RecordOut();', f'    {co}.blank_locs = true;']
            lx += ['    ' + l for l in write_to(co, ci, tree[1])]
            lx += [f'    base.add_hashed("conversions", interface_text({co}), {cj});', f'    {cj} += 1;', '}']
        elif tree[0] == 'vec' and tree[1][0] in ('model', 'ast'):
            lw, lr, lx, local = _list_delta(f'value.{fname}', tree[1], f'"{fname}"', f'base.{fname}', merge=fname not in resumed, named=fname == 'functions', own=None if fname in resumed else fname, ref='base.ref_functions' if fname == 'functions' else None)
            if fname == 'functions':
                lr = [_lazy(l) for l in lr]
                lx += ['base.ref_functions = value.functions.clone();']
        elif fname == 'argument_names':
            lw, lr, lx, local = _sorted_delta(fname, tree)
        elif tree[0] == 'vec':
            lw, lr, lx, local = _prefix_delta(fname, tree)
        elif tree[0] in ('set', 'map'):
            lw, lr, lx, local = _additions_delta(fname, tree)
        else:
            lw = write(f'value.{fname}', tree)
            lines, val = read(tree)
            local = fresh('_f')
            lr = lines + [f'var {local} = {val};']
            lx = []
        w += ['    ' + l for l in lw]
        if fname in resumed:
            xr += ['    ' + l for l in lx]
        w += [f'    base.stat("{fname}", out.values.count - _mark);', '    _mark = out.values.count;']
        r += ['    ' + l for l in lr]
        x += ['    ' + l for l in lx]
        names[f['name']] = local
    w.append('}')
    x.append('}')
    xr.append('}')
    required = [f for f in fields if default_of(f['type']) is None]
    optional = [f for f in fields if default_of(f['type']) is not None]
    r.append(f'    return Module({", ".join(names[f["name"]] for f in required + optional)});')
    r.append('}')
    return w + [''] + r + [''] + x + [''] + xr + [''] + struct_patch('s') + [''] + struct_patch('t') + [''] + struct_shallow() + [''] + same_functions()

def model_type_name(t):
    return f'ast.{t[1]}' if t[0] == 'ast' else t[1]

# For `PEPC_TRACE_INTERFACE`: the interface hash of each field of the
# module, and of each struct and function by name.
def module_interface_fields():
    fields = [f for f in model.items['Module']['fields'] if not f['skip']]
    lines = ['_m_Module_interface_fields(value: Module, interface: bool): Array<(String, String)> {',
             '    var found = Array<(String, String)>();']
    for f in fields:
        fname = model.fname(f['name'])
        tree = rust_type(f['type'])
        lines += ['    {', '        var out = RecordOut();', '        out.blank_bodies = interface;', '        out.blank_locs = interface;']
        body = write(f'value.{fname}', tree)
        if fname == 'templates':
            body = ['out.blank_bodies = false;'] + body
        if fname in ('literal_args', 'call_targets', 'argument_names', 'stripped', 'summaries_to_record', 'cached_files'):
            body = ['if (interface) {', '    out.unsigned(0);', '} else {'] + ['    ' + l for l in body] + ['}']
        if fname == 'recorded_summaries':
            body = ['if (interface) {', '    write_interface_summaries(out, value.recorded_summaries);', '} else {'] + ['    ' + l for l in body] + ['}']
        if fname == 'checked':
            body = [f'{fn(("model", "Checked"))}_write(out, value.checked);']
        lines += ['        ' + l for l in body]
        lines += [f'        found.append(("{fname}", interface_text(out)));', '    }']
    for fname, et in (('structs', ('model', 'StructDef')), ('functions', ('model', 'FunctionDef'))):
        item = fresh('_item')
        lines += [f'    for (var {item} in value.{fname}) {{', '        var out = RecordOut();', '        out.blank_bodies = interface;', '        out.blank_locs = interface;',
                  f'        {fn(et)}_write(out, {item});',
                  f'        found.append(("{fname} " + {item}.name, interface_text(out)));', '    }']
    lines += ['    return found;', '}']
    return lines


out_blocks.append(module_delta())
out_blocks.append(module_interface_fields())

header = '''## Saving and loading a checked module: a binary writer and reader for
## every type `Module` reaches, the AST nodes it holds included. Generated
## by `scripts/gen-sema-record.py`; do not edit.

import compiler.ast;
import [Loc] from "loc";
import "model";
import "pending";
import [
    compare_bytes,
    DeltaBase,
    interface_text,
    merge_by_place,
    RecordIn,
    RecordOut,
    struct_named,
    summary_without_place,
    write_interface_checked_summaries,
    write_interface_summaries
] from "record";

## Decodes a function body a reader skipped (`RecordIn.lazy_bodies`).
##
## @param pending where the body is in its record
## @returns the body
export decode_body(pending: PendingBody): Block {
    return _m_Block_read(RecordIn.at(pending));
}

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

## Writes `module` to `out` as a delta on the module `base` indexes: each
## element of its lists that the base holds as it is becomes a reference.
##
## @param out the record
## @param module the module
## @param base the index of the module it is written on
export write_module_delta(out: RecordOut, module: Module, base: DeltaBase) {
    _m_Module_write_delta(out, module, base);
}

## Reads a module from `input`, as `write_module_delta` wrote it on `base`.
## The elements it refers to are `base`'s own, not copies.
##
## @param input the record
## @param base the module it was written on, as read back
## @returns the module
export read_module_delta(input: RecordIn, base: Module): Module {
    return _m_Module_read_delta(input, base);
}

## Indexes `module`'s list elements into `base`, for `write_module_delta`.
##
## @param module the module a later delta is written on
## @param base the index
export index_module(module: Module, base: DeltaBase) {
    _m_Module_index(module, base);
}

## Indexes into `base` the fields of `module` that `resume_checked` replaces,
## which `write_module_delta` leaves out of its `next`.
##
## @param module the module, resumed
## @param base the index
export index_resumed(module: Module, base: DeltaBase) {
    _m_Module_index_resumed(module, base);
}

## Returns the interface hash of each field of `module`, and of each
## struct and function by name, for `PEPC_TRACE_INTERFACE`; or with
## `interface` false, the hash of each as it is written in full.
##
## @param module the module
## @param interface whether to hash the interface
## @returns (what, hash) pairs
export interface_fields(module: Module, interface: bool = true): Array<(String, String)> {
    return _m_Module_interface_fields(module, interface);
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
