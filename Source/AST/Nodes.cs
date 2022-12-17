
using Pepper.Codegen;

namespace Pepper.AST {
    public abstract class Node {
        public SourceLocation Source { get; private set; }

        public Node() {
            Source = SourceLocation.Current;
        }

        // Each node should only every be codegen'ed once
        private Func<Node, Value> CachedCodegen = Memoizer.Memoize<Node, Value>(node => node.Codegen());
        // This is the implementation that gets overridden by nodes
        protected abstract Value Codegen();
        // This is the public interface. The parameter is a dummy to differentiate the signatures
        public Value Codegen(object? dummy = null) => CachedCodegen(this);
    }

    // A symbol is anything with a type and a name (variable, function, parameter, etc)
    public class Symbol : Node {
        public Type Type { get; private set; }
        public string Name { get; private set; }
        public Symbol(Type type, string name) {
            Type = type;
            Name = name;
        }

        protected override Value Codegen() {
            throw new NotImplementedException();
        }
        public static implicit operator Codegen.Symbol(Symbol sym) => new Codegen.Symbol(sym.Type, sym.Name);
    }

    public abstract class Expression : Node {
        public abstract Type Type { get; }
    }
}
