
grammar Pepper;

compilationUnit
	: translationUnit? EOF
	;

translationUnit
	: externalDeclaration+
	;

externalDeclaration
    : functionDefinition
    | externFunction
    | structDeclaration
    | extensionDefinition
    | useStatement
    |   ';' // stray ;
    ;

functionDefinition
    :   typeName? functionName '(' parameterList? ')' block
    ;

functionName
    : typeDeclaration
    | binaryOperator
    | unaryOperator
    ;

parameterList
    :   parameterDeclaration (',' parameterDeclaration)*
    ;

parameterDeclaration
	: typeName Identifier (Assign expression)?
	;

extensionDefinition
    :   Extend typeDeclaration '{' functionDefinitionList '}'
    ;

functionDefinitionList
    :   functionDefinition* {}
    ;

block
    :   '{' statementList? '}'
    ;

statementList
    :   statement+
    ;

statement
    :   variableDeclaration
    |   block
    |   structDeclaration
    |   expressionStatement
    |   ifStatement
    |   iterationStatement
    |   jumpStatement
    |   functionDefinition
    ;

externFunction
    : '@' 'extern' 'weak'? externTypeName Identifier '(' externParameterList? ')'
    ;

externTypeName
    :   Identifier '*'?
    ;

externParameterList
    :   externParameter (',' externParameter)* (',' Ellipsis)?
    ;

externParameter
    : externTypeName Identifier?
    ;

useStatement
    : Use (StringLiteral|Identifier) (As Identifier)? ';'
    ;

expressionStatement
    : expression ';'
    ;

expression
    : singleExpression
    ;

variableDeclaration
    : typeQualifier? typeName Identifier (Assign expression)? ';' #ExplicitVariableDeclaration
    | typeQualifier Identifier Assign expression ';'              #ImplicitVariableDeclaration
    ;

storageClassSpecifier
	: 'static'
	;

typeQualifier
	: Var
	| Const
	;

typeName
    : Identifier genericArgs? Brackets?
	;

genericArgs
    : '<' genericArgsList '>'
    ;

genericArgsList
    : typeName (',' typeName)?
    ;

ifStatement
    :   ifBranch elseBranch?
    ;

condition
    : expression
    ;

ifCondition
    : condition
    ;

ifBranch
    : If '(' ifCondition ')' statement
    ;

elseBranch
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
	:   forDeclaration In forExpression
	|   forExpression
	;

forDeclaration
    :   typeQualifier? Identifier
    ;

forExpression
    :   sliceNotation
    |   expression
    ;

sliceNotation
    :   expression '..'
    |   expression '..' expression?
    |   expression '..' expression? (',' expression)?
    ;

structDeclaration
	: Struct typeDeclaration '{' structMemberDeclaration* '}'
	;

typeDeclaration
    : Identifier genericParams?
    ;

genericParams
    : '<' genericParamsList '>'
    ;

genericParamsList
    : Identifier (',' Identifier)?
    ;

structMemberDeclaration
    :   fieldDeclaration
    |   constructorDefinition
    ;

constructorParam
    : parameterDeclaration
    | This '.' Identifier (Assign singleExpression)?
    ;

constructorParamList
    : constructorParam (',' constructorParam)*
    ;

constructorDefinition
    :   New '(' constructorParamList? ')' block
    |   Del '(' ')' block
    ;

fieldDeclaration
	: typeQualifier* variableDeclaration
    ;

jumpStatement
    :   Continue ';'		    # Continue
	|   Break ';'				# Break
	|   Return expression? ';'	# Return
    ;

singleExpression
    :   lambdaFunction                                          #LambdaExpr
    |   singleExpression '[' singleExpression ']'               #IndexAccess
    |   singleExpression '.' Identifier                         #MemberAccess
    |   singleExpression '(' argumentList ')'                   #FunctionCall
    |   typeName '(' argumentList ')'                           #GenericCtor
    |   singleExpression '++'                                   #PostIncrement
    |   singleExpression '--'                                   #PostDecrement
    |   '++' singleExpression                                   #PreIncrement
    |   '--' singleExpression                                   #PreDecrement
    |   '+'  singleExpression                                   #UnaryPlus
    |   '-'  singleExpression                                   #UnaryMinus
    |   '~'  singleExpression                                   #BitNot
    |   '!'  singleExpression                                   #LogicalNot
    |   <assoc=right> singleExpression '**' singleExpression    #Pow
    |   singleExpression '*' singleExpression                   #Mul
    |   singleExpression '/' singleExpression                   #Div
    |   singleExpression '%' singleExpression                   #Mod
    |   singleExpression '+' singleExpression                   #Add
    |   singleExpression '-' singleExpression                   #Sub
    |   singleExpression '??'  singleExpression                 #Coalesce
    |   singleExpression '<<' singleExpression                  #LShift
    |   singleExpression '>>' singleExpression                  #RShift
    |   singleExpression '<' singleExpression                   #Less
    |   singleExpression '<=' singleExpression                  #LessEqual
    |   singleExpression '>' singleExpression                   #Greater
    |   singleExpression '>=' singleExpression                  #GreaterEqual
    |   singleExpression '==' singleExpression                  #Equal
    |   singleExpression '!=' singleExpression                  #NotEqual
    |   singleExpression '&' singleExpression                   #BitAnd
    |   singleExpression '|' singleExpression                   #BitOr
    |   singleExpression '^' singleExpression                   #BitXor
    |   singleExpression ('&&'|And) singleExpression            #LogicalAnd
    |   singleExpression ('||'|Or) singleExpression             #LogicalOr
    |   singleExpression '?' singleExpression ':' singleExpression #Ternary
    |   <assoc=right> singleExpression '=' singleExpression     #Assignment
    |   <assoc=right> singleExpression assignmentOperator singleExpression    #AssignmentOp
    |   (Identifier | This)                                       #IdentifierExpr
    |   literal                                                 #LiteralExpr
    |   arrayLiteral                                            #ArrayLiteralExpr
    |   '(' expression ')'                                      #ParenExpr
    ;

literal
    : BooleanLiteral
    | StringLiteral+
    | numericLiteral
    | Null
    ;

numericLiteral
    : DecimalLiteral
    | HexIntegerLiteral
    | OctalIntegerLiteral
    | BinaryIntegerLiteral
    ;

arrayLiteral
    : ('[' elementList ']')
    ;

elementList
    : arrayElement? (','+ arrayElement)* ','*
    ;

arrayElement
    : singleExpression
    ;

assignmentOperator
    : '*='
    | '/='
    | '%='
    | '+='
    | '-='
    | '<<='
    | '>>='
    | '&='
    | '^='
    | '|='
    | '**='
    ;

binaryOperator
    : '+' | '-' | '*' | '/' | '%' | '==' | '!=' | '<<' | '>>'
    ;

unaryOperator
    : '++' | '--' | '[]'
    ;

argumentList
    : argument? (',' argument)* (',' Ellipsis)?
    ;

argument
    : (expression|Identifier)
    ;

lambdaFunction
    : '(' parameterList? ')' block
    ;


And: 'and';
As: 'as';
Break : 'break';
Case : 'case';
Const : 'const';
Continue : 'continue';
Default : 'default';
Del : 'del';
Do : 'do';
Else : 'else';
Enum : 'enum';
Extend : 'extend';
Extern : 'extern';
For : 'for';
If : 'if';
In: 'in';
New: 'new';
Null: '__null';
Or: 'or';
Return : 'return';
Static : 'static';
Struct : 'struct';
Switch : 'switch';
This: 'this';
Use: 'use';
Var: 'var';
Weak: 'weak';
While : 'while';
With: 'with';

LeftParen : '(';
RightParen : ')';
LeftBracket : '[';
RightBracket : ']';
Brackets: '[]';
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
MulAssign : '*=';
DivAssign : '/=';
ModAssign : '%=';
AddAssign : '+=';
SubAssign : '-=';
LShiftAssign : '<<=';
RShiftAssign : '>>=';
BitAndAssign : '&=';
BitXorAssign : '^=';
BitOrAssign : '|=';

Equal : '==';
NotEqual : '!=';

Arrow : '->';
DotDot : '..';
Dot : '.';
Ellipsis : '...';

BooleanLiteral
    : 'true'
    | 'false'
    ;

Identifier
    :   IdentifierNondigit
        (   IdentifierNondigit
        |   Digit
        )*
    ;

/// Numeric Literals

DecimalLiteral:                 DecimalIntegerLiteral '.' [0-9] [0-9_]* ExponentPart?
              |                 '.' [0-9] [0-9_]* ExponentPart?
              |                 DecimalIntegerLiteral ExponentPart?
              ;

/// Numeric Literals

HexIntegerLiteral:              '0' [xX] [0-9a-fA-F] HexDigit*;
OctalIntegerLiteral:            '0' [oO] [0-7] [_0-7]*;
BinaryIntegerLiteral:           '0' [bB] [01] [_01]*;

StringLiteral
    :   '"' DoubleStringCharacter* '"'
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

fragment DoubleStringCharacter
    : ~["\\\r\n]
    | '\\' EscapeSequence
    | LineContinuation
    ;
fragment SingleStringCharacter
    : ~['\\\r\n]
    | '\\' EscapeSequence
    | LineContinuation
    ;
fragment EscapeSequence
    : CharacterEscapeSequence
    | '0' // no digit ahead! TODO
    | HexEscapeSequence
    | UnicodeEscapeSequence
    | ExtendedUnicodeEscapeSequence
    ;
fragment CharacterEscapeSequence
    : SingleEscapeCharacter
    | NonEscapeCharacter
    ;
fragment HexEscapeSequence
    : 'x' HexDigit HexDigit
    ;
fragment UnicodeEscapeSequence
    : 'u' HexDigit HexDigit HexDigit HexDigit
    | 'u' '{' HexDigit HexDigit+ '}'
    ;
fragment ExtendedUnicodeEscapeSequence
    : 'u' '{' HexDigit+ '}'
    ;
fragment SingleEscapeCharacter
    : ['"\\bfnrtv]
    ;

fragment NonEscapeCharacter
    : ~['"\\bfnrtv0-9xu\r\n]
    ;
fragment EscapeCharacter
    : SingleEscapeCharacter
    | [0-9]
    | [xu]
    ;
fragment LineContinuation
    : '\\' [\r\n\u2028\u2029]
    ;
fragment HexDigit
    : [_0-9a-fA-F]
    ;
fragment DecimalIntegerLiteral
    : '0'
    | [1-9] [0-9_]*
    ;
fragment ExponentPart
    : [eE] [+-]? [0-9_]+
    ;

//fragment IdentifierPart
//    : IdentifierStart
//    | [\p{Mn}]
//    | [\p{Nd}]
//    | [\p{Pc}]
//    | '\u200C'
//    | '\u200D'
//    ;
//fragment IdentifierStart
//    : [\p{L}]
//    | [$_]
//    | '\\' UnicodeEscapeSequence
//    ;
