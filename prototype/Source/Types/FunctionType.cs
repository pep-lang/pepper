using LLVMSharp.Interop;
using Pepper.Codegen;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection.Metadata;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    public class FunctionType : Type {
        public Type ReturnType { get; private set; }
        public IEnumerable<Symbol> Parameters { get; private set; }
        public bool Varargs { get; private set; } = false;

        protected FunctionType(Type returnType, IEnumerable<Symbol> parameters, bool varargs = false)
            : base(Signature(returnType, parameters, varargs), LLVMTypeRef.CreateFunction(returnType, parameters.Select(p => p.Type.Ref).ToArray(), varargs)) {
            ReturnType = returnType;
            Parameters = parameters;
            Varargs = varargs;
        }

        public override PointerType Pointer() => throw new NotImplementedException();

        public override Value Coerce(Value val) {
            throw new NotImplementedException();
        }

        public static FunctionType Create(Type returnType, IEnumerable<Symbol> parameters, bool varargs = false) {
            string sig = Signature(returnType, parameters, varargs);
            try {
                var func = Context.Locals.GetType<FunctionType>(sig);
                if (func != null)
                    return func;
            } catch {
                var func = Runtime.Environment.GetType<FunctionType>(sig);
                if (func != null)
                    return func;
            }

            return new FunctionType(returnType, parameters, varargs);
        }

        protected static string Signature(Type returnType, IEnumerable<Symbol> parameters, bool varargs = false) {
            var paramsList = string.Join(", ", parameters.Select(p => $"{p.Type.Name} {p.Name}"));
            var ellipsis = varargs ? ", ..." : "";
            return $"{returnType.Name}({paramsList}{ellipsis})";
        }
    }

    public class MethodType : FunctionType {
        public Type TargetType;

        private MethodType(Type targetType, Type returnType, IEnumerable<Symbol> parameters, bool varargs = false) 
            : base(returnType, parameters, varargs) {
            TargetType = targetType;
            
        }

        public static MethodType Create(Type targetType, Type returnType, IEnumerable<Symbol> parameters, bool varargs = false) {
            string sig = Signature(returnType, parameters);
            sig = $"{targetType.Name}.{sig}";
            try {
                var method = Context.Locals.GetType<MethodType>(sig);
                if (method != null)
                    return method;
            } catch { }
            return new MethodType(targetType, returnType, parameters, varargs);
        }
    }
}
