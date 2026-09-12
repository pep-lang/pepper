//
// Created by justi on 5/27/2026.
//

#include "ModelBuilder.h"

#include "Model/Tracer.h"
#include "Param.h"

#define TRACE(node)                                                                                                    \
    trace.trace(fmt::format(                                                                                           \
        "{}({})", internal::function_name(__FUNCTION__), internal::type_name<std::decay_t<decltype(node)>>()))
#define TRACE_VAL(node)                                                                                                \
    trace.trace(fmt::format("-> {}({}): {}",                                                                           \
                            internal::function_name(__FUNCTION__),                                                     \
                            internal::type_name<std::decay_t<decltype(node)>>(),                                       \
                            visualize(node, 0)))
#define TRACE_SCOPE(node)                                                                                              \
    auto PEP_CONTAT(scope, __LINE__) = trace.scope(fmt::format(                                                        \
        "{}({})", internal::function_name(__FUNCTION__), internal::type_name<std::decay_t<decltype(node)>>()))
#define TRACE_PUSH(node)                                                                                               \
    auto PEP_CONCAT(scope, __LINE__) = trace.pushln(fmt::format(                                                       \
        "{}({})", internal::function_name(__FUNCTION__), internal::type_name<std::decay_t<decltype(node)>>()))
#define TRACE_FUNCTION(node) TRACE_PUSH(node)
#define TRACE_NODE(node) trace.trace((node).to_string())
#define TRACE_POP(node)                                                                                                \
    (void)(node);                                                                                                      \
    trace.pop()

#define TRACE_NONE

#define SOURCE_SCOPE(node)                                                                                             \
    const SourceScope PEP_CONCAT(_sourceScope_, __LINE__) {                                                            \
        node                                                                                                           \
    }

#define VISIT_PREAMBLE(node, trace)                                                                                    \
    trace(node);                                                                                                       \
    SOURCE_SCOPE(node)

namespace pepper::sema {
    class SemaParser {
        struct SourceScope {
            explicit SourceScope(const ast::Node& node) {
                Node::push_source(node.Location);
            }

            ~SourceScope() {
                Node::pop_source();
            }
        };

        ParserTracer trace;
        std::shared_ptr<Module> module;
        Builder* builder = nullptr;

      public:
        explicit SemaParser(const std::shared_ptr<Module>& _module)
            : module(_module) {
            builder = module->builder(&trace);
        }

        void visit(const ast::Module& mod) {
            builder->begin_scope("global");
            for (const auto& import : mod.imports) {
                visit(*import);
            }
            for (const auto& decl : mod.declarations) {
                visit(*decl);
            }
            builder->end_scope();
        }

      private:
        template <typename T, typename N>
            requires std::is_base_of_v<ast::Node, N> && std::is_base_of_v<ast::Node, T>
        auto try_visit(const N& node) {
            if (node.template is<T>()) {
                return visit(*node.template as<T>());
            }
            return decltype(visit(*node.template as<T>()))();
        }

        void visit(const ast::Import& import) {
            VISIT_PREAMBLE(import, TRACE_VAL);
            builder->import(new Import(import.name, import.is_local, import.alias));
        }

        void visit(const ast::Declaration& decl) {
            try_visit<ast::VariableDecl>(decl);
            try_visit<ast::StructDecl>(decl);
            try_visit<ast::FunctionDecl>(decl);
        }

        void visit(const ast::Statement& stmt) {
            if (stmt.is_block()) {
                const auto* block = stmt.node()->as<ast::Block>();
                visit(block->body);
                return;
            }
            if (stmt.is_expression()) {
                const auto* expr = stmt.node()->as<ast::Expr>();
                builder->insert(visit(*expr));
                return;
            }
            if (stmt.is_declaration()) {
                const auto* decl = stmt.node()->as<ast::Declaration>();
                visit(*decl);
                return;
            }
            if (stmt.is_branch()) {
                const auto* branch = stmt.node()->as<ast::Branch>();
                visit(*branch);
                return;
            }
            if (stmt.is_loop()) {
                const auto* loop = stmt.node()->as<ast::While>();
                visit(*loop);
                return;
            }
            if (stmt.is_return()) {
                const auto* ret = stmt.node()->as<ast::ReturnStatement>();
                visit(*ret);
                return;
            }
        }

        Block* visit(const std::vector<std::shared_ptr<ast::Statement>>& block_statements) {
            auto* block = new Block();
            builder->begin_block(block);
            for (const auto& stmt : block_statements) {
                visit(*stmt);
            }
            builder->end_block();
            return block;
        }

        Block* visit(const ast::Block& block) {
            VISIT_PREAMBLE(block, TRACE_FUNCTION);
            return visit(block.body);
        }

        void visit(const ast::VariableDecl& decl) {
            VISIT_PREAMBLE(decl, TRACE_VAL);
            Expression* value = decl.default_value ? visit(*decl.default_value) : nullptr;
            const auto var = new VariableDef(decl.type, decl.name, value);
            builder->symbol(var);
        }

        void visit(const ast::FunctionDecl& decl) {
            VISIT_PREAMBLE(decl, TRACE_FUNCTION);
            Params params;
            for (const auto& param : decl.parameters) {
                params.emplace_back(
                    param.name, param.type, param.default_value ? visit(*param.default_value) : nullptr);
            }

            if (decl.external) {
                builder->insert(new ExternFunctionRef(decl.return_type, decl.name, params));
                return;
            }

            auto* function = new FunctionDef(decl.return_type, decl.name, params);
            builder->begin_function(function);
            function->body = visit(*decl.body);
            function->body->name = function->name;
            builder->end_function();
        }

        void visit(const ast::StructDecl& decl) {
            VISIT_PREAMBLE(decl, TRACE_FUNCTION);
            auto* st = new StructDef(decl.name, decl.name.name);
            builder->begin_struct(st);
            for (const auto& field : decl.fields) {
                visit(field);
            }
            for (const auto& method : decl.methods) {
                visit(method);
            }
            builder->end_struct();
        }

        Expression* visit(const ast::Expr& expr) {
            if (auto* binary_expr = try_visit<ast::BinaryExpr>(expr))
                return binary_expr;
            if (auto* unary_expr = try_visit<ast::UnaryExpr>(expr))
                return unary_expr;
            if (auto* ref = try_visit<ast::SymbolRef>(expr))
                return ref;
            if (auto* literal = try_visit<ast::Literal<bool>>(expr))
                return literal;
            if (auto* literal = try_visit<ast::Literal<int64_t>>(expr))
                return literal;
            if (auto* literal = try_visit<ast::Literal<double>>(expr))
                return literal;
            if (auto* literal = try_visit<ast::String>(expr))
                return literal;
            if (auto* size_of = try_visit<ast::SizeOf>(expr))
                return size_of;
            if (auto* ternary = try_visit<ast::TernaryExpr>(expr))
                return ternary;
            if (auto* index = try_visit<ast::IndexExpr>(expr))
                return index;
            if (auto* member = try_visit<ast::MemberAccess>(expr))
                return member;
            if (auto* call = try_visit<ast::FunctionCall>(expr))
                return call;
            return nullptr;
        }

        BinaryOp* visit(const ast::BinaryExpr& expr) {
            VISIT_PREAMBLE(expr, TRACE_FUNCTION);
            static std::unordered_map<std::string, std::function<BinaryOp*(Expression * lhs, Expression * rhs)>>
                binary_ops = {
                    {"+", [](auto* lhs, auto* rhs) { return new Add(lhs, rhs); }},
                    {"-", [](auto* lhs, auto* rhs) { return new Sub(lhs, rhs); }},
                    {"*", [](auto* lhs, auto* rhs) { return new Mul(lhs, rhs); }},
                    {"/", [](auto* lhs, auto* rhs) { return new Div(lhs, rhs); }},
                    {"%", [](auto* lhs, auto* rhs) { return new Mod(lhs, rhs); }},
                    {"<<", [](auto* lhs, auto* rhs) { return new LShift(lhs, rhs); }},
                    {">>", [](auto* lhs, auto* rhs) { return new RShift(lhs, rhs); }},
                    {"&", [](auto* lhs, auto* rhs) { return new BitAnd(lhs, rhs); }},
                    {"&&", [](auto* lhs, auto* rhs) { return new LogicalAnd(lhs, rhs); }},
                    {"|", [](auto* lhs, auto* rhs) { return new BitOr(lhs, rhs); }},
                    {"||", [](auto* lhs, auto* rhs) { return new LogicalOr(lhs, rhs); }},
                    {"^", [](auto* lhs, auto* rhs) { return new BitXor(lhs, rhs); }},
                    {"==", [](auto* lhs, auto* rhs) { return new Equal(lhs, rhs); }},
                    {">=", [](auto* lhs, auto* rhs) { return new GreaterEqual(lhs, rhs); }},
                    {"<=", [](auto* lhs, auto* rhs) { return new LessEqual(lhs, rhs); }},
                    {">", [](auto* lhs, auto* rhs) { return new Greater(lhs, rhs); }},
                    {"<", [](auto* lhs, auto* rhs) { return new Less(lhs, rhs); }},
                    {"!=", [](auto* lhs, auto* rhs) { return new NotEqual(lhs, rhs); }},
                    {"**", [](auto* lhs, auto* rhs) { return new Pow(lhs, rhs); }},
                    {"=", [](auto* lhs, auto* rhs) { return new Assign(lhs, rhs); }},
                    {"+=", [](auto* lhs, auto* rhs) { return new AddAssign(lhs, rhs); }},
                    {"-=", [](auto* lhs, auto* rhs) { return new SubAssign(lhs, rhs); }},
                    {"*=", [](auto* lhs, auto* rhs) { return new MulAssign(lhs, rhs); }},
                    {"/=", [](auto* lhs, auto* rhs) { return new DivAssign(lhs, rhs); }},
                    {"%=", [](auto* lhs, auto* rhs) { return new ModAssign(lhs, rhs); }},
                    {"<<=", [](auto* lhs, auto* rhs) { return new LShiftAssign(lhs, rhs); }},
                    {">>=", [](auto* lhs, auto* rhs) { return new RShiftAssign(lhs, rhs); }},
                    {"&=", [](auto* lhs, auto* rhs) { return new BitAndAssign(lhs, rhs); }},
                    {"|=", [](auto* lhs, auto* rhs) { return new BitOrAssign(lhs, rhs); }},
                    {"^=", [](auto* lhs, auto* rhs) { return new BitOrAssign(lhs, rhs); }},
                };
            const auto& factory = binary_ops[expr.op];
            return factory(visit(*expr.lhs), visit(*expr.rhs));
        }

        UnaryOp* visit(const ast::UnaryExpr& expr) {
            VISIT_PREAMBLE(expr, TRACE_FUNCTION);
            static std::unordered_map<std::string, std::function<UnaryOp*(Expression * expr, bool pre)>> unary_ops = {
                {"+", [](auto* operand, bool) { return new Plus(operand); }},
                {"-", [](auto* operand, bool) { return new Minus(operand); }},
                {"++",
                 [](auto* operand, bool pre) -> UnaryOp* {
                     if (pre)
                         return new PreIncrement(operand);
                     return new PostIncrement(operand);
                 }},
                {"--",
                 [](auto* operand, bool pre) -> UnaryOp* {
                     if (pre)
                         return new PreDecrement(operand);
                     return new PostDecrement(operand);
                 }},
                {"!", [](auto* operand, bool pre) -> UnaryOp* { return new LogicalNot(operand); }},
                {"~", [](auto* operand, bool pre) -> UnaryOp* { return new BitNot(operand); }},
            };
            const auto& factory = unary_ops[expr.op];
            return factory(visit(*expr.operand), expr.type == ast::Prefix);
        }

        SymbolRef* visit(const ast::SymbolRef& ref) {
            VISIT_PREAMBLE(ref, TRACE_VAL);
            if (ref.identifier == "this")
                return new ThisRef();
            return new SymbolRef(ref.identifier);
        }

        BoolLiteral* visit(const ast::Literal<bool>& literal) {
            VISIT_PREAMBLE(literal, TRACE_VAL);
            return new BoolLiteral(literal.value);
        }

        IntegerLiteral* visit(const ast::Literal<int64_t>& literal) {
            VISIT_PREAMBLE(literal, TRACE_VAL);
            return new IntegerLiteral(literal.value);
        }

        FloatLiteral* visit(const ast::Literal<double>& literal) {
            VISIT_PREAMBLE(literal, TRACE_VAL);
            return new FloatLiteral(literal.value);
        }

        StringLiteral* visit(const ast::String& literal) {
            VISIT_PREAMBLE(literal, TRACE_VAL);
            return new StringLiteral(literal.value, literal.raw);
        }

        SizeOf* visit(const ast::SizeOf& size_of) {
            VISIT_PREAMBLE(size_of, TRACE_VAL);
            return new SizeOf(size_of.type);
        }

        Ternary* visit(const ast::TernaryExpr& ternary) {
            VISIT_PREAMBLE(ternary, TRACE_VAL);
            return new Ternary(visit(*ternary.condition), visit(*ternary.true_expr), visit(*ternary.false_expr));
        }

        Index* visit(const ast::IndexExpr& expr) {
            VISIT_PREAMBLE(expr, TRACE_VAL);
            return new Index(visit(*expr.lhs), visit(*expr.rhs));
        }

        MemberRef* visit(const ast::MemberAccess& ref) {
            VISIT_PREAMBLE(ref, TRACE_VAL);
            return new MemberRef(visit(*ref.lhs), ref.name);
        }

        FunctionCall* visit(const ast::FunctionCall& call) {
            VISIT_PREAMBLE(call, TRACE_VAL);
            ExprList args;
            for (const auto& arg : call.arguments) {
                args.push_back(visit(*arg));
            }
            return new FunctionCall(visit(*call.function), std::move(args));
        }

        void visit(const ast::ReturnStatement& ret_stmt) {
            VISIT_PREAMBLE(ret_stmt, TRACE_FUNCTION);
            builder->insert(new Return(visit(*ret_stmt.expr)));
        }

        void visit(const ast::Branch& branch) {
            VISIT_PREAMBLE(branch, TRACE_FUNCTION);
            builder->insert(new If(visit(*branch.condition),
                                   visit(*branch.if_block),
                                       branch.else_block ? visit(*branch.else_block) : nullptr));
        }

        void visit(const ast::While& loop) {
            VISIT_PREAMBLE(loop, TRACE_FUNCTION);
            builder->insert(new While(visit(*loop.condition), visit(*loop.block)));
        }
    };

    ModelBuilder::ModelBuilder(const std::shared_ptr<ast::Module>& ast_module, ModuleKind module_kind)
        : ast(ast_module)
        , module(std::make_shared<Module>(module_kind)) {}

    std::shared_ptr<Module> ModelBuilder::build() {
        SemaParser parser(module);
        parser.visit(*ast);
        return module;
    }
} // namespace pepper::sema
