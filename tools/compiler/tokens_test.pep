# `parse.parse_written` keeps every token beside the tree (`Module.tokens`),
# with the comments and line breaks around it, and keeps parentheses
# (`Expression.Parenthesized`): enough for a tool to print the source back.
#
# The token walk below is the proof: it walks a module in source order and
# takes each token where the grammar puts it, checking its spelling, from
# the tree and the token table alone. On every source file of the
# repository it must take every token exactly once, in order. pep-fmt's
# formatter (tools/pep-fmt/format.pep) walks the tree the same way and adds
# the layout.

import compiler.ast;
import [
    Attribute,
    Block,
    Declaration,
    DestructureBinding,
    EnumCase,
    ExportAlias,
    Expression,
    ExtendDecl,
    FunctionDecl,
    GenericParam,
    Import,
    Match,
    MatchExpression,
    PropertyDecl,
    Span,
    Statement,
    StaticBlock,
    StructDecl,
    TraitDecl,
    TypeAliasDecl,
    VariableDecl
] from compiler.ast;
import compiler.desugar;
import io;
import [Directory, File, Path] from io;
import compiler.parse;
import syntax;

# A node the walk visited: what it is, its first and last tokens, and how
# deep it is (the module is 0).
struct Visited {
    var kind: String;
    var first: ulong;
    var last: ulong;
    var depth: ulong;

    construct(kind: String, first: ulong, depth: ulong) {
        this.kind = kind;
        this.first = first;
        this.last = first;
        this.depth = depth;
    }
}

# A member of a struct, trait, extension or enum, or an item of a module:
# where it starts, which list it is in, and its index there.
struct Entry {
    var start: ulong;
    var list: int;
    var index: ulong;

    construct(start: ulong, list: int, index: ulong) {
        this.start = start;
        this.list = list;
        this.index = index;
    }
}

# Sorts `entries` by where they start, keeping the order of equal ones.
sort_entries(entries: Entry[]) {
    ulong i = 1;
    while (i < entries.count) {
        var entry = entries[i];
        ulong j = i;
        while (j > 0 and entries[j - 1].start > entry.start) {
            entries[j] = entries[j - 1];
            j -= 1;
        }
        entries[j] = entry;
        i += 1;
    }
}

# Walks a module as `parse.parse_written` returns it, in source order,
# taking each token of `Module.tokens` where the grammar puts it. The first
# token that is not where the walk expects it stops the walk (`error`).
struct TokenWalk {
    var tokens: ast.SourceTokens;
    # The index of the next token to take.
    var next: ulong;
    var error: String = "";
    # Every node visited, in the order the walk entered them.
    var visited: Visited[] = Array<Visited>();
    # The indexes in `visited` of the nodes being walked.
    var open: ulong[] = Array<ulong>();

    construct(tokens: ast.SourceTokens) {
        this.tokens = tokens;
    }

    # ── Taking tokens ───────────────────────────────────────────────────

    # The index of the `End` token, which the walk never takes.
    end_index(): ulong {
        return tokens.tokens.count - 1;
    }

    fail(message: String) {
        if (!error.is_empty) {
            return;
        }
        var token = tokens.tokens[next];
        error = $"{message}; found '{tokens.text(next)}' at byte {token.offset}";
    }

    # Whether the next token is spelled `text`.
    at(text: String): bool {
        return error.is_empty and next < end_index() and tokens.tokens[next].spells(tokens.source, text);
    }

    take(text: String) {
        if (!error.is_empty) {
            return;
        }
        if (!at(text)) {
            fail($"expected '{text}'");
            return;
        }
        next += 1;
    }

    take_optional(text: String): bool {
        if (!at(text)) {
            return false;
        }
        next += 1;
        return true;
    }

    # Takes a `var` or a `const`.
    take_binding_keyword() {
        if (!take_optional("var")) {
            take("const");
        }
    }

    # Takes a name: an identifier.
    take_name() {
        if (!error.is_empty) {
            return;
        }
        if (next >= end_index() or tokens.tokens[next].kind != syntax.TokenKind.Identifier) {
            fail("expected a name");
            return;
        }
        next += 1;
    }

    # Takes the tokens of `span`, which must start at the next token.
    leaf(span: Span) {
        if (!error.is_empty) {
            return;
        }
        if (next >= end_index() or tokens.tokens[next].offset != span.start) {
            fail($"expected a token at byte {span.start}");
            return;
        }
        while (next < end_index() and tokens.tokens[next].offset < span.end) {
            next += 1;
        }
    }

    # Takes the tokens before byte `offset`: at least one.
    until(offset: ulong) {
        if (!error.is_empty) {
            return;
        }
        if (next >= end_index() or tokens.tokens[next].offset >= offset) {
            fail($"expected a token before byte {offset}");
            return;
        }
        while (next < end_index() and tokens.tokens[next].offset < offset) {
            next += 1;
        }
    }

    # Takes `;`s that end nothing.
    empties() {
        while (at(";")) {
            enter("Empty");
            next += 1;
            leave();
        }
    }

    enter(kind: String) {
        open.append(visited.count);
        visited.append(Visited(kind, next, open.count));
    }

    leave() {
        var node = visited[open.last()];
        node.last = next > node.first ? next - 1 : node.first;
        open.pop();
    }

    # ── Module ──────────────────────────────────────────────────────────

    module(tree: ast.Module) {
        visited.append(Visited("Module", 0, 0));
        var items = Array<Entry>();
        ulong i = 0;
        while (i < tree.imports.count) {
            items.append(Entry(tree.imports[i].span.start, 0, i));
            i += 1;
        }
        i = 0;
        while (i < tree.exports.count) {
            items.append(Entry(tree.exports[i].span.start, 1, i));
            i += 1;
        }
        i = 0;
        while (i < tree.declarations.count) {
            items.append(Entry(tree.declarations[i].span().start, 2, i));
            i += 1;
        }
        sort_entries(items);
        for (var item in items) {
            empties();
            if (item.list == 0) {
                import_declaration(tree.imports[item.index]);
            } else if (item.list == 1) {
                export_alias(tree.exports[item.index]);
            } else {
                declaration(tree.declarations[item.index]);
            }
        }
        empties();
        if (error.is_empty and next != end_index()) {
            fail("expected the end of the file");
        }
        visited[0].last = end_index();
    }

    attributes(list: Attribute[]) {
        for (var attribute in list) {
            enter("Attribute");
            take("[");
            expression(attribute.body);
            take("]");
            leave();
        }
    }

    modifiers(exported: bool, file_private: bool) {
        if (exported) {
            take("export");
        }
        if (file_private) {
            take("private");
        }
    }

    import_declaration(item: Import) {
        enter("Import");
        attributes(item.attributes);
        take(item.reexport ? "export" : "import");
        if (take_optional("*")) {
            take("from");
        }
        if (item.symbols.is_value()) {
            take("[");
            ulong i = 0;
            for (var symbol in item.symbols.value()) {
                if (i > 0) {
                    take(",");
                }
                enter("ImportSymbol");
                leaf(symbol.span);
                leave();
                i += 1;
            }
            take_optional(",");
            take("]");
            take("from");
        }
        leaf(item.name_span);
        if (take_optional("as")) {
            take_name();
        }
        take_optional(";");
        leave();
    }

    export_alias(item: ExportAlias) {
        enter("ExportAlias");
        attributes(item.attributes);
        take("export");
        leaf(item.symbol_span);
        if (take_optional("as")) {
            take_name();
        }
        take_optional(";");
        leave();
    }

    # ── Declarations ────────────────────────────────────────────────────

    declaration(d: Declaration) {
        match (d) {
            Variable(decl) => {
                enter("Variable");
                variable(decl, decl.default_value);
                take_optional(";");
                leave();
            }
            Function(decl) => {
                function(decl);
            }
            Struct(decl) => {
                aggregate(decl);
            }
            Trait(decl) => {
                trait_declaration(decl);
            }
            Extend(decl) => {
                extension(decl);
            }
            TypeAlias(decl) => {
                type_alias(decl);
            }
            Static(block) => {
                static_block(block);
            }
        }
    }

    # A variable, field or binding, from its attributes to its value
    # (`value`, which a `with` keeps apart), without its `;`.
    variable(decl: VariableDecl, value: Expression?) {
        attributes(decl.attributes);
        modifiers(decl.is_exported, decl.is_private);
        if (at("var") or at("const")) {
            take_binding_keyword();
        } else {
            leaf(decl.type_name.span);
        }
        leaf(decl.name_span);
        if (take_optional(":")) {
            leaf(decl.type_name.span);
        }
        if (value.is_value()) {
            take("=");
            expression(value.value());
        }
    }

    function(decl: FunctionDecl) {
        enter("Function");
        attributes(decl.attributes);
        modifiers(decl.is_exported, decl.is_private);
        if (decl.is_static) {
            take("static");
        }
        if (decl.external) {
            take("extern");
            leaf(decl.return_type.span);
            leaf(decl.name_span);
            parameters(decl.parameters, decl.is_variadic);
            take_optional(";");
            leave();
            return;
        }
        if (error.is_empty and tokens.tokens[next].offset != decl.name_span.start) {
            # `Type name(...)`: the return type comes first.
            until(decl.name_span.start);
        }
        leaf(decl.name_span);
        if (decl.is_indexer and at("[")) {
            # `Type [](...)`, whose name is its return type.
            take("[");
            take("]");
        }
        if (at("<")) {
            generic_parameters(decl.generic_params);
        }
        if (at("(")) {
            parameters(decl.parameters, false);
        }
        if (take_optional(":")) {
            leaf(decl.return_type.span);
        }
        if (decl.body.is_value()) {
            block(decl.body.value());
        } else {
            take_optional(";");
        }
        leave();
    }

    parameters(list: VariableDecl[], variadic: bool) {
        take("(");
        ulong i = 0;
        for (var item in list) {
            if (i > 0) {
                take(",");
            }
            parameter(item);
            i += 1;
        }
        if (variadic) {
            if (i > 0) {
                take(",");
            }
            take("...");
        }
        take_optional(",");
        take(")");
    }

    parameter(decl: VariableDecl) {
        enter("Parameter");
        attributes(decl.attributes);
        if (at("this")) {
            take("this");
            take(".");
            leaf(decl.name_span);
        } else if (at("var") or at("const")) {
            take_binding_keyword();
            leaf(decl.name_span);
            if (take_optional(":")) {
                leaf(decl.type_name.span);
            }
        } else if (error.is_empty and tokens.tokens[next].offset == decl.name_span.start) {
            leaf(decl.name_span);
            take(":");
            leaf(decl.type_name.span);
        } else {
            leaf(decl.type_name.span);
            leaf(decl.name_span);
        }
        if (decl.default_value.is_value()) {
            take("=");
            expression(decl.default_value.value());
        }
        leave();
    }

    generic_parameters(list: GenericParam[]) {
        take("<");
        ulong i = 0;
        for (var item in list) {
            if (i > 0) {
                take(",");
            }
            enter("GenericParameter");
            leaf(item.name_span);
            ulong b = 0;
            for (var bound in item.bounds) {
                take(b == 0 ? ":" : "&");
                leaf(bound.span);
                b += 1;
            }
            if (item.default.is_value()) {
                take("=");
                leaf(item.default.value().span);
            }
            leave();
            i += 1;
        }
        take(">");
    }

    # A struct or an enum.
    aggregate(decl: StructDecl) {
        enter(decl.enumeration.is_value() ? "Enum" : "Struct");
        attributes(decl.attributes);
        modifiers(decl.is_exported, decl.is_private);
        take(decl.enumeration.is_value() ? "enum" : "struct");
        leaf(decl.name_span);
        if (at("<")) {
            generic_parameters(decl.generic_params);
        }
        var cases = Array<EnumCase>();
        if (decl.enumeration.is_value()) {
            var body = decl.enumeration.value();
            if (body.representation.is_value()) {
                take(":");
                leaf(body.representation.value().span);
            }
            cases = body.cases;
        }
        var fields = decl.fields;
        var constructors = decl.constructors;
        var entries = member_entries(decl.methods, decl.properties);
        ulong i = 0;
        while (i < fields.count) {
            entries.append(Entry(fields[i].span.start, 2, i));
            i += 1;
        }
        i = 0;
        while (i < constructors.count) {
            entries.append(Entry(constructors[i].span.start, 3, i));
            i += 1;
        }
        i = 0;
        while (i < cases.count) {
            entries.append(Entry(cases[i].span.start, 4, i));
            i += 1;
        }
        if (decl.destructor.is_value()) {
            var body = decl.destructor.value();
            var start = decl.destruct_span.value().start;
            if (body.attributes.count > 0) {
                start = body.attributes[0].span.start;
            }
            entries.append(Entry(start, 5, 0));
        }
        sort_entries(entries);
        take("{");
        for (var entry in entries) {
            empties();
            if (entry.list == 0) {
                function(decl.methods[entry.index]);
            } else if (entry.list == 1) {
                property(decl.properties[entry.index]);
            } else if (entry.list == 2) {
                enter("Field");
                variable(fields[entry.index], fields[entry.index].default_value);
                take_optional(";");
                leave();
            } else if (entry.list == 3) {
                constructor(constructors[entry.index]);
            } else if (entry.list == 4) {
                enum_case(cases[entry.index]);
            } else {
                var body = decl.destructor.value();
                enter("Destructor");
                attributes(body.attributes);
                take("destruct");
                block_body(body);
                leave();
            }
        }
        empties();
        take("}");
        leave();
    }

    # The methods and properties of a member list, unsorted.
    member_entries(methods: FunctionDecl[], properties: PropertyDecl[]): Entry[] {
        var entries = Array<Entry>();
        ulong i = 0;
        while (i < methods.count) {
            entries.append(Entry(methods[i].span.start, 0, i));
            i += 1;
        }
        i = 0;
        while (i < properties.count) {
            entries.append(Entry(properties[i].span.start, 1, i));
            i += 1;
        }
        return entries;
    }

    # The `{ ... }` of a trait or an extension.
    members(methods: FunctionDecl[], properties: PropertyDecl[]) {
        var entries = member_entries(methods, properties);
        sort_entries(entries);
        take("{");
        for (var entry in entries) {
            empties();
            if (entry.list == 0) {
                function(methods[entry.index]);
            } else {
                property(properties[entry.index]);
            }
        }
        empties();
        take("}");
    }

    constructor(decl: FunctionDecl) {
        enter("Constructor");
        attributes(decl.attributes);
        if (!take_optional("new")) {
            take("construct");
        }
        parameters(decl.parameters, false);
        block(decl.body.value());
        leave();
    }

    property(decl: PropertyDecl) {
        enter("Property");
        attributes(decl.attributes);
        take("var");
        leaf(decl.name_span);
        take(":");
        leaf(decl.type_name.span);
        take("{");
        var getter_first = decl.getter.is_value()
            and (!decl.setter.is_value() or decl.getter.value().span.start < decl.setter.value().span.start);
        if (getter_first) {
            accessor(decl.getter.value(), "get");
        }
        if (decl.setter.is_value()) {
            accessor(decl.setter.value(), "set");
        }
        if (decl.getter.is_value() and !getter_first) {
            accessor(decl.getter.value(), "get");
        }
        take("}");
        if (decl.default_value.is_value()) {
            take("=");
            expression(decl.default_value.value());
            take_optional(";");
        }
        leave();
    }

    accessor(item: ast.Accessor, keyword: String) {
        enter("Accessor");
        take(keyword);
        if (item.function.body.is_value()) {
            block(item.function.body.value());
        } else {
            take(";");
        }
        leave();
    }

    enum_case(item: EnumCase) {
        enter("EnumCase");
        attributes(item.attributes);
        leaf(item.name_span);
        if (item.payload.is_value()) {
            parameters(item.payload.value(), false);
        }
        if (item.value.is_value()) {
            take("=");
            expression(item.value.value());
        }
        take_optional(",");
        leave();
    }

    trait_declaration(decl: TraitDecl) {
        enter("Trait");
        attributes(decl.attributes);
        modifiers(decl.is_exported, decl.is_private);
        take("trait");
        leaf(decl.name_span);
        if (at("<")) {
            generic_parameters(decl.generic_params);
        }
        members(decl.methods, decl.properties);
        leave();
    }

    extension(decl: ExtendDecl) {
        enter("Extend");
        attributes(decl.attributes);
        modifiers(decl.is_exported, decl.is_private);
        take("extend");
        leaf(decl.target.span);
        if (take_optional("with")) {
            ulong i = 0;
            for (var adopted in decl.traits) {
                if (i > 0) {
                    take(",");
                }
                leaf(adopted.span);
                i += 1;
            }
        }
        if (!take_optional(";")) {
            members(decl.methods, decl.properties);
        }
        leave();
    }

    type_alias(decl: TypeAliasDecl) {
        enter("TypeAlias");
        attributes(decl.attributes);
        modifiers(decl.is_exported, decl.is_private);
        take("type");
        leaf(decl.name_span);
        if (at("<")) {
            generic_parameters(decl.generic_params);
        }
        take("=");
        leaf(decl.target.span);
        take_optional(";");
        leave();
    }

    static_block(decl: StaticBlock) {
        enter("Static");
        attributes(decl.attributes);
        modifiers(decl.is_exported, decl.is_private);
        take("static");
        if (take_optional("(")) {
            ulong i = 0;
            for (var capture in decl.captures) {
                if (i > 0) {
                    take(",");
                }
                leaf(capture.span);
                i += 1;
            }
            take(")");
        }
        block(decl.block);
        leave();
    }

    # ── Statements ──────────────────────────────────────────────────────

    block(item: Block) {
        enter("Block");
        attributes(item.attributes);
        block_body(item);
        leave();
    }

    # `{ statement... }`, without the attributes, which a statement around
    # it may hold.
    block_body(item: Block) {
        take("{");
        for (var s in item.statements) {
            empties();
            statement(s);
        }
        empties();
        take("}");
    }

    statement(s: Statement) {
        match (s) {
            Expression(e) => {
                enter("ExpressionStatement");
                expression(e);
                take_optional(";");
                leave();
            }
            Block(inner) => {
                block(inner);
            }
            Declaration(d) => {
                declaration(d);
            }
            Branch(condition, if_block, else_block, _) => {
                enter("If");
                attributes(if_block.attributes);
                take("if");
                expression(condition);
                block_body(if_block);
                if (else_block.is_value()) {
                    take("else");
                    var other = else_block.value();
                    if (is_else_if(other)) {
                        statement(other.statements[0]);
                    } else {
                        block(other);
                    }
                }
                leave();
            }
            While(condition, body, _) => {
                enter("While");
                take("while");
                expression(condition);
                block(body);
                leave();
            }
            For(binding, pattern, iterable, body, _) => {
                enter("For");
                take("for");
                bool parenthesized = take_optional("(");
                if (pattern.count > 0) {
                    take_binding_keyword();
                    destructure_bindings(pattern);
                } else {
                    enter("Variable");
                    variable(binding, binding.default_value);
                    leave();
                }
                take("in");
                expression(iterable);
                if (parenthesized) {
                    take(")");
                }
                block(body);
                leave();
            }
            With(binding, scope, body, else_block, _) => {
                enter("With");
                take("with");
                bool parenthesized = take_optional("(");
                if (binding.is_value()) {
                    enter("Variable");
                    variable(binding.value(), Optional<Expression>.Value(scope));
                    leave();
                } else {
                    expression(scope);
                }
                if (parenthesized) {
                    take(")");
                }
                block(body);
                if (else_block.is_value()) {
                    take("else");
                    block(else_block.value());
                }
                leave();
            }
            Return(value, _) => {
                enter("Return");
                take("return");
                if (value.is_value()) {
                    expression(value.value());
                }
                take_optional(";");
                leave();
            }
            LoopBreak(is_continue, label, _, _) => {
                enter("Jump");
                take(is_continue ? "continue" : "break");
                if (!label.is_empty) {
                    take(label);
                }
                take_optional(";");
                leave();
            }
            Labeled(label, _, loop, _) => {
                enter("Labeled");
                take(label);
                take(":");
                statement(loop);
                leave();
            }
            Destructure(bindings, value, is_const, _) => {
                enter("Destructure");
                take(is_const ? "const" : "var");
                destructure_bindings(bindings);
                take("=");
                expression(value);
                take_optional(";");
                leave();
            }
            Match(m) => {
                match_statement(m);
            }
            Static(inner) => {
                static_block(inner);
            }
        }
    }

    # Whether `other`, an `else` block, stands for an `else if`: a block
    # that only holds the `if`, spanning just that.
    is_else_if(other: Block): bool {
        if (other.statements.count != 1) {
            return false;
        }
        if (other.statements[0] is Branch(_, _, _, span)) {
            return span.start == other.span.start and span.end == other.span.end;
        }
        return false;
    }

    destructure_bindings(list: DestructureBinding[]) {
        take("(");
        ulong i = 0;
        for (var binding in list) {
            if (i > 0) {
                take(",");
            }
            if (binding.name.is_empty) {
                destructure_bindings(binding.nested);
            } else {
                leaf(binding.name_span);
                if (take_optional(":")) {
                    leaf(binding.type_name.span);
                }
            }
            i += 1;
        }
        take(")");
    }

    match_statement(m: Match) {
        enter("Match");
        take("match");
        expression(m.value);
        take("{");
        var entries = Array<Entry>();
        ulong i = 0;
        while (i < m.arms.count) {
            entries.append(Entry(m.arms[i].span.start, 0, i));
            i += 1;
        }
        if (m.else_block.is_value()) {
            var start = m.else_span.start;
            var attributes = m.else_block.value().attributes;
            if (attributes.count > 0) {
                start = attributes[0].span.start;
            }
            entries.append(Entry(start, 1, 0));
        }
        sort_entries(entries);
        for (var entry in entries) {
            enter("MatchArm");
            if (entry.list == 0) {
                var arm = m.arms[entry.index];
                attributes(arm.body.attributes);
                patterns(arm.patterns);
                if (arm.guard.is_value()) {
                    take("if");
                    expression(arm.guard.value());
                }
                take("=>");
                block_body(arm.body);
            } else {
                var body = m.else_block.value();
                attributes(body.attributes);
                take("else");
                take("=>");
                block_body(body);
            }
            take_optional(",");
            leave();
        }
        take("}");
        leave();
    }

    patterns(list: ast.Pattern[]) {
        ulong i = 0;
        for (var item in list) {
            if (i > 0) {
                take(",");
            }
            enter("Pattern");
            leaf(item.span);
            leave();
            i += 1;
        }
    }

    # ── Expressions ─────────────────────────────────────────────────────

    expression(e: Expression) {
        if (!error.is_empty) {
            return;
        }
        match (e) {
            Literal(_, span) => {
                enter("Literal");
                leaf(span);
                leave();
            }
            SymbolRef(_, span) => {
                enter("Name");
                leaf(span);
                leave();
            }
            TypeLiteral(type_name) => {
                enter("TypeLiteral");
                leaf(type_name.span);
                leave();
            }
            SizeOf(type_name) => {
                enter("Sizeof");
                take("sizeof");
                take("<");
                leaf(type_name.span);
                take(">");
                if (take_optional("(")) {
                    take(")");
                }
                leave();
            }
            Unary(op, prefix, operand, _) => {
                enter("Unary");
                if (prefix) {
                    take(op);
                    expression(operand);
                } else {
                    expression(operand);
                    take(op);
                }
                leave();
            }
            Cast(value, type_name, _, _, optional) => {
                enter("Cast");
                expression(value);
                take("as");
                if (optional) {
                    take("?");
                }
                leaf(type_name.span);
                leave();
            }
            Binary(lhs, op, rhs, _) => {
                enter("Binary");
                expression(lhs);
                take(op);
                expression(rhs);
                leave();
            }
            Ternary(condition, true_expr, false_expr, _) => {
                enter("Ternary");
                expression(condition);
                take("?");
                expression(true_expr);
                take(":");
                expression(false_expr);
                leave();
            }
            Index(lhs, rhs, _) => {
                enter("Index");
                expression(lhs);
                take("[");
                expression(rhs);
                take("]");
                leave();
            }
            MemberAccess(lhs, _, name_span, span) => {
                enter("Member");
                expression(lhs);
                take(".");
                leaf(Span(name_span.start, span.end));
                leave();
            }
            FunctionCall(function, arguments, _) => {
                enter("Call");
                expression(function);
                take("(");
                list(arguments);
                take(")");
                leave();
            }
            NamedArgument(_, name_span, value, _) => {
                enter("NamedArgument");
                leaf(name_span);
                take("=");
                expression(value);
                leave();
            }
            Closure(closure) => {
                enter("Closure");
                take("(");
                ulong i = 0;
                for (var parameter in closure.parameters) {
                    if (i > 0) {
                        take(",");
                    }
                    enter("Parameter");
                    leaf(parameter.name_span);
                    if (take_optional(":")) {
                        leaf(parameter.type_name.span);
                    }
                    leave();
                    i += 1;
                }
                take(")");
                if (take_optional(":")) {
                    leaf(closure.return_type.span);
                }
                take("=>");
                if (closure.expression_body) {
                    if (closure.body.statements[0] is Return(value, _)) {
                        expression(value.value());
                    }
                } else {
                    block(closure.body);
                }
                leave();
            }
            Tuple(elements, labels, _) => {
                enter("Tuple");
                take("(");
                ulong i = 0;
                ulong label = 0;
                for (var element in elements) {
                    if (i > 0) {
                        take(",");
                    }
                    if (label < labels.count
                        and error.is_empty
                        and tokens.tokens[next].offset == labels[label].span.start) {
                        leaf(labels[label].span);
                        take(":");
                        label += 1;
                    }
                    expression(element);
                    i += 1;
                }
                take_optional(",");
                take(")");
                leave();
            }
            ArrayLiteral(elements, _) => {
                enter("Array");
                take("[");
                list(elements);
                take("]");
                leave();
            }
            MapLiteral(entries, _) => {
                enter("Map");
                take("[");
                if (entries.is_empty) {
                    take(":");
                }
                ulong i = 0;
                for (var entry in entries) {
                    if (i > 0) {
                        take(",");
                    }
                    expression(entry.key);
                    take(":");
                    expression(entry.value);
                    i += 1;
                }
                take_optional(",");
                take("]");
                leave();
            }
            Match(m) => {
                match_expression(m);
            }
            Is(value, pattern, _, _) => {
                enter("Is");
                expression(value);
                take("is");
                leaf(pattern.span);
                leave();
            }
            Interpolated(_, span) => {
                enter("Literal");
                leaf(span);
                leave();
            }
            FormatString(_, span, _, _) => {
                enter("Literal");
                leaf(span);
                leave();
            }
            Parenthesized(value, _) => {
                enter("Parenthesized");
                take("(");
                expression(value);
                take(")");
                leave();
            }
        }
    }

    # Expressions separated by `,`, and a `,` after the last.
    list(elements: Expression[]) {
        ulong i = 0;
        for (var element in elements) {
            if (i > 0) {
                take(",");
            }
            expression(element);
            i += 1;
        }
        take_optional(",");
    }

    match_expression(m: MatchExpression) {
        enter("Match");
        take("match");
        expression(m.value);
        take("{");
        var entries = Array<Entry>();
        ulong i = 0;
        while (i < m.arms.count) {
            entries.append(Entry(m.arms[i].span.start, 0, i));
            i += 1;
        }
        if (m.else_value.is_value()) {
            entries.append(Entry(m.else_span.start, 1, 0));
        }
        sort_entries(entries);
        for (var entry in entries) {
            enter("MatchArm");
            if (entry.list == 0) {
                var arm = m.arms[entry.index];
                patterns(arm.patterns);
                if (arm.guard.is_value()) {
                    take("if");
                    expression(arm.guard.value());
                }
                take("=>");
                expression(arm.value);
            } else {
                take("else");
                take("=>");
                expression(m.else_value.value());
            }
            take_optional(",");
            leave();
        }
        take("}");
        leave();
    }

    # ── Comments ────────────────────────────────────────────────────────

    # The node each comment belongs to, one line per comment in source
    # order: `text: Kind (role)`. A comment before a token belongs to the
    # outermost node that starts there ("before"), a comment after one to
    # the outermost node that ends there ("after"); any other comment, as
    # on a `)` or a `}`, is "inside" the innermost node around its token,
    # and the comments before the end of the file are the module's ("end").
    comment_owners(): String[] {
        var count = tokens.tokens.count;
        var starting = Array<long>();
        var ending = Array<long>();
        var around = Array<long>();
        ulong t = 0;
        while (t < count) {
            starting.append(-1);
            ending.append(-1);
            around.append(0);
            t += 1;
        }
        ulong v = 1;
        while (v < visited.count) {
            var node = visited[v];
            if (starting[node.first] < 0) {
                starting[node.first] = v as long;
            }
            var last = ending[node.last];
            if (last < 0 or visited[last as ulong].depth >= node.depth) {
                ending[node.last] = v as long;
            }
            # In entering order, a node inside another comes later.
            t = node.first;
            while (t <= node.last) {
                around[t] = v as long;
                t += 1;
            }
            v += 1;
        }
        var out = Array<String>();
        t = 0;
        while (t < count) {
            var token = tokens.tokens[t];
            for (var comment in token.leading_comments) {
                if (t + 1 == count) {
                    out.append($"{comment.text}: Module (end)");
                } else if (starting[t] >= 0) {
                    out.append($"{comment.text}: {visited[starting[t] as ulong].kind} (before)");
                } else {
                    out.append($"{comment.text}: {visited[around[t] as ulong].kind} (inside)");
                }
            }
            if (token.has_trailing_comment()) {
                if (ending[t] >= 0) {
                    out.append($"{token.trailing_comment}: {visited[ending[t] as ulong].kind} (after)");
                } else {
                    out.append($"{token.trailing_comment}: {visited[around[t] as ulong].kind} (inside)");
                }
            }
            t += 1;
        }
        return out;
    }
}

# Walks `module`, which `parse.parse_written` returned with its tokens.
walk(module: ast.Module): TokenWalk {
    var walker = TokenWalk(module.tokens.value());
    walker.module(module);
    return walker;
}

# Whether `tokens` are the lexer's tokens of their source, with the `>`s
# the parser joined into one token joined: an empty String when they are,
# else where they are not.
lexer_difference(tokens: ast.SourceTokens): String {
    var lexed = syntax.lex(tokens.source);
    if (lexed.is_err()) {
        return "the lexer fails";
    }
    var expected = lexed.value();
    ulong j = 0;
    ulong i = 0;
    while (i < tokens.tokens.count) {
        var token = tokens.tokens[i];
        if (j >= expected.count or expected[j].offset != token.offset) {
            return $"token {i} at byte {token.offset}";
        }
        # A joined token covers the adjacent one-byte tokens after it.
        ulong end = expected[j].offset + expected[j].size;
        j += 1;
        while (end < token.offset + token.size and j < expected.count and expected[j].offset == end) {
            end += expected[j].size;
            j += 1;
        }
        if (end != token.offset + token.size) {
            return $"token {i} at byte {token.offset}";
        }
        i += 1;
    }
    if (j != expected.count) {
        return "tokens are missing at the end";
    }
    return "";
}

# Appends the `.pep` files under `folder` to `out`, in name order, leaving
# out hidden folders.
collect_sources(folder: Path, out: Path[]) {
    var listing = Directory.open(folder);
    if (listing.is_err()) {
        return;
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return;
    }
    var names = Array<String>();
    var by_name = HashMap<String, io.DirEntry>();
    for (var entry in entries.value()) {
        names.append(entry.name);
        by_name[entry.name] = entry;
    }
    names.sort((a, b) => a.compare(b));
    for (var name in names) {
        var entry = by_name[name];
        if (entry.is_directory and !name.starts_with(".")) {
            collect_sources(entry.path, out);
        } else if (entry.is_file and name.ends_with(".pep")) {
            out.append(entry.path);
        }
    }
}

# The value of the first statement of the first function, a `var`.
initializer(module: ast.Module): Expression {
    if (module.declarations[0] is Function(function)) {
        var statement = function.body.value().statements[0];
        if (statement is Declaration(local)) {
            if (local is Variable(variable)) {
                return variable.default_value.value();
            }
        }
    }
    return Expression.SymbolRef("", Span());
}

[Test]
parse_keeps_no_tokens_and_no_parentheses() {
    var module = parse.parse("f() { var x = (1 + 2) * 3; }").value();
    expect_false(module.tokens.is_value());
    var value = initializer(module);
    expect_true(value is Binary(_, _, _, _));
    if (value is Binary(lhs, _, _, _)) {
        expect_true(lhs is Binary(_, _, _, _));
    }
}

[Test]
parse_written_keeps_the_parentheses() {
    var source = "f() { var x = ((1 + 2)) * 3; }";
    var module = parse.parse_written(source).value();
    var value = initializer(module);
    expect_true(value is Binary(_, _, _, _));
    if (value is Binary(lhs, _, _, _)) {
        expect_true(lhs is Parenthesized(_, _));
        expect_equal(lhs.to_string(), "(((1 + 2)))");
        expect_equal(lhs.span().start, 14 as ulong);
        expect_equal(lhs.span().end, 23 as ulong);
    }
    var rewritten = desugar.desugar(module).value();
    expect_equal(rewritten.to_json().to_string(), parse.parse(source).value().to_json().to_string());
}

[Test]
parse_written_keeps_the_tokens_and_their_comments() {
    var source = "# head\n\n## doc\nf() {  # opens\n    g(a >> 1);\n\n    # last\n}\n# tail\n";
    var tokens = parse.parse_written(source).value().tokens.value();
    expect_equal(tokens.tokens.count, 13 as ulong);
    expect_equal(tokens.text(7), ">>");
    expect_equal(tokens.text(tokens.next_index(16)), "(");
    expect_equal(tokens.index_at(tokens.tokens[7].offset), 7 as long);
    expect_equal(tokens.index_at(tokens.tokens[7].offset + 1), -1 as long);
    var function = Span(15, 58);
    var leading = tokens.leading(function);
    expect_equal(leading.count, 2 as ulong);
    expect_equal(leading[0].text, "# head");
    expect_equal(leading[1].text, "## doc");
    expect_false(tokens.blank_before(function));
    expect_equal(tokens.trailing(Span(15, 20)), "# opens");
    expect_equal(tokens.trailing(function), "");
    expect_equal(tokens.leading(Span(57, 58))[0].text, "# last");
    expect_true(tokens.leading(Span(57, 58))[0].newlines_before >= 2, "a blank line comes before `# last`");
    expect_equal(tokens.tokens.last().leading_comments[0].text, "# tail");
    expect_equal(lexer_difference(tokens), "");
}

[Test]
places_each_comment_on_one_node() {
    var source = "# above the import\n"
        + "import io;  # after the import\n"
        + "\n"
        + "# above the attributes\n"
        + "[Test]\n"
        + "# between the attributes\n"
        + "[Inline]\n"
        + "export f(\n"
        + "    a: int,  # after a parameter\n"
        + "    # above the last parameter\n"
        + "    b: int\n"
        + "    # before the close\n"
        + "): int {  # after the open brace\n"
        + "    var x = (a  # inside the parentheses\n"
        + "        # above an operator\n"
        + "        + b);\n"
        + "    g(\n"
        + "        # in an empty argument list\n"
        + "    );\n"
        + "    if (x > 0) {\n"
        + "        return x;\n"
        + "    }\n"
        + "    # above else\n"
        + "    else {\n"
        + "        # in an empty block\n"
        + "    }\n"
        + "    match (x) {\n"
        + "        1 => {}  # after an arm\n"
        + "        # above else arm\n"
        + "        else => {}\n"
        + "    }\n"
        + "    # after the last statement\n"
        + "}\n"
        + "\n"
        + "struct S {\n"
        + "    # above a field\n"
        + "    int x;  # after a field\n"
        + "    # at the end of the members\n"
        + "}\n"
        + "# at the end of the file\n";
    var module = parse.parse_written(source).value();
    var walker = walk(module);
    expect_equal(walker.error, "");
    expect_equal(
        "\n".join(walker.comment_owners()),
        "# above the import: Import (before)\n"
            + "# after the import: Import (after)\n"
            + "# above the attributes: Function (before)\n"
            + "# between the attributes: Attribute (before)\n"
            + "# after a parameter: Function (inside)\n"
            + "# above the last parameter: Parameter (before)\n"
            + "# before the close: Function (inside)\n"
            + "# after the open brace: Block (inside)\n"
            + "# inside the parentheses: Name (after)\n"
            + "# above an operator: Binary (inside)\n"
            + "# in an empty argument list: Call (inside)\n"
            + "# above else: If (inside)\n"
            + "# in an empty block: Block (inside)\n"
            + "# after an arm: MatchArm (after)\n"
            + "# above else arm: MatchArm (before)\n"
            + "# after the last statement: Block (inside)\n"
            + "# above a field: Field (before)\n"
            + "# after a field: Field (after)\n"
            + "# at the end of the members: Struct (inside)\n"
            + "# at the end of the file: Module (end)"
    );
}

# The number of comments attached to `tokens`.
comment_count(tokens: ast.SourceTokens): ulong {
    ulong count = 0;
    for (var token in tokens.tokens) {
        count += token.leading_comments.count;
        if (token.has_trailing_comment()) {
            count += 1;
        }
    }
    return count;
}

# What is wrong with `source`'s written tree, or an empty String: its
# tokens are not the lexer's, the walk does not take them all, a comment
# is placed on no node, or `desugar` does not make it `parse.parse`'s tree.
problem(source: String): String {
    var module = parse.parse_written(source);
    if (module.is_err()) {
        return "";
    }
    var tokens = module.value().tokens.value();
    var difference = lexer_difference(tokens);
    if (!difference.is_empty) {
        return $"not the lexer's tokens: {difference}";
    }
    var walker = walk(module.value());
    if (!walker.error.is_empty) {
        return walker.error;
    }
    var placed = walker.comment_owners().count;
    if (placed != comment_count(tokens)) {
        return $"{placed} of {comment_count(tokens)} comments placed";
    }
    var rewritten = desugar.desugar(module.value());
    if (rewritten.is_err()) {
        return $"desugar fails: {rewritten.error().message}";
    }
    if (rewritten.value().to_json().to_string() != parse.parse(source).value().to_json().to_string()) {
        return "desugar does not give parse's tree";
    }
    return "";
}

# The files are split in parts, each a test of its own, so they run side
# by side.
[Test]
walks_every_token_of_every_source_file_part_1() {
    walks_tokens(0);
}

[Test]
walks_every_token_of_every_source_file_part_2() {
    walks_tokens(1);
}

[Test]
walks_every_token_of_every_source_file_part_3() {
    walks_tokens(2);
}

[Test]
walks_every_token_of_every_source_file_part_4() {
    walks_tokens(3);
}

const TOKEN_PARTS: ulong = 4;

# Walks the tokens of every `TOKEN_PARTS`th source file of the repository,
# from the `part`th.
walks_tokens(part: ulong) {
    var files = Array<Path>();
    for (var folder in ["runtime", "tools", "tests", "docs/examples"]) {
        collect_sources(Path("..").join(folder), files);
    }
    expect_true(files.count > 400, "the repository's sources are found from tools/");
    ulong walked = 0;
    ulong tokens = 0;
    ulong comments = 0;
    ulong failures = 0;
    var i = part;
    while (i < files.count) {
        var file = files[i];
        i += TOKEN_PARTS;
        var source = File.read_to_string(file);
        if (source.is_err()) {
            continue;
        }
        var found = problem(source.value());
        if (!found.is_empty) {
            print($"{file}: {found}");
            failures += 1;
            continue;
        }
        var module = parse.parse_written(source.value());
        if (module.is_err()) {
            # A test of the parser's errors.
            continue;
        }
        var table = module.value().tokens.value();
        walked += 1;
        tokens += table.tokens.count;
        comments += comment_count(table);
    }
    print($"walked {walked} files: {tokens} tokens, {comments} comments");
    expect_true(walked * TOKEN_PARTS > 400, "most files parse");
    expect_equal(failures, 0 as ulong);
}
