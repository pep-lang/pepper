//
// Created by Justin Boswell on 12/26/22.
//

#include "AST/Struct.h"

namespace pepper::ast {
    FieldDef::FieldDef(Ref<StructDef> st, const Name& type, const Name& name, Ref<Expression> defaultValue)
        : VariableDef(type, name) {
        Struct = st;
    }

    std::string FieldDef::toString() const {
        return Node::toString() + std::string(llvm::formatv("{0} {1}.{2}", type(), Struct->identifier(), identifier()));
    }

    std::string FieldDef::dump() const {
        return Node::dump() + std::string(llvm::formatv("{0} {1}.{2} = {3}",
                                                        type(),
                                                        Struct->identifier(),
                                                        identifier(),
                                                        Default ? Default->toString() : "default"));
    }

    MethodDef::MethodDef(Ref<StructDef> st, const Name& returnType, const Name& name, const Params& params, bool vararg)
        : FunctionDef(returnType, name, params, vararg)
        , Struct(std::move(st)) {
    }

    std::string MethodDef::toString() const {
        const char* sep = "\n    ";
        Vector<std::string> types = Query(Parameters).select<std::string>([](auto p) { return p.Type; });
        Vector<std::string> vars = Query(locals()).select<std::string>([](auto l) { return l->toString(); });
        Vector<std::string> exprs = Query(body()->Items).select<std::string>([](auto e) { return e->toString(); });
        return Node::toString() +
               std::string(llvm::formatv("{0} {1}.{2}({3})",
                                         ReturnType,
                                         structDef()->identifier(),
                                         identifier(),
                                         llvm::join(types.begin(), types.end(), ", "))) +
               sep + llvm::join(vars.begin(), vars.end(), sep) + sep + llvm::join(exprs.begin(), exprs.end(), sep);
    }

    std::string MethodDef::dump() const {
        const char* sep = "\n";
        Vector<std::string> types = Query(Parameters).select<std::string>([](auto p) { return p.Type; });
        Vector<std::string> vars = Query(locals()).select<std::string>([](auto l) { return l->dump(); });
        Vector<std::string> exprs = Query(body()->Items).select<std::string>([](auto e) { return e->dump(); });
        return Node::dump() +
               std::string(llvm::formatv("{0} {1}.{2}({3})",
                                         ReturnType,
                                         structDef()->identifier(),
                                         identifier(),
                                         llvm::join(types.begin(), types.end(), ", "))) +
               sep + llvm::join(vars.begin(), vars.end(), sep) + sep + llvm::join(exprs.begin(), exprs.end(), sep);
    }

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
            Ref<VariableRef>::New("this"),
            Ref<Return>::New(NewInstance, Ref<VariableRef>::New("this")),
        };
        NewInstance->body()->Items = body;

        // Fill in initializer
        for (auto& field : Fields) {
            Initializer->locals().push_back(field);
        }
        Initializer->body()->Items.push_back(Ref<Return>::New(Initializer));

        // insert initializer as the first instruction in Constructor
        Constructor->body()->Items.insert(Constructor->body()->Items.begin(), Ref<FunctionCall>::New(Initializer));

        // insert free as the last instruction before return in Destructor
        auto lastExpr = Destructor->body()->Items.size() ? Destructor->body()->Items.back() : nullptr;
        if (lastExpr && lastExpr->is<Return>()) {
            Destructor->body()->Items.pop_back();
        }

        Destructor->body()->Items.push_back(Ref<FunctionCall>::New(
            ExternFunctionDef::Free, Vector<Ref<Expression>>{Ref<ThisRef>::New(shared_from_this())}));
    }

    std::string StructDef::toString() const {
        return Node::toString() + identifier();
    }

    std::string StructDef::dump() const {
        const char* sep = "\n  ";
        Vector<std::string> fields = Query(Fields).select<std::string>([](auto f) { return f->toString(); });
        Vector<std::string> methods = Query(Methods).select<std::string>([](auto m) { return m->toString(); });
        return llvm::join_items(sep,
                                Node::dump() + std::string(llvm::formatv("{0}", identifier())),
                                llvm::join(fields.begin(), fields.end(), sep),
                                llvm::join(methods.begin(), methods.end(), sep));
    }
} // namespace pepper::ast
