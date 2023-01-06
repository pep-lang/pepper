//
// Created by Justin Boswell on 1/1/23.
//

#include "AST/Node.h"
#include <regex>

#include "Core/Exceptions.h"
#include "Core/Query.h"

namespace pepper::ast {
    const TypeName TypeName::Void = TypeName{"void"};
    const TypeName TypeName::Auto = TypeName{"__auto"};
    const TypeName TypeName::Bool = TypeName{"bool"};
    const TypeName TypeName::VoidPtr = TypeName{"void*"};
    const TypeName TypeName::Int8 = TypeName{"i8"};
    const TypeName TypeName::UInt8 = TypeName{"u8"};
    const TypeName TypeName::Int32 = TypeName{"i32"};
    const TypeName TypeName::UInt32 = TypeName{"u32"};
    const TypeName TypeName::Int64 = TypeName{"i64"};
    const TypeName TypeName::UInt64 = TypeName{"u64"};
    const TypeName TypeName::Double = TypeName{"f64"};
    const TypeName TypeName::Float = TypeName{"f32"};

    const TypeName& TypeName::Widest(const TypeName& lhs, const TypeName& rhs) {
        struct NumericTypeName {
            const TypeName* Name;
            const unsigned Width = -1;
            const bool isSigned = true;
            const bool isFloat = false;
        };

        static llvm::StringMap<NumericTypeName> NumericTypes = {
            {"i1", {&TypeName::Bool, 1}},
            {"i8", {&TypeName::Int8, 8}},
            {"u8", {&TypeName::UInt8, 8, false}},
            {"i32", {&TypeName::Int32, 32}},
            {"u32", {&TypeName::UInt32, 32, false}},
            {"i64", {&TypeName::Int64, 64}},
            {"u64", {&TypeName::UInt64, 64}},
            {"f32", {&TypeName::Float, 32, true, true}},
            {"f64", {&TypeName::Double, 64, true, true}},
        };

        assert(lhs.GenericTypes.empty() && rhs.GenericTypes.empty());

        const auto lhsName = lhs.Name == "bool" ? "i1" : lhs.Name;
        const auto rhsName = rhs.Name == "bool" ? "i1" : rhs.Name;
        assert(NumericTypes.find(lhsName) != NumericTypes.end());
        assert(NumericTypes.find(rhsName) != NumericTypes.end());

        const auto& lhsType = NumericTypes.lookup(lhsName);
        const auto& rhsType = NumericTypes.lookup(rhsName);

        const auto width = std::max(lhsType.Width, rhsType.Width);
        if (lhsType.isFloat || rhsType.isFloat)
            return width > 32 ? TypeName::Double : TypeName::Float;
        if (!lhsType.isSigned && !rhsType.isSigned) {
            if (width > 32)
                return TypeName::UInt64;
            if (width > 8)
                return TypeName::UInt32;
            return TypeName::UInt8;
        }
        if (width > 32)
            return TypeName::Int64;
        if (width > 8)
            return TypeName::Int32;
        return TypeName::Int8;

        throw InternalCompilerError(
            "Incomparable types encountered while computing width: {0}, {1}", lhs.toString(), rhs.toString());
    }

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
