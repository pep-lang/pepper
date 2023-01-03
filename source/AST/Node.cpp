//
// Created by Justin Boswell on 1/1/23.
//

#include "AST/Node.h"

#include "Core/Query.h"

namespace pepper::ast {
    std::string TypeName::toString() const {
        std::string genericTypes;
        if (!GenericTypes.empty()) {
            Vector<std::string> genericStrings =
                Query(GenericTypes).select<std::string>([](auto& a) { return a.toString(); });
            genericTypes = "<" + llvm::join(genericStrings.begin(), genericStrings.end(), ", ") + ">";
        }
        return Name + genericTypes;
    }

    void TypeName::replace(const Ident& genericParam, const TypeName& genericArg) {
        if (Name == genericParam) {
            Name = genericArg;
        }
        for (auto& arg : GenericTypes) {
            arg.replace(genericParam, genericArg);
        }
    }

    std::string Node::sourcePrefix(int width, int indent) const {
        width = (width >= 0) ? width : Source.File.size() + 10;
        width += indent;
        std::string src = Source.toString();
        std::string padding = repeat(" ", width - src.size());
        return llvm::formatv("{0}:{1}", Source.toString(), padding);
    }

    std::string Node::toString() const {
        return llvm::formatv("{0}: ", rtti()->name());
    }

    std::string Node::dump(int indent) const {
        return llvm::formatv("{0}{1} ", repeat(" ", indent), rtti()->name());
    }
} // namespace pepper::ast
