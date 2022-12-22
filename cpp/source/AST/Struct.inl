//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

namespace pepper::ast {
    class StructDef : public Symbol {
      public:
        StructDef(llvm::Type* type, std::string name)
            : Symbol(type, std::move(name)) {
        }
    };
} // namespace pepper::ast
