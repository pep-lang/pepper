
#pragma once

#include <memory>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "Core/Ident.h"
#include "Core/RTTI.h"
#include "Core/SourceLocation.h"
#include "Sema/Model/TypeName.h"
#include "fmt/format.h"
#include "lexy/action/parse.hpp"
#include "lexy/action/trace.hpp"
#include "lexy/callback.hpp"
#include "lexy/dsl.hpp"
#include "lexy/input/base.hpp"
#include "lexy/input/string_input.hpp"
#include "lexy_ext/report_error.hpp"

namespace pepper {
    namespace ast {
        class SourceInput {
          public:
            using encoding = lexy::utf8_encoding;
            using char_type = typename encoding::char_type;

            //=== constructors ===//
            constexpr SourceInput() noexcept
                : _data(nullptr)
                , _size(0u)
                , _shared_reader(nullptr) {}

            constexpr SourceInput(const char_type* data, std::size_t size) noexcept
                : _data(data)
                , _size(size)
                , _shared_reader(std::make_unique<reader_type>(_data, _data + _size)) {}

            constexpr SourceInput(const char_type* begin, const char_type* end) noexcept
                : SourceInput(begin, std::size_t(end - begin)) {}

            template <typename CharT, typename = lexy::_detail::require_secondary_char_type<encoding, CharT>>
            SourceInput(const CharT* data, std::size_t size) noexcept
                : _data(reinterpret_cast<const char_type*>(data))
                , _size(size)
                , _shared_reader(std::make_unique<reader_type>(_data, _data + _size)) {}

            template <typename CharT, typename = lexy::_detail::require_secondary_char_type<encoding, CharT>>
            SourceInput(const CharT* begin, const CharT* end) noexcept
                : SourceInput(begin, std::size_t(end - begin)) {}

            template <typename View, typename CharT = lexy::_string_view_char_type<View>>
            constexpr explicit SourceInput(const View& view) noexcept
                : _size(view.size()) {
                if constexpr (std::is_same_v<CharT, char_type>) {
                    _data = view.data();
                } else {
                    static_assert(encoding::template is_secondary_char_type<CharT>());
                    _data = reinterpret_cast<const char_type*>(view.data());
                }
                _shared_reader = std::make_unique<reader_type>(lexy::_range_reader<encoding>(_data, _data + _size));
            }

            //=== access ===//
            constexpr const char_type* data() const noexcept {
                return _data;
            }

            constexpr std::size_t size() const noexcept {
                return _size;
            }

            //=== reader ===//
            constexpr auto reader() const& noexcept {
                return *_shared_reader;
            }

            constexpr auto shared_reader() const noexcept {
                return _shared_reader.get();
            }

          private:
            const char_type* _data;
            std::size_t _size;

            using reader_type = decltype(lexy::_range_reader<encoding>(_data, _data + _size));
            std::unique_ptr<reader_type> _shared_reader;
        };

        struct ParseContext {
            constexpr ParseContext(std::string_view _name, std::string_view _input)
                : source_name(_name)
                , source_input(_input)
                , source_reader(source_input.shared_reader()) {
                current = this;
            }

            ~ParseContext() {
                current = nullptr;
            }

            constexpr SourceLocation location() const {
                const auto loc = lexy::get_input_location(source_input, source_reader->position());
                return SourceLocation(source_name, loc.line_nr(), loc.column_nr());
            }

            const std::string source_name;
            const SourceInput source_input;
            const lexy::_pr8* source_reader;

            static thread_local const ParseContext* current;
        };

        using Identifier = Ident;
        using TypeName = sema::TypeName;

        inline std::string visualize(const Identifier& id, size_t depth) {
            return id;
        }

        inline std::string visualize(const TypeName& ty, size_t depth) {
            return ty.to_string();
        }

        struct Node {
            DECLARE_RTTI(Node);

            Node()
                : Location(ParseContext::current->location()) {}

            virtual ~Node() = default;

            SourceLocation Location;
        };

        using NodePtr = std::shared_ptr<Node>;

        struct Expr : Node {
            DECLARE_RTTI(Expr, Node);
        };

        using ExprPtr = std::shared_ptr<Expr>;

        std::string visualize(const Expr& expr, size_t depth);

        template <typename VT>
        struct Literal : Expr {
            DECLARE_RTTI(Literal<VT>, Expr);

            explicit Literal(const VT& val)
                : value(val) {}

            const VT value;
        };

        struct String : Expr {
            DECLARE_RTTI(String, Expr);

            String(const std::string& str, bool _raw = false)
                : value(str)
                , raw(_raw) {}

            const std::string value;
            const bool raw = false;
        };

        inline std::string visualize(bool b, size_t) {
            return b ? "true" : "false";
        }

        inline std::string visualize(int64_t i, size_t) {
            return fmt::format("{}", i);
        }

        inline std::string visualize(double d, size_t) {
            return fmt::format("{}", d);
        }

        inline std::string visualize(const std::string& str, size_t) {
            return str;
        }

        template <typename VT>
        std::string visualize(const Literal<VT>& literal, size_t depth) {
            return visualize(literal.value, depth);
        }

        struct SymbolRef : Expr {
            DECLARE_RTTI(SymbolRef, Expr);

            explicit SymbolRef(const Identifier& name)
                : identifier(name) {}

            SymbolRef(Identifier&& name)
                : identifier(std::move(name)) {}

            const Identifier identifier;
        };

        inline std::string visualize(const SymbolRef& ref, size_t depth) {
            return visualize(ref.identifier, 0);
        }

        struct SizeOf : Expr {
            DECLARE_RTTI(SizeOf, Expr);

            SizeOf(const TypeName& ty)
                : type(ty) {}

            TypeName type;
        };

        inline std::string visualize(const SizeOf& s, size_t depth) {
            return fmt::format("sizeof<{}>()", visualize(s.type, 0));
        }

        enum OperatorType {
            Infix,
            Prefix,
            Postfix,
        };

        // TODO: this is not strictly accurate, but it works for now
        constexpr size_t op_len(const char* c) {
            size_t len = 0;
            while (std::ispunct(*c) && *c != ';' && len <= 4) {
                ++c;
                ++len;
            }
            return len;
        }

        struct Operator {
            constexpr Operator(const std::string_view lit)
                : literal(lit) {}

            constexpr Operator(const LEXY_CHAR8_T* it)
                : literal((const char*)it, op_len((const char*)it)) {}

            constexpr Operator(Operator&&) noexcept = default;
            constexpr Operator(const Operator&) = default;

            constexpr operator std::string_view() const {
                return literal;
            }

            constexpr operator std::string() const {
                return std::string{literal};
            }

            const std::string_view literal;
        };

        struct Operators {
            static constexpr Operator Pow{"**"};
            static constexpr Operator Mul{"*"};
            static constexpr Operator Div{"/"};
            static constexpr Operator Mod{"%"};
            static constexpr Operator Add{"+"};
            static constexpr Operator Sub{"-"};
            static constexpr Operator LShift{"<<"};
            static constexpr Operator RShift{">>"};
            static constexpr Operator BitAnd{"&"};
            static constexpr Operator BitXor{"^"};
            static constexpr Operator BitOr{"|"};
            static constexpr Operator BitNot{"~"};
            static constexpr Operator Dot{"."};
            static constexpr Operator Assign{"="};
            static constexpr Operator Equal{"=="};
            static constexpr Operator NotEqual{"!="};
            static constexpr Operator Less{"<"};
            static constexpr Operator Greater{">"};
            static constexpr Operator LessEqual{"<="};
            static constexpr Operator GreaterEqual{">="};
            static constexpr Operator AddAssign{"+="};
            static constexpr Operator SubAssign{"-="};
            static constexpr Operator MulAssign{"*="};
            static constexpr Operator DivAssign{"/="};
            static constexpr Operator ModAssign{"%="};
            static constexpr Operator LShiftAssign{"<<="};
            static constexpr Operator RShiftAssign{">>="};
            static constexpr Operator AndAssign{"&="};
            static constexpr Operator XorAssign{"^="};
            static constexpr Operator OrAssign{"|="};
            static constexpr Operator LogicAnd{"&&"};
            static constexpr Operator LogicOr{"||"};
            static constexpr Operator LogicNot{"!"};
            static constexpr Operator PlusPlus{"++"};
            static constexpr Operator MinusMinus{"--"};
        };

        struct UnaryExpr : Expr {
            DECLARE_RTTI(UnaryExpr, Expr);

            UnaryExpr(const std::string& _op, const ExprPtr& expr)
                : type(Prefix)
                , op(_op)
                , operand(expr) {}

            UnaryExpr(ExprPtr expr, const std::string& _op)
                : type(Postfix)
                , op(_op)
                , operand(expr) {}

            OperatorType type;
            const std::string op;
            ExprPtr operand;
        };

        inline std::string visualize(const UnaryExpr& expr, size_t depth) {
            return fmt::format("{}{}", expr.op, visualize(*expr.operand, depth));
        }

        struct BinaryExpr : Expr {
            DECLARE_RTTI(BinaryExpr, Expr);

            BinaryExpr(const ExprPtr& _lhs, const std::string& _op, const ExprPtr& _rhs)
                : lhs(_lhs)
                , op(_op)
                , rhs(_rhs) {}

            ExprPtr lhs;
            const std::string op;
            ExprPtr rhs;
        };

        inline std::string visualize(const BinaryExpr& expr, size_t depth) {
            return fmt::format("{} {} {}", visualize(*expr.lhs, depth), expr.op, visualize(*expr.rhs, depth));
        }

        struct TernaryExpr : Expr {
            DECLARE_RTTI(TernaryExpr, Expr);

            TernaryExpr(const ExprPtr& cond = nullptr,
                        const ExprPtr& _true_expr = nullptr,
                        const ExprPtr& _false_expr = nullptr)
                : condition(cond)
                , true_expr(_true_expr)
                , false_expr(_false_expr) {}

            ExprPtr condition;
            ExprPtr true_expr;
            ExprPtr false_expr;
        };

        inline std::string visualize(const TernaryExpr& expr, size_t depth) {
            return fmt::format("{} ? {} : {}",
                               visualize(*expr.condition, depth),
                               visualize(*expr.true_expr, 0),
                               visualize(*expr.false_expr, 0));
        }

        struct IndexExpr : Expr {
            DECLARE_RTTI(IndexExpr, Expr);

            IndexExpr(const ExprPtr& _lhs, const ExprPtr& _rhs)
                : lhs(_lhs)
                , rhs(_rhs) {}

            IndexExpr(const ExprPtr& _rhs = nullptr)
                : rhs(_rhs) {}

            ExprPtr lhs;
            ExprPtr rhs;
        };

        inline std::string visualize(const IndexExpr& expr, size_t depth) {
            return fmt::format("{}[{}]", visualize(*expr.lhs, depth), visualize(*expr.rhs, 0));
        }

        struct MemberAccess : Expr {
            DECLARE_RTTI(MemberAccess, Expr);

            MemberAccess(const ExprPtr& _lhs = nullptr, const Identifier& _name = {})
                : lhs(_lhs)
                , name(_name) {}

            ExprPtr lhs;
            Identifier name;
        };

        inline std::string visualize(const MemberAccess& expr, size_t depth) {
            return fmt::format("{}.{}", visualize(*expr.lhs, depth), visualize(expr.name, depth));
        }

        struct FunctionCall : Expr {
            DECLARE_RTTI(FunctionCall, Expr);

            FunctionCall(const ExprPtr& fn = nullptr, const std::vector<ExprPtr>& args = {})
                : function(fn)
                , arguments(args) {}

            ExprPtr function;
            std::vector<ExprPtr> arguments;
        };

        std::string visualize(const FunctionCall& expr, size_t depth);

        struct Import : Node {
            DECLARE_RTTI(Import, Node);

            Import(const std::string& _name,
                   const std::string& _alias = {},
                   const std::unordered_map<std::string, std::string>& map = {},
                   bool local = false)
                : name(_name)
                , alias(_alias)
                , symbol_map(map)
                , is_local(local) {}

            std::string name;
            std::string alias;
            std::unordered_map<std::string, std::string> symbol_map;
            bool is_local = false;
        };

        std::string visualize(const Import& import, size_t depth);

        struct Declaration : Node {
            DECLARE_RTTI(Declaration, Node);
        };

        using DeclPtr = std::shared_ptr<Declaration>;

        std::string visualize(const Declaration& decl, size_t depth);

        struct VariableDecl : Declaration {
            DECLARE_RTTI(VariableDecl, Declaration);

            VariableDecl(const Identifier& _name, const TypeName& _type, ExprPtr _value = nullptr, bool _const = true)
                : name(_name)
                , type(_type)
                , default_value(_value)
                , is_const(_const) {}

            Identifier name;
            TypeName type;
            ExprPtr default_value;
            bool is_const = true;
        };

        std::string visualize(const VariableDecl& decl, size_t depth);

        struct Block : Node {
            DECLARE_RTTI(Block, Node);

            Block(const std::vector<std::shared_ptr<struct Statement>>& statements = {})
                : body(statements) {}

            std::vector<std::shared_ptr<struct Statement>> body;
        };

        std::string visualize(const Block& block, size_t depth);

        struct Branch : Node {
            DECLARE_RTTI(Branch, Node);

            Branch(ExprPtr cond, std::shared_ptr<Block> _if_block, std::shared_ptr<Block> _else_block = nullptr)
                : condition(cond)
                , if_block(_if_block)
                , else_block(_else_block) {}

            ExprPtr condition;
            std::shared_ptr<Block> if_block;
            std::shared_ptr<Block> else_block;
        };

        std::string visualize(const Branch& branch, size_t depth);

        struct While : Node {
            DECLARE_RTTI(While, Node);

            While(const ExprPtr& _condition, std::shared_ptr<Block> _block = nullptr)
                : condition(_condition)
                , block(_block) {}

            ExprPtr condition;
            std::shared_ptr<Block> block;
        };

        std::string visualize(const While& loop, size_t depth);

        struct FunctionDecl : Declaration {
            DECLARE_RTTI(FunctionDecl, Declaration);

            Identifier name;
            TypeName return_type;
            std::vector<VariableDecl> parameters;
            bool lambda = false;
            bool external = false;
            std::shared_ptr<Block> body;
        };

        std::string visualize(const FunctionDecl& decl, size_t depth);

        struct StructDecl : Declaration {
            DECLARE_RTTI(StructDecl, Declaration);

            TypeName name;
            std::vector<VariableDecl> fields;
            std::vector<FunctionDecl> methods;
        };

        std::string visualize(const StructDecl& decl, size_t depth);

        struct ReturnStatement : Node {
            DECLARE_RTTI(ReturnStatement, Node);

            ReturnStatement(const ExprPtr& _expr)
                : expr(_expr) {}

            ExprPtr expr;
        };

        inline std::string visualize(const ReturnStatement& statement, size_t depth) {
            return fmt::format("return {}", visualize(*statement.expr, depth));
        }

        struct Statement : Node {
            DECLARE_RTTI(Statement, Node);

            enum Type {
                Expression,
                Block,
                Declaration,
                Branch,
                Loop,
                Return,
            };

            template <typename T>
            constexpr Statement(const std::shared_ptr<T>& s)
                : statement(s) {}

            constexpr bool is_expression() const {
                return statement.index() == Expression;
            }

            constexpr bool is_block() const {
                return statement.index() == Block;
            }

            constexpr bool is_declaration() const {
                return statement.index() == Declaration;
            }

            constexpr bool is_branch() const {
                return statement.index() == Branch;
            }

            constexpr bool is_loop() const {
                return statement.index() == Loop;
            }

            constexpr bool is_return() const {
                return statement.index() == Return;
            }

            Node* node() const {
                if (auto expr = std::get_if<Expression>(&statement)) {
                    return expr->get();
                }
                if (auto block = std::get_if<Block>(&statement)) {
                    return block->get();
                }
                if (auto decl = std::get_if<Declaration>(&statement)) {
                    return decl->get();
                }
                if (auto branch = std::get_if<Branch>(&statement)) {
                    return branch->get();
                }
                if (auto loop = std::get_if<Loop>(&statement)) {
                    return loop->get();
                }
                return std::get_if<Return>(&statement)->get();
            }

            std::variant<std::shared_ptr<Expr>,
                         std::shared_ptr<struct Block>,
                         std::shared_ptr<struct Declaration>,
                         std::shared_ptr<struct Branch>,
                         std::shared_ptr<While>,
                         std::shared_ptr<ReturnStatement>>
                statement;
        };

        std::string visualize(const Statement& statement, size_t depth);

        struct Module : Node {
            DECLARE_RTTI(Module, Node);

            Module(const std::vector<std::shared_ptr<Import>>& _imports = {},
                   const std::vector<std::shared_ptr<Declaration>>& decls = {})
                : imports(_imports)
                , declarations(decls) {}

            std::vector<std::shared_ptr<Import>> imports;
            std::vector<std::shared_ptr<Declaration>> declarations;
        };

        std::string visualize(const Module& module, size_t depth);
    } // namespace ast

    namespace grammar {
        namespace dsl = lexy::dsl;

        struct Comment {
            static constexpr auto name = "comment";
            static constexpr auto whitespace = dsl::ascii::space | dsl::unicode::space;
            static constexpr auto rule = LEXY_LIT("#") >> dsl::loop(-dsl::ascii::newline | dsl::break_) + dsl::eol;
        };

        constexpr auto escaped_newline = dsl::backslash >> dsl::newline;
        constexpr auto skip_whitespace = dsl::ascii::space | dsl::unicode::space;
        constexpr auto whitespace_and_comments = skip_whitespace | dsl::inline_<Comment>;

        struct Identifier {
            static constexpr auto rule =
                dsl::identifier(dsl::unicode::xid_start_underscore, dsl::unicode::xid_continue);
            static constexpr auto value = lexy::callback<ast::Identifier>([](const lexy::lexeme<lexy::_pr8>& buf) {
                const auto s = std::string{reinterpret_cast<std::string_view::const_pointer>(buf.begin()),
                                           static_cast<size_t>(buf.end() - buf.begin())};
                return ast::Identifier{s};
            });
        };

        using Constant = std::variant<bool, int64_t, double, std::string>;

        struct BoolConstant : lexy::token_production {
            struct True {
                static constexpr auto rule = LEXY_LIT("true");
                static constexpr auto value = lexy::constant(true);
            };

            struct False {
                static constexpr auto rule = LEXY_LIT("false");
                static constexpr auto value = lexy::constant(false);
            };

            static constexpr auto rule = dsl::p<True> | dsl::p<False>;
            static constexpr auto value = lexy::forward<bool>;
        };

        struct NumericConstant {
            struct HexInt : lexy::transparent_production {
                static constexpr auto rule = LEXY_LIT("0x") >> dsl::integer<int64_t, dsl::hex>;
                static constexpr auto value = lexy::as_integer<int64_t>;
            };

            struct Integer : lexy::transparent_production {
                static constexpr auto rule = dsl::p<HexInt> |
                                             dsl::peek(dsl::lit_c<'-'> / dsl::digit<>) >>
                                                 dsl::minus_sign +
                                                     dsl::integer<int64_t>(dsl::digits<>.no_leading_zero()) |
                                             dsl::integer<std::int64_t>(dsl::digits<>.no_leading_zero());
                static constexpr auto value = lexy::as_integer<int64_t>;
            };

            struct Fraction : lexy::transparent_production {
                static constexpr auto rule = dsl::period >> dsl::capture(dsl::digits<>);
                static constexpr auto value = lexy::as_string<std::string>;
            };

            struct PosExponent : lexy::transparent_production {
                static constexpr auto rule = [] {
                    constexpr auto exp_char = dsl::lit_c<'e'> | dsl::lit_c<'E'>;
                    return exp_char >> dsl::plus_sign + dsl::integer<std::uint16_t>;
                }();
                static constexpr auto value = lexy::callback<uint16_t>([](lexy::plus_sign, uint16_t e) { return e; },
                                                                       [](uint16_t e) { return e; });
            };

            struct NegExponent : lexy::transparent_production {
                static constexpr auto rule = [] {
                    constexpr auto exp_char = dsl::lit_c<'e'> | dsl::lit_c<'E'>;
                    return dsl::peek(exp_char + dsl::lit_c<'-'>) >>
                           exp_char + dsl::minus_sign + dsl::integer<std::int16_t>;
                }();
                static constexpr auto value =
                    lexy::callback<int16_t>([](lexy::minus_sign, int16_t e) { return e; }, [](int16_t e) { return e; });
            };

            template <typename T>
            static constexpr T exp(int64_t integer, int16_t exponent) {
                if (exponent >= 0) {
                    return static_cast<int64_t>(integer * pow(10, exponent));
                }
                return static_cast<double>(integer) * std::pow(10.0, exponent);
            }

            static constexpr auto rule =
                dsl::peek(dsl::lit_c<'-'> / dsl::digit<>) >>
                dsl::p<Integer> + dsl::opt(dsl::p<Fraction>) + dsl::opt(dsl::p<NegExponent> | dsl::p<PosExponent>);
            static constexpr auto value = lexy::callback<std::variant<int64_t, double>>(
                [](const int64_t integer,
                   const std::optional<std::string>& fraction,
                   const std::variant<lexy::nullopt, int16_t, uint16_t>& exponent = {})
                    -> std::variant<int64_t, double> {
                    // Plain signed integer
                    if (!fraction && exponent.index() == 0) {
                        return integer;
                    }

                    if (fraction) {
                        // need to account for leading fractional 0s (e.g. 0.0012 parses as integer=0, fraction=0012)
                        const auto frac_str = "0." + *fraction;
                        const auto frac = std::strtod(frac_str.c_str(), nullptr);
                        const double float_abs = static_cast<double>(std::abs(integer)) + frac;
                        return integer >= 0 ? float_abs : float_abs * -1.0;
                    }
                    // positive exponent
                    if (exponent.index() > 1) {
                        return exp<int64_t>(integer, std::get<uint16_t>(exponent));
                    }
                    // negative exponent
                    return exp<double>(integer, -std::get<int16_t>(exponent));
                });
        };

        struct QuotedString : lexy::transparent_production {
            struct invalid_str_char {
                static constexpr auto name = "invalid string character";
            };

            static constexpr auto valid_chars = (-dsl::unicode::control).error<invalid_str_char>;
            static constexpr auto rule = dsl::quoted(valid_chars);
            static constexpr auto value = lexy::as_string<std::string>;
        };

        struct StringConstant {
            static constexpr auto specifiers = lexy::symbol_table<std::string_view>.map<LEXY_SYMBOL("@")>("@");
            static constexpr auto rule = dsl::peek(LEXY_LIT("@") | LEXY_LIT("\"")) >>
                                         dsl::opt(dsl::symbol<specifiers>) + dsl::p<QuotedString>;
            static constexpr auto value = lexy::callback<ast::ExprPtr>(
                [](const std::optional<std::string_view> specifier, const std::string& str) {
                    return std::make_shared<ast::String>(str, !!specifier);
                });
        };

        struct TypeNameList {
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = dsl::peek(dsl::lit_c<'<'>) >>
                                         dsl::angle_bracketed.list(dsl::recurse<struct TypeName>, dsl::sep(dsl::comma));
            static constexpr auto value = lexy::as_list<std::vector<ast::TypeName>>;
        };

        struct TypeName {
            static constexpr auto name = "typename";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule =
                dsl::p<Identifier> + dsl::opt(dsl::peek(dsl::lit_c<'<'>) >> dsl::p<TypeNameList>);
            static constexpr auto value = lexy::callback<ast::TypeName>(
                [](const ast::Identifier& name, lexy::nullopt) { return ast::TypeName{name}; },
                [](const ast::Identifier& name, const std::vector<ast::TypeName>& sub_types) {
                    return ast::TypeName{name, sub_types};
                });
        };

        struct SizeOfExpression {
            static constexpr auto name = "sizeof expression";
            static constexpr auto rule = LEXY_LIT("sizeof") >> dsl::angle_bracketed(dsl::p<TypeName>);
            static constexpr auto value = lexy::new_<ast::SizeOf, ast::ExprPtr>;
        };

        struct PrimaryExpression {
            static constexpr auto rule = dsl::p<BoolConstant> | dsl::p<NumericConstant> | dsl::p<StringConstant> |
                                         dsl::p<Identifier> | dsl::p<SizeOfExpression>;
            static constexpr auto value = lexy::callback<ast::ExprPtr>(
                // These should be forwards, but std::string and Ident are convertible, so the wrong overload is chosen
                [](const ast::Identifier& ident) { return std::make_shared<ast::SymbolRef>(ident); },
                lexy::new_<ast::Literal<bool>, ast::ExprPtr>,
                [](const std::variant<int64_t, double>& v) -> ast::ExprPtr {
                    if (std::holds_alternative<double>(v))
                        return std::make_shared<ast::Literal<double>>(std::get<double>(v));
                    return std::make_shared<ast::Literal<int64_t>>(std::get<int64_t>(v));
                },
                lexy::forward<ast::ExprPtr>);
        };

        struct NestedExpression : lexy::transparent_production {
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = dsl::recurse<struct Expression>;
            static constexpr auto value = lexy::forward<ast::ExprPtr>;
        };

        struct CallArgs {
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = dsl::parenthesized.opt_list(dsl::p<NestedExpression>, dsl::sep(dsl::comma));
            static constexpr auto value = lexy::as_list<std::vector<ast::ExprPtr>>;
        };

        using Operator = ast::Operator;

        struct Expression : lexy::expression_production {
            static constexpr auto whitespace = whitespace_and_comments;

            static constexpr auto atom = [] {
                constexpr auto paren_expr = dsl::parenthesized(dsl::p<NestedExpression>);
                return paren_expr | dsl::p<PrimaryExpression>;
            }();

            struct MemberAccess : dsl::postfix_op {
                static constexpr auto name = "member access";
                static constexpr auto op = dsl::op<ast::MemberAccess>(dsl::period >> dsl::p<Identifier>);
                using operand = dsl::atom;
            };

            struct IndexExpression : dsl::postfix_op {
                static constexpr auto name = "index expression";
                static constexpr auto op = dsl::op<ast::IndexExpr>(dsl::square_bracketed(dsl::p<NestedExpression>));
                using operand = MemberAccess;
            };

            struct PostfixExpression : dsl::postfix_op {
                static constexpr auto name = "postfix expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("++")) / dsl::op<Operator>(LEXY_LIT("--"));

                using operand = IndexExpression;
            };

            struct FunctionCall : dsl::postfix_op {
                static constexpr auto name = "function call";
                static constexpr auto op = dsl::op<ast::FunctionCall>(
                    dsl::parenthesized.opt_list(dsl::p<NestedExpression>, dsl::sep(dsl::comma)));
                using operand = PostfixExpression;
            };

            struct PowExpression : dsl::infix_op_right {
                static constexpr auto name = "pow expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("**"));
                using operand = FunctionCall;
            };

            struct UnaryExpression : dsl::prefix_op {
                static constexpr auto name = "unary expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("+")) / dsl::op<Operator>(LEXY_LIT("-")) /
                                           dsl::op<Operator>(LEXY_LIT("~")) / dsl::op<Operator>(LEXY_LIT("!"));
                using operand = PowExpression;
            };

            struct PrefixExpression : dsl::prefix_op {
                static constexpr auto name = "prefix expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("++")) / dsl::op<Operator>(LEXY_LIT("--"));
                using operand = UnaryExpression;
            };

            struct MulExpression : dsl::infix_op_left {
                static constexpr auto name = "product expression";
                static constexpr auto op
                    // differentiate ** (pow) vs * (mul)
                    = dsl::op<Operator>(dsl::not_followed_by(LEXY_LIT("*"), dsl::lit_c<'*'>)) /
                      dsl::op<Operator>(LEXY_LIT("/")) / dsl::op<Operator>(LEXY_LIT("%"));
                using operand = PrefixExpression;
            };

            struct AddExpression : dsl::infix_op_left {
                static constexpr auto name = "sum expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("+")) / dsl::op<Operator>(LEXY_LIT("-"));
                using operand = MulExpression;
            };

            struct ShiftExpression : dsl::infix_op_left {
                static constexpr auto name = "shift expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("<<")) / dsl::op<Operator>(LEXY_LIT(">>"));
                using operand = AddExpression;
            };

            struct RelationalExpression : dsl::infix_op_left {
                static constexpr auto name = "relational expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("<=")) / dsl::op<Operator>(LEXY_LIT(">=")) /
                                           dsl::op<Operator>(LEXY_LIT("<")) / dsl::op<Operator>(LEXY_LIT(">"));
                using operand = ShiftExpression;
            };

            struct EqualityExpression : dsl::infix_op_left {
                static constexpr auto name = "equality expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("==")) / dsl::op<Operator>(LEXY_LIT("!="));
                using operand = RelationalExpression;
            };

            struct BitAndExpression : dsl::infix_op_left {
                static constexpr auto name = "bitwise and expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("&"));
                using operand = EqualityExpression;
            };

            struct BitOrExpression : dsl::infix_op_left {
                static constexpr auto name = "bitwise xor/or expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("|")) / dsl::op<Operator>(LEXY_LIT("^"));
                using operand = BitAndExpression;
            };

            struct LogicalAndExpression : dsl::infix_op_left {
                static constexpr auto name = "logical and expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("&&")) / dsl::op<Operator>(LEXY_LIT("and"));
                using operand = BitOrExpression;
            };

            struct LogicalOrExpression : dsl::infix_op_left {
                static constexpr auto name = "logical or expression";
                static constexpr auto op = dsl::op<Operator>(LEXY_LIT("||")) / dsl::op<Operator>(LEXY_LIT("or"));
                using operand = LogicalAndExpression;
            };

            struct TernaryExpression : dsl::infix_op_single {
                static constexpr auto name = "ternary expression";
                static constexpr auto op =
                    dsl::op<ast::TernaryExpr>(LEXY_LIT("?") >> dsl::p<NestedExpression> + LEXY_LIT(":"));
                using operand = LogicalOrExpression;
            };

            struct AssignmentExpression : dsl::infix_op_single {
                static constexpr auto name = "assignment expression";
                static constexpr auto op = dsl::op<Operator>(dsl::not_followed_by(LEXY_LIT("="), dsl::lit_c<'='>)) /
                                           dsl::op<Operator>(LEXY_LIT("*=")) / dsl::op<Operator>(LEXY_LIT("/=")) /
                                           dsl::op<Operator>(LEXY_LIT("%=")) / dsl::op<Operator>(LEXY_LIT("+=")) /
                                           dsl::op<Operator>(LEXY_LIT("-=")) / dsl::op<Operator>(LEXY_LIT("<<=")) /
                                           dsl::op<Operator>(LEXY_LIT(">>=")) / dsl::op<Operator>(LEXY_LIT("&=")) /
                                           dsl::op<Operator>(LEXY_LIT("^=")) / dsl::op<Operator>(LEXY_LIT("|="));
                using operand = TernaryExpression;
            };

            using operation = AssignmentExpression;

            static inline const auto value =
                // Fold function call arguments into a vector
                lexy::fold_inplace<std::vector<ast::ExprPtr>>(
                    std::vector<ast::ExprPtr>{},
                    [](std::vector<ast::ExprPtr>& args, ast::ExprPtr arg) { args.push_back(arg); })
                // Callbacks for converting the various expression values into nodes
                >>
                lexy::callback<ast::ExprPtr>(
                    lexy::forward<ast::ExprPtr>, // atoms
                    [](ast::ExprPtr lhs, const ast::IndexExpr&, ast::ExprPtr rhs) {
                        return std::make_shared<ast::IndexExpr>(lhs, rhs);
                    },
                    [](ast::ExprPtr lhs, const ast::MemberAccess&, ast::Identifier&& name) {
                        return std::make_shared<ast::MemberAccess>(lhs, std::move(name));
                    },
                    [](ast::ExprPtr fn,
                       const ast::FunctionCall&,
                       const std::optional<std::vector<ast::ExprPtr>>& args) {
                        return std::make_shared<ast::FunctionCall>(fn, args ? *args : std::vector<ast::ExprPtr>{});
                    },
                    [](ast::ExprPtr expr, const std::string& op) { return std::make_shared<ast::UnaryExpr>(expr, op); },
                    [](const std::string& op, ast::ExprPtr expr) { return std::make_shared<ast::UnaryExpr>(op, expr); },
                    [](ast::ExprPtr lhs, const std::string& op, ast::ExprPtr rhs) {
                        return std::make_shared<ast::BinaryExpr>(lhs, op, rhs);
                    },
                    [](ast::ExprPtr condition,
                       const ast::TernaryExpr&,
                       ast::ExprPtr true_expr,
                       ast::ExprPtr false_expr) {
                        return std::make_shared<ast::TernaryExpr>(condition, true_expr, false_expr);
                    });
        };

        struct Import {
            static constexpr auto name = "import statement";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = LEXY_LIT("import") + (dsl::p<QuotedString> | dsl::p<Identifier>)+dsl::if_(
                                                                  LEXY_LIT("as") >> dsl::p<Identifier>);
            static constexpr auto value = lexy::callback<std::shared_ptr<ast::Import>>(
                [](const std::string& name) {
                    auto import = std::make_shared<ast::Import>(name);
                    import->is_local = true;
                    return import;
                },
                [](const ast::Identifier& name) {
                    auto import = std::make_shared<ast::Import>(name);
                    import->is_local = false;
                    return import;
                },
                [](const std::string& name, const ast::Identifier& alias) {
                    auto import = std::make_shared<ast::Import>(name, alias);
                    import->is_local = true;
                    return import;
                },
                [](const ast::Identifier& name, const ast::Identifier& alias) {
                    auto import = std::make_shared<ast::Import>(name, alias);
                    import->is_local = false;
                    return import;
                });
        };

        struct VariableSpecifier {
            static constexpr auto name = "variable specifier";
            // clang-format: off
            static constexpr auto specifiers =
                lexy::symbol_table<std::string_view>
                    .map<LEXY_SYMBOL("const")>("const") // const
                    .map<LEXY_SYMBOL("var")>("var");
            // clang-format: on
            static constexpr auto rule = dsl::symbol<specifiers>(dsl::identifier(dsl::ascii::lower));
            static constexpr auto value =
                lexy::callback<std::string>([](std::string_view specifier) { return std::string{specifier}; });
        };

        struct VariableType {
            static constexpr auto name = "variable type";
            static constexpr auto rule = dsl::colon >> dsl::p<TypeName>;
            static constexpr auto value = lexy::forward<ast::TypeName>;
        };

        struct VariableDeclaration {
            static constexpr auto name = "variable declaration";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = dsl::opt(dsl::p<VariableSpecifier>) + dsl::p<Identifier> +
                                         dsl::opt(dsl::p<VariableType>) +
                                         dsl::opt(LEXY_LIT("=") >> dsl::p<NestedExpression>);
            static constexpr auto value =
                lexy::callback<std::shared_ptr<ast::VariableDecl>>([](const std::optional<std::string>& spec,
                                                                      const ast::Identifier& name,
                                                                      const std::optional<ast::TypeName>& type,
                                                                      ast::ExprPtr expr = nullptr) {
                    const ast::Identifier var_name = spec == "this" ? "this" : name;
                    return std::make_shared<ast::VariableDecl>(
                        var_name, type.has_value() ? *type : ast::TypeName::Auto, expr, spec && *spec == "const");
                });
        };

        struct GenericParameters {
            static constexpr auto name = "generic parameters";
            static constexpr auto whitespace = whitespace_and_comments;
            // TODO: add constraints here
            static constexpr auto rule = dsl::angle_bracketed.list(dsl::p<TypeName>, dsl::sep(dsl::comma));
            static constexpr auto value = lexy::as_list<std::vector<ast::TypeName>>;
        };

        struct FunctionParameters {
            static constexpr auto name = "function parameters";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = dsl::parenthesized.opt_list(dsl::p<VariableDeclaration>, dsl::sep(dsl::comma));
            static constexpr auto value = lexy::as_list<std::vector<std::shared_ptr<ast::VariableDecl>>>;
        };

        struct ReturnStatement {
            static constexpr auto name = "return statement";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = LEXY_LIT("return") + dsl::p<Expression>;
            static constexpr auto value = lexy::new_<ast::ReturnStatement, std::shared_ptr<ast::ReturnStatement>>;
        };

        struct Branch {
            static constexpr auto name = "branch";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = LEXY_LIT("if") + dsl::p<Expression> + dsl::recurse<struct Block> +
                                         dsl::opt(LEXY_LIT("else") >> dsl::recurse<struct Block>);
            static constexpr auto value = lexy::callback<std::shared_ptr<ast::Branch>>(
                [](const ast::ExprPtr& condition,
                   const std::shared_ptr<ast::Block>& if_block,
                   const std::optional<std::shared_ptr<ast::Block>>& else_block) {
                    return std::make_shared<ast::Branch>(condition, if_block, else_block.value_or(nullptr));
                });
        };

        struct While {
            static constexpr auto name = "while loop";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = LEXY_LIT("while") + dsl::p<Expression> + dsl::recurse<struct Block>;
            static constexpr auto value = lexy::callback<std::shared_ptr<ast::While>>(
                [](const ast::ExprPtr& condition, const std::shared_ptr<ast::Block>& block) {
                    return std::make_shared<ast::While>(condition, block);
                });
        };

        // struct For {
        //     static constexpr auto name = "for loop";
        //     static constexpr auto whitespace = ws_and_comments;
        //     static constexpr auto rule = LEXY_LIT("for") + dsl::p<Expression> +
        // };

        struct Statement {
            static constexpr auto name = "statement";
            static constexpr auto rule
                // naked block
                = dsl::peek(dsl::lit_c<'{'>) >> dsl::recurse<struct Block>
                  // variable declaration
                  | dsl::peek(dsl::p<VariableSpecifier>) >> dsl::p<VariableDeclaration>
                  // branch
                  | dsl::peek(LEXY_LIT("if")) >> dsl::p<Branch>
                  // loops
                  | dsl::peek(LEXY_LIT("while")) >> dsl::p<While>
                  // return
                  | dsl::peek(LEXY_LIT("return")) >> dsl::p<ReturnStatement>
                  // otherwise, must be an expression of some sort
                  | dsl::else_ >> dsl::p<Expression>;
            static constexpr auto value = lexy::callback<std::shared_ptr<ast::Statement>>(
                [](const ast::ExprPtr& expr) { return std::make_shared<ast::Statement>(expr); },
                [](const std::shared_ptr<ast::Block>& block) { return std::make_shared<ast::Statement>(block); },
                [](const std::shared_ptr<ast::Declaration>& decl) { return std::make_shared<ast::Statement>(decl); },
                [](const std::shared_ptr<ast::Branch>& branch) { return std::make_shared<ast::Statement>(branch); },
                [](const std::shared_ptr<ast::While>& loop) { return std::make_shared<ast::Statement>(loop); },
                [](const std::shared_ptr<ast::ReturnStatement>& ret) { return std::make_shared<ast::Statement>(ret); });
        };

        struct Statements {
            static constexpr auto name = "statements";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule =
                dsl::curly_bracketed.opt_list(dsl::p<Statement>, dsl::trailing_sep(dsl::semicolon));
            static constexpr auto value = lexy::as_list<std::vector<std::shared_ptr<ast::Statement>>>;
        };

        struct Block {
            static constexpr auto name = "block";
            static constexpr auto rule = dsl::p<Statements>;
            static constexpr auto value = lexy::callback<std::shared_ptr<ast::Block>>(
                [](const std::vector<std::shared_ptr<ast::Statement>>& statements) {
                    return std::make_shared<ast::Block>(statements);
                });
        };

        struct ExternTypeName {
            static constexpr auto name = "external type name";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto pointer_symbols =
                lexy::symbol_table<std::string_view>.map<LEXY_SYMBOL("**")>("**").map<LEXY_SYMBOL("*")>("*");
            static constexpr auto rule = dsl::p<TypeName> + dsl::opt(dsl::symbol<pointer_symbols>(LEXY_LIT("*")));
            static constexpr auto value = lexy::callback<ast::TypeName>(
                [](const ast::TypeName& type, const std::optional<std::string_view> decorators) {
                    return decorators ? ast::TypeName{type.name + std::string{*decorators}} : type;
                });
        };

        struct ExternFunctionParameter {
            static constexpr auto name = "external function parameter";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = dsl::p<ExternTypeName> + dsl::p<Identifier>;
            static constexpr auto value = lexy::callback<std::shared_ptr<ast::VariableDecl>>(
                [](const ast::TypeName& type, const ast::Identifier& name) {
                    return std::make_shared<ast::VariableDecl>(name, type);
                });
        };

        struct ExternFunctionParameters {
            static constexpr auto name = "external function parameters";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = dsl::parenthesized.list(dsl::p<ExternFunctionParameter>, dsl::sep(dsl::comma));
            static constexpr auto value = lexy::as_list<std::vector<std::shared_ptr<ast::VariableDecl>>>;
        };

        struct ExternFunctionDeclaration {
            static constexpr auto name = "extern function declaration";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = LEXY_LIT("extern") + dsl::p<ExternTypeName> + dsl::p<Identifier> +
                                         dsl::p<ExternFunctionParameters> + dsl::semicolon;
            static constexpr auto value = lexy::callback<std::shared_ptr<ast::FunctionDecl>>(
                [](const ast::TypeName& return_type,
                   const std::string& name,
                   const std::vector<std::shared_ptr<ast::VariableDecl>>& params) {
                    auto func = std::make_shared<ast::FunctionDecl>();
                    func->name = name;
                    func->external = true;
                    for (const auto& param : params) {
                        func->parameters.push_back(*param);
                    }
                    func->return_type = return_type;
                    return func;
                });
        };

        struct FunctionDeclaration {
            static constexpr auto name = "function declaration";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule =
                dsl::p<Identifier> + dsl::opt(dsl::peek(dsl::lit_c<'<'>) >> dsl::p<GenericParameters>) +
                dsl::p<FunctionParameters> + dsl::opt(LEXY_LIT(":") >> dsl::p<TypeName>) + dsl::p<Block>;

            static constexpr auto value = lexy::callback<std::shared_ptr<ast::FunctionDecl>>(
                [](const ast::Identifier& name,
                   const std::optional<std::vector<ast::TypeName>>& generic_params,
                   const std::vector<std::shared_ptr<ast::VariableDecl>>& params,
                   const std::optional<ast::TypeName>& return_type,
                   const std::shared_ptr<ast::Block> body) {
                    auto func = std::make_shared<ast::FunctionDecl>();
                    func->name = name;
                    if (generic_params.has_value()) {
                        // TODO
                    }
                    for (const auto& param : params) {
                        func->parameters.push_back(*param);
                    }
                    if (return_type.has_value()) {
                        func->return_type = return_type.value();
                    }
                    func->body = body;
                    return func;
                });
        };

        struct MemberDeclarations {
            static constexpr auto name = "member declarations";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule =
                dsl::curly_bracketed.opt_list(dsl::peek(dsl::p<VariableSpecifier>) >> dsl::p<VariableDeclaration> |
                                                  dsl::peek(dsl::p<Identifier>) >> dsl::p<FunctionDeclaration>,
                                              dsl::trailing_sep(dsl::semicolon));
            static constexpr auto value = lexy::as_list<std::vector<ast::DeclPtr>>;
        };

        struct StructDeclaration {
            static constexpr auto name = "struct declaration";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule = LEXY_LIT("struct") + dsl::p<Identifier> +
                                         dsl::opt(dsl::peek(dsl::lit_c<'<'>) >> dsl::p<GenericParameters>) +
                                         dsl::p<MemberDeclarations>;
            static constexpr auto value = lexy::callback<std::shared_ptr<ast::StructDecl>>(
                [](const ast::Identifier& name,
                   const std::optional<std::vector<ast::TypeName>>& generic_params,
                   const std::optional<std::vector<ast::DeclPtr>>& members) {
                    const auto st = std::make_shared<ast::StructDecl>();
                    st->name = name;
                    if (members) {
                        for (const auto& member : *members) {
                            if (member->is<ast::VariableDecl>()) {
                                st->fields.push_back(*std::static_pointer_cast<ast::VariableDecl>(member));
                            } else {
                                st->methods.push_back(*std::static_pointer_cast<ast::FunctionDecl>(member));
                            }
                        }
                    }
                    return st;
                });
        };

        struct Declaration {
            static constexpr auto name = "declaration";
            static constexpr auto rule = dsl::peek(LEXY_LIT("struct")) >> dsl::p<StructDeclaration> |
                                         dsl::peek(LEXY_LIT("extern")) >> dsl::p<ExternFunctionDeclaration> |
                                         dsl::else_ >> dsl::p<FunctionDeclaration>;
            static constexpr auto value = lexy::forward<ast::DeclPtr>;
        };

        struct Imports {
            static constexpr auto name = "import declarations";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule =
                dsl::opt(dsl::list(dsl::peek(LEXY_LIT("import")) >> dsl::p<Import>, dsl::trailing_sep(dsl::semicolon)));
            static constexpr auto value = lexy::as_list<std::vector<std::shared_ptr<ast::Import>>>;
        };

        struct Declarations {
            static constexpr auto name = "module declarations";
            static constexpr auto whitespace = whitespace_and_comments;
            static constexpr auto rule =
                dsl::opt(dsl::list(dsl::peek(LEXY_LIT("struct") | dsl::p<Identifier>) >> dsl::p<Declaration>));
            static constexpr auto value = lexy::as_list<std::vector<std::shared_ptr<ast::Declaration>>>;
        };

        struct Module {
            static constexpr auto name = "module";
            static constexpr auto rule = dsl::p<Imports> + dsl::p<Declarations>;
            static constexpr auto value = lexy::callback<std::shared_ptr<ast::Module>>(
                [](const std::vector<std::shared_ptr<ast::Import>>& imports, const std::vector<ast::DeclPtr>& decls) {
                    return std::make_shared<ast::Module>(imports, decls);
                });
        };

        template <typename T = Module>
        auto parse(std::string_view source_name, std::string_view source) {
            const auto context = ast::ParseContext(source_name, source);

            const auto trace_input{lexy::string_input<lexy::utf8_encoding>{source}};
            lexy::trace<T>(stdout, trace_input, {lexy::visualize_fancy});
            std::fflush(stdout);

            const auto parse_input = ast::SourceInput{source};
            return lexy::parse<T>(context.source_input, lexy_ext::report_error);
        }
    } // namespace grammar
} // namespace pepper

namespace pepper::parser {
    class LexyParser {
      public:
        static std::unique_ptr<LexyParser> create(const std::string& source_file, const std::string& source);

      public:
        LexyParser() {}

        virtual ~LexyParser() {}

        virtual class std::shared_ptr<ast::Module> tree() const = 0;
        virtual bool parse() = 0;
    };
} // namespace pepper::parser
