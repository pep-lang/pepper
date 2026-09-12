#pragma once

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Woverloaded-shift-op-parentheses"
#pragma clang diagnostic ignored "-Wunknown-attributes"
#pragma clang diagnostic ignored "-Wcharacter-conversion"

#include <fmt/ranges.h>

#include "Parser.h"
#include "Sema/Model/Functions.h"
#include "Sema/Types.h"
#include "boost/parser/parser.hpp"

namespace pepper::parser {
    class BoostParser {
      public:
        static std::unique_ptr<BoostParser> create(const std::string& source_file, const std::string& source);

      public:
        BoostParser() {}

        virtual ~BoostParser() {}

        virtual ModuleNode* tree() const = 0;
        virtual bool parse() = 0;
    };

    struct ParserContext {};

    struct Identifier {
        std::string name;

        std::strong_ordering operator<=>(const char* other) const { return name <=> other; }
        std::strong_ordering operator<=>(const std::string& other) const { return name <=> other; }
        std::string to_string() const { return name; }
    };

    inline bool operator==(const Identifier& lhs, const std::string& rhs) { return lhs.name == rhs; }
    inline bool operator==(const Identifier& lhs, const char* rhs) { return lhs.name == rhs; }
    //inline bool operator==(const char* lhs, const Identifier& rhs) { return rhs == lhs; }

    inline std::string format_as(const Identifier& identifier) { return identifier.to_string(); }

    struct TypeName {
        Identifier name;
        std::vector<Identifier> generic_params;

        TypeName() = default;
        TypeName(TypeName&&) = default;
        TypeName(const TypeName&) = default;
        TypeName& operator=(const TypeName&) = default;

        TypeName(const Identifier& _name, const std::optional<std::vector<Identifier>>& params)
            : name(_name) {
            if (params) {
                generic_params = *params;
            }
        }

        TypeName(const Identifier& _name, const std::vector<Identifier>& _params={})
            : name(_name)
            , generic_params(_params)
        {}

        std::string to_string() const {
            return generic_params.size() > 0 ? fmt::format("{}<{}>", name, fmt::join(generic_params, ", ")) : name.to_string();
        }
    };

    template <typename>
    struct IsExpression : std::false_type {};

    template <typename T>
    constexpr bool IsExpressionV = IsExpression<std::decay_t<T>>::value;

    template<typename... Types>
    struct TypeList {
        template<typename T>
        static constexpr bool includes() {
            return std::disjunction_v<std::is_same<T, Types>...>;
        }

        template <typename T>
        static constexpr bool contains = includes<T>();
    };

    template <typename TL, typename T>
    constexpr bool Contains = TL::template includes<T>();

    // A type-erased Expression type makes it much more ergonomic and easier to deal with circularly-dependent
    // nodes
    struct Expression {
        Expression() = default;

        Expression(const Expression&) = default;
        Expression(Expression&& other) noexcept
            : expr(std::move(other.expr)) {
        }
        Expression& operator=(const Expression&) = default;

        template <typename E>
        Expression(const E& _expr);

        template <typename E>
            requires (!std::same_as<Expression, std::decay_t<E>>)
        Expression(E&& _expr);

        template <typename E>
        Expression(std::optional<E> _expr) {
            if (_expr) {
                *this = Expression{*_expr};
            }
        }

        // Ban tuple construction so that aggregate construction will be done instead
        // which will prevent a multi-expression structure from being combined into a tuple
        template <typename ...Es>
        Expression(std::tuple<Es...>) = delete;

        template <typename E>
        const E& get() const;

        template <typename E>
        E& get();

        template <typename E>
        const E* try_get() const;

        const std::type_info& type() const {
            return expr.type();
        }

        template <typename E>
        bool is() const;

        bool has_value() const {
            return expr.has_value();
        }

        operator bool() const { return has_value(); }

        std::string type() {
            return expr.type().name();
        }

        std::any expr;
    };

    struct SizeOfExpression {
        TypeName type;
    };

    struct PostfixOpExpression {
        Expression lhs;
        std::string op;
    };

    struct PrefixOpExpression {
        std::string op;
        Expression rhs;
    };

    struct TernaryBranch {
        Expression condition;
        Expression true_result;
        Expression false_result;
    };

    struct IndexExpression {
        Expression indexee;
        Expression index;
    };

    struct MemberAccess {
        Expression target;
        Identifier member;
    };

    struct FunctionCall {
        FunctionCall() = default;
        FunctionCall(const Expression& fn, const std::optional<std::vector<Expression>>& args);

        Expression function_expr;
        std::vector<Expression> arguments;
    };

    template <typename Self, typename ...Types>
    struct Expr {
        using Variant = std::variant<Types...>;

        constexpr Expr() = default;

        explicit Expr(Self&& other)
            : expr(std::move(other.expr)) {
        }
        explicit Expr(const Self& other)
            : expr(other.expr) {
        }

        template <typename T>
            requires std::is_constructible_v<Variant, T&&>
        constexpr Expr(T&& t)
            : expr(std::forward<T>(t)) {
        }

        template <typename T>
        constexpr auto get() {
            return std::get<T>(expr);
        }

        template <typename T>
        constexpr auto get() const {
            return std::get<T>(expr);
        }

        template <typename T>
        constexpr auto try_get() {
            return std::get_if<T>(&expr);
        }

        template <typename T>
        constexpr auto try_get() const {
            return std::get_if<T>(&expr);
        }

        // Aggregate construction of component types
        // template <typename T, typename ...Ts>
        //     requires (sizeof...(Types) > 0) && std::is_constructible_v<std::variant_alternative_t<0, Variant>, T, Ts...>
        // Expr(T&& t, Ts&&... ts) : expr(std::variant_alternative_t<0, Variant>(std::forward<T>(t), std::forward<Ts>(ts)...)) {}
        //
        // template <typename T, typename ...Ts>
        //     requires (sizeof...(Types) > 1) && std::is_constructible_v<std::variant_alternative_t<1, Variant>, T, Ts...>
        // Expr(T&& t, Ts&&... ts) : expr(std::variant_alternative_t<1, Variant>(std::forward<T>(t), std::forward<Ts>(ts)...)) {}
        //
        // template <typename T, typename ...Ts>
        //     requires (sizeof...(Types) > 2) && std::is_constructible_v<std::variant_alternative_t<2, Variant>, T, Ts...>
        // Expr(T&& t, Ts&&... ts) : expr(std::variant_alternative_t<2, Variant>(std::forward<T>(t), std::forward<Ts>(ts)...)) {}
        //
        // template <typename T, typename ...Ts>
        //     requires (sizeof...(Types) > 3) && std::is_constructible_v<std::variant_alternative_t<3, Variant>, T, Ts...>
        // Expr(T&& t, Ts&&... ts) : expr(std::variant_alternative_t<3, Variant>(std::forward<T>(t), std::forward<Ts>(ts)...)) {}
        //
        // template <typename T, typename ...Ts>
        //     requires (sizeof...(Types) > 4) && std::is_constructible_v<std::variant_alternative_t<4, Variant>, T, Ts...>
        // Expr(T&& t, Ts&&... ts) : expr(std::variant_alternative_t<4, Variant>(std::forward<T>(t), std::forward<Ts>(ts)...)) {}
        //
        // template <typename T, typename ...Ts>
        //     requires (sizeof...(Types) > 5) && std::is_constructible_v<std::variant_alternative_t<5, Variant>, T, Ts...>
        // Expr(T&& t, Ts&&... ts) : expr(std::variant_alternative_t<5, Variant>(std::forward<T>(t), std::forward<Ts>(ts)...)) {}
        //
        // template <typename T, typename ...Ts>
        //     requires (sizeof...(Types) > 6) && std::is_constructible_v<std::variant_alternative_t<6, Variant>, T, Ts...>
        // Expr(T&& t, Ts&&... ts) : expr(std::variant_alternative_t<6, Variant>(std::forward<T>(t), std::forward<Ts>(ts)...)) {}
        //
        // template <typename T, typename ...Ts>
        //     requires (sizeof...(Types) > 7) && std::is_constructible_v<std::variant_alternative_t<7, Variant>, T, Ts...>
        // Expr(T&& t, Ts&&... ts) : expr(std::variant_alternative_t<7, Variant>(std::forward<T>(t), std::forward<Ts>(ts)...)) {}
        //
        // template <typename T, typename ...Ts>
        //     requires (sizeof...(Types) > 8) && std::is_constructible_v<std::variant_alternative_t<8, Variant>, T, Ts...>
        // Expr(T&& t, Ts&&... ts) : expr(std::variant_alternative_t<8, Variant>(std::forward<T>(t), std::forward<Ts>(ts)...)) {}
        //
        // template <typename T, typename ...Ts>
        //     requires (sizeof...(Types) > 9) && std::is_constructible_v<std::variant_alternative_t<9, Variant>, T, Ts...>
        // Expr(T&& t, Ts&&... ts) : expr(std::variant_alternative_t<9, Variant>(std::forward<T>(t), std::forward<Ts>(ts)...)) {}
        
        
            
        // Expr(std::variant_alternative_t<0, Variant>&& t)
        //     requires (sizeof...(Types) > 0)
        //     : expr(std::forward<std::variant_alternative_t<0, Variant>>(t)) {}
        //
        // Expr(std::variant_alternative_t<1, Variant>&& t)
        //     requires (sizeof...(Types) > 1)
        //     : expr(std::forward<std::variant_alternative_t<1, Variant>>(t)) {}
        //
        // Expr(std::variant_alternative_t<2, Variant>&& t)
        //     requires (sizeof...(Types) > 2)
        //     : expr(std::forward<std::variant_alternative_t<2, Variant>>(t)) {}
        //
        // Expr(std::variant_alternative_t<3, Variant>&& t)
        //     requires (sizeof...(Types) > 3)
        //     : expr(std::forward<std::variant_alternative_t<3, Variant>>(t)) {}
        //
        // Expr(std::variant_alternative_t<4, Variant>&& t)
        //     requires (sizeof...(Types) > 4)
        //     : expr(std::forward<std::variant_alternative_t<4, Variant>>(t)) {}
        //
        // Expr(std::variant_alternative_t<5, Variant>&& t)
        //     requires (sizeof...(Types) > 5)
        //     : expr(std::forward<std::variant_alternative_t<5, Variant>>(t)) {}
        //
        // Expr(std::variant_alternative_t<6, Variant>&& t)
        //     requires (sizeof...(Types) > 6)
        //     : expr(std::forward<std::variant_alternative_t<6, Variant>>(t)) {}
        //
        // Expr(std::variant_alternative_t<7, Variant>&& t)
        //     requires (sizeof...(Types) > 7)
        //     : expr(std::forward<std::variant_alternative_t<7, Variant>>(t)) {}
        //
        // Expr(std::variant_alternative_t<8, Variant>&& t)
        //     requires (sizeof...(Types) > 8)
        //     : expr(std::forward<std::variant_alternative_t<8, Variant>>(t)) {}
        //
        // Expr(std::variant_alternative_t<9, Variant>&& t)
        //     requires (sizeof...(Types) > 9)
        //     : expr(std::forward<std::variant_alternative_t<9, Variant>>(t)) {}

        // Tuple construction
        // template <typename ...Ts>
        // Expr(std::tuple<Ts...>&& tuple)
        //     requires (sizeof...(Types) > 0) && std::is_constructible_v<std::variant_alternative_t<0, Variant>, Ts...>
        //     : Expr(std::make_from_tuple<std::variant_alternative_t<0, Variant>>(std::move(tuple))) {
        // }
        //
        // template <typename ...Ts>
        // Expr(std::tuple<Ts...>&& tuple)
        //     requires (sizeof...(Types) > 1) && std::is_constructible_v<std::variant_alternative_t<1, Variant>, Ts...>
        //     : Expr(std::make_from_tuple<std::variant_alternative_t<1, Variant>>(std::move(tuple))) {
        // }
        //
        // template <typename ...Ts>
        // Expr(std::tuple<Ts...>&& tuple)
        //     requires (sizeof...(Types) > 2) && std::is_constructible_v<std::variant_alternative_t<2, Variant>, Ts...>
        //     : Expr(std::make_from_tuple<std::variant_alternative_t<2, Variant>>(std::move(tuple))) {
        // }
        //
        // template <typename ...Ts>
        // Expr(std::tuple<Ts...>&& tuple)
        //     requires (sizeof...(Types) > 3) && std::is_constructible_v<std::variant_alternative_t<3, Variant>, Ts...>
        //     : Expr(std::make_from_tuple<std::variant_alternative_t<3, Variant>>(std::move(tuple))) {
        // }
        //
        // template <typename ...Ts>
        // Expr(std::tuple<Ts...>&& tuple)
        //     requires (sizeof...(Types) > 4) && std::is_constructible_v<std::variant_alternative_t<4, Variant>, Ts...>
        //     : Expr(std::make_from_tuple<std::variant_alternative_t<4, Variant>>(std::move(tuple))) {
        // }
        //
        // template <typename ...Ts>
        // Expr(std::tuple<Ts...>&& tuple)
        //     requires (sizeof...(Types) > 5) && std::is_constructible_v<std::variant_alternative_t<5, Variant>, Ts...>
        //     : Expr(std::make_from_tuple<std::variant_alternative_t<5, Variant>>(std::move(tuple))) {
        // }
        //
        // template <typename ...Ts>
        // Expr(std::tuple<Ts...>&& tuple)
        //     requires (sizeof...(Types) > 6) && std::is_constructible_v<std::variant_alternative_t<6, Variant>, Ts...>
        //     : Expr(std::make_from_tuple<std::variant_alternative_t<6, Variant>>(std::move(tuple))) {
        // }
        //
        // template <typename ...Ts>
        // Expr(std::tuple<Ts...>&& tuple)
        //     requires (sizeof...(Types) > 7) && std::is_constructible_v<std::variant_alternative_t<7, Variant>, Ts...>
        //     : Expr(std::make_from_tuple<std::variant_alternative_t<7, Variant>>(std::move(tuple))) {
        // }
        //
        // template <typename ...Ts>
        // Expr(std::tuple<Ts...>&& tuple)
        //     requires (sizeof...(Types) > 8) && std::is_constructible_v<std::variant_alternative_t<8, Variant>, Ts...>
        //     : Expr(std::make_from_tuple<std::variant_alternative_t<8, Variant>>(std::move(tuple))) {
        // }
        //
        // template <typename ...Ts>
        // Expr(std::tuple<Ts...>&& tuple)
        //     requires (sizeof...(Types) > 9) && std::is_constructible_v<std::variant_alternative_t<9, Variant>, Ts...>
        //     : Expr(std::make_from_tuple<std::variant_alternative_t<9, Variant>>(std::move(tuple))) {
        // }

        Variant expr;
    };

    struct Constant : Expr<Constant, int64_t, double, bool, std::string> {
        using Base = Expr;
        using Base::Base;
    };

    struct PrimaryExpression : Expr<PrimaryExpression, Identifier, Constant, Expression> {
        using Base = Expr;
        using Base::Base;
    };
    //using PrimaryExpression = std::variant<Identifier, Constant, Expression>;
    struct PostfixExpression : Expr<PostfixExpression, PrimaryExpression, IndexExpression, FunctionCall, MemberAccess, PostfixOpExpression> {
        using Base = Expr;
        using Base::Base;
    };
    //using PostfixExpression = std::variant<PrimaryExpression, IndexExpression, FunctionCall, MemberAccess, PostfixOpExpression>;
    struct UnaryExpression : Expr<UnaryExpression, PostfixExpression, PrefixOpExpression, SizeOfExpression> {
        using Base = Expr;
        using Base::Base;
    };
    //using UnaryExpression = std::variant<PostfixExpression, PrefixOpExpression, SizeOfExpression>;

    struct BinaryExpression {
        Expression lhs;
        std::string op;
        Expression rhs;
    };

    // template <typename Self, typename T>
    // struct BinaryExpressionOr : Expr<Self, T, BinaryExpression> {
    //     using Base = Expr<Self, T, BinaryExpression>;
    //     using Base::Base;
    //
    //     // Any binary expression container needs to be constructible from an aggregate of{Expression, string, Expression}
    //     BinaryExpressionOr(const Expression& lhs, const std::string& op, const Expression&& rhs)
    //         : Base(BinaryExpression{lhs, op}, rhs) {}
    //     BinaryExpressionOr(Expression&& lhs, std::string&& op, const Expression&& rhs)
    //         : Base(BinaryExpression{std::move(lhs), std::move(op), std::move(rhs)}) {}
    // };

    //using BinaryOpExpression = std::variant<BinaryExpression, UnaryExpression>;

    struct BinaryOpExpression : Expr<BinaryOpExpression, BinaryExpression, UnaryExpression> {
        using Base = Expr;
        using Base::Base;

        template <typename ...Ts>
        BinaryOpExpression(Ts&&... ts)
            : Base(std::forward<Ts>(ts)...) {
        }

        template <typename L, typename R>
        BinaryOpExpression(L lhs, std::tuple<std::string, R>&& rhs)
            : Base(BinaryExpression{std::forward<L>(lhs), std::get<0>(rhs), std::get<1>(rhs)}) {
        }

        BinaryOpExpression(BinaryOpExpression&& lhs, std::tuple<std::string, std::variant<UnaryExpression, BinaryOpExpression>>&& op_rhs)
        {
            auto&& op = std::get<0>(op_rhs);
            if (auto&& rhs_var = std::get<1>(op_rhs); rhs_var.index()) {
                expr = BinaryExpression{std::move(lhs), std::move(op), std::get<1>(rhs_var)};
            } else {
                expr = BinaryExpression{std::move(lhs), std::move(op), std::get<0>(rhs_var)};
            }
        }

        BinaryOpExpression(std::variant<UnaryExpression, BinaryOpExpression>&& var) {
            if (var.index()) {
                expr = std::get<1>(var);
            } else {
                expr = std::get<0>(var);
            }
        }

        BinaryOpExpression(BinaryOpExpression&& lhs, std::tuple<std::string, UnaryExpression>&& op_rhs)
            : Base(BinaryExpression{std::move(lhs), std::get<0>(op_rhs), std::get<1>(op_rhs)}) {}

        BinaryOpExpression(BinaryOpExpression&& lhs, std::tuple<std::string, BinaryOpExpression>&& op_rhs)
            : Base(BinaryExpression{std::move(lhs), std::get<0>(op_rhs), std::get<1>(op_rhs)}) {}

        // template <typename L, typename R>
        // BinaryOpExpression(std::tuple<L, std::tuple<std::string, R>>&& tuple)
        //     : Base(BinaryExpression{std::get<0>(tuple), std::get<0>(std::get<1>(tuple)), std::get<1>(std::get<1>(tuple))}) {}

    };
    //using BinaryOpExpression = std::tuple<Expression, std::string, Expression>;

    // struct AddExpression : BinaryExpressionOr<AddExpression, BinaryOpExpression> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };
    // struct ShiftExpression : BinaryExpressionOr<ShiftExpression, AddExpression> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };
    // struct RelationExpression : BinaryExpressionOr<RelationExpression, ShiftExpression> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };
    // struct EqualityExpression : BinaryExpressionOr<EqualityExpression, RelationExpression> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };
    // struct BitAndExpression : BinaryExpressionOr<BitAndExpression, EqualityExpression> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };
    // struct BitXorExpression : BinaryExpressionOr<BitXorExpression, BitAndExpression> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };
    // struct BitOrExpression : BinaryExpressionOr<BitOrExpression, BitXorExpression> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };
    // struct AndExpression : BinaryExpressionOr<AndExpression, BitOrExpression> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };
    // struct OrExpression : BinaryExpressionOr<OrExpression, AndExpression> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };
    // struct TernaryExpression : BinaryExpressionOr<TernaryExpression, TernaryBranch> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };
    // struct AssignmentExpression : BinaryExpressionOr<AssignmentExpression, TernaryExpression> {
    //     using Base = BinaryExpressionOr;
    //     using Base::Base;
    // };

    //using AssignmentExpression = std::variant<BinaryOpExpression, TernaryBranch>;
    //using AssignmentExpression = std::tuple<UnaryExpression, std::string, Expression>;
    struct AssignmentExpression : Expr<AssignmentExpression, BinaryOpExpression, TernaryBranch> {
        using Base = Expr;
        using Base::Base;

        template <typename L, typename R>
        AssignmentExpression(L&& _lhs, const std::string& _op, R&& _rhs)
            : Expr(BinaryOpExpression{std::forward<L>(_lhs), _op, std::forward<R>(_rhs)}) {}

        // AssignmentExpression(UnaryExpression&& lhs_expr, std::string&& _op, AssignmentExpression&& rhs_expr)
        //     : lhs(std::forward<UnaryExpression>(lhs_expr))
        //     , op(std::forward<std::string>(_op))
        //     , rhs(std::forward<Expr>(rhs_expr)) {
        // }

        UnaryExpression lhs;
        std::string op;
        Expr rhs;
    };

    template <typename T>
        requires TypeList<
            Identifier,
            Constant,
            SizeOfExpression,
            PrimaryExpression,
            PostfixExpression,
            TernaryBranch,
            IndexExpression,
            MemberAccess,
            PrefixOpExpression,
            PostfixOpExpression,
            UnaryExpression,
            BinaryExpression,
            BinaryOpExpression,
            // AddExpression,
            // ShiftExpression,
            // RelationExpression,
            // EqualityExpression,
            // BitAndExpression,
            // BitXorExpression,
            // BitOrExpression,
            // AndExpression,
            // OrExpression,
            // TernaryExpression,
            AssignmentExpression
        >::contains<std::decay_t<T>>
    struct IsExpression<T> : std::true_type {};

    template <typename ...Ts>
    struct IsExpression<Expr<Ts...>> : std::true_type {};

    template <typename ...Ts>
    struct IsExpression<std::variant<Ts...>> : std::bool_constant<std::conjunction_v<IsExpression<Ts> ...>> {};

    inline FunctionCall::FunctionCall(const Expression& fn, const std::optional<std::vector<Expression>>& args)
        : function_expr(fn)
        , arguments(args ? *args : std::vector<Expression>{}) {
    }

    template <typename E>
    Expression::Expression(const E& _expr)
        : expr(_expr) {
        static_assert(IsExpressionV<E>);
    }

    template <typename E>
        requires (!std::same_as<Expression, std::decay_t<E>>)
    Expression::Expression(E&& _expr)
        : expr(std::forward<E>(_expr)) {
        static_assert(IsExpressionV<E>);
    }

    template <typename E>
    const E& Expression::get() const {
        static_assert(IsExpressionV<E>);
        return std::any_cast<const E&>(expr);
    }

    template <typename E>
    E& Expression::get() {
        static_assert(IsExpressionV<E>);
        return std::any_cast<E&>(expr);
    }

    template <typename E>
    const E* Expression::try_get() const {
        static_assert(IsExpressionV<E>);
        return std::any_cast<E>(&expr);
    }

    template <typename E>
    bool Expression::is() const {
        static_assert(IsExpressionV<E>);
        return try_get<E>() != nullptr;
    }

    using Declarator = std::variant<Identifier>;

    struct Initializer {
        std::variant<AssignmentExpression, std::vector<Initializer>> expression;
    };

    struct InitDeclarator {
        std::unique_ptr<Declarator> declarator;
        std::unique_ptr<Initializer> initializer;
    };

    //struct ConstantExpression : TernaryExpression {};

    struct Statement {};

    struct Block {
        std::vector<Statement> statements;
    };

    struct Branch {
        Expression condition;
        Block if_block;
        std::optional<Block> else_block;
    };

    struct While {
        Expression condition;
        Block block;
    };

    struct DoWhile {
        Block block;
        Expression condition;
    };

    struct For {
        Expression init;
        Expression condition;
        Expression step;
        Block block;
    };

    struct ForEach {
        Expression iter;
        Expression range;
        Block block;
    };

    using Loop = std::variant<While, DoWhile, For, ForEach>;

    struct Control {
        std::string verb;
        Expression expression;
    };

    struct ParameterDecl {
        Identifier name;
        TypeName type;
    };

    struct FunctionDecl {
        Identifier name;
        // std::vector<std::string> generic_params;
        std::vector<ParameterDecl> parameters;
        TypeName return_type{Identifier{"void"}};
    };

    struct FunctionDef : FunctionDecl {
        Block body;
    };

    struct ExternTypeName {
        Identifier name;
        bool is_pointer = false;

        // ExternTypeName(const Identifier& _name, const std::string& qualifier={})
        //     : name{_name}
        //     , is_pointer{qualifier == "*"}
        // {}
    };

    struct ExternParameterDecl {
        ExternTypeName type;
        Identifier name;
    };

    struct ExternFunctionDecl {
        TypeName return_type;
        Identifier name;
        std::vector<ExternParameterDecl> parameters;
    };

    using Declaration = std::variant<ExternFunctionDecl, FunctionDecl>;

    using Module  = std::vector<Declaration>;

    std::unique_ptr<Module> parse(std::string_view source);

#define DEFINE_RULE(r) \
    BOOST_PARSER_DEFINE_RULES(r); \
    constexpr auto BOOST_PARSER_PP_CAT(r, _rule) = Rule{r, BOOST_PARSER_PP_CAT(r, _def)};

    namespace rules {
        namespace bp = boost::parser;
        using namespace bp::literals;

        template <typename R, typename Parser>
        struct Rule {
            R& rule;
            Parser& parser;
        };

        // clang-format off
        constexpr bp::rule<class ws> ws = "whitespace";
        constexpr auto ws_def = bp::ws;
        DEFINE_RULE(ws);

        constexpr bp::rule<class semi> semi = "semicolon";
        constexpr auto semi_def = ';'_l;
        DEFINE_RULE(semi);

        constexpr bp::rule<class string_literal, std::string> string_literal = "string";
        constexpr auto string_literal_def = bp::quoted_string;
        DEFINE_RULE(string_literal);

        constexpr bp::rule<class int_literal, int64_t> int_literal = "integer";
        constexpr auto int_literal_def = ("0x" > bp::hex) | ("0" >> bp::oct) | bp::long_long;
        DEFINE_RULE(int_literal);

        const auto to_float = [](const auto& tuple) {
            auto pre = std::get<0>(tuple);
            auto post = std::get<1>(tuple);
            const std::string str = std::to_string(pre) + "." + std::to_string(post);
            return std::strtod(str.data(), nullptr);
        };

        constexpr bp::rule<class float_literal, double> float_literal = "float";
        constexpr auto float_literal_def = bp::transform(to_float)[bp::long_long >> '.' > bp::long_long];
        DEFINE_RULE(float_literal);

        constexpr bp::rule<class bool_literal, bool> bool_literal = "boolean value";
        constexpr auto bool_literal_def = bp::bool_;
        DEFINE_RULE(bool_literal);

        constexpr bp::rule<class constant, Constant> constant = "constant";
        constexpr auto constant_def = float_literal | int_literal | bool_literal | string_literal;
        DEFINE_RULE(constant);

        constexpr bp::rule<class digits, std::string> digits = "digits";
        constexpr auto digits_def = +bp::digit;
        DEFINE_RULE(digits);

        constexpr auto identifier_start
            = bp::char_('A', 'Z')
            | bp::char_('a', 'z')
            | '_'_p;
        constexpr auto identifier_chars
            = identifier_start
            | bp::digit;

        constexpr bp::rule<class identifier, Identifier> identifier = "identifier";
        constexpr auto identifier_def = identifier_start >> *identifier_chars;
        DEFINE_RULE(identifier);

        constexpr bp::rule<class generic_params, std::vector<Identifier>> generic_params = "generic parameters";
        constexpr auto generic_params_def = '<' > (identifier % ',') > '>';
        DEFINE_RULE(generic_params);

        constexpr bp::rule<class type_name, TypeName> type_name = "type name";
        constexpr auto type_name_def
            = identifier >> -generic_params;
        DEFINE_RULE(type_name);

        constexpr bp::rule<class expression> expression = "expression";
        constexpr bp::rule<class argument_exprs> argument_exprs = "function call arguments";
        constexpr bp::rule<class assignment_expr> assignment_expr = "assignment expression";
        constexpr bp::rule<class unary_expr> unary_expr = "unary expression";
        constexpr bp::rule<class postfix_expr> postfix_expr = "postfix expression";
        constexpr bp::rule<class index_expr> index_expr = "index expression";

        constexpr bp::rule<class primary_expr> primary_expr = "primary expression";
        constexpr auto primary_expr_def
            = identifier
            | constant
            | '(' > expression > ')';
        DEFINE_RULE(primary_expr);

        constexpr auto argument_exprs_def
            = assignment_expr % ',';
        DEFINE_RULE(argument_exprs);

        constexpr auto index_expr_def
            = postfix_expr >> '[' > expression > ']';
        DEFINE_RULE(index_expr);

        constexpr bp::rule<class member_access> member_access = "member access";
        constexpr auto member_access_def
            = postfix_expr >> '.' > identifier;
        DEFINE_RULE(member_access);

        constexpr bp::rule<class function_call> function_call = "function call";
        constexpr auto function_call_def
            = postfix_expr >> '(' > -argument_exprs > ')';
        DEFINE_RULE(function_call);

        constexpr bp::rule<class postfix_op> postfix_op = "postfix operator expression";
        constexpr auto postfix_op_def
            = postfix_expr >> "++"_p
            | postfix_expr >> "--"_p;
        DEFINE_RULE(postfix_op);

        constexpr auto postfix_expr_def
            = primary_expr
            | index_expr
            | function_call
            | member_access
            | postfix_op;
        DEFINE_RULE(postfix_expr);

        constexpr bp::rule<class sizeof_expr, SizeOfExpression> sizeof_expr = "sizeof<T>() expression";
        constexpr auto sizeof_expr_def = bp::lit("sizeof") > '<' > type_name > '>' > '(' > ')';
        DEFINE_RULE(sizeof_expr);

        constexpr bp::rule<class unary_operator, std::string> unary_operator = "unary operator";
        constexpr auto unary_operator_def
            = "&"_p
            | "+"_p
            | "-"_p
            | "~"_p
            | "!"_p;
        DEFINE_RULE(unary_operator);

        constexpr bp::rule<class prefix_op> prefix_op = "prefix operator expression";
        constexpr auto prefix_op_def
            = "++"_p > unary_expr
            | "--"_p > unary_expr;
        DEFINE_RULE(prefix_op);

        constexpr auto unary_expr_def
            = postfix_expr
            | prefix_op
            | sizeof_expr;
        DEFINE_RULE(unary_expr);

        // constexpr bp::rule<class mul_expr, MulExpression> mul_expr = "multiply expression";
        // constexpr auto mul_expr_def
        //     = mul_expr >> "*"_p > unary_expr
        //     | mul_expr >> "/"_p > unary_expr
        //     | mul_expr >> "%"_p > unary_expr
        //     | unary_expr;
        // DEFINE_RULE(mul_expr);
        //
        // constexpr bp::rule<class add_expr, AddExpression> add_expr = "addition expression";
        // constexpr auto add_expr_def
        //     = add_expr >> "+"_p > mul_expr
        //     | add_expr >> "-"_p > mul_expr
        //     | mul_expr;
        // DEFINE_RULE(add_expr);
        //
        // constexpr bp::rule<class shift_expr, ShiftExpression> shift_expr = "shift expression";
        // constexpr auto shift_expr_def
        //     = shift_expr >> "<<"_p > add_expr
        //     | shift_expr >> ">>"_p > add_expr
        //     | add_expr;
        // DEFINE_RULE(shift_expr);
        //
        // constexpr bp::rule<class relation_expr, RelationExpression> relation_expr = "relational expression";
        // constexpr auto relation_expr_def
        //     = relation_expr >> "<"_p > shift_expr
        //     | relation_expr >> ">"_p > shift_expr
        //     | relation_expr >> "<="_p > shift_expr
        //     | relation_expr >> ">="_p > shift_expr
        //     | shift_expr;
        // DEFINE_RULE(relation_expr);
        //
        // constexpr bp::rule<class equality_expr, EqualityExpression> equality_expr = "equality expression";
        // constexpr auto equality_expr_def
        //     = equality_expr >> "=="_p > relation_expr
        //     | equality_expr >> "!="_p > relation_expr
        //     | relation_expr;
        // DEFINE_RULE(equality_expr);
        //
        // constexpr bp::rule<class bit_and_expr, BitAndExpression> bit_and_expr = "bitwise and expression";
        // constexpr auto bit_and_expr_def
        //     = bit_and_expr >> "&"_p > equality_expr
        //     | equality_expr;
        // DEFINE_RULE(bit_and_expr);
        //
        // constexpr bp::rule<class bit_xor_expr, BitXorExpression> bit_xor_expr = "bitwise xor expression";
        // constexpr auto bit_xor_expr_def
        //     = bit_xor_expr >> "^"_p > bit_and_expr
        //     | bit_and_expr;
        // DEFINE_RULE(bit_xor_expr);
        //
        // constexpr bp::rule<class bit_or_expr, BitOrExpression> bit_or_expr = "bitwise or expression";
        // constexpr auto bit_or_expr_def
        //     = bit_or_expr >> "|"_p > bit_xor_expr
        //     | bit_xor_expr;
        // DEFINE_RULE(bit_or_expr);
        //
        // constexpr bp::rule<class and_expr, AndExpression> and_expr = "logical and expression";
        // constexpr auto and_expr_def
        //     = and_expr >> "&&"_p > bit_or_expr
        //     | bit_or_expr;
        // DEFINE_RULE(and_expr);
        //
        // constexpr bp::rule<class or_expr, OrExpression> or_expr = "logical or expression";
        // constexpr auto or_expr_def
        //     = or_expr >> "||"_p > and_expr
        //     | and_expr;
        // DEFINE_RULE(or_expr);
        //
        // constexpr bp::rule<class ternary_expr, TernaryExpression> ternary_expr = "ternary expression";
        // constexpr auto ternary_expr_def
        //     = or_expr >> '?' > expression > ':' > ternary_expr
        //     | or_expr;
        // DEFINE_RULE(ternary_expr);
        //
        // constexpr bp::rule<class assignment_operator, std::string> assignment_operator = "assignment operator";
        // constexpr auto assignment_operator_def
        //     = "="_p
        //     | "*="_p
        //     | "/="_p
        //     | "%="_p
        //     | "+="_p
        //     | "-="_p
        //     | "<<="_p
        //     | ">>="_p
        //     | "&="_p
        //     | "^="_p
        //     | "|="_p;
        // DEFINE_RULE(assignment_operator);
        //
        // constexpr auto assignment_expr_def
        //     = unary_expr > assignment_operator > assignment_expr
        //     | ternary_expr;
        // DEFINE_RULE(assignment_expr);

        constexpr bp::rule<class mul_expr/* , BinaryOpExpression */> mul_expr = "multiply expression";
        constexpr auto mul_expr_def
            = mul_expr >> "*"_p > unary_expr
            | mul_expr >> "/"_p > unary_expr
            | mul_expr >> "%"_p > unary_expr;
        DEFINE_RULE(mul_expr);

        constexpr bp::rule<class add_expr/* , BinaryOpExpression */> add_expr = "addition expression";
        constexpr auto add_expr_def
            = add_expr >> "+"_p > mul_expr
            | add_expr >> "-"_p > mul_expr;
        DEFINE_RULE(add_expr);

        constexpr bp::rule<class shift_expr/* , BinaryOpExpression */> shift_expr = "shift expression";
        constexpr auto shift_expr_def
            = shift_expr >> "<<"_p > add_expr
            | shift_expr >> ">>"_p > add_expr;
        DEFINE_RULE(shift_expr);

        constexpr bp::rule<class relation_expr/* , BinaryOpExpression */> relation_expr = "relational expression";
        constexpr auto relation_expr_def
            = relation_expr >> "<"_p > shift_expr
            | relation_expr >> ">"_p > shift_expr
            | relation_expr >> "<="_p > shift_expr
            | relation_expr >> ">="_p > shift_expr;
        DEFINE_RULE(relation_expr);

        constexpr bp::rule<class equality_expr/* , BinaryOpExpression */> equality_expr = "equality expression";
        constexpr auto equality_expr_def
            = equality_expr >> "=="_p > relation_expr
            | equality_expr >> "!="_p > relation_expr;
        DEFINE_RULE(equality_expr);

        constexpr bp::rule<class bit_and_expr/* , BinaryOpExpression */> bit_and_expr = "bitwise and expression";
        constexpr auto bit_and_expr_def
            = bit_and_expr >> "&"_p > equality_expr;
        DEFINE_RULE(bit_and_expr);

        constexpr bp::rule<class bit_xor_expr/* , BinaryOpExpression */> bit_xor_expr = "bitwise xor expression";
        constexpr auto bit_xor_expr_def
            = bit_xor_expr >> "^"_p > bit_and_expr;
        DEFINE_RULE(bit_xor_expr);

        constexpr bp::rule<class bit_or_expr/* , BinaryOpExpression */> bit_or_expr = "bitwise or expression";
        constexpr auto bit_or_expr_def
            = bit_or_expr >> "|"_p > bit_xor_expr;
        DEFINE_RULE(bit_or_expr);

        constexpr bp::rule<class and_expr/* , BinaryOpExpression */> and_expr = "logical and expression";
        constexpr auto and_expr_def
            = and_expr >> "&&"_p > bit_or_expr;
        DEFINE_RULE(and_expr);

        constexpr bp::rule<class or_expr/* , BinaryOpExpression */> or_expr = "logical or expression";
        constexpr auto or_expr_def
            = or_expr >> "||"_p > and_expr;
        DEFINE_RULE(or_expr);

        constexpr bp::rule<class ternary_expr> ternary_expr = "ternary expression";
        constexpr auto ternary_expr_def
            = or_expr >> '?' > expression > ':' > ternary_expr;
        DEFINE_RULE(ternary_expr);

        constexpr bp::rule<class assignment_operator, std::string> assignment_operator = "assignment operator";
        constexpr auto assignment_operator_def
            = "="_p
            | "*="_p
            | "/="_p
            | "%="_p
            | "+="_p
            | "-="_p
            | "<<="_p
            | ">>="_p
            | "&="_p
            | "^="_p
            | "|="_p;
        DEFINE_RULE(assignment_operator);

        constexpr auto assignment_expr_def
            = unary_expr >> assignment_operator > assignment_expr;
        DEFINE_RULE(assignment_expr);

        constexpr bp::rule<struct any_expr> any_expr = "any expression";
        constexpr auto any_expr_def
            = mul_expr
            | add_expr
            | shift_expr
            | relation_expr
            | equality_expr
            | bit_and_expr
            | bit_xor_expr
            | bit_or_expr
            | and_expr
            | or_expr
            | ternary_expr
            | assignment_expr
            | unary_expr;
        DEFINE_RULE(any_expr);

        constexpr auto expression_def = any_expr;
        DEFINE_RULE(expression);

        // constexpr bp::rule<class constant_expr, ConstantExpression> constant_expr = "constant expression";
        // constexpr auto constant_expr_def = ternary_expr;
        // DEFINE_RULE(constant_expr);

        constexpr bp::rule<class type_specifier, TypeName> type_specifier = "type specifier";
        constexpr auto type_specifier_def
            = "void"_p
            | "bool"_p
            | "byte"_p
            | bp::merge[-"u"_p >> "int"_p -digits]
            | bp::merge["float"_p - digits]
            | type_name;
        DEFINE_RULE(type_specifier);

        constexpr bp::rule<class type_qualifier, std::string> type_qualifier = "type qualifier";
        constexpr auto type_qualifier_def = "const"_p;
        DEFINE_RULE(type_qualifier);

        constexpr bp::rule<class declaration_specifiers, std::vector<std::string>> declaration_specifiers = "declaration specifiers";
        constexpr auto declaration_specifiers_def
            = type_specifier >> declaration_specifiers
            | type_specifier
            | type_qualifier >> declaration_specifiers
            | type_qualifier;
        DEFINE_RULE(declaration_specifiers);

        constexpr bp::rule<class declarator, Declarator> declarator = "declarator";
        constexpr auto declarator_def = identifier;
        DEFINE_RULE(declarator);

        constexpr bp::rule<class initializer, Initializer> initializer = "initializer";
        constexpr bp::rule<class initializer_list, std::vector<Initializer>> initializer_list = "initializer_list";
        constexpr auto initializer_list_def
            = initializer_list >> ',' > initializer
            | initializer;
        DEFINE_RULE(initializer_list);

        constexpr auto initializer_def
            = '{' >> initializer_list >> ',' > '}'
            | '{' >> initializer_list > '}'
            | assignment_expr;
        DEFINE_RULE(initializer);

        constexpr bp::rule<class init_declarator, InitDeclarator> init_declarator = "init declarator";
        constexpr auto init_declarator_def
            = declarator >> '=' > initializer
            | declarator;
        DEFINE_RULE(init_declarator);

        constexpr bp::rule<class init_declarators, std::vector<InitDeclarator>> init_declarators = "init_declarators";
        constexpr auto init_declarators_def
            = init_declarators >> ',' > init_declarator
            | init_declarator;
        DEFINE_RULE(init_declarators);

        constexpr bp::rule<class declaration, Declaration> declaration = "declaration";
        constexpr bp::rule<class statement, Statement> statement = "statement";

        // constexpr bp::rule<class declaration_list, std::vector<Declaration>> declaration_list = "declaration list";
        // constexpr auto declaration_list_def
        //     = declaration
        //     | declaration_list > declaration;

        constexpr bp::rule<class block, Block> block = "block";
        constexpr auto block_def
            = '{'_l >> '}'_l
            | '{' >> *statement > '}'
            | '{' >> *declaration > '}'
            | '{' >> *declaration >> *statement > '}';
        DEFINE_RULE(block);

        constexpr bp::rule<class expr_statement, Statement> expr_statement = "expression statement";
        constexpr auto expr_statement_def
            = expression > semi
            | semi;
        DEFINE_RULE(expr_statement);

        constexpr bp::rule<class branch_statement, Branch> branch_statement = "branch statement";
        constexpr auto branch_statement_def
            = "if"_l > '(' > expression > ')' > block >> "else" > block
            | "if"_l > '(' > expression > ')' > block;
        DEFINE_RULE(branch_statement);

        constexpr bp::rule<class loop_statement, Loop> loop_statement = "loop";
        constexpr auto loop_statement_def
            = "while"_l > '(' > expression > ')' > block
            | "do"_l > block > "while" > '(' > expression > ')' > semi
            | "for"_l >> '(' >> -declaration > ';' > -expression > ';' > -expression > ')' > block
            | "for"_l >> '(' >> declaration > ':' > expression > ')' > block;
        DEFINE_RULE(loop_statement);

        constexpr bp::rule<class control_statement, Control> control_statement = "control statement";
        constexpr auto control_statement_def
            = "continue"_p > semi
            | "break"_p > semi
            | "return"_p > -expression > semi;
        DEFINE_RULE(control_statement);

        constexpr auto statement_def
            = block
            | expr_statement
            | loop_statement
            | control_statement;
        DEFINE_RULE(statement);

        constexpr bp::rule<class parameter_decl, ParameterDecl> parameter_decl = "function parameter";
        constexpr auto parameter_decl_def = identifier > ':' > type_name;
        DEFINE_RULE(parameter_decl);

        constexpr bp::rule<class parameter_decls, std::vector<ParameterDecl>> parameter_decls = "parameter list";
        constexpr auto parameter_decls_def = parameter_decl % ',';
        DEFINE_RULE(parameter_decls);

        // TODO: generics
        constexpr bp::rule<class function_decl, FunctionDef> function_decl = "function";
        constexpr auto function_decl_def = identifier > '(' >> parameter_decls > ')' >> ':'_l > type_name > block;
        DEFINE_RULE(function_decl);

        constexpr bp::rule<class extern_type, ExternTypeName> extern_type = "external C type";
        constexpr auto extern_type_def = identifier > -bp::char_('*');
        DEFINE_RULE(extern_type);

        constexpr bp::rule<class extern_parameter_decl, ExternParameterDecl> extern_parameter_decl = "external function parameter declaration";
        constexpr auto extern_parameter_decl_def = extern_type > identifier;
        DEFINE_RULE(extern_parameter_decl);

        // constexpr bp::rule<class extern_parameter_decls, std::vector<ExternParameterDecl>> extern_parameter_decls = "external function parameter declarations";
        // constexpr auto extern_parameter_decls_def = extern_parameter_decl % ',';

        constexpr bp::rule<class extern_decl, ExternFunctionDecl> extern_decl = "external function declaration";
        constexpr auto extern_decl_def = bp::lit("extern") > extern_type > identifier > '(' > -(extern_parameter_decl % ',') > ')';
        DEFINE_RULE(extern_decl);

        // constexpr auto declaration_def
        //     = declaration_specifiers > ';'
        //     | declaration_specifiers >> init_declarator > ';';

        constexpr auto declaration_def
            = extern_decl > ';'
            | function_decl > ';';
        DEFINE_RULE(declaration);

        constexpr bp::rule<class module, Module> module = "module";
        constexpr auto module_def = *declaration;
        DEFINE_RULE(module);
    }

    template <typename ...RuleParams>
    auto parse(const boost::parser::rule<RuleParams...>& rule, std::string_view source, const boost::parser::trace trace = boost::parser::trace::on) {
        namespace bp = boost::parser;
        const auto source_range = bp::detail::text::as_utf8(source);
        return bp::parse(source_range, rule, rules::ws, trace);
    }

    template <typename Rule, typename Parser>
    auto parse(const rules::Rule<Rule, Parser>& rule, std::string_view source, const boost::parser::trace trace = boost::parser::trace::on) {
        namespace bp = boost::parser;
        const auto source_range = bp::detail::text::as_utf8(source);
        using Attr = bp::attribute_t<decltype(source_range), std::decay_t<decltype(rule.parser)>>;
        Attr result;
        bp::parse(source_range, rule.parser, rules::ws, result, trace);
        return result;
    }

    template <typename Result, typename Rule, typename Parser>
    std::optional<Result> parse(const rules::Rule<Rule, Parser>& rule, std::string_view source, const boost::parser::trace trace = boost::parser::trace::on) {
        auto result = parse(rule, source, trace);
        return result ? Result{result} : Result{};
    }
}

#pragma clang diagnostic pop
