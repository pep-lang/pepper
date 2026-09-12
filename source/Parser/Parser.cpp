
#include "Parser/Parser.h"

#include "llvm/Support/TypeName.h"

namespace pepper { namespace parser {
    class ParserImpl : public Parser {
      public:
        ParserImpl(const ParseState& state)
            : Parser(state)
            , cur(this)
            , trace(this) {
            trace.traceln(fmt::format("Parsing {}:", source_file));
            while (!eof() && cur->in(Lexeme::Whitespace, Lexeme::Newline)) {
                advance();
            }
        }

        class TokenCursor {
            const Token* token = nullptr;
            ParserImpl* parent;

          public:
            TokenCursor(ParserImpl* p)
                : parent(p) {}

            const Token* operator->() const {
                return parent->peek(0);
            }

            const Token& operator*() const {
                return *parent->peek(0);
            }

            operator bool() const {
                return parent->peek(0) != nullptr;
            }

            operator std::add_const_t<Token>*() const {
                return parent->peek(0);
            }

            auto operator==(const Lexeme& lex) const {
                auto peek = parent->peek(0);
                return *peek == lex;
            }

            auto operator==(std::string_view sv) const {
                return std::string_view{*parent->peek(0)} == sv;
            }

            void update() {
                token = this->operator->();
            }
        } cur;

        uint32_t token_idx = 0; // current token in the stream
        Vector<DeclarationNode*> declaration_stack = {nullptr};
        std::unique_ptr<ModuleNode> parse_tree = std::make_unique<ModuleNode>();

        class TokenMark {
            ParserImpl* parent = nullptr;
            uint32_t idx = 0;

          public:
            TokenMark(ParserImpl* p = nullptr, uint32_t i = -1)
                : parent(p)
                , idx(i) {}

            TokenMark(const TokenMark&) = delete;
            TokenMark(TokenMark&&) = default;
            TokenMark& operator=(const TokenMark&) = delete;

            void backtrack() const {
                if (parent) {
                    parent->backtrack(idx);
                }
            }
        };

        struct ParserScope : debug::TraceScope {
            size_t start = 0;
            bool success = false;
            bool rejected = false;

            ParserScope(debug::BasicTracer* t, std::string_view name)
                : TraceScope(t, name) {
                start = tracer<Tracer>()->parser->token_idx;
            }

            ParserScope(ParserScope&&) noexcept = default;

            ~ParserScope() override {
                if (this->tracer()) {
                    if (!success && !rejected) {
                        reject();
                    }
                }
            }

            void backtrack(TokenMark& marker) const {
                tracer<Tracer>()->backtrack(marker);
            }

            template <typename Node>
            Node&& result(Node&& node) {
                if (is_inline) {
                    return std::forward<Node>(node);
                }

                auto* t = tracer<Tracer>();
                t->trace("->");
                t->trace(node, ":");

                // print out the component tokens that went into the node
                const auto pos = t->parser->token_idx;
                if (t->continue_line) {
                    const auto& tokens = t->parser->tokens;
                    const auto end = std::size(tokens);
                    auto idx = start;
                    // skip leading whitespace
                    while (idx < end && tokens[idx].in(Lexeme::Whitespace, Lexeme::Newline)) {
                        ++idx;
                    }
                    std::string buf;
                    for (; idx < pos; ++idx) {
                        const auto& token = tokens[idx];
                        // clip off large blocks of tokens, just use the first line
                        if (token.in(Lexeme::Newline)) {
                            buf += "...";
                            break;
                        }
                        buf += token.to_string();
                        // no language element spans across a ';'
                        if (token.in(Lexeme::Semicolon)) {
                            break;
                        }
                    }
                    if (start < tokens.size() - 1) {
                        buf += fmt::format(" @ {}({}, {})",
                                           t->parser->source_file,
                                           tokens[start].location().line,
                                           tokens[start].location().column);
                        t->trace(buf);
                    } else {
                        t->trace("None");
                    }
                }
                success = true;
                t->parser->clear_error_context();
                return std::forward<Node>(node);
            }

            std::nullptr_t reject(TokenMark&& marker = {}, const std::string& context = {}) {
                if (Tracer* t = tracer<Tracer>()) {
                    if (!is_inline) {
                        t->traceln("-> rejected");
                        backtrack(marker);
                    }

                    if (!context.empty()) {
                        t->parser->record_error_context(context);
                    }

                    rejected = true;
                }

                return nullptr;
            }
        };

        struct Tracer : debug::Tracer<ParserScope> {
            ParserImpl* parser;

            Tracer(ParserImpl* p)
                : parser(p) {}

            template <typename Node>
            void trace(const std::unique_ptr<Node>& node, const std::string& msg = {}) {
                const auto name = strip_symbol(llvm::getTypeName<Node>());
                trace(fmt::format("{}{}", node ? name : "null", msg));
            }

            template <typename Node, ConstString OpName>
            void trace(const std::unique_ptr<BinaryExpressionNode<Node, OpName>>& node, const std::string& msg = {}) {
                std::string_view name{OpName};
                trace(fmt::format("BinaryExpressionNode<{}>{}", node ? name : "null", msg));
            }

            using debug::Tracer<ParserScope>::trace;

            void backtrack(TokenMark& marker) {
                const auto end = parser->token_idx;
                marker.backtrack();
                const auto start = parser->token_idx;
                if (end - start > 0) {
                    std::string buf;
                    for (uint32_t idx = start; idx < end; ++idx) {
                        buf += parser->tokens[idx].to_string();
                    }
                    traceln(fmt::format("backtracked: {}", buf));
                }
            }
        } trace;

        ModuleNode* tree() const override {
            return parse_tree.get();
        }

        bool parse() override {
            parse_tree = parse_module();
            return parse_tree && eof();
        }

      private:
        void record_error_context(const std::string& msg, SourcePosition loc = {}) {
            if (loc == SourcePosition{}) {
                loc = cur->location();
            }
            errors.emplace_back(loc, msg);
        }

        void clear_error_context() {
            errors.clear();
        }

        size_t find_line_start(size_t line_idx) const {
            for (size_t idx = 0; idx < std::size(tokens); ++idx) {
                if (tokens[idx].location().line == line_idx) {
                    return idx;
                }
            }
            assert("find_line_start: found no tokens on line");
            return -1;
        }

        void print_error_and_source(SourcePosition loc, const std::string& msg) {
            llvm::errs() << "\n" << fmt::format("{}({}): {}\n", source_file, loc.line, msg);
            // Find the start of the line the error occurred on
            const size_t start = find_line_start(loc.line);
            size_t idx = start;
            while (tokens[idx] != Lexeme::Newline) {
                llvm::errs() << tokens[idx].to_string();
                ++idx;
            }
            llvm::errs() << "\n";
            llvm::errs() << std::string_view{indent(loc.column - 1)} << '^' << "\n";
        }

        void report_error(const char* msg, SourcePosition loc = {}) {
            if (loc == SourcePosition{}) {
                loc = cur->location();
            }
            llvm::errs() << "\n";

            // report any gathered error context
            for (const auto& [where, what] : errors) {
                print_error_and_source(where, what);
            }
            clear_error_context();

            print_error_and_source(loc, msg);
            llvm::errs().flush();
            // Messages::report<Error>(fmt::format("{}:{}: {}", source_file, loc.line, msg));
        }

        void report_error(const std::string& msg, SourcePosition loc = {}) {
            report_error(msg.c_str(), loc);
        }

        void report_error(const int offset, const std::string& msg) {
            const auto loc = peek(offset)->location();
            report_error(msg, loc);
        }

        const Token& current() const {
            return tokens[token_idx];
        }

        const Token* peek(int offset) const {
            auto idx = token_idx + offset;
            if (idx >= 0 && idx < std::size(tokens)) {
                return &tokens[idx];
            }
            return nullptr;
        }

        ssize_t lookahead(const Vector<Lexeme>& needles, const Lexeme& end) const {
            auto offset = 0;
            while (peek(offset) && peek(offset)->in(needles)) {
                ++offset;
            }
            return (peek(offset) && peek(offset)->type() == end) ? offset : -1;
        }

        void consume_whitespace() {
            while (!eof() && cur->in(Lexeme::Whitespace, Lexeme::Newline)) {
                advance();
            }
        }

        void advance(size_t count = 1, bool skip_newline = false) {
            const auto token_count = std::size(tokens);
            const auto token_start = token_idx;
            token_idx = std::min(token_idx + count, token_count);
            while (token_idx < token_count && (cur == Lexeme::Whitespace || (skip_newline && cur == Lexeme::Newline))) {
                token_idx = std::min<uint32_t>(token_idx + 1, token_count);
            }
            std::string buf = "consumed: ";
            for (auto idx = token_start; idx < token_idx; ++idx) {
                const auto& token = tokens[idx];
                std::string str;
                switch (token.type()) {
                    case Lexeme::Whitespace:
                        str = "∙";
                        break;
                    case Lexeme::Newline:
                        str = "\\n";
                        break;
                    default:
                        str = token.to_string();
                        break;
                }
                buf += fmt::format("{}{}", str, idx < (token_idx - 1) ? " " : "");
            }
            trace.traceln(buf);
            cur.update();
        }

        const Token* consume() {
            const auto* token = &current();
            advance(1, true);
            return token;
        }

        TokenMark mark() {
            return TokenMark(this, token_idx);
        }

        void backtrack(const uint32_t idx) {
            token_idx = idx;
            cur.update();
        }

        bool eof() const {
            return token_idx == std::size(tokens);
        }

        // id
        // literal
        // ( expressions? )
        std::unique_ptr<PrimaryExpressionNode> parse_primary_expression() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto expr = std::make_unique<PrimaryExpressionNode>();

            bool expect_call = false;
            if (auto id = parse_id()) {
                expr->expr = std::move(id);
                return scope.result(std::move(expr));
            }

            if (auto literal = parse_literal()) {
                expr->expr = std::move(literal);
                return scope.result(std::move(expr));
            }

            if (cur == Lexeme::LParen) {
                auto open = consume();
                auto close = Lexeme::bracket_pair(open->type());
                auto exprs = parse_expressions(open);
                if (!exprs) {
                    report_error("Expected one or more expressions or ')' after '('");
                    advance();
                    return {};
                }
                if (cur != close) {
                    report_error(fmt::format("Expected a '{}' to close function call arguments", close.to_string()));
                    advance();
                    return {};
                }
                exprs->close = consume();

                expr->expr = std::move(exprs);
                return scope.result(std::move(expr));
            }

            return {};
        }

        // literal
        std::unique_ptr<LiteralNode> parse_literal() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            if (!Lexeme::is_literal(cur->type())) {
                return {};
            }
            auto literal = std::make_unique<LiteralNode>();
            literal->literal = consume();

            return scope.result(std::move(literal));
        }

        // identifier
        std::unique_ptr<IdentifierNode> parse_identifier() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            if (cur != Lexeme::Identifier) {
                return {};
            }

            auto ident = std::make_unique<IdentifierNode>();
            ident->identifier = consume();

            return scope.result(std::move(ident));
        }

        // expression, ...
        // NOTE: does not require nor parse surrounding parens
        std::unique_ptr<ExpressionsNode> parse_expressions(const Token* open, bool in_initializer = false) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto exprs = std::make_unique<ExpressionsNode>();
            exprs->open = open;
            exprs->in_initializer = in_initializer;

            auto expr = parse_expression();
            if (!expr) {
                // empty expression list
                return scope.result(std::move(exprs));
            }

            exprs->expressions.emplace_back(std::move(expr));

            while (cur == Lexeme::Comma) {
                advance(); // past comma
                expr = parse_expression();
                if (!expr) {
                    report_error("Invalid tokens in expression");
                    return {};
                }
                exprs->expressions.emplace_back(std::move(expr));
            }

            return scope.result(std::move(exprs));
        }

        // primary_expression postfix_operator
        std::unique_ptr<PostfixExpressionNode> parse_postfix_expression() {
            auto scope = trace.scope(debug::FunctionTag{__FUNCTION__});
            auto expr = std::make_unique<PostfixExpressionNode>();
            expr->expr = parse_primary_expression();
            if (!expr->expr) {
                return {};
            }

            auto is_postfix_expr = [&] {
                const auto loc = cur->location();
                const auto prior = peek(-1);
                bool is_postfix = Lexeme::is_postfix_operator(cur->type()) || cur == Lexeme::Question;
                bool is_adjacent =
                    loc.line == prior->location().line && loc.column == prior->location().column + prior->length();
                return (is_postfix && is_adjacent) || cur->type().in({Lexeme::LBracket, Lexeme::LParen, Lexeme::Dot});
            };

            // Postfix operators can chain, e.g. arr[x].get_foos()[x].bar()
            while (!eof() && is_postfix_expr()) {
                auto operand_mark = mark();
                auto operand = PostfixExpressionNode::operand{cur};
                if (cur == Lexeme::LBracket) {
                    advance(); // past '['
                    operand.exprs = parse_expressions(cur);
                    if (!operand.exprs) {
                        report_error("[ must be followed by an expression");
                        return {};
                    }
                    if (cur != Lexeme::RBracket) {
                        report_error(std::string("unexpected token: ") + cur->to_string() + ", expected ']'");
                        return {};
                    }
                    operand.close = operand.exprs->close = consume();
                } else if (cur == Lexeme::LParen) {
                    // if there is a list of expressions, this is a function call,
                    // otherwise backtrack and let something else take a run at the '('
                    advance(); // past '('
                    operand.exprs = parse_expressions(cur);
                    if (!operand.exprs) {
                        scope.backtrack(operand_mark);
                        break;
                    }
                    if (cur != Lexeme::RParen) {
                        report_error("Expected ')' after expression(s)");
                        return {};
                    }
                    operand.close = operand.exprs->close = consume();
                } else if (cur == Lexeme::Dot) {
                    advance(); // skip '.'
                    operand.identifier_expr = parse_identifier();
                    if (!operand.identifier_expr) {
                        report_error("'.' must be followed by a member name");
                        return {};
                    }
                } else if (cur == Lexeme::Question) {
                    // ternary
                    advance(); // past '?'
                    auto then_expr = parse_expression();
                    if (!then_expr) {
                        report_error("Invalid expression");
                        return {};
                    }
                    if (cur != Lexeme::Colon) {
                        report_error("Expected ':' after expression");
                        return {};
                    }
                    advance(); // past ':'
                    auto else_expr = parse_expression();
                    if (!else_expr) {
                        report_error("Invalid expression");
                        return {};
                    }
                } else {
                    advance(); // past op
                }

                expr->ops.emplace_back(std::move(operand));
            }

            for (const auto& e : ExpressionNode::expressions) {
                e->subexpressions += std::size(expr->ops);
            }
            return scope.result(std::move(expr));
        }

        // prefix_operator postfix_expression
        std::unique_ptr<PrefixExpressionNode> parse_prefix_expression() {
            auto scope = trace.scope(debug::FunctionTag{__FUNCTION__});
            auto expr = std::make_unique<PrefixExpressionNode>();
            while (Lexeme::is_prefix_operator(cur->type())) {
                expr->ops.emplace_back(consume());
            }
            expr->expr = parse_postfix_expression();
            if (!expr->expr) {
                expr.reset();
            }
            return scope.result(std::move(expr));
        }

        // prefix_expression as id
        std::unique_ptr<CastExpressionNode> parse_cast_expression() {
            auto scope = trace.scope(debug::FunctionTag{__FUNCTION__});
            auto cast = std::make_unique<CastExpressionNode>();
            cast->expr = parse_prefix_expression();
            if (!cast->expr) {
                return {};
            }

            while (!eof() && (cur == "as")) {
                auto operand = CastExpressionNode::operand{};
                operand.op = consume();

                operand.type = parse_id();
                if (!operand.type) {
                    report_error("Expected type after 'as'");
                    return {};
                }

                cast->operands.emplace_back(std::move(operand));
            }

            return scope.result(std::move(cast));
        }

        template <typename BinaryNode, typename Predicate, typename ParseOperand>
        std::unique_ptr<BinaryNode> parse_binary_expression(Predicate op_matches, ParseOperand parse_operand) {
            auto scope = trace.top(); // scope(fmt::format("parse_binary_expression<{}>", BinaryNode::name()));
            auto expr = std::make_unique<BinaryNode>();
            if ((expr->expr = parse_operand())) {
                bool matched = false;
                while (!eof()) {
                    typename BinaryNode::operand operand{};

                    auto operand_mark = mark();

                    // 1 token -> bool
                    if constexpr (requires { bool{op_matches(*cur)}; }) {
                        if (!op_matches(*cur)) {
                            break;
                        }
                        matched = true;
                        trace.traceln(fmt::format("op: {}", cur->to_string()));
                        advance(); // past operator
                    }
                    // 2 tokens -> const token*
                    else if constexpr (requires { op_matches(*cur, *peek(1)); }) {
                        // if there's no next token or the predicate fails
                        if (!peek(1) || (operand.op = op_matches(*cur, *peek(1))) == nullptr) {
                            break;
                        }
                        matched = true;
                        trace.traceln(fmt::format("op: {}", operand.op->to_string()));
                        // if the next token wasn't consumed, consume 2 tokens (e.g. '>>=')
                        if (*operand.op != cur) {
                            advance();
                        }
                        advance();
                    } else {
                        assert(!"parse_binary_expression predicate has incorrect signature");
                    }

                    // attempt to parse the next operand. If it is not valid, then this is not
                    // a binary op, let the outer parsing function deal with it
                    if (!(expr->expr = parse_operand())) {
                        trace.backtrack(operand_mark);
                        return {};
                    }

                    expr->operands.emplace_back(std::move(operand));
                }
                return matched ? scope.result(std::move(expr)) : std::move(expr);
            }
            return {};
        }

        // cast_expression product_operator cast_expression
        auto parse_product_expression() {
            auto scope = trace.scope(__FUNCTION__);
            auto matches = [](const Token& t) {
                return t.type().in({Lexeme::Star, Lexeme::Star2, Lexeme::Slash, Lexeme::Percent});
            };
            return scope.result(
                parse_binary_expression<ProductExpressionNode>(matches, [this] { return parse_cast_expression(); }));
        }

        // product_expression sum_operator product_expression
        auto parse_sum_expression() {
            auto scope = trace.scope(__FUNCTION__);
            auto matches = [](const Token& t) {
                return t.type().in({Lexeme::Plus, Lexeme::Minus});
            };
            return scope.result(
                parse_binary_expression<SumExpressionNode>(matches, [this] { return parse_product_expression(); }));
        }

        // sum_expression shift_operator sum_expression
        // Includes fix-up for >> and >>= that cannot be known at lexer time
        auto parse_shift_expression(const bool allow_angle_brackets = true) {
            auto scope = trace.scope(__FUNCTION__);
            if (allow_angle_brackets) {
                auto matches = [this](const Token& t, const Token& u) -> const Token* {
                    if (t.type() == Lexeme::LeftShift) {
                        return &t;
                    }
                    const bool adjacent =
                        t.location().line == u.location().line && t.location().column == (u.location().column - 1);
                    // hand fix-up '>>' from ['>','>']
                    if (t.type() == Lexeme::Greater && u.type() == Lexeme::Greater && adjacent) {
                        tokens.emplace(tokens.begin() + token_idx, Lexeme::RightShift, ">>", t.location());
                        // erase the prior 2 tokens
                        tokens.erase(tokens.begin() + token_idx + 1);
                        tokens.erase(tokens.begin() + token_idx + 1);
                        return &current();
                    }
                    return {};
                };
                return scope.result(
                    parse_binary_expression<ShiftExpressionNode>(matches, [this] { return parse_sum_expression(); }));
            }
            return scope.result(parse_binary_expression<ShiftExpressionNode>(
                [](const Token&, const Token&) { return nullptr; }, [this] { return parse_sum_expression(); }));
        }

        // shift_expression compare_operator shift_expression
        auto parse_compare_expression(bool allow_angle_brackets = true) {
            auto scope = trace.scope(__FUNCTION__);
            return scope.result(parse_binary_expression<CompareExpressionNode>(
                [](const Token& t) { return t.type() == Lexeme::Spaceship; },
                [=, this] { return parse_shift_expression(allow_angle_brackets); }));
        }

        // compare_expression relation_operator compare_expression
        auto parse_relation_expression(bool allow_angle_brackets = true) {
            auto scope = trace.scope(__FUNCTION__);
            if (allow_angle_brackets) {
                auto matches = [](const Token& t, const Token& u) -> const Token* {
                    // <, <=, >=
                    if (t.type().in({Lexeme::Less, Lexeme::LessEq, Lexeme::GreaterEq})) {
                        return &t;
                    }
                    // >, but skip >>=
                    if (t.type() == Lexeme::Greater && u.type() != Lexeme::GreaterEq) {
                        return &t;
                    }
                    return nullptr;
                };
                return scope.result(parse_binary_expression<RelationExpressionNode>(
                    matches, [=, this] { return parse_compare_expression(allow_angle_brackets); }));
            }
            return scope.result(parse_binary_expression<RelationExpressionNode>(
                [](const Token&, const Token&) { return nullptr; },
                [=, this] { return parse_compare_expression(allow_angle_brackets); }));
        }

        // relation_expression equality_operator relation_expression
        auto parse_equality_expression(bool allow_angle_brackets, bool allow_equality = true) {
            auto scope = trace.scope(__FUNCTION__);
            if (allow_equality) {
                return scope.result(parse_binary_expression<EqualityExpressionNode>(
                    [](const Token& t) {
                        return t.type().in({Lexeme::Equal3, Lexeme::Equal2, Lexeme::NotEq, Lexeme::NotEq2});
                    },
                    [=, this] { return parse_relation_expression(allow_angle_brackets); }));
            }
            return scope.result(parse_binary_expression<EqualityExpressionNode>(
                [](const Token& t) { return t.type().in({Lexeme::NotEq, Lexeme::NotEq2}); },
                [=, this] { return parse_relation_expression(allow_angle_brackets); }));
        }

        // equality_expression & equality_expression
        auto parse_bit_and_expression(bool allow_angle_brackets = true, bool allow_equality = true) {
            auto scope = trace.scope(__FUNCTION__);
            return scope.result(parse_binary_expression<BitAndExpressionNode>(
                [](const Token& t) { return t.type() == Lexeme::Ampersand; },
                [=, this] { return parse_equality_expression(allow_angle_brackets, allow_equality); }));
        }

        // bit_and_expression ^ bit_and_expression
        auto parse_bit_xor_expression(bool allow_angle_brackets = true, bool allow_equality = true) {
            auto scope = trace.scope(__FUNCTION__);
            return scope.result(parse_binary_expression<BitXorExpressionNode>(
                [](const Token& t) { return t.type() == Lexeme::Caret; },
                [=, this] { return parse_bit_and_expression(allow_angle_brackets, allow_equality); }));
        }

        // bit_xor_expression | bit_xor_expression
        auto parse_bit_or_expression(bool allow_angle_brackets = true, bool allow_equality = true) {
            auto scope = trace.scope(__FUNCTION__);
            return scope.result(parse_binary_expression<BitOrExpressionNode>(
                [](const Token& t) { return t.type() == Lexeme::Pipe; },
                [=, this] { return parse_bit_xor_expression(allow_angle_brackets, allow_equality); }));
        }

        // bit_or_expression && bit_or_expression
        // bit_or_expression and bit_or_expression
        auto parse_logic_and_expression(bool allow_angle_brackets = true, bool allow_equality = true) {
            auto scope = trace.scope(__FUNCTION__);
            return scope.result(parse_binary_expression<LogicAndExpressionNode>(
                [](const Token& t) { return t.type() == Lexeme::Ampersand2; },
                [=, this] { return parse_bit_or_expression(allow_angle_brackets, allow_equality); }));
        }

        // logic_and_expression || logic_and_expression
        // logic_and_expression or logic_and_expression
        auto parse_logic_or_expression(bool allow_angle_brackets = true, bool allow_equality = true) {
            auto scope = trace.scope(__FUNCTION__);
            return scope.result(parse_binary_expression<LogicOrExpressionNode>(
                [](const Token& t) { return t.type() == Lexeme::Pipe2; },
                [=, this] { return parse_logic_and_expression(allow_angle_brackets, allow_equality); }));
        }

        // logic_or_expression assignment_operator logic_or_expression
        auto parse_assignment_expression(bool allow_angle_brackets = true) {
            auto scope = trace.scope(__FUNCTION__);
            std::unique_ptr<AssignmentExpressionNode> expr;
            if (allow_angle_brackets) {
                auto matches = [this](const Token& t, const Token& u) -> const Token* {
                    if (Lexeme::is_assignment_operator(t.type())) {
                        return &t;
                    }
                    const bool adjacent =
                        t.location().line == u.location().line && t.location().column == (u.location().column - 1);
                    if (t == Lexeme::Greater && u == Lexeme::GreaterEq && adjacent) {
                        tokens.emplace(tokens.begin() + token_idx, Lexeme::RightShiftEq, ">>=", t.location());
                        // erase the prior 2 tokens
                        tokens.erase(tokens.begin() + token_idx + 1);
                        tokens.erase(tokens.begin() + token_idx + 1);
                        return &current();
                    }
                    return nullptr;
                };
                expr = parse_binary_expression<AssignmentExpressionNode>(
                    matches, [=, this] { return parse_logic_or_expression(allow_angle_brackets); });
            } else {
                expr = parse_binary_expression<AssignmentExpressionNode>(
                    [](const Token&, const Token&) { return nullptr; },
                    [=, this] { return parse_logic_or_expression(allow_angle_brackets); });
            }

            return scope.result(std::move(expr));
        }

        // assignment_expression
        auto parse_expression(const bool allow_angle_brackets = true) -> std::unique_ptr<ExpressionNode> {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto expr = std::make_unique<ExpressionNode>();

            ExpressionNode::expressions.emplace_back(expr.get());
            auto pop = defer([] { ExpressionNode::expressions.pop_back(); });

            if (!(expr->expr = parse_assignment_expression(allow_angle_brackets))) {
                return {};
            }

            for (auto& e : ExpressionNode::expressions) {
                e->subexpressions++;
            }

            return scope.result(std::move(expr));
        }

        // identifier
        // identifier < id, ... >
        std::unique_ptr<IdNode> parse_id() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            if (cur != Lexeme::Identifier) {
                return {};
            }

            auto type = std::make_unique<IdNode>();
            type->identifier = parse_identifier();

            const bool expect_generic = (*peek(-1) != Lexeme::Whitespace);
            if (expect_generic && cur == Lexeme::Less) {
                type->open_generic = consume();
                while (cur != Lexeme::Greater) {
                    GenericArgument arg{};
                    arg.type = parse_id();
                    if (!arg.type) {
                        report_error("Expected typename");
                    }
                    type->generic_args.emplace_back(std::move(arg));
                    if (cur == Lexeme::Greater) {
                        break;
                    }
                    if (cur != Lexeme::Comma) {
                        report_error("Expected ','");
                    }
                    advance(); // past ','
                }
                type->close_generic = consume();
            }

            if (cur == Lexeme::Star) {
                type->qualifiers.push_back(consume());
            }

            return scope.result(std::move(type));
        }

        // expression ;
        std::unique_ptr<ExpressionStatementNode> parse_expression_statement(bool require_terminate) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto expr = std::make_unique<ExpressionStatementNode>();

            ExpressionStatementNode::expression_statements.emplace_back(expr.get());
            auto cleanup = defer([] { ExpressionStatementNode::expression_statements.pop_back(); });

            expr->expr = parse_expression(true);
            if (!expr->expr) {
                return {};
            }

            const bool terminated = eof() || cur->type().in({Lexeme::Semicolon, Lexeme::Newline});
            if (require_terminate && !terminated) {
                return {};
            }
            expr->terminates = terminated;
            advance(); // past terminator
            return scope.result(std::move(expr));
        }

        // if { block }
        // if { block } else { block }
        std::unique_ptr<BranchNode> parse_branch() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            if (cur != Lexeme::Keyword || *cur != "if") {
                return {};
            }
            auto branch = std::make_unique<BranchNode>();
            branch->keyword = consume();

            branch->condition = parse_logic_or_expression();
            if (!branch->condition) {
                report_error("Expected conditional expression after 'if'");
                return {};
            }

            if (cur != Lexeme::LBrace) {
                report_error("Expected '{' after 'if' condition");
                return {};
            }

            branch->then_block = parse_block();
            if (!branch->then_block) {
                report_error("Invalid 'if' branch block");
                return {};
            }
            if (cur == Lexeme::Keyword && *cur == "else") {
                branch->else_location = cur->location();
                advance();

                if (cur != Lexeme::LBrace && *cur != "if") {
                    report_error("Expected either 'if' or '{' after 'else'");
                    return {};
                }

                branch->else_block = parse_block();
                if (!branch->else_block) {
                    report_error("Invalid 'else' branch block");
                    return {};
                }
            }
            return scope.result(std::move(branch));
        }

        // return ;
        // return expression ;
        std::unique_ptr<ReturnStatementNode> parse_return_statement() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            if (cur != Lexeme::Keyword || *cur != "return") {
                return {};
            }

            auto ret = std::make_unique<ReturnStatementNode>();
            ret->keyword = consume();

            if (cur->type().in({Lexeme::Semicolon, Lexeme::Newline})) {
                return scope.result(std::move(ret));
            }

            auto expr = parse_expression();
            if (!expr) {
                report_error("Invalid expression after 'return'");
                return {};
            }

            if (!cur->type().in({Lexeme::Semicolon, Lexeme::Newline})) {
                report_error("Unexpected token after 'return' expression");
                advance();
                return {};
            }
            advance(); // past terminator
            return scope.result(std::move(ret));
        }

        // for parameter_declaration in expression { block }
        // while logic_or_expression { block }
        std::unique_ptr<LoopNode> parse_loop() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            if (cur != Lexeme::Keyword || !cur->in("while", "for")) {
                return {};
            }
            auto loop = std::make_unique<LoopNode>();
            loop->keyword = consume();

            if (*loop->keyword == "for") {
                loop->iterator = parse_parameter_declaration();
                if (!loop->iterator) {
                    report_error("Invalid iterator declaration after 'for'");
                    return {};
                }
                if (cur != Lexeme::Keyword || *cur != "in") {
                    report_error("Expected 'in' after iterator declaration");
                    return {};
                }
                advance();
                loop->next_expr = parse_expression();
                if (!loop->next_expr) {
                    report_error("Invalid range expression in 'for' loop");
                    return {};
                }
            } else if (*loop->keyword == "while") {
                loop->condition = parse_logic_or_expression();
                if (!loop->condition) {
                    report_error("Invalid condition after 'while'");
                    return {};
                }
            }

            if (cur != Lexeme::LBrace) {
                report_error(std::string("Expected '{' after ") + loop->keyword->to_string());
                return {};
            }

            loop->body = parse_block();
            if (!loop->body) {
                report_error("Invalid loop body");
                return {};
            }

            return scope.result(std::move(loop));
        }

        // break ;
        // continue ;
        std::unique_ptr<JumpStatementNode> parse_jump_statement() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            if (cur != Lexeme::Keyword || !cur->in("break", "continue")) {
                return {};
            }

            auto jump = std::make_unique<JumpStatementNode>();
            jump->keyword = consume();

            if (!cur->in(Lexeme::Semicolon, Lexeme::Semicolon)) {
                report_error("Unexpected token after " + jump->keyword->to_string());
                return {};
            }
            advance(); // past terminator

            return scope.result(std::move(jump));
        }

        // branch
        // return ;
        // jump ;
        // loop
        // block
        // declaration ;
        // expression_statement ;
        std::unique_ptr<StatementNode> parse_statement(bool require_terminate = true, BlockNode* outer = nullptr) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto statement = std::make_unique<StatementNode>(outer);
            bool terminated = false;

            if (auto b = parse_branch()) {
                statement->statement = std::move(b);
                terminated = true;
            } else if (auto r = parse_return_statement()) {
                statement->statement = std::move(r);
            } else if (auto j = parse_jump_statement()) {
                statement->statement = std::move(j);
            } else if (auto l = parse_loop()) {
                statement->statement = std::move(l);
                terminated = true;
            } else if (auto b = parse_block()) {
                statement->statement = std::move(b);
                terminated = true;
            } else if (auto d = parse_declaration(require_terminate)) {
                terminated = d->is_terminated;
                statement->statement = std::move(d);
            } else if (auto e = parse_expression_statement(require_terminate)) {
                statement->statement = std::move(e);
            }

            if (!terminated && require_terminate && !cur->in(Lexeme::Semicolon, Lexeme::Newline)) {
                report_error("No terminator found at the end of statement");
                return nullptr;
            }
            while (cur->in(Lexeme::Semicolon, Lexeme::Newline)) {
                advance(1, true);
            }

            return scope.result(std::move(statement));
        }

        enum class decl_context : uint8_t {
            None,
            Parameter, // function parameter
            Generic,   // generic parameter
            Return,    // return or multi-return
        };

        static std::string_view to_string(const decl_context ctx) {
            switch (ctx) {
                case decl_context::Parameter:
                    return "parameter";
                case decl_context::Generic:
                    return "generic";
                case decl_context::Return:
                    return "return";
                case decl_context::None:
                default:
                    return "None";
            }
        }

        // let identifier: id = expression ;
        // var identifier : id ;
        // var identifier = expression ;
        // struct identifier struct_type
        // identifier declarations
        // type_decl
        std::unique_ptr<DeclarationNode> parse_declaration(const bool require_terminate = true,
                                                           const decl_context ctx = decl_context::None,
                                                           StatementNode* statement = nullptr) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            if (eof()) {
                return {};
            }

            while (cur->in(Lexeme::Semicolon, Lexeme::Newline)) {
                advance();
            }

            auto marker = mark();
            auto decl = std::make_unique<DeclarationNode>(declaration_stack.back());

            if (ctx == decl_context::Parameter) {
                decl->is_function_parameter = true;
                // determine if this is a this param, e.g. 'this.x'
                if (cur == Lexeme::Identifier && cur == "this") {
                    decl->is_this_param = true;
                    advance(); // past 'this'
                    if (cur != Lexeme::Dot) {
                        report_error("Expected '.' after 'this'");
                        return {};
                    }
                    advance(); // past '.'
                }
                auto identifier = parse_identifier();
                if (!identifier) {
                    report_error("Expected identifier");
                    return {};
                }
                decl->identifier = std::move(identifier);
                // this params do not need a type, their type is taken from the member decl
                if (!decl->is_this_param) {
                    if (cur != Lexeme::Colon) {
                        // if there's no colon, it must be a function call, not a declaration
                        return scope.reject(std::move(marker), "Expected ':' <typename> for parameter");
                    }
                    advance(); // past ':'
                    auto type = parse_id();
                    if (!type) {
                        report_error("Invalid type for parameter");
                        return {};
                    }
                    decl->type_info = std::move(type);
                }

                if (cur == Lexeme::Star) {
                    decl->is_pointer = true;
                    advance(); // past '*'
                }

                if (cur == Lexeme::Equal) {
                    advance(); // past '='
                    decl->initializer = parse_expression(false);
                    if (!decl->initializer) {
                        report_error(fmt::format("Invalid initializer for {}", decl->identifier->to_string()));
                        return {};
                    }
                }
                return scope.result(std::move(decl));
            }

            if (cur->in("let", "var")) {
                decl->qualifiers.emplace_back(consume()); // eat the keyword
                decl->identifier = parse_identifier();
                if (!decl->identifier) {
                    report_error(fmt::format("Expected identifier after {}", cur->to_string()));
                    return {};
                }
                if (cur == Lexeme::Colon) {
                    advance(); // past ':'
                    auto type = parse_id();
                    if (!type) {
                        report_error(fmt::format("Invalid type name for {} {}",
                                                 decl->qualifiers.front()->to_string(),
                                                 decl->identifier->to_string()));
                        return {};
                    }
                    decl->type_info = std::move(type);
                }
                if (cur == Lexeme::Equal) {
                    advance(); // past '='
                    decl->initializer = parse_expression();
                    if (!decl->initializer) {
                        report_error("Invalid expression in declaration initializer");
                        return {};
                    }
                    decl->type_info = std::make_unique<IdNode>(IdNode::auto_type());
                    decl->type_decl = std::make_unique<TypeDeclNode>(TypeDeclNode::auto_type());
                }
                // see if the decl is terminated with ';' or '\n'
                decl->is_terminated = cur->in(Lexeme::Semicolon, Lexeme::Newline);
                if (decl->is_terminated) {
                    advance(1, true);
                } else {
                    if (require_terminate) {
                        report_error("Expected ';' or newline after declaration");
                        return {};
                    }
                }
                return scope.result(std::move(decl));
            } else if (auto s = parse_struct(decl.get())) {
                decl->type_info = std::move(s);
                return scope.result(std::move(decl));
            } else if (auto ext = parse_extension(decl.get())) {
                decl->type_info = std::move(ext);
                return scope.result(std::move(decl));
            } else if (auto f = parse_function(decl.get())) {
                decl->type_info = std::move(f);
                return scope.result(std::move(decl));
            }

            if (require_terminate) {
                return scope.reject(std::move(marker), "Invalid declaration");
            }

            decl->type_decl = parse_type_decl();
            if (!decl->type_decl) {
                report_error("Invalid declaration encountered");
                return {};
            }

            return scope.result(std::move(decl));
        }

        // identifier
        // identifier < parameter_declaration, ... >
        std::unique_ptr<TypeDeclNode> parse_type_decl() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto type = std::make_unique<TypeDeclNode>();
            type->identifier = parse_identifier();
            if (!type->identifier) {
                report_error("Expected identifier in type declaration");
                return {};
            }
            if (cur == Lexeme::Less) {
                advance(); // past '<'
                while (cur != Lexeme::Greater) {
                    GenericParameter param{};
                    param.param = parse_parameter_declaration();
                    if (!param.param) {
                        report_error("Expected typename");
                    }

                    type->generic_params.emplace_back(std::move(param));

                    if (cur == Lexeme::Comma) {
                        advance(); // past ','
                        continue;
                    }

                    if (cur != Lexeme::Greater) {
                        report_error("Expected '>'");
                        return {};
                    }
                }
                advance(); // past '>'
            }

            return scope.result(std::move(type));
        }

        // C-style extern function decl
        std::unique_ptr<FunctionTypeNode> parse_extern_function(DeclarationNode* decl) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto marker = mark();
            auto open = Lexeme::LParen;
            auto close = Lexeme::RParen;

            if (cur != "extern") {
                report_error("Expected extern function declaration");
                return {};
            }

            advance(); // past 'extern'

            auto return_type = parse_id();
            if (!return_type) {
                report_error("Expected extern function return type");
                return {};
            }

            if (cur == Lexeme::Star) {
                return_type->qualifiers.push_back(consume());
            }

            decl->type_info = std::move(return_type);

            decl->identifier = parse_identifier();
            if (!decl->identifier) {
                report_error("Expected extern function name");
                return {};
            }

            // extern functions are C, only have an identifier, no template params
            decl->type_decl = std::make_unique<TypeDeclNode>();
            decl->type_decl->identifier = std::make_unique<IdentifierNode>(*decl->identifier);

            if (cur != open) {
                report_error("Expected function signature");
                return {};
            }

            std::unique_ptr<FunctionTypeNode> func = std::make_unique<FunctionTypeNode>(decl);
            auto params = std::make_unique<ParameterDeclarationsNode>();
            params->open = consume();

            int param_idx = 1;
            bool trailing_comma = false;
            while (!eof() && cur != close) {
                trailing_comma = false;

                std::unique_ptr<DeclarationNode> param_decl = std::make_unique<DeclarationNode>(decl);
                auto type = parse_id();
                if (!type) {
                    report_error("Expected parameter type");
                    return {};
                }

                if (cur == Lexeme::Star) {
                    type->qualifiers.emplace_back(consume());
                }

                param_decl->type_info = std::move(type);
                param_decl->identifier = parse_identifier();
                param_decl->is_function_parameter = true;

                std::unique_ptr<ParameterDeclarationNode> parameter = std::make_unique<ParameterDeclarationNode>();
                parameter->declaration = std::move(param_decl);
                parameter->index = param_idx++;
                params->parameters.emplace_back(std::move(parameter));

                if (cur == close) {
                    break;
                }

                if (cur != Lexeme::Comma) {
                    report_error("Expected ',' or ')' after parameter declaration");
                    return {};
                }

                trailing_comma = true;
                advance();
            }

            if (trailing_comma) {
                report_error("Expected parameter declaration after ','");
                return {};
            }

            params->close = consume();

            func->parameters = std::move(params);

            return scope.result(std::move(func));
        }

        // extern type_decl function_type
        // type_decl function_type
        std::unique_ptr<FunctionTypeNode> parse_function(DeclarationNode* decl) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            // there are a few lookahead paths, if they fail backtracking will be necessary
            auto marker = mark();

            std::unique_ptr<FunctionTypeNode> func;
            decl->loc = cur->location();
            if (cur->type() == Lexeme::Keyword) {
                decl->is_extern = (cur == "extern");
                if (!decl->is_extern) {
                    report_error("Unexpected keyword '" + cur->to_string() + "' before declaration");
                    return {};
                }

                func = parse_extern_function(decl);
            }

            if (!func) {
                decl->type_decl = parse_type_decl();
                if (!decl->type_decl) {
                    return scope.reject(std::move(marker), "Expected function declaration");
                }

                decl->identifier = std::make_unique<IdentifierNode>(*decl->type_decl->identifier);

                if (cur != Lexeme::LParen) {
                    // this is not a function, backtrack
                    return scope.reject(std::move(marker), "Expected '(' in function declaration");
                }

                func = parse_function_type(decl);
                if (!func) {
                    return scope.reject(std::move(marker), "Invalid function declaration");
                }
            }

            // If the next non-whitespace token is '{', parse the function body
            if (ssize_t skip = lookahead({Lexeme::Whitespace, Lexeme::Newline}, Lexeme::LBrace); skip >= 0) {
                advance(skip);
                func->body = parse_block();
                if (!func->body) {
                    report_error("Invalid function body");
                    return {};
                }
            } else {
                // only extern decls don't have bodies
                if (!decl->is_extern) {
                    report_error("Only extern functions require forward declaration");
                    return {};
                }
                if (!cur->in(Lexeme::Semicolon, Lexeme::Newline)) {
                    report_error("Expected ; or newline after extern function declaration");
                    return {};
                }
                advance(1, true); // past ';' or '\n'
            }

            return scope.result(std::move(func));
        }

        // struct type_decl { declaration ; ... }
        std::unique_ptr<StructTypeNode> parse_struct(DeclarationNode* decl) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});

            if (cur != Lexeme::Keyword || cur != "struct") {
                return {};
            }
            advance(); // past struct

            auto s = std::make_unique<StructTypeNode>(decl);
            decl->type_decl = parse_type_decl();

            if (cur != Lexeme::LBrace) {
                report_error("Expected '{' after 'struct' declaration");
                return {};
            }

            advance(1, true); // past '{'

            while (cur != Lexeme::RBrace) {
                auto member = parse_declaration();
                if (!member) {
                    report_error("Invalid declaration in struct");
                    return {};
                }
                member->outer_declaration = decl;
                s->members.emplace_back(std::move(member));
            }

            advance(1, true); // past '}'

            return scope.result(std::move(s));
        };

        std::unique_ptr<ExtensionNode> parse_extension(DeclarationNode* decl) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});

            if (cur != Lexeme::Keyword || cur != "extend") {
                return {};
            }
            advance(1, true); // past 'extend'

            auto ext = std::make_unique<ExtensionNode>(decl);
            ext->target = parse_id();
            if (!ext->target) {
                report_error("Invalid target of extend");
                return {};
            }

            if (cur == "with") {
                advance(1, true); // past 'with'
                ext->trait = parse_id();
                if (!ext->trait) {
                    report_error("Invalid trait in extend statement");
                    return {};
                }
            }

            if (cur != Lexeme::LBrace) {
                report_error("Expected '{' after extend declaration");
                return {};
            }

            advance(1, true); // past '{'

            while (cur != Lexeme::RBrace) {
                auto member = parse_declaration();
                if (!member) {
                    report_error("Invalid declaration in struct");
                    return {};
                }
                member->outer_declaration = decl;
                ext->members.emplace_back(std::move(member));
            }

            advance(1, true); // past '}'

            return scope.result(std::move(ext));
        }

        // declaration
        std::unique_ptr<ParameterDeclarationNode> parse_parameter_declaration(
            const decl_context ctx = decl_context::None, const bool is_statement = false) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto marker = mark();
            auto param = std::make_unique<ParameterDeclarationNode>();
            param->loc = cur->location();

            param->declaration = parse_declaration(false, ctx);
            if (!param->declaration) {
                return scope.reject(std::move(marker), fmt::format("Invalid declaration for {}", to_string(ctx)));
            }
            return scope.result(std::move(param));
        }

        // ( declaration, ... )
        // < declaration, ... >
        std::unique_ptr<ParameterDeclarationsNode> parse_parameter_declarations(
            const decl_context ctx = decl_context::None, const bool is_statement = false) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto open = Lexeme::LParen;
            auto close = Lexeme::RParen;
            if (ctx == decl_context::Generic) {
                open = Lexeme::Less;
                close = Lexeme::Greater;
            }

            if (cur != open) {
                return {};
            }

            // may have to backtrack if this is another type of parenthesized expression
            auto marker = mark();
            auto params = std::make_unique<ParameterDeclarationsNode>();
            params->open = consume();

            auto param = std::make_unique<ParameterDeclarationNode>();
            size_t count = 1;
            bool trailing_comma = false;

            while (!eof() && cur != close) {
                trailing_comma = false;

                param = parse_parameter_declaration(ctx, is_statement);
                if (!param) {
                    return scope.reject(std::move(marker), "Invalid parameter declaration");
                }

                param->index = count++;
                params->parameters.emplace_back(std::move(param));

                if (cur == close) {
                    break;
                }

                if (cur != Lexeme::Comma) {
                    if (is_statement) {
                        return scope.reject(std::move(marker), "Expected ',' or ')'");
                    }
                    report_error("Expected ',' or ')' after parameter declaration");
                    return {};
                }

                trailing_comma = true;
                advance();
            }

            if (trailing_comma) {
                report_error("Expected parameter declaration after ','");
            }

            if (cur != close) {
                if (is_statement) {
                    return scope.reject(std::move(marker),
                                        fmt::format("Expected {} after parameters", close.to_string()));
                }
                report_error("Expected " + std::string(close.to_string()) + " after parameters");
                return {};
            }
            params->close = consume();

            return scope.result(std::move(params));
        }

        // parameter_declarations
        // parameter_declarations : id
        // parameter_declarations : parameter_declarations
        std::unique_ptr<FunctionTypeNode> parse_function_type(DeclarationNode* decl) {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto func = std::make_unique<FunctionTypeNode>(decl);

            auto marker = mark();

            auto params = parse_parameter_declarations(decl_context::Parameter);
            if (!params) {
                return scope.reject(std::move(marker), "Invalid parameter declaration(s)");
            }
            func->parameters = std::move(params);

            if (cur == Lexeme::Colon) {
                // parse return type
                advance(); // past ':'
                if (cur == Lexeme::LParen) {
                    // multi-return
                    func->returns = parse_parameter_declarations(decl_context::Return);
                } else {
                    func->returns = parse_id();
                }

                if (func->returns.index() == FunctionTypeNode::empty) {
                    report_error("Invalid return type specification");
                    return {};
                }
            }

            return scope.result(std::move(func));
        }

        // { statement ; ... }
        std::unique_ptr<BlockNode> parse_block() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            if (cur != Lexeme::LBrace) {
                return {};
            }

            auto block = std::make_unique<BlockNode>();
            auto marker = mark();
            block->start = consume();
            while (cur != Lexeme::RBrace) {
                auto statement = parse_statement();
                if (!statement) {
                    report_error("Invalid statement in block");
                    scope.backtrack(marker);
                    return {};
                }
                block->statements.emplace_back(std::move(statement));
            }
            block->end = consume();

            return scope.result(std::move(block));
        }

        std::unique_ptr<ImportNode> parse_import() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            if (cur != Lexeme::Keyword || cur != "use") {
                return {};
            }

            auto import = std::make_unique<ImportNode>();
            import->keyword = consume();

            if (cur == Lexeme::Identifier) {
                import->target = parse_identifier();
            } else if (cur == Lexeme::StringLiteral) {
                import->target = parse_literal();
            } else {
                report_error("Invalid 'use' directive");
                return {};
            }

            if (import->target.index() == ImportNode::empty) {
                report_error("Invalid module id after 'use'");
                return {};
            }

            if (cur->in(Lexeme::Semicolon, Lexeme::Newline)) {
                advance(1, true);
            }

            return scope.result(std::move(import));
        }

        // decl ; ...
        std::unique_ptr<ModuleNode> parse_module() {
            auto scope = trace.pushln(debug::FunctionTag{__FUNCTION__});
            auto mod = std::make_unique<ModuleNode>();
            consume_whitespace();
            while (!eof()) {
                if (auto import = parse_import()) {
                    mod->imports.emplace_back(std::move(import));
                }
                auto decl = parse_declaration();
                if (!decl) {
                    report_error("Invalid declaration", cur->location());
                    return {};
                }
                mod->declarations.emplace_back(std::move(decl));

                consume_whitespace();
            }
            return scope.result(std::move(mod));
        }
    };

    std::unique_ptr<Parser> Parser::create(const ParseState& state) {
        return std::make_unique<ParserImpl>(state);
    }

    template <int Idx>
    std::string try_visualize(auto& v, auto&&... args) {
        if (v.index() == Idx) {
            const auto& value = std::get<Idx>(v);
            return visualize(*value, std::forward<decltype(args)...>(args)...);
        }
        return "";
    }

    template <typename V>
    auto visualize_list(auto& list, V vis) {
        size_t size = std::size(list);
        std::string ret;
        for (size_t idx = 0; const auto& elem : list) {
            ret += vis(elem);
            if (idx++ < (size - 1)) {
                ret += ", ";
            }
        }
        return ret;
    }

    auto visualize(const Token& t, size_t depth) -> std::string {
        return t.to_string();
    }

    auto visualize(const std::vector<Token>& ts, size_t depth) -> std::string {
        std::string ret;
        for (const auto& t : ts) {
            ret += t.to_string() + " ";
        }
        return ret;
    }

    auto visualize(const PrimaryExpressionNode& n, size_t depth) -> std::string {
        std::string ret;
        ret += try_visualize<PrimaryExpressionNode::id>(n.expr, depth);
        ret += try_visualize<PrimaryExpressionNode::expressions>(n.expr, depth);
        ret += try_visualize<PrimaryExpressionNode::declaration>(n.expr, depth);
        ret += try_visualize<PrimaryExpressionNode::literal>(n.expr, depth);
        return ret;
    }

    auto visualize(const LiteralNode& l, size_t depth) -> std::string {
        return l.literal->to_string();
    }

    auto visualize(const IdentifierNode& i, size_t depth) -> std::string {
        return i.identifier->to_string();
    }

    auto visualize(const PrefixExpressionNode& n, size_t depth) -> std::string {
        std::string ret;
        for (const auto& op : n.ops) {
            ret += op->to_string();
        }

        ret += visualize(*n.expr, depth);
        return ret;
    }

    auto visualize(const PostfixExpressionNode& n, size_t depth) -> std::string {
        auto ret = visualize(*n.expr, depth);
        for (const auto& op : n.ops) {
            ret += " " + op.op->to_string() + " " + visualize(*op.exprs, depth);
        }
        return ret;
    }

    auto visualize(const ExpressionNode& expr, size_t depth) -> std::string {
        return visualize(*expr.expr, depth);
    }

    auto visualize(const ExpressionsNode& exprs, size_t depth) -> std::string {
        auto ret = exprs.open->to_string();

        ret += visualize_list(exprs.expressions, [depth](const auto& expr) { return visualize(*expr->expr, depth); });

        ret += exprs.close->to_string();
        return ret;
    }

    template <typename Operand, ConstString Name>
    auto visualize(const BinaryExpressionNode<Operand, Name>& b, size_t depth) -> std::string {
        auto ret = visualize(*b.expr, depth);
        for (const auto& op : b.operands) {
            ret += " " + op.op->to_string() + " " + visualize(*op.expr, depth);
        }
        return ret;
    }

    auto visualize(const ExpressionStatementNode& expr, size_t depth) -> std::string {
        auto ret = visualize(*expr.expr, depth);
        if (expr.terminates) {
            ret += ";";
        }
        return ret;
    }

    auto visualize(const IdNode& t, size_t depth) -> std::string {
        std::string ret;

        ret += visualize(*t.identifier, depth);
        if (t.open_generic) {
            ret += "<";
            ret += visualize_list(t.generic_args, [depth](const auto& arg) { return visualize(*arg.type, depth); });
            ret += ">";
        }
        return ret;
    }

    auto visualize(const BlockNode& b, size_t depth) -> std::string {
        auto ret = std::string(" ") + "{\n";
        for (const auto& s : b.statements) {
            ret += visualize(*s, depth + 1);
        }
        ret += std::string("\n") + indent(depth) + "}";
        return ret;
    }

    auto visualize(const StatementNode& s, size_t depth) -> std::string {
        std::string ret;

        if (s.is_expression()) {
            if (s.parent) {
                ret += std::string("\n") + indent(depth);
            }
            const auto& expr = std::get<StatementNode::expression>(s.statement);
            ret += visualize(*expr, depth);
        } else {
            ret += try_visualize<StatementNode::block>(s.statement, depth);
            ret += try_visualize<StatementNode::branch>(s.statement, depth);
            ret += try_visualize<StatementNode::declaration>(s.statement, depth);
            ret += try_visualize<StatementNode::ret>(s.statement, depth);
            ret += try_visualize<StatementNode::loop>(s.statement, depth);
            ret += try_visualize<StatementNode::jump>(s.statement, depth);
        }

        return ret;
    }

    auto visualize(const CastExpressionNode& c, size_t depth) -> std::string {
        auto ret = visualize(*c.expr, depth);
        for (const auto& op : c.operands) {
            if (op.op) {
                ret += " " + op.op->to_string() + " ";
            }
            if (op.type) {
                ret += visualize(*op.type, depth);
            }
            if (op.op) {
                ret += visualize(*op.op, depth);
            }
        }
        return ret;
    }

    auto visualize(const BranchNode& b, size_t depth) -> std::string {
        auto ret = std::string("\n") + indent(depth) + b.keyword->to_string() + " ";
        ret += visualize(*b.condition, depth);
        ret += visualize(*b.then_block, depth);
        if (b.else_block) {
            ret += visualize(*b.else_block, depth);
        }
        return ret;
    }

    auto visualize(const LoopNode& loop, size_t depth) -> std::string {
        std::string ret;
        if (loop.body) {
            ret += visualize(*loop.body, depth);
        }

        if (*loop.keyword == "for") {
            ret = "for " + visualize(*loop.iterator, depth) + " " + //
                  visualize(*loop.condition, depth) + " " +         //
                  visualize(*loop.next_expr, depth) + ret;
        }
        if (*loop.keyword == "while") {
            ret = "while " + visualize(*loop.condition, depth) + ret;
        }
        return ret;
    }

    auto visualize(const ReturnStatementNode& r, size_t depth) -> std::string {
        auto ret = std::string("\n") + indent(depth) + "return";
        if (r.expression) {
            ret += " " + visualize(*r.expression, depth);
        }
        return ret;
    }

    auto visualize(const JumpStatementNode& j, size_t depth) -> std::string {
        auto ret = std::string("\n") + indent(depth) + j.keyword->to_string();
        if (j.label) {
            ret += " " + j.label->to_string();
        }
        return ret;
    }

    auto visualize(const ImportNode& i, size_t depth) -> std::string {
        auto ret = std::string("\n") + "use ";
        try_visualize<ImportNode::identifier>(i.target, depth);
        try_visualize<ImportNode::literal>(i.target, depth);
        return ret;
    }

    auto visualize(const FunctionTypeNode& f, size_t depth) -> std::string {
        std::string ret;
        ret += try_visualize<FunctionTypeNode::single>(f.returns, depth);
        ret += try_visualize<FunctionTypeNode::multiple>(f.returns, depth);
        ret += " (";
        ret += visualize_list(*f.parameters, [depth](const auto& p) { return visualize(*p, depth); });
        ret += ")";
        return ret;
    }

    auto visualize(const ParameterDeclarationNode& p, size_t depth) -> std::string {
        return visualize(*p.declaration, depth);
    }

    auto visualize(const ParameterDeclarationsNode& ps, size_t depth) -> std::string {
        auto ret = ps.open->to_string();

        for (const auto& p : ps.parameters) {
            ret += visualize(*p, depth);
        }

        ret += ps.close->to_string();
        return ret;
    }

    auto visualize(const TypeDeclNode& type, size_t depth) -> std::string {
        std::string ret = visualize(*type.identifier, depth);
        if (!type.generic_params.empty()) {
            ret += "<";
            ret += visualize_list(type.generic_params, [depth](const auto& p) { return visualize(*p.param, depth); });
            ret += ">";
        }
        return ret;
    }

    auto visualize(const StructTypeNode& s, size_t depth) -> std::string {
        std::string ret = "{";
        ret += visualize_list(s.members, [depth](const auto& member) { return visualize(*member, depth + 1); });
        ret += "}\n";
        return ret;
    }

    auto visualize(const DeclarationNode& d, size_t depth) -> std::string {
        std::string type_name = visualize(*d.type_decl, depth);

        std::string initializer;
        if (d.initializer) {
            initializer += visualize(*d.initializer, depth);
        }

        std::string ret;
        if (!d.outer_is_function() && !d.outer_is_struct() && !d.is_parameter()) {
            const DeclarationNode* last_outer_type = nullptr;
            if (d.outer_is_struct()) {
                last_outer_type = d.outer();
            } else {
                ret += "\n";
            }
        } else {
            ret += "\n";
        }

        if (!d.is_function_parameter && d.name()) {
            ret += std::string("\n") + indent(depth);
        }

        if (d.identifier) {
            ret += visualize(*d.identifier, depth);
        }

        if (d.is_function()) {
            const auto& f = std::get<DeclarationNode::function>(d.type_info);
            ret += type_name + visualize(*f, depth) + initializer;
        } else if (d.is_struct()) {
            const auto& t = std::get<DeclarationNode::structure>(d.type_info);
            ret += type_name + " " + visualize(*t, depth) + initializer;
        }

        return ret;
    }

    auto visualize(const ModuleNode& m, size_t depth) -> std::string {
        std::string ret;
        for (const auto& d : m.declarations) {
            ret += visualize(*d, depth) + "\n";
        }
        return ret;
    }
}} // namespace pepper::parser
