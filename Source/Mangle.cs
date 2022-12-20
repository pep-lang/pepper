using Pepper.AST;
using Pepper.Codegen;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    internal static class Mangle {
        public static string Method(StructDef structDef, string functionName) {
            return Method(structDef.Name, functionName);
        }

        public static string Method(string structName, Function func) {
            return Method(structName, func.Name);
        }

        public static string Method(string structName, string funcName) {
            var sep = (funcName.StartsWith("__")) ? "/" : "__";
            return $"${structName}{sep}{funcName}";
        }
    }
}
