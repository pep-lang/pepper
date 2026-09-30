## The syntax tree: a lossless tree whose leaves are the source's tokens, in
## order. Every token (and so every comment) of the source is a leaf, so a
## tool can print the tree back without losing anything, and can find the
## exact token behind any construct.
##
## Each node's `kind` says which construct it is, and its `children` are its
## tokens and sub-nodes in source order. The `NODE_` constants below list
## each kind's children; `[x]` is optional and `x...` repeats.

import "token";

## A token leaf. Its `leaf` is the token; it has no children.
export const NODE_TOKEN = 0;
## A whole file: its items, then the end token.
export const NODE_MODULE = 1;
## `[attribute]... import [list from] name [as alias] [;]`, or a re-export
## `[attribute]... export (* | list) from name [;]`.
export const NODE_IMPORT = 2;
## `[ symbol, ... ]` in an import: `IMPORT_SYMBOL`s separated by `,`.
export const NODE_IMPORT_LIST = 3;
## `name [as alias]` inside an import list.
export const NODE_IMPORT_SYMBOL = 4;
## `[attribute]... export name[.name]... [as alias] [;]`
export const NODE_EXPORT_ALIAS = 5;
## `[ expression ]`
export const NODE_ATTRIBUTE = 6;
## `[attribute]... [export] struct Name [GENERIC_PARAMETERS] MEMBERS`
export const NODE_STRUCT = 7;
## `[attribute]... [export] trait Name [GENERIC_PARAMETERS] MEMBERS`
export const NODE_TRAIT = 8;
## `[attribute]... [export] extend TYPE [with TYPE, ...] MEMBERS`
export const NODE_EXTEND = 9;
## `[attribute]... [export] type Name [GENERIC_PARAMETERS] = TYPE [;]`
export const NODE_TYPE_ALIAS = 10;
## `{ member... }`: the body of a struct, trait or extension.
export const NODE_MEMBERS = 11;
## `[attribute]... [export] extern TYPE name PARAMETERS [;]`
export const NODE_EXTERN_FUNCTION = 12;
## A function or method: `[attribute]... [export] [static]`, a signature,
## then a `BLOCK` (or `;` for a trait method without a body). The signature
## is `name [GENERIC_PARAMETERS] [PARAMETERS] [: TYPE]`,
## `TYPE name [PARAMETERS] [: TYPE]` (the name may be an operator), or the
## indexer form `TYPE [ ] PARAMETERS`.
export const NODE_FUNCTION = 13;
## `[attribute]... construct PARAMETERS BLOCK`
export const NODE_CONSTRUCTOR = 14;
## `[attribute]... destruct BLOCK`
export const NODE_DESTRUCTOR = 15;
## A variable, field or binding: `[attribute]... [export]`, then
## `var name`, `const name` or `TYPE name`, then `[: TYPE] [= expression]`,
## then `[;]`. A line break may stand in for the `;`, as for every simple
## statement.
export const NODE_VARIABLE = 16;
## `( PARAMETER, ... )`
export const NODE_PARAMETERS = 17;
## One parameter: `name : TYPE [= expression]`, `TYPE name [= expression]`,
## `this . field = expression`, a `var` form, or `...`.
export const NODE_PARAMETER = 18;
## `< GENERIC_PARAMETER, ... >`
export const NODE_GENERIC_PARAMETERS = 19;
## `Name [= TYPE]`
export const NODE_GENERIC_PARAMETER = 20;
## A type: `name[.name]... [TYPE_ARGUMENTS] [[ ]]... [*]...`, or a function
## type `[shared|extern] ( TYPE, ... ) => TYPE`.
export const NODE_TYPE = 21;
## `< TYPE, ... >`
export const NODE_TYPE_ARGUMENTS = 22;
## `[attribute]... { statement... }`
export const NODE_BLOCK = 23;
## `if expression BLOCK [else (IF | BLOCK)]`
export const NODE_IF = 24;
## `while expression BLOCK`
export const NODE_WHILE = 25;
## `for [(] VARIABLE in expression [)] BLOCK`
export const NODE_FOR = 26;
## `with [(] (VARIABLE | expression) [)] BLOCK [else BLOCK]`
export const NODE_WITH = 27;
## `return [expression] [;]`
export const NODE_RETURN = 28;
## `break [;]` or `continue [;]`
export const NODE_JUMP = 29;
## `expression [;]`
export const NODE_EXPRESSION_STATEMENT = 30;
## A `;` that ends nothing: after a block, or on its own. It says nothing.
export const NODE_EMPTY = 31;
## `( expression )`
export const NODE_PARENTHESIZED = 32;
## `expression operator expression`, assignments included.
export const NODE_BINARY = 33;
## `expression ? expression : expression`
export const NODE_TERNARY = 34;
## `operator expression`: `-x`, `!x`, `++x`, and negative literals.
export const NODE_PREFIX = 35;
## `expression ++` or `expression --`
export const NODE_POSTFIX = 36;
## `expression as TYPE`
export const NODE_CAST = 37;
## `expression . name [TYPE_ARGUMENTS]`
export const NODE_MEMBER = 38;
## `expression [ expression ]`
export const NODE_INDEX = 39;
## `expression ARGUMENTS`
export const NODE_CALL = 40;
## `( expression, ... )`
export const NODE_ARGUMENTS = 41;
## `sizeof < TYPE > [( )]`
export const NODE_SIZEOF = 42;
## A generic type used as an expression: `TYPE`, as in `Array<int>()`.
export const NODE_TYPE_LITERAL = 43;
## `CLOSURE_PARAMETERS [: TYPE] => (BLOCK | expression)`
export const NODE_CLOSURE = 44;
## `( CLOSURE_PARAMETER, ... )`
export const NODE_CLOSURE_PARAMETERS = 45;
## `name [: TYPE]`
export const NODE_CLOSURE_PARAMETER = 46;
## `[attribute]... [export] enum Name [GENERIC_PARAMETERS] [: TYPE] MEMBERS`,
## whose members are its `ENUM_CASE`s, then its methods.
export const NODE_ENUM = 47;
## `[attribute]... Name [PARAMETERS] [= expression] [,]`: one case of an enum.
export const NODE_ENUM_CASE = 48;
## `match expression MATCH_ARMS`
export const NODE_MATCH = 49;
## `{ MATCH_ARM... }`
export const NODE_MATCH_ARMS = 50;
## `PATTERN, ... => BLOCK`, or `else => BLOCK`.
export const NODE_MATCH_ARM = 51;
## `name[.name]... [( name, ... )]`: a case, and the names it binds.
export const NODE_PATTERN = 52;

## A node of the syntax tree: a token leaf, or a construct with children.
export struct Node {
    ## What construct this is: one of the `NODE_` constants.
    int kind;
    ## The token, for a `NODE_TOKEN` leaf; null otherwise.
    Token leaf;
    ## The construct's tokens and sub-nodes, in source order.
    Node[] children = Array<Node>();

    ## Creates a node with no children.
    ##
    ## @param this.kind one of the `NODE_` constants
    construct(this.kind = 0) {}

    ## Creates a `NODE_TOKEN` leaf holding `token`.
    ##
    ## @param token the token the leaf holds
    ## @returns the new leaf
    static of_token(token: Token): Node {
        var node = Node(NODE_TOKEN);
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
        return kind == NODE_TOKEN and leaf.text == text;
    }

    ## Returns the first token under this node, in source order.
    ##
    ## @returns the first token
    ## @panics if the node has no tokens
    first_token(): Token {
        if (kind == NODE_TOKEN) {
            return leaf;
        }
        return children[0].first_token();
    }

    ## Returns the last token under this node, in source order.
    ##
    ## @returns the last token
    ## @panics if the node has no tokens
    last_token(): Token {
        if (kind == NODE_TOKEN) {
            return leaf;
        }
        return children[children.count() - 1].last_token();
    }

    ## Returns whether any token under this node carries a comment.
    ##
    ## @returns true when a leading or trailing comment is attached below
    has_comments(): bool {
        if (kind == NODE_TOKEN) {
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
