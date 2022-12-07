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
        LLVMValueRef? ValueRef;

        public LLVMValueRef Ref {
            get {
                if (ValueRef.HasValue) {
                    return ValueRef.Value;
                }
                throw new CompileException("Value dereferenced before being allocated");
            }
            protected set {
                ValueRef = value;
            }
        }

        public Value(Type type, string name = "Anonymous value", LLVMBuilderRef? builder = null) {
            Type = type;
            Name = name;
            if (builder.HasValue) {
                Alloc(builder.Value);
            }
        }

        public Value(Type type, LLVMValueRef valueRef, string name = "Unnamed value") {
            Type = type;
            Name = name;
            ValueRef = valueRef;
        }

        public virtual LLVMValueRef Alloc(LLVMBuilderRef builder) {
            return Ref = builder.BuildAlloca(Type, Name);
        }

        public static implicit operator LLVMValueRef(Value v) => v.Ref;
    }

    internal class Constant : Value {
        public Constant(Type type, string name = "Anonymous constant", LLVMBuilderRef? builder = null)
            : base(type, name, builder) {
        }

        public override LLVMValueRef Alloc(LLVMBuilderRef builder) {
            throw new NotImplementedException();
        }
    }

    internal class ConstantInt : Constant {
        private long Value;
        public ConstantInt(long value, string name = "Anonymous constant integer", LLVMBuilderRef? builder = null) 
            : base(IntegralType.I64, name) {
            Value = value;
            if (builder.HasValue) {
                Alloc(builder.Value);
            }
        }

        public override LLVMValueRef Alloc(LLVMBuilderRef builder) {
            return Ref = LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, (ulong)Value);
        }
    }

    internal class ConstantDouble : Constant {
        private double Value;
        public ConstantDouble(double value, string name = "Anonymous constant double", LLVMBuilderRef? builder = null)
            : base(IntegralType.Double, name) {
            Value = value;
            if (builder.HasValue) {
                Alloc(builder.Value);
            }
        }

        public override LLVMValueRef Alloc(LLVMBuilderRef builder) {
            return Ref = builder.BuildStore(LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, BitConverter.DoubleToUInt64Bits(Value)), Ref);
        }
    }
}
