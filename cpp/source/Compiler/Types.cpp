
#include "Compiler/Types.h"

#include "AST/Nodes.h"
#include "Compiler/Context.h"
#include "Param.h"
#include "llvm/IR/Value.h"
#include "llvm/Support/raw_ostream.h"
#include <sstream>

#pragma warning(disable : 4624) // warning C4624: 'llvm::detail::move_construction_triviality_helper<T>': destructor was
                                // implicitly defined as deleted
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Type.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper {

    std::string FunctionType::Signature(llvm::Type* returnType, const Params& params, bool varargs) {
        std::vector<std::string> paramNames;
        std::transform(params.begin(), params.end(), std::back_inserter(paramNames), [](auto p) { return p.Name; });
        std::string paramsString = llvm::join(paramNames.begin(), paramNames.end(), ", ");
        std::string ellipsis = varargs ? ", ..." : "";
        return llvm::formatv("{0}({1}{2})", Types::toString(returnType), paramsString, ellipsis);
    }

    llvm::Type* Types::Bool;
    llvm::Type* Types::Void;
    llvm::Type* Types::Int8;
    llvm::Type* Types::UInt8;
    llvm::Type* Types::Int32;
    llvm::Type* Types::UInt32;
    llvm::Type* Types::Int64;
    llvm::Type* Types::UInt64;
    llvm::Type* Types::Double;
    llvm::Type* Types::Float;

    Types::Types(llvm::LLVMContext& ctx)
        : Ctx(ctx) {
        KnownTypes["void"] = Void = llvm::Type::getVoidTy(ctx);
        KnownTypes["char"] = KnownTypes["i8"] = Int8 = llvm::Type::getInt8Ty(ctx);
        KnownTypes["byte"] = KnownTypes["u8"] = UInt8 = llvm::Type::getInt8Ty(ctx);
        KnownTypes["int"] = KnownTypes["i32"] = Int32 = llvm::Type::getInt32Ty(ctx);
        KnownTypes["uint"] = KnownTypes["u32"] = UInt32 = llvm::Type::getInt32Ty(ctx);
        KnownTypes["long"] = KnownTypes["i64"] = Int64 = llvm::Type::getInt64Ty(ctx);
        KnownTypes["ulong"] = KnownTypes["u64"] = UInt64 = llvm::Type::getInt64Ty(ctx);
        KnownTypes["Bool"] = Bool = llvm::Type::getInt1Ty(ctx);
        KnownTypes["double"] = KnownTypes["f64"] = Double = llvm::Type::getDoubleTy(ctx);
        KnownTypes["float"] = KnownTypes["f32"] = Float = llvm::Type::getFloatTy(ctx);
        // insert pointer types for all native types
        for (const auto& ty : KnownTypes) {
            if (ty.first() == "bool")
                continue;
            KnownTypes[ty.first().str() + "*"] = ty.second->getPointerTo(0);
        }
    }

    llvm::Type* Types::getType(const std::string& name) {
        return KnownTypes[name];
    }

    std::string Types::Types::toString(llvm::Type* ty) {
        std::string str;
        llvm::raw_string_ostream stream(str);
        ty->print(stream, true, true);
        return str;
    }
} // namespace pepper
