
#pragma once

class Codegen {
  public:
    void beginFunction();

    void endFunction();

    void functionCall();

    void stringLiteral();

    void identifier();

    void variableDeclaration();

    void binaryMul();

    void binaryDiv();

    void binaryMod();

    void binaryPow();

    void binaryAdd();

    void binarySub();

    void binaryLeftShift();

    void binaryRightShift();

    void compareLess();

    void compareLessEqual();

    void compareGreater();

    void compareGreaterEqual();

    void bitwiseAnd();

    void bitwiseXor();

    void bitwiseOr();

    void equal();

    void notEqual();

    void assign();

    void mulAssign();

    void divAssign();

    void modAssign();

    void leftShiftAssign();

    void rightShiftAssign();

    void bitAndAssign();

    void bitXorAssign();

    void bitOrAssign();

    void ternary();
};
