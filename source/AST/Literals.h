
#pragma once

#include <cstdint>

#include "AST/Node.h"

namespace pepper::ast {
    struct Literal : public Expression {
        DECLARE_RTTI(Literal, Expression);
    };

    struct BoolLiteral : public Literal {
        DECLARE_RTTI(BoolLiteral, Literal);

        const bool Value;

        explicit BoolLiteral(bool value)
            : Value(value) {
        }

        const TypeName& type() const override {
            static TypeName Bool("bool");
            return Bool;
        }

        std::string toString() const override {
            return std::string(llvm::formatv("{0} {1}", Node::toString(), Value));
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) + std::to_string(Value);
        }
    };

    struct IntegerLiteral : public Literal {
        DECLARE_RTTI(IntegerLiteral, Literal);

        const int64_t Value;

        explicit IntegerLiteral(int64_t value)
            : Value(value) {
        }

        [[nodiscard]] const TypeName& type() const override {
            static TypeName Long("long");
            return Long;
        }

        std::string toString() const override {
            return std::string(llvm::formatv("{0} {1}", Node::toString(), Value));
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) + std::to_string(Value);
        }
    };

    struct FloatLiteral : public Literal {
        DECLARE_RTTI(FloatLiteral, Literal);

        const double Value;

        FloatLiteral(double value)
            : Value(value) {
        }

        const TypeName& type() const override {
            static TypeName Double("double");
            return Double;
        }

        std::string toString() const override {
            return std::string(llvm::formatv("{0} {1}", Node::toString(), Value));
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) + std::to_string(Value);
        }
    };

    struct StringLiteral : public Literal {
        DECLARE_RTTI(StringLiteral, Literal);

        const std::string Value;

        StringLiteral(const std::string& value)
            : Value(value) {
        }

        const TypeName& type() const override {
            static TypeName String("string");
            return String;
        }

        std::string toString() const override {
            return std::string(llvm::formatv("{0} {1}", Node::toString(), Value));
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) + Value;
        }
    };
} // namespace pepper::ast
