

#include <utility>

#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Vector.h"
#include "Sema/Model/Builder.h"
#include "Sema/Model/Module.h"
#include "Sema/Model/Nodes.h"
#include "Tracer.h"
#include "llvm/ADT/STLExtras.h"

namespace pepper::sema {
    class BuilderImpl : public Builder {
        using TraceScope = debug::Tracer<ParserScope>::Scope;

        struct Scope {
            const Ident name;

            ScopeTarget* target = nullptr;

            Node* parent = nullptr;
            Block* block = nullptr;
            Vector<Node*> lvalues;
            Vector<Node*> rvalues;
            std::unique_ptr<TraceScope> parser_scope;

            explicit Scope(Ident name = "Anonymous")
                : name(std::move(name)) {}
        };

        Module& ast;
        Vector<Ref<Scope>> scope_stack;

      public:
        explicit BuilderImpl(Module& _ast, ParserTracer* tracer)
            : Builder(tracer)
            , ast(_ast) {
            auto globals = Ref<Scope>::create("Global");
            scope_stack.emplace_back(globals); // global scope
        }

        SourceLocation location() const override {
            return Node::get_source_location();
        }

        ScopeTarget* target() override {
            for (const auto& scope : llvm::reverse(scope_stack)) {
                if (scope->target) {
                    return scope->target;
                }
            }
            return nullptr;
        }

        void push_rvalue(Node* value) override {
            auto& scope = scope_stack.back();
            //            std::cout << "rpush: " << scope->Ident << ": " << value->to_string() << std::endl;
            scope->rvalues.push_back(value);
        }

        Node* pop_rvalue() override {
            auto& scope = scope_stack.back();
            if (scope->rvalues.empty()) {
                Messages::report<Warning>(location(), "Attempted to pop empty r-value stack");
                return nullptr;
            }
            auto val = scope->rvalues.pop_back_val();
            //            std::cout << "rpop: " << scope->Ident << ": " << val->rtti()->name() << std::endl;
            return val;
        }

        Node* peek_rvalue(unsigned int idx = 0) const override {
            const auto& scope = scope_stack.back();
            const int maxDepth = (int)scope->rvalues.size() - 1;
            if (idx > maxDepth) {
                return nullptr;
            }
            auto val = scope->rvalues[maxDepth - idx];
            //            std::cout << "rpeek: " << scope->Ident << " " << idx << "/" << maxDepth + 1 << ": " <<
            //            val->rtti()->name()
            //                      << std::endl;
            return val;
        }

        void push_lvalue(Node* value) override {
            auto& scope = scope_stack.back();
            //            std::cout << "lpush: " << scope->Ident << ": " << value->to_string() << std::endl;
            scope->lvalues.push_back(value);
        }

        Node* pop_lvalue() override {
            auto& scope = scope_stack.back();
            if (scope->lvalues.empty()) {
                throw InternalCompilerError(location(), "Attempted to pop empty l-value stack");
            }
            auto val = scope->lvalues.pop_back_val();
            //            std::cout << "lpop: " << scope->Ident << ": " << val->rtti()->name() << std::endl;
            return val;
        }

        Node* peek_lvalue(unsigned int idx = 0) const override {
            const auto& scope = scope_stack.back();
            const int maxDepth = (int)scope->lvalues.size() - 1;
            if (int(idx) > maxDepth) {
                return nullptr;
            }
            auto val = scope->lvalues[maxDepth - idx];
            //            std::cout << "lpeek: " << scope->Ident << " " << idx << "/" << maxDepth + 1 << ": " <<
            //            val->rtti()->name()
            //                      << std::endl;
            return val;
        }

        template <typename Arg0, typename... Args>
        void trace(std::string_view format, Arg0&& arg0, Args&&... args) {
            trace(fmt::format(fmt::runtime(format), std::forward<Arg0>(arg0), std::forward<Args>(args)...));
        }

        void trace(const std::string& msg) const {
            tracer->trace(msg);
        }

        void trace(const Node* node) const {
            trace(node->to_string());
        }

        template <typename Arg0, typename... Args>
        auto trace_push(std::string_view format, Arg0&& arg0, Args&&... args) {
            return trace_push(fmt::format(fmt::runtime(format), std::forward<Arg0>(arg0), std::forward<Args>(args)...));
        }

        auto trace_push(const std::string& scope = {}) const {
            return std::make_unique<TraceScope>(std::move(tracer->pushln(scope)));
        }

        template <typename Arg0, typename... Args>
        void trace_pop(std::string_view format, Arg0&& arg0, Args&&... args) {
            trace_pop(fmt::format(fmt::runtime(format), std::forward<Arg0>(arg0), std::forward<Args>(args)...));
        }

        void trace_pop(const std::string& msg = {}) const {
            if (!msg.empty())
                trace(msg);
            tracer->pop();
        }

        void begin_struct(StructDef* structDef) override {
            auto& scope = scope_stack.back();
            structDef->source_loc = location();
            begin_scope(structDef->name);
            auto& structScope = scope_stack.back();
            structScope->target = structDef;
        }

        void end_struct() override {
            auto& scope = scope_stack.back();
            auto structDef = scope->target->to<StructDef>();
            structDef->finish();
            ast.insert(structDef);
            end_scope();
        }

        void begin_trait(TraitDecl* trait) override {
            begin_scope(trait->name);
            auto& traitScope = scope_stack.back();
            traitScope->target = trait;
        }

        void end_trait() override {
            auto& scope = scope_stack.back();
            auto trait = scope->target->to<TraitDecl>();
            ast.insert(trait);
            end_scope();
        }

        void begin_extension(ExtensionDef* ext) override {
            auto name = ext->Target.to_string();
            if (auto traitDef = ext->as<TraitDef>())
                name += llvm::formatv(": {0}", traitDef->decl.to_string());
            begin_scope(name);
            auto& extScope = scope_stack.back();
            extScope->target = ext;
        }

        void end_extension() override {
            auto& scope = scope_stack.back();
            auto extension = scope->target->to<ExtensionDef>();
            ast.insert(extension);
            end_scope();
        }

        void begin_function(FunctionNode* func) override {
            auto& scope = scope_stack.back();

            // set the parent to the enclosing function for lambdas, its null otherwise
            func->source_loc = location();
            begin_scope(func->type.to_string());
            auto& fnScope = scope_stack.back();
            fnScope->target = func;

            if (auto funcDef = func->as<FunctionDef>()) {
                funcDef->body->source_loc = func->source_loc;
                fnScope->block = funcDef->body;
            }
        }

        void end_function() override {
            auto& scope = scope_stack.back();
            auto* function = scope->target->to<FunctionNode>();
            end_scope();
            if (auto tgt = target()) {
                if (auto method = function->as<MethodDecl>()) {
                    tgt->add_method(method);
                } else {
                    tgt->add_function(function->as<FunctionDef>());
                }
            } else {
                ast.insert(function);
            }
        }

        void begin_block(Block* block) override {
            begin_scope(block->name);
            auto scope = scope_stack.back();
            scope->block = block;
        }

        void end_block() override {
            end_scope();
        }

        Block* block() const override {
            const auto& scope = scope_stack.back();
            return scope->block;
        }

        void begin_scope(const Ident& name = "Anonymous") override {
            auto top = scope_stack.back();
            const std::string newScopeName = llvm::formatv("{0}.{1}", top->name, name);
            auto scope = Ref<Scope>::create(newScopeName);
            scope_stack.emplace_back(scope);
            scope->parser_scope = trace_push(newScopeName);
            // Messages::indent(TraceChannel::Parser);
        }

        void end_scope() override {
            auto scope = scope_stack.pop_back_val();
            // Messages::outdent(TraceChannel::Parser);
            trace("end scope({})", scope->name);
        }

        void symbol(VariableDef* var) override {
            auto& scope = scope_stack.back();
            if (block()) {
                block()->items.push_back(var);
            } else {
                assert(target());
                target()->add_field(var);
            }

            trace(var);
        }

        void insert(Node* expr) override {
            // If there's an l-value waiting for an expression value, it'll pull it
            // off the stack when its terminal completes
            if (peek_lvalue()) {
                push_rvalue(expr->as<Expression>());
                return;
            }

            if (auto* cur_block = block()) {
                cur_block->items.push_back(expr);
            } else {
                ast.insert(expr);
            }
            trace(expr);
        }

        void import(Import* import) override {
            ast.insert(import);
            trace(import);
        }
    };

    Builder* Module::builder(ParserTracer* tracer) {
        if (!tree_builder) {
            tree_builder = std::make_unique<BuilderImpl>(*this, tracer);
        }

        return tree_builder.get();
    }
} // namespace pepper::sema
