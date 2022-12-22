
#pragma once

#include "Compiler/Types.h"
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
        IntegerLiteral(int64_t value)
            : Value(value) {
        }

        llvm::Type* type() override const {
            return *Types::Int64;
        }
    };

    class FloatLiteral : Literal {
        DECLARE_RTTI(FloatLiteral, Literal);

      private:
        const double Value;

      public:
        FloatLiteral(double value)
            : Value(value) {
        }

        llvm::Type* type() override const {
            return *Types::Double;
        }
    };

    class StringLiteral : Literal {
        DECLARE_RTTI(StringLiteral, Literal);

      private:
        const std::string Value;

      public:
        StringLiteral(const std::string& value)
            : Value(value) {
        }

        llvm::Type* type() override const {
            return *Types::Int8->pointer();
        }
    };
} // namespace pepper::ast
