
#include "Types.h"
#include <sstream>

#include "Core/Exceptions.h"
#include "Core/Vector.h"
#include "Operations.h"
#include "SemaContext.h"
#include "llvm/IR/Type.h"
#include "llvm/Support/raw_ostream.h"

namespace pepper {

    Type::Type(const Ident& name, llvm::Type* type, bool is_signed_type)
        : std::enable_shared_from_this<Type>()
        , identifier(name)
        , ir_type(type)
        , signed_type(is_signed_type) {}

    Operations* Type::ops() {
        if (!operations)
            operations = Operations::get(shared_from_this());
        return operations.get();
    }

    //    std::string FunctionType::Signature(llvm::Type* return_type, const Params& params, bool varargs) {
    //        Vector<std::string> paramNames;
    //        std::transform(
    //            params.begin(), params.end(), std::back_inserter(paramNames), [](auto p) { return p.ParamName; });
    //        std::string paramsString = llvm::join(paramNames.begin(), paramNames.end(), ", ");
    //        std::string ellipsis = varargs ? ", ..." : "";
    //        return llvm::formatv("{0}({1}{2})", Types::to_string(return_type), paramsString, ellipsis);
    //    }

    Ref<Type> Type::pointer() const {
        if (identifier.ends_with('*')) {
            throw CompileError("Pointers to pointers are not supported");
        }
        if (ir_type->isPointerTy()) {
            throw CompileError("Explicit pointers to structs are not supported");
        }
        return Types::get(identifier + "*");
    }

    Type::Size Type::size() const {
        return Size::Fixed(size_in_bits() / 8);
    }

    Type::Size Type::size_in_bits() const {
        return ir_type->getPrimitiveSizeInBits();
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
        , pointee(pointee) {}

    Types::Types(llvm::LLVMContext& ctx)
        : llvm_ctx(ctx) {
        Void = add_type(Ref<Type>::create("void", llvm::Type::getVoidTy(ctx)));
        Int8 = add_type(Ref<Type>::create("i8", llvm::Type::getInt8Ty(ctx), true), {"char"});
        UInt8 = add_type(Ref<Type>::create("u8", llvm::Type::getInt8Ty(ctx)), {"byte"});
        Int32 = add_type(Ref<Type>::create("i32", llvm::Type::getInt32Ty(ctx), true), {"int"});
        UInt32 = add_type(Ref<Type>::create("u32", llvm::Type::getInt32Ty(ctx)), {"uint"});
        Int64 = add_type(Ref<Type>::create("i64", llvm::Type::getInt64Ty(ctx), true), {"long"});
        UInt64 = add_type(Ref<Type>::create("u64", llvm::Type::getInt64Ty(ctx)), {"ulong"});
        Bool = add_type(Ref<Type>::create("bool", llvm::Type::getInt1Ty(ctx)));
        Double = add_type(Ref<Type>::create("f64", llvm::Type::getDoubleTy(ctx), true), {"double"});
        Float = add_type(Ref<Type>::create("f32", llvm::Type::getFloatTy(ctx), true), {"float"});
        // insert pointer types for all native types
        known_types.erase("bool*");
        // llvm has no void*, use char* instead
        VoidPtr = add_type(Ref<PointerType>::create("void*", known_types["i8*"]));
    }

    Ref<Type> Types::add_type(Ref<Type> t, const Vector<Ident>& aliases) {
        auto llvmType = t->llvmType();
        bool generatePointerType = !llvmType->isStructTy() && !llvmType->isPointerTy() && !llvmType->isVoidTy();

        // add requested type with aliases
        known_types[t->name()] = t;
        canonical_types[t.get()] = t->llvmType();
        for (const auto& alias : aliases) {
            known_types[alias] = t;
        }
        // add pointer types as well

        if (generatePointerType) {
            auto ptrType = Ref<PointerType>::create(t);
            known_types[t->name() + "*"] = ptrType;
            canonical_types[ptrType.get()] = ptrType->llvmType();
            for (const auto& alias : aliases) {
                known_types[alias + "*"] = ptrType;
            }
        }

        return t;
    }

    Ref<Type> Types::get_type(const Ident& name) const {
        auto it = known_types.find(name);
        if (it != known_types.end()) {
            return it->second;
        }
        return nullptr;
    }

    llvm::Type* Types::get_type(const Type* ty) const {
        return canonical_types.lookup(ty);
    }

    std::string Types::to_string(Ref<Type> ty) {
        return ty->name();
    }

    std::string Types::to_string(llvm::Type* ty) {
        std::string str;
        llvm::raw_string_ostream stream(str);
        ty->print(stream, true, true);
        return str;
    }

    Ref<Type> Types::add(Ref<Type> type, const Vector<Ident>& aliases) {
        return SemaContext::get().types()->add_type(type, aliases);
    }

    Ref<Type> Types::get(const Ident& name) {
        return SemaContext::get().types()->get_type(name);
    }

    llvm::Type* Types::get(const Type* ty) {
        return SemaContext::get().types()->get_type(ty);
    }
} // namespace pepper
