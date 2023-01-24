
#include "AST/Nodes.h"
#include "AST/Param.h"
#include "Core/Query.h"
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
        , Vararg(vararg) {}

    std::string FunctionNode::signature() const {
        Vector<std::string> types = Query(Parameters).select<std::string>([](auto& p) { return p.Type.toString(); });
        std::string sig =
            llvm::formatv("{0} {1}({2:$[, ]})", ReturnType, Name, llvm::make_range(types.begin(), types.end()));
        return sig;
    }

    std::string FunctionNode::toString() const {
        std::string sig = llvm::formatv("{0} {1}", Node::toString(), signature());
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

    Node* FunctionDef::clone() const {
        auto function = new FunctionDef(ReturnType, Name, Parameters, Vararg);
        function->GenericParams = GenericParams;
        function->Body = Body->cloneAs<Block>();
        return function;
    }

    std::string FunctionDef::dump(int indent) const {
        const char* sep = "\n";
        auto indentStr = repeat(" ", indent);
        auto contents = Body->Items.size() ? llvm::join_items(sep, " {", Body->dump(indent + 2), indentStr + "}") : "";
        return FunctionNode::dump(indent) + contents;
    }

} // namespace pepper::ast
