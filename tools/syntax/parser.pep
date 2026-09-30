## The parser: builds a lossless syntax tree (see `Node`) from tokens.
##
## It follows the compiler's own grammar (crates/pepper-parser) decision for
## decision, including where a line break ends an expression, so a tool that
## changes only whitespace between the tree's tokens keeps the program's
## meaning. Where the compiler would reject a program, this parser may accept
## it; it is meant for source that compiles.
import "lexer";

import "token";
import "tree";

# The words `identifier()` in the compiler refuses as names.
reserved_words(): HashSet<String> {
    var words = HashSet<String>();
    words.insert("import");
    words.insert("struct");
    words.insert("var");
    words.insert("const");
    words.insert("if");
    words.insert("else");
    words.insert("while");
    words.insert("for");
    words.insert("return");
    words.insert("extern");
    words.insert("and");
    words.insert("or");
    words.insert("new");
    words.insert("construct");
    words.insert("destruct");
    words.insert("static");
    words.insert("sizeof");
    words.insert("true");
    words.insert("false");
    words.insert("trait");
    words.insert("extend");
    words.insert("type");
    words.insert("export");
    words.insert("with");
    words.insert("enum");
    words.insert("match");
    return words;
}

# The words that stop a statement from being read as a `Type name`
# declaration (the list in the compiler's `statement()`).
statement_keywords(): HashSet<String> {
    var words = HashSet<String>();
    words.insert("if");
    words.insert("while");
    words.insert("return");
    words.insert("break");
    words.insert("continue");
    words.insert("struct");
    words.insert("extern");
    words.insert("import");
    words.insert("true");
    words.insert("false");
    words.insert("sizeof");
    words.insert("and");
    words.insert("or");
    words.insert("new");
    words.insert("construct");
    words.insert("destruct");
    words.insert("static");
    words.insert("trait");
    words.insert("extend");
    words.insert("with");
    words.insert("enum");
    words.insert("match");
    return words;
}

# The operators a method may be named after, as `bool ==(T other)`.
operator_method_names(): HashSet<String> {
    var names = HashSet<String>();
    names.insert("<<=");
    names.insert(">>=");
    names.insert("==");
    names.insert("!=");
    names.insert("!!");
    names.insert("<=");
    names.insert(">=");
    names.insert("+=");
    names.insert("-=");
    names.insert("*=");
    names.insert("/=");
    names.insert("%=");
    names.insert("++");
    names.insert("--");
    names.insert("<<");
    names.insert(">>");
    names.insert("**");
    names.insert("&&");
    names.insert("||");
    names.insert("&=");
    names.insert("|=");
    names.insert("^=");
    names.insert("+");
    names.insert("-");
    names.insert("*");
    names.insert("/");
    names.insert("%");
    names.insert("<");
    names.insert(">");
    names.insert("&");
    names.insert("|");
    names.insert("^");
    names.insert("!");
    names.insert("~");
    return names;
}

# Whether a node of `kind` ends in `;` (rather than in a block).
ends_in_semicolon(kind: int): bool {
    return kind == NODE_VARIABLE
        or kind == NODE_DESTRUCTURE
        or kind == NODE_TYPE_ALIAS
        or kind == NODE_EXPRESSION_STATEMENT
        or kind == NODE_RETURN
        or kind == NODE_JUMP
        or kind == NODE_IMPORT
        or kind == NODE_EXPORT_ALIAS
        or kind == NODE_EXTERN_FUNCTION;
}

# Recursive descent over the token list. Every parse method returns a node;
# on a syntax error it sets `_failed` and the node is incomplete. A method
# that tries one reading and falls back to another saves `_position`, and
# restores it (clearing `_failed`) when the first fails.
struct Parser {
    Token[] _tokens;
    ulong _position;
    bool _failed;
    bool _has_error;
    String _error_message = "";
    ulong _error_offset;
    # Set by a missing `;`, which is reported over any error found further
    # on, like the compiler's hard errors.
    bool _missing_semicolon;
    # Whether a type is being read where an expression could also start, in
    # which case `a.b` is a qualified type only when `a` names an import.
    bool _probing;
    HashSet<String> _qualifiers = HashSet<String>();
    HashSet<String> _reserved = reserved_words();
    HashSet<String> _statement_keywords = statement_keywords();
    HashSet<String> _operator_names = operator_method_names();

    construct(this._tokens = Array<Token>()) {}

    # ── Token access ─────────────────────────────────────────────────────────

    _peek(): Token {
        return _tokens[_position];
    }

    _peek_at(offset: ulong): Token {
        ulong index = _position + offset;
        if (index >= _tokens.count()) {
            return _tokens.last();
        }
        return _tokens[index];
    }

    _advance(): Token {
        var token = _tokens[_position];
        if (token.kind != TOKEN_END) {
            _position += 1;
        }
        return token;
    }

    # Takes the next token as a leaf of `node`.
    _take(node: Node) {
        node.add_token(_advance());
    }

    _at(punctuation: String): bool {
        return _peek().is(punctuation);
    }

    _at_word(word: String): bool {
        return _peek().is_word(word);
    }

    _at_end(): bool {
        return _peek().kind == TOKEN_END;
    }

    # Whether the next token is a name: an identifier that is not reserved.
    _at_name(): bool {
        var token = _peek();
        return token.kind == TOKEN_IDENTIFIER and !_reserved.contains(token.text);
    }

    # Whether the token at `offset` follows the one before it with no space.
    _adjacent(offset: ulong): bool {
        return !_peek_at(offset).space_before;
    }

    _fail(message: String) {
        var offset = _peek().offset;
        if (!_missing_semicolon and (!_has_error or offset > _error_offset)) {
            _error_message = message;
            _error_offset = offset;
            _has_error = true;
        }
        _failed = true;
    }

    _restore(position: ulong) {
        _position = position;
        _failed = false;
    }

    # Takes the punctuation `text` into `node`, or fails.
    _expect(node: Node, text: String) {
        if (_at(text)) {
            _take(node);
        } else {
            _fail("expected '" + text + "'");
        }
    }

    # Takes a name into `node`, or fails.
    _expect_name(node: Node, what: String) {
        if (_at_name()) {
            _take(node);
        } else {
            _fail("expected " + what);
        }
    }

    # Ends a simple statement or declaration: takes its `;`, or fails with
    # `expected ';'` right after its last token, as the compiler's
    # `missing_semicolon` does.
    _finish_statement(node: Node) {
        if (_at(";")) {
            _take(node);
            return;
        }
        var last = _tokens[_position - 1];
        _error_message = "expected ';'";
        _error_offset = last.offset + last.text.size();
        _has_error = true;
        _missing_semicolon = true;
        _failed = true;
    }

    # The operator at the input, joining the adjacent tokens that the lexer
    # keeps apart: `>` into `>>`, `>=` and `>>=`, and `!` into the truth
    # test `!!`. Expressions never ask for `!!`: `!!x` is two prefix `!`.
    _operator_text(): String {
        var token = _peek();
        if (token.kind != TOKEN_PUNCTUATION) {
            return "";
        }
        if (token.text == "!" and _peek_at(1).is("!") and _adjacent(1)) {
            return "!!";
        }
        if (token.text != ">") {
            return token.text;
        }
        if (_peek_at(1).is(">") and _adjacent(1)) {
            if (_peek_at(2).is("=") and _adjacent(2)) {
                return ">>=";
            }
            return ">>";
        }
        if (_peek_at(1).is("=") and _adjacent(1)) {
            return ">=";
        }
        return ">";
    }

    # Takes the operator `text` (as `operator_text()` spelled it) into `node`
    # as one token.
    _take_operator(node: Node, text: String) {
        var first = _peek();
        if (first.text == text) {
            _take(node);
            return;
        }
        var merged = Token(TOKEN_PUNCTUATION, text, first.offset);
        merged.newlines_before = first.newlines_before;
        merged.newlines_after_comments = first.newlines_after_comments;
        merged.space_before = first.space_before;
        merged.leading_comments = first.leading_comments;
        ulong count = text.size();
        ulong i = 0;
        var last = first;
        while (i < count) {
            last = _advance();
            i += 1;
        }
        merged.trailing_comment = last.trailing_comment;
        node.add_token(merged);
    }

    # ── Types ────────────────────────────────────────────────────────────────

    # The compiler's `type_name`: a function type, or a named type with
    # array and pointer suffixes.
    _type_name(): Node {
        var node = Node(NODE_TYPE);
        if (_at("(")) {
            _function_type(node);
            return node;
        }
        if ((_at_word("shared") or _at_word("extern")) and _peek_at(1).is("(")) {
            ulong position = _position;
            _take(node);
            _function_type(node);
            if (!_failed) {
                return node;
            }
            _restore(position);
            node = Node(NODE_TYPE);
        }
        _type_base(node);
        if (_failed) {
            return node;
        }
        _type_suffixes(node);
        return node;
    }

    # `[]` array suffixes, `?` optional suffixes, then `*` pointer suffixes.
    _type_suffixes(node: Node) {
        while (true) {
            if (_at("[") and _peek_at(1).is("]")) {
                _take(node);
                _take(node);
                continue;
            }
            break;
        }
        _optional_suffixes(node);
        while (true) {
            if (_at("*") or _at("**")) {
                _take(node);
                continue;
            }
            break;
        }
    }

    # `?` optional suffixes, after a named type or a tuple type.
    _optional_suffixes(node: Node) {
        while (_at("?") and (!_probing or _optional_suffix_in_probe())) {
            _take(node);
        }
    }

    # Whether the `?` at the current token makes an optional type while
    # probing, where `a ? b : c` may be a ternary instead: the compiler's
    # `optional_suffix_in_probe`. It does when it closes or separates type
    # arguments, or when a name follows that ends the declaration
    # (`Node? x;`, `Node? x = y`, `Node? x` at the end of the line).
    _optional_suffix_in_probe(): bool {
        var next = _peek_at(1);
        if (next.is(">") or next.is(",")) {
            return true;
        }
        if (next.kind != TOKEN_IDENTIFIER or _reserved.contains(next.text)) {
            return false;
        }
        var after = _peek_at(2);
        return after.kind == TOKEN_END
            or after.newlines_before > 0
            or !next.trailing_comment.empty()
            or after.is(";")
            or after.is("}")
            or after.is("=");
    }

    # `( TYPE, ... ) => TYPE`, added to `node`, or a tuple type
    # `( TYPE, TYPE, ... )`: the compiler reads a tuple where `=>` is missing
    # after two or more types.
    _function_type(node: Node) {
        _take(node);
        int types = 0;
        while (true) {
            if (_at(")")) {
                _take(node);
                break;
            }
            # A tuple element's label, `line:` in `(line: int, column: int)`.
            if (_at_name() and _peek_at(1).is(":")) {
                _take(node);
                _take(node);
            }
            node.add(_type_name());
            if (_failed) {
                return;
            }
            types += 1;
            if (_at(",")) {
                _take(node);
                continue;
            }
            if (_at(")")) {
                _take(node);
                break;
            }
            _fail("expected ')'");
            return;
        }
        ulong position = _position;
        if (!_at("=>")) {
            if (types >= 2) {
                _restore(position);
                # `(int, String)?`: an optional tuple.
                _optional_suffixes(node);
                return;
            }
            _fail("expected '=>'");
            return;
        }
        _take(node);
        node.add(_type_name());
    }

    # A name, qualified by `.name`s written directly after it, then generic
    # arguments: the compiler's `type_name_base`.
    _type_base(node: Node) {
        if (!_at_name()) {
            _fail("expected a type");
            return;
        }
        var first = _advance();
        node.add_token(first);
        _qualified_tail(node, first.text);
        if (_at("<")) {
            node.add(_type_arguments());
        }
    }

    # `.name` segments after `first`: always in a declaration, and while
    # probing only after an import's qualifier.
    _qualified_tail(node: Node, first: String) {
        if (_probing and !_qualifiers.contains(first)) {
            return;
        }
        while (_at(".")
            and _adjacent(0)
            and _adjacent(1)
            and _peek_at(1).kind == TOKEN_IDENTIFIER
            and !_reserved.contains(_peek_at(1).text)) {
            _take(node);
            _take(node);
        }
    }

    _type_arguments(): Node {
        var node = Node(NODE_TYPE_ARGUMENTS);
        _take(node);
        while (true) {
            node.add(_type_name());
            if (_failed) {
                return node;
            }
            if (_at(",")) {
                _take(node);
                continue;
            }
            if (_at(">")) {
                _take(node);
                return node;
            }
            _fail("expected '>'");
            return node;
        }
        return node;
    }

    # A type where an expression could also start.
    _probe_type(): Node {
        bool outer = _probing;
        _probing = true;
        var node = _type_name();
        _probing = outer;
        return node;
    }

    # ── Expressions ──────────────────────────────────────────────────────────

    _expression(): Node {
        return _assignment();
    }

    _assignment(): Node {
        var lhs = _ternary();
        if (_failed) {
            return lhs;
        }
        var op = _operator_text();
        if (op == "*="
            or op == "/="
            or op == "%="
            or op == "+="
            or op == "-="
            or op == "<<="
            or op == ">>="
            or op == "&="
            or op == "^="
            or op == "|="
            or op == "=") {
            var node = Node(NODE_BINARY);
            node.add(lhs);
            _take_operator(node, op);
            node.add(_assignment());
            return node;
        }
        return lhs;
    }

    _ternary(): Node {
        var condition = _logical_or();
        if (_failed) {
            return condition;
        }
        if (!_at("?")) {
            return condition;
        }
        var node = Node(NODE_TERNARY);
        node.add(condition);
        _take(node);
        node.add(_expression());
        if (_failed) {
            return node;
        }
        _expect(node, ":");
        if (_failed) {
            return node;
        }
        node.add(_expression());
        return node;
    }

    # The binary operator at the input for precedence `level` (1 is `||`,
    # 9 is `*`), or "" when there is none.
    _binary_operator(level: int): String {
        var op = _operator_text();
        var token = _peek();
        if (level == 1) {
            if (op == "||" or token.is_word("or")) {
                return token.text;
            }
        } else if (level == 2) {
            if (op == "&&" or token.is_word("and")) {
                return token.text;
            }
        } else if (level == 3) {
            if (op == "|" or op == "^") {
                return op;
            }
        } else if (level == 4) {
            if (op == "&") {
                return op;
            }
        } else if (level == 5) {
            if (op == "===" or op == "!==" or op == "==" or op == "!=") {
                return op;
            }
        } else if (level == 6) {
            if (op == "<=" or op == ">=" or op == "<" or op == ">") {
                return op;
            }
        } else if (level == 7) {
            if (op == "<<" or op == ">>") {
                return op;
            }
        } else if (level == 8) {
            if (op == "+" or op == "-") {
                return op;
            }
        } else if (level == 9) {
            if (op == "*" or op == "/" or op == "%") {
                return op;
            }
        }
        return "";
    }

    _binary_operand(level: int): Node {
        if (level == 1) {
            return _binary_level(2);
        }
        if (level == 6) {
            return _is_test();
        }
        if (level < 9) {
            return _binary_level(level + 1);
        }
        return _prefix_increment();
    }

    # `value is Pattern`, between the relational and shift levels as in the
    # compiler's `is_test`. `is` is a keyword only here, so it stays usable
    # as a name.
    _is_test(): Node {
        var value = _binary_level(7);
        if (_failed or !_at_word("is")) {
            return value;
        }
        var node = Node(NODE_BINARY);
        node.add(value);
        _take(node);
        node.add(_pattern());
        return node;
    }

    # A left-associative binary level, the compiler's `binary_left`.
    _binary_level(level: int): Node {
        var lhs = _binary_operand(level);
        if (_failed) {
            return lhs;
        }
        while (true) {
            var op = _binary_operator(level);
            if (op.empty()) {
                break;
            }
            var node = Node(NODE_BINARY);
            node.add(lhs);
            _take_operator(node, op);
            node.add(_binary_operand(level));
            lhs = node;
            if (_failed) {
                return lhs;
            }
        }
        return lhs;
    }

    _logical_or(): Node {
        return _binary_level(1);
    }

    # Prefix `++` and `--`.
    _prefix_increment(): Node {
        if (_at("++") or _at("--")) {
            var node = Node(NODE_PREFIX);
            _take(node);
            node.add(_unary());
            return node;
        }
        return _unary();
    }

    # Prefix `+`, `-`, `~` and `!`.
    _unary(): Node {
        if (_at("+") or _at("-") or _at("~") or _at("!")) {
            var node = Node(NODE_PREFIX);
            _take(node);
            # The operand may itself be prefixed: `!!x` is `!(!x)`.
            node.add(_unary());
            return node;
        }
        return _cast();
    }

    _cast(): Node {
        var operand = _power();
        if (_failed) {
            return operand;
        }
        if (_at_word("as")) {
            var node = Node(NODE_CAST);
            node.add(operand);
            _take(node);
            node.add(_type_name());
            return node;
        }
        return operand;
    }

    # `**`, right-associative.
    _power(): Node {
        var base = _postfix();
        if (_failed) {
            return base;
        }
        if (_at("**")) {
            var node = Node(NODE_BINARY);
            node.add(base);
            _take(node);
            node.add(_power());
            return node;
        }
        return base;
    }

    _postfix(): Node {
        var operand = _atom();
        while (!_failed) {
            if (_at(".")) {
                var node = Node(NODE_MEMBER);
                node.add(operand);
                _take(node);
                # A tuple element, `t.0`.
                if (_peek().kind == TOKEN_NUMBER) {
                    _take(node);
                    operand = node;
                    continue;
                }
                _expect_name(node, "member name");
                if (_failed) {
                    return node;
                }
                # `x.map<long>(f)`: type arguments written right after the
                # name, with `(` right after the `>`.
                if (_at("<") and _adjacent(0)) {
                    ulong position = _position;
                    var arguments = _type_arguments();
                    if (!_failed and _at("(") and _adjacent(0)) {
                        node.add(arguments);
                    } else {
                        _restore(position);
                    }
                }
                operand = node;
                continue;
            }
            if (_at("[")) {
                var node = Node(NODE_INDEX);
                node.add(operand);
                _take(node);
                node.add(_expression());
                if (_failed) {
                    return node;
                }
                _expect(node, "]");
                operand = node;
                continue;
            }
            if (_at("(")) {
                var node = Node(NODE_CALL);
                node.add(operand);
                node.add(_arguments());
                operand = node;
                continue;
            }
            if (_at("++") or _at("--")) {
                var node = Node(NODE_POSTFIX);
                node.add(operand);
                _take(node);
                operand = node;
                continue;
            }
            break;
        }
        return operand;
    }

    _arguments(): Node {
        var node = Node(NODE_ARGUMENTS);
        _take(node);
        if (!_at(")")) {
            while (true) {
                node.add(_expression());
                if (_failed) {
                    return node;
                }
                if (_at(",")) {
                    _take(node);
                    continue;
                }
                break;
            }
        }
        _expect(node, ")");
        return node;
    }

    _atom(): Node {
        if (_at("(")) {
            ulong position = _position;
            var closure = _closure_literal();
            if (!_failed) {
                return closure;
            }
            _restore(position);
            var node = Node(NODE_PARENTHESIZED);
            _take(node);
            # `(line: 3, column: 7)`: a label makes it a tuple literal.
            bool labeled = _at_tuple_label();
            if (labeled) {
                node.kind = NODE_TUPLE;
            }
            node.add(_tuple_element(labeled));
            if (_failed) {
                return node;
            }
            # `(a, b)`: a comma makes it a tuple literal.
            if (_at(",")) {
                node.kind = NODE_TUPLE;
                while (_at(",")) {
                    _take(node);
                    node.add(_tuple_element(labeled));
                    if (_failed) {
                        return node;
                    }
                }
            } else if (labeled) {
                _fail("expected ','");
                return node;
            }
            _expect(node, ")");
            return node;
        }
        return _primary();
    }

    _at_tuple_label(): bool {
        return _at_name() and _peek_at(1).is(":");
    }

    # One element of a tuple literal: `label: expression` when `labeled`,
    # else an expression alone.
    _tuple_element(labeled: bool): Node {
        if (!labeled) {
            return _expression();
        }
        var node = Node(NODE_TUPLE_ELEMENT);
        if (!_at_tuple_label()) {
            _fail("expected a label ('name: value'), as the first element has one");
            return node;
        }
        _take(node);
        _take(node);
        node.add(_expression());
        return node;
    }

    _primary(): Node {
        var token = _peek();
        if (token.is_word("match")) {
            return _match_expression();
        }
        if (token.is_word("true")
            or token.is_word("false")
            or token.is_word("__null")
            or token.kind == TOKEN_NUMBER
            or token.kind == TOKEN_STRING
            or token.kind == TOKEN_CHARACTER) {
            return Node.of_token(_advance());
        }
        # A `-` written directly before a number is part of the literal.
        if (token.is("-") and _peek_at(1).kind == TOKEN_NUMBER and _adjacent(1)) {
            var node = Node(NODE_PREFIX);
            _take(node);
            _take(node);
            return node;
        }
        if (token.is_word("sizeof")) {
            var node = Node(NODE_SIZEOF);
            _take(node);
            _expect(node, "<");
            if (_failed) {
                return node;
            }
            node.add(_type_name());
            if (_failed) {
                return node;
            }
            _expect(node, ">");
            if (_failed) {
                return node;
            }
            if (_at("(")) {
                _take(node);
                _expect(node, ")");
            }
            return node;
        }
        if (!_at_name()) {
            _fail("expected expression");
            return Node(NODE_TOKEN);
        }
        ulong position = _position;
        # `m.Box<int>()`: a generic type of an imported module.
        if (_qualifiers.contains(token.text) and _peek_at(1).is(".") and _adjacent(1)) {
            var probe = _probe_type();
            if (!_failed and _qualified_generic(probe) and (_at("(") or _at("."))) {
                var literal = Node(NODE_TYPE_LITERAL);
                literal.add(probe);
                return literal;
            }
            _restore(position);
        }
        var name = Node.of_token(_advance());
        if (_at("<")) {
            ulong after = _position;
            _restore(position);
            var probe = _probe_type();
            if (!_failed) {
                var literal = Node(NODE_TYPE_LITERAL);
                literal.add(probe);
                return literal;
            }
            _restore(after);
        }
        return name;
    }

    # Whether a type node is qualified (`m.Box`) and has type arguments.
    _qualified_generic(candidate: Node): bool {
        bool qualified = false;
        bool generic = false;
        for (var child in candidate.children) {
            if (child.is_token(".")) {
                qualified = true;
            }
            if (child.kind == NODE_TYPE_ARGUMENTS) {
                generic = true;
            }
        }
        return qualified and generic;
    }

    _closure_literal(): Node {
        var node = Node(NODE_CLOSURE);
        var parameters = Node(NODE_CLOSURE_PARAMETERS);
        _take(parameters);
        while (true) {
            if (_at(")")) {
                _take(parameters);
                break;
            }
            if (!_at_name()) {
                _fail("expected parameter name");
                return node;
            }
            var parameter = Node(NODE_CLOSURE_PARAMETER);
            _take(parameter);
            if (_at(":")) {
                _take(parameter);
                parameter.add(_type_name());
                if (_failed) {
                    return node;
                }
            }
            parameters.add(parameter);
            if (_at(",")) {
                _take(parameters);
                continue;
            }
            if (_at(")")) {
                _take(parameters);
                break;
            }
            _fail("expected ')'");
            return node;
        }
        node.add(parameters);
        if (_at(":")) {
            _take(node);
            node.add(_type_name());
            if (_failed) {
                return node;
            }
        }
        if (!_at("=>")) {
            _fail("expected '=>'");
            return node;
        }
        _take(node);
        if (_at("{")) {
            node.add(_block(Array<Node>()));
        } else {
            node.add(_expression());
        }
        return node;
    }

    # ── Statements ───────────────────────────────────────────────────────────

    _attributes(): Node[] {
        var list = Array<Node>();
        # `[]` starts a Pepper-style indexer (`[](index: ulong): T`).
        while (_at("[") and !_peek_at(1).is("]")) {
            var node = Node(NODE_ATTRIBUTE);
            _take(node);
            node.add(_expression());
            if (_failed) {
                return list;
            }
            _expect(node, "]");
            if (_failed) {
                return list;
            }
            list.append(node);
        }
        return list;
    }

    _block(prefix: Node[]): Node {
        var node = Node(NODE_BLOCK);
        for (var item in prefix) {
            node.add(item);
        }
        _expect(node, "{");
        if (_failed) {
            return node;
        }
        while (true) {
            if (_at("}") or _at_end()) {
                break;
            }
            if (_at(";")) {
                var empty = Node(NODE_EMPTY);
                _take(empty);
                node.add(empty);
                continue;
            }
            var statement = _statement();
            if (_failed) {
                return node;
            }
            if (ends_in_semicolon(statement.kind)) {
                _finish_statement(statement);
            }
            node.add(statement);
        }
        _expect(node, "}");
        return node;
    }

    _statement(): Node {
        if (_at("[")) {
            var list = _attributes();
            if (_failed) {
                return Node(NODE_BLOCK);
            }
            return _block(list);
        }
        if (_at("{")) {
            return _block(Array<Node>());
        }
        if (_at_word("if")) {
            return _if_statement();
        }
        if (_at_word("while")) {
            var node = Node(NODE_WHILE);
            _take(node);
            node.add(_expression());
            if (_failed) {
                return node;
            }
            node.add(_block(Array<Node>()));
            return node;
        }
        if (_at_word("for")) {
            return _for_statement();
        }
        if (_at_word("with")) {
            return _with_statement();
        }
        if (_at_word("match")) {
            return _match_statement();
        }
        if (_at_word("return")) {
            var node = Node(NODE_RETURN);
            _take(node);
            if (!_at(";") and !_at("}")) {
                node.add(_expression());
            }
            return node;
        }
        if (_at_word("break") or _at_word("continue")) {
            var node = Node(NODE_JUMP);
            _take(node);
            return node;
        }
        if ((_at_word("var") or _at_word("const")) and _peek_at(1).is("(")) {
            return _destructure();
        }
        var token = _peek();
        bool declaration = token.is_word("var")
            or token.is_word("const")
            or (token.is_word("extern") and _peek_at(1).is("("))
            or (token.kind == TOKEN_IDENTIFIER and !_statement_keywords.contains(token.text));
        if (declaration) {
            ulong position = _position;
            var variable = _variable_declaration(Array<Node>());
            if (!_failed and _declaration_boundary()) {
                return variable;
            }
            _restore(position);
        }
        var node = Node(NODE_EXPRESSION_STATEMENT);
        node.add(_expression());
        return node;
    }

    _if_statement(): Node {
        var node = Node(NODE_IF);
        _take(node);
        node.add(_expression());
        if (_failed) {
            return node;
        }
        node.add(_block(Array<Node>()));
        if (_failed) {
            return node;
        }
        if (_at_word("else")) {
            _take(node);
            if (_at_word("if")) {
                node.add(_if_statement());
            } else {
                node.add(_block(Array<Node>()));
            }
        }
        return node;
    }

    _for_statement(): Node {
        var node = Node(NODE_FOR);
        _take(node);
        bool parenthesized = _at("(");
        if (parenthesized) {
            _take(node);
        }
        if (_at_word("var") and _peek_at(1).is("(")) {
            # `for (var (k, v) in pairs)`: a pattern.
            var pattern = Node(NODE_DESTRUCTURE);
            _take(pattern);
            pattern.add(_binding_pattern());
            node.add(pattern);
        } else {
            node.add(_variable_declaration(Array<Node>()));
        }
        if (_failed) {
            return node;
        }
        if (!_at_word("in")) {
            _fail("expected 'in'");
            return node;
        }
        _take(node);
        node.add(_expression());
        if (_failed) {
            return node;
        }
        if (parenthesized) {
            _expect(node, ")");
            if (_failed) {
                return node;
            }
        }
        node.add(_block(Array<Node>()));
        return node;
    }

    _with_statement(): Node {
        var node = Node(NODE_WITH);
        _take(node);
        bool parenthesized = _at("(");
        if (parenthesized) {
            _take(node);
        }
        ulong position = _position;
        bool is_var = _at_word("var") or _at_word("const");
        var binding = _variable_declaration(Array<Node>());
        if (!_failed and _has_value(binding) and !binding.child(0).is_token("const")) {
            node.add(binding);
        } else if (is_var) {
            if (!_failed) {
                _fail("expected '='");
            }
            return node;
        } else {
            _restore(position);
            node.add(_expression());
            if (_failed) {
                return node;
            }
        }
        if (parenthesized) {
            _expect(node, ")");
            if (_failed) {
                return node;
            }
        }
        node.add(_block(Array<Node>()));
        if (_failed) {
            return node;
        }
        if (_at_word("else")) {
            _take(node);
            node.add(_block(Array<Node>()));
        }
        return node;
    }

    _match_statement(): Node {
        var node = Node(NODE_MATCH);
        _take(node);
        node.add(_expression());
        if (_failed) {
            return node;
        }
        var arms = Node(NODE_MATCH_ARMS);
        node.add(arms);
        _expect(arms, "{");
        while (!_failed) {
            if (_at("}") or _at_end()) {
                break;
            }
            var arm = Node(NODE_MATCH_ARM);
            arms.add(arm);
            if (_at_word("else")) {
                _take(arm);
            } else {
                arm.add(_pattern());
                while (!_failed and _at(",")) {
                    _take(arm);
                    arm.add(_pattern());
                }
            }
            if (_failed) {
                return node;
            }
            _expect(arm, "=>");
            if (_failed) {
                return node;
            }
            arm.add(_block(Array<Node>()));
        }
        if (_failed) {
            return node;
        }
        _expect(arms, "}");
        return node;
    }

    # A `match` that produces a value: `match (x) { A, B => 1, else => 0 }`.
    # Each arm is patterns, `=>`, a value, and a `,` (optional after the
    # last).
    _match_expression(): Node {
        var node = Node(NODE_MATCH);
        _take(node);
        node.add(_expression());
        if (_failed) {
            return node;
        }
        var arms = Node(NODE_MATCH_ARMS);
        node.add(arms);
        _expect(arms, "{");
        while (!_failed) {
            if (_at("}") or _at_end()) {
                break;
            }
            var arm = Node(NODE_MATCH_ARM);
            arms.add(arm);
            if (_at_word("else")) {
                _take(arm);
            } else {
                arm.add(_pattern());
                while (!_failed and _at(",")) {
                    _take(arm);
                    arm.add(_pattern());
                }
            }
            if (_failed) {
                return node;
            }
            _expect(arm, "=>");
            if (_failed) {
                return node;
            }
            arm.add(_expression());
            if (_failed) {
                return node;
            }
            if (_at(",")) {
                _take(arm);
            } else if (!_at("}")) {
                _expect(arm, "}");
                return node;
            }
        }
        if (_failed) {
            return node;
        }
        _expect(arms, "}");
        return node;
    }

    # A case pattern: `Case`, `Enum.Case`, `module.Enum.Case`, or
    # `Case(x, _)`; or a literal: a number (`-1` too), string, character,
    # `true` or `false`.
    _pattern(): Node {
        var node = Node(NODE_PATTERN);
        var token = _peek();
        if (token.is_word("true")
            or token.is_word("false")
            or token.kind == TOKEN_NUMBER
            or token.kind == TOKEN_STRING
            or token.kind == TOKEN_CHARACTER
            or (token.is("-") and _peek_at(1).kind == TOKEN_NUMBER and _adjacent(1))) {
            node.add(_primary());
            return node;
        }
        _expect_name(node, "a case name");
        while (!_failed and _at(".") and _adjacent(0) and _peek_at(1).kind == TOKEN_IDENTIFIER and _adjacent(1)) {
            _take(node);
            _take(node);
        }
        if (_failed) {
            return node;
        }
        if (!_at("(")) {
            return node;
        }
        _take(node);
        while (!_failed) {
            if (_at(")")) {
                break;
            }
            _expect_name(node, "a name to bind");
            if (_at(",")) {
                _take(node);
                continue;
            }
            break;
        }
        _expect(node, ")");
        return node;
    }

    # Whether a variable node has an `= value`.
    _has_value(variable: Node): bool {
        for (var child in variable.children) {
            if (child.is_token("=")) {
                return true;
            }
        }
        return false;
    }

    # The compiler's `decl_boundary` or `missing_decl_semicolon`: what may
    # follow a `Type name` statement. After a line break it is one whose `;`
    # is missing, which `_finish_statement` then reports.
    _declaration_boundary(): bool {
        return _at_end() or _at(";") or _at("}") or _peek().newlines_before > 0;
    }

    # `(var | const) PATTERN = value`.
    _destructure(): Node {
        var node = Node(NODE_DESTRUCTURE);
        _take(node);
        node.add(_binding_pattern());
        if (_failed) {
            return node;
        }
        _expect(node, "=");
        if (_failed) {
            return node;
        }
        node.add(_expression());
        return node;
    }

    # `( binding, ... )` of a destructuring, where a binding is
    # `name [: Type]` or a nested pattern.
    _binding_pattern(): Node {
        var bindings = Node(NODE_CLOSURE_PARAMETERS);
        _take(bindings);
        while (true) {
            if (_at("(")) {
                bindings.add(_binding_pattern());
                if (_failed) {
                    return bindings;
                }
            } else {
                if (!_at_name()) {
                    _fail("expected variable name");
                    return bindings;
                }
                var binding = Node(NODE_CLOSURE_PARAMETER);
                _take(binding);
                if (_at(":")) {
                    _take(binding);
                    binding.add(_type_name());
                    if (_failed) {
                        return bindings;
                    }
                }
                bindings.add(binding);
            }
            if (_at(",")) {
                _take(bindings);
                continue;
            }
            _expect(bindings, ")");
            return bindings;
        }
        return bindings;
    }

    # `var name`, `const name` or `Type name`, then `[: Type] [= value]`.
    _variable_declaration(prefix: Node[]): Node {
        var node = Node(NODE_VARIABLE);
        for (var item in prefix) {
            node.add(item);
        }
        if (_at_word("var") or _at_word("const")) {
            _take(node);
            _expect_name(node, "variable name");
            if (_failed) {
                return node;
            }
        } else {
            node.add(_probe_type());
            if (_failed) {
                return node;
            }
            if (_at("(")) {
                _fail("expected variable name");
                return node;
            }
            _expect_name(node, "variable name");
            if (_failed) {
                return node;
            }
        }
        if (_at(":")) {
            _take(node);
            node.add(_type_name());
            if (_failed) {
                return node;
            }
        }
        if (_at("=")) {
            _take(node);
            node.add(_expression());
        }
        return node;
    }

    # ── Declarations ─────────────────────────────────────────────────────────

    _generic_parameters(): Node {
        var node = Node(NODE_GENERIC_PARAMETERS);
        _take(node);
        while (true) {
            if (_at(">")) {
                _take(node);
                return node;
            }
            var parameter = Node(NODE_GENERIC_PARAMETER);
            _expect_name(parameter, "generic parameter name");
            if (_failed) {
                return node;
            }
            if (_at("=")) {
                _take(parameter);
                parameter.add(_type_name());
                if (_failed) {
                    return node;
                }
            }
            node.add(parameter);
            if (_at(",")) {
                _take(node);
                continue;
            }
            _expect(node, ">");
            return node;
        }
        return node;
    }

    # `( parameter, ... )` of a function, method or constructor.
    _parameters(): Node {
        var node = Node(NODE_PARAMETERS);
        _expect(node, "(");
        if (_failed) {
            return node;
        }
        while (true) {
            if (_at(")")) {
                _take(node);
                return node;
            }
            node.add(_parameter());
            if (_failed) {
                return node;
            }
            if (_at(",")) {
                _take(node);
                continue;
            }
            _expect(node, ")");
            return node;
        }
        return node;
    }

    _parameter(): Node {
        # Attributes on a parameter (`[Move] value: T`).
        var attributes = _attributes();
        if (_failed) {
            var failed = Node(NODE_PARAMETER);
            for (var attribute in attributes) {
                failed.add(attribute);
            }
            return failed;
        }
        var node = _parameter_body(attributes);
        return node;
    }

    _parameter_body(attributes: Node[]): Node {
        var node = Node(NODE_PARAMETER);
        for (var attribute in attributes) {
            node.add(attribute);
        }
        if (_at_word("this")) {
            _take(node);
            _expect(node, ".");
            if (_failed) {
                return node;
            }
            _expect_name(node, "field name");
            if (_failed) {
                return node;
            }
            _expect(node, "=");
            if (_failed) {
                return node;
            }
            node.add(_expression());
            return node;
        }
        if (_at_word("var") or _at_word("const")) {
            var variable = _variable_declaration(attributes);
            variable.kind = NODE_PARAMETER;
            return variable;
        }
        # `name: Type`
        ulong position = _position;
        if (_at_name() and _peek_at(1).is(":")) {
            _take(node);
            _take(node);
            node.add(_type_name());
            if (!_failed) {
                _parameter_default(node);
                return node;
            }
            _restore(position);
            node = Node(NODE_PARAMETER);
            for (var attribute in attributes) {
                node.add(attribute);
            }
        }
        # `Type name`
        node.add(_type_name());
        if (_failed) {
            return node;
        }
        _expect_name(node, "parameter name");
        if (_failed) {
            return node;
        }
        _parameter_default(node);
        return node;
    }

    _parameter_default(node: Node) {
        if (_at("=")) {
            _take(node);
            node.add(_expression());
        }
    }

    # C parameters of an `extern` function: `Type name`, or a final `...`.
    _extern_parameters(): Node {
        var node = Node(NODE_PARAMETERS);
        _expect(node, "(");
        if (_failed) {
            return node;
        }
        while (true) {
            if (_at(")")) {
                _take(node);
                return node;
            }
            var parameter = Node(NODE_PARAMETER);
            if (_at("...")) {
                _take(parameter);
                node.add(parameter);
                _expect(node, ")");
                return node;
            }
            parameter.add(_type_name());
            if (_failed) {
                return node;
            }
            _expect_name(parameter, "parameter name");
            if (_failed) {
                return node;
            }
            node.add(parameter);
            if (_at(",")) {
                _take(node);
                continue;
            }
            _expect(node, ")");
            return node;
        }
        return node;
    }

    _extern_function(prefix: Node[]): Node {
        var node = Node(NODE_EXTERN_FUNCTION);
        for (var item in prefix) {
            node.add(item);
        }
        _take(node);
        node.add(_type_name());
        if (_failed) {
            return node;
        }
        _expect_name(node, "function name");
        if (_failed) {
            return node;
        }
        node.add(_extern_parameters());
        if (_failed) {
            return node;
        }
        _finish_statement(node);
        return node;
    }

    # The body of a function: a block, or `;` where `bodyless` allows one.
    _function_body(node: Node, bodyless: bool) {
        if (bodyless and _at(";")) {
            _take(node);
            return;
        }
        node.add(_block(Array<Node>()));
    }

    # A top-level function: `name[<T>](params)[: Type] { }` or
    # `Type name(params)[: Type] { }`.
    _function(prefix: Node[]): Node {
        var node = Node(NODE_FUNCTION);
        for (var item in prefix) {
            node.add(item);
        }
        if (!_at_name()) {
            _fail("expected declaration");
            return node;
        }
        var first = Node(NODE_TYPE);
        var name = _advance();
        first.add_token(name);
        _qualified_tail(first, name.text);
        bool qualified = first.count() > 1;
        if (_at("(") or _at("<")) {
            if (qualified) {
                _fail("expected function name");
                return node;
            }
            node.add_token(name);
            if (_at("<")) {
                node.add(_generic_parameters());
                if (_failed) {
                    return node;
                }
            }
            if (_at("(")) {
                node.add(_parameters());
                if (_failed) {
                    return node;
                }
            }
            _return_annotation(node);
            if (_failed) {
                return node;
            }
            _function_body(node, false);
            return node;
        }
        if (!_at_name() and !_at("[")) {
            _fail("expected function name");
            return node;
        }
        while (_at("[") and _peek_at(1).is("]")) {
            _take(first);
            _take(first);
        }
        node.add(first);
        _expect_name(node, "function name");
        if (_failed) {
            return node;
        }
        if (_at("(")) {
            node.add(_parameters());
            if (_failed) {
                return node;
            }
        }
        _return_annotation(node);
        if (_failed) {
            return node;
        }
        _function_body(node, false);
        return node;
    }

    # An optional `: Type` after a parameter list.
    _return_annotation(node: Node) {
        if (_at(":")) {
            _take(node);
            node.add(_type_name());
        }
    }

    # A method of a struct, extension or trait (`bodyless` for a trait).
    _method(prefix: Node[], bodyless: bool): Node {
        var node = Node(NODE_FUNCTION);
        for (var item in prefix) {
            node.add(item);
        }
        if (_at_word("static")) {
            _take(node);
        }
        ulong position = _position;
        ulong children = node.count();

        # Pepper-style indexer or operator method: `[](params)[: Type] { }`,
        # `==(params)[: Type] { }`.
        bool pepper_style = false;
        if (_at("[") and _peek_at(1).is("]")) {
            _take(node);
            _take(node);
            pepper_style = true;
        } else {
            var leading = _operator_text();
            if (_operator_names.contains(leading)) {
                _take_operator(node, leading);
                pepper_style = true;
            }
        }
        if (pepper_style) {
            if (_at("(")) {
                node.add(_parameters());
                if (_failed) {
                    return node;
                }
                _return_annotation(node);
                if (_failed) {
                    return node;
                }
                _function_body(node, bodyless);
                return node;
            }
            _restore(position);
            node.children.truncate(children);
        }

        # Indexer: `T [](params) { }`
        var index_type = Node(NODE_TYPE);
        _type_base(index_type);
        if (!_failed) {
            if (_at("[") and _peek_at(1).is("]") and _peek_at(2).is("(")) {
                node.add(index_type);
                _take(node);
                _take(node);
                node.add(_parameters());
                if (_failed) {
                    return node;
                }
                _function_body(node, false);
                return node;
            }
        }
        _restore(position);

        # `name[<T>](params)[: Type] { }`
        if (_at_name()) {
            _take(node);
            bool generic = false;
            if (_at("<")) {
                ulong after_name = _position;
                var generics = _generic_parameters();
                if (!_failed and _at("(")) {
                    node.add(generics);
                    generic = true;
                } else {
                    _restore(after_name);
                }
            }
            if (_at("(") or generic) {
                node.add(_parameters());
                if (_failed) {
                    return node;
                }
                _return_annotation(node);
                if (_failed) {
                    return node;
                }
                _function_body(node, bodyless);
                return node;
            }
        }

        # `Type name(params) { }`, where the name may be an operator.
        _restore(position);
        node.children.truncate(children);
        var return_type = Node(NODE_TYPE);
        _type_base(return_type);
        if (_failed) {
            return node;
        }
        node.add(return_type);
        var op = _operator_text();
        if (_at_name()) {
            _take(node);
        } else if (_operator_names.contains(op)) {
            _take_operator(node, op);
        } else {
            _fail("expected method name");
            return node;
        }
        if (_at("(")) {
            node.add(_parameters());
            if (_failed) {
                return node;
            }
        }
        _return_annotation(node);
        if (_failed) {
            return node;
        }
        _function_body(node, bodyless);
        return node;
    }

    # `{ member... }` of a struct (`kind` NODE_STRUCT), trait or extension.
    _members(kind: int): Node {
        var node = Node(NODE_MEMBERS);
        _expect(node, "{");
        if (_failed) {
            return node;
        }
        while (true) {
            if (_at("}") or _at_end()) {
                break;
            }
            if (_at(";")) {
                var empty = Node(NODE_EMPTY);
                _take(empty);
                node.add(empty);
                continue;
            }
            var attributes = _attributes();
            if (_failed) {
                return node;
            }
            if (kind != NODE_STRUCT) {
                node.add(_method(attributes, kind == NODE_TRAIT));
                if (_failed) {
                    return node;
                }
                continue;
            }
            if (_at_word("construct") or _at_word("new")) {
                var constructor = Node(NODE_CONSTRUCTOR);
                for (var item in attributes) {
                    constructor.add(item);
                }
                _take(constructor);
                constructor.add(_parameters());
                if (_failed) {
                    return node;
                }
                constructor.add(_block(Array<Node>()));
                if (_failed) {
                    return node;
                }
                node.add(constructor);
                continue;
            }
            if (_at_word("destruct")) {
                var destructor = Node(NODE_DESTRUCTOR);
                for (var item in attributes) {
                    destructor.add(item);
                }
                _take(destructor);
                destructor.add(_block(Array<Node>()));
                if (_failed) {
                    return node;
                }
                node.add(destructor);
                continue;
            }
            if (_at_word("extern") and !_peek_at(1).is("(")) {
                node.add(_extern_function(attributes));
                if (_failed) {
                    return node;
                }
                continue;
            }
            ulong position = _position;
            var member = _method(attributes, false);
            if (!_failed) {
                node.add(member);
                continue;
            }
            _restore(position);
            var field = _variable_declaration(attributes);
            if (_failed) {
                return node;
            }
            if (!_declaration_boundary()) {
                _fail("expected ';'");
                return node;
            }
            _finish_statement(field);
            node.add(field);
        }
        _expect(node, "}");
        return node;
    }

    # A named declaration with generic parameters and members: a struct or
    # trait.
    _aggregate(prefix: Node[], kind: int): Node {
        var node = Node(kind);
        for (var item in prefix) {
            node.add(item);
        }
        _take(node);
        _expect_name(node, "name");
        if (_failed) {
            return node;
        }
        if (_at("<")) {
            node.add(_generic_parameters());
            if (_failed) {
                return node;
            }
        }
        node.add(_members(kind));
        return node;
    }

    # `enum Name [: Type] { cases, methods }`. A case list ends at a case
    # without a `,`, or at a name that starts a method, as in the compiler's
    # `enum_declaration`.
    _enum(prefix: Node[]): Node {
        var node = Node(NODE_ENUM);
        for (var item in prefix) {
            node.add(item);
        }
        _take(node);
        _expect_name(node, "an enum name");
        if (_failed) {
            return node;
        }
        if (_at("<")) {
            node.add(_generic_parameters());
            if (_failed) {
                return node;
            }
        }
        if (_at(":")) {
            _take(node);
            node.add(_type_name());
            if (_failed) {
                return node;
            }
        }
        var members = Node(NODE_MEMBERS);
        node.add(members);
        _expect(members, "{");
        if (_failed) {
            return node;
        }
        while (true) {
            if (_at("}") or _at_end()) {
                break;
            }
            ulong position = _position;
            ulong children = members.count();
            var item = Node(NODE_ENUM_CASE);
            for (var attribute in _attributes()) {
                item.add(attribute);
            }
            if (_failed) {
                return node;
            }
            if (!_at_name() or _at_word("static")) {
                _restore(position);
                break;
            }
            _take(item);
            if (_at("(")) {
                item.add(_parameters());
                if (_failed or _at(":") or _at("{")) {
                    # A method: the cases are over.
                    _restore(position);
                    members.children.truncate(children);
                    break;
                }
            } else if (_at(":") or _at("{") or _at("<")) {
                _restore(position);
                break;
            }
            if (_at("=")) {
                _take(item);
                item.add(_expression());
                if (_failed) {
                    return node;
                }
            }
            members.add(item);
            if (_at(",")) {
                _take(item);
                continue;
            }
            break;
        }
        while (true) {
            if (_at("}") or _at_end()) {
                break;
            }
            if (_at(";")) {
                var empty = Node(NODE_EMPTY);
                _take(empty);
                members.add(empty);
                continue;
            }
            var attributes = _attributes();
            if (_failed) {
                return node;
            }
            members.add(_method(attributes, false));
            if (_failed) {
                return node;
            }
        }
        _expect(members, "}");
        return node;
    }

    _extension(prefix: Node[]): Node {
        var node = Node(NODE_EXTEND);
        for (var item in prefix) {
            node.add(item);
        }
        _take(node);
        node.add(_type_name());
        if (_failed) {
            return node;
        }
        if (_at_word("with")) {
            _take(node);
            while (true) {
                node.add(_type_name());
                if (_failed) {
                    return node;
                }
                if (_at(",")) {
                    _take(node);
                    continue;
                }
                break;
            }
        }
        node.add(_members(NODE_EXTEND));
        return node;
    }

    _type_alias(prefix: Node[]): Node {
        var node = Node(NODE_TYPE_ALIAS);
        for (var item in prefix) {
            node.add(item);
        }
        _take(node);
        _expect_name(node, "type name");
        if (_failed) {
            return node;
        }
        if (_at("<")) {
            node.add(_generic_parameters());
            if (_failed) {
                return node;
            }
        }
        _expect(node, "=");
        if (_failed) {
            return node;
        }
        node.add(_type_name());
        return node;
    }

    _declaration(): Node {
        var prefix = _attributes();
        if (_failed) {
            return Node(NODE_FUNCTION);
        }
        if (_at_word("export")) {
            prefix.append(Node.of_token(_advance()));
            if (_at("[")) {
                _fail("'export' goes after the attributes");
                return Node(NODE_FUNCTION);
            }
        }
        if (_at_word("struct")) {
            return _aggregate(prefix, NODE_STRUCT);
        }
        if (_at_word("trait")) {
            return _aggregate(prefix, NODE_TRAIT);
        }
        if (_at_word("enum")) {
            return _enum(prefix);
        }
        if (_at_word("extend")) {
            return _extension(prefix);
        }
        if (_at_word("type")) {
            return _type_alias(prefix);
        }
        if (_at_word("extern") and !_peek_at(1).is("(")) {
            return _extern_function(prefix);
        }
        ulong position = _position;
        var function = _function(prefix);
        if (!_failed) {
            return function;
        }
        _restore(position);
        var variable = _variable_declaration(prefix);
        if (!_failed and _declaration_boundary()) {
            return variable;
        }
        if (!_failed) {
            _fail("expected declaration");
        }
        return variable;
    }

    # `import ...`, or `export * from ...` / `export [...] from ...`, which
    # has the same shape but requires `*` or a list and takes no alias.
    _import_declaration(prefix: Node[]): Node {
        var node = Node(NODE_IMPORT);
        for (var item in prefix) {
            node.add(item);
        }
        bool reexport = _at_word("export");
        _take(node);
        if (reexport and _at("*")) {
            _take(node);
            if (!_at_word("from")) {
                _fail("expected 'from'");
                return node;
            }
            _take(node);
        }
        bool list = _at("[");
        if (list) {
            var symbols = Node(NODE_IMPORT_LIST);
            _take(symbols);
            while (true) {
                if (_at("]") and symbols.count() == 1) {
                    break;
                }
                var symbol = Node(NODE_IMPORT_SYMBOL);
                _expect_name(symbol, "name");
                if (_failed) {
                    return node;
                }
                if (_at_word("as")) {
                    _take(symbol);
                    _expect_name(symbol, "name");
                    if (_failed) {
                        return node;
                    }
                }
                symbols.add(symbol);
                if (_at(",")) {
                    _take(symbols);
                    continue;
                }
                break;
            }
            _expect(symbols, "]");
            if (_failed) {
                return node;
            }
            node.add(symbols);
            if (!_at_word("from")) {
                _fail("expected 'from'");
                return node;
            }
            _take(node);
        }
        var name = _peek();
        if (name.kind == TOKEN_STRING) {
            _take(node);
        } else {
            _expect_name(node, "module name");
            if (_failed) {
                return node;
            }
        }
        ulong position = _position;
        if (!reexport and _at_word("as")) {
            _take(node);
            var alias = _peek();
            _expect_name(node, "name");
            if (_failed) {
                return node;
            }
            _qualifiers.insert(alias.text);
        } else {
            _restore(position);
            if (!list and !reexport and name.kind != TOKEN_STRING) {
                _qualifiers.insert(name.text);
            }
        }
        return node;
    }

    # Whether `export` is followed by `*` or `[`: an `export ... from`.
    _at_export_from(): bool {
        return _at_word("export") and (_peek_at(1).is("*") or _peek_at(1).is("["));
    }

    # `export name[.name] [as alias];`, a re-export. Fails (so the caller
    # reads a declaration instead) unless an `as` or `;` follows the name.
    _export_alias(prefix: Node[]): Node {
        var node = Node(NODE_EXPORT_ALIAS);
        for (var item in prefix) {
            node.add(item);
        }
        _take(node);
        if (!_at_name()) {
            _fail("expected name");
            return node;
        }
        var name = _advance();
        node.add_token(name);
        bool outer = _probing;
        _probing = false;
        _qualified_tail(node, name.text);
        _probing = outer;
        if (_at_word("as")) {
            _take(node);
            _expect_name(node, "name");
            return node;
        }
        if (!_at(";")) {
            _fail("expected ';'");
        }
        return node;
    }

    module(): Node {
        var node = Node(NODE_MODULE);
        while (true) {
            if (_at_end()) {
                break;
            }
            if (_at(";")) {
                var empty = Node(NODE_EMPTY);
                _take(empty);
                node.add(empty);
                continue;
            }
            ulong position = _position;
            var prefix = _attributes();
            if (_failed) {
                return node;
            }
            if (_at_word("import") or _at_export_from()) {
                var item = _import_declaration(prefix);
                if (_failed) {
                    return node;
                }
                _finish_statement(item);
                node.add(item);
                continue;
            }
            if (_at_word("export")) {
                ulong after_attributes = _position;
                var item = _export_alias(prefix);
                if (!_failed) {
                    _finish_statement(item);
                    node.add(item);
                    continue;
                }
                _restore(after_attributes);
            }
            _restore(position);
            var declaration = _declaration();
            if (_failed) {
                return node;
            }
            if (declaration.kind == NODE_VARIABLE or declaration.kind == NODE_TYPE_ALIAS) {
                _finish_statement(declaration);
            }
            node.add(declaration);
        }
        node.add_token(_advance());
        return node;
    }
}

## Parses Pepper source text into a syntax tree whose root is a
## `NODE_MODULE`.
##
## @param source the text of a Pepper source file
## @returns the tree, or the syntax error furthest into the source
export parse(source: String): Result<Node, SyntaxError> {
    var tokens = lex(source);
    if (tokens.is_err()) {
        return Result<Node, SyntaxError>.err(tokens.error());
    }
    var parser = Parser(tokens.value());
    var root = parser.module();
    if (parser._failed) {
        return Result<Node, SyntaxError>.err(SyntaxError(parser._error_message, parser._error_offset));
    }
    return Result<Node, SyntaxError>.ok(root);
}
