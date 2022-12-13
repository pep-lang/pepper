
#pragma once

class Codegen {
  public:
    void BeginFunction();

    void EndFunction();

    void FunctionCall();

    void StringLiteral();

    void Identifier();

    void VariableDeclaration();

    void BinaryMul();

    void BinaryDiv();

    void BinaryMod();

    void BinaryPow();

    void BinaryAdd();

    void BinarySub();

    void BinaryLeftShift();

    void BinaryRightShift();

    void CompareLess();

    void CompareLessEqual();

    void CompareGreater();

    void CompareGreaterEqual();

    void BitwiseAnd();

    void BitwiseXor();

    void BitwiseOr();

    void Equal();

    void NotEqual();

    void Assign();

    void MulAssign();

    void DivAssign();

    void ModAssign();

    void LeftShiftAssign();

    void RightShiftAssign();

    void BitAndAssign();

    void BitXorAssign();

    void BitOrAssign();

    void Ternary();
};
