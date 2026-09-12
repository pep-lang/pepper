
#include "Sema/Model/Functions.h"

#include "Core/Query.h"
#include "Sema/Model/Param.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper::sema {

    static Ident functionTy(const TypeName& return_type, const Params& args, bool vararg = false) {
        Ident args_str;
        for (auto it = args.begin(); it != args.end(); ++it) {
            args_str += it->type;
            if (it != args.end() - 1)
                args_str += ", ";
        }
        std::string ellipsis = vararg ? "..." : "";
        return std::string(llvm::formatv("{0}({1}{2})", return_type.to_string(), args_str, ellipsis));
    }

    static Ident function_sig(
        const TypeName& return_type, const Ident& name, const Params& params, bool vararg = false) {
        Vector<std::string> types = Query(params).select<std::string>([](auto& p) { return p.type.to_string(); });
        return std::string(llvm::formatv("{0} {1}({2:$[, ]}{3})",
                                         return_type,
                                         name,
                                         llvm::make_range(types.begin(), types.end()),
                                         vararg ? "..." : ""));
    }

    FunctionNode::FunctionNode(const TypeName& ret_type, const TypeName& name, const Params& params, bool vararg)
        : Symbol(name, name.name)
        , ScopeTarget(this)
        , return_type(ret_type)
        , parameters(params)
        , is_vararg(vararg) {
        is_generic_func = type.sub_types.size() > 0;
    }

    std::string FunctionNode::signature() const {
        Vector<std::string> types = Query(parameters).select<std::string>([](auto& p) { return p.type.to_string(); });
        std::string sig =
            llvm::formatv("{0} {1}({2:$[, ]})", return_type, name, llvm::make_range(types.begin(), types.end()));
        return sig;
    }

    bool FunctionNode::is_generic() const {
        return is_generic_func;
    }

    std::string FunctionNode::to_string() const {
        return llvm::formatv("{0}: {1}", node_name(), signature());
    }

    std::string FunctionNode::dump(int indent) const {
        Vector<std::string> types =
            Query(parameters).select<std::string>([](auto p) { return p.type.to_string() + " " + p.name; });
        return llvm::formatv("{0} {1} {2}({3})",
                             Node::dump(indent),
                             return_type.to_string(),
                             type.to_string(),
                             llvm::join(types.begin(), types.end(), ", "));
    }

    Node* FunctionDef::clone() const {
        auto function = new FunctionDef(return_type, name, parameters, is_vararg);
        function->body = body->clone_as<Block>();
        return function;
    }

    std::string FunctionDef::dump(int indent) const {
        const char* sep = "\n";
        auto indentStr = repeat(" ", indent);
        auto contents = body->items.size() ? llvm::join_items(sep, " {", body->dump(indent + 2), indentStr + "}") : "";
        return FunctionNode::dump(indent) + contents;
    }

    std::string FunctionCall::to_string() const {
        Vector<std::string> args_str = Query(args).select<std::string>([](const auto& a) { return a->to_string(); });
        return trim(llvm::formatv("{0}: {1}({2:$[, ]})",
                                  node_name(),
                                  target.to_string(),
                                  llvm::make_range(args_str.begin(), args_str.end())));
    }

    std::string FunctionCall::dump(int indent) const {
        Vector<std::string> args_str = Query(args).select<std::string>([](const auto& a) { return a->dump(); });
        return llvm::formatv("{0} {1}({2:$[, ]})",
                             Node::dump(indent),
                             target.to_string(),
                             llvm::make_range(args_str.begin(), args_str.end()));
    }

    void FunctionCall::visit(Visitor& visitor) {
        Expression::visit(visitor);
        visitor.visit(target);
        for (auto& arg : args)
            visitor.visit(arg);
    }

} // namespace pepper::sema
