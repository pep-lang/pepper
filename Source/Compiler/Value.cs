using LLVMSharp;
using LLVMSharp.Interop;
using System.Diagnostics;

namespace Pepper {
    public class Symbol {
        public Type Type;
        public string Name { get; private set; }

        public Symbol(Type type, string name) {
            Type = type;
            Name = name;
        }
    }

    public class Value : Symbol {
        LLVMValueRef? AddressRef;
        public LLVMValueRef Address {
            get {
                if (AddressRef.HasValue) {
                    return AddressRef.Value;
                }
                return Alloc(Context.Locals.FunctionRegisters);
            }
            protected set {
                AddressRef = value;
            }
        }

        public string RegisterName => AddressRef.HasValue ? AddressRef.Value.RegisterName() : "null";

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
            builder ??= Context.Locals.FunctionRegisters;
            Address = Type.Alloc(builder, Name);
            return Address;
        }

        public virtual Value Store(LLVMBuilderRef? builder = null) {
            var val = Address;
            AddressRef = null;
            Store(val, builder);
            return this;
        }

        public virtual Value Store(Value value, LLVMBuilderRef? builder = null) {
            builder ??= Context.Locals.Builder;
            Store(Type.Coerce(value).Load().Address, builder);
            return this;
        }

        public virtual LLVMValueRef Store(LLVMValueRef value, LLVMBuilderRef? builder = null) {
            builder ??= Context.Locals.Builder;
            // It would be better if exact types could be matched, but alloc and instructions dont have
            // types that can be extracted, so just make sure they're at least the same size/alignment
            //if (value.TypeOf.SizeOf != Type.Ref.SizeOf || value.TypeOf.AlignOf != Type.Ref.AlignOf) {
            //    throw new InternalCompilerException($"Attempted to store a value of type {value.TypeOf} to a value of type {Type}");
            //}
            return builder.Value.BuildStore(value, Address);
        }

        public virtual Value Load(LLVMBuilderRef? builder = null) {
            if (Address.IsAConstant != null || Address.IsAAllocaInst == null) {
                return this;
            }
            builder ??= Context.Locals.Builder;
            return new Value(Type, builder.Value.BuildLoad2(Type, Address, Name));
        }

        public Value AsBool() => Type.AsBool(this);
        public virtual Value As(Type type) => (type == Types.Bool ? Type.AsBool(this) : type.Coerce(this)).Load();

        public override string ToString() {
            var addr = (AddressRef.HasValue ? AddressRef.ToString()! : "undefined");
            var name = Name != "" && !addr.Contains($"%{Name}") ? $"{Name} " : "";
            return $"{name}{addr}";
        }
        public static implicit operator LLVMValueRef(Value v) => v.Address;
    }

    public class Constant : Value {
        public Constant(Type type, LLVMValueRef value, string name)
            : base(type, value, name) {
        }

        public override LLVMValueRef Store(LLVMValueRef value, LLVMBuilderRef? builder) => throw new CompileException($"Cannot store to constant {this}");

        public override Value Load(LLVMBuilderRef? builder) {
            return this;
        }

        public override LLVMValueRef Alloc(LLVMBuilderRef? builder) {
            return this;
        }
    }

    public class ConstantBool : Constant {
        private readonly bool Value;
        public ConstantBool(bool value, string name = "")
            : base(Types.ConstantBool, LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, value ? 1ul : 0ul), name) {
            Value = value;
        }

        public override string ToString() => $"{Type} {Value}";
        public override Value As(Type type) {
            if (type is IntegerType intType)
                return new Value(intType, LLVMValueRef.CreateConstInt(type, Value ? 1ul : 0ul, false));
            return base.As(type);
        }

        public static ConstantBool True => new(true, "true");
        public static ConstantBool False => new(false, "false");
    }

    public class ConstantInt : Constant {
        private readonly long Value;
        public ConstantInt(long value, string name = "")
            : base(Types.ConstantInt, LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, (ulong)value), name) {
            Value = value;
        }

        public override string ToString() => $"{Type} {Value}";
    }

    public class ConstantFloat : Constant {
        private readonly double Value;
        public ConstantFloat(double value, string name = "")
            : base(Types.ConstantFloat, LLVMValueRef.CreateConstReal(Types.Double, value), name) {
            Value = value;
        }

        public override string ToString() => $"{Type} {Value}";
    }

    public class ConstantString : Constant {
        private readonly string Value;
        public ConstantString(string value, string name = "")
            : base(Types.ConstantString, Context.Locals.Builder.BuildGlobalString(value, name), name) {
            Value = value;
        }

        public override string ToString() => $"{Type} \"{Value}\"";
    }

    public class ConstantPointer : Constant {
        private readonly IntPtr Value;
        public ConstantPointer(IntPtr value, string name = "")
            : base(Types.ConstantPointer, Types.Int8.Pointer().CreateConstant(value), name) {
            Value = value;
        }
    }

    public class Instruction : Value {
        public Instruction(LLVMValueRef instr)
            : base(Types.Instruction, instr) { }
        public override Value Load(LLVMBuilderRef? builder) => throw new InternalCompilerException($"Attempted to load an instruction {this}");
        public override Value Store(LLVMBuilderRef? builder = null) => throw new InternalCompilerException($"Attempted to store instruction {this}");
        public override LLVMValueRef Alloc(LLVMBuilderRef? builder = null) => throw new InternalCompilerException($"Attempted to alloca instruction {this}");
    }
}
