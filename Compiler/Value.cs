using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal class Value {
        public Type Type;
        public string Name { get; private set; }
        LLVMValueRef? AddressRef;

        public LLVMValueRef Address {
            get {
                if (AddressRef.HasValue) {
                    return AddressRef.Value;
                }
                return (LLVMValueRef)(AddressRef = Alloc(Context.Default.Locals.Builder));
            }
            protected set {
                AddressRef = value;
            }
        }

        public Value(Type type, string name = "") {
            Type = type;
            Name = name;
        }

        public Value(Type type, LLVMValueRef value, string name = "")
            : this(type, name) {
            AddressRef = value;
        }

        public Value(Type type, Value value, string name = "") 
            : this(type, name) {
            AddressRef = Store(value, Context.Default.Locals.Builder);
        }

        public virtual LLVMValueRef Alloc(LLVMBuilderRef builder) {
            return Type.Alloc(builder);
        }

        public virtual LLVMValueRef Store(Value value, LLVMBuilderRef builder) {
            return Store(value.Load(builder), builder);
        }

        public virtual LLVMValueRef Store(LLVMValueRef value, LLVMBuilderRef builder) {
            return builder.BuildStore(value, Address);
        }

        public virtual LLVMValueRef Load(LLVMBuilderRef builder) {
            return builder.BuildLoad2(Type, Address, Name);
        }

        public override string ToString() {
            var addr = (AddressRef.HasValue ? AddressRef.ToString() : "undefined");
            return $"{Type} {Name}{addr}";
        }
        public static implicit operator LLVMValueRef(Value v) => v.Address;
    }

    internal class Constant : Value {
        public Constant(Type type, string name)
            : base(type, name) {
        }

        public override LLVMValueRef Store(LLVMValueRef value, LLVMBuilderRef builder) => throw new CompileException($"Cannot store to constant {this}");

        public override LLVMValueRef Load(LLVMBuilderRef builder) {
            return Address;
        }
    }

    internal class ConstantInt : Constant {
        private readonly long Value;
        public ConstantInt(long value, string name = "") 
            : base(IntegralType.Int64, name) {
            Value = value;
        }

        public override LLVMValueRef Alloc(LLVMBuilderRef builder) {
            return LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, (ulong)Value);
        }

        public override string ToString() => $"{Type} {Value}";
    }

    internal class ConstantDouble : Constant {
        private readonly double Value;
        public ConstantDouble(double value, string name = "")
            : base(IntegralType.Double, name) {
            Value = value;
        }

        public override LLVMValueRef Alloc(LLVMBuilderRef builder) {
            return builder.BuildStore(LLVMValueRef.CreateConstReal(IntegralType.Double, Value), Address);
            //return builder.BuildStore(LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, BitConverter.DoubleToUInt64Bits(Value)), Address);
        }

        public override string ToString() => $"{Type} {Value}";
    }

    internal class ConstantString : Constant {
        private readonly string Value;
        public ConstantString(string value, string name = "")
            : base(IntegralType.Int8.Pointer(), name) {
            Value = value;
        }

        public override LLVMValueRef Alloc(LLVMBuilderRef builder) {
            return builder.BuildGlobalString(Value, Name);
        }

        public override string ToString() => $"{Type} \"{Value}\"";
    }
}
