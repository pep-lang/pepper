#!/usr/bin/env python3
# Regenerates tools/compiler/sema/model.pep, the sema model in Pepper, from
# its own declarations: each struct's and enum's fields as model.pep
# declares them, with a constructor, a deep `copy()`, a `fingerprint()` and
# a `to_json()` (what `pep-build --emit-model` prints, which passes_test
# compares against). To change the model, change a type's
# fields in model.pep, run this, then format the result:
#
#   python3 scripts/gen-sema-model.py tools/compiler/sema/model.pep
#   pep-fmt -w tools/compiler/sema/model.pep
#
# and regenerate the record codec (scripts/gen-sema-record.py), which reads
# the model through this script.

import json, os, re, sys

# ---- Helpers.

def split_top(s, sep=','):
    parts=[];depth=0;cur=''
    for c in s:
        if c in '<([{': depth+=1
        elif c in '>)]}': depth-=1
        if c==sep and depth==0:
            parts.append(cur);cur=''
        else: cur+=c
    if cur.strip(): parts.append(cur)
    return [p.strip() for p in parts if p.strip()]

# ---- The generator.

# The declarations come from model.pep itself: each struct's and enum's
# fields, read back into the Rust-shaped items the generator was written
# over (`rust_of` undoes `pep`). Change a type there, then run this to
# regenerate the methods.
MODEL=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','tools','compiler','sema','model.pep')

PEP_PRIM={'String':'String','bool':'bool','ulong':'u64','uint':'u32','long':'i64','int':'i32','double':'f64','u8':'u8'}

def rust_of(t):
    t=t.strip()
    if t.endswith('?'):
        return f'Option<{rust_of(t[:-1])}>'
    if t.startswith('(') and t.endswith(')'):
        return '('+', '.join(rust_of(x) for x in split_top(t[1:-1]))+')'
    m=re.match(r'^([\w.]+)<(.*)>$',t)
    if m:
        n=m.group(1); args=[rust_of(x) for x in split_top(m.group(2))]
        rust={'Optional':'Option','Array':'Vec','HashSet':'HashSet','HashMap':'HashMap','Map':'BTreeMap'}[n]
        return f'{rust}<{", ".join(args)}>'
    if t in PEP_PRIM: return PEP_PRIM[t]
    if t.startswith('ast.'): return 'ast::'+t[4:]
    return t

# Fields whose type is the AST's enum of the same name, which the methods
# share rather than default or fingerprint.
AST_FIELDS={('JumpStaticItem','kind'):'ast::LoopBreakKind'}

def parse_pepper(src):
    lines=src.split('\n')
    found={}
    order=[]
    i=0
    while i<len(lines):
        m=re.match(r'^export (struct|enum) (\w+) \{$',lines[i])
        if not m:
            i+=1
            continue
        kind,name=m.group(1),m.group(2)
        j=i+1
        body=[]
        while lines[j]!='}':
            body.append(lines[j]); j+=1
        if kind=='struct':
            fields=[]
            internal=[]
            for l in body:
                # A field with its own default is in memory only: declared
                # as written and kept by `copy()`, but not fingerprinted,
                # written as JSON or recorded.
                im=re.match(r'^    var (\w+): (.*) = (.*);$',l)
                if im:
                    internal.append({'name':im.group(1),'pep':im.group(2),'default':im.group(3)})
                    continue
                fm=re.match(r'^    var (\w+): (.*);$',l)
                if fm:
                    fn_=fm.group(1)
                    ty=AST_FIELDS.get((name,fn_)) or rust_of(fm.group(2))
                    fields.append({'name':{'this_value':'this'}.get(fn_,fn_),'type':ty,'skip':False})
            found[name]={'kind':'struct','fields':fields,'internal':internal,'ser':True}
        else:
            variants=[]
            for l in body:
                if l.startswith('    ##') or not l.startswith('    ') or l.startswith('     '):
                    continue
                vm=re.match(r'^    (\w+)(?:\((.*)\))?,$',l)
                if not vm:
                    continue
                vname,params=vm.group(1),vm.group(2)
                if params is None:
                    variants.append({'name':vname,'kind':'unit'})
                elif params==f'node: {vname}{name}':
                    variants.append({'name':vname,'kind':'struct','payload':vname+name})
                else:
                    variants.append({'name':vname,'kind':'tuple','types':[rust_of(p.split(':',1)[1]) for p in split_top(params)]})
            found[name]={'kind':'enum','variants':variants,'ser':True}
        order.append(name)
        i=j+1
    out={}
    payloads=set()
    for name in order:
        it=found[name]
        if it['kind']=='enum':
            for vv in it['variants']:
                if vv['kind']=='struct':
                    vv['fields']=found[vv.pop('payload')]['fields']
                    payloads.add(vv['name']+name)
    for name in order:
        if name not in payloads:
            out[name]=found[name]
    return out

items=parse_pepper(open(MODEL).read())

RENAME={'this':'this_value'}
PRIM={'String':'String','bool':'bool','usize':'ulong','u32':'uint','u64':'ulong','i64':'long','i128':'long','i32':'int','f64':'double','u8':'u8'}

def fname(n): return RENAME.get(n,n)

def strip_path(t):
    t=t.strip()
    t=re.sub(r'std::collections::','',t)
    t=re.sub(r'crate::type_name::','',t)
    return t

def parse_type(t):
    t=strip_path(t)
    if t.startswith('(') and t.endswith(')'):
        return ('tuple',[parse_type(x) for x in split_top(t[1:-1])])
    m=re.match(r'^([\w:]+)<(.*)>$',t)
    if m:
        return (m.group(1),[parse_type(x) for x in split_top(m.group(2))])
    return (t,[])

def pep(tp, top=True):
    n,args=tp
    if n=='tuple': return '('+', '.join(pep(a,False) for a in args)+')'
    if n=='Box': return pep(args[0],top)
    if n=='Option':
        inner=pep(args[0],False)
        return inner+'?' if top and not inner.startswith('(') else f'Optional<{inner}>'
    if n=='Vec': return f'Array<{pep(args[0],False)}>'
    if n=='HashSet': return f'HashSet<{pep(args[0],False)}>'
    if n=='HashMap': return f'HashMap<{pep(args[0],False)}, {pep(args[1],False)}>'
    if n=='BTreeMap': return f'Map<{pep(args[0],False)}, {pep(args[1],False)}>'
    if n in PRIM: return PRIM[n]
    if n=='ast::LoopBreakKind': return 'LoopBreakKind'
    if n.startswith('ast::'): return 'ast.'+n[5:]
    return n

def is_unit_enum(n):
    it=items.get(n)
    return it and it['kind']=='enum' and all(v['kind']=='unit' for v in it['variants'])

# Which generated types have a no-argument constructor.
defaultable_cache={}
def default_of(tp):
    n,args=tp
    if n=='Box': return default_of(args[0])
    if n=='Option': return 'Optional<%s>.Empty' % pep(args[0],False)
    if n in ('Vec','HashSet','HashMap','BTreeMap'): return pep(tp)+'()'
    if n=='String': return '""'
    if n=='bool': return 'false'
    if n in PRIM: return '0'
    if n=='Loc': return 'Loc()'
    if n=='tuple': return None
    if n.startswith('ast::'):
        return {'ast::Span':'ast.Span()'}.get(n)
    if is_unit_enum(n):
        return f"{n}.{items[n]['variants'][0]['name']}"
    it=items.get(n)
    if it and it['kind']=='struct' and struct_defaultable(n): return n+'()'
    return None

def struct_defaultable(n):
    if n in defaultable_cache: return defaultable_cache[n]
    defaultable_cache[n]=True
    ok=all(default_of(parse_type(f['type'])) is not None for f in items[n]['fields'] if not f['skip'])
    defaultable_cache[n]=ok
    return ok

COUNTER=[0]
def to_json(expr, tp, depth=0):
    """Returns (setup_lines, value_expr)."""
    n,args=tp
    COUNTER[0]+=1
    depth=COUNTER[0]
    v=f'_v{depth}'
    if n=='Box': return to_json(expr,args[0],depth)
    if n=='Option':
        lines,val=to_json(f'{expr}.value()',args[0],depth+1)
        if not lines:
            return [], f'({expr}.is_value() ? {val} : JsonValue.Null)'
        out=[f'var {v} = JsonValue.Null;', f'if ({expr}.is_value()) {{']+['    '+l for l in lines]+[f'    {v} = {val};','}']
        return out, v
    if n in ('Vec','HashSet'):
        item=f'_item{depth}'
        lines,val=to_json(item,args[0],depth+1)
        out=[f'var {v} = JsonValue.array();', f'for (var {item} in {expr}) {{']+['    '+l for l in lines]+[f'    {v}.append({val});','}']
        return out, v
    if n in ('HashMap','BTreeMap'):
        k=f'_key{depth}'; item=f'_item{depth}'
        lines,val=to_json(item,args[1],depth+1)
        keyval = k if args[0][0]=='String' else (f'$"{{{k}}}"' if args[0][0] in PRIM else f'{k}.to_json().to_string()')
        out=[f'var {v} = JsonValue.object();', f'for (var ({k}, {item}) in {expr}) {{']+['    '+l for l in lines]+[f'    {v}[{keyval}] = {val};','}']
        return out, v
    if n=='tuple':
        out=[f'var {v} = JsonValue.array();', f'var _t{depth} = {expr};']
        names=[f'_t{depth}_{i}' for i in range(len(args))]
        out.append(f'var ({", ".join(names)}) = _t{depth};')
        for i,a in enumerate(args):
            lines,val=to_json(names[i],a,depth+1)
            out+=lines+[f'{v}.append({val});']
        return out, v
    if n=='String': return [], f'JsonValue.String({expr})'
    if n=='bool': return [], f'JsonValue.Bool({expr})'
    if n=='f64': return [], f'JsonValue.Number({expr})'
    if n in ('usize','u64'): return [], f'unsigned_json({expr})'
    if n in PRIM: return [], f'JsonValue.Integer({expr} as long)'
    return [], f'{expr}.to_json()'


FCOUNTER=[0]
def fingerprint_of(expr, tp):
    """Returns the lines that add expr to the fingerprint `into`."""
    n,args=tp
    FCOUNTER[0]+=1
    d=FCOUNTER[0]
    if n=='Box': return fingerprint_of(expr,args[0])
    if n=='Option':
        lines=fingerprint_of(f'{expr}.value()',args[0])
        return [f'if ({expr}.is_value()) {{']+['    '+l for l in lines]+['    into.add(1);','} else {','    into.add(0);','}']
    # Hash sets and maps add in their iteration order: two equal ones
    # built in different orders may differ, which costs a walk, not a
    # wrong answer.
    if n in ('Vec','HashSet'):
        item=f'_item{d}'
        lines=fingerprint_of(item,args[0])
        return [f'into.add({expr}.count);', f'for (var {item} in {expr}) {{']+['    '+l for l in lines]+['}']
    if n in ('HashMap','BTreeMap'):
        k=f'_key{d}'; item=f'_item{d}'
        lines=fingerprint_of(k,args[0])+fingerprint_of(item,args[1])
        return [f'into.add({expr}.count);', f'for (var ({k}, {item}) in {expr}) {{']+['    '+l for l in lines]+['}']
    if n=='tuple':
        names=[f'_t{d}_{i}' for i in range(len(args))]
        out=[f'var ({", ".join(names)}) = {expr};']
        for i,a in enumerate(args):
            out+=fingerprint_of(names[i],a)
        return out
    if n=='String': return [f'into.add_text({expr});']
    if n=='bool': return [f'into.add({expr} ? 1 : 0);']
    if n=='f64': return [f'into.add_text($"{{{expr}}}");']
    if n in PRIM: return [f'into.add({expr} as ulong);']
    if n.startswith('ast::'):
        # The parser's nodes: sema never changes them.
        return []
    return [f'{expr}.fingerprint(into);']

CCOUNTER=[0]
def copy_of(expr, tp):
    """Returns (setup_lines, value_expr) for a deep copy of expr."""
    n,args=tp
    CCOUNTER[0]+=1
    d=CCOUNTER[0]
    v=f'_c{d}'
    if n=='Box': return copy_of(expr,args[0])
    if n=='Option':
        lines,val=copy_of(f'{expr}.value()',args[0])
        if not lines and val==f'{expr}.value()':
            return [], expr
        inner=pep(args[0],False)
        out=[f'var {v} = Optional<{inner}>.Empty;', f'if ({expr}.is_value()) {{']+['    '+l for l in lines]+[f'    {v} = Optional<{inner}>.Value({val});','}']
        return out, v
    if n in ('Vec','HashSet'):
        item=f'_item{d}'
        lines,val=copy_of(item,args[0])
        if not lines and val==item:
            return [], f'{expr}.copy()'
        out=[f'var {v} = {pep(tp)}();', f'for (var {item} in {expr}) {{']+['    '+l for l in lines]+[f'    {v}.{"append" if n=="Vec" else "insert"}({val});','}']
        return out, v
    if n in ('HashMap','BTreeMap'):
        k=f'_key{d}'; item=f'_item{d}'
        lines,val=copy_of(item,args[1])
        out=[f'var {v} = {pep(tp)}();', f'for (var ({k}, {item}) in {expr}) {{']+['    '+l for l in lines]+[f'    {v}[{k}] = {val};','}']
        return out, v
    if n=='tuple':
        names=[f'_t{d}_{i}' for i in range(len(args))]
        out=[f'var ({", ".join(names)}) = {expr};']
        vals=[]
        for i,a in enumerate(args):
            lines,val=copy_of(names[i],a)
            out+=lines; vals.append(val)
        return out, '('+', '.join(vals)+')'
    if n in PRIM or n in ('String','Loc') or n.startswith('ast::') or is_unit_enum(n):
        return [], expr
    return [], f'{expr}.copy()'

def doc_lines(text, indent):
    return [indent+'## '+text]

out=[]
emit=out.append

# keep the reachable ones only
reach=set();stack=['Module']
while stack:
    n=stack.pop()
    if n in reach or n not in items: continue
    reach.add(n)
    it=items[n]
    ts=[]
    if it['kind']=='struct': ts=[f['type'] for f in it['fields'] if not f['skip']]
    elif it['kind']=='tuple_struct': ts=it['fields']
    elif it['kind']=='enum':
        for vv in it['variants']:
            if vv['kind']=='struct': ts+=[f['type'] for f in vv['fields'] if not f['skip']]
            elif vv['kind']=='tuple': ts+=vv['types']
    for t in ts:
        for w in re.findall(r'[A-Za-z_][\w:]*',strip_path(t)):
            if not w.startswith('ast::'): stack.append(w)

# In-memory fields `copy()` leaves out, with their documentation.
NOT_COPIED = {
    'body_origin': [
        '## In memory only, and not kept by `copy()`: the body as the record',
        "## it was read from wrote it, which hashing a delta's base or an own",
        '## interface uses in place of the body, decoded or not: checked',
        "## bodies don't change, and decoding one is no change. A copy, such",
        '## as a specialization, gets a body of its own.',
    ],
}

def gen_struct(name, fields, doc, internal=()):
    lines=[]
    lines.append(f'## {doc}')
    lines.append(f'export struct {name} {{')
    for f in internal:
        if f['name'] in NOT_COPIED:
            lines += ['    ' + l for l in NOT_COPIED[f['name']]]
        else:
            lines.append(f'    ## In memory only: kept by `copy()`, not fingerprinted, written as')
            lines.append(f'    ## JSON or recorded.')
        lines.append(f'    var {f["name"]}: {f["pep"]} = {f["default"]};')
    required=[]
    optional=[]
    for f in fields:
        if f['skip']: continue
        tp=parse_type(f['type'])
        d=default_of(tp)
        t=pep(tp)
        lines.append(f'    var {fname(f["name"])}: {t};')
        if d is None:
            required.append((f,t,d))
        else:
            optional.append((f,t,d))
    lines.append('')
    params=', '.join([f'{fname(f["name"])}: {t}' for f,t,d in required]+[f'{fname(f["name"])}: {t} = {d}' for f,t,d in optional])
    lines.append(f'    construct({params}) {{')
    for f,t,d in required+optional:
        lines.append(f'        this.{fname(f["name"])} = {fname(f["name"])};')
    lines.append('    }')
    lines.append('')
    lines.append('    ## Returns a deep copy, which shares only locations and AST nodes.')
    lines.append(f'    copy(): {name} {{')
    vals=[]
    for f in fields:
        if f['skip']: continue
        setup,val=copy_of(f'this.{fname(f["name"])}',parse_type(f['type']))
        lines+=['        '+l for l in setup]
        vals.append(f'{fname(f["name"])} = {val}')
    if internal:
        lines.append(f'        var _copy = {name}({", ".join(vals)});')
        for f in internal:
            if f['name'] not in NOT_COPIED:
                lines.append(f'        _copy.{f["name"]} = this.{f["name"]};')
        lines.append('        return _copy;')
    else:
        lines.append(f'        return {name}({", ".join(vals)});')
    lines.append('    }')
    lines.append('')
    lines.append('    ## Adds this to `into`: equal values add the same.')
    lines.append('    ##')
    lines.append('    ## @param into the fingerprint')
    lines.append('    fingerprint(into: Fingerprint) {')
    lines.append(f'        into.add_text("{name}");')
    for f in fields:
        if f['skip']: continue
        lines+=['        '+l for l in fingerprint_of(f'this.{fname(f["name"])}',parse_type(f['type']))]
    lines.append('    }')
    lines.append('')
    lines.append('    to_json(): JsonValue {')
    lines.append('        var out = JsonValue.object();')
    for f in fields:
        if f['skip']: continue
        tp=parse_type(f['type'])
        setup,val=to_json(f'this.{fname(f["name"])}',tp)
        lines+=['        '+l for l in setup]
        lines.append(f'        out["{f["name"]}"] = {val};')
    lines.append('        return out;')
    lines.append('    }')
    lines.append('}')
    return lines

blocks=[]
for name in [k for k in items if k in reach]:
    it=items[name]
    if it['kind']=='struct':
        blocks.append(gen_struct(name,it['fields'],f'`{name}`, a type of the sema model.',it.get('internal',())))
    elif it['kind']=='enum':
        lines=[f'## `{name}`, a type of the sema model.', f'export enum {name} {{']
        extra=[]
        for vv in it['variants']:
            if vv['kind']=='unit':
                lines.append(f'    {vv["name"]},')
            elif vv['kind']=='tuple':
                if len(vv['types'])==1:
                    lines.append(f'    {vv["name"]}(value: {pep(parse_type(vv["types"][0]))}),')
                else:
                    ps=', '.join(f'v{i}: {pep(parse_type(t))}' for i,t in enumerate(vv['types']))
                    lines.append(f'    {vv["name"]}({ps}),')
            else:
                sname=vv['name']+name
                lines.append(f'    {vv["name"]}(node: {sname}),')
                extra.append(gen_struct(sname,vv['fields'],f'The fields of `{name}.{vv["name"]}`.'))
        lines.append('')
        lines.append('    ## Adds this to `into`: equal values add the same.')
        lines.append('    ##')
        lines.append('    ## @param into the fingerprint')
        lines.append('    fingerprint(into: Fingerprint) {')
        lines.append('        match (this) {')
        for i,vv in enumerate(it['variants']):
            if vv['kind']=='unit':
                lines.append(f'            {vv["name"]} => {{')
                lines.append(f'                into.add({i});')
            elif vv['kind']=='tuple':
                ns=['value'] if len(vv['types'])==1 else [f'v{j}' for j in range(len(vv['types']))]
                lines.append(f'            {vv["name"]}({", ".join(ns)}) => {{')
                lines.append(f'                into.add({i});')
                for nn,t in zip(ns,vv['types']):
                    lines+=['                '+l for l in fingerprint_of(nn,parse_type(t))]
            else:
                lines.append(f'            {vv["name"]}(node) => {{')
                lines.append(f'                into.add({i});')
                lines.append('                node.fingerprint(into);')
            lines.append('            }')
        lines.append('        }')
        lines.append('    }')
        lines.append('')
        if all(v['kind']=='unit' for v in it['variants']):
            lines.append('    to_json(): JsonValue {')
            lines.append('        match (this) {')
            for vv in it['variants']:
                lines.append(f'            {vv["name"]} => {{')
                lines.append(f'                return JsonValue.String("{vv["name"]}");')
                lines.append('            }')
            lines.append('        }')
            lines.append('    }')
        else:
            lines.append('    ## Returns a deep copy, which shares only locations and AST nodes.')
            lines.append(f'    copy(): {name} {{')
            lines.append('        match (this) {')
            for vv in it['variants']:
                if vv['kind']=='unit':
                    lines.append(f'            {vv["name"]} => {{')
                    lines.append('                return this;')
                elif vv['kind']=='tuple':
                    ns=['value'] if len(vv['types'])==1 else [f'v{i}' for i in range(len(vv['types']))]
                    lines.append(f'            {vv["name"]}({", ".join(ns)}) => {{')
                    vals=[]
                    for nn,t in zip(ns,vv['types']):
                        setup,val=copy_of(nn,parse_type(t))
                        lines+=['                '+l for l in setup]
                        vals.append(val)
                    lines.append(f'                return {name}.{vv["name"]}({", ".join(vals)});')
                else:
                    lines.append(f'            {vv["name"]}(node) => {{')
                    lines.append(f'                return {name}.{vv["name"]}(node.copy());')
                lines.append('            }')
            lines.append('        }')
            lines.append('    }')
            lines.append('')
            lines.append('    to_json(): JsonValue {')
            lines.append('        match (this) {')
            for vv in it['variants']:
                if vv['kind']=='unit':
                    lines.append(f'            {vv["name"]} => {{')
                    lines.append(f'                return JsonValue.String("{vv["name"]}");')
                elif vv['kind']=='tuple' and len(vv['types'])==1:
                    lines.append(f'            {vv["name"]}(value) => {{')
                    setup,val=to_json('value',parse_type(vv['types'][0]))
                    lines+=['                '+l for l in setup]
                    lines.append(f'                return _tagged("{vv["name"]}", {val});')
                elif vv['kind']=='tuple':
                    ns=[f'v{i}' for i in range(len(vv['types']))]
                    lines.append(f'            {vv["name"]}({", ".join(ns)}) => {{')
                    lines.append('                var items = JsonValue.array();')
                    for i,t in enumerate(vv['types']):
                        setup,val=to_json(ns[i],parse_type(t),i+1)
                        lines+=['                '+l for l in setup]
                        lines.append(f'                items.append({val});')
                    lines.append(f'                return _tagged("{vv["name"]}", items);')
                else:
                    lines.append(f'            {vv["name"]}(node) => {{')
                    lines.append(f'                return _tagged("{vv["name"]}", node.to_json());')
                lines.append('            }')
            lines.append('        }')
            lines.append('    }')
        lines.append('}')
        blocks.append(lines)
        blocks+=extra
    elif it['kind']=='tuple_struct':
        print('TUPLE STRUCT', name, file=sys.stderr)

header='''## The sema model: the tree the builder makes of the linked program and
## the passes rewrite. Each enum variant with named fields holds a struct of
## its own (`SymbolRefExpression` for `Expression.SymbolRef`), so a pass can
## change a node's fields in place. Each type's `to_json()` writes it as
## `pep-build --emit-model` prints it.
##
## The fields declared here are the model; the rest of each type is
## generated from them: change a type's fields, then run
## `scripts/gen-sema-model.py` and `scripts/gen-sema-record.py`.

import compiler.ast;
import json;
import [JsonValue] from json;
import [Fingerprint] from "fingerprint";
import [Loc] from "loc";
import [UnitDecls, PendingBody] from "pending";

'''
footer='''
## The one key of the object `unsigned_json` makes for a value too large
## for `JsonValue.Integer`; `canonical_json` writes that object as the
## value's digits. A key, not a string prefix: the model's strings hold
## the program's text, but its keys are field names and identifiers (#821).
export const UNSIGNED_MARK = "\\u{1}unsigned";

## Returns `value` as JSON: an integer, or for one past `long`'s range (a
## `WithSubject` id), an object holding its digits under `UNSIGNED_MARK`.
##
## @param value the value
## @returns the JSON
export unsigned_json(value: ulong): JsonValue {
    if (value <= 9223372036854775807) {
        return JsonValue.Integer(value as long);
    }
    return _tagged(UNSIGNED_MARK, JsonValue.String($"{value}"));
}

_tagged(name: String, value: JsonValue): JsonValue {
    var out = JsonValue.object();
    out[name] = value;
    return out;
}
'''
text=header+'\n\n'.join('\n'.join(b) for b in blocks)+'\n'+footer
if __name__ == '__main__':
    open(sys.argv[1],'w').write(text)
    print(len(blocks),'blocks', file=sys.stderr)
