#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::sema {
    struct ResolveImplicitTypes : public Transformer {
        DECLARE_RTTI(ResolveImplicitTypes, Transformer);

        struct TypeReplacer : Visitor {
            llvm::StringMap<StructDef*> structs;

            struct Scope {
                Ident name;
                llvm::StringMap<Symbol*> symbols;
                FunctionDef* function;

                Scope(const Ident& name, FunctionDef* function = nullptr)
                    : name(name)
                    , function(function) {}
            };

            Vector<Scope> Stack;

            TypeReplacer(llvm::StringMap<StructDef*>&& structs)
                : structs(std::move(structs)) {
                Stack.emplace_back("Globals");
            }

            void push_scope(const Ident& name, FunctionDef* function = nullptr) {
                Stack.emplace_back(name, function);
            }

            void pop_scope() {
                Stack.pop_back();
            }

            Scope& locals() {
                return Stack.back();
            }

            std::string scopePath() const {
                auto names = Query(Stack).range(1).select<std::string>([](const auto& s) { return s.name; });
                return llvm::formatv("{0:$[/]}", llvm::make_range(names.begin(), names.end()));
            }

            Symbol* findSymbol(const Ident& name) const {
                for (const auto& scope : llvm::reverse(Stack)) {
                    if (auto sym = scope.symbols.lookup(name))
                        return sym;
                }
                return nullptr;
            }

            TypeName findSymbolType(const Ident& name) const {
                if (name == "this") {
                    auto function = getFunction();
                    if (auto method = function->as<MethodDef>())
                        if (auto st = method->parent)
                            return st.value() ? st->type : st.target();
                }
                for (const auto& scope : llvm::reverse(Stack)) {
                    if (auto sym = scope.symbols.lookup(name))
                        return sym->type;
                    if (auto function = scope.function) {
                        for (auto& param : function->parameters) {
                            if (param.name == name)
                                return param.type;
                        }
                    }
                }
                // If the symbol is actually the name of a struct, resolve that instead
                if (auto st = structs.lookup(name)) {
                    return st->name;
                }
                return {};
            }

            FunctionDef* getFunction() const {
                for (const auto& scope : llvm::reverse(Stack)) {
                    if (scope.function)
                        return scope.function;
                }
                return nullptr;
            }

            StructDef* findStruct(const Ident& name) const {
                return structs.lookup(name);
            }

            TypeName typeOfExpr(Expression* expr) const {
                if (!expr->type().empty() && expr->type() != TypeName::Auto) {
                    return expr->type();
                }
                if (auto memRef = expr->as<MemberRef>()) {
                    auto lhsType = typeOfExpr(memRef->lhs);
                    if (lhsType != TypeName::Auto) {
                        if (auto st = findStruct(lhsType.to_string())) {
                            for (const auto& field : st->field_members) {
                                if (field->name == memRef->id) {
                                    return field->type;
                                }
                            }
                        }
                        PEP_TRACE_AST("Failed to resolve member {0}.{1}", lhsType.to_string(), memRef->id);
                    }
                }
                if (auto symRef = expr->as<SymbolRef>()) {
                    // symbol lookup is best-effort, sometimes type can't be known yet
                    return findSymbolType(symRef->id);
                }
                if (auto call = expr->as<MethodCall>()) {
                    if (auto st = findStruct(typeOfExpr(call->This).to_string())) {
                        if (auto method = call->Target.value())
                            return method->return_type;
                    }
                }
                return TypeName::Auto;
                // throw CompileError(expr->Source, "Unknown expression type in {0}", expr->rtti()->name());
            }

            void enterNode(NodeRef& node) override {
                if (auto function = node->as<FunctionDef>())
                    push_scope(function->name, function);
                if (auto block = node->as<Block>())
                    push_scope("block");
                if (auto st = node->as<StructDef>()) {
                    push_scope(st->name);
                    for (auto& field : st->field_members) {
                        locals().symbols[field->name] = field;
                    }
                }
            }

            void exitNode(NodeRef& node) override {
                if (node->is<FunctionDef>() || node->is<Block>() || node->is<StructDef>())
                    pop_scope();
            }

            void visitNode(NodeRef& node) override {
                // Record all local symbols as they come into existence
                if (auto sym = node->as<Symbol>()) {
                    locals().symbols[sym->name] = sym;
                }

                // Update all variable declarations
                if (auto var = node->as<VariableDef>()) {
                    if (var->type == TypeName::Auto) {
                        auto varType = typeOfExpr(var->default_value);
                        if (!varType.empty()) {
                            var->type = varType;
                            PEP_TRACE_AST("Resolved var {0}/{1} -> {2}", scopePath(), var->name, var->type);
                            return;
                        }

                        PEP_TRACE_AST(
                            "Unable to resolve type for var {0}/{1}, resolution pending", scopePath(), var->name);
                    }
                }

                // Update variable references
                if (auto symRef = node->as<SymbolRef>()) {
                    if (symRef->type() == TypeName::Auto) {
                        auto symType = typeOfExpr(symRef);
                        if (!symType.empty()) {
                            symRef->ty = symType;
                            PEP_TRACE_AST("Resolved ref {0}/{1} -> {2}", scopePath(), symRef->id, symRef->ty);
                            return;
                        }

                        PEP_TRACE_AST(
                            "Unable to resolve type for ref {0}/{1}, resolution pending", scopePath(), symRef->id);
                    }
                }
            }
        };

        void run(Ref<Module> module) override {
            llvm::StringMap<StructDef*> structs;
            for (auto& st : module->structs()) {
                structs[st->type.to_string()] = st;
            }

            auto replacer = TypeReplacer(std::move(structs));
            for (auto& st : module->structs()) {
                replacer.visit(st);
            }
            for (auto& fn : module->functions()) {
                replacer.visit(fn);
            }
        }
    };
} // namespace pepper::sema
