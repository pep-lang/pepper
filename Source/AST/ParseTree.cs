
using LLVMSharp;
using Pepper.Codegen;

namespace Pepper.AST {

    public class ParseTree {
        public class Scope {
            public string Name = "";
            public IEnumerable<Node> Nodes = Enumerable.Empty<Node>();
            public Scope? Inner;
            public Scope? Outer;
        }

        public class QueryResult {
            public Scope? Root { get; protected set; }
            private Scope? Current;

            public static implicit operator bool(QueryResult res) => res.Root != null;

            public Scope PushScope(string name) {
                Root ??= new Scope() { Name = "Root" };
                Current ??= Root;
                return Current.Inner = new Scope() { Name = name };
            }

            public Scope PopScope() {
                if (Root == null) throw new InternalCompilerError("ParseTree scope popped with no root");
                return Current == Root ? Root! : Current!.Outer!;
            }
        }

        public List<Symbol> TopLevelSymbols = new();

        public Builder Builder() => new(this);

        public ParseTree() { }

        public QueryResult Query(params System.Type[] nodeTypes) {
            return Query(nodeTypes);
        }

        public QueryResult Query(IEnumerable<System.Type> nodeTypes) {
            return Query(n => true, nodeTypes);
        }

        public QueryResult Query(Func<Node, bool> filter, params System.Type[] nodeTypes) {
            return Query(filter, nodeTypes);
        }

        public QueryResult Query(Func<Node, bool> filter, IEnumerable<System.Type> nodeTypes) {
            var result = new QueryResult();
            var includedTypes = new HashSet<System.Type>(nodeTypes);
            foreach (var symbol in TopLevelSymbols) {

            }
            return result;
        }
    }
}
