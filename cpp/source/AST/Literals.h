
#pragma once

#include "AST/Node.h"
#include <cstdint>

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

        [[nodiscard]] llvm::Type* type() const override;

        int64_t value() const {
            return Value;
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

        llvm::Type* type() const override;

        double value() const {
            return Value;
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

        llvm::Type* type() const override;

        const std::string& value() const {
            return Value;
        }
    };
} // namespace pepper::ast
