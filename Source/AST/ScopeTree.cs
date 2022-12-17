using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Security;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.AST {
    
    public class ScopeTree {
        public class Scope {
            public string Name;
            public List<Node> Nodes = new();
            public Dictionary<string, Symbol> Symbols = new();
            public List<Scope> Inners = new();
            public Scope? Outer;

            public Scope(string name, Scope? outer = null) {
                Name = name;
                Outer = outer;
            }

            public Symbol? this[string name] {
                get {
                    if (Symbols.TryGetValue(name, out var sym))
                        return sym;
                    return Outer?[name];
                }
                set { Symbols[name] = value!; }
            }
        }

        public Scope Root { get; protected set; }
        protected Scope Current;

        public ScopeTree(string name = "Module") {
            Root = new Scope(name);
            Current = Root;
        }

        public Scope PushScope(string name) {
            var scope = new Scope(name, Current);
            Current.Inners.Add(scope);
            return Current = scope;
        }

        public Scope PopScope() {
            return Current = Current == Root ? Root : Current.Outer!;
        }

        public void WalkBreadthFirst(Action<Scope> visit, Scope? scope = null) {
            scope ??= Root;
            visit(scope);
            scope.Inners.ForAll(s => WalkBreadthFirst(visit, s));
        }

        public void WalkDepthFirst(Action<Scope> visit, Scope? scope = null) {
            scope ??= Root;
            scope.Inners.ForAll(s => WalkDepthFirst(visit, s));
            visit(scope);
        }

        public IEnumerable<Scope> BreadthFirst() {
            var scopes = new List<Scope>();
            WalkBreadthFirst(s => scopes.Add(s));
            return scopes;
        }

        public IEnumerable<Scope> DepthFirst() {
            var scopes = new List<Scope>();
            WalkDepthFirst(s => scopes.Add(s));
            return scopes;
        }
    }
}
