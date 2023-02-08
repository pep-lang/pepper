
#pragma once

#include <cstdint>

#include "AST/Node.h"

namespace pepper::ast {
    struct Literal : public Expression {
        DECLARE_RTTI(Literal, Expression);
    };

    struct BoolLiteral : public Literal {
        DECLARE_RTTI(BoolLiteral, Literal);
        AST_NODE_POD_CLONE(BoolLiteral);

        const bool Value;

        explicit BoolLiteral(bool value)
            : Value(value) {}

        const TypeName& type() const override {
            static TypeName Bool("bool");
            return Bool;
        }

        std::string toString() const override {
            return std::string(llvm::formatv("{0}: {1}", nodeName(), Value));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0}({1})", Node::dump(indent), std::to_string(Value));
        }
    };

    struct IntegerLiteral : public Literal {
        DECLARE_RTTI(IntegerLiteral, Literal);
        AST_NODE_POD_CLONE(IntegerLiteral);

        const int64_t Value;

        explicit IntegerLiteral(int64_t value)
            : Value(value) {}

        [[nodiscard]] const TypeName& type() const override {
            static TypeName Long("long");
            return Long;
        }

        std::string toString() const override {
            return std::string(llvm::formatv("{0}({1})", nodeName(), Value));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), std::to_string(Value));
        }
    };

    struct FloatLiteral : public Literal {
        DECLARE_RTTI(FloatLiteral, Literal);
        AST_NODE_POD_CLONE(FloatLiteral);

        const double Value;

        FloatLiteral(double value)
            : Value(value) {}

        const TypeName& type() const override {
            static TypeName Double("double");
            return Double;
        }

        std::string toString() const override {
            return std::string(llvm::formatv("{0}({1})", nodeName(), Value));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), std::to_string(Value));
        }
    };

    struct StringLiteral : public Literal {
        DECLARE_RTTI(StringLiteral, Literal);
        AST_NODE_POD_CLONE(StringLiteral);

        const std::string Value;
        bool Raw;

        StringLiteral(const std::string& value, bool raw = false)
            : Value(value)
            , Raw(raw) {}

        const TypeName& type() const override {
            static TypeName String("string");
            return String;
        }

        std::string toString() const override {
            return std::string(llvm::formatv("{0}({1}\"{2}\")", nodeName(), Raw ? "@" : "", Value));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), Value);
        }
    };

    struct PointerLiteral : public Literal {
        DECLARE_RTTI(PointerLiteral, Literal);
        AST_NODE_POD_CLONE(PointerLiteral);

        const uint64_t Value;

        explicit PointerLiteral(uint64_t value = 0)
            : Value(value) {}

        [[nodiscard]] const TypeName& type() const override {
            static TypeName Ptr("ptr");
            return Ptr;
        }

        std::string toString() const override {
            return std::string(llvm::formatv("{0}({1})", nodeName(), Value));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), Value);
        }

        static PointerLiteral* Null() {
            static PointerLiteral* nullRef = new PointerLiteral(0);
            return nullRef;
        }
    };
} // namespace pepper::ast
