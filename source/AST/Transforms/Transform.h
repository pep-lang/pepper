
#pragma once

#include <memory>

#include "AST/AST.h"

namespace pepper::ast {
    struct SymbolTable {
        llvm::StringMap<FunctionDef*> Functions;
        llvm::StringMap<StructDef*> Structs;
        llvm::StringSet<> Types;

        SymbolTable();
        SymbolTable(const AST& ast);
        Symbol* find(const Ident& name) const;
        TypeName find(const TypeName& name) const;
    };

    struct Transformer {
        DECLARE_RTTI(Transformer);
        virtual ~Transformer() = default;
        virtual void run(Ref<AST> parseTree) = 0;
    };

    class TransformPass {
        Ref<AST> ParseTree;
        Vector<std::unique_ptr<Transformer>> Transformers;

      public:
        TransformPass(Ref<AST> parseTree);

        Ref<AST> run() const;
    };
} // namespace pepper::ast
