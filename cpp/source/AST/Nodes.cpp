
#include "AST/Nodes.h"
#include <algorithm>

#include "Core/Exceptions.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper::ast {

    static std::string functionTy(const Name& returnType, const Params& args, bool vararg = false) {
        Name argsStr;
        for (auto it = args.begin(); it != args.end(); ++it) {
            argsStr += it->Type;
            if (it != args.end() - 1)
                argsStr += ", ";
        }
        std::string ellipsis = vararg ? "..." : "";
        return llvm::formatv("{0}({1}{2})", returnType, argsStr, ellipsis);
    }

    FunctionNode::FunctionNode(const Name& returnType, const Name& name, const Params& params, bool vararg)
        : Symbol(functionTy(returnType, params, vararg), name)
        , ReturnType(returnType)
        , Parameters(params)
        , Vararg(vararg) {
    }

    StructDef::StructDef(const Name& type, const Name& name)
        : Symbol(type, name) {
        New = Ref<FunctionDef>::New(type, name);
        // TODO: deal with parameters to ctor here
        Initializer = Ref<MethodDef>::New(shared_from_this(), "void", "__init");
        Constructor = Ref<MethodDef>::New(shared_from_this(), "void", "__ctor");
        Destructor = Ref<MethodDef>::New(shared_from_this(), "void", "__dtor");
        Methods.push_back(Initializer);
        Methods.push_back(Constructor);
        Methods.push_back(Destructor);
    }

    void StructDef::finish() {
    }
} // namespace pepper::ast
