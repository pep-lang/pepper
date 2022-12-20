using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.AST.Validation {
    internal class SymbolReferences : Validator {
        public override void Evaluate(Compiler compiler, ParseTree ast) {
            var tree = ast.AsScopeTree();
            tree.WalkDepthFirst(scope => {
                using var checks = scope.On<VariableRef>((scope, vr) => {
                    if (scope[vr.Identifier] == null) {
                        compiler.Report<Error>($"Unable to resolve variable {vr.Identifier}", vr.Source);
                    }
                }).On<FunctionCall>((scope, call) => {
                    if (scope[call.Target.Name] == null) {
                        compiler.Report<Error>($"Unable to find function {call.Target.Name}", call.Source);
                    }
                });
            });
        }
    }
}
