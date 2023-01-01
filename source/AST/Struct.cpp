//
// Created by Justin Boswell on 12/26/22.
//

#include "AST/Struct.h"

namespace pepper::ast {
    FieldDef::FieldDef(Ref<StructDef> st, const Ident& type, const Ident& name, Ref<Expression> defaultValue)
        : VariableDef(type, name) {
        Struct = st;
    }

    std::string FieldDef::toString() const {
        return Node::toString() + std::string(llvm::formatv("{0} {1}.{2}", Type, Struct->Name, Name));
    }

    std::string FieldDef::dump(int indent) const {
        return Node::dump(indent) +
               std::string(llvm::formatv(
                   "{0} {1}.{2} = {3}", Type, Struct->Name, Name, Default ? Default->toString() : "default"));
    }

    MethodDef::MethodDef(
        Ref<StructDef> st, const Ident& returnType, const Ident& name, const Params& params, bool vararg)
        : FunctionDef(returnType, name, params, vararg)
        , Struct(std::move(st)) {
    }

    std::string MethodDef::toString() const {
        const char* sep = "\n    ";
        Vector<std::string> types = Query(Parameters).select<std::string>([](auto p) { return p.Type; });
        return Node::toString() +
               std::string(llvm::formatv(
                   "{0} {1}.{2}({3})", ReturnType, Struct->Name, Name, llvm::join(types.begin(), types.end(), ", "))) +
               sep + Body->toString();
    }

    std::string MethodDef::dump(int indent) const {
        const char* sep = "\n";
        Vector<std::string> types = Query(Parameters).select<std::string>([](auto p) { return p.Type; });
        return Node::dump() +
               std::string(llvm::formatv(
                   "{0} {1}.{2}({3})", ReturnType, Struct->Name, Name, llvm::join(types.begin(), types.end(), ", "))) +
               sep + Body->dump(indent);
    }

    StructDef::StructDef(const Ident& type, const Ident& name)
        : Symbol(type, name) {
    }

    Ref<StructDef> StructDef::New(const Ident& type, const Ident& name) {
        Ref<StructDef> structDef = Ref<StructDef>::New(type, name);
        structDef->NewInstance = Ref<FunctionDef>::New(type, name);
        // Note that the order of these is important, ctor depends on init, so must be generated after
        structDef->Initializer = Ref<MethodDef>::New(structDef, "void", "__init");
        structDef->Constructor = Ref<MethodDef>::New(structDef, "void", "__ctor");
        structDef->Destructor = Ref<MethodDef>::New(structDef, "void", "__dtor");
        return structDef;
    }

    void StructDef::finish() {
        // Fill in new, needs "size" variable value filled in once it is known at codegen time
        Vector<Ref<Node>> body = {
            Ref<VariableDef>::New("u64", "size"),
            Ref<VariableDef>::New(Name,
                                  "this",
                                  Ref<FunctionCall>::New(ExternFunctionDef::Malloc,
                                                         Vector<Ref<Expression>>{Ref<VariableRef>::New("size")})),
            Ref<MethodCall>::New(Ref<ThisRef>::New(shared_from_this()), "__ctor"),
            Ref<VariableRef>::New("this"),
            Ref<Return>::New(NewInstance, Ref<VariableRef>::New("this")),
        };
        NewInstance->Body->Items = body;

        // Fill in initializer
        for (auto& field : Fields) {
            Initializer->Body->Items.push_back(field);
        }
        Initializer->Body->Items.push_back(Ref<Return>::New(Initializer));

        // insert initializer as the first instruction in Constructor
        Constructor->Body->Items.insert(Constructor->Body->Items.begin(),
                                        Ref<MethodCall>::New(Ref<ThisRef>::New(shared_from_this()), "__init"));

        // insert free as the last instruction before return in Destructor
        auto lastExpr = Destructor->Body->Items.size() ? Destructor->Body->Items.back() : nullptr;
        if (lastExpr && lastExpr->is<Return>()) {
            Destructor->Body->Items.pop_back();
        }

        Destructor->Body->Items.push_back(Ref<FunctionCall>::New(
            ExternFunctionDef::Free, Vector<Ref<Expression>>{Ref<ThisRef>::New(shared_from_this())}));

        Methods.push_back(Initializer);
        Methods.push_back(Constructor);
        Methods.push_back(Destructor);
    }

    std::string StructDef::toString() const {
        return Node::toString() + Name;
    }

    std::string StructDef::dump(int indent) const {
        const char* sep = "\n";
        Vector<std::string> fields =
            Query(Fields).select<std::string>([indent](auto f) { return f->dump(indent + 2); });
        Vector<std::string> methods =
            Query(Methods).select<std::string>([indent](auto m) { return m->dump(indent + 2); });
        return llvm::join_items(Node::dump(indent) + std::string(llvm::formatv("{0}", Name)),
                                llvm::join(fields.begin(), fields.end(), sep),
                                llvm::join(methods.begin(), methods.end(), sep));
    }
} // namespace pepper::ast
