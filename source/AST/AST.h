
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
        NodeList<StructSpec> StructSpecs;
        NodeList<ExtensionDef> Extensions;
        NodeList<FunctionDef> Functions;
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

        using struct_iterator = typename NodeList<StructDef>::iterator;
        using const_struct_iterator = typename NodeList<StructDef>::const_iterator;

        const NodeList<StructDef>& structs() const {
            return Structs;
        }

        const_struct_iterator structs_begin() const {
            return Structs.begin();
        }

        const_struct_iterator structs_end() const {
            return Structs.end();
        }

        struct_iterator structs_begin() {
            return Structs.begin();
        }

        struct_iterator structs_end() {
            return Structs.end();
        }

        using sspec_iterator = typename NodeList<StructSpec>::iterator;
        using const_sspec_iterator = typename NodeList<StructSpec>::const_iterator;

        const NodeList<StructSpec>& structSpecs() const {
            return StructSpecs;
        }

        const_sspec_iterator sspecs_begin() const {
            return StructSpecs.begin();
        }

        const_sspec_iterator sspecs_end() const {
            return StructSpecs.end();
        }

        sspec_iterator sspecs_begin() {
            return StructSpecs.begin();
        }

        sspec_iterator sspecs_end() {
            return StructSpecs.end();
        }

        using extension_iterator = typename NodeList<ExtensionDef>::iterator;
        using const_extension_iterator = typename NodeList<ExtensionDef>::const_iterator;

        const NodeList<ExtensionDef>& extensions() const {
            return Extensions;
        }

        const_extension_iterator extensions_begin() const {
            return Extensions.begin();
        }

        const_extension_iterator extensions_end() const {
            return Extensions.end();
        }

        extension_iterator extensions_begin() {
            return Extensions.begin();
        }

        extension_iterator extensions_end() {
            return Extensions.end();
        }

        using function_iterator = typename NodeList<FunctionDef>::iterator;
        using const_function_iterator = typename NodeList<FunctionDef>::const_iterator;

        const NodeList<FunctionDef>& functions() const {
            return Functions;
        }

        const_function_iterator functions_begin() const {
            return Functions.begin();
        }

        const_function_iterator functions_end() const {
            return Functions.end();
        }

        function_iterator functions_begin() {
            return Functions.begin();
        }

        function_iterator functions_end() {
            return Functions.end();
        }

        using fspec_iterator = typename NodeList<FunctionSpec>::iterator;
        using const_fspec_iterator = typename NodeList<FunctionSpec>::const_iterator;

        const NodeList<FunctionSpec>& functionSpecs() const {
            return FunctionSpecs;
        }

        const_fspec_iterator fspecs_begin() const {
            return FunctionSpecs.begin();
        }

        const_fspec_iterator fspecs_end() const {
            return FunctionSpecs.end();
        }

        fspec_iterator fspecs_begin() {
            return FunctionSpecs.begin();
        }

        fspec_iterator fspecs_end() {
            return FunctionSpecs.end();
        }

        NodeList<Node> roots() const;

        void merge(Ref<AST> source);

        void dump() const;
    };
} // namespace pepper::ast

#define PEP_TRACE_AST(fmt, ...) PEP_TRACE(TraceChannel::AST, fmt, __VA_ARGS__)
