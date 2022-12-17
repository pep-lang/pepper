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
                foreach (var node in scope.Nodes) {
                    if (node is VariableRef varRef) {
                        if (scope[varRef.Identifier] == null) {
                            compiler.Report<Compiler.Error>($"Unable to resolve variable {varRef.Identifier}", varRef.Source);
                        }
                    } else if (node is FunctionCall call) {
                        if (scope[call.Target.Name] == null) {
                            compiler.Report<Compiler.Error>($"Unable to find function {call.Target.Name}", call.Source);
                        }
                    }
                }
            });
        }
    }
}
