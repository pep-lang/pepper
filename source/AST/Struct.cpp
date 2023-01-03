//
// Created by Justin Boswell on 12/26/22.
//

#include "AST/Struct.h"

namespace pepper::ast {
    FieldDef::FieldDef(Ref<StructDef> st, const TypeName& type, const Ident& name, Ref<Expression> defaultValue)
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
        Ref<StructDef> st, const TypeName& returnType, const Ident& name, const Params& params, bool vararg)
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

    StructDef::StructDef(const TypeName& type)
        : Symbol(type, type.toString()) {
    }

    Ref<StructDef> StructDef::New(const TypeName& type) {
        Ref<StructDef> structDef = Ref<StructDef>::New(type);
        structDef->NewInstance = Ref<FunctionDef>::New(type, structDef->Name);
        // Note that the order of these is important, ctor depends on init, so must be generated after
        structDef->Initializer = Ref<MethodDef>::New(structDef, TypeName("void"), "__init");
        structDef->Constructor = Ref<MethodDef>::New(structDef, TypeName("void"), "__ctor");
        structDef->Destructor = Ref<MethodDef>::New(structDef, TypeName("void"), "__dtor");
        return structDef;
    }

    static Ref<MethodDef> specializeMethod(Ref<MethodDef> srcMethod, Ref<StructDef> targetStruct) {
        auto genericStruct = srcMethod->Struct;
        auto method = Ref<MethodDef>::New(
            targetStruct, srcMethod->ReturnType, srcMethod->Name, srcMethod->Parameters, srcMethod->Vararg);
        for (int idx = 0; idx < genericStruct->GenericParams.size(); ++idx) {
            const auto& param = genericStruct->GenericParams[idx];
            const auto& type = targetStruct->GenericArgs[idx];
            method->ReturnType.replace(param, type);
            for (auto& methodParam : method->Parameters) {
                methodParam.Type.replace(param, type);
            }
        }
        return method;
    }

    void StructDef::specialize(Ref<StructDef> genericStruct, Vector<TypeName> genericArgs) {
        GenericStruct = std::move(genericStruct);
        GenericArgs = std::move(genericArgs);

        // replace types on fields
        for (const auto& srcField : GenericStruct->Fields) {
            auto field = Ref<FieldDef>::New(shared_from_this(), srcField->Type, srcField->Name, srcField->Default);
            for (int idx = 0; idx < GenericStruct->GenericParams.size(); ++idx) {
                const auto& param = GenericStruct->GenericParams[idx];
                const auto& type = GenericArgs[idx];
                field->Type.replace(param, type);
            }
            Fields.emplace_back(field);
        }

        // replace types in method return types and params
        for (const auto& srcMethod : GenericStruct->Methods) {
            // Do not specialized init/ctor/dtor
            if (srcMethod->Name.starts_with("__"))
                continue;
            auto method = specializeMethod(srcMethod, shared_from_this());
            Methods.emplace_back(method);
        }

        // Specialize the constructor (args could change), but the other functions can be defaulted
        Constructor = specializeMethod(GenericStruct->Constructor, shared_from_this());
    }

    void StructDef::finish() {
        // Fill in new, needs "size" variable value filled in once it is known at codegen time
        Vector<Ref<Node>> body = {
            Ref<VariableDef>::New(TypeName("u64"), "size"),
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
