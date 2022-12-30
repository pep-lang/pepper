
grammar Pepper;

primaryExpression
	: Identifier
	| Constant
    | StringLiteral+
	| '(' expression ')'
	;

postfixExpression
	: primaryExpression (PlusPlus | MinusMinus)*
	| arrayAccess
    | functionCall
    | memberAccess
	;

arrayAccess
    : primaryExpression '[' expression ']'
    ;

functionCall
    : (Identifier|'(' expression ')') '(' argumentExpressionList? ')'
    ;

memberAccess
    : primaryExpression '.' Identifier
    ;

argumentExpressionList
	: assignmentExpression (',' assignmentExpression)*
	;

unaryExpression
	: (PlusPlus | MinusMinus | 'typeof')*
	(postfixExpression
	| unaryOperator castExpression
	)
	;

unaryOperator
	: '&' | '*' | '+' | '-' | '~' | '!'
	;

castExpression
	: '(' Identifier As Identifier ')'
	| unaryExpression
	;

binaryOpExpression
	: castExpression #binaryOpDefault
    | binaryOpExpression Star binaryOpExpression #Mul
    | binaryOpExpression Div binaryOpExpression #Div
    | binaryOpExpression Mod binaryOpExpression #Mod
    | binaryOpExpression Pow binaryOpExpression #Pow
    | binaryOpExpression Plus binaryOpExpression #Add
    | binaryOpExpression Minus binaryOpExpression #Sub
    | binaryOpExpression LeftShift binaryOpExpression #LShift
    | binaryOpExpression RightShift binaryOpExpression #RShift
	;

relationExpression
	: binaryOpExpression #relationDefault
    | relationExpression Less relationExpression #Less
    | relationExpression Greater relationExpression #Greater
    | relationExpression LessEqual relationExpression #LessEqual
    | relationExpression GreaterEqual relationExpression #GreaterEqual
	;

equalExpression
	: relationExpression #equalDefault
    | relationExpression Equal relationExpression #Equal
    | relationExpression NotEqual relationExpression #NotEqual
	;

bitAndExpression
	: equalExpression #bitAndDefault
    | equalExpression BitAnd equalExpression #BitwiseAnd
	;

bitXorExpression
	: bitAndExpression #bitXorDefault
    | bitAndExpression Caret bitAndExpression #BitwiseXor
	;

bitOrExpression
	: bitXorExpression #bitOrDefault
    | bitXorExpression BitOr bitXorExpression #BitwiseOr
	;

logicalAndExpression
	: bitOrExpression #logicalAndDefault
    | bitOrExpression (AndAnd|And) bitOrExpression #LogicalAnd
	;

logicalOrExpression
	: logicalAndExpression #logicalOrDefault
    | logicalAndExpression (OrOr|Or) logicalAndExpression #LogicalOr
	;

ternaryExpression
	: logicalOrExpression #ternaryDefault
    | logicalOrExpression '?' expression ':' ternaryExpression #Ternary
	;

assignmentExpression
	: ternaryExpression #assignmentDefault
	| unaryExpression '=' assignmentExpression #Assignment
    | unaryExpression '*=' assignmentExpression #MulAssignment
    | unaryExpression '/=' assignmentExpression #DivAssignment
    | unaryExpression '%=' assignmentExpression #ModAssignment
    | unaryExpression '+=' assignmentExpression #AddAssignment
    | unaryExpression '-=' assignmentExpression #SubAssignment
    | unaryExpression '<<=' assignmentExpression #LShiftAssignment
    | unaryExpression '>>=' assignmentExpression #RShiftAssignment
    | unaryExpression '&=' assignmentExpression #BitAndAssignment
    | unaryExpression '^=' assignmentExpression #BitXorAssignment
    | unaryExpression '|=' assignmentExpression #BitOrAssignment
	| DigitSequence #AssignmentDigits
	;

expression
    :   assignmentExpression (',' assignmentExpression)*
    ;

constantExpression
    :   ternaryExpression
    ;

declaration
	: declarationSpecifiers initDeclaratorList? ';'
	;

declarationSpecifiers
	: declarationSpecifier+
	;

declarationSpecifier
	: storageClassSpecifier
	| typeSpecifier
	| typeQualifier
	;

initDeclaratorList
	: initDeclarator (',' initDeclarator)*
	;

initDeclarator
    :   declarator ('=' initializer)?
    ;

storageClassSpecifier
	: 'static'
	;

typeSpecifier
	: variableSpecifier
	| structDeclaration
	| enumSpecifier
	;

variableSpecifier
    : Identifier Identifier Assign assignmentExpression
    ;

structDeclaration
	: Struct Identifier '{' fieldDeclarationList '}'
	;

fieldDeclarationList
	: fieldDeclaration*
	;

fieldDeclaration
	: typeQualifier* variableSpecifier ';'
	;

enumSpecifier
	: 'enum' Identifier '{' enumeratorList ','? '}'
	;

enumeratorList
	: enumerator (',' enumerator)*
	;

// come back to this to add classes in here
enumerator
	: enumeratorConstant
	;

enumeratorConstant
	: Identifier
	;

typeQualifier
	: 'const'
	;

// This probably needs way more
declarator
	: Identifier
    | declarator '(' parameterTypeList? ')'
    | declarator '(' identifierList? ')'
	;

parameterTypeList
	: parameterList (',' '...')?
	;

parameterList
    :   parameterDeclaration (',' parameterDeclaration)*
    ;

parameterDeclaration
	: Identifier Identifier (Assign assignmentExpression)?
	;

identifierList
	: Identifier (',' Identifier)*
	;

initializer
	: assignmentExpression
	| '{' initializerList ','? '}'
	;

initializerList
	: initializer (',' initializer)*
	;

statement
	: labeledStatement
	| compoundStatement
	| expressionStatement
	| selectionStatement
	| iterationStatement
	| jumpStatement
    | '(' (logicalOrExpression (',' logicalOrExpression)*)? (':' (logicalOrExpression (',' logicalOrExpression)*)?)* ')' ';'
	;

labeledStatement
    :   Identifier ':' statement
    |   'case' constantExpression ':' statement
    |   'default' ':' statement
    ;

compoundStatement
    :   '{' blockItemList? '}'
    ;

blockItemList
    :   blockItem+
    ;

blockItem
    :   statement
    |   declaration
    ;

expressionStatement
    :   expression ';'
    ;

selectionStatement
    :   ifStatement elseStatement?
    //|   Switch '(' expression ')' statement
    ;

condition
    : expression
    ;

ifCondition
    : condition
    ;

ifStatement
    : If '(' ifCondition ')' statement
    ;

elseStatement
    : Else statement
    ;

iterationStatement
    :   While '(' whileCondition ')' statement #WhileLoop
    //|   Do statement While '(' condition ')' ';'? #DoWhileLoop
    |   For '(' forCondition ')' statement #ForLoop
    ;

whileCondition
    : condition
    ;

forCondition
	:   (forDeclaration | expression?) ';' forExpression? ';' forExpression?
	;

forDeclaration
    :   declarationSpecifiers initDeclaratorList?
    ;

forExpression
    :   assignmentExpression (',' assignmentExpression)*
    ;

jumpStatement:
	Continue ';'				# Continue
	| Break ';'					# Break
	| Return expression? ';'	# Return
    ;

compilationUnit
	: translationUnit? EOF
	;

translationUnit
	: externalDeclaration+
	;

externalDeclaration
    : functionDefinition
    | structDeclaration  
    |   ';' // stray ;
    ;

functionDefinition
    :   returnType? Identifier '(' parameterList? ')' compoundStatement
    ;

returnType
    : Identifier
    ;


And: 'and';
As: 'as';
Break : 'break';
Case : 'case';
Const : 'const';
Continue : 'continue';
Default : 'default';
Do : 'do';
Else : 'else';
Enum : 'enum';
Extern : 'extern';
For : 'for';
If : 'if';
Or: 'or';
Return : 'return';
Static : 'static';
Struct : 'struct';
Switch : 'switch';
Void : 'void';
While : 'while';

LeftParen : '(';
RightParen : ')';
LeftBracket : '[';
RightBracket : ']';
LeftBrace : '{';
RightBrace : '}';

Less : '<';
LessEqual : '<=';
Greater : '>';
GreaterEqual : '>=';
LeftShift : '<<';
RightShift : '>>';

Plus : '+';
PlusPlus : '++';
Minus : '-';
MinusMinus : '--';
Star : '*';
Pow : '**';
Div : '/';
Mod : '%';

BitAnd : '&';
BitOr : '|';
AndAnd : '&&';
OrOr : '||';
Caret : '^';
Not : '!';
Tilde : '~';

Question : '?';
Colon : ':';
Semi : ';';
Comma : ',';

Assign : '=';
// '*=' | '/=' | '%=' | '+=' | '-=' | '<<=' | '>>=' | '&=' | '^=' | '|='
StarAssign : '*=';
DivAssign : '/=';
ModAssign : '%=';
PlusAssign : '+=';
MinusAssign : '-=';
LeftShiftAssign : '<<=';
RightShiftAssign : '>>=';
AndAssign : '&=';
XorAssign : '^=';
OrAssign : '|=';

Equal : '==';
NotEqual : '!=';

Arrow : '->';
Dot : '.';
Ellipsis : '...';

Identifier
    :   IdentifierNondigit
        (   IdentifierNondigit
        |   Digit
        )*
    ;

fragment
IdentifierNondigit
    :   Nondigit
    ;

fragment
Nondigit
    :   [a-zA-Z_]
    ;

fragment
Digit
    :   [0-9]
    ;

Constant
    :   IntegerConstant
    |   FloatingConstant
    //|   EnumerationConstant
    |   CharacterConstant
    ;

fragment
IntegerConstant
    :   DecimalConstant
    |   OctalConstant
    |   HexadecimalConstant
    |	BinaryConstant
    ;

fragment
BinaryConstant
	:	'0' [bB] [0-1]+
	;

fragment
DecimalConstant
    :   Sign? NonzeroDigit Digit*
    ;

fragment
OctalConstant
    :   '0' OctalDigit*
    ;

fragment
HexadecimalConstant
    :   HexadecimalPrefix HexadecimalDigit+
    ;

fragment
HexadecimalPrefix
    :   '0' [xX]
    ;

fragment
NonzeroDigit
    :   [1-9]
    ;

fragment
OctalDigit
    :   [0-7]
    ;

fragment
HexadecimalDigit
    :   [0-9a-fA-F]
    ;

fragment
FloatingConstant
    :   DecimalFloatingConstant
    |   HexadecimalFloatingConstant
    ;

fragment
DecimalFloatingConstant
    :   FractionalConstant ExponentPart?
    |   DigitSequence ExponentPart
    ;

fragment
HexadecimalFloatingConstant
    :   HexadecimalPrefix (HexadecimalFractionalConstant | HexadecimalDigitSequence)
    ;

fragment
FractionalConstant
    :   DigitSequence? '.' DigitSequence
    |   DigitSequence '.'
    ;

fragment
ExponentPart
    :   [eE] Sign? DigitSequence
    ;

fragment
Sign
    :   [+-]
    ;

DigitSequence
    :   Digit+
    ;

fragment
HexadecimalFractionalConstant
    :   HexadecimalDigitSequence? '.' HexadecimalDigitSequence
    |   HexadecimalDigitSequence '.'
    ;

fragment
HexadecimalDigitSequence
    :   HexadecimalDigit+
    ;

fragment
CharacterConstant
    :   '\'' CCharSequence '\''
    |   'L\'' CCharSequence '\''
    |   'u\'' CCharSequence '\''
    |   'U\'' CCharSequence '\''
    ;

fragment
CCharSequence
    :   CChar+
    ;

fragment
CChar
    :   ~['\\\r\n]
    |   EscapeSequence
    ;

fragment
EscapeSequence
    :   SimpleEscapeSequence
    |   OctalEscapeSequence
    |   HexadecimalEscapeSequence
    ;

fragment
SimpleEscapeSequence
    :   '\\' ['"?abfnrtv\\]
    ;

fragment
OctalEscapeSequence
    :   '\\' OctalDigit OctalDigit? OctalDigit?
    ;

fragment
HexadecimalEscapeSequence
    :   '\\x' HexadecimalDigit+
    ;

StringLiteral
    :   '"' SCharSequence? '"'
    ;

fragment
SCharSequence
    :   SChar+
    ;
fragment
SChar
    :   ~["\\\r\n]
    |   EscapeSequence
    |   '\\\n'   // Added line
    |   '\\\r\n' // Added line
    ;

Whitespace
    :   [ \t]+
        -> skip
    ;

Newline
    :   (   '\r' '\n'?
        |   '\n'
        )
        -> skip
    ;

BlockComment
    :   '/*' .*? '*/'
        -> skip
    ;

LineComment
    :   '#' ~[\r\n]*
        -> skip
    ;