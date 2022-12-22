
#include "Core/Common.h"

namespace llvm {
    class Type;
}

namespace pepper::ast {

    class Node {
        DECLARE_RTTI(Node);

      public:
        Node() = default;
        virtual ~Node() = default;
    };

    class Symbol : public Node {
        DECLARE_RTTI(Symbol, Node);

      private:
        llvm::Type* SymbolType;
        std::string SymbolName;

      public:
        Symbol(llvm::Type* type, std::string name)
            : SymbolType(type)
            , SymbolName(std::move(name)) {
        }

        llvm::Type* type() const {
            return SymbolType;
        }

        [[nodiscard]] const std::string& name() const {
            return SymbolName;
        }
    };

    class Expression : public Node {
        DECLARE_RTTI(Expression, Node);

      public:
        virtual llvm::Type* type() const = 0;
    };
} // namespace pepper::ast