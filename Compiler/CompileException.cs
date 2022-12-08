using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal class CompileException : Exception {
        public CompileException(string message) : base(message) { }
        public CompileException(string message, Exception innerException) : base(message, innerException) { }
    }

    internal class InternalCompilerException : Exception {
        public InternalCompilerException(string message) : base(message) { }
        public InternalCompilerException(string message, Exception innerException) : base(message, innerException) { }
    }
}
