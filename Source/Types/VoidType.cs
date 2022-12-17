using LLVMSharp.Interop;
using Pepper.Codegen;

namespace Pepper {
    public class VoidType : NativeType {
        public override Value DefaultValue => throw new InternalCompilerError("void should never be used as a default value");

        public VoidType(string name, LLVMTypeRef typeRef)
            : base(name, typeRef) {
        }

        public override PointerType Pointer() {
            return new PointerType("void*", this);
        }

        public override Value Coerce(Value val) {
            throw new CompileError($"Cannot convert {val.Type} to void");
        }

        public override Value CreateConstant<U>(U value) => throw new InternalCompilerError("It is not possible to create a void constant");
    }
}
