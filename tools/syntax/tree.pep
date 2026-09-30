## The syntax tree: a lossless tree whose leaves are the source's tokens, in
## order. Every token (and so every comment) of the source is a leaf, so a
## tool can print the tree back without losing anything, and can find the
## exact token behind any construct.
##
## Each node's `kind` says which construct it is, and its `children` are its
## tokens and sub-nodes in source order. The `NodeKind` cases below list
## each kind's children; `[x]` is optional and `x...` repeats.

import "token";

## Which construct a `Node` is. Each case lists the node's children; `[x]` is
## optional and `x...` repeats.
export enum NodeKind {
    ## A token leaf. Its `leaf` is the token; it has no children.
    Token,
    ## A whole file: its items, then the end token.
    Module,
    ## `[attribute]... import [list from] name [as alias] [;]`, or a re-export
    ## `[attribute]... export (* | list) from name [;]`.
    Import,
    ## `[ symbol, ... ]` in an import: `IMPORT_SYMBOL`s separated by `,`.
    ImportList,
    ## `name [as alias]` inside an import list.
    ImportSymbol,
    ## `[attribute]... export name[.name]... [as alias] [;]`
    ExportAlias,
    ## `[ expression ]`
    Attribute,
    ## `[attribute]... [export] struct Name [GENERIC_PARAMETERS] MEMBERS`
    Struct,
    ## `[attribute]... [export] trait Name [GENERIC_PARAMETERS] MEMBERS`
    Trait,
    ## `[attribute]... [export] extend TYPE [with TYPE, ...] MEMBERS`; the
    ## target's type arguments may restate constraints (`Box<T: Shape>`).
    Extend,
    ## `[attribute]... [export] type Name [GENERIC_PARAMETERS] = TYPE [;]`
    TypeAlias,
    ## `{ member... }`: the body of a struct, trait or extension.
    Members,
    ## `[attribute]... [export] extern TYPE name PARAMETERS [;]`
    ExternFunction,
    ## A function or method: `[attribute]... [export] [static]`, a signature,
    ## then a `BLOCK` (or `;` for a trait method without a body). The signature
    ## is `name [GENERIC_PARAMETERS] [PARAMETERS] [: TYPE]`,
    ## `TYPE name [PARAMETERS] [: TYPE]` (the name may be an operator), or the
    ## indexer form `TYPE [ ] PARAMETERS`.
    Function,
    ## `[attribute]... construct PARAMETERS BLOCK`
    Constructor,
    ## `[attribute]... destruct BLOCK`
    Destructor,
    ## A variable, field or binding: `[attribute]... [export]`, then
    ## `var name`, `const name` or `TYPE name`, then `[: TYPE] [= expression]`,
    ## then `[;]`. A line break may stand in for the `;`, as for every simple
    ## statement.
    Variable,
    ## `( PARAMETER, ... )`
    Parameters,
    ## One parameter: `name : TYPE [= expression]`, `TYPE name [= expression]`,
    ## `this . field = expression`, a `var` form, or `...`.
    Parameter,
    ## `< GENERIC_PARAMETER, ... >`
    GenericParameters,
    ## `Name [: TYPE [& TYPE]...] [= TYPE]`
    GenericParameter,
    ## A type: `name[.name]... [TYPE_ARGUMENTS] [[ ]]... [*]...`, or a function
    ## type `[shared|extern] ( TYPE, ... ) => TYPE`.
    Type,
    ## `< TYPE, ... >`
    TypeArguments,
    ## `[attribute]... { statement... }`
    Block,
    ## `if expression BLOCK [else (IF | BLOCK)]`
    If,
    ## `while expression BLOCK`
    While,
    ## `for [(] VARIABLE in expression [)] BLOCK`
    For,
    ## `with [(] (VARIABLE | expression) [)] BLOCK [else BLOCK]`
    With,
    ## `return [expression] [;]`
    Return,
    ## `break [;]` or `continue [;]`
    Jump,
    ## `expression [;]`
    ExpressionStatement,
    ## A `;` that ends nothing: after a block, or on its own. It says nothing.
    Empty,
    ## `( expression )`
    Parenthesized,
    ## `expression operator expression`, assignments included.
    Binary,
    ## `expression ? expression : expression`
    Ternary,
    ## `operator expression`: `-x`, `!x`, `++x`, and negative literals.
    Prefix,
    ## `expression ++` or `expression --`
    Postfix,
    ## `expression as TYPE`
    Cast,
    ## `expression . name [TYPE_ARGUMENTS]`
    Member,
    ## `expression [ expression ]`
    Index,
    ## `expression ARGUMENTS`
    Call,
    ## `( expression, ... )`
    Arguments,
    ## `sizeof < TYPE > [( )]`
    Sizeof,
    ## A generic type used as an expression: `TYPE`, as in `Array<int>()`.
    TypeLiteral,
    ## `CLOSURE_PARAMETERS [: TYPE] => (BLOCK | expression)`
    Closure,
    ## `( CLOSURE_PARAMETER, ... )`
    ClosureParameters,
    ## `name [: TYPE]`
    ClosureParameter,
    ## `(var | const) CLOSURE_PARAMETERS = expression ;`, a destructuring
    ## declaration such as `var (a, b: long, _) = f();`, or `var CLOSURE_PARAMETERS`
    ## alone as the pattern of `for (var (k, v) in pairs)`. A nested pattern is a
    ## `CLOSURE_PARAMETERS` among the bindings.
    Destructure,
    ## `( element, element, ... )`, a tuple literal, whose elements are
    ## expressions or, when labeled, `TUPLE_ELEMENT`s.
    Tuple,
    ## `name : expression`, a labeled element of a tuple literal such as
    ## `(line: 3, column: 7)`.
    TupleElement,
    ## `[ expression, ... ]`, an array literal; a trailing `,` is kept.
    Array,
    ## `[ MAP_ENTRY, ... ]`, a map literal, or `[ : ]` when empty.
    Map,
    ## `expression : expression`, one entry of a map literal.
    MapEntry,
    ## `[attribute]... [export] enum Name [GENERIC_PARAMETERS] [: TYPE] MEMBERS`,
    ## whose members are its `ENUM_CASE`s, then its methods.
    Enum,
    ## `[attribute]... Name [PARAMETERS] [= expression] [,]`: one case of an enum.
    EnumCase,
    ## `match expression MATCH_ARMS`
    Match,
    ## `{ MATCH_ARM... }`
    MatchArms,
    ## `PATTERN, ... => BLOCK`, or `else => BLOCK`.
    MatchArm,
    ## `name[.name]... [( name, ... )]`: a case, and the names it binds; a
    ## literal; or `( PATTERN, PATTERN, ... )`, a tuple pattern.
    Pattern,
}

## A node of the syntax tree: a token leaf, or a construct with children.
export struct Node {
    ## What construct this is.
    NodeKind kind;
    ## The token, for a `NodeKind.Token` leaf; null otherwise.
    Token leaf;
    ## The construct's tokens and sub-nodes, in source order.
    Node[] children = Array<Node>();

    ## Creates a node with no children.
    ##
    ## @param this.kind which construct it is
    construct(this.kind = NodeKind.Token) {}

    ## Creates a `NodeKind.Token` leaf holding `token`.
    ##
    ## @param token the token the leaf holds
    ## @returns the new leaf
    static of_token(token: Token): Node {
        var node = Node(NodeKind.Token);
        node.leaf = token;
        return node;
    }

    ## Appends `child` to this node's children.
    ##
    ## @param child the token leaf or node to append
    add(child: Node) {
        children.append(child);
    }

    ## Appends a leaf holding `token` to this node's children.
    ##
    ## @param token the token to append
    add_token(token: Token) {
        children.append(Node.of_token(token));
    }

    ## Returns the number of children.
    ##
    ## @returns the number of tokens and nodes directly under this node
    count(): ulong {
        return children.count();
    }

    ## Returns the child at `index`.
    ##
    ## @param index the position of the child, from 0
    ## @returns the child
    ## @panics if `index` is not less than `count()`
    child(index: ulong): Node {
        return children[index];
    }

    ## Returns whether this node is a token leaf holding the punctuation or
    ## keyword `text`.
    ##
    ## @param text the token text to compare with
    ## @returns true for a leaf whose token is spelled `text`
    is_token(text: String): bool {
        return kind == NodeKind.Token and leaf.text == text;
    }

    ## Returns the first token under this node, in source order.
    ##
    ## @returns the first token
    ## @panics if the node has no tokens
    first_token(): Token {
        if (kind == NodeKind.Token) {
            return leaf;
        }
        return children[0].first_token();
    }

    ## Returns the last token under this node, in source order.
    ##
    ## @returns the last token
    ## @panics if the node has no tokens
    last_token(): Token {
        if (kind == NodeKind.Token) {
            return leaf;
        }
        return children[children.count() - 1].last_token();
    }

    ## Returns whether any token under this node carries a comment.
    ##
    ## @returns true when a leading or trailing comment is attached below
    has_comments(): bool {
        if (kind == NodeKind.Token) {
            return leaf.has_comments();
        }
        for (var child in children) {
            if (child.has_comments()) {
                return true;
            }
        }
        return false;
    }
}
