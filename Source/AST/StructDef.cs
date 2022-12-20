using System;
using LLVMSharp.Interop;
using Microsoft.VisualBasic.FileIO;
using Pepper.AST;
using Pepper.Codegen;
using Pepper;

namespace Pepper.AST {
    public class StructDef : Symbol {
        public FunctionDef New { get; private set; }
        public MethodDef Initializer { get; private set; }
        public MethodDef Constructor { get; private set; }
        public MethodDef Destructor { get; private set; }
        public List<FieldDef> Fields = new();
        public List<MethodDef> Methods = new();

        public StructDef(string name)
            : base(new StructType(name), name) {
            New = new FunctionDef(name, Type);
            // TODO: deal with parameters to ctor here
            Initializer = new MethodDef(this, "__init", Types.Void);
            Constructor = new MethodDef(this, "__ctor", Types.Void);
            Destructor = new MethodDef(this, "__dtor", Types.Void);
            Methods.Add(Initializer);
            Methods.Add(Constructor);
            Methods.Add(Destructor);
        }

        public void Finish() {
            Initializer.Variables = Fields.Select(f => new FieldDef(this, f.Type, f.Name, f.InitialValue)).Cast<VariableDef>().ToList();
            Initializer.Body.Add(new Return(Initializer, null));
        }
    }

    public class MemberRef : Expression {
        public override Type Type => Types.From(FieldType.Name);
        public Type FieldType { get; private set; }
        public Expression LHS { get; private set; }
        public string Name { get; private set; }

        public MemberRef(Type type, Expression lhs, string fieldName) {
            FieldType = type;
            LHS = lhs;
            Name = fieldName;
        }
    }
}
