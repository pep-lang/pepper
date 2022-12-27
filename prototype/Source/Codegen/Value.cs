using LLVMSharp;
using LLVMSharp.Interop;
using System.Diagnostics;

namespace Pepper.Codegen {

    public class Symbol {
        public Type Type;
        public string Name { get; protected set; }

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
                return Alloc();
            }
            protected set {
                AddressRef = value;
            }
        }

        public string RegisterName => AddressRef.HasValue ? AddressRef.Value.RegisterName(ToString()) : "null";
        LLVMBuilderRef Registers => Context.Locals.FunctionRegisters;
        LLVMBuilderRef Builder => Context.Locals.Builder;
        public SourceLocation Source { get; protected set; } = SourceLocation.Unknown;

        static Dictionary<Type, System.Type> ByType = new();
        // Take ownership of an already constructed value directly
        public static Value New(Type type, LLVMValueRef value, string name = "", SourceLocation? source = null) {
            if (ByType.TryGetValue(type, out var valType)) {
                return (Value)Activator.CreateInstance(valType, type, value, name, source)!;
            }
            return new Value(type, value, name, source);
        }

        // Copy/Store another value as Type
        public static Value New(Type type, Value value, string name = "", SourceLocation? source = null) {
            if (ByType.TryGetValue(type, out var valType)) {
                return (Value)Activator.CreateInstance(valType, type, value, name, source)!;
            }
            return new Value(type, value, name, source);
        }

        // Take ownership of an already constructed value directly
        public static Value New<V>(Type type, LLVMValueRef value, string name = "", SourceLocation? source = null) where V : Value {
            ByType.TryAdd(type, typeof(V));
            return (V)Activator.CreateInstance(typeof(V), type, value, name, source)!;
        }

        // Copy/Store another value as Type
        public static Value New<V>(Type type, Value value, string name = "", SourceLocation? source = null) where V : Value {
            ByType.TryAdd(type, typeof(V));
            return (V)Activator.CreateInstance(typeof(V), type, value, name, source)!;
        }

        // Take ownership of an already constructed value directly
        protected Value(Type type, LLVMValueRef value, string name = "", SourceLocation? source = null)
            : base(type, name) {
            Address = value;
            Source = source ?? Source;
        }

        // Copy/Store another value as Type
        protected Value(Type type, Value value, string name = "", SourceLocation? source = null)
            : base(type, name) {
            Source = source ?? Source;
            Store(value);
        }

        public virtual LLVMValueRef Alloc() {
            Address = Type.Alloc(Registers, Name);
            return Address;
        }

        public virtual Value Store(Value value) {
            Source = value.Source != SourceLocation.Unknown ? value.Source : Source;
            Store(Type.Coerce(value).Load().Address);
            return this;
        }

        public virtual LLVMValueRef Store(LLVMValueRef value) {
            // It would be better if exact types could be matched, but alloc and instructions dont have
            // types that can be extracted, so just make sure they're at least the same size/alignment
            //if (value.TypeOf.SizeOf != Type.Ref.SizeOf || value.TypeOf.AlignOf != Type.Ref.AlignOf) {
            //    throw new InternalCompilerException($"Attempted to store a value of type {value.TypeOf} to a value of type {Type}");
            //}
            return Builder.BuildStore(value, Address);
        }

        public virtual Value Load() {
            if (Address.IsALoadInst != null)
                return this;
            if (Address.IsAAllocaInst == null && Address.IsAInstruction == null) {
                return this;
            }
            return new Value(Type, Builder.BuildLoad2(Type, Address, Name), source: Source);
        }

        public Value AsBool() => Type.AsBool(this);
        public virtual Value As(Type type) => (type == Types.Bool ? Type.AsBool(this) : type.Coerce(this)).Load();

        public override string ToString() {
            var addr = AddressRef.HasValue ? AddressRef.ToString()! : "undefined";
            var name = Name != "" && !addr.Contains($"%{Name}") ? $"{Name} " : "";
            return $"{name}{addr}";
        }
        public static implicit operator LLVMValueRef(Value v) => v.Address;
        public static implicit operator Value(LLVMValueRef v) => new Value(Types.From(v), v, v.Name);

        public static readonly Value Null = new Value(Types.VoidPtr, LLVMValueRef.CreateConstPointerNull(Types.VoidPtr));
    }

    public class Constant : Value {
        public Constant(Type type, LLVMValueRef value, string name)
            : base(type, value, name) {
        }

        public override LLVMValueRef Store(LLVMValueRef value) => throw new CompileError($"Cannot store to constant {this}");

        public override Value Load() {
            return this;
        }

        public override LLVMValueRef Alloc() {
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
                return New(intType, LLVMValueRef.CreateConstInt(type, Value ? 1ul : 0ul, false));
            return base.As(type);
        }

        public static ConstantBool True => new(true, "true");
        public static ConstantBool False => new(false, "false");
    }

    public class ConstantInt32 : Constant {
        private readonly long Value;
        public ConstantInt32(int value, string name = "")
            : base(Types.ConstantInt32, LLVMValueRef.CreateConstInt(LLVMTypeRef.Int32, (ulong)value), name) {
            Value = value;
        }

        public override string ToString() => $"{Type} {Value}";
    }

    public class ConstantInt64 : Constant {
        private readonly long Value;
        public ConstantInt64(long value, string name = "")
            : base(Types.ConstantInt64, LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, (ulong)value), name) {
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
            : base(Types.ConstantPointer, new ConstantInt64(value), name) {
            Value = value;
        }
    }

    public class Instruction : Value {
        public Instruction(LLVMValueRef instr)
            : base(Types.Instruction, instr) { }
        public override Value Load() => throw new InternalCompilerError($"Attempted to load from an instruction {this}");
        public override Value Store(Value value) => throw new InternalCompilerError($"Attempted to store to an instruction {this}");
        public override LLVMValueRef Alloc() => throw new InternalCompilerError($"Attempted to alloca instruction {this}");
    }
}
