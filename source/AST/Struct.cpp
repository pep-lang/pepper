

#include "AST/Struct.h"

#include "AST/BinaryOps.h"
#include "AST/Literals.h"
#include "Sema/SemaContext.h"

namespace pepper::ast {
    FieldDef::FieldDef(
        const Resolvable<StructDef>& st, const TypeName& type, const Ident& name, Expression* defaultValue)
        : VariableDef(type, name, defaultValue)
        , Struct(st) {}

    std::string FieldDef::toString() const {
        return std::string(llvm::formatv("{0}: {1} {2}.{3}", nodeName(), Type, Struct.toString(), Name));
    }

    std::string FieldDef::dump(int indent) const {
        return llvm::formatv("{0} {1} {2}.{3} = {4}",
                             Node::dump(indent),
                             Type,
                             Struct.name(),
                             Name,
                             Default ? Default->toString() : "default");
    }

    Node* FieldDef::clone() const {
        return new FieldDef(Struct, Type, Name, Default ? Default->cloneAs<Expression>() : nullptr);
    }

    MethodDef::MethodDef(
        const TypeName& structName, const TypeName& returnType, const TypeName& name, const Params& params, bool vararg)
        : FunctionDef(returnType, name, params, vararg)
        , Struct(structName) {}

    void MethodDef::visit(Visitor& visitor) {
        FunctionDef::visit(visitor);
        visitor.visit(Struct);
    }

    std::string MethodDef::signature() const {
        Vector<std::string> types = Query(Parameters).select<std::string>([](auto& p) { return p.Type.toString(); });
        std::string sig = llvm::formatv(
            "{0} {1}.{2}({3:$[, ]})", ReturnType, Struct.name(), Name, llvm::make_range(types.begin(), types.end()));
        return sig;
    }

    std::string MethodDef::dump(int indent) const {
        const char* sep = "\n";
        auto indentStr = repeat(" ", indent);
        Vector<std::string> types =
            Query(Parameters).select<std::string>([](auto p) { return p.Type.toString() + " " + p.Name; });
        return std::string(llvm::formatv("{0} {1} {2}.{3}({4}) {{",
                                         Node::dump(indent),
                                         ReturnType,
                                         Struct.name(),
                                         Name,
                                         llvm::join(types.begin(), types.end(), ", "))) +
               sep + Body->dump(indent + 2) + "\n" + indentStr + "}";
    }

    Node* MethodDef::clone() const {
        auto method = new MethodDef(Struct, ReturnType, Name, Parameters, Vararg);
        method->StorageClass = StorageClass;
        method->Body = Body->cloneAs<Block>();
        return method;
    }

    std::string MethodCall::toString() const {
        Vector<std::string> args = Query(Args).select<std::string>([](const auto& a) { return a->toString(); });
        return llvm::formatv("{0}: {1}.{2}({3:$[, ]})",
                             nodeName(),
                             This->toString(),
                             Target.toString(),
                             llvm::make_range(args.begin(), args.end()));
    }

    std::string MethodCall::dump(int indent) const {
        Vector<std::string> args = Query(Args).select<std::string>([](const auto& a) { return a->dump(); });
        return llvm::formatv("{0} {1}.{2}({3})",
                             Node::dump(indent),
                             This->dump(),
                             Target.toString(),
                             llvm::join(args.begin(), args.end(), ", "));
    }

    template <typename N, typename... Args>
    static Node* Conditional(bool condition, Args&&... args) {
        if (condition) {
            return new N(std::forward<Args>(args)...);
        }
        return new None();
    }

    StructDef::StructDef(const TypeName& type, const Ident& name)
        : Symbol(type, name)
        , ScopeTarget(this)
        , Constructor(new ConstructorDef(this, Type, Name))
        , Destructor(new MethodDef(Type, TypeName::Void, {"__dtor"}))
        , Acquire(new MethodDef(Type, TypeName::Void, {"__acquire"}))
        , Release(new MethodDef(Type, TypeName::Void, {"__release"})) {
        Node::PushSource(Source);

        // Add a field at the head for the refcount
        Fields.push_back(new FieldDef(Type, TypeName{"u32"}, "__refcount", new IntegerLiteral(0)));

        auto refcount = []() {
            return new MemberRef(new ThisRef(), "__refcount");
        };
        Acquire->Body->Items = {
            // ++this.__refcount
            new Assign(refcount(), new Add(refcount(), new IntegerLiteral(1))),
            new FunctionCall(TypeName{"trace_ptr"},
                             ExprList({new ThisRef(), new StringLiteral("acquire: " + Name, true)})),
            new FunctionCall(TypeName{"trace_int"},
                             ExprList({refcount(), new StringLiteral("  refcount: " + Name, true)})),
        };
        Release->Body->Items = {
            // NOTE: release gets called blindly on the LHS of any assignment. The LHS can be a null-initialized ref.
            // if (!this) return
            new If(new Identical(new ThisRef(), PointerLiteral::Null()),
                   new Block("if",
                             {
                                 new Return(),
                             })),
            // --__refcount
            new Assign(refcount(), new Sub(refcount(), new IntegerLiteral(1))),

            new FunctionCall(TypeName{"trace_ptr"},
                             ExprList{new ThisRef(), new StringLiteral("release: " + Name, true)}),
            new FunctionCall(TypeName{"trace_int"},
                             ExprList{refcount(), new StringLiteral("  refcount: " + Name, true)}),

            // if (this.__refcount == 0)
            //     this.__dtor()
            new If(new Equal(refcount(), new IntegerLiteral(0)),
                   new Block("if",
                             NodeList<Node>{
                                 new FunctionCall(TypeName{"trace_ptr"},
                                                  ExprList{new ThisRef(), new StringLiteral("dtor: " + Name, true)}),
                                 new MethodCall(new ThisRef(), {"__dtor"}),
                             })),
        };
        Node::PopSource();
    }

    Node* StructDef::clone() const {
        auto newStruct = new StructDef(*this);
        newStruct->Acquire = newStruct->getMethod("__acquire");
        newStruct->Release = newStruct->getMethod("__release");
        newStruct->Destructor = newStruct->getMethod("__dtor");
        return newStruct;
    }

    void StructDef::finish() {
        // Copy off whatever the user put in the ctor, if anything
        auto userCtor = std::move(Constructor->Body->Items);
        Constructor->Body->Items.clear();

        // Create the allocation for `this`, needs "size" variable value filled in once it is known at codegen time
        Node::PushSource(Source);
        NodeList<Node> allocThis = {
            new VariableDef(TypeName("u64"), "size", nullptr, true),
            new ThisDef(Type, new FunctionCall(TypeName{"_pep_malloc"}, {new SymbolRef("size")})),
            new FunctionCall(TypeName{"trace_ptr"},
                             ExprList{new ThisRef(), new StringLiteral("ctor: " + Name, true)}),
        };
        Node::PopSource();

        Constructor->Body->Items = std::move(allocThis);

        // Fill in initializations
        for (auto& field : Fields) {
            Constructor->Body->Items.push_back(field);
        }

        // Restore user's instructions
        Constructor->Body->Items.append(userCtor);

        // Finally, ctor returns `this`
        Constructor->Body->Items.push_back(new Return(Constructor->ReturnType, new SymbolRef("this")));

        // insert free as the last instruction in Destructor
        Destructor->Body->Items.push_back(new FunctionCall(TypeName{"_pep_free"}, ExprList{new ThisRef()}));

        Methods.push_back(Release);
        Methods.push_back(Acquire);
        Methods.push_back(Destructor);
    }

    FieldDef* StructDef::getField(const Ident& name) const {
        for (auto& field : Fields) {
            if (field->Name == name)
                return field;
        }
        return nullptr;
    }

    MethodDef* StructDef::getMethod(const Ident& name) const {
        for (auto& method : Methods) {
            if (method->Name == name)
                return method;
        }
        return nullptr;
    }

    std::string StructDef::toString() const {
        return llvm::formatv("{0}: {1}", nodeName(), Type.toString());
    }

    std::string StructDef::dump(int indent) const {
        const char* sep = "\n";
        Vector<std::string> fields =
            Query(Fields).select<std::string>([indent](const auto& f) { return f->dump(indent + 2); });
        std::string ctorStr = Constructor->dump(indent + 2);
        Vector<std::string> methods =
            Query(Methods).select<std::string>([indent](const auto& m) { return m->dump(indent + 2); });
        auto indentStr = repeat(" ", indent);
        auto structStr = std::string(llvm::formatv("{0} {1} {{", Node::dump(indent), Type.toString()));
        auto fieldsStr = llvm::join(fields.begin(), fields.end(), sep);
        auto methodsStr = llvm::join(methods.begin(), methods.end(), sep);
        return llvm::join_items(sep, structStr, fieldsStr, ctorStr, methodsStr, indentStr + "}");
    }

    std::string StructSpec::toString() const {
        return llvm::formatv("{0}: {1}", nodeName(), Name);
    }

    std::string StructSpec::dump(int indent) const {
        auto indentStr = repeat(" ", indent);
        return indentStr + toString();
    }

    std::string ExtensionDef::toString() const {
        return llvm::formatv("{0}: {1}", nodeName(), Target.name());
    }

    std::string ExtensionDef::dump(int indent) const {
        const char* sep = "\n";
        auto indentStr = repeat(" ", indent);
        Vector<std::string> methods =
            Query(Methods).select<std::string>([indent](const auto& m) { return m->dump(indent + 2); });
        auto extStr = std::string(llvm::formatv("{0} {1} {{", Node::dump(indent), Target.name()));
        auto methodsStr = llvm::join(methods.begin(), methods.end(), sep);
        return llvm::join_items(sep, extStr, methodsStr, indentStr + "}");
    }
} // namespace pepper::ast
