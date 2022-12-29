
#pragma once

#include <cstdint>

#include "AST/Node.h"

namespace pepper::ast {
    class Literal : public Expression {
        DECLARE_RTTI(Literal, Expression);
    };

    class IntegerLiteral : public Literal {
        DECLARE_RTTI(IntegerLiteral, Literal);

      private:
        const int64_t Value;

      public:
        explicit IntegerLiteral(int64_t value)
            : Value(value) {
        }

        [[nodiscard]] const Name& type() const override {
            static Name Long("long");
            return Long;
        }

        int64_t value() const {
            return Value;
        }

        virtual std::string toString() const override {
            return std::string(llvm::formatv("{0} {1}", Node::toString(), Value));
        }

        virtual std::string dump() const override {
            return toString();
        }
    };

    class FloatLiteral : public Literal {
        DECLARE_RTTI(FloatLiteral, Literal);

      private:
        const double Value;

      public:
        FloatLiteral(double value)
            : Value(value) {
        }

        const Name& type() const override {
            static Name Double("double");
            return Double;
        }

        double value() const {
            return Value;
        }

        virtual std::string toString() const override {
            return std::string(llvm::formatv("{0} {1}", Node::toString(), Value));
        }

        virtual std::string dump() const override {
            return toString();
        }
    };

    class StringLiteral : public Literal {
        DECLARE_RTTI(StringLiteral, Literal);

      private:
        const std::string Value;

      public:
        StringLiteral(const std::string& value)
            : Value(value) {
        }

        const Name& type() const override {
            static Name String("string");
            return String;
        }

        const std::string& value() const {
            return Value;
        }

        virtual std::string toString() const override {
            return std::string(llvm::formatv("{0} {1}", Node::toString(), Value));
        }

        virtual std::string dump() const override {
            return toString();
        }
    };
} // namespace pepper::ast
