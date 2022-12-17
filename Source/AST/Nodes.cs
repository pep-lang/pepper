
using Pepper.Codegen;

namespace Pepper.AST {
    public abstract class Node {
        public SourceLocation Source { get; private set; }

        public Node() {
            Source = SourceLocation.Current;
        }

        public N Cast<N>() where N : Node {
            return (N)this;
        }
    }

    // A symbol is anything with a type and a name (variable, function, parameter, etc)
    public class Symbol : Node {
        public Type Type { get; private set; }
        public string Name { get; private set; }
        public Symbol(Type type, string name) {
            Type = type;
            Name = name;
        }

        public static implicit operator Codegen.Symbol(Symbol sym) => new Codegen.Symbol(sym.Type, sym.Name);
    }

    public abstract class Expression : Node {
        public abstract Type Type { get; }
    }
}
