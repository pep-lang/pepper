//
// Created by Justin Boswell on 12/26/22.
//

#include "AST/Struct.h"

#include "AST/BinaryOps.h"
#include "AST/Literals.h"

namespace pepper::ast {
    FieldDef::FieldDef(StructDef* st, const TypeName& type, const Ident& name, Ref<Expression> defaultValue)
        : VariableDef(type, name, defaultValue)
        , Struct(st) {
    }

    std::string FieldDef::toString() const {
        return Node::toString() + std::string(llvm::formatv("{0} {1}.{2}", Type, Struct->Name, Name));
    }

    std::string FieldDef::dump(int indent) const {
        return llvm::formatv("{0} {1} {2}.{3} = {4}",
                             Node::dump(indent),
                             Type,
                             Struct->Name,
                             Name,
                             Default ? Default->toString() : "default");
    }

    Ref<Node> FieldDef::clone() const {
        return Ref<FieldDef>::New(
            Struct, Type, Name, Ref<Expression>{Default ? Default->cloneAs<Expression>() : nullptr});
    }

    void FieldDef::specialize(const Specialization& spec) {
        VariableDef::specialize(spec);
        Struct = spec.Struct.get();
    }

    MethodDef::MethodDef(
        StructDef* st, const TypeName& returnType, const Ident& name, const Params& params, bool vararg)
        : FunctionDef(returnType, name, params, vararg)
        , Struct(st) {
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
        auto indentStr = repeat(" ", indent);
        Vector<std::string> types =
            Query(Parameters).select<std::string>([](auto p) { return p.Type.toString() + " " + p.Name; });
        return std::string(llvm::formatv("{0} {1} {2}.{3}({4}) {{",
                                         Node::dump(indent),
                                         ReturnType,
                                         Struct->Name,
                                         Name,
                                         llvm::join(types.begin(), types.end(), ", "))) +
               sep + Body->dump(indent + 2) + "\n" + indentStr + "}";
    }

    Ref<Node> MethodDef::clone() const {
        auto method = Ref<MethodDef>::New(Struct, ReturnType, Name, Parameters, Vararg);
        method->Body = Body->cloneAs<Block>();
        return method;
    }

    void MethodDef::specialize(const Specialization& spec) {
        FunctionDef::specialize(spec);
        Struct = spec.Struct.get();
    }

    void MethodCall::specialize(const Specialization& spec) {
        This->specialize(spec);
        Query(Args).each([&spec](auto& a) { a->specialize(spec); });
    }

    std::string MethodCall::dump(int indent) const {
        Vector<std::string> args = Query(Args).select<std::string>([](auto& a) { return a->dump(); });
        return llvm::formatv(
            "{0} {1}.{2}({3})", Node::dump(indent), This->dump(), Name, llvm::join(args.begin(), args.end(), ", "));
    }

    StructDef::StructDef(const TypeName& type)
        : Symbol(type, type.toString()) {
        NewInstance = Ref<FunctionDef>::New(Type, Name);
        // Note that the order of these is important, ctor depends on init, so must be generated after
        Initializer = Ref<MethodDef>::New(this, TypeName::Void, "__init");
        Constructor = Ref<MethodDef>::New(this, TypeName::Void, "__ctor");
        Destructor = Ref<MethodDef>::New(this, TypeName::Void, "__dtor");

        // Add a field at the head for the refcount
        Fields.emplace_back(Ref<FieldDef>::New(this, TypeName{"u32"}, "__refcount", Ref<IntegerLiteral>::New(0)));

        Acquire = Ref<MethodDef>::New(this, TypeName::Void, "__acquire", Params{{"ref", Type}});
        Release = Ref<MethodDef>::New(this, TypeName::Void, "__release");

        auto refcount = Ref<MemberRef>::New(Ref<ThisRef>::New(), "__refcount");
        Acquire->Body->Items = {
            // if (ref == this)
            //     return
            Ref<If>::New(Ref<Equal>::New(Ref<SymbolRef>::New("ref"), Ref<ThisRef>::New()),
                         Ref<Block>::New("if",
                                         Vector<Ref<Node>>{
                                             Ref<Return>::New(),
                                         })),
            // if (ref)
            //     ref.__release()
            Ref<If>::New(
                Ref<NotEqual>::New(Ref<SymbolRef>::New("ref"), PointerLiteral::Null()),
                Ref<Block>::New("if",
                                Vector<Ref<Node>>{
                                    Ref<MethodCall>::New(TypeName::Void, Ref<SymbolRef>::New("ref"), "__release"),
                                })),
            // this.__refcount += 1
            Ref<Assign>::New(refcount, Ref<Add>::New(refcount, Ref<IntegerLiteral>::New(1))),
        };
        Release->Body->Items = {
            // __refcount -= 1
            Ref<Assign>::New(refcount, Ref<Sub>::New(refcount, Ref<IntegerLiteral>::New(-1))),
            // if (this.__refcount == 0)
            //     this.__dtor()
            Ref<If>::New(Ref<Equal>::New(refcount, Ref<IntegerLiteral>::New(0)),
                         Ref<Block>::New("if",
                                         Vector<Ref<Node>>{
                                             Ref<MethodCall>::New(TypeName::Void, Ref<ThisRef>::New(), "__dtor"),
                                         })),
        };
    }

    StructDef::StructDef(const StructDef& rhs)
        : StructDef(rhs.Type) {
    }

    Ref<StructDef> StructDef::New(const TypeName& type) {
        Ref<StructDef> structDef = Ref<StructDef>::New(type);
        return structDef;
    }

    void StructDef::specialize(Ref<StructDef> genericStruct, Vector<TypeName> genericArgs) {
        GenericStruct = std::move(genericStruct);
        GenericArgs = std::move(genericArgs);

        Specialization spec{shared_from_this()};
        // map params -> args
        for (int idx = 0; idx < GenericStruct->GenericParams.size(); ++idx) {
            const auto& param = GenericStruct->GenericParams[idx];
            const auto& type = GenericArgs[idx];
            spec.TypeMap[param] = type;
        }

        // replace types on fields
        for (const auto& srcField : GenericStruct->Fields) {
            auto field = srcField->cloneAs<FieldDef>();
            field->specialize(spec);
            Fields.emplace_back(field);
        }

        // clone and specialize the `new` function
        NewInstance = GenericStruct->NewInstance->cloneAs<FunctionDef>();
        NewInstance->Name = spec.Struct->Name;
        NewInstance->Type = spec.Struct->Type;
        NewInstance->specialize(spec);

        // replace types in method return types and params
        for (const auto& srcMethod : GenericStruct->Methods) {
            // clone the method then specialize it
            auto method = srcMethod->cloneAs<MethodDef>();
            method->specialize(spec);
            Methods.emplace_back(method);

            // update Constructor once it's specialized
            if (method->Name == "__ctor")
                Constructor = method;
            if (method->Name == "__init")
                Initializer = method;
            if (method->Name == "__dtor")
                Destructor = method;
        }
    }

    void StructDef::finish() {
        // Fill in new, needs "size" variable value filled in once it is known at codegen time
        Vector<Ref<Node>> body = {
            Ref<VariableDef>::New(TypeName("u64"), "size"),
            Ref<VariableDef>::New(Type,
                                  "this",
                                  Ref<FunctionCall>::New(ExternFunctionDef::Malloc,
                                                         Vector<Ref<Expression>>{Ref<SymbolRef>::New("size")})),
            Ref<MethodCall>::New(TypeName::Void, Ref<ThisRef>::New(), "__ctor"),
            Ref<SymbolRef>::New("this"),
            Ref<Return>::New(NewInstance->ReturnType, Ref<SymbolRef>::New("this")),
        };
        NewInstance->Body->Items = body;

        // Fill in initializer
        for (auto& field : Fields) {
            Initializer->Body->Items.push_back(field);
        }
        Initializer->Body->Items.push_back(Ref<Return>::New());

        // insert initializer as the first instruction in Constructor
        Constructor->Body->Items.insert(Constructor->Body->Items.begin(),
                                        Ref<MethodCall>::New(TypeName::Void, Ref<ThisRef>::New(), "__init"));

        // insert free as the last instruction before return in Destructor
        auto lastExpr = !Destructor->Body->Items.empty() ? Destructor->Body->Items.back() : nullptr;
        if (lastExpr && lastExpr->is<Return>()) {
            Destructor->Body->Items.pop_back();
        }

        Destructor->Body->Items.push_back(
            Ref<FunctionCall>::New(ExternFunctionDef::Free, Vector<Ref<Expression>>{Ref<ThisRef>::New()}));

        Methods.push_back(Initializer);
        Methods.push_back(Constructor);
        Methods.push_back(Destructor);
        Methods.push_back(Acquire);
        Methods.push_back(Release);
    }

    Ref<FieldDef> StructDef::getField(const Ident& name) const {
        for (auto field : Fields) {
            if (field->Name == name)
                return field;
        }
        return nullptr;
    }

    Ref<MethodDef> StructDef::getMethod(const Ident& name) const {
        for (auto method : Methods) {
            if (method->Name == name)
                return method;
        }
        return nullptr;
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
        auto indentStr = repeat(" ", indent);
        auto structStr = std::string(llvm::formatv("{0} {1} {{", Node::dump(indent), Name));
        auto fieldsStr = llvm::join(fields.begin(), fields.end(), sep);
        auto methodsStr = llvm::join(methods.begin(), methods.end(), sep);
        return llvm::join_items(sep, structStr, fieldsStr, methodsStr, indentStr + "}");
    }
} // namespace pepper::ast
