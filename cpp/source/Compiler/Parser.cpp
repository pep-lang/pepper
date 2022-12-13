
#include "Parser.h"

#include "ANTLRInputStream.h"
#include "PepperBaseListener.h"
#include "PepperLexer.h"
#include "PepperParser.h"

class ParserListener : public Pepper::Parser::PepperBaseListener {
  private:
    std::shared_ptr<Codegen> Generator;

  public:
    ParserListener(std::shared_ptr<Codegen> gen) : Generator(gen) {}
};

void Parser::Parse(std::istream& stream) {
    antlr4::ANTLRInputStream inputStream(stream);
    Pepper::Parser::PepperLexer lexer(&inputStream);
    antlr4::CommonTokenStream tokenStream(&lexer);
    Pepper::Parser::PepperParser parser(&tokenStream);

    antlr4::tree::ParseTree* tree = parser.compilationUnit();
    ParserListener listener(Generator);
    antlr4::tree::ParseTreeWalker::DEFAULT.walk(&listener, tree);
}
