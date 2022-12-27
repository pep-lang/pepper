using LLVMSharp.Interop;
using Pepper.Codegen;
using System.Data;


namespace Pepper {
    public abstract class Type : IEquatable<Type> {
        public virtual string Name { get; protected set; }
        public virtual LLVMTypeRef Ref { get; protected set; }
        public virtual LLVMValueRef SizeOf => Ref.SizeOf;
        public virtual bool IsInt { get; protected set; } = false;
        public virtual bool IsFloat { get; protected set; } = false;
        public virtual bool IsPointer { get; protected set; } = false;
        public virtual bool IsSigned { get; protected set; } = false;
        public virtual uint Bits => 0;

        public Type(string name, LLVMTypeRef typeRef) {
            Name = name;
            Ref = typeRef;
            Types.Record(this);
        }

        public virtual Value Coerce(Value val) => throw new InternalCompilerError($"{Name} does not support type coercion");
        public virtual PointerType Pointer() => throw new InternalCompilerError($"{Name} does not have a corresponding pointer type");

        public LLVMValueRef Alloc(LLVMBuilderRef? builder, string name = "") {
            builder ??= Context.Locals.FunctionRegisters;
            return builder.Value.BuildAlloca(this, name);
        }

        public virtual Value DefaultValue => throw new InternalCompilerError($"Type {Name} does not have a default value");
        public virtual Value Add(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Sub(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Mul(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Div(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Mod(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Pow(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Less(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Greater(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value LessEqual(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value GreaterEqual(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value LShift(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value RShift(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Equal(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value NotEqual(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value Assign(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value BitAnd(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value BitOr(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value BitXor(Value lhs, Value rhs) => throw new NotImplementedException();
        public virtual Value AsBool(Value val) => throw new NotImplementedException();

        public override bool Equals(object? other) => (other is Type rhs) && Ref == rhs.Ref;
        public bool Equals(Type? other) => other != null ? Ref == other.Ref : false; 

        public override int GetHashCode() => Ref.GetHashCode();

        public override string ToString() => Name;
        public static implicit operator LLVMTypeRef(Type type) => type.Ref;
        public static implicit operator Type(LLVMTypeRef type) => Types.From(type);
    }

    public abstract class NativeType : Type {
        protected static LLVMBuilderRef Builder {
            get {
                return Context.Locals.Builder;
            }
        }

        public override uint Bits => Ref.IntWidth;

        public NativeType(string name, LLVMTypeRef typeRef)
            : base(name, typeRef) {
            Runtime.Environment.AddType(this);
        }

        public override PointerType Pointer() {
            return new PointerType($"{Name}*", this, LLVMTypeRef.CreatePointer(this, 0));
        }

        public virtual Value CreateConstant<U>(U value) => throw new InternalCompilerError($"{Name} is not a valid type for a constant");
    }

    public class InstructionType : NativeType {
        public InstructionType(string name)
            : base(name, LLVMTypeRef.Void) {
        }
    }
}


