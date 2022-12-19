
namespace Pepper {
    internal abstract class CompilerException : Exception {
        public SourceLocation? SourceLocation { get; private set; }

        public CompilerException(string message, SourceLocation? sourceLocation = null)
            : base($"{sourceLocation}: {message}") {
            SourceLocation = sourceLocation;
        }
    }

    internal class CompileError : CompilerException {
        public CompileError(string message, SourceLocation? sourceLocation = null)
            : base(message, sourceLocation) {
        }
    }

    internal class InternalCompilerError : CompilerException {
        public InternalCompilerError(string message, SourceLocation? sourceLocation = null)
            : base(message, sourceLocation) {
        }
    }
}
