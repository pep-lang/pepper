## Lowering `match`. Each arm test
## becomes `==` tests on the `match`'s subject (a value enum's case value,
## a reference enum's tag, a literal), a binding reads the payload field of
## its case, and each `match` is checked to handle every value of what it
## matches: by cases, by integer ranges, and for patterns nested in a
## case's values or a tuple's elements by the usefulness check of
## Maranget's "Warnings for pattern matching".

import [Diagnostic, Location] from compiler.diagnostic;
import [integer_range, payload_field, TAG_FIELD] from "builder";
import [unit_decls] from "checked";
import "common";
import "confinement";
import [install_traits, is_trait, reference_cases] from "enums";
import [Loc] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Branch,
    CaseValue,
    CasePattern,
    CastExpression,
    CastKind,
    ElementName,
    EnumCaseDef,
    EnumDef,
    Expression,
    FromTraitExpression,
    FunctionCallExpression,
    FunctionDef,
    MatchArmTest,
    MatchSite,
    MemberRefExpression,
    Module,
    Statement,
    StringLiteralExpression,
    SymbolRefExpression,
    TernaryExpression,
    TypeName,
    VariableDef
] from "model";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [is_integral_name, replace_map] from "type_name";
import [Rewriter, rewrite_block, rewrite_children, rewrite_expression] from "walk";

## Turns each `match` arm test into tests on the `match`'s subject, and
## checks each `match` handles every value. Runs once every type is final;
## generic bodies are skipped (their specializations are lowered in their
## place). An `else` nothing reaches is a warning, kept in `state.notes`.
##
## @param module the model
## @param state the passes' state, which takes the error
export lower_matches(module: Module, state: PassState) {
    # A checked declaration was walked with its unit (its body is stashed).
    var own = unit_decls(module);
    var lowering = _MatchLowering(module, state);
    var table = StructTable(module, memo = state.trait_types_memo());
    install_traits(module, state);
    var bodies = Array<_MatchBody>();
    for (var st in own.structs) {
        var generic_base = _is_generic_base(st);
        var current = Optional<TypeName>.Value(st.ty);
        var methods = Array<FunctionDef>();
        methods.append_all(st.method_members);
        methods.append_all(st.generic_methods);
        methods.append_all(st.constructors);
        methods.append(st.destructor);
        methods.append(st.acquire);
        methods.append(st.release);
        for (var m in methods) {
            if (!generic_base and !m.is_generic_func and m.body.is_value()) {
                bodies.append(_MatchBody(m, current));
            }
        }
    }
    for (var f in own.functions) {
        if (!f.is_generic_func and f.body.is_value()) {
            bodies.append(_MatchBody(f, Optional<TypeName>.Empty));
        }
    }
    var warnings = Array<Diagnostic>();
    for (var body in bodies) {
        var block = body.function.body.value();
        _check_arm_types(block, table, body.current, body.function.parameters, state);
        # Per body: a generic function's specializations each hold a copy
        # of its `match`es.
        lowering.coverage = HashMap<ulong, _Coverage>();
        lowering.subjects = HashMap<String, TypeName>();
        lowering.block(block);
        var ids = Array<ulong>();
        for (var (id, _) in lowering.coverage) {
            ids.append(id);
        }
        ids.sort((a: ulong, b: ulong) => a < b ? -1 : (a > b ? 1 : 0));
        for (var id in ids) {
            var warning = lowering.check_exhaustive(lowering.coverage[id]);
            if (warning.is_value() and !_seen_at(warnings, warning.value())) {
                warnings.append(warning.value());
            }
        }
    }
    state.notes.append_all(warnings);
}

_seen_at(warnings: Diagnostic[], w: Diagnostic): bool {
    for (var seen in warnings) {
        if (seen.location.is_value() == w.location.is_value()) {
            if (!w.location.is_value() or seen.location.value().same(w.location.value())) {
                return true;
            }
        }
    }
    return false;
}

struct _MatchBody {
    var function: FunctionDef;
    var current: TypeName?;

    construct(function: FunctionDef, current: TypeName?) {
        this.function = function;
        this.current = current;
    }
}

## What one `match` handles: each case (or literal) to the first pattern
## naming it.
struct _Coverage {
    var site: MatchSite? = Optional<MatchSite>.Empty;
    ## The enum matched (as shown) and its cases; for a literal match, the
    ## type matched and no cases.
    var matched_name: String? = Optional<String>.Empty;
    var matched_cases: EnumCaseDef[] = Array<EnumCaseDef>();
    ## The `match` is over a type with literal patterns.
    var literal: bool = false;
    var handled: HashMap<String, Loc> = HashMap<String, Loc>();
    ## For a `match` over an integer type: the values its unguarded literal
    ## and range patterns cover, as inclusive intervals.
    var intervals: Array<(long, long)> = Array<(long, long)>();
    ## For a `match` over a tuple: every pattern so far.
    var tuple: _TupleCoverage? = Optional<_TupleCoverage>.Empty;
    ## For a `match` over an enum: every unguarded pattern so far.
    var spaces: _TupleCoverage? = Optional<_TupleCoverage>.Empty;

    construct() {}
}

struct _TupleCoverage {
    var ty: TypeName;
    var domains: HashMap<String, Array<_DomainCase>>;
    var rows: Array<_Space> = Array<_Space>();

    construct(ty: TypeName, domains: HashMap<String, Array<_DomainCase>>) {
        this.ty = ty;
        this.domains = domains;
    }

    ## Each row as a one-column row.
    row_matrix(): Array<Array<_Space>> {
        var out = Array<Array<_Space>>();
        for (var r in rows) {
            out.append([r]);
        }
        return out;
    }
}

## A case of a type in a domain, with the types of the values it carries.
struct _DomainCase {
    var name: String;
    var types: TypeName[];

    construct(name: String, types: TypeName[]) {
        this.name = name;
        this.types = types;
    }
}

## The values a pattern covers, for exhaustiveness.
enum _Space {
    ## Every value: `_` or a name that binds.
    Any,
    ## One case with the spaces of the values it carries, or one literal.
    Case(name: String, args: _Space[]),
    ## A tuple of the element spaces.
    Tuple(elements: _Space[]),
}

_is_any_space(s: _Space): bool {
    match (s) {
        Any => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_spaces_equal(a: _Space[], b: _Space[]): bool {
    if (a.count != b.count) {
        return false;
    }
    ulong i = 0;
    while (i < a.count) {
        if (!_same_space(a[i], b[i])) {
            return false;
        }
        i += 1;
    }
    return true;
}

_same_space(a: _Space, b: _Space): bool {
    match (a) {
        Any => {
            return _is_any_space(b);
        }
        Case(name, args) => {
            match (b) {
                Case(other, other_args) => {
                    return name == other and _spaces_equal(args, other_args);
                }
                else => {
                    return false;
                }
            }
        }
        Tuple(elements) => {
            match (b) {
                Tuple(other) => {
                    return _spaces_equal(elements, other);
                }
                else => {
                    return false;
                }
            }
        }
    }
}

_all_any(spaces: _Space[]): bool {
    for (var s in spaces) {
        if (!_is_any_space(s)) {
            return false;
        }
    }
    return true;
}

_anys(count: ulong): _Space[] {
    var out = Array<_Space>();
    ulong i = 0;
    while (i < count) {
        out.append(_Space.Any);
        i += 1;
    }
    return out;
}

## A space as a witness shows it.
_space_text(s: _Space): String {
    match (s) {
        Any => {
            return "_";
        }
        Case(name, args) => {
            if (_all_any(args)) {
                return name;
            }
            var shown = Array<String>();
            for (var a in args) {
                shown.append(_space_text(a));
            }
            return $"{name}({", ".join(shown)})";
        }
        Tuple(elements) => {
            var shown = Array<String>();
            for (var e in elements) {
                shown.append(_space_text(e));
            }
            return $"({", ".join(shown)})";
        }
    }
}

## What a `match` is over: a value enum, a reference enum's cases, or a type
## matched by literals.
struct _Matched {
    ## 0: a value enum; 1: a reference enum; 2: a literal type.
    var kind: int;
    var enum_def: EnumDef? = Optional<EnumDef>.Empty;
    var ty: TypeName;
    var cases: EnumCaseDef[] = Array<EnumCaseDef>();
    var declared: Loc = Loc.none();

    construct(kind: int, ty: TypeName) {
        this.kind = kind;
        this.ty = ty;
    }

    is_literal(): bool {
        return kind == 2;
    }

    name(): String {
        return kind == 0 ? enum_def.value().name : _shown_type(ty);
    }

    names_case(name: String): bool {
        for (var c in cases) {
            if (c.name == name) {
                return true;
            }
        }
        return false;
    }
}

## A type `match` compares with literal patterns, other than `String` and
## `bool`: an integer or character type.
_is_integer_type(ty: TypeName): bool {
    return _is_literal_type(ty) and ty.name != "String" and ty.name != "bool";
}

## Whether the inclusive `intervals` together cover every integer from
## `low` to `high`.
_covers(intervals: Array<(long, long)>, low: long, high: long): bool {
    var sorted = intervals.copy();
    sorted.sort(_compare_intervals);
    var next = low;
    for (var (start, end) in sorted) {
        if (start > next) {
            break;
        }
        if (end >= high) {
            return true;
        }
        if (end + 1 > next) {
            next = end + 1;
        }
    }
    return next > high;
}

_compare_intervals(a: (long, long), b: (long, long)): int {
    var (a_start, a_end) = a;
    var (b_start, b_end) = b;
    if (a_start != b_start) {
        return a_start < b_start ? -1 : 1;
    }
    if (a_end != b_end) {
        return a_end < b_end ? -1 : 1;
    }
    return 0;
}

## The subject of a lowered `match` or `is` test, typed as `ty`.
_typed(subject: Expression, ty: TypeName): Expression {
    var out = subject.copy();
    match (out) {
        SymbolRef(node) => {
            node.ty = ty;
        }
        Subject(node) => {
            node.ty = ty;
        }
        else => {}
    }
    return out;
}

## `subject.__tag == case`, for a reference enum's object.
_tag_is(subject: Expression, c: EnumCaseDef, at: Loc): Expression {
    var tag = Expression.MemberRef(MemberRefExpression(subject.copy(), TAG_FIELD, at));
    return Expression.Binary(BinaryExpression(tag, Expression.IntLiteral(c.value), BinaryOp.Equal, at));
}

## The payload field a pattern's binding reads: `subject.Text.text`.
_case_field(subject: Expression, c: EnumCaseDef, index: ulong, at: Loc): Expression {
    var (name, _) = c.payload[index];
    return Expression.MemberRef(MemberRefExpression(subject.copy(), payload_field(c.name, name), at));
}

_either(condition: Expression?, next: Expression, op: BinaryOp, at: Loc): Expression {
    if (!condition.is_value()) {
        return next;
    }
    return Expression.Binary(BinaryExpression(condition.value(), next, op, at));
}

## The arm test a condition holds: `MatchArm(...)`, or the left side of a
## guarded arm's `MatchArm(...) && guard`.
_arm_test(condition: Expression): MatchArmTest? {
    match (condition) {
        MatchArm(test) => {
            return Optional<MatchArmTest>.Value(test);
        }
        Binary(node) => {
            if (node.op == BinaryOp.LogicalAnd) {
                if (node.lhs is MatchArm(test)) {
                    if (test.guarded) {
                        return Optional<MatchArmTest>.Value(test);
                    }
                }
            }
        }
        else => {}
    }
    return Optional<MatchArmTest>.Empty;
}

_is_no_match(e: Expression): bool {
    match (e) {
        NoMatch => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## The `match` keyword of a `match` expression chain that ends without an
## `else` arm.
_missing_else(chain: Expression): Loc? {
    Loc? keyword = Optional<Loc>.Empty;
    var at = chain;
    while (at is Ternary(node)) {
        if (!keyword.is_value()) {
            var test = _arm_test(node.condition);
            if (test.is_value()) {
                keyword = Optional<Loc>.Value(test.value().site.keyword);
            }
        }
        at = node.false_expr;
    }
    return _is_no_match(at) ? keyword : Optional<Loc>.Empty;
}

## A `match` expression without `else`, once its tests are lowered: the
## last arm's value stands on its own, so `test ? value : NoMatch` becomes
## `value`.
_drop_no_match(chain: Expression): Expression {
    if (chain is Ternary(top)) {
        if (_is_no_match(top.false_expr)) {
            return top.true_expr;
        }
        var parent = top;
        while (parent.false_expr is Ternary(node)) {
            if (_is_no_match(node.false_expr)) {
                parent.false_expr = node.true_expr;
                return chain;
            }
            parent = node;
        }
    }
    return chain;
}

## The type `resolve_implicit_types` gave the `Subject`s of the
## `WithSubject` numbered `id`.
_subject_type(body: Expression, id: ulong): TypeName? {
    var finder = _SubjectFinder(id);
    rewrite_expression(body, finder);
    return finder.found;
}

struct _SubjectFinder {
    var id: ulong;
    var found: TypeName? = Optional<TypeName>.Empty;

    construct(id: ulong) {
        this.id = id;
    }

    rewrite(e: Expression): Expression {
        if (!found.is_value()) {
            if (e is Subject(node)) {
                if (node.id == id) {
                    found = Optional<TypeName>.Value(node.ty);
                }
            }
        }
        return e;
    }
}

extend _SubjectFinder with Rewriter;

## A pattern as written, for messages.
_shown_pattern(p: CasePattern): String {
    if (p.literal.is_value() or p.elements.is_value()) {
        return p.case;
    }
    var out = p.qualifier.is_value() ? $"{p.qualifier.value().to_string()}.{p.case}" : p.case;
    if (p.bindings.is_value()) {
        var shown = Array<String>();
        for (var sub in p.bindings.value()) {
            shown.append(_shown_pattern(sub));
        }
        out = $"{out}({", ".join(shown)})";
    }
    return out;
}

## A typed subject path and the type of what it reads.
struct _TypedPath {
    var expr: Expression;
    var ty: TypeName;

    construct(expr: Expression, ty: TypeName) {
        this.expr = expr;
        this.ty = ty;
    }
}

## A case a binding may read from, with the binding's position there.
struct _Pick {
    var c: EnumCaseDef;
    var index: ulong;

    construct(c: EnumCaseDef, index: ulong) {
        this.c = c;
        this.index = index;
    }
}

## The result of an element test: failed after an error, or the test
## (none when the pattern matches every value).
struct _ElementTest {
    var failed: bool;
    var test: Expression?;

    construct(failed: bool, test: Expression?) {
        this.failed = failed;
        this.test = test;
    }
}

## The lowering of one body's `match`es.
struct _MatchLowering {
    var module: Module;
    var state: PassState;
    var enums: HashMap<String, EnumDef> = HashMap<String, EnumDef>();
    var subjects: HashMap<String, TypeName> = HashMap<String, TypeName>();
    var coverage: HashMap<ulong, _Coverage> = HashMap<ulong, _Coverage>();

    construct(module: Module, state: PassState) {
        this.module = module;
        this.state = state;
        for (var e in module.enums) {
            enums[e.name] = e;
        }
    }

    report(diagnostic: Diagnostic) {
        state.report(diagnostic);
    }

    # ── Statements ──

    block(b: Block) {
        var items = Array<Statement>();
        for (var s in b.items) {
            var lowered = statement(s);
            items.append(lowered);
            if (lowered is Declaration(declaration)) {
                if (declaration is Variable(variable)) {
                    items.append_all(declaration_after(variable));
                }
            }
        }
        b.items = items;
    }

    statement(s: Statement): Statement {
        match (s) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (variable.hidden and variable.name.starts_with("__match_")) {
                        subjects[variable.name] = variable.ty;
                    }
                    if (variable.default.is_value()) {
                        variable.default = Optional<Expression>.Value(rewrite(variable.default.value()));
                    }
                }
            }
            Block(inner) => {
                block(inner);
            }
            Expression(e) => {
                return Statement.Expression(rewrite(e));
            }
            Branch(branch) => {
                var test = _arm_test(branch.condition);
                if (test.is_value()) {
                    var cases = Array<String>();
                    var condition = lower_arm(test.value(), cases);
                    if (condition.is_value()) {
                        if (branch.condition is Binary(node)) {
                            node.lhs = condition.value();
                            node.rhs = rewrite(node.rhs);
                        } else {
                            branch.condition = condition.value();
                        }
                    }
                    # A bare element name that is a case binds nothing: drop
                    # the local the builder declared for it.
                    var kept = Array<Statement>();
                    for (var item in branch.if_block.items) {
                        if (!_declares_one_of(item, cases)) {
                            kept.append(item);
                        }
                    }
                    branch.if_block.items = kept;
                } else {
                    branch.condition = rewrite(branch.condition);
                }
                block(branch.if_block);
                if (branch.else_block.is_value()) {
                    block(branch.else_block.value());
                }
            }
            While(loop) => {
                loop.condition = rewrite(loop.condition);
                block(loop.block);
            }
            Return(ret) => {
                if (ret.expr.is_value()) {
                    ret.expr = Optional<Expression>.Value(rewrite(ret.expr.value()));
                }
            }
            else => {}
        }
        return s;
    }

    ## What follows a declaration in a lowered `match`: after the subject
    ## of a reference enum that is not `[Value]`, a check that it is not
    ## null; a binding's local gets the matched case's value.
    declaration_after(variable: VariableDef): Statement[] {
        var none = Array<Statement>();
        # A `[Value]` enum is never null.
        if (variable.hidden
            and variable.name.starts_with("__match_")
            and state.reference_enums.contains(variable.ty.name)
            and !state.is_value_struct(variable.ty.to_string())) {
            var message = $"match on a null '{_shown_type(variable.ty)}'";
            var not_null = Expression.Binary(
                BinaryExpression(
                    Expression.SymbolRef(SymbolRefExpression(variable.name, variable.ty, variable.loc)),
                    Expression.PointerLiteral,
                    BinaryOp.NotIdentical,
                    variable.loc
                )
            );
            var check = Expression.FunctionCall(
                FunctionCallExpression(
                    "_pep_assert",
                    [not_null, Expression.StringLiteral(StringLiteralExpression(message, true, variable.loc))],
                    variable.loc
                )
            );
            return [Statement.Expression(check)];
        }
        if (!variable.default.is_value()) {
            return none;
        }
        var initial = variable.default.value();
        if (!_is_case_value(initial)) {
            return none;
        }
        var value = _case_value_of(initial);
        var converted = trait_case_value(value);
        if (converted.is_value()) {
            variable.default = converted;
            return none;
        }
        var found = case_picks(value);
        if (!found.is_value()) {
            return none;
        }
        var (subject, picks) = found.value();
        var at = value.loc;
        if (picks.count == 1) {
            variable.default = Optional<Expression>.Value(_case_field(subject, picks[0].c, picks[0].index, at));
            return none;
        }
        # `var x; if (tag == A) { x = subject.A.x; } else if ... else { x = subject.Z.x; }`
        variable.default = Optional<Expression>.Empty;
        Block? chain = Optional<Block>.Empty;
        var i = picks.count;
        while (i > 0) {
            i -= 1;
            var pick = picks[i];
            var assign = Block(
                "",
                [
                    Statement.Expression(
                        Expression.Binary(
                            BinaryExpression(
                                Expression.SymbolRef(SymbolRefExpression(variable.name, variable.ty, at)),
                                _case_field(subject, pick.c, pick.index, at),
                                BinaryOp.Assign,
                                at
                            )
                        )
                    )
                ]
            );
            if (i + 1 == picks.count) {
                chain = Optional<Block>.Value(assign);
            } else {
                var branch = Branch(_tag_is(subject, pick.c, at), assign, chain);
                chain = Optional<Block>.Value(Block("", [Statement.Branch(branch)]));
            }
        }
        return chain.is_value() ? chain.value().items : none;
    }

    ## The typed subject a binding reads, and each case it may read from.
    case_picks(value: CaseValue): Optional<(Expression, Array<_Pick>)> {
        var none = Optional<(Expression, Array<_Pick>)>.Empty;
        var path = typed_path(value.subject);
        if (!path.is_value()) {
            return none;
        }
        var reference = reference_cases(state, path.value().ty);
        if (!reference.is_value()) {
            return none;
        }
        var (cases, _) = reference.value();
        var picks = Array<_Pick>();
        for (var choice in value.choices) {
            for (var c in cases) {
                if (c.name == choice.case) {
                    if (choice.index < c.payload.count) {
                        picks.append(_Pick(c, choice.index));
                    }
                    break;
                }
            }
        }
        return Optional<(Expression, Array<_Pick>)>.Value((path.value().expr, picks));
    }

    ## A `match`'s subject, or an element of it, with the subject typed,
    ## and the type of what it reads.
    typed_path(path: Expression): _TypedPath? {
        var none = Optional<_TypedPath>.Empty;
        match (path) {
            SymbolRef(node) => {
                var ty = subjects.try_get(node.id);
                if (!ty.is_value()) {
                    return none;
                }
                return Optional<_TypedPath>.Value(_TypedPath(_typed(path, ty.value()), ty.value()));
            }
            Subject(node) => {
                return Optional<_TypedPath>.Value(_TypedPath(path.copy(), node.ty));
            }
            # A case's value, the subject of a nested pattern.
            CaseValue(value) => {
                var inner = typed_path(value.subject);
                if (!inner.is_value() or value.choices.count == 0) {
                    return none;
                }
                var choice = value.choices[0];
                var reference = reference_cases(state, inner.value().ty);
                var types = _case_payload_types(state, inner.value().ty);
                if (!reference.is_value() or !types.is_value()) {
                    return none;
                }
                var (cases, _) = reference.value();
                ulong i = 0;
                while (i < cases.count and cases[i].name != choice.case) {
                    i += 1;
                }
                if (i >= cases.count or i >= types.value().count or choice.index >= types.value()[i].count) {
                    return none;
                }
                var value_type = types.value()[i][choice.index];
                if (choice.index >= cases[i].payload.count) {
                    return none;
                }
                return Optional<_TypedPath>.Value(
                    _TypedPath(_case_field(inner.value().expr, cases[i], choice.index, value.loc), value_type)
                );
            }
            MemberRef(node) => {
                var index = ulong.parse(node.name);
                if (!index.is_value()) {
                    return none;
                }
                var inner = typed_path(node.lhs);
                if (!inner.is_value()
                    or !inner.value().ty.is_tuple()
                    or index.value() >= inner.value().ty.sub_types.count) {
                    return none;
                }
                return Optional<_TypedPath>.Value(
                    _TypedPath(
                        Expression.MemberRef(MemberRefExpression(inner.value().expr, node.name, node.loc)),
                        inner.value().ty.sub_types[index.value()]
                    )
                );
            }
            else => {
                return none;
            }
        }
    }

    ## A binding's value in an arm over a trait value: the subject as the
    ## pattern's type.
    trait_case_value(value: CaseValue): Expression? {
        var none = Optional<Expression>.Empty;
        var path = typed_path(value.subject);
        if (!path.is_value() or !is_trait(state, path.value().ty) or value.choices.count == 0) {
            return none;
        }
        var target = value.choices[0].ty;
        if (!target.is_value()) {
            return none;
        }
        var found = _trait_target(state, path.value().ty, target.value(), value.loc);
        if (found.is_err()) {
            return none;
        }
        var (to, candidates) = found.value();
        return Optional<Expression>.Value(
            Expression.FromTrait(
                FromTraitExpression(path.value().expr, path.value().ty, to, candidates, false, value.loc)
            )
        );
    }

    ## A binding inside a `match` expression's arm value or guard: the
    ## payload field, or `?:` on the tag when alternatives bind it.
    lower_case_value(value: CaseValue): Expression? {
        var converted = trait_case_value(value);
        if (converted.is_value()) {
            return converted;
        }
        var found = case_picks(value);
        if (!found.is_value()) {
            return Optional<Expression>.Empty;
        }
        var (subject, picks) = found.value();
        if (picks.count == 0) {
            return Optional<Expression>.Empty;
        }
        var at = value.loc;
        var last = picks[picks.count - 1];
        var chain = _case_field(subject, last.c, last.index, at);
        var i = picks.count - 1;
        while (i > 0) {
            i -= 1;
            var pick = picks[i];
            chain = Expression.Ternary(
                TernaryExpression(_tag_is(subject, pick.c, at), _case_field(subject, pick.c, pick.index, at), chain)
            );
        }
        return Optional<Expression>.Value(chain);
    }

    # ── Expressions ──

    ## Lowers the `match` expressions and `is` tests in `e`, and the
    ## `match` statements inside closure literals it holds.
    rewrite(e: Expression): Expression {
        match (e) {
            ClosureLiteral(closure) => {
                var saved = subjects;
                subjects = subjects.copy();
                block(closure.body);
                subjects = saved;
                return e;
            }
            MatchArm(test) => {
                var lowered = lower_arm(test, Array<String>());
                return lowered.is_value() ? lowered.value() : Expression.BoolLiteral(false);
            }
            CaseValue(value) => {
                var lowered = lower_case_value(value);
                return lowered.is_value() ? lowered.value() : e;
            }
            WithSubject(subject) => {
                var ty = _subject_type(subject.body, subject.id);
                if (ty.is_value()
                    and state.reference_enums.contains(ty.value().name)
                    and !state.is_value_struct(ty.value().to_string())) {
                    subject.null_message = Optional<String>.Value($"match on a null '{_shown_type(ty.value())}'");
                }
                if (ty.is_value() and is_trait(state, ty.value())) {
                    var keyword = _missing_else(subject.body);
                    if (keyword.is_value()) {
                        var shown = _shown_type(ty.value());
                        report(
                            _error_at_known(
                                $"'match' on trait type '{shown}' needs an 'else' arm",
                                keyword.value()
                            ).with_note(
                                $"any struct may implement '{shown}', so no list of arms handles every value",
                                Optional<Location>.Empty
                            )
                        );
                        return e;
                    }
                }
                subject.subject = rewrite(subject.subject);
                subject.body = _drop_no_match(rewrite(subject.body));
                return e;
            }
            else => {
                return rewrite_children(e, this);
            }
        }
    }

    ## The tests one arm stands for, or none after reporting an error.
    ## `cases` receives each declared bare element name that turned out to
    ## be a case, whose local the caller drops.
    lower_arm(test: MatchArmTest, cases: String[]): Expression? {
        var condition = arm_condition(test, cases);
        if (!condition.is_value()) {
            return condition;
        }
        # The tests of nested patterns read a case's values.
        return Optional<Expression>.Value(rewrite_expression(condition.value(), _CaseValueLowering(this)));
    }

    coverage_of(site: MatchSite): _Coverage {
        var found = coverage.try_get(site.id);
        if (found.is_value()) {
            found.value().site = Optional<MatchSite>.Value(site);
            return found.value();
        }
        var entry = _Coverage();
        entry.site = Optional<MatchSite>.Value(site);
        coverage[site.id] = entry;
        return entry;
    }

    matched_of(ty: TypeName): _Matched? {
        var e = enums.try_get(ty.to_string());
        if (e.is_value()) {
            var out = _Matched(0, ty);
            out.enum_def = e;
            out.cases = e.value().cases;
            return Optional<_Matched>.Value(out);
        }
        if (_is_literal_type(ty)) {
            return Optional<_Matched>.Value(_Matched(2, ty));
        }
        var reference = reference_cases(state, ty);
        if (!reference.is_value()) {
            return Optional<_Matched>.Empty;
        }
        var (cases, declared) = reference.value();
        var out = _Matched(1, ty);
        out.cases = cases;
        out.declared = declared;
        return Optional<_Matched>.Value(out);
    }

    arm_condition(test: MatchArmTest, cases: String[]): Expression? {
        var none = Optional<Expression>.Empty;
        var ty = TypeName.auto();
        var subject_loc = Loc.none();
        match (test.subject) {
            SymbolRef(node) => {
                var found = subjects.try_get(node.id);
                ty = found.is_value() ? found.value() : TypeName.auto();
                subject_loc = node.loc;
            }
            Subject(node) => {
                ty = node.ty;
                subject_loc = node.loc;
            }
            else => {
                return none;
            }
        }
        var subject = _typed(test.subject, ty);
        var entry = coverage_of(test.site);
        if (is_trait(state, ty)) {
            return trait_arm(test, subject, ty, entry);
        }
        if (ty.is_tuple()) {
            return tuple_arm(test, subject, ty, subject_loc, entry, cases);
        }
        for (var p in test.patterns) {
            if (p.elements.is_value()) {
                var shown = ty.is_auto() ? "a value of an unknown type" : $"a value of '{_shown_type(ty)}'";
                report(
                    _error_at_known(
                        $"a tuple pattern cannot match {shown}", p.loc
                    ).with_note("the value matched is here", known_location(subject_loc))
                );
                return none;
            }
        }
        var found = matched_of(ty);
        if (!found.is_value()) {
            var shown = ty.is_auto() ? "an unknown type" : $"'{_shown_type(ty)}'";
            report(
                _error_at_known(
                    $"cannot match on a value of {shown}: 'match' needs an enum, an integer, 'char', 'bool' or 'String'",
                    subject_loc
                )
            );
            return none;
        }
        var matched = found.value();
        entry.matched_name = Optional<String>.Value(matched.name());
        entry.matched_cases = matched.cases;
        entry.literal = matched.is_literal();
        if (!entry.literal and !entry.spaces.is_value()) {
            var domains = HashMap<String, Array<_DomainCase>>();
            collect_domains(ty, domains);
            entry.spaces = Optional<_TupleCoverage>.Value(_TupleCoverage(ty, domains));
        }
        # Each bare name in a case's values, by location: whether it named a
        # case.
        var names = Array<(Loc, bool)>();
        Expression? condition = Optional<Expression>.Empty;
        for (var p in test.patterns) {
            # A pattern nested in a case's values covers part of the case.
            _Space? space = Optional<_Space>.Empty;
            bool partial = false;
            if (!entry.literal) {
                var s = space_of(p, ty);
                space = Optional<_Space>.Value(s);
                partial = true;
                if (s is Case(name, args)) {
                    partial = !_all_any(args);
                }
            }
            if (partial
                and !entry.handled.contains(p.case)
                and space.is_value()
                and entry.spaces.is_value()
                and !test.site.partial) {
                var spaces = entry.spaces.value();
                if (!useful(spaces.row_matrix(), [space.value()], [ty], spaces.domains).is_value()) {
                    report(
                        _error_at_known(
                            $"pattern '{_shown_pattern(p)}' is already handled", p.loc
                        ).with_note("the patterns before it match every value it does", Optional<Location>.Empty)
                    );
                    return none;
                }
            }
            var first = entry.handled.try_get(p.case);
            if (first.is_value()) {
                var what = p.literal.is_value() ? "value" : "case";
                report(
                    _error_at_known(
                        $"{what} '{p.case}' is already handled", p.loc
                    ).with_note("first handled here", known_location(first.value()))
                );
                return none;
            }
            Expression? equal = Optional<Expression>.Empty;
            if (matched.is_literal() and p.literal.is_value() and p.range and !_is_integer_type(matched.ty)) {
                report(
                    _error_at_known(
                        $"a range cannot match a value of '{_shown_type(matched.ty)}': ranges match integers and characters",
                        p.loc
                    ).with_note("the value matched is here", known_location(subject_loc))
                );
                return none;
            } else if (matched.is_literal() and p.literal.is_value()) {
                if (p.values.is_value() and _is_integer_type(matched.ty)) {
                    var (low, high) = p.values.value();
                    if (low > high) {
                        report(_error_at_known($"range '{p.case}' matches no value", p.loc));
                        return none;
                    }
                    if (_covers(entry.intervals, low, high)) {
                        report(
                            _error_at_known(
                                $"pattern '{p.case}' is already handled", p.loc
                            ).with_note("the patterns before it match every value it does", Optional<Location>.Empty)
                        );
                        return none;
                    }
                    if (!test.guarded) {
                        entry.intervals.append((low, high));
                    }
                }
                equal = Optional<Expression>.Value(p.literal.value().copy());
            } else if (matched.is_literal()) {
                report(
                    _error_at_known(
                        $"'{p.case}' is not a literal or a constant: a 'match' on '{_shown_type(matched.ty)}' takes literals, ranges and module-scope constants",
                        p.loc
                    )
                );
                return none;
            } else if (p.literal.is_value()) {
                var what = p.constant ? "a constant" : (p.range ? "a range" : "a literal");
                report(_error_at_known($"{what} cannot match a value of '{matched.name()}': name its cases", p.loc));
                return none;
            } else {
                equal = enum_test(p, matched, subject, subject_loc, names);
                if (!equal.is_value()) {
                    return none;
                }
            }
            # A guarded arm may not run, so it handles nothing.
            if (!test.guarded) {
                if (!partial) {
                    entry.handled[p.case] = p.loc;
                }
                if (space.is_value() and entry.spaces.is_value()) {
                    entry.spaces.value().rows.append(space.value());
                }
            }
            condition = Optional<Expression>.Value(_either(condition, equal.value(), BinaryOp.LogicalOr, p.loc));
        }
        if (!resolve_element_names(test, names, cases)) {
            return none;
        }
        return Optional<Expression>.Value(condition.is_value() ? condition.value() : Expression.BoolLiteral(false));
    }

    ## The test of an arm over a trait value: whether the value is one of
    ## the types its patterns name.
    trait_arm(test: MatchArmTest, subject: Expression, ty: TypeName, entry: _Coverage): Expression? {
        var none = Optional<Expression>.Empty;
        Expression? condition = Optional<Expression>.Empty;
        for (var p in test.patterns) {
            if (!p.ty.is_value() or p.literal.is_value() or p.elements.is_value()) {
                report(
                    _error_at_known(
                        $"a value of trait type '{_shown_type(ty)}' is matched by type: name a struct or trait, as in 'Circle(c)'",
                        p.loc
                    )
                );
                return none;
            }
            var found = _trait_target(state, ty, p.ty.value(), p.loc);
            if (found.is_err()) {
                report(found.error());
                return none;
            }
            var (to, candidates) = found.value();
            var key = to.to_string();
            var first = entry.handled.try_get(key);
            if (first.is_value()) {
                report(
                    _error_at_known(
                        $"type '{_shown_type(to)}' is already handled", p.loc
                    ).with_note("first handled here", known_location(first.value()))
                );
                return none;
            }
            if (!test.guarded) {
                entry.handled[key] = p.loc;
            }
            var is = Expression.FromTrait(FromTraitExpression(subject.copy(), ty, to, candidates, true, p.loc));
            condition = Optional<Expression>.Value(_either(condition, is, BinaryOp.LogicalOr, p.loc));
        }
        return Optional<Expression>.Value(condition.is_value() ? condition.value() : Expression.BoolLiteral(false));
    }

    ## The test of a case pattern over an enum, or none after reporting an
    ## error.
    enum_test(
        p: CasePattern, matched: _Matched, subject: Expression, subject_loc: Loc, names: Array<(Loc, bool)>
    ): Expression? {
        var none = Optional<Expression>.Empty;
        if (p.qualifier.is_value()) {
            var q = p.qualifier.value();
            var fits = matched.kind == 0 ?
                q.to_string() == matched.enum_def.value().name :
                (matched.kind == 1 and q.name == matched.ty.name);
            if (!fits) {
                report(
                    _error_at_known(
                        $"'{q.to_string()}' is not the type of the value matched, '{matched.name()}'", p.loc
                    ).with_note("the value matched is here", known_location(subject_loc))
                );
                return none;
            }
        }
        if (matched.is_literal()) {
            return none;
        }
        EnumCaseDef? found = Optional<EnumCaseDef>.Empty;
        for (var c in matched.cases) {
            if (c.name == p.case) {
                found = Optional<EnumCaseDef>.Value(c);
                break;
            }
        }
        if (!found.is_value()) {
            if (matched.kind == 0) {
                var e = matched.enum_def.value();
                report(
                    _error_at_known(
                        $"no case named '{p.case}' in '{e.name}'", p.loc
                    ).with_note($"'{e.name}' declared here", known_location(e.loc))
                );
            } else {
                var lookup = _find_case(matched.cases, p.case, matched.ty, matched.declared, p.loc);
                if (lookup is Err(error)) {
                    report(error);
                }
            }
            return none;
        }
        var c = found.value();
        if (p.bindings.is_value()) {
            var bindings = p.bindings.value();
            if (matched.kind == 0) {
                var at = bindings.count > 0 ? bindings[0].loc : p.loc;
                report(
                    _error_at_known(
                        $"case '{c.name}' of '{matched.enum_def.value().name}' carries no values to bind", at
                    ).with_note($"'{c.name}' declared here", known_location(c.loc))
                );
                return none;
            }
            var extra = bindings.count > c.payload.count ?
                Optional<Loc>.Value(bindings[c.payload.count].loc) :
                Optional<Loc>.Empty;
            var count_error = _check_binding_count(c, bindings.count, extra, p.loc);
            if (count_error.is_value()) {
                report(count_error.value());
                return none;
            }
        }
        var test = matched.kind == 0 ?
            Expression.Binary(
                BinaryExpression(
                    subject.copy(), _case_expression(matched.enum_def.value(), c, p.loc), BinaryOp.Equal, p.loc
                )
            ) :
            _tag_is(subject, c, p.loc);
        # The patterns of the case's values, each over its payload field,
        # once the tag says the fields are there.
        if (matched.kind == 1 and p.bindings.is_value()) {
            var types = _case_payload_types(state, matched.ty);
            if (!types.is_value()) {
                return none;
            }
            ulong index = 0;
            while (index < matched.cases.count and matched.cases[index].name != c.name) {
                index += 1;
            }
            if (index >= matched.cases.count) {
                return none;
            }
            var subs = p.bindings.value();
            ulong j = 0;
            while (j < subs.count) {
                var sub = subs[j];
                var path = _case_field(subject, c, j, sub.loc);
                if (j >= types.value()[index].count) {
                    return none;
                }
                var tested = element_test(sub, path, types.value()[index][j], subject_loc, names);
                if (tested.failed) {
                    return none;
                }
                if (tested.test.is_value()) {
                    test = Expression.Binary(BinaryExpression(test, tested.test.value(), BinaryOp.LogicalAnd, sub.loc));
                }
                j += 1;
            }
        }
        return Optional<Expression>.Value(test);
    }

    ## Lowers an arm of a `match` over a tuple.
    tuple_arm(
        test: MatchArmTest, subject: Expression, ty: TypeName, subject_loc: Loc, entry: _Coverage, cases: String[]
    ): Expression? {
        var none = Optional<Expression>.Empty;
        entry.matched_name = Optional<String>.Value(_shown_type(ty));
        entry.matched_cases = Array<EnumCaseDef>();
        if (!entry.tuple.is_value()) {
            var domains = HashMap<String, Array<_DomainCase>>();
            collect_domains(ty, domains);
            entry.tuple = Optional<_TupleCoverage>.Value(_TupleCoverage(ty, domains));
        }
        var tuple = entry.tuple.value();
        var names = Array<(Loc, bool)>();
        Expression? condition = Optional<Expression>.Empty;
        for (var p in test.patterns) {
            if (!p.elements.is_value()) {
                report(
                    _error_at_known(
                        $"'{p.case}' cannot match a value of '{_shown_type(ty)}': match a tuple with a tuple pattern, such as '(a, _)'",
                        p.loc
                    ).with_note("the value matched is here", known_location(subject_loc))
                );
                return none;
            }
            var tested = element_test(p, subject, ty, subject_loc, names);
            if (tested.failed) {
                return none;
            }
            var space = space_of(p, ty);
            if (!test.site.partial and !useful(tuple.row_matrix(), [space], [ty], tuple.domains).is_value()) {
                report(
                    _error_at_known(
                        $"pattern '{p.case}' is already handled", p.loc
                    ).with_note("the patterns before it match every value it does", Optional<Location>.Empty)
                );
                return none;
            }
            if (!test.guarded) {
                tuple.rows.append(space);
            }
            var this_test = tested.test.is_value() ? tested.test.value() : Expression.BoolLiteral(true);
            condition = Optional<Expression>.Value(_either(condition, this_test, BinaryOp.LogicalOr, p.loc));
        }
        if (!resolve_element_names(test, names, cases)) {
            return none;
        }
        return Optional<Expression>.Value(condition.is_value() ? condition.value() : Expression.BoolLiteral(false));
    }

    ## Checks the arm's bare names in tuple elements and case values: one
    ## that binds must be declared, and may not bind in an `is` test outside
    ## a condition. `cases` receives each declared name that is a case
    ## everywhere. False after reporting an error.
    resolve_element_names(test: MatchArmTest, names: Array<(Loc, bool)>, cases: String[]): bool {
        for (var name in test.element_names) {
            var resolved = _resolved_at(names, name.loc);
            if (!resolved.is_value() or resolved.value()) {
                continue;
            }
            if (test.site.no_bindings) {
                report(
                    _error_at_known(
                        $"cannot bind '{name.name}' here: 'is' binds names only as the whole condition of an 'if' or 'while'",
                        name.loc
                    )
                );
                return false;
            }
            if (name.missing.is_value()) {
                var (shown, at) = name.missing.value();
                report(
                    _error_at_known(
                        $"'{name.name}' is not bound by '{shown}': every pattern of an arm binds the same names", at
                    ).with_note($"'{name.name}' is bound here", known_location(name.loc))
                );
                return false;
            }
            if (!name.declared) {
                report(
                    _error_at_known(
                        $"'{name.name}' binds an element here, but not once at the same element in every pattern of the arm",
                        name.loc
                    ).with_note(
                        "bind it once in each pattern, at the same element, or use '_'", Optional<Location>.Empty
                    )
                );
                return false;
            }
        }
        # A declared name must be a case everywhere or a binding everywhere.
        for (var name in test.element_names) {
            if (!name.declared) {
                continue;
            }
            var resolved = Array<bool>();
            for (var other in test.element_names) {
                if (other.name == name.name) {
                    var at = _resolved_at(names, other.loc);
                    if (at.is_value()) {
                        resolved.append(at.value());
                    }
                }
            }
            bool all = true;
            bool any = false;
            for (var c in resolved) {
                all = all and c;
                any = any or c;
            }
            if (all) {
                if (resolved.count > 0 and !cases.contains(name.name)) {
                    cases.append(name.name);
                }
            } else if (any) {
                report(
                    _error_at_known(
                        $"'{name.name}' names a case in one pattern of the arm and binds an element in another: rename the binding",
                        name.loc
                    )
                );
                return false;
            }
        }
        return true;
    }

    ## The test of pattern `p` over `subject` of type `ty`.
    element_test(
        p: CasePattern, subject: Expression, ty: TypeName, subject_loc: Loc, names: Array<(Loc, bool)>
    ): _ElementTest {
        var failed = _ElementTest(true, Optional<Expression>.Empty);
        var any = _ElementTest(false, Optional<Expression>.Empty);
        if (p.elements.is_value()) {
            var elements = p.elements.value();
            if (!ty.is_tuple()) {
                report(_error_at_known($"a tuple pattern cannot match a value of '{_shown_type(ty)}'", p.loc));
                return failed;
            }
            var types = ty.sub_types;
            if (types.count != elements.count) {
                report(
                    _error_at_known(
                        $"pattern '{p.case}' has {elements.count} elements, but '{_shown_type(ty)}' has {types.count}",
                        p.loc
                    )
                );
                return failed;
            }
            Expression? condition = Optional<Expression>.Empty;
            ulong i = 0;
            while (i < elements.count) {
                var e = elements[i];
                var path = Expression.MemberRef(MemberRefExpression(subject.copy(), $"{i}", e.loc));
                var tested = element_test(e, path, types[i], subject_loc, names);
                if (tested.failed) {
                    return failed;
                }
                if (tested.test.is_value()) {
                    condition = Optional<Expression>.Value(
                        _either(condition, tested.test.value(), BinaryOp.LogicalAnd, e.loc)
                    );
                }
                i += 1;
            }
            return _ElementTest(false, condition);
        }
        var matched = matched_of(ty);
        if (p.literal.is_value()) {
            if (!matched.is_value() or !matched.value().is_literal()) {
                var what = p.constant ? "a constant" : (p.range ? "a range" : "a literal");
                report(_error_at_known($"{what} cannot match a value of '{_shown_type(ty)}'", p.loc));
                return failed;
            }
            if (p.range and !_is_integer_type(ty)) {
                report(
                    _error_at_known(
                        $"a range cannot match a value of '{_shown_type(ty)}': ranges match integers and characters",
                        p.loc
                    )
                );
                return failed;
            }
            return _ElementTest(false, Optional<Expression>.Value(p.literal.value().copy()));
        }
        if (!p.qualifier.is_value() and !p.bindings.is_value()) {
            if (p.case == "_") {
                return any;
            }
            var is_case = matched.is_value() and !matched.value().is_literal() and matched.value().names_case(p.case);
            names.append((p.loc, is_case));
            if (!is_case) {
                return any;
            }
        }
        if (matched.is_value() and !matched.value().is_literal()) {
            var tested = enum_test(p, matched.value(), subject, subject_loc, names);
            return tested.is_value() ? _ElementTest(false, tested) : failed;
        }
        report(_error_at_known($"'{p.case}' cannot match a value of '{_shown_type(ty)}': it is not an enum", p.loc));
        return failed;
    }

    # ── Exhaustiveness ──

    ## The cases of enum `ty`, a value enum or a reference enum, each with
    ## the types of the values it carries.
    cases_with_types(ty: TypeName): Array<_DomainCase>? {
        var out = Array<_DomainCase>();
        var e = enums.try_get(ty.to_string());
        if (e.is_value()) {
            for (var c in e.value().cases) {
                out.append(_DomainCase(c.name, Array<TypeName>()));
            }
            return Optional<Array<_DomainCase>>.Value(out);
        }
        var reference = reference_cases(state, ty);
        var types = _case_payload_types(state, ty);
        if (!reference.is_value() or !types.is_value()) {
            return Optional<Array<_DomainCase>>.Empty;
        }
        var (cases, _) = reference.value();
        ulong i = 0;
        while (i < cases.count and i < types.value().count) {
            out.append(_DomainCase(cases[i].name, types.value()[i]));
            i += 1;
        }
        return Optional<Array<_DomainCase>>.Value(out);
    }

    ## Every case of each enum (and of `bool`) reachable from `ty`.
    collect_domains(ty: TypeName, out: HashMap<String, Array<_DomainCase>>) {
        if (ty.is_tuple()) {
            for (var element in ty.sub_types) {
                collect_domains(element, out);
            }
            return;
        }
        var key = ty.to_string();
        if (out.contains(key)) {
            return;
        }
        var matched = matched_of(ty);
        Array<_DomainCase>? cases = Optional<Array<_DomainCase>>.Empty;
        if (matched.is_value()) {
            if (matched.value().is_literal()) {
                if (matched.value().ty.name == "bool") {
                    cases = Optional<Array<_DomainCase>>.Value(
                        [_DomainCase("true", Array<TypeName>()), _DomainCase("false", Array<TypeName>())]
                    );
                }
            } else {
                cases = cases_with_types(ty);
            }
        }
        if (!cases.is_value()) {
            return;
        }
        out[key] = cases.value();
        for (var c in cases.value()) {
            for (var t in c.types) {
                collect_domains(t, out);
            }
        }
    }

    ## The values pattern `p` over a value of `ty` covers.
    space_of(p: CasePattern, ty: TypeName): _Space {
        if (p.elements.is_value()) {
            var out = Array<_Space>();
            var elements = p.elements.value();
            var types = ty.is_tuple() ? ty.sub_types : Array<TypeName>();
            ulong i = 0;
            while (i < elements.count and i < types.count) {
                out.append(space_of(elements[i], types[i]));
                i += 1;
            }
            return _Space.Tuple(out);
        }
        if (p.literal.is_value()) {
            return _Space.Case(p.case, Array<_Space>());
        }
        var cases = cases_with_types(ty);
        _DomainCase? found = Optional<_DomainCase>.Empty;
        if (cases.is_value()) {
            for (var c in cases.value()) {
                if (c.name == p.case) {
                    found = Optional<_DomainCase>.Value(c);
                    break;
                }
            }
        }
        if (!p.qualifier.is_value() and !p.bindings.is_value() and (!found.is_value() or _is_literal_type(ty))) {
            return _Space.Any;
        }
        var types = found.is_value() ? found.value().types : Array<TypeName>();
        var args = Array<_Space>();
        if (p.bindings.is_value()) {
            var subs = p.bindings.value();
            ulong i = 0;
            while (i < subs.count and i < types.count) {
                args.append(space_of(subs[i], types[i]));
                i += 1;
            }
        } else {
            args = _anys(types.count);
        }
        return _Space.Case(p.case, args);
    }

    ## Reports a `match` that leaves cases unhandled; returns the warning
    ## for an `else` that nothing reaches.
    check_exhaustive(c: _Coverage): Diagnostic? {
        var none = Optional<Diagnostic>.Empty;
        if (!c.site.is_value() or !c.matched_name.is_value()) {
            return none;
        }
        var site = c.site.value();
        var name = c.matched_name.value();
        var cases = c.matched_cases;
        if (site.partial) {
            return none;
        }
        if (c.tuple.is_value()) {
            var tuple = c.tuple.value();
            var missing = useful(tuple.row_matrix(), [_Space.Any], [tuple.ty], tuple.domains);
            if (site.else_arm.is_value() and !missing.is_value()) {
                return Optional<Diagnostic>.Value(
                    _warning_at($"'else' is unreachable: every value of '{name}' is handled", site.else_arm.value())
                );
            }
            if (!site.else_arm.is_value() and missing.is_value()) {
                report(
                    _error_at_known(
                        $"match on '{name}' does not handle '{_space_text(missing.value()[0])}'", site.keyword
                    ).with_note("handle it with another arm, or add an 'else' arm", Optional<Location>.Empty)
                );
            }
            return none;
        }
        if (c.literal) {
            var every_bool = name == "bool" and c.handled.contains("true") and c.handled.contains("false");
            var (min, max) = integer_range(name);
            # `ulong`'s top half is past what a pattern's value holds.
            var every_integer = name != "ulong"
                and name != "u64"
                and _is_integer_type(TypeName.named(name))
                and _covers(c.intervals, min, max);
            if (site.else_arm.is_value()) {
                if (every_bool) {
                    return Optional<Diagnostic>.Value(
                        _warning_at("'else' is unreachable: 'true' and 'false' are both handled", site.else_arm.value())
                    );
                }
                if (every_integer) {
                    return Optional<Diagnostic>.Value(
                        _warning_at($"'else' is unreachable: every value of '{name}' is handled", site.else_arm.value())
                    );
                }
            } else if (!every_bool and !every_integer) {
                report(
                    _error_at_known(
                        $"match on '{name}' needs an 'else' arm", site.keyword
                    ).with_note("literal patterns cannot handle every value", Optional<Location>.Empty)
                );
            }
            return none;
        }
        # A case no pattern handles whole may still be covered by patterns
        # nested in its values; one that is not shows the value they miss.
        var missing_cases = Array<EnumCaseDef>();
        var witnesses = Array<String>();
        for (var case in cases) {
            if (c.handled.contains(case.name)) {
                continue;
            }
            String? witness = Optional<String>.Empty;
            if (c.spaces.is_value()) {
                var spaces = c.spaces.value();
                bool named = false;
                for (var r in spaces.rows) {
                    if (r is Case(n, args)) {
                        if (n == case.name) {
                            named = true;
                        }
                    }
                }
                if (!named) {
                    witness = Optional<String>.Value(case.name);
                } else {
                    var arity = _case_arguments(spaces.ty, case.name, spaces.domains).count;
                    var v = _Space.Case(case.name, _anys(arity));
                    var found = useful(spaces.row_matrix(), [v], [spaces.ty], spaces.domains);
                    if (found.is_value()) {
                        witness = Optional<String>.Value(_space_text(found.value()[0]));
                    }
                }
                if (witness.is_value()) {
                    missing_cases.append(case);
                    witnesses.append(witness.value());
                }
            } else {
                missing_cases.append(case);
                witnesses.append(case.name);
            }
        }
        if (site.else_arm.is_value()) {
            if (missing_cases.count == 0 and cases.count > 0) {
                return Optional<Diagnostic>.Value(
                    _warning_at($"'else' is unreachable: every case of '{name}' is handled", site.else_arm.value())
                );
            }
            return none;
        }
        if (missing_cases.count == 0) {
            return none;
        }
        const SHOWN: ulong = 5;
        var names = Array<String>();
        ulong i = 0;
        while (i < witnesses.count and i < SHOWN) {
            names.append($"'{witnesses[i]}'");
            i += 1;
        }
        var listed = names[0];
        if (names.count > 1) {
            var front = Array<String>();
            ulong j = 0;
            while (j + 1 < names.count) {
                front.append(names[j]);
                j += 1;
            }
            listed = $"{", ".join(front)} and {names[names.count - 1]}";
        }
        var more = missing_cases.count > SHOWN ? $" and {missing_cases.count - SHOWN} more" : "";
        var diagnostic = _error_at_known(
            $"match on '{name}' does not handle {listed}{more}", site.keyword
        ).with_note("handle each case, or add an 'else' arm", Optional<Location>.Empty);
        i = 0;
        while (i < missing_cases.count and i < SHOWN) {
            diagnostic = diagnostic.with_note(
                $"'{missing_cases[i].name}' declared here", known_location(missing_cases[i].loc)
            );
            i += 1;
        }
        report(diagnostic);
        return none;
    }
}

extend _MatchLowering with Rewriter;

## Lowers each `CaseValue` in an arm's tests to the payload field it reads.
struct _CaseValueLowering {
    var lowering: _MatchLowering;

    construct(lowering: _MatchLowering) {
        this.lowering = lowering;
    }

    rewrite(e: Expression): Expression {
        if (e is CaseValue(value)) {
            var lowered = lowering.lower_case_value(value);
            # Its subject is not lowered again: a leaf for the walk.
            return lowered.is_value() ? lowered.value() : e;
        }
        return e;
    }
}

extend _CaseValueLowering with Rewriter;

_is_case_value(e: Expression): bool {
    match (e) {
        CaseValue(value) => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_case_value_of(e: Expression): CaseValue {
    if (e is CaseValue(value)) {
        return value;
    }
    return CaseValue(e);
}

_declares_one_of(item: Statement, names: String[]): bool {
    if (item is Declaration(declaration)) {
        if (declaration is Variable(variable)) {
            return names.contains(variable.name);
        }
    }
    return false;
}

_resolved_at(names: Array<(Loc, bool)>, at: Loc): bool? {
    for (var (loc, is_case) in names) {
        if (loc.same(at)) {
            return Optional<bool>.Value(is_case);
        }
    }
    return Optional<bool>.Empty;
}

_warning_at(message: String, loc: Loc): Diagnostic {
    var out = Diagnostic.warning(message);
    return loc.is_none() ? out : out.at(location_of(loc));
}

## The types of the values each case of reference enum `ty` carries, in
## the order of `reference_cases`' cases, with `ty`'s type arguments in
## place of the enum's parameters.
_case_payload_types(state: PassState, ty: TypeName): Array<TypeName[]>? {
    var found = state.reference_enums.try_get(ty.name);
    if (!found.is_value()) {
        return Optional<Array<TypeName[]>>.Empty;
    }
    var r = found.value();
    var map = Array<(String, TypeName)>();
    ulong i = 0;
    while (i < r.generic_params.count) {
        var p = r.generic_params[i];
        if (i < ty.sub_types.count) {
            map.append((p.name, ty.sub_types[i]));
        } else if (p.default.is_value()) {
            map.append((p.name, p.default.value()));
        }
        i += 1;
    }
    var out = Array<TypeName[]>();
    for (var types in r.payload_types) {
        var kept = Array<TypeName>();
        for (var t in types) {
            if (_is_erased_parameter(t, r.generic_params, ty)) {
                continue;
            }
            var copied = t.copy();
            replace_map(copied, map);
            kept.append(copied);
        }
        out.append(kept);
    }
    return Optional<Array<TypeName[]>>.Value(out);
}

## The types of the values case `case` of `ty` carries, or none for a
## literal.
_case_arguments(ty: TypeName, case: String, domains: HashMap<String, Array<_DomainCase>>): TypeName[] {
    var cases = domains.try_get(ty.to_string());
    if (cases.is_value()) {
        for (var c in cases.value()) {
            if (c.name == case) {
                return c.types;
            }
        }
    }
    return Array<TypeName>();
}

_tail<T>(items: Array<T>, from: ulong): Array<T> {
    var out = Array<T>();
    var i = from;
    while (i < items.count) {
        out.append(items[i]);
        i += 1;
    }
    return out;
}

_head<T>(items: Array<T>, count: ulong): Array<T> {
    var out = Array<T>();
    ulong i = 0;
    while (i < count and i < items.count) {
        out.append(items[i]);
        i += 1;
    }
    return out;
}

## `args` cut or padded with `Any` to `arity`.
_padded(args: _Space[], arity: ulong): _Space[] {
    var out = _head(args, arity);
    while (out.count < arity) {
        out.append(_Space.Any);
    }
    return out;
}

## A value no row covers that `v` does, as a witness, or none when the rows
## cover everything `v` does. `tys` are the columns' types.
useful(
    rows: Array<Array<_Space>>, v: _Space[], tys: TypeName[], domains: HashMap<String, Array<_DomainCase>>
): _Space[]? {
    var none = Optional<_Space[]>.Empty;
    if (v.count == 0) {
        return rows.count == 0 ? Optional<_Space[]>.Value(Array<_Space>()) : none;
    }
    var head = v[0];
    var rest = _tail(v, 1);
    var ty = tys[0];
    if (ty.is_tuple()) {
        var arity = ty.sub_types.count;
        var expanded = Array<Array<_Space>>();
        for (var r in rows) {
            var e = _expand_tuple(r[0], arity);
            e.append_all(_tail(r, 1));
            expanded.append(e);
        }
        var v2 = _expand_tuple(head, arity);
        v2.append_all(rest);
        var tys2 = ty.sub_types.copy();
        tys2.append_all(_tail(tys, 1));
        var witness = useful(expanded, v2, tys2, domains);
        if (!witness.is_value()) {
            return none;
        }
        var out = Array<_Space>();
        out.append(_Space.Tuple(_head(witness.value(), arity)));
        out.append_all(_tail(witness.value(), arity));
        return Optional<_Space[]>.Value(out);
    }
    match (head) {
        Case(case, args) => {
            return _useful_in_case(rows, rest, tys, domains, case, args);
        }
        Any => {
            var used = HashSet<String>();
            for (var r in rows) {
                if (r[0] is Case(c, args)) {
                    used.insert(c);
                }
            }
            var domain = domains.try_get(ty.to_string());
            if (domain.is_value() and domain.value().count > 0) {
                bool all_used = true;
                for (var c in domain.value()) {
                    if (!used.contains(c.name)) {
                        all_used = false;
                    }
                }
                if (all_used) {
                    for (var c in domain.value()) {
                        var found = _useful_in_case(rows, rest, tys, domains, c.name, Array<_Space>());
                        if (found.is_value()) {
                            return found;
                        }
                    }
                    return none;
                }
            }
            var defaults = Array<Array<_Space>>();
            for (var r in rows) {
                if (_is_any_space(r[0])) {
                    defaults.append(_tail(r, 1));
                }
            }
            var witness = useful(defaults, rest, _tail(tys, 1), domains);
            if (!witness.is_value()) {
                return none;
            }
            _Space missing = _Space.Any;
            if (domain.is_value()) {
                for (var c in domain.value()) {
                    if (!used.contains(c.name)) {
                        missing = _Space.Case(c.name, _anys(c.types.count));
                        break;
                    }
                }
            }
            var out = Array<_Space>();
            out.append(missing);
            out.append_all(witness.value());
            return Optional<_Space[]>.Value(out);
        }
        Tuple(elements) => {
            return none;
        }
    }
}

_expand_tuple(s: _Space, arity: ulong): _Space[] {
    if (s is Tuple(elements)) {
        if (elements.count == arity) {
            return elements.copy();
        }
    }
    return _anys(arity);
}

## `useful` on the values of case `case`, then the witness rebuilt around
## them.
_useful_in_case(
    rows: Array<Array<_Space>>,
    rest: _Space[],
    tys: TypeName[],
    domains: HashMap<String, Array<_DomainCase>>,
    case: String,
    args: _Space[]
): _Space[]? {
    var types = _case_arguments(tys[0], case, domains);
    var arity = types.count;
    var specialized = Array<Array<_Space>>();
    for (var r in rows) {
        Array<_Space>? out = Optional<Array<_Space>>.Empty;
        match (r[0]) {
            Any => {
                out = Optional<Array<_Space>>.Value(_anys(arity));
            }
            Case(c, row_args) => {
                if (c == case) {
                    out = Optional<Array<_Space>>.Value(_padded(row_args, arity));
                }
            }
            else => {}
        }
        if (out.is_value()) {
            var row = out.value();
            row.append_all(_tail(r, 1));
            specialized.append(row);
        }
    }
    var v2 = _padded(args, arity);
    v2.append_all(rest);
    var tys2 = types.copy();
    tys2.append_all(_tail(tys, 1));
    var witness = useful(specialized, v2, tys2, domains);
    if (!witness.is_value()) {
        return Optional<_Space[]>.Empty;
    }
    var out = Array<_Space>();
    out.append(_Space.Case(case, _head(witness.value(), arity)));
    out.append_all(_tail(witness.value(), arity));
    return Optional<_Space[]>.Value(out);
}

## What a type pattern over a value of trait `from` tests for, and the
## structs a value may hold to match it; the error when `target` is
## neither a trait nor a struct that a `from` value can hold.
_trait_target(state: PassState, from: TypeName, target: TypeName, at: Loc): Result<(TypeName, TypeName[]), Diagnostic> {
    var from_c = _canonical(from).to_string();
    var target_c = _canonical(target).to_string();
    if (is_trait(state, target)) {
        var candidates = Array<TypeName>();
        for (var (ty, _, traits) in state.trait_structs) {
            if (traits.contains(from_c) and traits.contains(target_c)) {
                candidates.append(ty);
            }
        }
        return Result<(TypeName, TypeName[]), Diagnostic>.Ok((target, candidates));
    }
    for (var (ty, canonical, traits) in state.trait_structs) {
        if (canonical != target_c) {
            continue;
        }
        if (!traits.contains(from_c)) {
            return Result<(TypeName, TypeName[]), Diagnostic>.Err(
                _error_at_known(
                    $"'{_shown_type(target)}' does not implement '{_shown_type(from)}', so a '{_shown_type(from)}' value never holds one",
                    at
                )
            );
        }
        return Result<(TypeName, TypeName[]), Diagnostic>.Ok((ty, [ty]));
    }
    return Result<(TypeName, TypeName[]), Diagnostic>.Err(
        _error_at_known(
            $"no struct or trait named '{_shown_type(target)}': a value of trait type '{_shown_type(from)}' is matched by type",
            at
        )
    );
}

## Reports a `match` expression whose arms produce values of types that do
## not mix: numbers mix (they convert), and `null` fits any reference. A
## parameter has its declared type.
_check_arm_types(block: Block, table: StructTable, current: TypeName?, parameters: VariableDef[], state: PassState) {
    rewrite_block(block, _ArmTypes(table, current, parameters, state));
}

struct _ArmTypes {
    var table: StructTable;
    var current: TypeName?;
    var parameters: VariableDef[];
    var state: PassState;

    construct(table: StructTable, current: TypeName?, parameters: VariableDef[], state: PassState) {
        this.table = table;
        this.current = current;
        this.parameters = parameters;
        this.state = state;
    }

    type_of(e: Expression): TypeName? {
        if (e is SymbolRef(node)) {
            for (var p in parameters) {
                if (p.name == node.id) {
                    return Optional<TypeName>.Value(p.ty);
                }
            }
        }
        return static_type_of(e, table, current, state);
    }

    rewrite(e: Expression): Expression {
        if (e is WithSubject(subject)) {
            check(subject);
        }
        return e;
    }

    check(subject: WithSubject) {
        var arms = Array<Expression>();
        var at = subject.body;
        while (at is Ternary(node)) {
            if (!_arm_test(node.condition).is_value()) {
                break;
            }
            arms.append(node.true_expr);
            at = node.false_expr;
        }
        if (arms.count == 0) {
            return;
        }
        if (!_is_no_match(at)) {
            arms.append(at);
        }
        var first = arms[0];
        var expected = type_of(first);
        if (!expected.is_value()) {
            return;
        }
        ulong i = 1;
        while (i < arms.count) {
            var arm = arms[i];
            i += 1;
            if (arm is PointerLiteral) {
                continue;
            }
            var actual = type_of(arm);
            if (!actual.is_value()) {
                continue;
            }
            if (actual.value() == expected.value()
                or (_is_primitive(actual.value()) and _is_primitive(expected.value()))) {
                continue;
            }
            var diagnostic = _error_at_known(
                $"'match' arm has a value of type '{_shown_type(actual.value())}', but the first arm's is '{_shown_type(expected.value())}'",
                _expression_loc(arm)
            );
            var first_loc = _expression_loc(first);
            if (!first_loc.is_none()) {
                diagnostic = diagnostic.with_note("the first arm's value is here", known_location(first_loc));
            }
            state.report(diagnostic);
            return;
        }
        return;
    }
}

extend _ArmTypes with Rewriter;

_is_primitive(t: TypeName): bool {
    return t.is_scalar() and is_integral_name(t.name);
}
