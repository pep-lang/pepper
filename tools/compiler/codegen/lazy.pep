## Empty Arrays are null (#652): the `[__Lazy]` half of code generation. An
## object of a `[__Lazy]`
## struct (`Array<T>`) is null while it is empty, until a place holding it
## is written through or shared. This file finds the reads that may leave
## a local null because nothing follows them (`final_reads_of`), fills a
## place a read would share (`lazy_place`, `materialize`), and makes the
## null side of each (`fill_lazy`, `join_lazy`, `lazy_base`).

import compiler.ast;
import llvm;
import compiler.sema;
import [
    BinaryOp, Block, Expression, FunctionDef, Rewriter, rewrite_expression, Statement, SymbolRefExpression, VariableDef
] from compiler.sema;
import "address";
import "calls";
import "checks";
import "expressions";
import "functions";
import [Generator] from "generator";
import "generator";
import "globals";
import "operators";
import "ops";
import "refs";
import "simd";
import "traits";
import "types";

## The two sides of a null check on a `[__Lazy]` reference (`fill_lazy`):
## the block that branched, the join block, and the object made on the
## null side.
export struct LazyFill {
    var from: llvm.BasicBlock;
    var done: llvm.BasicBlock;
    var made: llvm.Value;

    construct(from: llvm.BasicBlock, done: llvm.BasicBlock, made: llvm.Value) {
        this.from = from;
        this.done = done;
        this.made = made;
    }
}

## Collects every variable read of the expressions it walks, in the order
## `rewrite_expression` visits them: each before what it contains.
struct _SymbolRefs {
    var found: SymbolRefExpression[] = Array<SymbolRefExpression>();

    construct() {}

    rewrite(e: Expression): Expression {
        if (e is SymbolRef(node)) {
            found.append(node);
        }
        return e;
    }
}

extend _SymbolRefs with Rewriter;

## The variable reads in `expr`, in visiting order.
_expression_refs(expr: Expression): SymbolRefExpression[] {
    var refs = _SymbolRefs();
    rewrite_expression(expr, refs);
    return refs.found;
}

## Adds the variable reads in `statement` to `refs`, in visiting order (a
## condition before its blocks; `static` blocks are expanded before
## codegen).
_statement_refs(statement: Statement, refs: _SymbolRefs) {
    match (statement) {
        Expression(e) => {
            rewrite_expression(e, refs);
        }
        Block(inner) => {
            for (var item in inner.items) {
                _statement_refs(item, refs);
            }
        }
        Declaration(declaration) => {
            if (declaration is Variable(var_def)) {
                if (var_def.default.is_value()) {
                    rewrite_expression(var_def.default.value(), refs);
                }
            }
        }
        Branch(branch) => {
            rewrite_expression(branch.condition, refs);
            _statement_refs(Statement.Block(branch.if_block), refs);
            if (branch.else_block.is_value()) {
                _statement_refs(Statement.Block(branch.else_block.value()), refs);
            }
        }
        While(wh) => {
            rewrite_expression(wh.condition, refs);
            _statement_refs(Statement.Block(wh.block), refs);
        }
        Return(ret) => {
            if (ret.expr.is_value()) {
                rewrite_expression(ret.expr.value(), refs);
            }
        }
        else => {}
    }
}

## Whether `expr` mentions `name`.
_mentions(name: String, expr: Expression): bool {
    for (var node in _expression_refs(expr)) {
        if (node.id == name) {
            return true;
        }
    }
    return false;
}

## Whether `statement` mentions `name` anywhere.
_mentions_statement(statement: Statement, name: String): bool {
    var refs = _SymbolRefs();
    _statement_refs(statement, refs);
    for (var node in refs.found) {
        if (node.id == name) {
            return true;
        }
    }
    return false;
}

## Whether `statement` holds a `break`, `continue` or `return`.
_jumps(statement: Statement): bool {
    match (statement) {
        LoopBreak(_), Return(_), Static(_) => {
            return true;
        }
        Block(inner) => {
            return _block_jumps(inner);
        }
        Branch(branch) => {
            return _block_jumps(branch.if_block)
                or (branch.else_block.is_value() and _block_jumps(branch.else_block.value()));
        }
        While(wh) => {
            return _block_jumps(wh.block);
        }
        else => {
            return false;
        }
    }
}

## Whether a statement of `block` jumps (`_jumps`).
_block_jumps(block: Block): bool {
    for (var statement in block.items) {
        if (_jumps(statement)) {
            return true;
        }
    }
    return false;
}

## Whether `statement` is `name = value` with no `name` in `value`.
_overwrites(statement: Statement, name: String): bool {
    if (statement is Expression(e)) {
        if (e is Binary(node)) {
            if (node.op == BinaryOp.Assign) {
                if (node.lhs is SymbolRef(target)) {
                    return target.id == name and !_mentions(name, node.rhs);
                }
            }
        }
    }
    return false;
}

## Adds to `finals` each read of a variable in `names` that the variable's
## next use overwrites: within one block, the read's statement (an
## expression or a declaration) holds the variable's last occurrence in it,
## and a later statement `name = value` (with no `name` in `value`) comes
## before any other use of it and any `break`, `continue` or `return`
## (`pending` in `t.comments = pending; pending = Array<Comment>();`).
_killed_reads(block: Block, names: HashSet<String>, finals: HashSet<SymbolRefExpression>) {
    for (var index in 0..block.items.count) {
        var statement = block.items[index];
        match (statement) {
            Block(inner) => {
                _killed_reads(inner, names, finals);
                continue;
            }
            Branch(branch) => {
                _killed_reads(branch.if_block, names, finals);
                if (branch.else_block.is_value()) {
                    _killed_reads(branch.else_block.value(), names, finals);
                }
                continue;
            }
            While(wh) => {
                _killed_reads(wh.block, names, finals);
                continue;
            }
            Expression(_) => {}
            Declaration(declaration) => {
                if (!(declaration is Variable(_))) {
                    continue;
                }
            }
            else => {
                continue;
            }
        }
        var refs = _SymbolRefs();
        _statement_refs(statement, refs);
        var last = HashMap<String, SymbolRefExpression>();
        for (var node in refs.found) {
            if (names.contains(node.id)) {
                last[node.id] = node;
            }
        }
        for (var entry in last) {
            var (name, read) = entry;
            for (var later in (index + 1)..block.items.count) {
                var next = block.items[later];
                if (_overwrites(next, name)) {
                    finals.insert(read);
                    break;
                }
                if (_mentions_statement(next, name) or _jumps(next)) {
                    break;
                }
            }
        }
    }
}

## A declaration seen twice in `_FinalReads.declared`.
const _DECLARED_TWICE: long = -1;

## The walk behind `final_reads_of`: each `[__Lazy]` variable's declaration
## depth and last occurrence, counting the loops around them.
struct _FinalReads {
    var generator: Generator;
    ## The number of loops around the statement being walked.
    var depth: long = 0;
    ## Name to the loop depth of its declaration, or `_DECLARED_TWICE`.
    var declared: HashMap<String, long> = HashMap<String, long>();
    ## Name to its last occurrence and that occurrence's loop depth.
    var last: HashMap<String, (SymbolRefExpression, long)> = HashMap<String, (SymbolRefExpression, long)>();

    construct(generator: Generator) {
        this.generator = generator;
    }

    ## Whether `var_def` holds a `[__Lazy]` struct.
    lazy(var_def: VariableDef): bool {
        return generator.is_lazy(var_def.ty.to_string());
    }

    declare(name: String) {
        if (declared.contains(name)) {
            declared[name] = _DECLARED_TWICE;
            return;
        }
        declared[name] = depth;
    }

    expression(expr: Expression) {
        for (var node in _expression_refs(expr)) {
            last[node.id] = (node, depth);
        }
    }

    block(statements: Block) {
        for (var statement in statements.items) {
            match (statement) {
                Expression(e) => {
                    expression(e);
                }
                Block(inner) => {
                    this.block(inner);
                }
                Declaration(declaration) => {
                    if (declaration is Variable(var_def)) {
                        if (var_def.default.is_value()) {
                            expression(var_def.default.value());
                        }
                        if (lazy(var_def)) {
                            declare(var_def.name);
                        }
                    }
                }
                Branch(branch) => {
                    expression(branch.condition);
                    this.block(branch.if_block);
                    if (branch.else_block.is_value()) {
                        this.block(branch.else_block.value());
                    }
                }
                While(wh) => {
                    depth += 1;
                    expression(wh.condition);
                    this.block(wh.block);
                    depth -= 1;
                }
                Return(ret) => {
                    if (ret.expr.is_value()) {
                        expression(ret.expr.value());
                    }
                }
                else => {}
            }
        }
    }
}

extend Generator {
    ## The reads of `function`'s `[__Lazy]` locals and parameters that no
    ## other use can follow: each one's last occurrence in `body`, when it is
    ## in no loop the variable's declaration is outside of. A name declared
    ## twice is left out. Copying such a read (an argument, an assignment's
    ## or a variable's value) is a move: no other name for the value
    ## remains, so an empty one need not be allocated. The reads are the
    ## `SymbolRef` nodes of `body` itself, by identity.
    final_reads_of(function: FunctionDef, body: Block): HashSet<SymbolRefExpression> {
        var finals = HashSet<SymbolRefExpression>();
        if (!any_lazy) {
            return finals;
        }
        var walk = _FinalReads(this);
        for (var parameter in function.parameters) {
            if (walk.lazy(parameter)) {
                walk.declare(parameter.name);
            }
        }
        walk.block(body);
        var names = HashSet<String>();
        for (var entry in walk.declared) {
            var (name, depth) = entry;
            if (depth != _DECLARED_TWICE) {
                names.insert(name);
            }
        }
        for (var entry in walk.last) {
            var (name, occurrence) = entry;
            var (read, depth) = occurrence;
            var declared = walk.declared.try_get(name);
            if (declared.is_value() and declared.value() == depth) {
                finals.insert(read);
            }
        }
        _killed_reads(body, names, finals);
        return finals;
    }

    ## Whether `expr` is a read of a `[__Lazy]` local that nothing follows
    ## (`final_reads_of`).
    is_final_read(expr: Expression): bool {
        if (expr is SymbolRef(node)) {
            return final_reads.contains(node);
        }
        return false;
    }

    ## Whether `ty` is a `[__Lazy]` struct (`Array<int>`).
    is_lazy(ty: String): bool {
        var desc = structs.try_get(ty);
        return desc.is_value() and desc.value().lazy;
    }

    ## Records which of `callee`'s `parameters` are `[__Reads]`.
    record_reads_params(callee: String, parameters: VariableDef[]) {
        var reads = Array<bool>();
        bool any = false;
        for (var p in parameters) {
            var marked = ast.has_attribute(p.attributes, sema.READS_ATTRIBUTE);
            reads.append(marked);
            any = any or marked;
        }
        if (any) {
            reads_params[callee] = reads;
        }
    }

    ## Whether parameter `index` of `callee` is `[__Reads]`.
    reads_param(callee: String, index: ulong): bool {
        var reads = reads_params.try_get(callee);
        return reads.is_value() and index < reads.value().count and reads.value()[index];
    }

    ## The type of `expr` when it is a place (a variable, a field, a buffer
    ## slot) of a `[__Lazy]` struct type, which a read may have to fill.
    lazy_place(expr: Expression): String? {
        if (!any_lazy) {
            return Optional<String>.Empty;
        }
        bool place = false;
        match (expr) {
            # A variable, not a type literal (`File` in `File.open(p)`).
            SymbolRef(node) => {
                place = frame.find_local(node.id).is_value() or global_addrs.contains(node.id);
            }
            Index(_), ArrayIndex(_) => {
                place = true;
            }
            MemberRef(node) => {
                var owner = struct_name_of(node.lhs);
                if (!owner.is_value()) {
                    place = true;
                } else if (tuples.contains(owner.value())) {
                    place = false;
                } else if (values.contains(owner.value())) {
                    place = is_value_place(node.lhs);
                } else {
                    place = true;
                }
            }
            else => {}
        }
        if (!place) {
            return Optional<String>.Empty;
        }
        var ty = value_sema_type(expr);
        if (!ty.is_value() or !is_lazy(ty.value())) {
            return Optional<String>.Empty;
        }
        return ty;
    }

    ## Whether the assignment target `lhs` is a field of a tuple or a
    ## `[Value]` struct, which its copies hold bitwise.
    stores_into_value(lhs: Expression): bool {
        if (lhs is MemberRef(node)) {
            var owner = struct_name_of(node.lhs);
            return owner.is_value() and (tuples.contains(owner.value()) or values.contains(owner.value()));
        }
        return false;
    }

    ## Reads the place `expr` of `[__Lazy]` type `ty`, first storing a new
    ## empty object into it when it holds null. A read that reaches here
    ## writes through the reference or shares it, so every name for the
    ## place must see one object from now on.
    materialize(expr: Expression, ty: String): Result<llvm.Value> {
        var address = codegen_lvalue(expr)?;
        var held = builder.load(context.pointer_type(), address.ptr, "lazy");
        var fill = fill_lazy(held, ty)?;
        builder.store(fill.made, address.ptr);
        return join_lazy(held, fill);
    }

    ## Branches on whether `held` (of `[__Lazy]` type `ty`) is null and, on
    ## the null side, constructs an empty `ty`, leaving the builder there so
    ## the caller can store it; `join_lazy` joins the two sides.
    fill_lazy(held: llvm.Value, ty: String): Result<LazyFill> {
        if (!frame.function.is_value()) {
            return fail<LazyFill>("no function");
        }
        var function = frame.function.value();
        var from = builder.insert_block();
        var make = context.append_block(function, "lazy_make");
        var done = context.append_block(function, "lazy_done");
        var is_null = builder.is_null(held, "lazy_null");
        builder.conditional_branch(is_null, make, done);
        builder.position_at_end(make);
        var outer = making_lazy;
        making_lazy = true;
        var made = codegen_call(ty, Array<Expression>());
        making_lazy = outer;
        return Result<LazyFill>.ok(LazyFill(from, done, made?));
    }

    ## Joins the sides `fill_lazy` opened: the object `held` was, or the one
    ## made in its place.
    join_lazy(held: llvm.Value, fill: LazyFill): Result<llvm.Value> {
        var made_in = builder.insert_block();
        builder.branch(fill.done);
        builder.position_at_end(fill.done);
        var phi = builder.phi(context.pointer_type(), "lazy_object");
        phi.add_incoming([held, fill.made], [fill.from, made_in]);
        return Result<llvm.Value>.ok(phi);
    }

    ## `fill_lazy` and `join_lazy` together: `held`, or a new empty `ty`
    ## when it is null, for a temporary no place holds.
    filled(held: llvm.Value, ty: String): Result<llvm.Value> {
        var fill = fill_lazy(held, ty)?;
        return join_lazy(held, fill);
    }

    ## The object a field read through `object` (of `[__Lazy]` type `ty`)
    ## reads: `object`, or when it is null a zeroed private constant of the
    ## struct's layout (`Array<int>.__empty`), whose fields read as an empty
    ## object's.
    lazy_base(ty: String, object: llvm.Value): Result<llvm.Value> {
        var desc = structs.try_get(ty);
        if (!desc.is_value()) {
            return fail<llvm.Value>($"not a struct: {ty}");
        }
        var layout = desc.value().llvm_type;
        var name = $"{ty}.__empty";
        var existing = ir.global(name);
        llvm.Value empty;
        if (existing.is_value()) {
            empty = existing.value();
        } else {
            empty = ir.add_global(layout, name);
            empty.set_initializer(layout.zero());
            empty.set_global_constant(true);
            empty.set_linkage(llvm.Linkage.Private);
            # `unnamed_addr`.
            empty.set_unnamed_address(2);
        }
        var is_null = builder.is_null(object, "lazy_null");
        return Result<llvm.Value>.ok(builder.select(is_null, empty, object, "lazy_base"));
    }
}
