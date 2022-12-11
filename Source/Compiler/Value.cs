using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    internal class TypedValue {
        public Type Type;
        public string Name { get; private set; }

        public TypedValue(Type type, string name) {
            Type = type;
            Name = name;
        }
    }

    internal class Value : TypedValue {
        LLVMValueRef? AddressRef;
        public LLVMValueRef Address {
            get {
                if (AddressRef.HasValue) {
                    return AddressRef.Value;
                }
                return Alloc(Context.Default.Locals.FunctionRegisters);
            }
            private set {
                AddressRef = value;
            }
        }

        // Take ownership of an already constructed value directly
        public Value(Type type, LLVMValueRef value, string name = "")
            : base(type, name) {
            Address = value;
        }

        // Copy/Store another value as Type
        public Value(Type type, Value value, string name = "", LLVMBuilderRef? builder = null) 
            : base(type, name) {
            Store(value, builder);
        }

        public virtual LLVMValueRef Alloc(LLVMBuilderRef? builder = null) {
            Debug.Assert(!AddressRef.HasValue);
            builder ??= Context.Default.Locals.FunctionRegisters;
            Address = Type.Alloc(builder, Name);
            return Address;
        }

        public virtual LLVMValueRef Store(Value value, LLVMBuilderRef? builder = null) {
            builder ??= Context.Default.Locals.Builder;
            return Store(value.Load(builder), builder);
        }

        public virtual LLVMValueRef Store(LLVMValueRef value, LLVMBuilderRef? builder = null) {
            builder ??= Context.Default.Locals.Builder;
            return builder.Value.BuildStore(value, Address);
        }

        public virtual LLVMValueRef Load(LLVMBuilderRef? builder = null) {
            if (Address.IsAConstant != null) {
                return Address;
            }
            builder ??= Context.Default.Locals.Builder;
            return builder.Value.BuildLoad2(Type, Address, Name);
        }

        public override string ToString() {
            var addr = (AddressRef.HasValue ? AddressRef.ToString()! : "undefined");
            var name = Name != "" ? $"{Name} " : "";
            return $"{name}{addr}";
        }
        public static implicit operator LLVMValueRef(Value v) => v.Address;
    }

    internal class Constant : Value {
        public Constant(Type type, LLVMValueRef value, string name)
            : base(type, value, name) {
        }

        public override LLVMValueRef Store(LLVMValueRef value, LLVMBuilderRef? builder) => throw new CompileException($"Cannot store to constant {this}");

        public override LLVMValueRef Load(LLVMBuilderRef? builder) {
            return Address;
        }
    }

    internal class ConstantInt : Constant {
        private readonly long Value;
        public ConstantInt(long value, string name = "") 
            : base(Types.Int64, LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, (ulong)value), name) {
            Value = value;
        }

        public override LLVMValueRef Alloc(LLVMBuilderRef? builder) {
            return this;
        }

        public override string ToString() => $"{Type} {Value}";
    }

    internal class ConstantDouble : Constant {
        private readonly double Value;
        public ConstantDouble(double value, string name = "")
            : base(Types.Double, LLVMValueRef.CreateConstReal(Types.Double, value), name) {
            Value = value;
        }

        public override LLVMValueRef Alloc(LLVMBuilderRef? builder) {
            return this;
            //return builder.Value.BuildStore(LLVMValueRef.CreateConstReal(IntegralType.Double, Value), Address);
            //return builder.BuildStore(LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, BitConverter.DoubleToUInt64Bits(Value)), Address);
        }

        public override string ToString() => $"{Type} {Value}";
    }

    internal class ConstantString : Constant {
        private readonly string Value;
        public ConstantString(string value, string name = "")
            : base(Types.Int8Ptr, Context.Default.Locals.Builder.BuildGlobalString(value, name), name) {
            Value = value;
        }

        public override LLVMValueRef Alloc(LLVMBuilderRef? builder) {
            return this;
        }

        public override string ToString() => $"{Type} \"{Value}\"";
    }
}
