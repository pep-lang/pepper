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
export const node_token = 0;
## A whole file: its items, then the end token.
export const node_module = 1;
## `[attribute]... import [list from] name [as alias] [;]`, or a re-export
## `[attribute]... export (* | list) from name [;]`.
export const node_import = 2;
## `[ symbol, ... ]` in an import: `IMPORT_SYMBOL`s separated by `,`.
export const node_import_list = 3;
## `name [as alias]` inside an import list.
export const node_import_symbol = 4;
## `[attribute]... export name[.name]... [as alias] [;]`
export const node_export_alias = 5;
## `[ expression ]`
export const node_attribute = 6;
## `[attribute]... [export] struct Name [GENERIC_PARAMETERS] MEMBERS`
export const node_struct = 7;
## `[attribute]... [export] trait Name [GENERIC_PARAMETERS] MEMBERS`
export const node_trait = 8;
## `[attribute]... [export] extend TYPE [with TYPE, ...] MEMBERS`
export const node_extend = 9;
## `[attribute]... [export] type Name [GENERIC_PARAMETERS] = TYPE [;]`
export const node_type_alias = 10;
## `{ member... }`: the body of a struct, trait or extension.
export const node_members = 11;
## `[attribute]... [export] extern TYPE name PARAMETERS [;]`
export const node_extern_function = 12;
## A function or method: `[attribute]... [export] [static]`, a signature,
## then a `BLOCK` (or `;` for a trait method without a body). The signature
## is `name [GENERIC_PARAMETERS] [PARAMETERS] [: TYPE]`,
## `TYPE name [PARAMETERS] [: TYPE]` (the name may be an operator), or the
## indexer form `TYPE [ ] PARAMETERS`.
export const node_function = 13;
## `[attribute]... construct PARAMETERS BLOCK`
export const node_constructor = 14;
## `[attribute]... destruct BLOCK`
export const node_destructor = 15;
## A variable, field or binding: `[attribute]... [export]`, then
## `var name`, `const name` or `TYPE name`, then `[: TYPE] [= expression]`,
## then `[;]`. A line break may stand in for the `;`, as for every simple
## statement.
export const node_variable = 16;
## `( PARAMETER, ... )`
export const node_parameters = 17;
## One parameter: `name : TYPE [= expression]`, `TYPE name [= expression]`,
## `this . field = expression`, a `var` form, or `...`.
export const node_parameter = 18;
## `< GENERIC_PARAMETER, ... >`
export const node_generic_parameters = 19;
## `Name [= TYPE]`
export const node_generic_parameter = 20;
## A type: `name[.name]... [TYPE_ARGUMENTS] [[ ]]... [*]...`, or a function
## type `[shared|extern] ( TYPE, ... ) => TYPE`.
export const node_type = 21;
## `< TYPE, ... >`
export const node_type_arguments = 22;
## `[attribute]... { statement... }`
export const node_block = 23;
## `if expression BLOCK [else (IF | BLOCK)]`
export const node_if = 24;
## `while expression BLOCK`
export const node_while = 25;
## `for [(] VARIABLE in expression [)] BLOCK`
export const node_for = 26;
## `with [(] (VARIABLE | expression) [)] BLOCK [else BLOCK]`
export const node_with = 27;
## `return [expression] [;]`
export const node_return = 28;
## `break [;]` or `continue [;]`
export const node_jump = 29;
## `expression [;]`
export const node_expression_statement = 30;
## A `;` that ends nothing: after a block, or on its own. It says nothing.
export const node_empty = 31;
## `( expression )`
export const node_parenthesized = 32;
## `expression operator expression`, assignments included.
export const node_binary = 33;
## `expression ? expression : expression`
export const node_ternary = 34;
## `operator expression`: `-x`, `!x`, `++x`, and negative literals.
export const node_prefix = 35;
## `expression ++` or `expression --`
export const node_postfix = 36;
## `expression as TYPE`
export const node_cast = 37;
## `expression . name [TYPE_ARGUMENTS]`
export const node_member = 38;
## `expression [ expression ]`
export const node_index = 39;
## `expression ARGUMENTS`
export const node_call = 40;
## `( expression, ... )`
export const node_arguments = 41;
## `sizeof < TYPE > [( )]`
export const node_sizeof = 42;
## A generic type used as an expression: `TYPE`, as in `Array<int>()`.
export const node_type_literal = 43;
## `CLOSURE_PARAMETERS [: TYPE] => (BLOCK | expression)`
export const node_closure = 44;
## `( CLOSURE_PARAMETER, ... )`
export const node_closure_parameters = 45;
## `name [: TYPE]`
export const node_closure_parameter = 46;
## `[attribute]... [export] enum Name [GENERIC_PARAMETERS] [: TYPE] MEMBERS`,
## whose members are its `ENUM_CASE`s, then its methods.
export const node_enum = 47;
## `[attribute]... Name [PARAMETERS] [= expression] [,]`: one case of an enum.
export const node_enum_case = 48;
## `match expression MATCH_ARMS`
export const node_match = 49;
## `{ MATCH_ARM... }`
export const node_match_arms = 50;
## `PATTERN, ... => BLOCK`, or `else => BLOCK`.
export const node_match_arm = 51;
## `name[.name]... [( name, ... )]`: a case, and the names it binds.
export const node_pattern = 52;

## A node of the syntax tree: a token leaf, or a construct with children.
export struct Node {
    ## What construct this is: one of the `NODE_` constants.
    int kind;
    ## The token, for a `node_token` leaf; null otherwise.
    Token leaf;
    ## The construct's tokens and sub-nodes, in source order.
    Node[] children = Array<Node>();

    ## Creates a node with no children.
    ##
    ## @param this.kind one of the `NODE_` constants
    construct(this.kind = 0) {}

    ## Creates a `node_token` leaf holding `token`.
    ##
    ## @param token the token the leaf holds
    ## @returns the new leaf
    static of_token(token: Token): Node {
        var node = Node(node_token);
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
        return kind == node_token and leaf.text == text;
    }

    ## Returns the first token under this node, in source order.
    ##
    ## @returns the first token
    ## @panics if the node has no tokens
    first_token(): Token {
        if (kind == node_token) {
            return leaf;
        }
        return children[0].first_token();
    }

    ## Returns the last token under this node, in source order.
    ##
    ## @returns the last token
    ## @panics if the node has no tokens
    last_token(): Token {
        if (kind == node_token) {
            return leaf;
        }
        return children[children.count() - 1].last_token();
    }

    ## Returns whether any token under this node carries a comment.
    ##
    ## @returns true when a leading or trailing comment is attached below
    has_comments(): bool {
        if (kind == node_token) {
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
