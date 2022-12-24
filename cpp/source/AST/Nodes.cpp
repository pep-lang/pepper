
#include "AST/Nodes.h"
#include <algorithm>

#include "AST/Param.h"
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

    Ref<ExternFunctionDef> ExternFunctionDef::Malloc =
        Ref<ExternFunctionDef>::New("void*", "malloc", Params{{"size", "u64"}});
    Ref<ExternFunctionDef> ExternFunctionDef::Free =
        Ref<ExternFunctionDef>::New("void", "free", Params{{"ptr", "void*"}});

    StructDef::StructDef(const Name& type, const Name& name)
        : Symbol(type, name) {
        New = Ref<FunctionDef>::New(type + "*", name);
        // TODO: deal with parameters to ctor here
        Initializer = Ref<MethodDef>::New(shared_from_this(), "void", "__init");
        Constructor = Ref<MethodDef>::New(shared_from_this(), "void", "__ctor");
        Destructor = Ref<MethodDef>::New(shared_from_this(), "void", "__dtor");
        Methods.push_back(Initializer);
        Methods.push_back(Constructor);
        Methods.push_back(Destructor);
    }

    void StructDef::finish() {
        // Fill in new, needs "size" variable value filled in once it is known at codegen time
        New->locals().push_back(Ref<VariableDef>::New("u64", "size"));
        New->body().push_back(Ref<Return>::New(
            New,
            Ref<FunctionCall>::New(
                Constructor,
                std::vector<Ref<Expression>>{Ref<FunctionCall>::New(
                    ExternFunctionDef::Malloc, std::vector<Ref<Expression>>{Ref<VariableRef>::New("size")})})));

        // Fill in initializer
        for (auto& field : Fields) {
            Initializer->locals().push_back(field);
        }
        Initializer->body().push_back(Ref<Return>::New(Initializer));

        // insert initializer as the first instruction in Constructor
        Constructor->body().insert(
            Constructor->body().begin(),
            Ref<FunctionCall>::New(Initializer, std::vector<Ref<Expression>>{Ref<ThisRef>::New(shared_from_this())}));

        // insert free as the last instruction before return in Destructor
        auto lastExpr = Destructor->body().size() ? Destructor->body().back() : nullptr;
        if (lastExpr && lastExpr->is<Return>()) {
            Destructor->body().pop_back();
        }

        Destructor->body().push_back(Ref<FunctionCall>::New(
            ExternFunctionDef::Free, std::vector<Ref<Expression>>{Ref<ThisRef>::New(shared_from_this())}));
    }
} // namespace pepper::ast
