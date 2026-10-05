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
# Whether `token` is one of the words `identifier()` in the compiler refuses
# as names, compared in place.
is_reserved_word(source: String, token: Token): bool {
    if (token.kind != TokenKind.Identifier) {
        return false;
    }
    int first = source.byte_at(token.offset);
    if (first == 'a') {
        return token.spells(source, "and");
    } else if (first == 'c') {
        return token.spells(source, "const") or token.spells(source, "construct");
    } else if (first == 'd') {
        return token.spells(source, "destruct");
    } else if (first == 'e') {
        return token.spells(source, "else")
            or token.spells(source, "extern")
            or token.spells(source, "extend")
            or token.spells(source, "export")
            or token.spells(source, "enum");
    } else if (first == 'f') {
        return token.spells(source, "for") or token.spells(source, "false");
    } else if (first == 'i') {
        return token.spells(source, "import") or token.spells(source, "if");
    } else if (first == 'm') {
        return token.spells(source, "match");
    } else if (first == 'n') {
        return token.spells(source, "new");
    } else if (first == 'o') {
        return token.spells(source, "or");
    } else if (first == 'p') {
        return token.spells(source, "private");
    } else if (first == 'r') {
        return token.spells(source, "return");
    } else if (first == 's') {
        return token.spells(source, "struct") or token.spells(source, "static") or token.spells(source, "sizeof");
    } else if (first == 't') {
        return token.spells(source, "true") or token.spells(source, "trait") or token.spells(source, "type");
    } else if (first == 'v') {
        return token.spells(source, "var");
    } else if (first == 'w') {
        return token.spells(source, "while") or token.spells(source, "with");
    }
    return false;
}

# The words that stop a statement from being read as a `Type name`
# declaration (the list in the compiler's `statement()`).
# Whether `token` is one of the words that stop a statement from being read
# as a `Type name` declaration (the list in the compiler's `statement()`),
# compared in place.
is_statement_keyword(source: String, token: Token): bool {
    if (token.kind != TokenKind.Identifier) {
        return false;
    }
    int first = source.byte_at(token.offset);
    if (first == 'a') {
        return token.spells(source, "and");
    } else if (first == 'b') {
        return token.spells(source, "break");
    } else if (first == 'c') {
        return token.spells(source, "continue") or token.spells(source, "construct");
    } else if (first == 'd') {
        return token.spells(source, "destruct");
    } else if (first == 'e') {
        return token.spells(source, "extern") or token.spells(source, "extend") or token.spells(source, "enum");
    } else if (first == 'f') {
        return token.spells(source, "false");
    } else if (first == 'i') {
        return token.spells(source, "if") or token.spells(source, "import");
    } else if (first == 'm') {
        return token.spells(source, "match");
    } else if (first == 'n') {
        return token.spells(source, "new");
    } else if (first == 'o') {
        return token.spells(source, "or");
    } else if (first == 'r') {
        return token.spells(source, "return");
    } else if (first == 's') {
        return token.spells(source, "struct") or token.spells(source, "sizeof") or token.spells(source, "static");
    } else if (first == 't') {
        return token.spells(source, "true") or token.spells(source, "trait");
    } else if (first == 'w') {
        return token.spells(source, "while") or token.spells(source, "with");
    }
    return false;
}

# The operators a method may be named after, as `bool ==(T other)`.
operator_method_names(): HashSet<String> {
    return [
        "<<=",
        ">>=",
        "==",
        "!=",
        "!!",
        "<=",
        ">=",
        "+=",
        "-=",
        "*=",
        "/=",
        "%=",
        "++",
        "--",
        "<<",
        ">>",
        "**",
        "&&",
        "||",
        "&=",
        "|=",
        "^=",
        "+",
        "-",
        "*",
        "/",
        "%",
        "<",
        ">",
        "&",
        "|",
        "^",
        "!",
        "~"
    ];
}

# Whether a node of `kind` ends in `;` (rather than in a block).
ends_in_semicolon(kind: NodeKind): bool {
    return kind == NodeKind.Variable
        or kind == NodeKind.Destructure
        or kind == NodeKind.TypeAlias
        or kind == NodeKind.ExpressionStatement
        or kind == NodeKind.Return
        or kind == NodeKind.Jump
        or kind == NodeKind.Import
        or kind == NodeKind.ExportAlias
        or kind == NodeKind.ExternFunction;
}

# Recursive descent over the token list. Every parse method returns a node;
# on a syntax error it sets `_failed` and the node is incomplete. A method
# that tries one reading and falls back to another saves `_position`, and
# restores it (clearing `_failed`) when the first fails.
struct Parser {
    Token[] _tokens;
    ulong _position;
    bool _failed;
    # The syntax error furthest into the source so far.
    SyntaxError? _error;
    # Set by a missing `;`, which is reported over any error found further
    # on, like the compiler's hard errors.
    bool _missing_semicolon;
    # Whether a type is being read where an expression could also start, in
    # which case `a.b` is a qualified type only when `a` names an import.
    bool _probing;
    # The next type arguments are an `extend` target's, which may restate
    # the struct's constraints (`extend Box<T: Shape>`).
    bool _restating;
    HashSet<String> _qualifiers = HashSet<String>();
    # How many `static` blocks enclose the parser, inside which the names a
    # `for` or `var` binds qualify types too (`case.Type`), as in the
    # compiler.
    int _static_depth;
    # The operators a method may be named after; made when first needed.
    HashSet<String> _operator_names;
    # The text the tokens point into.
    String _source;

    construct(this._source = "", this._tokens = Array<Token>()) {}

    # ── Token access ─────────────────────────────────────────────────────────

    _peek(): Token {
        return _tokens[_position];
    }

    _peek_at(offset: ulong): Token {
        ulong index = _position + offset;
        if (index >= _tokens.count) {
            return _tokens.last();
        }
        return _tokens[index];
    }

    _advance(): Token {
        var token = _tokens[_position];
        if (token.kind != TokenKind.End) {
            _position += 1;
        }
        return token;
    }

    # Takes the next token as a leaf of `node`.
    _take(node: Node) {
        node.add_token(_advance());
    }

    _at(punctuation: String): bool {
        return _peek().is(_source, punctuation);
    }

    _at_word(word: String): bool {
        return _peek().is_word(_source, word);
    }

    _at_end(): bool {
        return _peek().kind == TokenKind.End;
    }

    # Whether the next token is a name: an identifier that is not reserved.
    _at_name(): bool {
        var token = _peek();
        return token.kind == TokenKind.Identifier and !is_reserved_word(_source, token);
    }

    # Whether the token at `offset` follows the one before it with no space.
    _adjacent(offset: ulong): bool {
        return !_peek_at(offset).space_before;
    }

    _fail(message: String) {
        var offset = _peek().offset;
        if (!_missing_semicolon and (!_error or offset > _error.value().offset)) {
            _error = Optional<SyntaxError>.Value(SyntaxError(message, offset));
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
        _error = Optional<SyntaxError>.Value(SyntaxError("expected ';'", last.offset + last.size));
        _missing_semicolon = true;
        _failed = true;
    }

    # The byte length of the operator at the input, or 0 when the input is
    # not punctuation. It joins the adjacent tokens that the lexer keeps
    # apart: `>` into `>>`, `>=` and `>>=`, and `!` into the truth test
    # `!!`; since they are adjacent, the operator's text is that many bytes
    # of the source from the next token. Expressions never ask for `!!`:
    # `!!x` is two prefix `!`.
    _operator_size(): ulong {
        var token = _peek();
        if (token.kind != TokenKind.Punctuation) {
            return 0;
        }
        if (token.spells(_source, "!") and _peek_at(1).is(_source, "!") and _adjacent(1)) {
            return 2;
        }
        if (!token.spells(_source, ">")) {
            return token.size;
        }
        if (_peek_at(1).is(_source, ">") and _adjacent(1)) {
            if (_peek_at(2).is(_source, "=") and _adjacent(2)) {
                return 3;
            }
            return 2;
        }
        if (_peek_at(1).is(_source, "=") and _adjacent(1)) {
            return 2;
        }
        return 1;
    }

    # Whether the operator at the input, `size` bytes long (from
    # `_operator_size()`), is `text`.
    _operator_is(size: ulong, text: String): bool {
        return size == text.size and spells_at(_source, _peek().offset, size, text);
    }

    # The operator at the input, `size` bytes long, as a new String.
    _operator_text(size: ulong): String {
        return _source.substr_bytes(_peek().offset, size);
    }

    # Whether the operator at the input, `size` bytes long, can name a
    # method, as `bool ==(T other)`.
    _at_operator_name(size: ulong): bool {
        if (size == 0) {
            return false;
        }
        if (_operator_names === __null) {
            _operator_names = operator_method_names();
        }
        return _operator_names.contains(_operator_text(size));
    }

    # Takes the operator at the input, `size` bytes long (from
    # `_operator_size()` or a word operator's token), into `node` as one
    # token.
    _take_operator(node: Node, size: ulong) {
        var first = _peek();
        if (first.size == size) {
            _take(node);
            return;
        }
        # The joined tokens are adjacent, one byte each, so the merged
        # token's bytes in the source are its text.
        var merged = Token(TokenKind.Punctuation, first.offset, size);
        merged.newlines_before = first.newlines_before;
        merged.newlines_after_comments = first.newlines_after_comments;
        merged.space_before = first.space_before;
        merged._leading_comments = first._leading_comments;
        ulong i = 0;
        var last = first;
        while (i < size) {
            last = _advance();
            i += 1;
        }
        merged._trailing_comment = last._trailing_comment;
        node.add_token(merged);
    }

    # ── Types ────────────────────────────────────────────────────────────────

    # The compiler's `type_name`: a function type, or a named type with
    # array and pointer suffixes.
    _type_name(): Node {
        var node = Node(NodeKind.Type);
        if (_at("(")) {
            _function_type(node);
            return node;
        }
        if ((_at_word("shared") or _at_word("extern")) and _peek_at(1).is(_source, "(")) {
            ulong position = _position;
            _take(node);
            _function_type(node);
            if (!_failed) {
                return node;
            }
            _restore(position);
            node = Node(NodeKind.Type);
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
            if (_at("[") and _peek_at(1).is(_source, "]")) {
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
        if (next.is(_source, ">") or next.is(_source, ",")) {
            return true;
        }
        if (next.kind != TokenKind.Identifier or is_reserved_word(_source, next)) {
            return false;
        }
        var after = _peek_at(2);
        return after.kind == TokenKind.End
            or after.newlines_before > 0
            or next._trailing_comment !== __null
            or after.is(_source, ";")
            or after.is(_source, "}")
            or after.is(_source, "=");
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
            if (_at_name() and _peek_at(1).is(_source, ":")) {
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
        _qualified_tail(node, first);
        if (_at("<")) {
            node.add(_type_arguments());
        }
    }

    # `.name` segments after `first`: always in a declaration, and while
    # probing only after an import's qualifier.
    _qualified_tail(node: Node, first: Token) {
        if (_probing and !_qualifiers.contains(first.text(_source))) {
            return;
        }
        while (_at(".")
            and _adjacent(0)
            and _adjacent(1)
            and _peek_at(1).kind == TokenKind.Identifier
            and !is_reserved_word(_source, _peek_at(1))) {
            _take(node);
            _take(node);
        }
    }

    _type_arguments(): Node {
        var node = Node(NodeKind.TypeArguments);
        bool restating = _restating;
        _restating = false;
        _take(node);
        while (true) {
            if (_peek_at(0).kind == TokenKind.Number) {
                # A lane count, `16` in `__simd<byte, 16>`: the compiler's
                # `type_argument`.
                var count = Node(NodeKind.Type);
                _take(count);
                node.add(count);
            } else {
                node.add(_type_name());
            }
            if (_failed) {
                return node;
            }
            if (restating and _at(":")) {
                _take(node);
                node.add(_type_name());
                while (!_failed and _at("&")) {
                    _take(node);
                    node.add(_type_name());
                }
                if (_failed) {
                    return node;
                }
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
        var op = _operator_size();
        if (op > 0
            and (_operator_is(op, "*=")
                or _operator_is(op, "/=")
                or _operator_is(op, "%=")
                or _operator_is(op, "+=")
                or _operator_is(op, "-=")
                or _operator_is(op, "<<=")
                or _operator_is(op, ">>=")
                or _operator_is(op, "&=")
                or _operator_is(op, "^=")
                or _operator_is(op, "|=")
                or _operator_is(op, "="))) {
            var node = Node(NodeKind.Binary);
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
        var node = Node(NodeKind.Ternary);
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

    # The byte length of the binary operator at the input for precedence
    # `level` (1 is `||`, 9 is `*`), or 0 when there is none.
    _binary_operator(level: int): ulong {
        var op = _operator_size();
        if (level == 1) {
            if (_operator_is(op, "||") or _at_word("or")) {
                return _operator_size_or_word(op);
            }
        } else if (level == 2) {
            if (_operator_is(op, "&&") or _at_word("and")) {
                return _operator_size_or_word(op);
            }
        } else if (level == 3) {
            if (_operator_is(op, "|") or _operator_is(op, "^")) {
                return op;
            }
        } else if (level == 4) {
            if (_operator_is(op, "&")) {
                return op;
            }
        } else if (level == 5) {
            if (_operator_is(op, "===")
                or _operator_is(op, "!==")
                or _operator_is(op, "==")
                or _operator_is(op, "!=")) {
                return op;
            }
        } else if (level == 6) {
            if (_operator_is(op, "<=") or _operator_is(op, ">=") or _operator_is(op, "<") or _operator_is(op, ">")) {
                return op;
            }
        } else if (level == 7) {
            if (_operator_is(op, "<<") or _operator_is(op, ">>")) {
                return op;
            }
        } else if (level == 8) {
            if (_operator_is(op, "+") or _operator_is(op, "-")) {
                return op;
            }
        } else if (level == 9) {
            if (_operator_is(op, "*") or _operator_is(op, "/") or _operator_is(op, "%")) {
                return op;
            }
        }
        return 0;
    }

    # `op`, or for a word operator (`and`, `or`), the word's length.
    _operator_size_or_word(op: ulong): ulong {
        if (op > 0) {
            return op;
        }
        return _peek().size;
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

    # `a..b` or `a..>b`, between the shift and `is` levels as in the
    # compiler's `range`. Not associative.
    _range(): Node {
        var lhs = _binary_level(7);
        if (_failed or !(_at("..>") or _at(".."))) {
            return lhs;
        }
        var node = Node(NodeKind.Binary);
        node.add(lhs);
        _take(node);
        node.add(_binary_level(7));
        return node;
    }

    # `value is Pattern`, between the relational and shift levels as in the
    # compiler's `is_test`. `is` is a keyword only here, so it stays usable
    # as a name.
    _is_test(): Node {
        var value = _range();
        if (_failed or !_at_word("is")) {
            return value;
        }
        var node = Node(NodeKind.Binary);
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
            if (op == 0) {
                break;
            }
            var node = Node(NodeKind.Binary);
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
            var node = Node(NodeKind.Prefix);
            _take(node);
            node.add(_unary());
            return node;
        }
        return _unary();
    }

    # Prefix `+`, `-`, `~` and `!`.
    _unary(): Node {
        if (_at("+") or _at("-") or _at("~") or _at("!")) {
            var node = Node(NodeKind.Prefix);
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
            var node = Node(NodeKind.Cast);
            node.add(operand);
            _take(node);
            # `as?`: a trait value's conversion that may fail.
            if (_at("?") and _adjacent(0)) {
                _take(node);
            }
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
            var node = Node(NodeKind.Binary);
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
                var node = Node(NodeKind.Member);
                node.add(operand);
                _take(node);
                # A tuple element, `t.0`.
                if (_peek().kind == TokenKind.Number) {
                    _take(node);
                    operand = node;
                    continue;
                }
                _expect_name(node, "member name");
                if (_failed) {
                    return node;
                }
                # `x.map<long>(f)`: type arguments written right after the
                # name, with `(` right after the `>`; or `x.map<long>` as a
                # value, the expression ending after the `>`.
                if (_at("<") and _adjacent(0)) {
                    ulong position = _position;
                    var arguments = _type_arguments();
                    var ends = _at(";")
                        or _at(",")
                        or _at(")")
                        or _at("]")
                        or _at("}")
                        or _peek().kind == TokenKind.End;
                    if (!_failed and ((_at("(") and _adjacent(0)) or ends)) {
                        node.add(arguments);
                    } else {
                        _restore(position);
                    }
                }
                operand = node;
                continue;
            }
            if (_at("[")) {
                var node = Node(NodeKind.Index);
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
                var node = Node(NodeKind.Call);
                node.add(operand);
                node.add(_arguments());
                operand = node;
                continue;
            }
            if (_at("++") or _at("--") or (_at("?") and _propagates())) {
                var node = Node(NodeKind.Postfix);
                node.add(operand);
                _take(node);
                operand = node;
                continue;
            }
            break;
        }
        return operand;
    }

    # Whether the `?` at the current token is the postfix propagation
    # operator (`f()?`) rather than the start of a ternary's branches: the
    # compiler's `propagates`. It is when what follows cannot start an
    # expression, not when an operand follows, and, when the next token
    # could do either (`-`, `*`, `(`, ...), unless an expression and a `:`
    # follow.
    _propagates(): bool {
        var next = _peek_at(1);
        if (next.kind == TokenKind.End) {
            return true;
        }
        if (next.kind == TokenKind.Identifier) {
            return next.is_word(_source, "and")
                or next.is_word(_source, "or")
                or next.is_word(_source, "is")
                or next.is_word(_source, "as");
        }
        if (next.kind != TokenKind.Punctuation) {
            return false;
        }
        if (next.spells(_source, "&&") or next.spells(_source, "!=")) {
            return true;
        }
        int first = _source.byte_at(next.offset);
        if (!(first == '-'
            or first == '+'
            or first == '*'
            or first == '&'
            or first == '!'
            or next.spells(_source, "(")
            or next.spells(_source, "["))) {
            return true;
        }
        # Probe for `? expression :`, leaving no error behind.
        ulong position = _position;
        var error = _error;
        var missing_semicolon = _missing_semicolon;
        _advance();
        _expression();
        bool ternary = !_failed and _at(":");
        _restore(position);
        _error = error;
        _missing_semicolon = missing_semicolon;
        return !ternary;
    }

    _arguments(): Node {
        var node = Node(NodeKind.Arguments);
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
            var node = Node(NodeKind.Parenthesized);
            _take(node);
            # `(line: 3, column: 7)`: a label makes it a tuple literal.
            bool labeled = _at_tuple_label();
            if (labeled) {
                node.kind = NodeKind.Tuple;
            }
            node.add(_tuple_element(labeled));
            if (_failed) {
                return node;
            }
            # `(a, b)`: a comma makes it a tuple literal.
            if (_at(",")) {
                node.kind = NodeKind.Tuple;
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
        if (_at("[")) {
            return _collection_literal();
        }
        return _primary();
    }

    # `[a, b]`, an array literal, or `[k: v]` / `[:]`, a map literal: a `:`
    # after the first element makes it a map.
    _collection_literal(): Node {
        var node = Node(NodeKind.Array);
        _take(node);
        if (_at(":")) {
            node.kind = NodeKind.Map;
            _take(node);
            _expect(node, "]");
            return node;
        }
        while (!_at("]")) {
            var item = _expression();
            if (_failed) {
                node.add(item);
                return node;
            }
            if (node.count == 1 and _at(":")) {
                node.kind = NodeKind.Map;
            }
            if (node.kind == NodeKind.Map) {
                var entry = Node(NodeKind.MapEntry);
                entry.add(item);
                _expect(entry, ":");
                if (_failed) {
                    node.add(entry);
                    return node;
                }
                entry.add(_expression());
                node.add(entry);
                if (_failed) {
                    return node;
                }
            } else {
                node.add(item);
            }
            if (!_at(",")) {
                break;
            }
            _take(node);
        }
        _expect(node, "]");
        return node;
    }

    _at_tuple_label(): bool {
        return _at_name() and _peek_at(1).is(_source, ":");
    }

    # One element of a tuple literal: `label: expression` when `labeled`,
    # else an expression alone.
    _tuple_element(labeled: bool): Node {
        if (!labeled) {
            return _expression();
        }
        var node = Node(NodeKind.TupleElement);
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
        if (token.is_word(_source, "match")) {
            return _match_expression();
        }
        if (token.is_word(_source, "true")
            or token.is_word(_source, "false")
            or token.is_word(_source, "__null")
            or token.kind == TokenKind.Number
            or token.kind == TokenKind.String
            or token.kind == TokenKind.Character) {
            return Node.of_token(_advance());
        }
        # A `-` written directly before a number is part of the literal.
        if (token.is(_source, "-") and _peek_at(1).kind == TokenKind.Number and _adjacent(1)) {
            var node = Node(NodeKind.Prefix);
            _take(node);
            _take(node);
            return node;
        }
        if (token.is_word(_source, "sizeof")) {
            var node = Node(NodeKind.Sizeof);
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
            return Node(NodeKind.Token);
        }
        ulong position = _position;
        # `m.Box<int>()`: a generic type of an imported module.
        if (_peek_at(1).is(_source, ".") and _adjacent(1) and _qualifiers.contains(token.text(_source))) {
            var probe = _probe_type();
            if (!_failed and _qualified_generic(probe) and (_at("(") or _at("."))) {
                var literal = Node(NodeKind.TypeLiteral);
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
                var literal = Node(NodeKind.TypeLiteral);
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
            if (child.is_token(_source, ".")) {
                qualified = true;
            }
            if (child.kind == NodeKind.TypeArguments) {
                generic = true;
            }
        }
        return qualified and generic;
    }

    _closure_literal(): Node {
        var node = Node(NodeKind.Closure);
        var parameters = Node(NodeKind.ClosureParameters);
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
            var parameter = Node(NodeKind.ClosureParameter);
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
        while (_at("[") and !_peek_at(1).is(_source, "]")) {
            var node = Node(NodeKind.Attribute);
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
        var node = Node(NodeKind.Block);
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
                var empty = Node(NodeKind.Empty);
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
                return Node(NodeKind.Block);
            }
            # `[Likely]` or `[Unlikely]` above an `if`.
            if (_at_word("if")) {
                return _if_statement(list);
            }
            return _block(list);
        }
        if (_at("{")) {
            return _block(Array<Node>());
        }
        if (_at_word("if")) {
            return _if_statement(Array<Node>());
        }
        if (_at_word("while")) {
            var node = Node(NodeKind.While);
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
        if (_at_word("static") and (_peek_at(1).is(_source, "(") or _peek_at(1).is(_source, "{"))) {
            return _static_block(Array<Node>());
        }
        if (_at_word("match")) {
            return _match_statement();
        }
        if (_at_word("return")) {
            var node = Node(NodeKind.Return);
            _take(node);
            if (!_at(";") and !_at("}")) {
                node.add(_expression());
            }
            return node;
        }
        if (_at_word("break") or _at_word("continue")) {
            var node = Node(NodeKind.Jump);
            _take(node);
            return node;
        }
        if ((_at_word("var") or _at_word("const")) and _peek_at(1).is(_source, "(")) {
            return _destructure();
        }
        var token = _peek();
        bool declaration = token.is_word(_source, "var")
            or token.is_word(_source, "const")
            or (token.is_word(_source, "extern") and _peek_at(1).is(_source, "("))
            or (token.kind == TokenKind.Identifier and !is_statement_keyword(_source, token));
        if (declaration) {
            ulong position = _position;
            var variable = _variable_declaration(Array<Node>());
            if (!_failed and _declaration_boundary()) {
                _bind_qualifier(variable);
                return variable;
            }
            _restore(position);
        }
        var node = Node(NodeKind.ExpressionStatement);
        node.add(_expression());
        return node;
    }

    _if_statement(prefix: Node[]): Node {
        var node = Node(NodeKind.If);
        for (var item in prefix) {
            node.add(item);
        }
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
            # `else [Unlikely] if`.
            var list = _attributes();
            if (_failed) {
                return node;
            }
            if (_at_word("if") or list.count > 0) {
                node.add(_if_statement(list));
            } else {
                node.add(_block(Array<Node>()));
            }
        }
        return node;
    }

    _for_statement(): Node {
        var node = Node(NodeKind.For);
        _take(node);
        bool parenthesized = _at("(");
        if (parenthesized) {
            _take(node);
        }
        if (_at_word("var") and _peek_at(1).is(_source, "(")) {
            # `for (var (k, v) in pairs)`: a pattern.
            var pattern = Node(NodeKind.Destructure);
            _take(pattern);
            pattern.add(_binding_pattern());
            node.add(pattern);
        } else {
            var binding = _variable_declaration(Array<Node>());
            node.add(binding);
            if (!_failed) {
                _bind_qualifier(binding);
            }
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

    _static_block(prefix: Node[]): Node {
        var node = Node(NodeKind.Static);
        for (var item in prefix) {
            node.add(item);
        }
        _take(node);
        if (_at("(")) {
            node.add(_arguments());
            if (_failed) {
                return node;
            }
        }
        # The names the block binds qualify types only inside it.
        var outer = HashSet<String>();
        for (var name in _qualifiers) {
            outer.insert(name);
        }
        _static_depth += 1;
        node.add(_block(Array<Node>()));
        _static_depth -= 1;
        _qualifiers = outer;
        return node;
    }

    # Inside a `static` block, makes the name `variable` binds a qualifier.
    _bind_qualifier(variable: Node) {
        if (_static_depth > 0 and variable.count > 1 and variable.child(1).kind == NodeKind.Token) {
            _qualifiers.insert(variable.child(1).leaf.text(_source));
        }
    }

    _with_statement(): Node {
        var node = Node(NodeKind.With);
        _take(node);
        bool parenthesized = _at("(");
        if (parenthesized) {
            _take(node);
        }
        ulong position = _position;
        bool is_var = _at_word("var") or _at_word("const");
        var binding = _variable_declaration(Array<Node>());
        if (!_failed and _has_value(binding) and !binding.child(0).is_token(_source, "const")) {
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
        var node = Node(NodeKind.Match);
        _take(node);
        node.add(_expression());
        if (_failed) {
            return node;
        }
        var arms = Node(NodeKind.MatchArms);
        node.add(arms);
        _expect(arms, "{");
        while (!_failed) {
            if (_at("}") or _at_end()) {
                break;
            }
            var arm = Node(NodeKind.MatchArm);
            arms.add(arm);
            # `[Likely]` or `[Unlikely]` above the arm.
            for (var attribute in _attributes()) {
                arm.add(attribute);
            }
            if (_failed) {
                return node;
            }
            if (_at_word("else")) {
                _take(arm);
            } else {
                arm.add(_pattern());
                while (!_failed and _at(",")) {
                    _take(arm);
                    arm.add(_pattern());
                }
                # A guard: `if condition`.
                if (!_failed and _at_word("if")) {
                    _take(arm);
                    arm.add(_expression());
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
        var node = Node(NodeKind.Match);
        _take(node);
        node.add(_expression());
        if (_failed) {
            return node;
        }
        var arms = Node(NodeKind.MatchArms);
        node.add(arms);
        _expect(arms, "{");
        while (!_failed) {
            if (_at("}") or _at_end()) {
                break;
            }
            var arm = Node(NodeKind.MatchArm);
            arms.add(arm);
            if (_at_word("else")) {
                _take(arm);
            } else {
                arm.add(_pattern());
                while (!_failed and _at(",")) {
                    _take(arm);
                    arm.add(_pattern());
                }
                # A guard: `if condition`.
                if (!_failed and _at_word("if")) {
                    _take(arm);
                    arm.add(_expression());
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
    # `Case(x, _)`, whose values are patterns too (`Value(Text(t))`); a
    # literal: a number (`-1` too), string, character, `true` or `false`,
    # or a range of them (`1..9`); or a tuple pattern of two or more,
    # `(Case, x, 0)`.
    _pattern(): Node {
        var node = Node(NodeKind.Pattern);
        if (_at("(")) {
            _take(node);
            int elements = 0;
            while (true) {
                node.add(_pattern());
                if (_failed) {
                    return node;
                }
                elements += 1;
                if (_at(",")) {
                    _take(node);
                    continue;
                }
                break;
            }
            if (elements < 2) {
                _fail("expected ','");
                return node;
            }
            _expect(node, ")");
            return node;
        }
        var token = _peek();
        if (token.is_word(_source, "true")
            or token.is_word(_source, "false")
            or token.kind == TokenKind.Number
            or token.kind == TokenKind.String
            or token.kind == TokenKind.Character
            or (token.is(_source, "-") and _peek_at(1).kind == TokenKind.Number and _adjacent(1))) {
            node.add(_primary());
            _pattern_range(node);
            return node;
        }
        _expect_name(node, "a case name");
        while (!_failed and _at(".") and _adjacent(0) and _peek_at(1).kind == TokenKind.Identifier and _adjacent(1)) {
            _take(node);
            _take(node);
        }
        if (_failed) {
            return node;
        }
        if (_at("..") or _at("..>")) {
            _pattern_range(node);
            return node;
        }
        # A type pattern's type arguments, over a trait value: `Box<int>(b)`.
        if (_at("<") and _adjacent(0)) {
            node.add(_type_arguments());
            if (_failed) {
                return node;
            }
        }
        if (!_at("(")) {
            return node;
        }
        _take(node);
        while (!_failed) {
            if (_at(")")) {
                break;
            }
            node.add(_pattern());
            if (_at(",")) {
                _take(node);
                continue;
            }
            break;
        }
        _expect(node, ")");
        return node;
    }

    # The end of a range pattern, `..end` or `..>end`, when one follows.
    _pattern_range(node: Node) {
        if (_failed or !(_at("..") or _at("..>"))) {
            return;
        }
        _take(node);
        node.add(_unary());
    }

    # Whether a variable node has an `= value`.
    _has_value(variable: Node): bool {
        for (var child in variable.children) {
            if (child.is_token(_source, "=")) {
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
        var node = Node(NodeKind.Destructure);
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
        var bindings = Node(NodeKind.ClosureParameters);
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
                var binding = Node(NodeKind.ClosureParameter);
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
        var node = Node(NodeKind.Variable);
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
        var node = Node(NodeKind.GenericParameters);
        _take(node);
        while (true) {
            if (_at(">")) {
                _take(node);
                return node;
            }
            var parameter = Node(NodeKind.GenericParameter);
            _expect_name(parameter, "generic parameter name");
            if (_failed) {
                return node;
            }
            # Constraints: `T: Shape & Named`.
            if (_at(":")) {
                _take(parameter);
                parameter.add(_type_name());
                while (!_failed and _at("&")) {
                    _take(parameter);
                    parameter.add(_type_name());
                }
                if (_failed) {
                    return node;
                }
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
        var node = Node(NodeKind.Parameters);
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
            var failed = Node(NodeKind.Parameter);
            for (var attribute in attributes) {
                failed.add(attribute);
            }
            return failed;
        }
        var node = _parameter_body(attributes);
        return node;
    }

    _parameter_body(attributes: Node[]): Node {
        var node = Node(NodeKind.Parameter);
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
            variable.kind = NodeKind.Parameter;
            return variable;
        }
        # `name: Type`
        ulong position = _position;
        if (_at_name() and _peek_at(1).is(_source, ":")) {
            _take(node);
            _take(node);
            node.add(_type_name());
            if (!_failed) {
                _parameter_default(node);
                return node;
            }
            _restore(position);
            node = Node(NodeKind.Parameter);
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
        var node = Node(NodeKind.Parameters);
        _expect(node, "(");
        if (_failed) {
            return node;
        }
        while (true) {
            if (_at(")")) {
                _take(node);
                return node;
            }
            var parameter = Node(NodeKind.Parameter);
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
        var node = Node(NodeKind.ExternFunction);
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

    # The body of a function: a block, or `;` where `bodyless` allows one (a
    # trait's requirement) or after a parameter list (a compiler built-in's
    # `[__BuiltIn]` declaration; the compiler rejects it anywhere else).
    _function_body(node: Node, bodyless: bool) {
        bool parameters = false;
        for (var child in node.children) {
            if (child.kind == NodeKind.Parameters) {
                parameters = true;
            }
        }
        if ((bodyless or parameters) and _at(";")) {
            _take(node);
            return;
        }
        node.add(_block(Array<Node>()));
    }

    # A top-level function: `name[<T>](params)[: Type] { }` or
    # `Type name(params)[: Type] { }`.
    _function(prefix: Node[]): Node {
        var node = Node(NodeKind.Function);
        for (var item in prefix) {
            node.add(item);
        }
        if (!_at_name()) {
            _fail("expected declaration");
            return node;
        }
        var first = Node(NodeKind.Type);
        var name = _advance();
        first.add_token(name);
        _qualified_tail(first, name);
        bool qualified = first.count > 1;
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
        while (_at("[") and _peek_at(1).is(_source, "]")) {
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
        var node = Node(NodeKind.Function);
        for (var item in prefix) {
            node.add(item);
        }
        if (_at_word("static")) {
            _take(node);
        }
        ulong position = _position;
        ulong children = node.count;

        # Pepper-style indexer or operator method: `[](params)[: Type] { }`,
        # `==(params)[: Type] { }`.
        bool pepper_style = false;
        if (_at("[") and _peek_at(1).is(_source, "]")) {
            _take(node);
            _take(node);
            pepper_style = true;
        } else {
            var leading = _operator_size();
            if (_at_operator_name(leading)) {
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
        var index_type = Node(NodeKind.Type);
        _type_base(index_type);
        if (!_failed) {
            if (_at("[") and _peek_at(1).is(_source, "]") and _peek_at(2).is(_source, "(")) {
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
        var return_type = Node(NodeKind.Type);
        _type_base(return_type);
        if (_failed) {
            return node;
        }
        node.add(return_type);
        var op = _operator_size();
        if (_at_name()) {
            _take(node);
        } else if (_at_operator_name(op)) {
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

    # `{ member... }` of a struct (`kind` NodeKind.Struct), trait or extension.
    _members(kind: NodeKind): Node {
        var node = Node(NodeKind.Members);
        _expect(node, "{");
        if (_failed) {
            return node;
        }
        while (true) {
            if (_at("}") or _at_end()) {
                break;
            }
            if (_at(";")) {
                var empty = Node(NodeKind.Empty);
                _take(empty);
                node.add(empty);
                continue;
            }
            var attributes = _attributes();
            if (_failed) {
                return node;
            }
            if (kind != NodeKind.Struct and _at_word("var")) {
                var variable = _variable_declaration(attributes);
                if (_failed) {
                    return node;
                }
                if (!_at("{")) {
                    _fail("expected '{'");
                    return node;
                }
                node.add(_property(variable));
                if (_failed) {
                    return node;
                }
                continue;
            }
            if (kind != NodeKind.Struct) {
                node.add(_method(attributes, kind == NodeKind.Trait));
                if (_failed) {
                    return node;
                }
                continue;
            }
            if (_at_word("construct") or _at_word("new")) {
                var constructor = Node(NodeKind.Constructor);
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
                var destructor = Node(NodeKind.Destructor);
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
            if (_at_word("extern") and !_peek_at(1).is(_source, "(")) {
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
            if (_at("{")) {
                node.add(_property(field));
                if (_failed) {
                    return node;
                }
                continue;
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

    # The rest of a property after `var name: Type` (parsed as `variable`):
    # its accessors, then `[= value ;]`.
    _property(variable: Node): Node {
        var node = Node(NodeKind.Property);
        for (var child in variable.children) {
            node.add(child);
        }
        var accessors = Node(NodeKind.Accessors);
        node.add(accessors);
        _take(accessors);
        while (!_at("}")) {
            if (_at_end() or !(_at_word("get") or _at_word("set"))) {
                _fail("expected 'get' or 'set'");
                return node;
            }
            var accessor = Node(NodeKind.Accessor);
            _take(accessor);
            if (_at(";")) {
                _take(accessor);
            } else {
                accessor.add(_block(Array<Node>()));
                if (_failed) {
                    return node;
                }
            }
            accessors.add(accessor);
        }
        _take(accessors);
        if (_at("=")) {
            _take(node);
            node.add(_expression());
            if (_failed) {
                return node;
            }
            _finish_statement(node);
        }
        return node;
    }

    # A named declaration with generic parameters and members: a struct or
    # trait.
    _aggregate(prefix: Node[], kind: NodeKind): Node {
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

    # `enum Name [: Type] { cases, methods and properties }`. A case list
    # ends at a case without a `,`, or at a name that starts a method or a
    # property, as in the compiler's `enum_declaration`.
    _enum(prefix: Node[]): Node {
        var node = Node(NodeKind.Enum);
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
        var members = Node(NodeKind.Members);
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
            ulong children = members.count;
            var item = Node(NodeKind.EnumCase);
            for (var attribute in _attributes()) {
                item.add(attribute);
            }
            if (_failed) {
                return node;
            }
            if (!_at_name() or _at_word("static") or _at_word("var")) {
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
                var empty = Node(NodeKind.Empty);
                _take(empty);
                members.add(empty);
                continue;
            }
            var attributes = _attributes();
            if (_failed) {
                return node;
            }
            if (_at_word("var")) {
                var variable = _variable_declaration(attributes);
                if (_failed) {
                    return node;
                }
                members.add(_property(variable));
            } else {
                members.add(_method(attributes, false));
            }
            if (_failed) {
                return node;
            }
        }
        _expect(members, "}");
        return node;
    }

    _extension(prefix: Node[]): Node {
        var node = Node(NodeKind.Extend);
        for (var item in prefix) {
            node.add(item);
        }
        _take(node);
        _restating = true;
        node.add(_type_name());
        _restating = false;
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
            # `extend X with Trait;` has no body.
            if (_at(";")) {
                _take(node);
                return node;
            }
        }
        node.add(_members(NodeKind.Extend));
        return node;
    }

    _type_alias(prefix: Node[]): Node {
        var node = Node(NodeKind.TypeAlias);
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
            return Node(NodeKind.Function);
        }
        bool exported = false;
        bool file_private = false;
        while (_at_word("export") or _at_word("private")) {
            bool is_export = _at_word("export");
            if ((is_export and exported) or (!is_export and file_private)) {
                _fail(is_export ? "duplicate 'export' modifier" : "duplicate 'private' modifier");
                return Node(NodeKind.Function);
            }
            if (exported or file_private) {
                _fail("a declaration cannot be both 'export' and 'private'");
                return Node(NodeKind.Function);
            }
            exported = is_export;
            file_private = !is_export;
            prefix.append(Node.of_token(_advance()));
            if (_at("[")) {
                _fail(is_export ? "'export' goes after the attributes" : "'private' goes after the attributes");
                return Node(NodeKind.Function);
            }
        }
        if (_at_word("struct")) {
            return _aggregate(prefix, NodeKind.Struct);
        }
        if (_at_word("trait")) {
            return _aggregate(prefix, NodeKind.Trait);
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
        if (_at_word("static") and (_peek_at(1).is(_source, "(") or _peek_at(1).is(_source, "{"))) {
            return _static_block(prefix);
        }
        if (_at_word("extern") and !_peek_at(1).is(_source, "(")) {
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
        var node = Node(NodeKind.Import);
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
            var symbols = Node(NodeKind.ImportList);
            _take(symbols);
            while (true) {
                if (_at("]") and symbols.count == 1) {
                    break;
                }
                var symbol = Node(NodeKind.ImportSymbol);
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
        if (name.kind == TokenKind.String) {
            _take(node);
        } else {
            _expect_name(node, "module name");
            if (_failed) {
                return node;
            }
            # `import http.client`: a module inside a package, which binds
            # its last name.
            while (_at(".")) {
                _take(node);
                name = _peek();
                _expect_name(node, "module name");
                if (_failed) {
                    return node;
                }
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
            _qualifiers.insert(alias.text(_source));
        } else {
            _restore(position);
            if (!list and !reexport and name.kind != TokenKind.String) {
                _qualifiers.insert(name.text(_source));
            }
        }
        return node;
    }

    # Whether `export` is followed by `*` or `[`: an `export ... from`.
    _at_export_from(): bool {
        return _at_word("export") and (_peek_at(1).is(_source, "*") or _peek_at(1).is(_source, "["));
    }

    # `export name[.name] [as alias];`, a re-export. Fails (so the caller
    # reads a declaration instead) unless an `as` or `;` follows the name.
    _export_alias(prefix: Node[]): Node {
        var node = Node(NodeKind.ExportAlias);
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
        _qualified_tail(node, name);
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
        var node = Node(NodeKind.Module);
        while (true) {
            if (_at_end()) {
                break;
            }
            if (_at(";")) {
                var empty = Node(NodeKind.Empty);
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
            if (declaration.kind == NodeKind.Variable or declaration.kind == NodeKind.TypeAlias) {
                _finish_statement(declaration);
            }
            node.add(declaration);
        }
        node.add_token(_advance());
        return node;
    }
}

## Parses Pepper source text into a syntax tree whose root is a
## `NodeKind.Module`.
##
## @param source the text of a Pepper source file
## @returns the tree, or the syntax error furthest into the source
export parse(source: String): Result<Node, SyntaxError> {
    var tokens = lex(source);
    if (tokens.is_err()) {
        return Result<Node, SyntaxError>.err(tokens.error());
    }
    var parser = Parser(source, tokens.value());
    var root = parser.module();
    if (parser._failed) {
        return Result<Node, SyntaxError>.err(parser._error.value());
    }
    return Result<Node, SyntaxError>.ok(root);
}

## Parses `source` as a single expression, the whole of it: the text in the
## braces of an interpolated string, for instance.
##
## @param source the text of one Pepper expression
## @param qualifiers the names that qualify a type where the expression
##   appears (`geo` in `geo.Box<int>()`): imports, and in a `static` block
##   the names its `for`s and `var`s bind
## @returns the expression's tree, or the syntax error furthest into the
##   source, including text left over after the expression
export parse_expression(source: String, qualifiers: String[] = Array<String>()): Result<Node, SyntaxError> {
    var tokens = lex(source);
    if (tokens.is_err()) {
        return Result<Node, SyntaxError>.err(tokens.error());
    }
    var parser = Parser(source, tokens.value());
    for (var name in qualifiers) {
        parser._qualifiers.insert(name);
    }
    var root = parser._expression();
    if (!parser._failed and !parser._at_end()) {
        parser._fail("unexpected '" + parser._peek().text(source) + "'");
    }
    if (parser._failed) {
        return Result<Node, SyntaxError>.err(parser._error.value());
    }
    return Result<Node, SyntaxError>.ok(root);
}
