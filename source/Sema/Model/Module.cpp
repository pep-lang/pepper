
#include "Sema/Model/Module.h"
#include <filesystem>

#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Sema/Model/Node.h"
#include "Sema/Model/Parser.h"
#include "Sema/Model/Struct.h"
#include "Sema/Model/Tracer.h"

namespace llvm {
    auto format_as(StringRef ref) {
        return std::string_view(ref);
    }
} // namespace llvm

namespace pepper::sema {

    Module::Module(ModuleKind type)
        : module_type(type) {}

    Module::~Module() {
        if (module_type == ModuleKind::Main) {
            NodeHeap::clear();
        }
    }

    void Module::insert(Node* root) {
        if (root->is<Import>()) {
            import_nodes.push_back(root->as<Import>());
        } else if (root->is<StructDef>()) {
            struct_defs.push_back(root->as<StructDef>());
        } else if (root->is<TraitDecl>()) {
            trait_decls.push_back(root->as<TraitDecl>());
        } else if (root->is<StructSpec>()) {
            struct_specs.push_back(root->as<StructSpec>());
        } else if (root->is<ExtensionDef>()) {
            extension_defs.push_back(root->as<ExtensionDef>());
        } else if (root->is<FunctionDef>()) {
            function_defs.push_back(root->as<FunctionDef>());
        } else if (root->is<ExternFunctionRef>()) {
            extern_refs.push_back(root->as<ExternFunctionRef>());
        } else if (root->is<FunctionSpec>()) {
            func_specs.push_back(root->as<FunctionSpec>());
        } else {
            throw InternalCompilerError("Unknown AST root node: {0}", root->to_string());
        }
    }

    void Module::merge(Ref<Module> source) {
        import_nodes.merge(source->import_nodes);
        struct_defs.merge(source->struct_defs);
        trait_decls.merge(source->trait_decls);
        struct_specs.merge(source->struct_specs);
        extension_defs.merge(source->extension_defs);
        function_defs.merge(source->function_defs);
        extern_refs.merge(source->extern_refs);
        func_specs.merge(source->func_specs);
    }

    NodeList<Node> Module::roots() const {
        NodeList<Node> all;
        for (auto& i : import_nodes)
            all.emplace_back(i);
        for (auto& s : struct_defs)
            all.emplace_back(s);
        for (auto& t : trait_decls)
            all.emplace_back(t);
        for (auto& s : struct_specs)
            all.emplace_back(s);
        for (auto& ext : extension_defs)
            all.emplace_back(ext);
        for (auto& fn : function_defs)
            all.emplace_back(fn);
        for (auto& fn : extern_refs)
            all.emplace_back(fn);
        for (auto& fs : func_specs)
            all.emplace_back(fs);

        return all;
    }

    void Module::dump() const {
        if (PEP_TRACING(TraceChannel::AST)) {
            for (const auto& root : roots()) {
                PEP_TRACE_AST(root->dump());
                PEP_TRACE_AST({}); // add a newline between roots
            }
        }
    }

    bool Module::parse(const ParseState& state, const parser::ModuleNode* parse_tree) {
        auto parser = Parser::create(state, this, parse_tree);
        return parser->parse();
    }
} // namespace pepper::sema
