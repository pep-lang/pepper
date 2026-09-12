
#pragma once

#include <memory>

#include "Sema/Model/Module.h"

namespace pepper::sema {
    struct SymbolTable {
        llvm::StringMap<FunctionNode*> functions;
        llvm::StringMap<StructDef*> structs;
        llvm::StringMap<TraitDecl*> traits;
        llvm::StringSet<> types;

        SymbolTable();
        SymbolTable(const Module& ast);
        Symbol* find(const Ident& name) const;
        TypeName find(const TypeName& name) const;
    };

    struct Transformer {
        DECLARE_RTTI(Transformer);
        virtual ~Transformer() = default;
        virtual void run(Ref<Module> module) = 0;
    };

    class TransformPass {
        Ref<Module> module;
        Vector<std::unique_ptr<Transformer>> transformers;

      public:
        TransformPass(Ref<Module> module);

        Ref<Module> run() const;
    };
} // namespace pepper::sema
