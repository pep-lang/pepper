
#pragma once

#include <memory>
#include <string>

#include "AST/Builder.h"
#include "Core/Common.h"
#include "Core/Vector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/ilist.h"

namespace pepper::ast {

    class AST {
      public:
        enum class TreeType {
            Main,
            SourceFile,
        };

      private:
        NodeList<Import> Imports;
        NodeList<StructDef> Structs;
        NodeList<TraitDecl> Traits;
        NodeList<StructSpec> StructSpecs;
        NodeList<ExtensionDef> Extensions;
        NodeList<FunctionDef> Functions;
        NodeList<ExternFunctionDef> Externs;
        NodeList<FunctionSpec> FunctionSpecs;
        std::unique_ptr<Builder> TreeBuilder;
        TreeType Type;

      public:
        AST(TreeType type = TreeType::Main);
        ~AST();

        Builder* builder();

        void insert(Node* root);

        using import_iterator = typename NodeList<Import>::iterator;
        using const_import_iterator = typename NodeList<Import>::const_iterator;

        const NodeList<Import>& imports() const {
            return Imports;
        }

        const_import_iterator imports_begin() const {
            return Imports.begin();
        }

        const_import_iterator imports_end() const {
            return Imports.end();
        }

        import_iterator imports_begin() {
            return Imports.begin();
        }

        import_iterator imports_end() {
            return Imports.end();
        }

        const NodeList<StructDef>& structs() const {
            return Structs;
        }

        const NodeList<TraitDecl>& traits() const {
            return Traits;
        }

        const NodeList<StructSpec>& structSpecs() const {
            return StructSpecs;
        }

        const NodeList<ExtensionDef>& extensions() const {
            return Extensions;
        }

        const NodeList<FunctionDef>& functions() const {
            return Functions;
        }

        const NodeList<FunctionSpec>& functionSpecs() const {
            return FunctionSpecs;
        }

        const NodeList<ExternFunctionDef>& externs() const {
            return Externs;
        }

        NodeList<Node> roots() const;

        void merge(Ref<AST> source);

        void dump() const;
    };
} // namespace pepper::ast

#define PEP_TRACE_AST(fmt, ...) PEP_TRACE(TraceChannel::AST, fmt, __VA_ARGS__)
