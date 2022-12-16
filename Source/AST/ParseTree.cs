using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.AST {
    public class Builder {
        class Scope {
            public Dictionary<string, Type> Types = new();
            public Dictionary<string, VariableDef> Variables = new();
            public List<VariableDef> VariableOrder = new();
            public Dictionary<string, FunctionDef> Functions = new();
            public List<FunctionDef> FunctionOrder = new();
            public List<Expression> Expressions = new();
            public Stack<Node> Stack = new();
            public FunctionDef? ReturnTarget = null;
        }

        readonly Stack<Scope> Scopes = new();

        Scope Globals => Scopes.Last();

        public FunctionDef ReturnTarget {
            get {
                foreach (var scope in Scopes) {
                    if (scope.ReturnTarget != null)
                        return scope.ReturnTarget;
                }
                throw new InternalCompilerException("No return target available during AST build");
            }
        }

        readonly ParseTree AST;
        public Builder(ParseTree ast) {
            AST = ast;
            Scopes.Push(new Scope()); // globals/top level
        }

        public Type? FindType(string name) {
            foreach (var scope in Scopes) {
                if (scope.Types.TryGetValue(name, out var type))
                    return type;
            }
            return Context.Default.Locals.GetType(name);
        }

        public FunctionDef? FindFunction(string name) {
            foreach (var scope in Scopes) {
                if (scope.Functions.TryGetValue(name, out var localFunc))
                    return localFunc;
            }
            var globalFunc = Context.Default.Locals.GetFunction(name);
            if (globalFunc != null) {
                var globalDef = new FunctionDef(globalFunc.ReturnType, name, globalFunc.Parameters.Select(p => new Symbol(p.Type, p.Name)), globalFunc.Varargs);
                Globals.Functions.Add(name, globalDef);
                Globals.FunctionOrder.Add(globalDef);
                return globalDef;
            }
            return null;
        }

        public VariableDef? FindVariable(string name) {
            foreach (var scope in Scopes) {
                if (scope.Variables.TryGetValue(name, out var variable))
                    return variable;
            }
            return null;
        }

        public Symbol? FindSymbol(string name) {
            return FindVariable(name) as Symbol ?? FindFunction(name) as Symbol;
        }

        public Builder BeginFunction(FunctionDef func) {
            var scope = Scopes.Peek();
            scope.Functions[func.Name] = func;
            scope.FunctionOrder.Add(func);
            AST.TopLevelSymbols.Add(func);
            BeginScope();
            var funcScope = Scopes.Peek();
            funcScope.ReturnTarget = func;
            return this;
        }

        public Builder EndFunction() {
            var scope = Scopes.Peek();
            var func = ReturnTarget;
            func.Variables = scope.VariableOrder;
            func.Body = scope.Expressions;
            EndScope();
            return this;
        }

        public Builder BeginScope() {
            Scopes.Push(new Scope());
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
            return top as T ?? throw new CompileException($"Tried to pop {typeof(T)}, found {top}");
        }

        public Node PeekStack(uint idx = 0) {
            var scope = Scopes.Peek();
            return scope.Stack.ElementAt((int)idx);
        }

        public T? PeekStack<T>(uint idx = 0) where T : class {
            return PeekStack(idx) as T;
        }

        public Builder NewType(Type type) {
            var scope = Scopes.Peek();
            scope.Types.Add(type.Name, type);
            return this;
        }

        public Builder NewVariable(VariableDef variable) {
            var scope = Scopes.Peek();
            scope.Variables.Add(variable.Name, variable);
            scope.VariableOrder.Add(variable);
            return this;
        }

        public Builder NewExpression(Expression expr) {
            var scope = Scopes.Peek();
            scope.Expressions.Add(expr);
            scope.Stack.Push(expr);
            return this;
        }
    }

    public class ParseTree {
        public List<Symbol> TopLevelSymbols = new();

        public Builder Builder() => new(this);

        public ParseTree() {

        }
    }
}
