
#pragma once

#include <memory>

#include "Core/Common.h"
#include "Core/Vector.h"
#include "Parser/Parser.h"
#include "Sema/Model/Builder.h"

namespace pepper::sema {

    enum class ModuleKind {
        Main,
        SourceFile,
    };

    class Module {
      public:
        NodeList<Import> import_nodes;
        NodeList<StructDef> struct_defs;
        NodeList<TraitDecl> trait_decls;
        NodeList<StructSpec> struct_specs;
        NodeList<ExtensionDef> extension_defs;
        NodeList<FunctionDef> function_defs;
        NodeList<ExternFunctionRef> extern_refs;
        NodeList<FunctionSpec> func_specs;
        std::unique_ptr<Builder> tree_builder;
        ModuleKind module_type;

      public:
        Module(ModuleKind type);
        ~Module();

        Builder* builder(ParserTracer* tracer = nullptr);

        void insert(Node* root);

        using import_iterator = typename NodeList<Import>::iterator;
        using const_import_iterator = typename NodeList<Import>::const_iterator;

        const NodeList<Import>& imports() const {
            return import_nodes;
        }

        const_import_iterator imports_begin() const {
            return import_nodes.begin();
        }

        const_import_iterator imports_end() const {
            return import_nodes.end();
        }

        import_iterator imports_begin() {
            return import_nodes.begin();
        }

        import_iterator imports_end() {
            return import_nodes.end();
        }

        const NodeList<StructDef>& structs() const {
            return struct_defs;
        }

        const NodeList<TraitDecl>& traits() const {
            return trait_decls;
        }

        const NodeList<StructSpec>& structSpecs() const {
            return struct_specs;
        }

        const NodeList<ExtensionDef>& extensions() const {
            return extension_defs;
        }

        const NodeList<FunctionDef>& functions() const {
            return function_defs;
        }

        const NodeList<FunctionSpec>& function_specs() const {
            return func_specs;
        }

        const NodeList<ExternFunctionRef>& externs() const {
            return extern_refs;
        }

        NodeList<Node> roots() const;

        bool parse(const ParseState& state, const parser::ModuleNode* parse_tree);

        void merge(Ref<Module> source);

        void dump() const;
    };
} // namespace pepper::sema

#define PEP_TRACE_AST(fmt, ...) PEP_TRACE(TraceChannel::AST, fmt, __VA_ARGS__)
