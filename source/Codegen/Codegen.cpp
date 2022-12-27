
#include "Codegen.h"
#include <functional>
#include <unordered_map>

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Codegen/Context.h"
#include "Codegen/Function.h"
#include "Codegen/LLVMUtils.h"
#include "Codegen/ModuleContext.h"
#include "Codegen/Scope.h"
#include "Codegen/Struct.h"
#include "Codegen/TypeOps.h"
#include "Codegen/Types.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    using namespace pepper::ast;

    static llvm::Value* codegen(Ref<Node> node);

    template <typename N>
    static llvm::Value* maybeCodegen(Ref<N> node) {
        return node ? codegen(node) : nullptr;
    }

    static Ref<llvm::IRBuilderBase> ir() {
        return Context::get().locals()->builder();
    }

    static Ref<llvm::IRBuilderBase> registers() {
        return Context::get().locals()->registers();
    }

    using llvm::cast;
    using llvm::isa;

    static llvm::Type* resolveType(llvm::Value* value) {
        if (isa<llvm::AllocaInst>(*value)) {
            auto allocaInst = cast<llvm::AllocaInst>(value);
            return allocaInst->getAllocatedType();
        }
        if (isa<llvm::GetElementPtrInst>(value)) {
            auto gepInst = cast<llvm::GetElementPtrInst>(value);
            return gepInst->getResultElementType();
        }
        return value->getType();
    }

    static llvm::Value* read(llvm::Value* value) {
        if (isa<llvm::AllocaInst>(*value)) {
            auto type = resolveType(value);
            return ir()->CreateLoad(type, value);
        }
        if (isa<llvm::GetElementPtrInst>(value)) {
            auto type = resolveType(value);
            return ir()->CreateLoad(type, value);
        }
        return value;
    }

    static void codegenFunction(Ref<UserFunction> function, Ref<FunctionDef> funcDef) {
        Context::get().pushFunction(function);

        // Allocate parameters
        auto llvmFunction = function->function();
        auto args = Vector<llvm::Value*>();
        for (int paramIdx = 0; paramIdx < function->params().size(); ++paramIdx) {
            auto param = function->params()[paramIdx];
            auto arg = llvmFunction->getArg(paramIdx);
            auto local = ir()->CreateAlloca(*param.ParamType, nullptr, param.ParamName);
            ir()->CreateStore(arg, local);
            Context::get().locals()->newSymbol(param.ParamName, local);
            args.push_back(local);
        }

        // Push all known variables (except params, which are already done above) at the top of the function block
        Query(funcDef->locals())
            .without([](auto local) { return local->template is<ParamDef>(); })
            .each([&](auto local) { codegen(local); });

        // Emit the body of the function, after ensuring there is a return instruction
        auto lastExpr = (funcDef->body().size()) ? funcDef->body().back() : nullptr;
        if (!lastExpr || !lastExpr->is<Return>()) {
            funcDef->body().push_back(Ref<Return>::New(funcDef));
        }
        std::for_each(funcDef->body().begin(), funcDef->body().end(), [&](auto expr) { codegen(expr); });

        Context::get().popScope();
        Context::get().locals()->newFunction(function);
    }

    llvm::Value* zeroValue(llvm::Type* type) {
        if (type->isIntegerTy())
            return llvm::ConstantInt::get(type, 0);
        if (type->isFloatingPointTy())
            return llvm::ConstantFP::get(type, 0.0f);
        if (type->isPointerTy())
            return llvm::ConstantPointerNull::get(cast<llvm::PointerType>(type));
        throw InternalCompilerError("No known default value for type {0}", Types::toString(type));
    }

    static llvm::Value* emit(Ref<VariableRef> variableRef) {
        auto value = Context::get().locals()->findSymbol(variableRef->identifier());
        return value;
    }

    static llvm::Value* emit(Ref<VariableDef> variableDef) {
        auto typeName = variableDef->type();
        auto type = Types::get(typeName);
        auto value = registers()->CreateAlloca(*type, nullptr, variableDef->identifier());

        auto defaultValue = maybeCodegen(variableDef->defaultValue());
        if (!defaultValue)
            defaultValue = zeroValue(*type);

        auto typeOps = TypeOps::get(*type);
        auto coercedValue = typeOps->coerce(defaultValue);
        ir()->CreateStore(coercedValue, value);
        Context::get().locals()->newSymbol(variableDef->identifier(), value);
        return value;
    }

    static llvm::Value* emit(Ref<StringLiteral> stringLiteral) {
        auto value = ir()->CreateGlobalString(stringLiteral->value());
        return value;
    }

    static llvm::Value* emit(Ref<IntegerLiteral> intLiteral) {
        auto value = llvm::ConstantInt::get(*Types::Int64, intLiteral->value());
        return value;
    }

    static llvm::Value* emit(Ref<FloatLiteral> floatLiteral) {
        auto value = llvm::ConstantFP::get(*Types::Double, floatLiteral->value());
        return value;
    }

    static Ref<Struct> emit(Ref<StructDef> structDef) {
        // convert fields to symbols before type gen
        pepper::Params fields;
        Vector<llvm::Type*> fieldTypes;
        for (auto& field : structDef->Fields) {
            auto type = Types::get(field->type());
            fieldTypes.push_back(*type);
            fields.emplace_back(field->identifier(), type);
        }

        // generate the new struct type
        auto llvmType = llvm::StructType::create(fieldTypes, structDef->identifier());
        auto structType = Types::add(Ref<Type>::New(structDef->identifier(), llvmType));
        auto structPtrType = Types::get(structDef->identifier());
        auto structDesc = Struct::New(structType, structDef->identifier());
        structDesc->setFields(fields);

        // Update Struct()/new function now that the size of the struct is known
        auto sizeVar = std::find_if(structDef->NewInstance->locals().begin(),
                                    structDef->NewInstance->locals().end(),
                                    [](auto& local) { return (local->identifier() == "size"); });
        assert(sizeVar != structDef->NewInstance->locals().end());
        (*sizeVar)->setDefaultValue(Ref<IntegerLiteral>::New(structDesc->size()));

        // Export new function to the enclosing scope
        Context::get().locals()->newFunction(structDesc->instanceNew());

        // map method names to mangled free functions while maintaining order
        Vector<Ref<Method>> methods;
        for (auto& method : structDef->Methods) {
            auto realName = method->identifier();
            pepper::Params params;
            // inject this pointer
            auto thisType = Types::get(structDef->identifier());
            params.emplace_back("this", thisType);
            for (auto& paramDef : method->params()) {
                auto type = Types::get(paramDef.Type);
                params.emplace_back(paramDef.Identifier, type, maybeCodegen(paramDef.Default));
            }
            // TODO: mangle these properly
            auto mangledName = structDef->identifier() + "." + realName;
            auto returnType = Types::get(method->returnType());
            auto newMethod = Ref<Method>::New(mangledName, returnType, params);
            methods.push_back(newMethod);
            structDesc->addMethod(newMethod);
        }

        for (int methodIdx = 0; methodIdx < methods.size(); ++methodIdx) {
            auto& method = methods[methodIdx];
            auto& methodDef = structDef->Methods[methodIdx];
            codegenFunction(method, methodDef);
        }

        codegenFunction(structDesc->instanceNew(), structDef->NewInstance);

        return structDesc;
    }

    static llvm::Value* emit(Ref<FieldDef> fieldDef) {
        auto st = Struct::get(fieldDef->Struct->identifier());
        auto instance = Context::get().locals()->findSymbol("this");
        auto fieldName = fieldDef->identifier();
        auto field = st->getField(instance, fieldName);
        if (!field) {
            throw CompileError("struct {0} does not contain a field named {1}", st->name(), fieldName);
        }
        auto type = Types::get(fieldDef->type());
        auto value = maybeCodegen(fieldDef->defaultValue());
        if (!value) {
            value = zeroValue(*type);
        }
        ir()->CreateStore(value, field);
        return field;
    }

    static llvm::Value* emit(Ref<MemberRef> memberRef) {
        auto lhs = codegen(memberRef->lhs());
        auto lhsType = Types::get(lhs->getType());
        auto structDesc = Struct::get(lhsType->name());
        auto memberName = memberRef->name();
        auto thisPtr = read(lhs);
        auto member = structDesc->getMember(thisPtr, memberName);
        return member;
    }

    static llvm::Value* emit(Ref<ThisRef> thisRef) {
        auto thisPtr = Context::get().locals()->findSymbol("this");
        return thisPtr;
    }

    static pepper::Params astToTypedParams(const ast::Params& src) {
        pepper::Params params;
        for (auto p : src) {
            params.emplace_back(p.Identifier, Types::get(p.Type), maybeCodegen(p.Default));
        }
        return params;
    }

    static llvm::Value* emit(Ref<FunctionDef> functionDef) {
        auto returnType = Types::get(functionDef->returnType());
        auto params = astToTypedParams(functionDef->params());
        auto function = Ref<UserFunction>::New(functionDef->identifier(), returnType, params);
        codegenFunction(function, functionDef);
        return function->function();
    }

    static llvm::Value* emit(Ref<Return> ret) {
        if (ret->value()) {
            auto returnValueExpr = codegen(ret->value());
            auto returnValue = read(returnValueExpr);
            auto func = ret->target();
            auto returnType = Types::get(func->returnType());
            auto type = TypeOps::get(*returnType);
            auto rv = type->coerce(returnValue);
            return ir()->CreateRet(rv);
        }
        return ir()->CreateRetVoid();
    }

    static Ref<Function> resolveFunction(Ref<FunctionCall> call) {
        auto functionName = call->target()->identifier();
        auto target = call->target();
        if (target->is<MethodDef>()) {
            auto methodDef = target.as<MethodDef>();
            auto st = methodDef->structDef();
            auto name = methodDef->identifier();
            auto mangledName = st->identifier() + "." + name;
            functionName = mangledName;
        }
        return Context::get().locals()->findFunction(functionName);
    }

    static llvm::Value* emit(Ref<FunctionCall> call) {
        auto function = resolveFunction(call);
        if (!function) {
            throw CompileError("Function {0} not found", call->target()->identifier());
        }
        Vector<llvm::Value*> args;
        if (function->is<Method>()) {
            auto thisRef = Context::get().locals()->findSymbol("this");
            assert(thisRef);
            args.push_back(thisRef);
        }

        const auto& callArgs = call->args();
        for (auto argExpr : callArgs) {
            args.push_back(codegen(argExpr));
        }
        return function->call(args);
    }

    static auto binaryOp(Ref<BinaryOp> op) {
        if (op->is<Assign>())
            return &TypeOps::assign;
        if (op->is<Add>())
            return &TypeOps::add;
        if (op->is<Sub>())
            return &TypeOps::sub;
        if (op->is<Mul>())
            return &TypeOps::mul;
        if (op->is<Div>())
            return &TypeOps::div;
        if (op->is<Mod>())
            return &TypeOps::mod;
        if (op->is<Pow>())
            return &TypeOps::pow;
        if (op->is<LShift>())
            return &TypeOps::lshift;
        if (op->is<RShift>())
            return &TypeOps::rshift;
        if (op->is<Equal>())
            return &TypeOps::equal;
        if (op->is<NotEqual>())
            return &TypeOps::notEqual;
        if (op->is<Assign>())
            return &TypeOps::assign;
        if (op->is<Less>())
            return &TypeOps::less;
        if (op->is<LessEqual>())
            return &TypeOps::lessEq;
        if (op->is<Greater>())
            return &TypeOps::greater;
        if (op->is<GreaterEqual>())
            return &TypeOps::greaterEq;
        if (op->is<BitAnd>())
            return &TypeOps::bitAnd;
        if (op->is<BitOr>())
            return &TypeOps::bitOr;
        if (op->is<BitXor>())
            return &TypeOps::bitXor;
        if (op->is<LogicalAnd>())
            return &TypeOps::bitAnd;
        if (op->is<LogicalOr>())
            return &TypeOps::bitOr;
        throw InternalCompilerError("Unknown binary op: {0}", op->rtti()->name());
    }

    static Ref<Type> largestIntType(llvm::Type* lhs, llvm::Type* rhs) {
        auto bits = std::max(lhs->getIntegerBitWidth(), rhs->getIntegerBitWidth());
        return (bits > 32) ? Types::Int64 : Types::Int32;
    }

    static Ref<Type> largestOperandType(llvm::Type* lhs, llvm::Type* rhs) {
        if (lhs->isIntegerTy() && rhs->isIntegerTy()) {
            return largestIntType(lhs, rhs);
        }
        if (lhs->isFloatingPointTy() || rhs->isFloatingPointTy()) {
            auto bits = std::max(lhs->getPrimitiveSizeInBits(), rhs->getPrimitiveSizeInBits());
            return (bits > 32) ? Types::Double : Types::Float;
        }
        return nullptr;
    }

    static Ref<Type> structOperandType(Ref<BinaryOp> op, llvm::Type* lhs, llvm::Type* rhs) {
        return nullptr;
    }

    static Ref<Type> operandType(Ref<BinaryOp> op, llvm::Type* lhs, llvm::Type* rhs) {
        if (lhs->isStructTy() || lhs->isPointerTy()) {
            return structOperandType(op, lhs, rhs);
        }
        return llvm::StringSwitch<Ref<Type>>(op->rtti()->name())
            .Cases("Add", "Sub", "Mul", "Div", "Mod", "Pow", largestOperandType(lhs, rhs))
            .Cases("Equal", "NotEqual", "Less", "LessEqual", "Greater", "GreaterEqual", largestOperandType(lhs, rhs))
            .Cases("LShift", "RShift", "BitAnd", "BitOr", "BitXor", largestIntType(lhs, rhs))
            .Cases("LogicalAnd", "LogicalOr", Types::Bool)
            .Cases("AddAssign", "SubAssign", "MulAssign", "ModAssign", largestOperandType(lhs, rhs))
            .Cases(
                "LShiftAssign", "RShiftAssign", "BitAndAssign", "BitOrAssign", "BitXorAssign", largestIntType(lhs, rhs))
            .Case("Assign", Types::get(lhs));
    }

    static auto compoundOp(Ref<CompoundAssign> op) {
        if (op->is<AddAssign>())
            return &TypeOps::add;
        if (op->is<SubAssign>())
            return &TypeOps::sub;
        if (op->is<MulAssign>())
            return &TypeOps::mul;
        if (op->is<DivAssign>())
            return &TypeOps::div;
        if (op->is<ModAssign>())
            return &TypeOps::mod;
        if (op->is<LShiftAssign>())
            return &TypeOps::lshift;
        if (op->is<RShiftAssign>())
            return &TypeOps::rshift;
        if (op->is<BitAndAssign>())
            return &TypeOps::bitAnd;
        if (op->is<BitOrAssign>())
            return &TypeOps::bitOr;
        if (op->is<BitXorAssign>())
            return &TypeOps::bitXor;
        throw InternalCompilerError("Unknown compound assignment op: {0}", op->rtti()->name());
    }

    static llvm::Value* emit(Ref<CompoundAssign> op) {
        auto rhs = codegen(op->rhs());
        auto lhs = codegen(op->lhs());
        auto opType = Types::get(resolveType(lhs));
        if (!opType) {
            throw InternalCompilerError("Unable to determine operand types for {0} {2} {1}",
                                        Types::toString(lhs->getType()),
                                        Types::toString(rhs->getType()),
                                        op->rtti()->name());
        }
        auto typeOps = TypeOps::get(*opType);
        auto mathOp = compoundOp(op);
        auto lhsOperand = typeOps->coerce(read(lhs));
        auto rhsOperand = typeOps->coerce(read(rhs));
        auto result = std::invoke(mathOp, typeOps, lhsOperand, rhsOperand);
        typeOps->assign(lhs, result);
        return lhs;
    }

    static llvm::Value* emit(Ref<BinaryOp> op) {
        if (op->is<CompoundAssign>())
            return emit(op.as<CompoundAssign>());

        auto rhs = codegen(op->rhs());
        auto lhs = codegen(op->lhs());
        lhs = read(lhs);
        rhs = read(rhs);
        auto opType = operandType(op, lhs->getType(), rhs->getType());
        if (!opType) {
            throw InternalCompilerError("Unable to determine operand types for {0} {2} {1}",
                                        Types::toString(lhs->getType()),
                                        Types::toString(rhs->getType()),
                                        op->rtti()->name());
        }
        auto typeOps = TypeOps::get(*opType);
        auto lhsOperand = typeOps->coerce(lhs);
        auto rhsOperand = typeOps->coerce(rhs);
        auto typeOp = binaryOp(op);
        auto result = std::invoke(typeOp, typeOps, lhsOperand, rhsOperand);
        return result;
    }

    static llvm::Value* codegen(Ref<Node> node) {
        llvm::Value* value = nullptr;
        if (node->is<BinaryOp>())
            value = emit(node.as<BinaryOp>());
        else if (node->is<FieldDef>())
            value = emit(node.as<FieldDef>());
        else if (node->is<VariableDef>())
            value = emit(node.as<VariableDef>());
        else if (node->is<ThisRef>())
            value = emit(node.as<ThisRef>());
        else if (node->is<MemberRef>())
            value = emit(node.as<MemberRef>());
        else if (node->is<VariableRef>())
            value = emit(node.as<VariableRef>());
        else if (node->is<FunctionDef>())
            value = emit(node.as<FunctionDef>());
        else if (node->is<Return>())
            value = emit(node.as<Return>());
        else if (node->is<FunctionCall>())
            value = emit(node.as<FunctionCall>());
        else if (node->is<StringLiteral>())
            value = emit(node.as<StringLiteral>());
        else if (node->is<FloatLiteral>())
            value = emit(node.as<FloatLiteral>());
        else if (node->is<IntegerLiteral>())
            value = emit(node.as<IntegerLiteral>());
        if (value) {
            PEP_TRACE(TraceChannel::Codegen, "{0} -> {1}", node->toString(), toString(value));
            return value;
        }
        throw InternalCompilerError("Unknown AST node");
    }

    static Ref<Struct> codegenStruct(Ref<StructDef> structDef) {
        auto st = emit(structDef);
        PEP_TRACE(
            TraceChannel::Codegen, "StructDef {0} -> {1}", structDef->identifier(), toString(st->type()->llvmType()));
        return st;
    }

    Codegen::Codegen(const Name& moduleName, Ref<ast::AST> tree)
        : Tree(tree) {
        Ctx = Ref<Context>::New(moduleName);
        Module = Ctx->moduleContext();
    }

    Ref<ModuleContext> Codegen::emit() {
        for (auto root : Tree->roots()) {
            try {
                if (root->is<StructDef>())
                    codegenStruct(root.as<StructDef>());
                else
                    codegen(root);
            } catch (CompileError ce) {
                Messages::Report<Error>(ce.what());
            } catch (InternalCompilerError ice) {
                Messages::Report<Error>(ice.what());
                return nullptr;
            }
        }
        return Context::get().moduleContext();
    }
} // namespace pepper
