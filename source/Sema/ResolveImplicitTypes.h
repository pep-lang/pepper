#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ResolveImplicitTypes : public Transformer {
        DECLARE_RTTI(ResolveImplicitTypes, Transformer);

        struct TypeReplacer : Visitor {
            llvm::StringMap<StructDef*> Structs;

            struct Scope {
                Ident Name;
                llvm::StringMap<Symbol*> Symbols;
                FunctionDef* Function;

                Scope(const Ident& name, FunctionDef* function = nullptr)
                    : Name(name)
                    , Function(function) {}
            };

            Vector<Scope> Stack;

            TypeReplacer(llvm::StringMap<StructDef*>&& structs)
                : Structs(std::move(structs)) {
                Stack.emplace_back("Globals");
            }

            void pushScope(const Ident& name, FunctionDef* function = nullptr) {
                Stack.emplace_back(name, function);
            }

            void popScope() {
                Stack.pop_back();
            }

            Scope& locals() {
                return Stack.back();
            }

            std::string scopePath() const {
                auto names = Query(Stack).range(1).select<std::string>([](const auto& s) { return s.Name; });
                return llvm::formatv("{0:$[/]}", llvm::make_range(names.begin(), names.end()));
            }

            Symbol* findSymbol(const Ident& name) const {
                for (const auto& scope : llvm::reverse(Stack)) {
                    if (auto sym = scope.Symbols.lookup(name))
                        return sym;
                }
                return nullptr;
            }

            TypeName findSymbolType(const Ident& name) const {
                if (name == "this") {
                    auto function = getFunction();
                    if (auto method = function->as<MethodDef>())
                        if (auto st = method->Struct)
                            return st.value() ? st->Type : st.target();
                }
                for (const auto& scope : llvm::reverse(Stack)) {
                    if (auto sym = scope.Symbols.lookup(name))
                        return sym->Type;
                    if (auto function = scope.Function) {
                        for (auto& param : function->Parameters) {
                            if (param.Name == name)
                                return param.Type;
                        }
                    }
                }
                // If the symbol is actually the name of a struct, resolve that instead
                if (auto st = Structs.lookup(name)) {
                    return st->Name;
                }
                return {};
            }

            FunctionDef* getFunction() const {
                for (const auto& scope : llvm::reverse(Stack)) {
                    if (scope.Function)
                        return scope.Function;
                }
                return nullptr;
            }

            StructDef* findStruct(const Ident& name) const {
                return Structs.lookup(name);
            }

            TypeName typeOfExpr(Expression* expr) const {
                if (!expr->type().empty() && expr->type() != TypeName::Auto) {
                    return expr->type();
                }
                if (auto memRef = expr->as<MemberRef>()) {
                    auto lhsType = typeOfExpr(memRef->LHS);
                    if (lhsType != TypeName::Auto) {
                        if (auto st = findStruct(lhsType.toString())) {
                            for (const auto& field : st->Fields) {
                                if (field->Name == memRef->Name) {
                                    return field->Type;
                                }
                            }
                        }
                        PEP_TRACE_AST("Failed to resolve member {0}.{1}", lhsType.toString(), memRef->Name);
                    }
                }
                if (auto symRef = expr->as<SymbolRef>()) {
                    // symbol lookup is best-effort, sometimes type can't be known yet
                    return findSymbolType(symRef->Name);
                }
                if (auto call = expr->as<MethodCall>()) {
                    if (auto st = findStruct(typeOfExpr(call->This).toString())) {
                        if (auto method = call->Target.value())
                            return method->ReturnType;
                    }
                }
                return TypeName::Auto;
                // throw CompileError(expr->Source, "Unknown expression type in {0}", expr->rtti()->name());
            }

            void enterNode(NodeRef& node) override {
                if (auto function = node->as<FunctionDef>())
                    pushScope(function->Name, function);
                if (auto block = node->as<Block>())
                    pushScope("block");
                if (auto st = node->as<StructDef>()) {
                    pushScope(st->Name);
                    for (auto& field : st->Fields) {
                        locals().Symbols[field->Name] = field;
                    }
                }
            }

            void exitNode(NodeRef& node) override {
                if (node->is<FunctionDef>() || node->is<Block>() || node->is<StructDef>())
                    popScope();
            }

            void visitNode(NodeRef& node) override {
                // Record all local symbols as they come into existence
                if (auto sym = node->as<Symbol>()) {
                    locals().Symbols[sym->Name] = sym;
                }

                // Update all variable declarations
                if (auto var = node->as<VariableDef>()) {
                    if (var->Type == TypeName::Auto) {
                        auto varType = typeOfExpr(var->Default);
                        if (!varType.empty()) {
                            var->Type = varType;
                            PEP_TRACE_AST("Resolved var {0}/{1} -> {2}", scopePath(), var->Name, var->Type);
                            return;
                        }

                        PEP_TRACE_AST(
                            "Unable to resolve type for var {0}/{1}, resolution pending", scopePath(), var->Name);
                    }
                }

                // Update variable references
                if (auto symRef = node->as<SymbolRef>()) {
                    if (symRef->type() == TypeName::Auto) {
                        auto symType = typeOfExpr(symRef);
                        if (!symType.empty()) {
                            symRef->Type = symType;
                            PEP_TRACE_AST("Resolved ref {0}/{1} -> {2}", scopePath(), symRef->Name, symRef->Type);
                            return;
                        }

                        PEP_TRACE_AST(
                            "Unable to resolve type for ref {0}/{1}, resolution pending", scopePath(), symRef->Name);
                    }
                }
            }
        };

        void run(Ref<AST> parseTree) override {
            llvm::StringMap<StructDef*> structs;
            for (auto& st : parseTree->structs()) {
                structs[st->Type.toString()] = st;
            }

            auto replacer = TypeReplacer(std::move(structs));
            for (auto& st : parseTree->structs()) {
                replacer.visit(st);
            }
            for (auto& fn : parseTree->functions()) {
                replacer.visit(fn);
            }
        }
    };
} // namespace pepper::ast
