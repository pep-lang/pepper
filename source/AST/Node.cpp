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

    void TypeName::specialize(const Specialization::GenericTypeMap& map) {
        for (const auto& generic : map) {
            replace(generic.getKey().str(), generic.getValue());
        }
    }

    std::string Node::source(int width, int indent, const char* sep) const {
        if (Source.File.empty()) {
            return {""};
        }
        width = (width >= 0) ? width : (int)Source.File.size() + 10;
        width += indent;
        std::string src = Source.toString();
        std::string padding = repeat(" ", width - src.size());
        return llvm::formatv("{0}{1}{2}", src, sep, padding);
    }

    std::string Node::toString() const {
        return llvm::formatv("{0}: ", rtti()->name());
    }

    std::string Node::dump(int indent) const {
        return llvm::formatv("{0}{1}", repeat(" ", indent), rtti()->name());
    }

    Ref<Node> Node::clone() const {
        return Ref<Node>{((const RttiInstance<Node>*)rtti())->clone(this)};
    }

    void Symbol::specialize(const Specialization& spec) {
        Type.specialize(spec.TypeMap);
    }
} // namespace pepper::ast
