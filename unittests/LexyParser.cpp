
#include "Parser/LexyParser.h"

#include "TestUtils.h"
#include "gtest/gtest.h"
#include "lexy/action/parse.hpp"
#include "lexy/action/parse_as_tree.hpp"
#include "lexy/action/trace.hpp"
#include "lexy/input/string_input.hpp"
#include "lexy_ext/report_error.hpp"

using namespace TestUtils;
using namespace pepper;

template <typename R, typename Err>
void verify(const lexy::parse_result<R, Err>& result) {
    ASSERT_TRUE(result.is_success());
    ASSERT_TRUE(result.has_value());
}

template <typename T, typename R, typename Err>
const T* extract(const lexy::parse_result<R, Err>& result) {
    verify(result);
    const std::shared_ptr<ast::Node> node = result.value();
    if constexpr (std::is_same_v<R, std::shared_ptr<ast::Statement>>) {
        if (node->is<ast::Statement>()) {
            const auto inner = node->as<ast::Statement>()->node();
            EXPECT_TRUE(inner->is<T>());
            return inner->as<T>();
        }
    }
    EXPECT_TRUE(node->is<T>());
    return node->as<T>();
}

TEST(LexyParser, Constants) {
    {
        const auto result = grammar::parse<grammar::NumericConstant>(this->test_info_->name(), "42");
        verify(result);
        const auto value = std::get<int64_t>(result.value());
        EXPECT_EQ(42, value);
    }
    {
        const auto result = grammar::parse<grammar::NumericConstant>(this->test_info_->name(), "3.14");
        verify(result);
        EXPECT_EQ(3.14, std::get<double>(result.value()));
    }
    {
        const auto result = grammar::parse<grammar::NumericConstant>(this->test_info_->name(), "-3.14");
        verify(result);
        EXPECT_EQ(-3.14, std::get<double>(result.value()));
    }
    {
        const auto result = grammar::parse<grammar::NumericConstant>(this->test_info_->name(), "3.042");
        verify(result);
        EXPECT_EQ(3.042, std::get<double>(result.value()));
    }
    {
        const auto result = grammar::parse<grammar::NumericConstant>(this->test_info_->name(), "-3.0014");
        verify(result);
        EXPECT_EQ(-3.0014, std::get<double>(result.value()));
    }
    {
        const auto result = grammar::parse<grammar::NumericConstant>(this->test_info_->name(), "5E5");
        verify(result);
        const int64_t expected = 5 * std::pow(10, 5);
        EXPECT_EQ(expected, std::get<int64_t>(result.value()));
    }
    {
        const auto result = grammar::parse<grammar::NumericConstant>(this->test_info_->name(), "3E-2");
        verify(result);
        const double expected = 3 * std::pow(10, -2);
        EXPECT_EQ(expected, std::get<double>(result.value()));
    }
    {
        const auto result = grammar::parse<grammar::PrimaryExpression>(this->test_info_->name(), R"("test")");
        verify(result);
        const auto constant = result.value();
        ASSERT_TRUE(constant->is<ast::Literal<std::string>>());
        const auto str = constant->as<ast::Literal<std::string>>();
        EXPECT_EQ("test", str->value);
    }
}

TEST(LexyParser, Comments) {
    {
        const auto result = grammar::parse<grammar::Module>(this->test_info_->name(), R"(
            # test
        )");
    }
}

TEST(LexyParser, Identifier) {
    const auto result = grammar::parse<grammar::Identifier>(this->test_info_->name(), "test");
    ASSERT_TRUE(result.is_success());
    ASSERT_TRUE(result.has_value());
    EXPECT_EQ("test", result.value());
}

TEST(LexyParser, TypeName) {
    {
        const auto result = grammar::parse<grammar::TypeName>(this->test_info_->name(), "test");
        verify(result);
        const auto t = result.value();
        EXPECT_EQ("test", t.name);
        EXPECT_EQ(0, t.sub_types.size());
    }
    {
        const auto result = grammar::parse<grammar::TypeName>(this->test_info_->name(), "test<int>");
        verify(result);
        const auto t = result.value();
        EXPECT_EQ("test", t.name);
        ASSERT_EQ(1, t.sub_types.size());
        EXPECT_EQ("int", t.sub_types[0].name);
    }
}

TEST(LexyParser, Expressions) {
    {
        const auto result = grammar::parse<grammar::PrimaryExpression>(this->test_info_->name(), "test");
        const auto expr = result.value();
        EXPECT_TRUE(expr->is<ast::SymbolRef>());
        const auto ref = extract<ast::SymbolRef>(result);
        EXPECT_EQ("test", ref->identifier);
    }
    {
        const auto result = grammar::parse<grammar::Statement>(this->test_info_->name(), "test = 42;");
        EXPECT_TRUE(extract<ast::BinaryExpr>(result));
    }
    {
        const auto result = grammar::parse<grammar::Statement>(this->test_info_->name(), "test = 1 + 2;");
        const auto expr = extract<ast::BinaryExpr>(result);
        EXPECT_EQ("=", expr->op);
        const auto rhs = expr->rhs;
        ASSERT_TRUE(rhs->is<ast::BinaryExpr>());
        const auto add = rhs->as<ast::BinaryExpr>();
        EXPECT_EQ("+", add->op);
    }
    {
        const auto result = grammar::parse<grammar::Statement>(this->test_info_->name(), "test();");
        const auto call = extract<ast::FunctionCall>(result);
        ASSERT_TRUE(call->function->is<ast::SymbolRef>());
        EXPECT_EQ("test", call->function->as<ast::SymbolRef>()->identifier);
    }
    {
        const auto result = grammar::parse<grammar::Expression>(this->test_info_->name(), "test(4, 2)");
        const auto call = extract<ast::FunctionCall>(result);
        ASSERT_TRUE(call->function->is<ast::SymbolRef>());
        EXPECT_EQ("test", call->function->as<ast::SymbolRef>()->identifier);
        ASSERT_EQ(2, call->arguments.size());
        ASSERT_TRUE(call->arguments[0]->is<ast::Literal<int64_t>>());
        ASSERT_TRUE(call->arguments[1]->is<ast::Literal<int64_t>>());
        EXPECT_EQ(4, call->arguments[0]->as<ast::Literal<int64_t>>()->value);
        EXPECT_EQ(2, call->arguments[1]->as<ast::Literal<int64_t>>()->value);
    }
}

TEST(LexyParser, Imports) {
    {
        const auto result = grammar::parse<grammar::Import>(this->test_info_->name(), R"(import "test";)");
        const auto import = extract<ast::Import>(result);
        EXPECT_EQ("test", import->name);
        EXPECT_TRUE(import->is_local);
    }
    {
        const auto result = grammar::parse<grammar::Import>(this->test_info_->name(), R"(import test);)");
        const auto import = extract<ast::Import>(result);
        EXPECT_EQ("test", import->name);
        EXPECT_FALSE(import->is_local);
    }
    {
        const auto result = grammar::parse<grammar::Import>(this->test_info_->name(), R"(import "test" as t;)");
        const auto import = extract<ast::Import>(result);
        EXPECT_EQ("test", import->name);
        EXPECT_EQ("t", import->alias);
        EXPECT_TRUE(import->is_local);
    }
    {
        const auto result = grammar::parse<grammar::Import>(this->test_info_->name(), R"(import test as t;)");
        const auto import = extract<ast::Import>(result);
        EXPECT_EQ("test", import->name);
        EXPECT_EQ("t", import->alias);
        EXPECT_FALSE(import->is_local);
    }
}

TEST(LexyParser, VariableDeclarations) {
    {
        const auto result = grammar::parse<grammar::VariableDeclaration>(this->test_info_->name(), R"(var test: int;)");
        const auto decl = extract<ast::VariableDecl>(result);
        EXPECT_EQ("test", decl->name);
        EXPECT_EQ("int", decl->type);
    }
    {
        const auto result =
            grammar::parse<grammar::VariableDeclaration>(this->test_info_->name(), R"(const test = 42;)");
        const auto decl = extract<ast::VariableDecl>(result);
        EXPECT_EQ("test", decl->name);
        EXPECT_EQ(ast::TypeName::Auto, decl->type);
    }
}

TEST(LexyParser, Structs) {
    {
        const auto result = grammar::parse<grammar::StructDeclaration>(this->test_info_->name(), R"(struct test {})");
        const auto decl = extract<ast::StructDecl>(result);
        EXPECT_EQ("test", decl->name.name);
    }
    {
        const auto source = R"(struct test {
            var integer = 0;
        })";
        const auto result = grammar::parse<grammar::StructDeclaration>(this->test_info_->name(), source);
        const auto decl = extract<ast::StructDecl>(result);
        EXPECT_EQ("test", decl->name);
        ASSERT_EQ(1, decl->fields.size());
        const auto field = decl->fields[0];
        EXPECT_EQ("integer", field.name);
        EXPECT_EQ(ast::TypeName::Auto, field.type);
    }
}

TEST(LexyParser, Functions) {
    {
        const auto result = grammar::parse<grammar::FunctionDeclaration>(this->test_info_->name(), R"(test() {})");
        const auto func = extract<ast::FunctionDecl>(result);
        EXPECT_EQ("test", func->name);
    }
    {
        const auto result = grammar::parse<grammar::FunctionDeclaration>(this->test_info_->name(), R"(test(): int {
            return 12;
        })");
    }
}

TEST(LexyParser, ParseTree) {
    const std::string_view source = R"(
        import test as t;

        struct Foo {
            var a = 12;
            const b = 9;
        }
    )";
    const auto trace_input{lexy::string_input<lexy::utf8_encoding>{source}};
    lexy::trace<grammar::Module>(stdout, trace_input, {lexy::visualize_fancy});
    std::fflush(stdout);
    auto result = grammar::parse<>(this->test_info_->name(), source);
}
