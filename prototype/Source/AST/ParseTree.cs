
using LLVMSharp;
using Pepper.Codegen;
using System.Security;

namespace Pepper.AST {

    public class ParseTree {
        public List<Symbol> TopLevelSymbols = new();

        public Builder Builder() => new(this);

        public ParseTree() { }

        public ScopeTree AsScopeTree() {
            var tree = new ScopeTree();
            foreach (var symbol in TopLevelSymbols) {
                var scope = tree.Root;
                Walk(n => {
                    if (n is Symbol s) {
                        scope[s.Name] = s;
                    }
                    scope.Nodes.Add(n);
                    if (n is FunctionDef f) {
                        scope = tree.PushScope(f.Name);
                    }                    
                    if (n is FunctionEnd) {
                        scope = tree.PopScope();
                    }
                }, symbol);
            }
            return tree;
        }

        private void Walk(Action<Node> visit, Node node) {
            visit(node);
            foreach (var child in node.Children) {
                Walk(visit, child);
            }
        }
    }
}
