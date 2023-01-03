
#include <algorithm>

#include "AST/Nodes.h"
#include "AST/Param.h"
#include "Core/Exceptions.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper::ast {

    static Ident functionTy(const TypeName& returnType, const Params& args, bool vararg = false) {
        Ident argsStr;
        for (auto it = args.begin(); it != args.end(); ++it) {
            argsStr += it->Type;
            if (it != args.end() - 1)
                argsStr += ", ";
        }
        std::string ellipsis = vararg ? "..." : "";
        return std::string(llvm::formatv("{0}({1}{2})", returnType.toString(), argsStr, ellipsis));
    }

    FunctionNode::FunctionNode(const TypeName& returnType, const Ident& name, const Params& params, bool vararg)
        : Symbol(functionTy(returnType, params, vararg), name)
        , ReturnType(returnType)
        , Parameters(params)
        , Vararg(vararg) {
    }

    Ref<ExternFunctionDef> ExternFunctionDef::Malloc =
        Ref<ExternFunctionDef>::New(TypeName("void*"), "malloc", Params{{"size", TypeName("u64")}});
    Ref<ExternFunctionDef> ExternFunctionDef::Free =
        Ref<ExternFunctionDef>::New(TypeName("void"), "free", Params{{"ptr", TypeName("void*")}});

} // namespace pepper::ast
