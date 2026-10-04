#!/usr/bin/env python3
# Generates tools/compiler/sema/model.pep, the sema model in Pepper, from
# crates/pepper-sema/src/model.rs and type_name.rs: every type the Rust
# `Module` reaches, with a constructor, a deep `copy()` and a `to_json()`
# that writes what serde writes. Run it after changing the Rust model, then
# format the result:
#
#   python3 scripts/gen-sema-model.py tools/compiler/sema/model.pep
#   target/release/pep-fmt -w tools/compiler/sema/model.pep

import json, os, re, sys

# ---- A small reader of Rust struct and enum declarations.

def strip_comments(src):
    out=[]
    for line in src.split('\n'):
        s=line.strip()
        if s.startswith('//'):
            out.append('')
            continue
        # strip trailing // comments not in strings (good enough)
        i=line.find('//')
        if i>=0 and line.count('"',0,i)%2==0:
            line=line[:i]
        out.append(line)
    return '\n'.join(out)

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

def match_brace(s,i):
    # s[i] is opening
    o=s[i]; c={'{':'}','(':')','[':']'}[o]; d=0
    for j in range(i,len(s)):
        if s[j]==o: d+=1
        elif s[j]==c:
            d-=1
            if d==0: return j
    raise Exception('unbalanced')

def parse_fields(body):
    fields=[]
    for part in split_top(body):
        attrs=re.findall(r'#\[(.*?)\]\s*',part)
        part=re.sub(r'#\[.*?\]\s*','',part).strip()
        part=re.sub(r'^pub(\(crate\))?\s+','',part)
        name,ty=part.split(':',1)
        fields.append({'name':name.strip(),'type':' '.join(ty.split()),'skip':any('serde(skip' in a for a in attrs)})
    return fields

def parse(src):
    src=strip_comments(src)
    items={}
    for m in re.finditer(r'#\[derive\(([^)]*)\)\]\s*((?:#\[[^\]]*\]\s*)*)pub\s+(struct|enum)\s+(\w+)(<[^>{(]*>)?',src):
        derives=m.group(1)
        kind=m.group(3); name=m.group(4)
        ser='Serialize' in derives
        i=m.end()
        while src[i] in ' \n': i+=1
        if src[i]=='{':
            j=match_brace(src,i); body=src[i+1:j]
        elif src[i]=='(':
            j=match_brace(src,i); body=src[i+1:j]
            items[name]={'kind':'tuple_struct','fields':[re.sub(r'^pub\s+','',t) for t in split_top(body)],'ser':ser}
            continue
        elif src[i]==';':
            items[name]={'kind':'unit_struct','ser':ser};continue
        else:
            continue
        if kind=='struct':
            items[name]={'kind':'struct','fields':parse_fields(body),'ser':ser}
        else:
            variants=[]
            for part in split_top(body):
                part=re.sub(r'#\[.*?\]\s*','',part).strip()
                vm=re.match(r'(\w+)\s*(.*)$',part,re.S)
                vname=vm.group(1); rest=vm.group(2).strip()
                if rest.startswith('{'):
                    variants.append({'name':vname,'kind':'struct','fields':parse_fields(rest[1:-1])})
                elif rest.startswith('('):
                    variants.append({'name':vname,'kind':'tuple','types':[' '.join(t.split()) for t in split_top(rest[1:-1])]})
                else:
                    variants.append({'name':vname,'kind':'unit'})
            items[name]={'kind':'enum','variants':variants,'ser':ser}
    return items

# ---- The generator.

ROOT=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','crates','pepper-sema','src')+os.sep
items={}
for f in ['model.rs','type_name.rs']:
    for k,v in parse(open(ROOT+f).read()).items():
        items[k]=v

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
    if n in PRIM: return [], f'JsonValue.Integer({expr} as long)'
    return [], f'{expr}.to_json()'


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

def gen_struct(name, fields, doc):
    lines=[]
    lines.append(f'## {doc}')
    lines.append(f'export struct {name} {{')
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
    lines.append(f'        return {name}({", ".join(vals)});')
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
        blocks.append(gen_struct(name,it['fields'],f'`{name}` in `model.rs`.'))
    elif it['kind']=='enum':
        lines=[f'## `{name}` in `model.rs`.', f'export enum {name} {{']
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
                extra.append(gen_struct(sname,vv['fields'],f'The fields of `{name}::{vv["name"]}`.'))
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

header='''## The sema model: `crates/pepper-sema/src/model.rs` and `type_name.rs` in
## Pepper, the tree the builder makes of the linked program and the passes
## rewrite. Each Rust enum variant with named fields holds a struct of its
## own (`SymbolRefExpression` for `Expression::SymbolRef`), so a pass can
## change a node's fields in place. Each type's `to_json()` writes what
## serde writes for the Rust type.

import compiler.ast;
import json;
import [JsonValue] from json;
import [Loc] from "loc";

'''
footer='''
_tagged(name: String, value: JsonValue): JsonValue {
    var out = JsonValue.object();
    out[name] = value;
    return out;
}
'''
text=header+'\n\n'.join('\n'.join(b) for b in blocks)+'\n'+footer
open(sys.argv[1],'w').write(text)
print(len(blocks),'blocks', file=sys.stderr)
