
#include "Frontend/Types.h"
#include <sstream>

#include "Core/Exceptions.h"
#include "Core/Vector.h"
#include "Frontend/Operations.h"
#include "Frontend/PepContext.h"
#include "llvm/IR/Type.h"
#include "llvm/Support/raw_ostream.h"

namespace pepper {

    Type::Type(const Ident& name, llvm::Type* type, bool isSigned)
        : std::enable_shared_from_this<Type>()
        , Name(name)
        , IRType(type)
        , IsSigned(isSigned) {}

    Operations* Type::ops() {
        if (!Ops)
            Ops = Operations::get(shared_from_this());
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

    Ref<Type> Type::pointer() const {
        if (Name.ends_with('*')) {
            throw CompileError("Pointers to pointers are not supported");
        }
        if (IRType->isPointerTy()) {
            throw CompileError("Explicit pointers to structs are not supported");
        }
        return Types::get(Name + "*");
    }

    unsigned Type::size() const {
        return IRType->getPrimitiveSizeInBits() / 8;
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

    PointerType::PointerType(Ref<Type> pointee)
        : PointerType(pointee->name() + "*", pointee) {}

    PointerType::PointerType(const Ident& name, Ref<Type> pointee)
        : Type(name, pointee->llvmType()->getPointerTo(), false)
        , PointeeType(pointee) {}

    unsigned PointerType::size() const {
        return llvmType()->getPrimitiveSizeInBits() / 8;
    }

    Types::Types(llvm::LLVMContext& ctx)
        : Ctx(ctx) {
        Void = addType(Ref<Type>::New("void", llvm::Type::getVoidTy(ctx)));
        Int8 = addType(Ref<Type>::New("i8", llvm::Type::getInt8Ty(ctx), true), {"char"});
        UInt8 = addType(Ref<Type>::New("u8", llvm::Type::getInt8Ty(ctx)), {"byte"});
        Int32 = addType(Ref<Type>::New("i32", llvm::Type::getInt32Ty(ctx), true), {"int"});
        UInt32 = addType(Ref<Type>::New("u32", llvm::Type::getInt32Ty(ctx)), {"uint"});
        Int64 = addType(Ref<Type>::New("i64", llvm::Type::getInt64Ty(ctx), true), {"long"});
        UInt64 = addType(Ref<Type>::New("u64", llvm::Type::getInt64Ty(ctx)), {"ulong"});
        Bool = addType(Ref<Type>::New("bool", llvm::Type::getInt1Ty(ctx)));
        Double = addType(Ref<Type>::New("f64", llvm::Type::getDoubleTy(ctx), true), {"double"});
        Float = addType(Ref<Type>::New("f32", llvm::Type::getFloatTy(ctx), true), {"float"});
        // insert pointer types for all native types
        KnownTypes.erase("bool*");
        // llvm has no void*, use char* instead
        VoidPtr = addType(Ref<PointerType>::New("void*", KnownTypes["i8*"]));
    }

    Ref<Type> Types::addType(Ref<Type> t, const Vector<Ident>& aliases) {
        if (t->llvmType()->isStructTy()) {
            KnownTypes[t->name()] = t;
        } else {
            // add requested type with aliases
            KnownTypes[t->name()] = t;
            for (const auto& alias : aliases) {
                KnownTypes[alias] = t;
            }
            // add pointer types as well
            if (!t->llvmType()->isPointerTy() && !t->llvmType()->isVoidTy()) {
                auto ptrType = Ref<PointerType>::New(t);
                KnownTypes[t->name() + "*"] = ptrType;
                for (const auto& alias : aliases) {
                    KnownTypes[alias + "*"] = ptrType;
                }
            }
        }

        return t;
    }

    Ref<Type> Types::getType(const Ident& name) const {
        auto it = KnownTypes.find(name);
        if (it != KnownTypes.end()) {
            return it->second;
        }
        return nullptr;
    }

    std::string Types::toString(Ref<Type> ty) {
        return ty->name();
    }

    std::string Types::toString(llvm::Type* ty) {
        std::string str;
        llvm::raw_string_ostream stream(str);
        ty->print(stream, true, true);
        return str;
    }

    Ref<Type> Types::add(Ref<Type> type, const Vector<Ident>& aliases) {
        return PepContext::get().types()->addType(type, aliases);
    }

    Ref<Type> Types::get(const Ident& name) {
        return PepContext::get().types()->getType(name);
    }
} // namespace pepper
