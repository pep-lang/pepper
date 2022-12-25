
#include "Codegen/Types.h"
#include <sstream>
#include <vector>

#include "AST/Nodes.h"
#include "Codegen/Context.h"
#include "Param.h"
#include "llvm/IR/Value.h"
#include "llvm/Support/raw_ostream.h"

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
        std::transform(
            params.begin(), params.end(), std::back_inserter(paramNames), [](auto p) { return p.ParamName; });
        std::string paramsString = llvm::join(paramNames.begin(), paramNames.end(), ", ");
        std::string ellipsis = varargs ? ", ..." : "";
        return llvm::formatv("{0}({1}{2})", Types::toString(returnType), paramsString, ellipsis);
    }

    Ref<Type> Types::Bool;
    Ref<Type> Types::Void;
    Ref<Type> Types::VoidPtr;
    Ref<Type> Types::Int8;
    Ref<Type> Types::UInt8;
    Ref<Type> Types::Int32;
    Ref<Type> Types::UInt32;
    Ref<Type> Types::Int64;
    Ref<Type> Types::UInt64;
    Ref<Type> Types::Double;
    Ref<Type> Types::Float;

    Types::Types(llvm::LLVMContext& ctx)
        : Ctx(ctx) {
        Void = addType(Ref<Type>::New("void", llvm::Type::getVoidTy(ctx)));
        Int8 = addType(Ref<Type>::New("i8", llvm::Type::getInt8Ty(ctx)), {"char"});
        UInt8 = addType(Ref<Type>::New("u8", llvm::Type::getInt8Ty(ctx)), {"byte"});
        Int32 = addType(Ref<Type>::New("i32", llvm::Type::getInt32Ty(ctx)), {"int"});
        UInt32 = addType(Ref<Type>::New("u32", llvm::Type::getInt32Ty(ctx)), {"uint"});
        Int64 = addType(Ref<Type>::New("i64", llvm::Type::getInt64Ty(ctx)), {"long"});
        UInt64 = addType(Ref<Type>::New("u64", llvm::Type::getInt64Ty(ctx)), {"ulong"});
        Bool = addType(Ref<Type>::New("bool", llvm::Type::getInt1Ty(ctx)));
        Double = addType(Ref<Type>::New("f64", llvm::Type::getDoubleTy(ctx)), {"double"});
        Float = addType(Ref<Type>::New("f32", llvm::Type::getFloatTy(ctx)), {"float"});
        // insert pointer types for all native types
        KnownTypes.erase("bool*");
        // llvm has no void*, use char* intead
        VoidPtr = addType(Ref<Type>::New("void*", *KnownTypes["i8*"]));
    }

    Ref<Type> Types::addType(Ref<Type> t, const llvm::SmallVector<Name>& aliases) {
        if (t->llvmType()->isStructTy()) {
            // add <struct>* as "<struct>", and <struct> as "_<struct>"
            KnownTypes["_" + t->name()] = t;
            TypeCache[*t] = t;
            auto ptrType = Ref<Type>::New(t->name(), t->llvmType()->getPointerTo());
            KnownTypes[t->name()] = ptrType;
            KnownTypes[t->name() + "*"] = ptrType;
            TypeCache[*ptrType] = ptrType;
            for (const auto& alias : aliases) {
                KnownTypes[alias] = ptrType;
                if (!alias.ends_with('*'))
                    KnownTypes[alias + "*"] = ptrType;
            }
        } else {
            // add requested type with aliases
            KnownTypes[t->name()] = t;
            TypeCache[*t] = t;
            for (const auto& alias : aliases) {
                KnownTypes[alias] = t;
            }
            // add pointer types as well
            if (!t->llvmType()->isPointerTy() && !t->llvmType()->isVoidTy()) {
                auto ptrType = Ref<Type>::New(t->name() + "*", t->llvmType()->getPointerTo());
                KnownTypes[t->name() + "*"] = ptrType;
                TypeCache[*ptrType] = ptrType;
                for (const auto& alias : aliases) {
                    KnownTypes[alias + "*"] = ptrType;
                }
            }
        }

        return t;
    }

    Ref<Type> Types::getType(const Name& name) const {
        auto it = KnownTypes.find(name);
        if (it != KnownTypes.end()) {
            return it->second;
        }
        return nullptr;
    }

    Ref<Type> Types::getType(llvm::Type* type) const {
        auto it = TypeCache.find(type);
        if (it != TypeCache.end()) {
            return it->second;
        }
        return nullptr;
    }

    std::string Types::Types::toString(llvm::Type* ty) {
        std::string str;
        llvm::raw_string_ostream stream(str);
        ty->print(stream, true, true);
        return str;
    }

    Ref<Type> Types::add(Ref<Type> type, const llvm::SmallVector<Name>& aliases) {
        return Context::get().types()->addType(type, aliases);
    }

    Ref<Type> Types::get(const Name& name) {
        return Context::get().types()->getType(name);
    }

    Ref<Type> Types::get(llvm::Type* type) {
        return Context::get().types()->getType(type);
    }
} // namespace pepper
