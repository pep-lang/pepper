
#pragma once

#include <memory>
#include <variant>

#include "Core/Messages.h"
#include "Core/Tracer.h"
#include "Parser/Lexer.h"
#include "fmt/format.h"
#include "llvm/Support/raw_ostream.h"

namespace pepper::parser {

    template <int Idx>
    void try_visit(auto& variant, auto& visitor) {
        if (variant.index() == Idx) {
            const auto& value = std::get<Idx>(variant);
            value->visit(visitor);
        }
    }

    template <int Idx, typename Tag>
    void try_visit(auto& variant, auto& visitor) {
        if (variant.index() == Idx) {
            visitor.start(Tag{});
            const auto& value = std::get<Idx>(variant);
            value->visit(visitor);
            visitor.end(Tag{});
        }
    }

    struct ExpressionNode;
    struct ExpressionsNode;
    struct IdentifierNode;
    struct LiteralNode;
    struct GenericArgument;
    struct DeclarationNode;
    struct IdNode;

    struct IdentifierNode {
        const Token* identifier;

        IdentifierNode(const Token* ident = nullptr)
            : identifier(ident) {}

        auto to_string() const {
            return identifier->to_string();
        }

        SourcePosition location() const {
            return identifier->location();
        }

        void visit(auto& visitor) {
            visitor.visit(*this);
        }
    };

    // leaf value nodes, variable references, literals, function calls
    struct PrimaryExpressionNode {
        enum {
            empty = 0,
            id,
            expressions,
            declaration,
            literal,
        };

        std::variant<std::monostate,
                     std::unique_ptr<IdNode>,
                     std::unique_ptr<ExpressionsNode>,
                     std::unique_ptr<DeclarationNode>,
                     std::unique_ptr<LiteralNode>>
            expr;

        bool is_expression() const {
            return expr.index() == expressions;
        }

        bool is_id() const {
            return expr.index() == id;
        }

        bool is_declaration() const {
            return expr.index() == declaration;
        }

        bool is_literal() const {
            return expr.index() == literal;
        }

        SourcePosition location() const;

        void visit(auto& visitor);
    };

    struct LiteralNode {
        const Token* literal = nullptr;

        auto token() const {
            return literal;
        }

        SourcePosition location() const {
            return literal->location();
        }

        void visit(auto& visitor) {
            visitor.visit(*this);
        }

        std::string to_string() const {
            return literal->to_string();
        }
    };

    struct PostfixExpressionNode;

    struct PrefixExpressionNode {
        std::vector<const Token*> ops;
        std::unique_ptr<PostfixExpressionNode> expr;

        bool is_id() const;
        bool is_literal() const;
        bool is_expression() const;

        SourcePosition location() const;

        void visit(auto& visitor);
    };

    template <typename Operand, ConstString Name>
    struct BinaryExpressionNode {
        std::unique_ptr<Operand> expr;
        const ExpressionNode* expression;

        struct operand {
            const Token* op;
            std::unique_ptr<Operand> expr;
        };

        std::vector<operand> operands;

        BinaryExpressionNode();

        bool is_id() const {
            return operands.empty() && expr->is_id();
        }

        static std::string_view name() {
            return Name;
        }

        SourcePosition location() const {
            return expr->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            expr->visit(visitor);
            for (const auto& op : operands) {
                assert(op.op);
                assert(op.expr);
                visitor.start(*op.op);
                op.expr->visit(visitor);
            }
            visitor.end(*this);
        }
    };

    struct CastExpressionNode;

    using ProductExpressionNode = BinaryExpressionNode<CastExpressionNode, "product">;
    using SumExpressionNode = BinaryExpressionNode<ProductExpressionNode, "sum">;
    using ShiftExpressionNode = BinaryExpressionNode<SumExpressionNode, "shift">;
    using CompareExpressionNode = BinaryExpressionNode<ShiftExpressionNode, "compare">;
    using RelationExpressionNode = BinaryExpressionNode<CompareExpressionNode, "relation">;
    using EqualityExpressionNode = BinaryExpressionNode<RelationExpressionNode, "equality">;
    using BitAndExpressionNode = BinaryExpressionNode<EqualityExpressionNode, "bit_and">;
    using BitXorExpressionNode = BinaryExpressionNode<BitAndExpressionNode, "bit_xor">;
    using BitOrExpressionNode = BinaryExpressionNode<BitXorExpressionNode, "bit_or">;
    using LogicAndExpressionNode = BinaryExpressionNode<BitOrExpressionNode, "logic_and">;
    using LogicOrExpressionNode = BinaryExpressionNode<LogicAndExpressionNode, "logic_or">;
    using AssignmentExpressionNode = BinaryExpressionNode<LogicOrExpressionNode, "assignment">;

    struct AssignmentExpressionOperands {
        PostfixExpressionNode* lhs;
        LogicOrExpressionNode* rhs;
    };

    struct ExpressionStatementNode;

    struct ExpressionNode {
        static inline std::vector<ExpressionNode*> expressions = {};

        std::unique_ptr<AssignmentExpressionNode> expr;
        const ExpressionStatementNode* statement;
        uint32_t subexpressions = 0;

        ExpressionNode();

        SourcePosition location() const {
            return expr->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            expr->visit(visitor);
            visitor.end(*this);
        }
    };

    struct ExpressionsNode {
        const Token* open = nullptr;
        const Token* close = nullptr;
        bool in_initializer;
        Vector<std::unique_ptr<ExpressionNode>> expressions;

        SourcePosition location() const {
            return open->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            for (const auto& expr : expressions) {
                expr->visit(visitor);
            }
            visitor.end(*this);
        }
    };

    template <typename Operand, ConstString Name>
    BinaryExpressionNode<Operand, Name>::BinaryExpressionNode() {
        if (!ExpressionNode::expressions.empty()) {
            expression = ExpressionNode::expressions.back();
        }
    }

    struct ExpressionStatementNode {
        static inline std::vector<ExpressionStatementNode*> expression_statements = {};

        std::unique_ptr<ExpressionNode> expr;
        bool terminates = false; // has semicolon

        SourcePosition location() const {
            return expr->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            expr->visit(visitor);
            visitor.end(*this);
        }
    };

    struct PostfixExpressionNode {
        std::unique_ptr<PrimaryExpressionNode> expr;

        struct operand {
            const Token* op;

            // lhs if op is .
            std::unique_ptr<IdentifierNode> identifier_expr = {};

            // if op is [ or (, these are the expressions in between op and close
            std::unique_ptr<ExpressionsNode> exprs = {};
            const Token* close = {};
        };

        std::vector<operand> ops;

        bool is_id() const {
            return ops.empty() && expr->is_id();
        }

        bool is_expression() const {
            return ops.empty() && expr->is_expression();
        }

        bool is_literal() const {
            return ops.empty() && expr->is_literal();
        }

        SourcePosition location() const {
            return expr->location();
        }

        void visit(auto& visitor);
    };

    inline bool PrefixExpressionNode::is_id() const {
        return ops.empty() && expr->is_id();
    }

    inline bool PrefixExpressionNode::is_literal() const {
        return ops.empty() && expr->is_literal();
    }

    inline bool PrefixExpressionNode::is_expression() const {
        return ops.empty() && expr->is_expression();
    }

    inline void PrefixExpressionNode::visit(auto& visitor) {
        visitor.start(*this);
        for (const auto& op : ops) {
            visitor.start(*op);
        }
        expr->visit(visitor);
        visitor.end(*this);
    }

    inline SourcePosition PrefixExpressionNode::location() const {
        return expr->location();
    }

    struct IdNode;
    struct ParameterDeclarationNode;

    // specification of generic params when struct/function is declared
    struct GenericParameter {
        std::unique_ptr<ParameterDeclarationNode> param;
    };

    // signifies the start/end of a set of generic parameters
    struct GenericParamsTag {};

    // The name and generic parameters of a function, struct, or extension declaration
    struct TypeDeclNode {
        std::unique_ptr<IdentifierNode> identifier;
        Vector<GenericParameter> generic_params;

        SourcePosition location() const {
            return identifier->location();
        }

        void visit(auto& visitor);

        static TypeDeclNode auto_type() {
            static Token auto_token(Lexeme::Keyword, "__auto", {});
            TypeDeclNode decl;
            decl.identifier = std::make_unique<IdentifierNode>(&auto_token);
            return decl;
        }
    };

    // generic arguments when a generic struct/function is used
    struct GenericArgument {
        std::unique_ptr<IdNode> type;
    };

    // Signifies the start/end of a set of generic arguments
    struct GenericArgsTag {};

    // reference to/use of a type (either struct or function)
    struct IdNode {
        std::vector<const Token*> qualifiers;
        std::unique_ptr<IdentifierNode> identifier;
        Vector<GenericArgument> generic_args;
        // track open/close of <> separately in case support for empty generic lists is desirable, this can
        // be removed if not
        const Token* open_generic = nullptr;
        const Token* close_generic = nullptr;

        const Vector<GenericArgument>& generic_arguments() const {
            return generic_args;
        }

        bool is_pointer() const {
            for (auto qualifier : qualifiers) {
                if (qualifier->type() == Lexeme::Star) {
                    return true;
                }
            }
            return false;
        }

        const Token* token() const {
            return identifier->identifier;
        }

        SourcePosition location() const {
            return identifier->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            visitor.start(*identifier);

            if (open_generic) {
                visitor.start(GenericArgsTag{});
                for (const auto& arg : generic_args) {
                    arg.type->visit(visitor);
                }
                visitor.end(GenericArgsTag{});
            }

            visitor.end(*this);
        }

        static IdNode auto_type() {
            static Token auto_token(Lexeme::Keyword, "__auto", {});
            IdNode id;
            id.identifier = std::make_unique<IdentifierNode>(&auto_token);
            return id;
        }
    };

    // Signifies the start/end of struct members
    struct StructMembersTag {
        struct StructTypeNode* type;
    };

    // Represents the contents of a struct declaration
    struct StructTypeNode {
        DeclarationNode* declaration;
        std::vector<std::unique_ptr<DeclarationNode>> members;

        StructTypeNode(DeclarationNode* decl)
            : declaration(decl) {}

        const Vector<GenericParameter>& generic_parameters() const;
        const Token* name() const;
        SourcePosition location() const;

        void visit(auto& visitor);
    };

    struct ExtensionMembersTag {
        struct ExtensionNode* extension;
    };

    struct ExtensionNode {
        DeclarationNode* declaration;
        std::unique_ptr<IdNode> target;
        std::unique_ptr<IdNode> trait;
        std::vector<std::unique_ptr<DeclarationNode>> members;

        ExtensionNode(DeclarationNode* decl)
            : declaration(decl) {}

        void visit(auto& visitor);

        SourcePosition location() const;
    };

    // Result of a cast, e.g. x as Y
    struct CastExpressionNode {
        std::unique_ptr<PrefixExpressionNode> expr;

        struct operand {
            const Token* op = nullptr;

            // type to cast to
            std::unique_ptr<IdNode> type;
        };

        std::vector<operand> operands;

        bool is_id() const {
            return operands.empty() && expr->is_id();
        }

        bool is_expression() const {
            return operands.empty() && expr->is_expression();
        }

        bool is_literal() const {
            return operands.empty() && expr->is_literal();
        }

        SourcePosition location() const {
            return expr->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            expr->visit(visitor);
            for (auto& operand : operands) {
                visitor.start(*operand.op);
                if (operand.type) {
                    operand.type->visit(visitor);
                }
            }
            visitor.end(*this);
        }
    };

    inline ExpressionNode::ExpressionNode() {
        if (!ExpressionStatementNode::expression_statements.empty()) {
            statement = ExpressionStatementNode::expression_statements.back();
        }
    }

    void PostfixExpressionNode::visit(auto& visitor) {
        visitor.start(*this);
        expr->visit(visitor);
        visitor.end(*this);
    }

    struct StatementNode;

    struct BlockNode {
        const Token* start;
        const Token* end = {};
        std::vector<std::unique_ptr<StatementNode>> statements;

        SourcePosition location() const {
            return start->location();
        }

        void visit(auto& visitor);
    };

    struct BranchNode {
        const Token* keyword = nullptr;
        SourcePosition else_location;
        std::unique_ptr<LogicOrExpressionNode> condition;
        std::unique_ptr<BlockNode> then_block;
        std::unique_ptr<BlockNode> else_block;

        SourcePosition location() const {
            return keyword->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            visitor.start(*keyword);
            condition->visit(visitor);
            then_block->visit(visitor);
            if (else_block) {
                else_block->visit(visitor);
            }
            visitor.end(*this);
        }
    };

    struct LoopNode {
        const Token* keyword = nullptr;
        std::unique_ptr<ParameterDeclarationNode> iterator; // for iterator
        std::unique_ptr<ExpressionNode> next_expr;          // advance for iterator
        std::unique_ptr<LogicOrExpressionNode> condition;   // while condition

        std::unique_ptr<BlockNode> body;

        SourcePosition location() const {
            return keyword->location();
        }

        void visit(auto& visitor);
    };

    struct ReturnStatementNode {
        const Token* keyword = nullptr;
        std::unique_ptr<ExpressionNode> expression;

        SourcePosition location() const {
            return keyword->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            if (expression) {
                expression->visit(visitor);
            }
            visitor.end(*this);
        }
    };

    // break, continue
    struct JumpStatementNode {
        const Token* keyword;
        const Token* label;

        SourcePosition location() const {
            return keyword->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            if (keyword) {
                keyword->visit(visitor);
            }
            if (label) {
                label->visit(visitor);
            }
            visitor.end(*this);
        }
    };

    struct ImportNode {
        const Token* keyword = nullptr;

        enum {
            empty = 0,
            identifier,
            literal,
        };

        std::variant<std::monostate, std::unique_ptr<IdentifierNode>, std::unique_ptr<LiteralNode>> target;

        SourcePosition location() const {
            return keyword->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            try_visit<identifier>(target, visitor);
            try_visit<literal>(target, visitor);
            visitor.end(*this);
        }

        bool is_identifier() const {
            return target.index() == identifier;
        }

        bool is_literal() const {
            return target.index() == literal;
        }

        template <typename Node>
        auto get_if() const {
            auto node = std::get_if<std::unique_ptr<Node>>(&target);
            if (node) {
                return node->get();
            }
            return static_cast<Node*>(nullptr);
        }
    };

    struct StatementNode {
        BlockNode* parent;

        enum {
            expression = 0,
            block,
            branch,
            declaration,
            ret,
            loop,
            jump,
        };

        std::variant<std::unique_ptr<ExpressionStatementNode>,
                     std::unique_ptr<BlockNode>,
                     std::unique_ptr<BranchNode>,
                     std::unique_ptr<DeclarationNode>,
                     std::unique_ptr<ReturnStatementNode>,
                     std::unique_ptr<LoopNode>,
                     std::unique_ptr<JumpStatementNode>>
            statement;

        StatementNode(BlockNode* parent_block = nullptr)
            : parent(parent_block) {}

        bool is_expression() const {
            return statement.index() == expression;
        }

        bool is_block() const {
            return statement.index() == block;
        }

        bool is_branch() const {
            return statement.index() == branch;
        }

        bool is_declaration() const {
            return statement.index() == declaration;
        }

        bool is_return() const {
            return statement.index() == ret;
        }

        bool is_loop() const {
            return statement.index() == loop;
        }

        bool is_jump() const {
            return statement.index() == jump;
        }

        template <typename Node>
        auto get_if() {
            auto node = std::get_if<std::unique_ptr<Node>>(&statement);
            if (node) {
                return node->get();
            }
            return nullptr;
        }

        template <typename Node>
        auto get_if() const {
            auto node = std::get_if<std::unique_ptr<Node>>(&statement);
            if (node) {
                return node->get();
            }
            return static_cast<Node*>(nullptr);
        }

        SourcePosition location() const;
        void visit(auto& visitor);
    };

    void BlockNode::visit(auto& visitor) {
        visitor.start(*this);
        for (auto& statement : statements) {
            statement->visit(visitor);
        }
        visitor.end(*this);
    }

    // Function or Generic parameter declaration
    struct ParameterDeclarationNode {
        SourcePosition loc = {};
        std::unique_ptr<DeclarationNode> declaration;
        size_t index = 0;

        const Token* name() const;

        SourcePosition location() const;
        void visit(auto& visitor);
    };

    struct ParameterDeclarationsNode {
        const Token* open = nullptr;
        const Token* close = nullptr;

        Vector<std::unique_ptr<ParameterDeclarationNode>> parameters;

        auto operator[](const int idx) {
            return parameters[idx].get();
        }

        auto operator[](const int idx) const {
            return parameters[idx].get();
        }

        size_t size() const {
            return parameters.size();
        }

        auto begin() {
            return parameters.begin();
        }

        auto begin() const {
            return parameters.begin();
        }

        auto end() {
            return parameters.end();
        }

        auto end() const {
            return parameters.end();
        }

        SourcePosition location() const {
            return open->location();
        }

        void visit(auto& visitor) {
            visitor.start(*this);
            for (const auto& p : parameters) {
                p->visit(visitor);
            }
            visitor.end(*this);
        }
    };

    void StatementNode::visit(auto& visitor) {
        visitor.start(*this);
        try_visit<expression>(statement, visitor);
        try_visit<block>(statement, visitor);
        try_visit<branch>(statement, visitor);
        try_visit<declaration>(statement, visitor);
        try_visit<ret>(statement, visitor);
        try_visit<loop>(statement, visitor);
        try_visit<jump>(statement, visitor);
        visitor.end(*this);
    }

    struct FunctionParametersTag {};

    struct FunctionReturnTag {};

    // Contents of a function body
    struct FunctionTypeNode {
        DeclarationNode* declaration;
        std::unique_ptr<ParameterDeclarationsNode> parameters;
        std::unique_ptr<BlockNode> body;

        enum {
            empty = 0,
            single,
            multiple,
        };

        std::variant<std::monostate, std::unique_ptr<IdNode>, std::unique_ptr<ParameterDeclarationsNode>> returns;

        explicit FunctionTypeNode(DeclarationNode* decl)
            : declaration(decl) {}

        bool is_method() const;
        bool is_constructor() const;
        bool is_destructor() const;
        bool is_operator() const;

        bool has_explicit_return_type() const {
            return returns.index() != empty;
        }

        bool has_implicit_return_type() const {
            bool has_auto_return =
                (returns.index() == single) && *std::get<single>(returns)->identifier->identifier == "auto";
            return returns.index() == empty || has_auto_return;
        }

        bool has_void_return_type() const {
            if (auto ret = std::get_if<single>(&returns)) {
                return std::string_view(*(*ret)->identifier->identifier) == "void";
            }
            return returns.index() == empty;
        }

        bool has_multi_return_type() const {
            return returns.index() == multiple;
        }

        size_t parameter_count() const {
            return parameters->size();
        }

        SourcePosition location() const;

        void visit(auto& visitor) {
            visitor.start(*this);

            // visitor.start(FunctionReturnTag{});
            // if (returns.index() == single) {
            //     auto& ret = std::get<single>(returns);
            //     ret->visit(visitor);
            // } else if (returns.index() == multiple) {
            //     const auto& rets = std::get<multiple>(returns);
            //     for (auto& ret : *rets) {
            //         visitor.start(*ret);
            //         ret->visit(visitor);
            //         visitor.end(*ret);
            //     }
            // }
            // visitor.end(FunctionReturnTag{});
            //
            // visitor.start(FunctionParametersTag{});
            // for (const auto& param : *parameters) {
            //     param->visit(visitor);
            // }
            // visitor.end(FunctionParametersTag{});

            if (body) {
                body->visit(visitor);
            }

            visitor.end(*this);
        }
    };

    struct DeclarationIdentifierTag {
        IdentifierNode* identifier;
    };

    // signifies a name and a type within the scope denoted by the outer_declaration. If outer_declaration is
    // null, this is a global (module-level) declaration
    struct DeclarationNode {
        std::unique_ptr<IdentifierNode> identifier;
        std::unique_ptr<TypeDeclNode> type_decl;
        SourcePosition loc;
        Vector<const Token*> qualifiers;

        DeclarationNode* outer_declaration;       // the scope of this declaration
        StatementNode* outer_statement = nullptr; // the statement that contains this declaration
        bool is_generic_parameter = false;
        bool is_function_parameter = false;
        bool is_extern = false;
        bool is_pointer = false;
        bool is_terminated = false;
        bool is_this_param = false;

        enum {
            empty,
            variable,
            function,
            structure,
            extension,
        };

        std::variant<std::monostate,
                     std::unique_ptr<IdNode>,
                     std::unique_ptr<FunctionTypeNode>,
                     std::unique_ptr<StructTypeNode>,
                     std::unique_ptr<ExtensionNode>>
            type_info;

        std::unique_ptr<ExpressionNode> initializer; // if this is a variable/parameter with a default value

        explicit DeclarationNode(DeclarationNode* outer_decl)
            : outer_declaration(outer_decl) {}

        bool has_name() const {
            return !!identifier;
        }

        const Token* name() const {
            return identifier ? identifier->identifier : nullptr;
        }

        bool is_variable() const {
            return type_info.index() == variable;
        }

        bool is_function() const {
            return type_info.index() == function;
        }

        bool is_struct() const {
            return type_info.index() == structure;
        }

        bool is_extension() const {
            return type_info.index() == extension;
        }

        bool is_parameter() const {
            return is_function_parameter || is_generic_parameter;
        }

        IdNode* variable_type() const {
            return is_variable() ? std::get<variable>(type_info).get() : nullptr;
        }

        FunctionTypeNode* function_type() const {
            return is_function() ? std::get<function>(type_info).get() : nullptr;
        }

        StructTypeNode* struct_type() const {
            return is_struct() ? std::get<structure>(type_info).get() : nullptr;
        }

        bool is_global() const {
            return outer_declaration == nullptr;
        }

        bool outer_is_function() const {
            return outer_declaration && outer_declaration->is_function();
        }

        bool outer_is_struct() const {
            return outer_declaration && outer_declaration->is_struct();
        }

        DeclarationNode* outer() const {
            return outer_declaration;
        }

        StatementNode* statement() const {
            return outer_statement;
        }

        SourcePosition location() const {
            return loc;
        }

        void visit(auto& visitor) {
            visitor.start(*this);

            // if (type_decl) {
            //     type_decl->visit(visitor);
            // }
            // if (identifier) {
            //     identifier->visit(visitor);
            // }
            //
            // try_visit<variable>(type_info, visitor);
            // try_visit<function>(type_info, visitor);
            // try_visit<structure>(type_info, visitor);
            // try_visit<extension>(type_info, visitor);
            //
            // if (initializer) {
            //     initializer->visit(visitor);
            // }

            visitor.end(*this);
        }
    };

    inline SourcePosition PrimaryExpressionNode::location() const {
        switch (expr.index()) {
            case empty:
                return {};
            case id: {
                const auto& ident = std::get<id>(expr);
                return ident->location();
            }
            case expressions: {
                const auto& e = std::get<expressions>(expr);
                return e->location();
            }
            case declaration: {
                const auto& decl = std::get<declaration>(expr);
                return decl->location();
            }
            case literal: {
                const auto& lit = std::get<literal>(expr);
                return lit->location();
            }
            default:
                assert(!"Impossible PrimaryExpressionNode type");
                return {};
        }
    }

    void PrimaryExpressionNode::visit(auto& visitor) {
        visitor.start(*this);
        try_visit<id>(expr, visitor);
        try_visit<expressions>(expr, visitor);
        try_visit<declaration>(expr, visitor);
        try_visit<literal>(expr, visitor);
        visitor.end(*this);
    }

    inline const Vector<GenericParameter>& StructTypeNode::generic_parameters() const {
        return declaration->type_decl->generic_params;
    }

    inline void StructTypeNode::visit(auto& visitor) {
        visitor.start(*this);

        visitor.start(StructMembersTag{this});
        for (auto& member : members) {
            member->visit(visitor);
        }
        visitor.end(StructMembersTag{this});

        visitor.end(*this);
    }

    inline const Token* StructTypeNode::name() const {
        return declaration->type_decl->identifier->identifier;
    }

    inline SourcePosition StructTypeNode::location() const {
        return declaration->type_decl->location();
    }

    inline void ExtensionNode::visit(auto& visitor) {
        visitor.start(*this);
        if (target) {
            target->visit(visitor);
        }
        if (trait) {
            trait->visit(visitor);
        }
        visitor.start(ExtensionMembersTag{this});
        for (auto& member : members) {
            member->visit(visitor);
        }
        visitor.end(ExtensionMembersTag{this});
        visitor.end(*this);
    }

    inline void TypeDeclNode::visit(auto& visitor) {
        visitor.start(*this);
        identifier->visit(visitor);
        if (!generic_params.empty()) {
            visitor.start(GenericParamsTag{});
            for (auto& arg : generic_params) {
                arg.param->visit(visitor);
            }
            visitor.end(GenericParamsTag{});
        }

        visitor.end(*this);
    }

    inline SourcePosition ExtensionNode::location() const {
        return declaration->location();
    }

    inline const Token* ParameterDeclarationNode::name() const {
        return declaration->name();
    }

    struct IteratorTag {
        ParameterDeclarationNode* iterator;
    };

    struct NextExprTag {
        ExpressionNode* next_expr;
    };

    struct LoopBodyTag {
        BlockNode* block;
    };

    struct ConditionTag {
        LogicOrExpressionNode* condition;
    };

    void LoopNode::visit(auto& visitor) {
        visitor.start(*this);
        if (keyword) {
            keyword->visit(visitor);
        }
        if (iterator) {
            visitor.start(IteratorTag{iterator.get()});
            iterator->visit(visitor);
            visitor.end(IteratorTag{iterator.get()});
        }
        if (next_expr) {
            visitor.start(NextExprTag{next_expr.get()});
            next_expr->visit(visitor);
            visitor.end(NextExprTag{next_expr.get()});
        }
        if (condition) {
            visitor.start(ConditionTag{condition.get()});
            condition->visit(visitor);
            visitor.end(ConditionTag{condition.get()});
        }
        if (body) {
            visitor.start(LoopBodyTag{body.get()});
            body->visit(visitor);
            visitor.end(LoopBodyTag{body.get()});
        }
        visitor.end(*this);
    }

    inline SourcePosition StatementNode::location() const {
        switch (statement.index()) {
            case expression: {
                const auto& expr = std::get<expression>(statement);
                return expr->location();
            }
            case block: {
                const auto& b = std::get<block>(statement);
                return b->location();
            }
            case branch: {
                const auto& b = std::get<branch>(statement);
                return b->location();
            }
            case declaration: {
                const auto& d = std::get<declaration>(statement);
                return d->location();
            }
            case ret: {
                const auto& r = std::get<ret>(statement);
                return r->location();
            }
            case loop: {
                const auto& l = std::get<loop>(statement);
                return l->location();
            }
            case jump: {
                const auto& j = std::get<jump>(statement);
                return j->location();
            }
            default:
                assert(!"Impossible StatementNode type");
                return {};
        }
    }

    inline SourcePosition ParameterDeclarationNode::location() const {
        return loc;
    }

    void ParameterDeclarationNode::visit(auto& visitor) {
        visitor.start(*this);
        declaration->visit(visitor);
        visitor.end(*this);
    }

    inline SourcePosition FunctionTypeNode::location() const {
        return declaration->location();
    }

    struct ModuleNode {
        std::vector<std::unique_ptr<ImportNode>> imports;
        std::vector<std::unique_ptr<DeclarationNode>> declarations;

        SourcePosition location() const {
            if (std::size(declarations) > 0) {
                return declarations.front()->location();
            }
            return {};
        }

        void visit(auto& visitor) const {
            visitor.start(*this);
            for (const auto& import : imports) {
                import->visit(visitor);
            }
            for (const auto& decl : declarations) {
                decl->visit(visitor);
            }
            visitor.end(*this);
        }
    };

    auto visualize(const Token& t, size_t depth) -> std::string;
    // auto visualize(const std::vector<const Token*>& ts, size_t depth) -> std::string;
    auto visualize(const PrimaryExpressionNode& n, size_t depth) -> std::string;
    auto visualize(const LiteralNode& n, size_t depth) -> std::string;
    auto visualize(const IdentifierNode& i, size_t depth) -> std::string;
    auto visualize(const PrefixExpressionNode& e, size_t depth) -> std::string;
    auto visualize(const PostfixExpressionNode& e, size_t depth) -> std::string;
    auto visualize(const ExpressionNode& e, size_t depth) -> std::string;
    auto visualize(const ExpressionsNode& es, size_t depth) -> std::string;
    template <typename Operand, ConstString Name>
    auto visualize(const BinaryExpressionNode<Operand, Name>& b, size_t depth) -> std::string;
    auto visualize(const ExpressionStatementNode& es, size_t depth) -> std::string;
    auto visualize(const IdNode& t, size_t depth) -> std::string;
    auto visualize(const BlockNode& b, size_t depth) -> std::string;
    auto visualize(const StatementNode& s, size_t depth) -> std::string;
    auto visualize(const CastExpressionNode& c, size_t depth) -> std::string;
    auto visualize(const BranchNode& b, size_t depth) -> std::string;
    auto visualize(const LoopNode& l, size_t depth) -> std::string;
    auto visualize(const ReturnStatementNode& r, size_t depth) -> std::string;
    auto visualize(const JumpStatementNode& j, size_t depth) -> std::string;
    auto visualize(const ImportNode& i, size_t depth) -> std::string;
    auto visualize(const ParameterDeclarationNode& p, size_t depth) -> std::string;
    auto visualize(const ParameterDeclarationsNode& ps, size_t depth) -> std::string;
    auto visualize(const FunctionTypeNode& f, size_t depth) -> std::string;
    auto visualize(const TypeDeclNode& type, size_t depth) -> std::string;
    auto visualize(const StructTypeNode& s, size_t depth) -> std::string;
    auto visualize(const DeclarationNode& d, size_t depth) -> std::string;
    auto visualize(const ModuleNode& m, size_t depth) -> std::string;

    class Parser : public ParseState {
      public:
        static std::unique_ptr<Parser> create(const ParseState& state);

      public:
        Parser(const ParseState& state)
            : ParseState(state) {}

        virtual ~Parser() {}

        virtual ModuleNode* tree() const = 0;
        virtual bool parse() = 0;
    };

} // namespace pepper::parser
