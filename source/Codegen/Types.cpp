
#include "Codegen/Types.h"
#include <sstream>

#include "AST/Nodes.h"
#include "Codegen/Context.h"
#include "Core/Vector.h"
#include "Param.h"
#include "llvm/IR/Value.h"
#include "llvm/Support/raw_ostream.h"

#pragma warning(disable : 4624) // warning C4624: 'llvm::detail::move_construction_triviality_helper<T>': destructor was
                                // implicitly defined as deleted
#include "Codegen/TypeOps.h"
#include "Core/Exceptions.h"
#include "Core/Vector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Type.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper {

    TypeInfo::TypeInfo(const Ident& name, llvm::Type* type, bool isSigned)
        : std::enable_shared_from_this<TypeInfo>()
        , TypeName(name)
        , TypeRef(type)
        , IsSigned(false) {
    }

    TypeOps* TypeInfo::ops() {
        if (!Ops)
            Ops = TypeOps::get(shared_from_this());
        return Ops.get();
    }

    //    std::string FunctionType::Signature(llvm::Type* returnType, const Params& params, bool varargs) {
    //        Vector<std::string> paramNames;
    //        std::transform(
    //            params.begin(), params.end(), std::back_inserter(paramNames), [](auto p) { return p.ParamName; });
    //        std::string paramsString = llvm::join(paramNames.begin(), paramNames.end(), ", ");
    //        std::string ellipsis = varargs ? ", ..." : "";
    //        return llvm::formatv("{0}({1}{2})", Types::toString(returnType), paramsString, ellipsis);
    //    }

    Ref<TypeInfo> TypeInfo::pointer() const {
        if (TypeName.ends_with('*')) {
            throw CompileError("Pointers to pointers are not supported");
        }
        if (TypeRef->isPointerTy()) {
            throw CompileError("Explicit pointers to structs are not supported");
        }
        return Types::get(TypeName + "*");
    }

    Ref<TypeInfo> Types::Bool;
    Ref<TypeInfo> Types::Void;
    Ref<TypeInfo> Types::VoidPtr;
    Ref<TypeInfo> Types::Int8;
    Ref<TypeInfo> Types::UInt8;
    Ref<TypeInfo> Types::Int32;
    Ref<TypeInfo> Types::UInt32;
    Ref<TypeInfo> Types::Int64;
    Ref<TypeInfo> Types::UInt64;
    Ref<TypeInfo> Types::Double;
    Ref<TypeInfo> Types::Float;

    Types::Types(llvm::LLVMContext& ctx)
        : Ctx(ctx) {
        Void = addType(Ref<TypeInfo>::New("void", llvm::Type::getVoidTy(ctx)));
        Int8 = addType(Ref<TypeInfo>::New("i8", llvm::Type::getInt8Ty(ctx)), {"char"});
        UInt8 = addType(Ref<TypeInfo>::New("u8", llvm::Type::getInt8Ty(ctx)), {"byte"});
        Int32 = addType(Ref<TypeInfo>::New("i32", llvm::Type::getInt32Ty(ctx)), {"int"});
        UInt32 = addType(Ref<TypeInfo>::New("u32", llvm::Type::getInt32Ty(ctx)), {"uint"});
        Int64 = addType(Ref<TypeInfo>::New("i64", llvm::Type::getInt64Ty(ctx)), {"long"});
        UInt64 = addType(Ref<TypeInfo>::New("u64", llvm::Type::getInt64Ty(ctx)), {"ulong"});
        Bool = addType(Ref<TypeInfo>::New("bool", llvm::Type::getInt1Ty(ctx)));
        Double = addType(Ref<TypeInfo>::New("f64", llvm::Type::getDoubleTy(ctx)), {"double"});
        Float = addType(Ref<TypeInfo>::New("f32", llvm::Type::getFloatTy(ctx)), {"float"});
        // insert pointer types for all native types
        KnownTypes.erase("bool*");
        // llvm has no void*, use char* intead
        VoidPtr = addType(Ref<TypeInfo>::New("void*", *KnownTypes["i8*"]));
    }

    Ref<TypeInfo> Types::addType(Ref<TypeInfo> t, const Vector<Ident>& aliases) {
        if (t->llvmType()->isStructTy()) {
            // add <struct>* as "<struct>", and <struct> as "_<struct>"
            KnownTypes["_" + t->name()] = t;
            // TypeCache[*t] = t;
            auto ptrType = Ref<TypeInfo>::New(t->name(), t->llvmType()->getPointerTo());
            KnownTypes[t->name()] = ptrType;
            KnownTypes[t->name() + "*"] = ptrType;
            // TypeCache[*ptrType] = ptrType;
            for (const auto& alias : aliases) {
                KnownTypes[alias] = ptrType;
                if (!alias.ends_with('*'))
                    KnownTypes[alias + "*"] = ptrType;
            }
        } else {
            // add requested type with aliases
            KnownTypes[t->name()] = t;
            // TypeCache[*t] = t;
            for (const auto& alias : aliases) {
                KnownTypes[alias] = t;
            }
            // add pointer types as well
            if (!t->llvmType()->isPointerTy() && !t->llvmType()->isVoidTy()) {
                auto ptrType = Ref<TypeInfo>::New(t->name() + "*", t->llvmType()->getPointerTo());
                KnownTypes[t->name() + "*"] = ptrType;
                // TypeCache[*ptrType] = ptrType;
                for (const auto& alias : aliases) {
                    KnownTypes[alias + "*"] = ptrType;
                }
            }
        }

        return t;
    }

    Ref<TypeInfo> Types::getType(const Ident& name) const {
        auto it = KnownTypes.find(name);
        if (it != KnownTypes.end()) {
            return it->second;
        }
        return nullptr;
    }

    std::string Types::toString(Ref<TypeInfo> ty) {
        return ty->name();
    }

    std::string Types::toString(llvm::Type* ty) {
        std::string str;
        llvm::raw_string_ostream stream(str);
        ty->print(stream, true, true);
        return str;
    }

    Ref<TypeInfo> Types::add(Ref<TypeInfo> type, const Vector<Ident>& aliases) {
        return Context::get().types()->addType(type, aliases);
    }

    Ref<TypeInfo> Types::get(const Ident& name) {
        return Context::get().types()->getType(name);
    }
} // namespace pepper
