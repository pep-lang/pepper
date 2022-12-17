
using Pepper.Codegen;

namespace Pepper.AST {

    public class ParseTree {
        public List<Symbol> TopLevelSymbols = new();

        public Builder Builder() => new(this);

        public ParseTree() {

        }
    }
}
