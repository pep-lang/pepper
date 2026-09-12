
#include "CodeGen/LLVM/LLVMCodeGenerator.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Core/TypeSwitch.h"
#include "Sema/Model/Intrinsics.h"

namespace pepper {
    Address LLVMCodeGenerator::emitSizeOf(const sema::SizeOf* sizeOf) {
        auto structDesc = Struct::get(sizeOf->target.to_string());
        if (structDesc)
            return Address(Types::UInt64, llvm::ConstantInt::get(*Types::UInt64, structDesc->size()));
        auto type = Types::get(sizeOf->target.to_string());
        if (!type)
            throw CompileError(
                sizeOf->source_loc, "__sizeof called on non-existent type {0}", sizeOf->target.to_string());
        return Address(Types::UInt64, llvm::ConstantInt::get(*Types::UInt64, type->size()));
    }

    Address LLVMCodeGenerator::emitArrayIndex(const sema::ArrayIndex* index) {
        if (index->args.size() != 2)
            throw CompileError(
                index->source_loc, "__array_index requires exactly 2 arguments, got {0}", index->args.size());
        auto lhs = codegen(index->args[0]);
        auto idx = codegen(index->args[1]);
        lhs = load(lhs);
        idx = load(idx);
        auto element_type = lhs.type->as<PointerType>()->pointee_type();
        if (!element_type) {
            throw CompileError(
                index->source_loc, "Unknown element type in __array_index: {0}", index->target.to_string());
        }
        auto element = ir()->CreateInBoundsGEP(*element_type, lhs, {idx});
        return Address{element_type, element};
    }

    Address LLVMCodeGenerator::emitIsPod(const sema::IsPod* isPod) {
        if (isPod->target.sub_types.size() != 1)
            throw CompileError(isPod->source_loc,
                               "__is_pod<T>() takes exactly one type argument, got {0}",
                               isPod->target.sub_types.size());
        auto typeName = isPod->target.sub_types.front();
        auto type = Types::get(typeName.to_string());
        if (!type)
            throw CompileError(isPod->source_loc, "Unknown type in __is_pod: {0}", typeName.to_string());
        auto res = llvm::ConstantInt::getBool(*Types::Bool, !type->is_struct());
        return Address{Types::Bool, res, "is_pod"};
    }

    Address LLVMCodeGenerator::emitDefault(const sema::Default* defaultVal) {
        if (defaultVal->target.sub_types.size() != 1)
            throw CompileError(defaultVal->source_loc,
                               "default<T>() takes exactly one type argument, got {0}",
                               defaultVal->target.sub_types.size());
        auto typeName = defaultVal->target.sub_types.front();
        auto type = Types::get(typeName.to_string());
        if (!type)
            throw CompileError(defaultVal->source_loc, "Unknown type in __default: {0}", typeName.to_string());
        auto res = zero_value(type);
        return Address{type, res, "default"};
    }

    Address LLVMCodeGenerator::emit(const sema::Intrinsic* it) {
        // clang-format off
        return TypeSwitch<const sema::Intrinsic*, Address>(it)
            .Case<sema::SizeOf>([&](auto* it) { return emitSizeOf(it);})
            .Case<sema::ArrayIndex>([&](auto* it) { return emitArrayIndex(it); })
            .Case<sema::IsPod>([&](auto* it) { return emitIsPod(it); })
            .Case<sema::Default>([&](auto* it) { return emitDefault(it); })
            .Default([](const auto* it) -> Address { throw CompileError(it->source_loc, "Unknown intrinsic: {0}", it->rtti()->name()); });
        // clang-format on
    }
} // namespace pepper
