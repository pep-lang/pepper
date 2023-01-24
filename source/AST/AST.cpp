
#include "AST/AST.h"

#include "AST/Struct.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"

namespace pepper::ast {

    AST::AST(TreeType type)
        : Type(type) {}

    AST::~AST() {
        if (Type == TreeType::Main) {
            NodeHeap::Clear();
        }
    }

    void AST::insert(Node* root) {
        if (root->is<Import>()) {
            Imports.push_back(root->as<Import>());
        } else if (root->is<StructDef>()) {
            Structs.push_back(root->as<StructDef>());
        } else if (root->is<StructSpec>()) {
            StructSpecs.push_back(root->as<StructSpec>());
        } else if (root->is<ExtensionDef>()) {
            Extensions.push_back(root->as<ExtensionDef>());
        } else if (root->is<FunctionDef>()) {
            Functions.push_back(root->as<FunctionDef>());
        } else if (root->is<FunctionSpec>()) {
            FunctionSpecs.push_back(root->as<FunctionSpec>());
        } else {
            throw InternalCompilerError("Unknown AST root node: {0}", root->toString());
        }
    }

    void AST::merge(Ref<AST> source) {
        Imports.merge(source->Imports);
        Structs.merge(source->Structs);
        StructSpecs.merge(source->StructSpecs);
        Extensions.merge(source->Extensions);
        Functions.merge(source->Functions);
        FunctionSpecs.merge(source->FunctionSpecs);
    }

    NodeList<Node> AST::roots() const {
        NodeList<Node> all;
        for (auto i = imports_begin(); i != imports_end(); ++i)
            all.emplace_back(*i);
        for (auto s = structs_begin(); s != structs_end(); ++s)
            all.emplace_back(*s);
        for (auto sspec = sspecs_begin(); sspec != sspecs_end(); ++sspec)
            all.emplace_back(*sspec);
        for (auto ext = extensions_begin(); ext != extensions_end(); ++ext)
            all.emplace_back(*ext);
        for (auto fn = functions_begin(); fn != functions_end(); ++fn)
            all.emplace_back(*fn);
        for (auto fs = fspecs_begin(); fs != fspecs_end(); ++fs)
            all.emplace_back(*fs);

        return all;
    }

    void AST::dump() const {
        if (PEP_TRACING(TraceChannel::AST)) {
            for (const auto& root : roots()) {
                PEP_TRACE_AST(root->dump());
                PEP_TRACE_AST({}); // add a newline between roots
            }
        }
    }
} // namespace pepper::ast
