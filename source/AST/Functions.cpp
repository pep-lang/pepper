
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

    static Ident functionSig(const TypeName& returnType, const Ident& name, const Params& params, bool vararg = false) {
        Vector<std::string> types = Query(params).select<std::string>([](auto& p) { return p.Type.toString(); });
        return std::string(llvm::formatv("{0} {1}({2:$[, ]}{3})",
                                         returnType,
                                         name,
                                         llvm::make_range(types.begin(), types.end()),
                                         vararg ? "..." : ""));
    }

    FunctionNode::FunctionNode(const TypeName& returnType, const TypeName& name, const Params& params, bool vararg)
        : Symbol(name, name.Name)
        , ScopeTarget(this)
        , ReturnType(returnType)
        , Parameters(params)
        , Vararg(vararg) {
        Generic = name.SubTypes.size() > 0;
    }

    std::string FunctionNode::signature() const {
        Vector<std::string> types = Query(Parameters).select<std::string>([](auto& p) { return p.Type.toString(); });
        std::string sig =
            llvm::formatv("{0} {1}({2:$[, ]})", ReturnType, Name, llvm::make_range(types.begin(), types.end()));
        return sig;
    }

    bool FunctionNode::isGeneric() const {
        return Generic;
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
                             Type.toString(),
                             llvm::join(types.begin(), types.end(), ", "));
    }

    Node* FunctionDef::clone() const {
        auto function = new FunctionDef(ReturnType, Name, Parameters, Vararg);
        function->Body = Body->cloneAs<Block>();
        return function;
    }

    std::string FunctionDef::dump(int indent) const {
        const char* sep = "\n";
        auto indentStr = repeat(" ", indent);
        auto contents = Body->Items.size() ? llvm::join_items(sep, " {", Body->dump(indent + 2), indentStr + "}") : "";
        return FunctionNode::dump(indent) + contents;
    }

    std::string FunctionCall::toString() const {
        Vector<std::string> argsStr = Query(Args).select<std::string>([](const auto& a) { return a->toString(); });
        return trim(llvm::formatv("{0} {1}({2:$[, ]})",
                                  Node::toString(),
                                  Target.toString(),
                                  llvm::make_range(argsStr.begin(), argsStr.end())));
    }

    std::string FunctionCall::dump(int indent) const {
        Vector<std::string> argsStr = Query(Args).select<std::string>([](const auto& a) { return a->dump(); });
        return llvm::formatv("{0} {1}({2:$[, ]})",
                             Node::dump(indent),
                             Target.toString(),
                             llvm::make_range(argsStr.begin(), argsStr.end()));
    }

    void FunctionCall::visit(Visitor& visitor) {
        Expression::visit(visitor);
        visitor.visit(Target);
        for (auto& arg : Args)
            visitor.visit(arg);
    }

} // namespace pepper::ast
