
#include "AST/Intrinsics.h"
#include "CodeGen/CodeGenerator.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Core/TypeSwitch.h"

namespace pepper {
    Address CodeGenerator::emitSizeOf(const ast::SizeOf* sizeOf) {
        auto structDesc = Struct::get(sizeOf->Target.toString());
        if (structDesc)
            return Address(Types::UInt64, llvm::ConstantInt::get(*Types::UInt64, structDesc->size()));
        auto type = Types::get(sizeOf->Target.toString());
        if (!type)
            throw CompileError(sizeOf->Source, "__sizeof called on non-existent type {0}", sizeOf->Target.toString());
        return Address(Types::UInt64, llvm::ConstantInt::get(*Types::UInt64, type->size()));
    }

    Address CodeGenerator::emitArrayIndex(const ast::ArrayIndex* index) {
        if (index->Args.size() != 2)
            throw CompileError(
                index->Source, "__array_index requires exactly 2 arguments, got {0}", index->Args.size());
        auto lhs = codegen(index->Args[0]);
        auto idx = codegen(index->Args[1]);
        lhs = load(lhs);
        idx = load(idx);
        auto elementType = lhs.Ty->as<PointerType>()->pointeeType();
        if (!elementType) {
            throw CompileError(index->Source, "Unknown element type in __array_index: {0}", index->Target.toString());
        }
        auto element = ir()->CreateInBoundsGEP(*elementType, lhs, {idx});
        return Address{elementType, element};
    }

    Address CodeGenerator::emitIsPod(const ast::IsPod* isPod) {
        if (isPod->Target.SubTypes.size() != 1)
            throw CompileError(
                isPod->Source, "__is_pod<T>() takes exactly one type argument, got {0}", isPod->Target.SubTypes.size());
        auto typeName = isPod->Target.SubTypes.front();
        auto type = Types::get(typeName.toString());
        if (!type)
            throw CompileError(isPod->Source, "Unknown type in __is_pod: {0}", typeName.toString());
        auto res = llvm::ConstantInt::getBool(*Types::Bool, !type->isStruct());
        return Address{Types::Bool, res, "is_pod"};
    }

    Address CodeGenerator::emitDefault(const ast::Default* defaultVal) {
        if (defaultVal->Target.SubTypes.size() != 1)
            throw CompileError(defaultVal->Source,
                               "default<T>() takes exactly one type argument, got {0}",
                               defaultVal->Target.SubTypes.size());
        auto typeName = defaultVal->Target.SubTypes.front();
        auto type = Types::get(typeName.toString());
        if (!type)
            throw CompileError(defaultVal->Source, "Unknown type in __default: {0}", typeName.toString());
        auto res = zeroValue(type);
        return Address{type, res, "default"};
    }

    Address CodeGenerator::emit(const ast::Intrinsic* it) {
        // clang-format off
        return TypeSwitch<const ast::Intrinsic*, Address>(it)
            .Case<ast::SizeOf>([&](auto* it) { return emitSizeOf(it);})
            .Case<ast::ArrayIndex>([&](auto* it) { return emitArrayIndex(it); })
            .Case<ast::IsPod>([&](auto* it) { return emitIsPod(it); })
            .Case<ast::Default>([&](auto* it) { return emitDefault(it); })
            .Default([](const auto* it) -> Address { throw CompileError(it->Source, "Unknown intrinsic: {0}", it->rtti()->name()); });
        // clang-format on
    }
} // namespace pepper