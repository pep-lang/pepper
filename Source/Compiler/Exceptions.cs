
namespace Pepper {
    internal abstract class Error : Exception {
        public SourceLocation? SourceLocation { get; private set; }

        public Error(string message, SourceLocation? sourceLocation = null)
            : base(message) {
            SourceLocation = sourceLocation;
        }
    }

    internal class CompileError : Error {
        public CompileError(string message, SourceLocation? sourceLocation = null)
            : base(message, sourceLocation) {
        }
    }

    internal class InternalCompilerError : Error {
        public InternalCompilerError(string message, SourceLocation? sourceLocation = null)
            : base(message, sourceLocation) {
        }
    }
}
