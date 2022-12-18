using Pepper.Codegen;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.AST {
    public class Builder {
        class Scope {
            public string Name { get; set; } = "Anonymous";
            public Dictionary<string, StructDef> Structs = new();
            public Dictionary<string, Symbol> Symbols = new();
            public List<Symbol> SymbolOrder = new();
            public Dictionary<string, FunctionDef> Functions = new();
            public List<FunctionDef> FunctionOrder = new();
            public List<Expression> Expressions = new();
            public Stack<Node> Stack = new();
            public FunctionDef? ReturnTarget = null;
            public StructDef? Struct = null;
        }

        readonly Stack<Scope> Scopes = new();

        Scope Globals => Scopes.Last();

        public FunctionDef? FunctionTarget {
            get {
                foreach (var scope in Scopes) {
                    if (scope.ReturnTarget != null)
                        return scope.ReturnTarget;
                }
                return null;
            }
        }

        public StructDef? StructTarget {
            get {
                foreach (var scope in Scopes) {
                    if (scope.Struct != null)
                        return scope.Struct;
                }
                return null;
            }
        }

        readonly ParseTree AST;
        public Builder(ParseTree ast) {
            AST = ast;
            BeginScope("Global"); // globals/top level
        }

        public Type? FindType(string name) {
            foreach (var scope in Scopes) {
                if (scope.Structs.TryGetValue(name, out var type))
                    return type.Type;
            }
            return Context.Locals.GetType(name);
        }

        public FunctionDef? FindFunction(string name) {
            foreach (var scope in Scopes) {
                if (scope.Functions.TryGetValue(name, out var localFunc))
                    return localFunc;
            }
            var globalFunc = Context.Locals.GetFunction(name);
            if (globalFunc != null) {
                var globalDef = new FunctionDef(globalFunc.ReturnType, name, globalFunc.Parameters.Select(p => new FunctionDef.Parameter(p.Type, p.Name)), globalFunc.Varargs);
                Globals.Functions.Add(name, globalDef);
                Globals.FunctionOrder.Add(globalDef);
                return globalDef;
            }
            return null;
        }

        public Symbol? FindSymbol(string name) {
            foreach (var scope in Scopes) {
                if (scope.Symbols.TryGetValue(name, out var variable))
                    return variable;
            }
            return null;
        }

        public Builder BeginFunction(FunctionDef func) {
            var scope = Scopes.Peek();
            scope.Functions[func.Name] = func;
            scope.FunctionOrder.Add(func);
            NewSymbol(func);

            if (StructTarget == null) {
                AST.TopLevelSymbols.Add(func);
            }

            BeginScope(func.Name);
            var funcScope = Scopes.Peek();
            funcScope.ReturnTarget = func;
            return this;
        }

        public Builder EndFunction() {
            var scope = Scopes.Peek();
            var func = FunctionTarget!;
            func.Variables = scope.SymbolOrder.Where(v => v is VariableDef).Select(v => (v as VariableDef)!).ToList();
            func.Body = scope.Expressions;
            EndScope();
            return this;
        }

        public Builder BeginStruct(StructDef structDef) {
            var scope = Scopes.Peek();
            scope.Structs.Add(structDef.Name, structDef);
            NewSymbol(structDef);

            if (StructTarget == null && FunctionTarget == null) {
                AST.TopLevelSymbols.Add(structDef);
            }

            BeginScope(structDef.Name);
            var structScope = Scopes.Peek();
            structScope.Struct = structDef;
            return this;
        }

        public Builder EndStruct() {
            var scope = Scopes.Peek();
            var structDef = scope.Struct!;
            structDef.Fields = scope.SymbolOrder.OfType<VariableDef>().ToList();
            structDef.Methods = scope.FunctionOrder.OfType<FunctionDef>().ToList();
            EndScope();
            return this;
        }

        public Builder BeginScope(string name = "") {
            Scopes.Push(new Scope() { Name = name });
            return this;
        }
        public Builder EndScope() {
            Scopes.Pop();
            return this;
        }

        public void PushStack(Node value) {
            var scope = Scopes.Peek();
            scope.Stack.Push(value);
        }

        public Node PopStack() {
            var scope = Scopes.Peek();
            return scope.Stack.Pop();
        }

        public bool TryPopStack<T>(out T value) where T : class {
            var top = PeekStack<T>();
#pragma warning disable CS8601 // Possible null reference assignment
            value = top;
#pragma warning restore CS8601
            return (top != null);
        }

        public T PopStack<T>() where T : class {
            var top = PopStack();
            return top as T ?? throw new CompileError($"Tried to pop {typeof(T)}, found {top}");
        }

        public Node PeekStack(uint idx = 0) {
            var scope = Scopes.Peek();
            return scope.Stack.ElementAt((int)idx);
        }

        public T? PeekStack<T>(uint idx = 0) where T : class {
            return PeekStack(idx) as T;
        }

        public Builder NewSymbol(Symbol symbol) {
            var scope = Scopes.Peek();
            scope.Symbols.Add(symbol.Name, symbol);
            scope.SymbolOrder.Add(symbol);
            return this;
        }

        public Builder NewExpression(Expression expr) {
            var scope = Scopes.Peek();
            scope.Expressions.Add(expr);
            scope.Stack.Push(expr);
            return this;
        }
    }
}
