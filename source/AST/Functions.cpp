
#include <algorithm>

#include "AST/Nodes.h"
#include "AST/Param.h"
#include "Core/Exceptions.h"
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

    Ref<ExternFunctionDef> ExternFunctionDef::Malloc =
        Ref<ExternFunctionDef>::New("void*", "malloc", Params{{"size", "u64"}});
    Ref<ExternFunctionDef> ExternFunctionDef::Free =
        Ref<ExternFunctionDef>::New("void", "free", Params{{"ptr", "void*"}});

} // namespace pepper::ast
