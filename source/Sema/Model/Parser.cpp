
#include "Sema/Model/Parser.h"
#include <filesystem>

#include "Sema/Model/Tracer.h"

namespace pepper::sema {
    using namespace pepper::parser;

#define TRACE(node)                                                                                                    \
    trace.trace(fmt::format(                                                                                           \
        "{}({})", internal::function_name(__FUNCTION__), internal::type_name<std::decay_t<decltype(node)>>()))
#define TRACE_VAL(node)                                                                                                \
    trace.trace(fmt::format("-> {}({}): {}",                                                                           \
                            internal::function_name(__FUNCTION__),                                                     \
                            internal::type_name<std::decay_t<decltype(node)>>(),                                       \
                            visualize(node, 0)))
#define TRACE_SCOPE(node)                                                                                              \
    auto scope_##__LINE__ = trace.scope(fmt::format(                                                                   \
        "{}({})", internal::function_name(__FUNCTION__), internal::type_name<std::decay_t<decltype(node)>>()))
#define TRACE_PUSH(node)                                                                                               \
    auto scope_##__LINE__ = trace.pushln(fmt::format(                                                                  \
        "{}({})", internal::function_name(__FUNCTION__), internal::type_name<std::decay_t<decltype(node)>>()))
#define TRACE_FUNCTION(node) TRACE_PUSH(node)
#define TRACE_NODE(node) trace.trace((node).to_string())
#define TRACE_POP(node)                                                                                                \
    (void)(node);                                                                                                      \
    trace.pop()

#define TRACE_NONE

#define SOURCE_SCOPE(node) const SourceScope PEP_CONCAT(_sourceScope_, __LINE__){this, node};

#define VISIT_PREAMBLE(node, trace)                                                                                    \
    trace(node);                                                                                                       \
    SOURCE_SCOPE(node);

    class ParserImpl : public Parser {
        Module* module;
        const ModuleNode* parse_tree;
        Builder* builder;
        bool has_errors = false;
        SourcePosition position;
        ParserTracer trace;

        void record_error_context(const std::string& msg, SourcePosition loc = {}) {
            if (loc == SourcePosition{}) {
                loc = position;
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
            assert(!"find_line_start: found no tokens on line");
            return -1;
        }

        void print_error_and_source(SourcePosition loc, const std::string& msg) {
            std::cerr << std::endl << fmt::format("{}({}): {}\n", source_file, loc.line, msg);
            // Find the start of the line the error occurred on
            size_t start = find_line_start(loc.line);
            while (start > 0 && tokens[start] != Lexeme::Newline) {
                --start;
            }
            size_t idx = start + 1;
            while (idx < tokens.size() && tokens[idx] != Lexeme::Newline) {
                std::cerr << tokens[idx].to_string();
                ++idx;
            }
            std::cerr << std::endl;
            std::cerr << indent(loc.column - 1) << '^' << std::endl;
        }

        void report_error(const char* msg, SourcePosition loc = {}) {
            if (loc == SourcePosition{}) {
                loc = position;
            }
            std::cerr << std::endl;

            // report any gathered error context
            for (const auto& err : errors) {
                print_error_and_source(err.where, err.what);
            }
            clear_error_context();

            print_error_and_source(loc, msg);
            std::cerr.flush();
        }

        void report_error(const std::string& msg, SourcePosition loc = {}) {
            report_error(msg.c_str(), loc);
        }

        void push_source(const SourcePosition& pos) {
            Node::push_source(SourceLocation{source_file, pos.line, pos.column});
        }

        void pop_source() {
            Node::pop_source();
        }

        template <typename N>
        void push_source(const N& node) {
            push_source(node.location());
        }

        class SourceScope {
            ParserImpl* parser;

          public:
            template <typename N>
            SourceScope(ParserImpl* p, const N& node)
                : parser(p) {
                parser->push_source(node);
            }

            ~SourceScope() {
                parser->pop_source();
            }
        };

        void push_node(Node* val) {
            trace.traceln(fmt::format("lpush: {}", val->to_string()));
            builder->push_lvalue(val);
        }

        template <typename N>
        N* pop_node() {
            auto val = builder->pop_lvalue();
            // unwrap pending node if found
            if (val) {
                trace.traceln(fmt::format("lpop:  {}", val->to_string()));
                if (val->is<Pending>() && val->as<Pending>()->Type->is(RTTI::of<N>())) {
                    auto value = val->as<Pending>()->Value;
                    return value ? value->as<N>() : nullptr;
                }

                if (val->is<N>()) {
                    return val->as<N>();
                }
            }

            throw InternalCompilerError("Attempted to pop {0} from AST l-value stack, found {1} instead",
                                        RTTI::of<N>()->name(),
                                        val ? RTTI::of(*val)->name() : "null");
        }

        template <typename N>
        N* peek_node(unsigned int idx = 0) {
            auto val = builder->peek_lvalue(idx);
            // unwrap pending node if found
            if constexpr (!std::is_same_v<N, Pending>) {
                if (val && val->is<Pending>() && val->as<Pending>()->Type->is(RTTI::of<N>())) {
                    auto value = val->as<Pending>()->Value;
                    return value ? value->as<N>() : nullptr;
                }
            }
            if (val && val->is<N>()) {
                return val->as<N>();
            }
            return nullptr;
        }

        template <typename N>
        bool has_node(unsigned int idx = 0) const {
            auto val = builder->peek_lvalue(idx);
            // unwrap pending node if found
            if constexpr (!std::is_same_v<N, Pending>) {
                if (val && val->is<Pending>() && val->as<Pending>()->Type->is(RTTI::of<N>())) {
                    return true;
                }
            }
            if (val && val->is<N>()) {
                return true;
            }
            return false;
        }

        bool push_rvalue(Node* val) {
            // Only bother tracking this rvalue if there is a pending l-value on the stack to receive it
            if (peek_node<Pending>() || peek_node<Node>()) {
                builder->push_rvalue(val);
                return true;
            }
            return false;
        }

        void push_or_insert_rvalue(Node* val) {
            if (push_rvalue(val))
                return;
            builder->insert(val);
        }

        template <typename N>
        N* pop_rvalue() {
            auto val = builder->pop_rvalue();
            if (val && val->is<N>()) {
                return val->as<N>();
            }
            throw InternalCompilerError("Attempted to pop {0} from AST r-value stack, found {1} instead",
                                        RTTI::of<N>()->name(),
                                        val ? RTTI::of(*val)->name() : "null");
        }

        template <typename N>
        N* peek_rvalue(unsigned int idx = 0) {
            auto val = builder->peek_rvalue(idx);
            if (val && val->is<N>()) {
                return val->as<N>();
            }
            throw InternalCompilerError("Attempted to peek a {0} in AST r-value stack at slot {1}, found {2} instead",
                                        RTTI::of<N>()->name(),
                                        idx,
                                        val ? RTTI::of(*val)->name() : "null");
        }

      public:
        ParserImpl(const ParseState& state, Module* mod, const ModuleNode* tree)
            : Parser(state)
            , module(mod)
            , parse_tree(tree)
            , builder(mod->builder(&trace)) {
            trace.traceln(fmt::format("Sema Parsing {}:", source_file));
        }

        bool parse() override {
            parse_tree->visit(*this);
            return !has_errors;
        }

        Module* ast() const override {
            return module;
        }

        static TypeName parse_type_name(const IdNode& id) {
            TypeName type(id.identifier->identifier->to_string());
            for (const auto& arg : id.generic_arguments()) {
                type.sub_types.push_back(parse_type_name(*arg.type));
            }
            for (const auto& qualifier : id.qualifiers) {
                if (qualifier->in(Lexeme::Star)) {
                    type.name += "*";
                }
            }
            // TODO: arrays
            return type;
        }

        static TypeName parse_type_name(const TypeDeclNode& decl) {
            TypeName type(decl.identifier->identifier->to_string());
            for (const auto& arg : decl.generic_params) {
                const auto& arg_decl = arg.param->declaration->type_decl;
                assert(arg_decl);
                type.sub_types.push_back(parse_type_name(*arg_decl));
            }
            return type;
        }

        static Literal* parse_literal(const LiteralNode& literal) {
            const auto token = literal.token()->to_string();
            switch (literal.token()->type()) {
                case Lexeme::BoolLiteral: {
                    return new BoolLiteral(literal.to_string() == "true");
                }
                case Lexeme::IntLiteral: {
                    const int64_t value = std::atoll(token.c_str());
                    return new IntegerLiteral(value);
                }
                case Lexeme::FloatLiteral: {
                    const double value = std::atof(token.c_str());
                    return new FloatLiteral(value);
                }
                case Lexeme::StringLiteral:
                case Lexeme::RawStringLiteral:
                    return new StringLiteral(token, literal.token()->type() == Lexeme::RawStringLiteral);
                default:
                    break;
            }
            throw new InternalCompilerError("Unexpected literal type: {0}", literal.to_string());
        }

        // default handlers for visit events
        void start(const auto& node) {
            // VISIT_PREAMBLE(node, TRACE_FUNCTION);
        }

        void end(const auto& node) {
            // VISIT_PREAMBLE(node, TRACE_FUNCTION);
        }

        void visit(const auto& node) {
            // VISIT_PREAMBLE(node, TRACE_VAL);
        }

        // void visit(const IdentifierNode& identifier) {
        //     VISIT_PREAMBLE(identifier, TRACE_VAL);
        //     trace.traceln();
        //     if (auto import = peek_node<Import>()) {
        //         import->Module = identifier.to_string();
        //         return;
        //     }
        //     if (auto variable = peek_node<VariableDef>()) {
        //         variable->name = identifier.to_string();
        //         return;
        //     }
        //     if (has_node<FunctionDef>()) {
        //         // nothing to do here, the identifier will be consumed by the FunctionTypeNode parser
        //         return;
        //     }
        //
        //     report_error("Unexpected identifier", identifier.location());
        // }

        void visit(const IdNode& id) {
            VISIT_PREAMBLE(id, TRACE_VAL);

            if (peek_rvalue<SymbolRef>()) {
                pop_rvalue<SymbolRef>();
                push_rvalue(new SymbolRef(id.token()->to_string()));
            }
        }

        void visit(const LiteralNode& literal) {
            VISIT_PREAMBLE(literal, TRACE_VAL);

            if (auto variable = peek_node<VariableDef>()) {
                const auto token = literal.token()->to_string();
                const auto parsed_literal = parse_literal(literal);
                push_rvalue(parsed_literal);
            }

            report_error("Unexpected literal", literal.location());
        }

        void visit(const ImportNode& imp) {
            VISIT_PREAMBLE(imp, TRACE_FUNCTION);
            auto* import = new Import();

            if (imp.is_identifier()) {
                import->Local = false;
                import->Module = imp.get_if<IdentifierNode>()->to_string();
            } else if (imp.is_literal()) {
                import->Local = true;
                import->Module = imp.get_if<LiteralNode>()->to_string();
            }
            builder->import(import);
        }

        void start(const BlockNode& block) {
            VISIT_PREAMBLE(block, TRACE_FUNCTION);
            builder->begin_block(new Block());
        }

        void end(const BlockNode& block) {
            VISIT_PREAMBLE(block, TRACE_FUNCTION);
            builder->end_block();
        }

        void start(const DeclarationNode& decl) {
            VISIT_PREAMBLE(decl, TRACE_FUNCTION);
            switch (decl.type_info.index()) {
                case DeclarationNode::empty: // no type, must be inferred from initializer
                case DeclarationNode::variable:
                    start_variable_decl(decl);
                    break;
                case DeclarationNode::function:
                    start_function_decl(decl);
                    break;
                    // case DeclarationNode::structure:
                    //     start<structure>();
                    //     break;
                    // case DeclarationNode::extension:
                    //     start<extension>();
                    //     break;
                    // default:
                    //     report_error("Unexpected declaration");
            }
        }

        void end(const DeclarationNode& decl) {
            VISIT_PREAMBLE(decl, TRACE_FUNCTION);
            switch (decl.type_info.index()) {
                case DeclarationNode::variable:
                    end_variable_decl(decl);
                    break;
                case DeclarationNode::function:
                    end_function_decl(decl);
                    break;
                    // case DeclarationNode::structure:
                    //     start<structure>();
                    //     break;
                    // case DeclarationNode::extension:
                    //     start<extension>();
                    //     break;
                    // default:
                    //     report_error("Unexpected declaration");
            }
        }

        void start_variable_decl(const DeclarationNode& var_decl) {
            VISIT_PREAMBLE(var_decl, TRACE_FUNCTION);
            assert(var_decl.is_variable());

            if (const auto struct_def = builder->target_as<StructDef>()) {
                push_node(new FieldDef(struct_def->type));
            } else {
                push_node(new VariableDef());
            }
            VariableDef* var = peek_node<VariableDef>();
            var->type = parse_type_name(*var_decl.type_decl);
            var->name = var_decl.identifier->identifier->to_string();
        }

        void end_variable_decl(const DeclarationNode& var_decl) {
            VISIT_PREAMBLE(var_decl, TRACE_FUNCTION);
            assert(var_decl.is_variable());

            auto* var = pop_node<VariableDef>();
            builder->symbol(var);
        }

        void start_function_decl(const DeclarationNode& func_decl) {
            VISIT_PREAMBLE(func_decl, TRACE_SCOPE);
            FunctionDef* func = [&]() -> FunctionDef* {
                if (const auto st = builder->target_as<StructDef>()) {
                    return new MethodDef(st->type);
                }
                return new FunctionDef();
            }();
            push_node(func);
            parse(*func_decl.function_type());
            TRACE_NODE(*func);
            builder->begin_function(func);
            func_decl.function_type()->visit(*this);
        }

        void end_function_decl(const DeclarationNode& func_decl) {
            VISIT_PREAMBLE(func_decl, TRACE_SCOPE);
            builder->end_function();
            pop_node<FunctionDef>();
        }

        void parse(const FunctionTypeNode& func) {
            VISIT_PREAMBLE(func, TRACE_FUNCTION);

            FunctionDef* function = peek_node<FunctionDef>();
            assert(function);

            function->type = parse_type_name(*func.declaration->type_decl);
            function->is_generic_func = function->type.sub_types.size() > 0;

            function->return_type = [&]() {
                if (func.has_void_return_type()) {
                    return TypeName::Void;
                }
                if (func.has_explicit_return_type()) {
                    return parse_type_name(*std::get<FunctionTypeNode::single>(func.returns));
                }
                if (func.has_implicit_return_type()) {
                    return TypeName::Auto;
                }
                // TODO: multi-return
                assert(!func.has_multi_return_type());
                return TypeName::Auto;
            }();

            const auto location = builder->location();
            function->name = {func.declaration->has_name()
                                  ? func.declaration->name()->to_string()
                                  : fmt::format("lambda_{}_{}_{}",
                                                std::filesystem::path(this->source_file).filename().string(),
                                                location.line,
                                                location.column)};

            if (func.parameters) {
                for (const auto& param : *func.parameters) {
                    const auto& decl = param->declaration;
                    if (!decl->is_parameter()) {
                        report_error("Parameter declaration is not a parameter", decl->loc);
                    }
                    TypeName param_type = parse_type_name(*decl->variable_type());
                    Ident param_name = param->declaration->name()->to_string();
                    function->parameters.emplace_back(param_name, param_type);
                }
            }
        }

        void start(const StatementNode& statement) {
            VISIT_PREAMBLE(statement, TRACE_FUNCTION);
            if (statement.is_declaration()) {
                // const auto* decl = statement.get_if<DeclarationNode>();
                // if (decl->is_variable()) {

                //     push_node()
                // }
            }
        }

        void end(const StatementNode& statement) {
            VISIT_PREAMBLE(statement, TRACE_FUNCTION);
            if (statement.is_declaration()) {
                // auto symbol = pop_node<VariableDef>();
                // symbol->default_value = pop_rvalue<Expression>();
                // builder->symbol(symbol);
                // push_rvalue(symbol);
            }
        }

        void start(const PrimaryExpressionNode& expr) {
            VISIT_PREAMBLE(expr, TRACE_FUNCTION);
            // if (expr.is_id()) {
            //     push_rvalue(Pending::create<SymbolRef>());
            // }
        }

        void end(const PrimaryExpressionNode& expr) {
            VISIT_PREAMBLE(expr, TRACE_FUNCTION);
            // if (expr.is_id()) {
            //     auto ref = pop_rvalue<SymbolRef>();
            // }
        }

        void visit(const Token& token) {
            trace.trace(fmt::format("Token: {}", token.to_string()));
        }

        // void end(const FunctionTypeNode& func) {
        //     VISIT_PREAMBLE(func, TRACE_FUNCTION);
        //     builder->end_function();
        //     pop_node<FunctionDef>();
        // }

        void start(const StructTypeNode& struct_type) {
            VISIT_PREAMBLE(struct_type, TRACE_FUNCTION);
        }

        void end(const StructTypeNode& struct_type) {
            VISIT_PREAMBLE(struct_type, TRACE_FUNCTION);
        }

        void start(const ExtensionNode& ext) {
            VISIT_PREAMBLE(ext, TRACE_FUNCTION);
        }

        void end(const ExtensionNode& ext) {
            VISIT_PREAMBLE(ext, TRACE_FUNCTION);
        }

        // void visit(const AssignmentExpressionNode& expr) {

        // }

        // void visit(const LogicOrExpressionNode& expr) {

        // }

        // void visit(const LogicAndExpressionNode& expr) {

        // }

        // void visit(const BitOrExpressionNode& expr) {

        // }

        // void visit(const BitXorExpressionNode& expr) {

        // }

        // void visit(const BitAndExpressionNode& expr) {

        // }

        // void visit(const EqualityExpressionNode& expr) {

        // }

        // void visit(const RelationExpressionNode& expr) {

        // }

        // void visit(const CompareExpressionNode& expr) {

        // }

        // void visit(const ShiftExpressionNode& expr) {

        // }

        // void visit(const SumExpressionNode& expr) {

        // }

        // void visit(const ProductExpressionNode& expr) {

        // }

        // void visit(const CastExpressionNode& expr) {

        // }

        // void visit(const PrefixExpressionNode& expr) {

        // }

        // void visit(const PostfixExpressionNode& expr) {

        // }
    };

    std::unique_ptr<Parser> Parser::create(
        const ParseState& state, Module* module, const parser::ModuleNode* parse_tree) {
        return std::make_unique<ParserImpl>(state, module, parse_tree);
    }
} // namespace pepper::sema
