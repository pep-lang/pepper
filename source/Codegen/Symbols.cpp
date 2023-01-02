//
// Created by Justin Boswell on 1/1/23.
//

#include "Codegen/Symbols.h"

#include "Codegen/Scope.h"

namespace pepper {
    Symbols::Symbols() {
    }

    Ref<Symbols> Symbols::FromScope(Ref<Scope> scope) {
        auto symbols = Ref<Symbols>::New();
        for (const auto& entry : scope->Functions) {
            symbols->Table[entry.getKey()] = entry.getValue();
        }
        return symbols;
    }
} // namespace pepper
