
#include "AST/Nodes.h"
#include "AST/Param.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"
#include "Frontend/Runtime.h"
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

    std::string FunctionNode::toString() const {
        Vector<std::string> types = Query(Parameters).select<std::string>([](auto p) { return p.Type.toString(); });
        std::string sig = llvm::formatv(
            "{0} {1} {2}({3})", Node::toString(), ReturnType, Name, llvm::join(types.begin(), types.end(), ", "));
        return sig;
    }

    std::string FunctionNode::dump(int indent) const {
        Vector<std::string> types =
            Query(Parameters).select<std::string>([](auto p) { return p.Type.toString() + " " + p.Name; });
        return llvm::formatv("{0} {1} {2}({3})",
                             Node::dump(indent),
                             ReturnType.toString(),
                             Name,
                             llvm::join(types.begin(), types.end(), ", "));
    }

    void FunctionNode::specialize(const Specialization& spec) {
        ReturnType.specialize(spec.TypeMap);
        for (auto& param : Parameters) {
            param.Type.specialize(spec.TypeMap);
        }
    }

    void FunctionDef::specialize(const Specialization& spec) {
        FunctionNode::specialize(spec);
        Body->specialize(spec);
    }

    std::string FunctionDef::dump(int indent) const {
        const char* sep = "\n";
        auto indentStr = repeat(" ", indent);
        auto contents =
            llvm::join_items(sep, FunctionNode::dump(indent) + " {", Body->dump(indent + 2), indentStr + "}");
        return contents;
    }

    void Return::specialize(const Specialization& spec) {
        Type.specialize(spec.TypeMap);
    }

    Ref<ExternFunctionDef> ExternFunctionDef::Find(const Ident& name) {
        for (const auto& import : Runtime::Imports()) {
            if (import.Name == name) {
                Params params;
                for (const auto& param : import.Params) {
                    params.emplace_back(param.second, param.first);
                }
                return Ref<ExternFunctionDef>::New(import.Return, import.Name, params, import.Vararg);
            }
        }
        return nullptr;
    }

} // namespace pepper::ast
