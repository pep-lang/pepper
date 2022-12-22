//
// Created by Justin Boswell on 12/21/22.
//

#pragma once



namespace pepper::ast {
    class StructDef : public Symbol {
      public:
        StructDef(Ref<Type> type, std::string name)
            : Symbol(std::move(type),std::move(name)) {

        }
    };
}
