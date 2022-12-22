
#pragma once

#include "AST/Node.h"
#include <cstdint>

namespace pepper::ast {
    class Literal : public Expression {
        DECLARE_RTTI(Literal, Expression);
    };

    class IntegerLiteral : Literal {
        DECLARE_RTTI(IntegerLiteral, Literal);

      private:
        const int64_t Value;

      public:
        explicit IntegerLiteral(int64_t value)
            : Value(value) {
        }

        [[nodiscard]] llvm::Type* type() const override;
    };

    class FloatLiteral : Literal {
        DECLARE_RTTI(FloatLiteral, Literal);

      private:
        const double Value;

      public:
        FloatLiteral(double value)
            : Value(value) {
        }

        llvm::Type* type() const override;
    };

    class StringLiteral : Literal {
        DECLARE_RTTI(StringLiteral, Literal);

      private:
        const std::string Value;

      public:
        StringLiteral(const std::string& value)
            : Value(value) {
        }

        llvm::Type* type() const override;
    };
} // namespace pepper::ast
