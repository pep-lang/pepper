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
                return Alloc(Context.Locals.FunctionRegisters);
            }
            protected set {
                AddressRef = value;
            }
        }

        public string RegisterName => AddressRef.HasValue ? AddressRef.Value.RegisterName(ToString()) : "null";
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
        protected Value(Type type, Value value, string name = "", SourceLocation? source = null, LLVMBuilderRef? builder = null)
            : base(type, name) {
            Source = source ?? Source;
            Store(value, builder);
        }

        public void Replace(LLVMValueRef newValue) {
            if (AddressRef.HasValue && AddressRef.Value.TypeOf != newValue.TypeOf) {
                Compiler.Report<Warning>($"Replacing {this} with mismatched type: expected {AddressRef.Value}, got {newValue.TypeOf}", Source);
            }
            AddressRef = newValue;
        }

        public virtual LLVMValueRef Alloc(LLVMBuilderRef? builder = null) {
            builder ??= Context.Locals.FunctionRegisters;
            Address = Type.Alloc(builder, Name);
            return Address;
        }

        public virtual Value Store(LLVMBuilderRef? builder = null) {
            var val = Address;
            AddressRef = Alloc(builder);
            Store(val, builder);
            return this;
        }

        public virtual Value Store(Value value, LLVMBuilderRef? builder = null) {
            Source = value.Source != SourceLocation.Unknown ? value.Source : Source;
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
            return new Value(Type, builder.Value.BuildLoad2(Type, Address, Name), source: Source);
        }

        public Value AsBool() => Type.AsBool(this);
        public virtual Value As(Type type) => (type == Types.Bool ? Type.AsBool(this) : type.Coerce(this)).Load();

        public override string ToString() {
            var addr = AddressRef.HasValue ? AddressRef.ToString()! : "undefined";
            var name = Name != "" && !addr.Contains($"%{Name}") ? $"{Name} " : "";
            return $"{name}{addr}";
        }
        public static implicit operator LLVMValueRef(Value v) => v.Address;
        public static implicit operator Value(LLVMValueRef v) => new Value(Types.From(v.TypeOf), v, v.Name);
    }

    public class Constant : Value {
        public Constant(Type type, LLVMValueRef value, string name)
            : base(type, value, name) {
        }

        public override LLVMValueRef Store(LLVMValueRef value, LLVMBuilderRef? builder) => throw new CompileError($"Cannot store to constant {this}");

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
            : base(Types.ConstantString, Context.Module.Context.GetConstString(name, false), name) {
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
        public override Value Load(LLVMBuilderRef? builder) => throw new InternalCompilerError($"Attempted to load an instruction {this}");
        public override Value Store(LLVMBuilderRef? builder = null) => throw new InternalCompilerError($"Attempted to store instruction {this}");
        public override LLVMValueRef Alloc(LLVMBuilderRef? builder = null) => throw new InternalCompilerError($"Attempted to alloca instruction {this}");
    }
}
