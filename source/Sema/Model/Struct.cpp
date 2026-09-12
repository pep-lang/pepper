

#include "Sema/Model/Struct.h"

#include "Sema/Model/BinaryOps.h"
#include "Sema/Model/Branches.h"
#include "Sema/Model/Literals.h"

namespace pepper::sema {
    FieldDef::FieldDef(
        const Resolvable<StructDef>& st, const TypeName& type, const Ident& name, Expression* defaultValue)
        : VariableDef(type, name, defaultValue)
        , parent(st) {}

    std::string FieldDef::to_string() const {
        return std::string(llvm::formatv("{0}: {1} {2}.{3}", node_name(), type, parent.to_string(), name));
    }

    std::string FieldDef::dump(int indent) const {
        return llvm::formatv("{0} {1} {2}.{3} = {4}",
                             Node::dump(indent),
                             type,
                             parent.name(),
                             name,
                             default_value ? default_value->to_string() : "default");
    }

    Node* FieldDef::clone() const {
        return new FieldDef(parent, type, name, default_value ? default_value->clone_as<Expression>() : nullptr);
    }

    MethodDef::MethodDef(const TypeName& structName,
                         const TypeName& return_type,
                         const TypeName& name,
                         const Params& params,
                         bool vararg)
        : FunctionDef(return_type, name, params, vararg)
        , parent(structName) {}

    void MethodDef::visit(Visitor& visitor) {
        FunctionDef::visit(visitor);
        visitor.visit(parent);
    }

    std::string MethodDef::signature() const {
        Vector<std::string> types = Query(parameters).select<std::string>([](auto& p) { return p.type.to_string(); });
        std::string sig = llvm::formatv(
            "{0} {1}.{2}({3:$[, ]})", return_type, parent.name(), name, llvm::make_range(types.begin(), types.end()));
        return sig;
    }

    std::string MethodDef::dump(int indent) const {
        const char* sep = "\n";
        auto indentStr = repeat(" ", indent);
        Vector<std::string> types =
            Query(parameters).select<std::string>([](auto p) { return p.type.to_string() + " " + p.name; });
        return std::string(llvm::formatv("{0} {1} {2}.{3}({4}) {{",
                                         Node::dump(indent),
                                         return_type,
                                         parent.name(),
                                         name,
                                         llvm::join(types.begin(), types.end(), ", "))) +
               sep + body->dump(indent + 2) + "\n" + indentStr + "}";
    }

    Node* MethodDef::clone() const {
        auto method = new MethodDef(parent, return_type, name, parameters, is_vararg);
        method->storage_class = storage_class;
        method->body = body->clone_as<Block>();
        return method;
    }

    std::string MethodCall::to_string() const {
        Vector<std::string> args = Query(Args).select<std::string>([](const auto& a) { return a->to_string(); });
        return llvm::formatv("{0}: {1}.{2}({3:$[, ]})",
                             node_name(),
                             This->to_string(),
                             Target.to_string(),
                             llvm::make_range(args.begin(), args.end()));
    }

    std::string MethodCall::dump(int indent) const {
        Vector<std::string> args = Query(Args).select<std::string>([](const auto& a) { return a->dump(); });
        return llvm::formatv("{0} {1}.{2}({3})",
                             Node::dump(indent),
                             This->dump(),
                             Target.to_string(),
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
        , construct(new ConstructorDef(this, type, name))
        , destruct(new MethodDef(type, TypeName::Void, {"__dtor"}))
        , acquire(new MethodDef(type, TypeName::Void, {"__acquire"}))
        , release(new MethodDef(type, TypeName::Void, {"__release"})) {
        Node::push_source(source_loc);

        // Add a field at the head for the refcount
        field_members.push_back(new FieldDef(type, TypeName{"u32"}, "__refcount", new IntegerLiteral(0)));

        auto refcount = []() {
            return new MemberRef(new ThisRef(), "__refcount");
        };
        acquire->body->items = {
            // ++this.__refcount
            new Assign(refcount(), new Add(refcount(), new IntegerLiteral(1))),
            new FunctionCall(TypeName{"trace_ptr"},
                             ExprList({new ThisRef(), new StringLiteral("acquire: " + name, true)})),
            new FunctionCall(TypeName{"trace_int"},
                             ExprList({refcount(), new StringLiteral("  refcount: " + name, true)})),
        };
        release->body->items = {
            // NOTE: release gets called blindly on the lhs of any assignment. The lhs can be a null-initialized ref.
            // if (!this) return
            new If(new Identical(new ThisRef(), PointerLiteral::null()),
                   new Block("if",
                             {
                                 new Return(),
                             })),
            // --__refcount
            new Assign(refcount(), new Sub(refcount(), new IntegerLiteral(1))),

            new FunctionCall(TypeName{"trace_ptr"},
                             ExprList{new ThisRef(), new StringLiteral("release: " + name, true)}),
            new FunctionCall(TypeName{"trace_int"},
                             ExprList{refcount(), new StringLiteral("  refcount: " + name, true)}),

            // if (this.__refcount == 0)
            //     this.__dtor()
            new If(new Equal(refcount(), new IntegerLiteral(0)),
                   new Block("if",
                             NodeList<Node>{
                                 new FunctionCall(TypeName{"trace_ptr"},
                                                  ExprList{new ThisRef(), new StringLiteral("dtor: " + name, true)}),
                                 new MethodCall(new ThisRef(), {"__dtor"}),
                             })),
        };
        Node::pop_source();
    }

    Node* StructDef::clone() const {
        auto newStruct = new StructDef(*this);
        newStruct->acquire = newStruct->get_method("__acquire");
        newStruct->release = newStruct->get_method("__release");
        newStruct->destruct = newStruct->get_method("__dtor");
        return newStruct;
    }

    void StructDef::finish() {
        // Copy off whatever the user put in the ctor, if anything
        auto userCtor = std::move(construct->body->items);
        construct->body->items.clear();

        // Create the allocation for `this`, needs "size" variable value filled in once it is known at codegen time
        Node::push_source(source_loc);
        NodeList<Node> alloc_this = {
            new VariableDef(TypeName("u64"), "size", nullptr, true),
            new ThisDef(type, new FunctionCall(TypeName{"_pep_malloc"}, {new SymbolRef("size")})),
            new FunctionCall(TypeName{"trace_ptr"}, ExprList{new ThisRef(), new StringLiteral("ctor: " + name, true)}),
        };
        Node::pop_source();

        construct->body->items = std::move(alloc_this);

        // Fill in initializations
        for (auto& field : field_members) {
            construct->body->items.push_back(field);
        }

        // Restore user's instructions
        construct->body->items.append(userCtor);

        // Finally, ctor returns `this`
        construct->body->items.push_back(new Return(new SymbolRef("this")));

        // insert free as the last instruction in destruct
        destruct->body->items.push_back(new FunctionCall(TypeName{"_pep_free"}, ExprList{new ThisRef()}));

        method_members.push_back(release);
        method_members.push_back(acquire);
        method_members.push_back(destruct);
    }

    FieldDef* StructDef::get_field(const Ident& name) const {
        for (auto& field : field_members) {
            if (field->name == name)
                return field;
        }
        return nullptr;
    }

    MethodDef* StructDef::get_method(const Ident& name) const {
        for (auto& method : method_members) {
            if (method->name == name)
                return method;
        }
        return nullptr;
    }

    std::string StructDef::to_string() const {
        return llvm::formatv("{0}: {1}", node_name(), type.to_string());
    }

    std::string StructDef::dump(int indent) const {
        const char* sep = "\n";
        Vector<std::string> field_dump =
            Query(field_members).select<std::string>([indent](const auto& f) { return f->dump(indent + 2); });
        auto ctorStr = construct->dump(indent + 2);
        Vector<std::string> method_dump =
            Query(method_members).select<std::string>([indent](const auto& m) { return m->dump(indent + 2); });
        auto indentStr = repeat(" ", indent);
        auto structStr = std::string(llvm::formatv("{0} {1} {{", Node::dump(indent), type.to_string()));
        auto fieldsStr = llvm::join(field_dump.begin(), field_dump.end(), sep);
        auto methodsStr = llvm::join(method_dump.begin(), method_dump.end(), sep);
        return llvm::join_items(sep, structStr, fieldsStr, ctorStr, methodsStr, indentStr + "}");
    }

    std::string StructSpec::to_string() const {
        return llvm::formatv("{0}: {1}", node_name(), name);
    }

    std::string StructSpec::dump(int indent) const {
        auto indentStr = repeat(" ", indent);
        return indentStr + to_string();
    }

    std::string ExtensionDef::to_string() const {
        return llvm::formatv("{0}: {1}", node_name(), Target.name());
    }

    std::string ExtensionDef::dump(int indent) const {
        const char* sep = "\n";
        auto indentStr = repeat(" ", indent);
        Vector<std::string> method_dump =
            Query(method_members).select<std::string>([indent](const auto& m) { return m->dump(indent + 2); });
        auto extStr = std::string(llvm::formatv("{0} {1} {{", Node::dump(indent), Target.name()));
        auto methodsStr = llvm::join(method_dump.begin(), method_dump.end(), sep);
        return llvm::join_items(sep, extStr, methodsStr, indentStr + "}");
    }
} // namespace pepper::sema
