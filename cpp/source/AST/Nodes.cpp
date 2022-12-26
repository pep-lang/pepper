
#include "AST/Nodes.h"
#include <algorithm>

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

    StructDef::StructDef(const Name& type, const Name& name)
        : Symbol(type, name) {
    }

    Ref<StructDef> StructDef::New(const Name& type, const Name& name) {
        Ref<StructDef> structDef = Ref<StructDef>::New(type, name);
        structDef->NewInstance = Ref<FunctionDef>::New(type, name);
        // Note that the order of these is important, ctor depends on init, so must be generated after
        // TODO: deal with parameters to ctor here
        structDef->Initializer = Ref<MethodDef>::New(structDef, "void", "__init");
        structDef->Constructor = Ref<MethodDef>::New(structDef, "void", "__ctor");
        structDef->Destructor = Ref<MethodDef>::New(structDef, "void", "__dtor");
        structDef->Methods.push_back(structDef->Initializer);
        structDef->Methods.push_back(structDef->Constructor);
        structDef->Methods.push_back(structDef->Destructor);

        return structDef;
    }

    void StructDef::finish() {
        // Fill in new, needs "size" variable value filled in once it is known at codegen time
        NewInstance->locals().push_back(Ref<VariableDef>::New("u64", "size"));
        NewInstance->locals().push_back(Ref<VariableDef>::New(
            identifier(),
            "this",
            Ref<FunctionCall>::New(ExternFunctionDef::Malloc, Vector<Ref<Expression>>{Ref<VariableRef>::New("size")})));
        Vector<Ref<Expression>> body = {
            Ref<FunctionCall>::New(Constructor),
            Ref<Return>::New(NewInstance, Ref<VariableRef>::New("this")),
        };
        NewInstance->body() = body;

        // Fill in initializer
        for (auto& field : Fields) {
            Initializer->locals().push_back(field);
        }
        Initializer->body().push_back(Ref<Return>::New(Initializer));

        // insert initializer as the first instruction in Constructor
        Constructor->body().insert(Constructor->body().begin(), Ref<FunctionCall>::New(Initializer));

        // insert free as the last instruction before return in Destructor
        auto lastExpr = Destructor->body().size() ? Destructor->body().back() : nullptr;
        if (lastExpr && lastExpr->is<Return>()) {
            Destructor->body().pop_back();
        }

        Destructor->body().push_back(Ref<FunctionCall>::New(
            ExternFunctionDef::Free, Vector<Ref<Expression>>{Ref<ThisRef>::New(shared_from_this())}));
    }
} // namespace pepper::ast
