#pragma once

#include "Model/Module.h"
#include "Parser/LexyParser.h"

namespace pepper::sema {
    class ModelBuilder {
      public:
        explicit ModelBuilder(const std::shared_ptr<ast::Module>& ast_module, ModuleKind module_kind);
        ~ModelBuilder() = default;

        std::shared_ptr<Module> build();

        std::shared_ptr<ast::Module> ast;
        std::shared_ptr<Module> module;
    };
} // namespace pepper::sema
