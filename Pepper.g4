
grammar Pepper;

primaryExpression
	: Identifier
	| Constant
	| '(' expression ')'
	;

postfixExpression
	: 
	(
		'[' expression ']'
		| '(' argumentExpressionList ')'
		| '.' Identifier
		| ('++' | '--')
	)*
	;

argumentExpressionList
	: assignmentExpression (',' assignmentExpression)*
	;

unaryExpression
	: ('++' | '--' | 'typeof')*
	(
		postfixExpression
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

mulDivExpression
	: castExpression (('*'|'**'|'/'|'%') castExpression)*
	;

addSubExpression
	: mulDivExpression (('+'|'-') mulDivExpression)*
	;

shiftExpression
	: addSubExpression (('<<'|'>>') addSubExpression)
	;

relationExpression
	: shiftExpression (('<'|'>'|'<='|'>=') shiftExpression)*
	;

equalExpression
	: relationExpression (('=='|'!=') relationExpression)*
	;

bitAndExpression
	: equalExpression ('&' equalExpression)*
	;

bitXorExpression
	: bitAndExpression ('^' bitXorExpression)*
	;

bitOrExpression
	: bitXorExpression ('|' bitXorExpression)*
	;

logicalAndExpression
	: bitOrExpression (('&&'|And) bitOrExpression)*
	;

logicalOrExpression
	: logicalAndExpression (('||'|Or) logicalAndExpression)*
	;

ternaryExpression
	: logicalOrExpression ('?' expression ':' ternaryExpression)*
	;

assignmentExpression
	: ternaryExpression
	| unaryExpression assignmentOperator assignmentExpression
	| DigitSequence
	;

assignmentOperator
    :   '=' | '*=' | '/=' | '%=' | '+=' | '-=' | '<<=' | '>>=' | '&=' | '^=' | '|='
    ;

expression
    :   assignmentExpression (',' assignmentExpression)*
    ;

constantExpression
    :   ternaryExpression
    ;

declaration
	: declarationSpecifiers initDeclaratorList?
	;

declarationSpecifiers
	: declarationSpecifier+
	;

paramSpecifiers
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
	: 
	(
	  'void'
	| 'byte'
	| 'i32'
	| 'u32'
	| 'i64'
	| 'u64'
	| 'f32'
	| 'f64'
	| 'bool'
	)
	| structSpecifier
	| enumSpecifier
	;

structSpecifier
	: Struct Identifier? '{' structDeclarationList '}'
	;

structDeclarationList
	: structDeclaration*
	;

structDeclaration
	: specifierQualifierList structDeclaratorList ';'?
	| specifierQualifierList ';'?
	;

specifierQualifierList
	: (typeSpecifier|typeQualifier) specifierQualifierList?
	;

structDeclaratorList
	: structDeclarator (',' structDeclarator)*
	;

structDeclarator
	: declarator
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
	;

typeQualifierList
	: typeQualifier+
	;

parameterTypeList
	: parameterList (',' '...')?
	;

parameterList
    :   parameterDeclaration (',' parameterDeclaration)*
    ;

parameterDeclaration
	: declarationSpecifiers declarator
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
    :   expression? ';'
    ;

selectionStatement
    :   'if' '(' expression ')' statement ('else' statement)?
    |   'switch' '(' expression ')' statement
    ;

iterationStatement
    :   While '(' expression ')' statement
    |   Do statement While '(' expression ')' ';'
    |   For '(' forCondition ')' statement
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

jumpStatement
    :   ('goto' Identifier
    |   ('continue'| 'break')
    |   'return' expression?
    |   'goto' unaryExpression // GCC extension
    )
    ';'
    ;

compilationUnit
	: translationUnit? EOF
	;

translationUnit
	: externalDeclaration+
	;

externalDeclaration
    :   functionDefinition
    |   declaration
    |   ';' // stray ;
    ;

functionDefinition
    :   declarationSpecifiers? declarator declarationList? compoundStatement
    ;

declarationList
    :   declaration+
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
    :   NonzeroDigit Digit*
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