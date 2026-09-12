
#include "LexyParser.h"
#include <lexy/action/parse.hpp>
#include <lexy/input/string_input.hpp>
#include <lexy_ext/report_error.hpp>

namespace pepper::ast {
    thread_local const ParseContext* ParseContext::current{nullptr};

    template <int Idx>
    std::string try_visualize(auto& v, auto&&... args) {
        if (v.index() == Idx) {
            const auto& value = std::get<Idx>(v);
            return visualize(*value, std::forward<decltype(args)...>(args)...);
        }
        return "";
    }

    template <typename V>
    auto visualize_list(const auto& list, V vis) {
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

    std::string visualize(const VariableDecl& decl, size_t depth) {
        const auto value = decl.default_value ? fmt::format(" = {}", visualize(*decl.default_value, 0)) : "";
        return fmt::format("{}: {}{}", visualize(decl.name, depth), visualize(decl.type, 0), value);
    }

    std::string visualize(const FunctionCall& expr, size_t depth) {
        return fmt::format("{}({})",
                           visualize(*expr.function, depth),
                           visualize_list(expr.arguments, [](const auto& arg) { return visualize(*arg, 0); }));
    }

    std::string visualize(const Import& import, size_t depth) {
        if (import.is_local)
            return fmt::format("import \"{}\"{}", import.name, import.alias.empty() ? "" : " as " + import.alias);
        return fmt::format("import {}", import.name, import.alias.empty() ? "" : " as " + import.alias);
    }

    std::string visualize(const Expr& expr, size_t depth) {
        return {};
    }

    std::string visualize(const Declaration& decl, size_t depth) {
        return {};
    }

    std::string visualize(const Block& block, size_t depth) {
        std::string ret = "{\n";
        for (const auto& stmt : block.body) {
            ret += visualize(*stmt, depth + 1) + "\n";
        }
        ret += "}";
        return ret;
    }

    std::string visualize(const Branch& branch, size_t depth) {
        return fmt::format("if {} {}{}",
                           visualize(*branch.condition, depth),
                           visualize(*branch.if_block, depth + 1),
                           branch.else_block ? "else " + visualize(*branch.else_block, depth + 1) : "");
    }

    std::string visualize(const While& loop, size_t depth) {
        return fmt::format("while {} {}", visualize(*loop.condition, depth), visualize(*loop.block, depth + 1));
    }

    std::string visualize(const FunctionDecl& decl, size_t depth) {
        return fmt::format("{}({}) : {} {}",
                           visualize(decl.name, depth),
                           visualize_list(decl.parameters, [](const auto& p) { return visualize(p, 0); }),
                           visualize(decl.return_type, 0),
                           visualize(*decl.body, 0));
    }

    std::string visualize(const StructDecl& decl, size_t depth) {
        std::string fields;
        for (const auto& field : decl.fields) {
            fields += fmt::format("{}: {}{}\n",
                                  visualize(field.name, depth + 1),
                                  visualize(field.type, 0),
                                  field.default_value ? " = " + visualize(*field.default_value, 0) : "");
        }
        std::string methods;
        for (const auto& method : decl.methods) {
            methods += visualize(method, depth + 1) + "\n";
        }
        return fmt::format("struct {} {{\n{}\n}}", visualize(decl.name, depth), fields, methods);
    }

    std::string visualize(const Statement& statement, size_t depth) {
        return {};
    }

    std::string visualize(const Module& module, size_t depth) {
        return {};
    }
} // namespace pepper::ast

namespace pepper::parser {

    class LexyParserImpl: public LexyParser {
        std::shared_ptr<ast::Module> module;
        const std::string source_file;
        const std::string source;
    public:
        LexyParserImpl(const std::string& _source_file, const std::string& _source)
            : source_file(_source_file), source(_source) {}

        std::shared_ptr<ast::Module> tree() const override {
            return module;
        }

        bool parse() override {
            module = parse_module();
            return !!module;
        }

        std::shared_ptr<ast::Module> parse_module() const {
            const auto result = grammar::parse(source_file, source);
            if (result.has_value()) {
                return result.value();
            }
            return nullptr;
        }
    };

    std::unique_ptr<LexyParser> LexyParser::create(const std::string& source_file, const std::string& source) {
        return std::make_unique<LexyParserImpl>(source_file, source);
    }

}
