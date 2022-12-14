
#include "AST/AST.h"

#include "AST/Nodes.h"

using namespace ast;

class BuilderImpl : public AST::Builder {
    AST& ast;

  public:
    BuilderImpl(AST& _ast)
        : ast(_ast) {
    }

    Builder* startFunction(Ref<FunctionDef> func) override {
        return this;
    }

    Builder* endFunction() {
        return this;
    }

    Builder* variable(Ref<ast::VariableDecl> var) {
        return this;
    }

    Builder* expression(Ref<ast::Expression> expr) {
        return this;
    }
};

AST::AST() {
}

Ref<AST::Builder> AST::builder() {
    return std::make_shared<BuilderImpl>(*this);
}
