//
// Created by Justin Boswell on 12/21/22.
//

#include "Frontend/Runtime.h"

#include "CodeGen/CodeGenModule.h"
#include "Frontend/Function.h"
#include "Frontend/Param.h"
#include "Frontend/Symbols.h"
#include "Frontend/Types.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Mangler.h"
#include "llvm/IR/Type.h"

namespace pepper {

    static struct RegisterCRT {
        RegisterCRT() {
            Runtime::Import("int", "puts", {{"char*", "str"}});
            Runtime::Import("void*", "malloc", {{"u64", "size"}});
            Runtime::Import("void", "free", {{"void*", "ptr"}});
        }
    } Registrar;

    void Runtime::Import(
        const Ident& returnType, const Ident& name, const Vector<std::pair<Ident, Ident>>& params, bool vararg) {
        for (const auto& import : Imports()) {
            if (import.Name == name)
                return;
        }
        Imports().emplace_back(FunctionProto{name, returnType, params, vararg});
    }

    Vector<Runtime::FunctionProto>& Runtime::Imports() {
        static Vector<FunctionProto> imports;
        return imports;
    }

    Runtime::Runtime(Ref<CodeGenModule> module)
        : Scope("Runtime") {
        for (auto& proto : Imports()) {
            auto returnType = Types::get(proto.Return);
            auto params = Params{};
            for (auto& param : proto.Params) {
                auto type = Types::get(param.first);
                params.emplace_back(param.second, type);
            }
            //            llvm::SmallString<256> mangledName;
            //            llvm::Mangler::getNameWithPrefix(mangledName, proto.Name,
            //            module->getModule()->getDataLayout());
            Functions[proto.Name] = Ref<Function>::New(proto.Name, returnType, params, proto.Vararg);
        }
    }
} // namespace pepper
