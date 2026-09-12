
#include "Parser/BoostParser.h"
#include "TestUtils.h"
#include "gtest/gtest.h"
#include "llvm/Object/Binary.h"

using namespace TestUtils;
using namespace pepper;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Woverloaded-shift-op-parentheses"
#pragma clang diagnostic ignored "-Wunknown-attributes"
#pragma clang diagnostic ignored "-Wcharacter-conversion"

TEST(Parser, Boolean) {
    const auto t = parser::parse(parser::rules::bool_literal, "true");
    ASSERT_TRUE(t);
    EXPECT_TRUE(*t);

    const auto f = parser::parse(parser::rules::bool_literal, "false");
    ASSERT_TRUE(f);
    EXPECT_FALSE(*f);

    const auto fail = parser::parse(parser::rules::bool_literal, "TRUE");
    EXPECT_FALSE(fail);
}

TEST(Parser, String) {
    const auto s = parser::parse(parser::rules::string_literal, "\"string\"");
    EXPECT_EQ(s, "string");
}

TEST(Parser, IntLiteral) {
    const auto zero = parser::parse(parser::rules::int_literal, "0");
    EXPECT_EQ(zero, 0);

    const auto pos = parser::parse(parser::rules::int_literal, "42");
    EXPECT_EQ(pos, 42);

    const auto neg = parser::parse(parser::rules::int_literal, "-42");
    EXPECT_EQ(neg, -42);

    const auto hex = parser::parse(parser::rules::int_literal, "0xff");
    EXPECT_EQ(hex, 0xff);

    const auto oct = parser::parse(parser::rules::int_literal, "0755");
    EXPECT_EQ(oct, 0755);
}

TEST(Parser, FloatLiteral) {
    const auto pi = parser::parse(parser::rules::float_literal, "3.14");
    EXPECT_EQ(pi, 3.14);

    const auto neg_pi = parser::parse(parser::rules::float_literal, "-3.14");
    EXPECT_EQ(neg_pi, -3.14);
}

TEST(Parser, Constants) {
    const auto pi = parser::parse(parser::rules::constant, "3.14");
    ASSERT_TRUE(pi);
    const auto pi_val = *pi;
    EXPECT_EQ(3.14, pi_val.get<double>());

    const auto x = parser::parse(parser::rules::constant, "42");
    ASSERT_TRUE(x);
    const auto x_val = *x;
    std::variant<int64_t, double, bool, std::string> y;
    const auto y2 = std::get<int64_t>(y);
    const auto x2 = std::get<int64_t>(x_val.expr);
    const auto x_v = x_val.get<int64_t>();
    EXPECT_EQ(42, x_val.get<int64_t>());
}

TEST(Parser, Identifier) {
    const auto test = parser::parse(parser::rules::identifier, "test");
    ASSERT_TRUE(test);
}

TEST(Parser, TypeName) {
    //static_assert(std::is_aggregate_v<parser::TypeName>, "TypeName must be an aggregate");
    const auto params = parser::parse(parser::rules::generic_params, "<T, U>");
    ASSERT_TRUE(params);
    EXPECT_EQ(2, params->size());
    EXPECT_EQ("T", params->at(0).name);
    EXPECT_EQ("U", params->at(1).name);

    const auto test = parser::parse(parser::rules::type_name, "test");
    ASSERT_TRUE(test);
    EXPECT_EQ("test", test->name);
    EXPECT_EQ(0, test->generic_params.size());

    const auto test_t = parser::parse(parser::rules::type_name, "test<T>");
    ASSERT_TRUE(test_t);
    EXPECT_EQ("test", test_t->name.name);
    ASSERT_EQ(1, test_t->generic_params.size());
    EXPECT_EQ("T", test_t->generic_params[0].name);

    const auto test_tu = parser::parse(parser::rules::type_name, "test<T, U>");
    ASSERT_TRUE(test_tu);
    EXPECT_EQ("test", test_tu->name.name);
    ASSERT_EQ(2, test_tu->generic_params.size());
    EXPECT_EQ("T", test_tu->generic_params[0].name);
    EXPECT_EQ("U", test_tu->generic_params[1].name);
}

TEST(Parser, Expressions) {
    namespace bp = boost::parser;
    using namespace bp::literals;
    using namespace parser;

    const auto constant = parser::parse(rules::constant, "42");
    ASSERT_TRUE(constant);

    const auto primary = parser::parse<PrimaryExpression>(rules::primary_expr_rule, "test");
    using PT = bp::attribute_t<std::string_view, decltype(rules::primary_expr_def)>;
    ASSERT_TRUE(primary);
    // const auto index = parser::parse<IndexExpression>(rules::index_expr_rule, "test[42]");
    // ASSERT_TRUE(index);
    const auto test = parser::parse(rules::expression, "test");
    ASSERT_TRUE(test);
    // const auto& test_expr = *test;
    // ASSERT_TRUE(test_expr.is<parser::BinaryExpression>());
    // const auto& expr = test_expr.get<parser::BinaryExpression>();
    // ASSERT_TRUE(expr.lhs);
}

namespace test {
    namespace bp = boost::parser;
    using namespace bp::literals;
    using namespace parser;

    struct C {
        std::variant<std::string, int64_t> a;
        std::variant<std::string, int64_t> b;
    };

    constexpr bp::rule<struct a, std::string> a = "A";
    constexpr auto a_def = "test"_p;
    BOOST_PARSER_DEFINE_RULES(a);
    constexpr bp::rule<struct b, int64_t> b = "B";
    constexpr auto b_def = bp::long_long;
    BOOST_PARSER_DEFINE_RULES(b);
    constexpr bp::rule<struct scratch, C> scratch = "scratch test";
    constexpr auto scratch_def = a > b;
    BOOST_PARSER_DEFINE_RULES(scratch);

    constexpr bp::rule<struct lhs> lhs = "lhs";
    constexpr bp::rule<struct rhs> rhs = "rhs";
    constexpr auto lhs_def
        = rules::identifier
        | rules::constant;
    constexpr auto rhs_def
        = rules::identifier
        | rules::constant;
    constexpr bp::rule<struct math_op> math_op = "math op";
    constexpr auto math_op_def
        = lhs >> "*"_p > rhs
        | lhs;
    BOOST_PARSER_DEFINE_RULES(lhs, rhs, math_op);

    using mul_t = bp::attribute_t<std::string_view, decltype(rules::mul_expr)>;
}

TEST(Parser, Scratch) {
    using namespace parser;

    static_assert(IsExpressionV<Identifier>);
    static_assert(IsExpressionV<std::variant<Identifier>>);
    static_assert(IsExpressionV<Constant>);
    static_assert(IsExpressionV<std::variant<Identifier, Constant>>);


    // const auto test = parser::parse(test::scratch, "test 42");
    // ASSERT_TRUE(test);
    // EXPECT_EQ("test", std::get<std::string>(test->a));
    // EXPECT_EQ(42, std::get<int64_t>(test->b));

    auto a = Expression{std::move(AssignmentExpression{})};
    auto c = test::C{std::string{"test"}, 42};
    PostfixExpression x = PostfixExpression{PostfixOpExpression{PrimaryExpression{Identifier{"test"}}, "++"}};
    //PostfixExpression y = std::move(MulExpression{UnaryExpression{PrefixOpExpression{"++", PrimaryExpression{Identifier{"test"}}}}});
    //FunctionCall fc = {PostfixExpression{{AssignmentExpression{}}}, {}};
    //UnaryExpression ue = std::move(SizeOfExpression{});
    // EqualityExpression e = EqualityExpression{};
    // EqualityExpression eq = {EqualityExpression{}};
    // EqualityExpression eqm = std::move(EqualityExpression{});
    // EqualityExpression eqe = std::move(e);

    constexpr bool aex = IsExpressionV<AssignmentExpression>;

    using Test = std::variant<PostfixExpression, PrefixOpExpression, SizeOfExpression>;
    UnaryExpression ue0;
    PrefixOpExpression poe1{"+", ue0};
    PostfixExpression pfe1;
    UnaryExpression ue1 = PrefixOpExpression{"+", poe1};
    UnaryExpression ue2 = UnaryExpression{ue1};
    //BinaryOpExpression boe1 = AssignmentExpression{UnaryExpression{}, "=", BinaryOpExpression{}};
    //AssignmentExpression ae{std::make_tuple(UnaryExpression{}, "=", AssignmentExpression{std::move(ue1), "=", std::move(boe1)})};

    PostfixExpression pfe2 = pfe1;

    std::variant<PostfixExpression, PrefixOpExpression, SizeOfExpression> uev = PrefixOpExpression{std::string{"+"}, ue0};
    PrefixOpExpression poe2 = poe1;
    SizeOfExpression soe1;
    SizeOfExpression soe2 = soe1;
    TypeName tn1;
    TypeName tn2 = tn1;
    Test t1;
    Test t2 = t1;

    BinaryOpExpression me1;
    BinaryOpExpression me2 = me1;
    BinaryExpression be = {me1, "+", ue2};
    BinaryOpExpression mea = ue2;
    // using T1 = std::variant_alternative_t<0, BinaryOpExpression::Variant>;
    // using T2 = std::variant_alternative_t<1, BinaryOpExpression::Variant>;
    //using T3 = std::variant_alternative_t<2, BinaryOpExpression::Variant>;
    UnaryExpression boe = std::make_from_tuple<PrefixOpExpression>(std::make_tuple("+", ue2));
    mea = be;
    BinaryOpExpression mea2 = UnaryExpression{PostfixExpression{PrimaryExpression{Constant{42}}}};
    BinaryOpExpression mea3 = PrefixOpExpression{"++", PrimaryExpression{Identifier{"test"}}};

    auto mul = parse(test::math_op, "12 * 20");
    ASSERT_TRUE(mul);
    auto mul2 = parse(test::math_op, "12");
    ASSERT_TRUE(mul2);
}

#pragma clang diagnostic pop
