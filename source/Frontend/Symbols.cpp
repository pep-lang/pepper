

#include "Frontend/Symbols.h"

#include "Frontend/Scope.h"

namespace pepper {
    Symbols::Symbols() {}

    Ref<Symbols> Symbols::FromScope(Ref<Scope> scope) {
        auto symbols = Ref<Symbols>::New();
        for (const auto& entry : scope->Functions) {
            symbols->Table[entry.getKey()] = entry.getValue();
        }
        return symbols;
    }
} // namespace pepper
