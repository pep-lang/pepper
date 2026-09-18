//! Full Pepper grammar implemented with winnow.
//!
//! Precedence (low → high):
//!   assignment  →  ternary  →  logical_or  →  logical_and  →
//!   bit_or      →  bit_and   →  equality    →  relational   →
//!   shift       →  add       →  mul         →  prefix       →
//!   unary       →  pow       →  postfix     →  atom

use crate::ast::*;
use winnow::error::ErrMode;


// Error type for &str input (lifetime elided via associated type)
pub type Result<T> = std::result::Result<T, ErrMode<&'static str>>;

fn bt(_input: &mut &str) -> ErrMode<&'static str> {
    ErrMode::Backtrack("parse error")
}
fn cut(_input: &mut &str) -> ErrMode<&'static str> {
    ErrMode::Cut("parse error")
}

// ── Keywords ──────────────────────────────────────────────────────────────────

const RESERVED: &[&str] = &[
    "import", "use", "struct", "var", "const",
    "if", "else", "while", "return", "extern",
    "and", "or", "new", "construct", "destruct", "static",
    "sizeof", "true", "false",
    "trait", "extend",
];

/// Operators that may appear as method names (overloadable operators), longest first.
const OPERATORS: &[&str] = &[
    "<<=", ">>=", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=",
    "++", "--", "<<", ">>", "**", "&&", "||", "&=", "|=", "^=",
    "+", "-", "*", "/", "%", "<", ">", "&", "|", "^", "!", "~",
];

/// Parse an operator token (used as an overloadable method name, e.g. `bool ==(x)`).
fn operator_name(input: &mut &str) -> Result<String> {
    for op in OPERATORS {
        if input.starts_with(op) {
            *input = &input[op.len()..];
            return Ok(op.to_string());
        }
    }
    Err(bt(input))
}

// ── Whitespace / comments ─────────────────────────────────────────────────────

fn ws(input: &mut &str) -> Result<()> {
    loop {
        let before = *input;
        // skip whitespace chars
        while let Some(c) = input.chars().next() {
            if c.is_whitespace() {
                *input = &input[1..];
            } else {
                break;
            }
        }
        // skip # comment to end of line
        if input.starts_with('#') {
            *input = &input[1..];
            while let Some(c) = input.chars().next() {
                *input = &input[1..];
                if c == '\n' { break; }
            }
        }
        if *input == before { break; }
    }
    Ok(())
}

/// Skip spaces/tabs only, stopping before a newline (used after a default
/// expression so decl_boundary can see the statement separator).
fn skip_inline_ws(input: &mut &str) {
    while let Some(c) = input.chars().next() {
        if c == ' ' || c == '\t' || c == '\r' {
            *input = &input[1..];
        } else {
            break;
        }
    }
}

// ── Tokens ────────────────────────────────────────────────────────────────────

fn identifier(input: &mut &str) -> Result<String> {
    let start = *input;
    // first char: alpha or _
    match input.chars().next() {
        Some(c) if c.is_ascii_alphabetic() || c == '_' => {
            *input = &input[1..];
        }
        _ => return Err(bt(input)),
    }
    // rest: alnum or _
    while let Some(c) = input.chars().next() {
        if c.is_ascii_alphanumeric() || c == '_' {
            *input = &input[1..];
        } else {
            break;
        }
    }
    let id = start[..start.len() - input.len()].to_string();
    if RESERVED.contains(&id.as_str()) {
        *input = start; // restore
        return Err(bt(input));
    }
    Ok(id)
}

fn type_name(input: &mut &str) -> Result<TypeName> {
    let mut ty = type_name_base(input)?;

    // array suffix: one or more `[]`  (e.g. int[], int[][], ptr<char>[]) 
    loop {
        ws(input)?;
        if input.starts_with('[') {
            *input = &input[1..];
            ws(input)?;
            if input.starts_with(']') {
                *input = &input[1..];
                ty.name.push_str("[]");
                continue;
            }
            // malformed — restore and break
            break;
        }
        break;
    }

    Ok(ty)
}

/// Type name without a trailing array suffix, so indexer methods
/// (`T [](params)`) are not mistaken for `T[]` array types.
fn type_name_base(input: &mut &str) -> Result<TypeName> {
    let name = identifier(input)?;
    ws(input)?;

    // generic types: < T, T, ... >
    let mut generic_types = vec![];
    if input.starts_with('<') {
        *input = &input[1..];
        loop {
            ws(input)?;
            generic_types.push(type_name(input)?);
            ws(input)?;
            if input.starts_with(',') {
                *input = &input[1..];
                continue;
            }
            if input.starts_with('>') {
                *input = &input[1..];
                break;
            }
            return Err(cut(input));
        }
    }

    Ok(TypeName { name, generic_types })
}

fn string_constant(input: &mut &str) -> Result<Literal> {
    if !input.starts_with('"') {
        return Err(bt(input));
    }
    *input = &input[1..]; // consume opening quote
    let mut content = String::new();
    while let Some(c) = input.chars().next() {
        if c == '"' { break; }
        content.push(c);
        *input = &input[c.len_utf8()..];
    }
    // consume closing quote
    if !input.starts_with('"') { return Err(cut(input)); }
    *input = &input[1..];
    Ok(Literal::String(content))
}

fn numeric_constant(input: &mut &str) -> Result<Literal> {
    let start = *input;

    // hex
    if input.starts_with("0x") {
        *input = &input[2..];
        while let Some(c) = input.chars().next() {
            if c.is_ascii_hexdigit() {
                *input = &input[1..];
            } else {
                break;
            }
        }
        let hex = &start[2..start.len() - input.len()];
        return Ok(Literal::Integer(i64::from_str_radix(hex, 16).unwrap()));
    }

    // integer part
    while let Some(c) = input.chars().next() {
        if c.is_ascii_digit() { *input = &input[1..]; } else { break; }
    }

    // fraction
    let has_frac = input.starts_with('.');
    if has_frac {
        *input = &input[1..];
        while let Some(c) = input.chars().next() {
            if c.is_ascii_digit() { *input = &input[1..]; } else { break; }
        }
    }

    // exponent
    let has_exp = input.starts_with('e') || input.starts_with('E');
    if has_exp {
        *input = &input[1..];
        if input.starts_with('+') || input.starts_with('-') { *input = &input[1..]; }
        while let Some(c) = input.chars().next() {
            if c.is_ascii_digit() { *input = &input[1..]; } else { break; }
        }
    }

    let s = &start[..start.len() - input.len()];
    if has_frac || has_exp {
        Ok(Literal::Float(s.parse().unwrap()))
    } else {
        Ok(Literal::Integer(s.parse().unwrap()))
    }
}

// ── Expressions ───────────────────────────────────────────────────────────────

fn primary_expression(input: &mut &str) -> Result<Expression> {
    // true / false
    if input.starts_with("true") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[4..];
        return Ok(Expression::Literal(Literal::Bool(true)));
    }
    if input.starts_with("false") && !input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[5..];
        return Ok(Expression::Literal(Literal::Bool(false)));
    }
    // numeric
    if input.starts_with(|c: char| c.is_ascii_digit()) || (input.starts_with('-') && input[1..].starts_with(|c: char| c.is_ascii_digit())) {
        let n = numeric_constant(input)?;
        return Ok(Expression::Literal(n));
    }
    // string
    if input.starts_with('"') || input.starts_with('@') {
        let s = string_constant(input)?;
        return Ok(Expression::Literal(s));
    }
    // __null
    if input.starts_with("__null") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[6..];
        return Ok(Expression::Literal(Literal::Null));
    }
    // sizeof<TypeName>
    if input.starts_with("sizeof") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[6..];
        ws(input)?;
        if !input.starts_with('<') { return Err(cut(input)); }
        *input = &input[1..];
        ws(input)?;
        let ty = type_name(input)?;
        ws(input)?;
        if !input.starts_with('>') { return Err(cut(input)); }
        *input = &input[1..];
        // `sizeof<T>()` is the same expression; absorb the call parens so we
        // don't wrap a `SizeOf` in an empty `FunctionCall`.
        ws(input)?;
        if input.starts_with('(') {
            *input = &input[1..];
            ws(input)?;
            if !input.starts_with(')') { return Err(cut(input)); }
            *input = &input[1..];
        }
        return Ok(Expression::SizeOf(ty));
    }
    // symbol reference, or a generic type literal such as `array<int>` in `array<int>()`
    let before = *input;
    let name = identifier(input)?;
    ws(input)?;
    if input.starts_with('<') {
        let mut probe: &str = before;
        if let Ok(ty) = type_name(&mut probe) {
            // The whole `Name<...>` parsed as a type; advance the real input past it.
            // (If it failed, this was a `<` comparison and `name` is a plain symbol.)
            *input = probe;
            return Ok(Expression::TypeLiteral(ty));
        }
    }
    Ok(Expression::SymbolRef(name))
}

fn atom(input: &mut &str) -> Result<Expression> {
    if input.starts_with('(') {
        *input = &input[1..];
        ws(input)?;
        let expr = expression(input)?;
        ws(input)?;
        if !input.starts_with(')') { return Err(cut(input)); }
        *input = &input[1..];
        return Ok(expr);
    }
    primary_expression(input)
}

fn postfix(input: &mut &str) -> Result<Expression> {
    let mut expr = atom(input)?;
    loop {
        // The raw remainder starting with a newline separates statements:
        // stop before ws() swallows it into a postfix operator check.
        if input.starts_with('\n') || input.starts_with("\r\n") {
            break;
        }
        ws(input)?;
        if input.starts_with('.') {
            *input = &input[1..];
            ws(input)?;
            let name = identifier(input)?;
            expr = Expression::MemberAccess { lhs: Box::new(expr), name };
            continue;
        }
        if input.starts_with('[') {
            *input = &input[1..];
            ws(input)?;
            let rhs = expression(input)?;
            ws(input)?;
            if !input.starts_with(']') { return Err(cut(input)); }
            *input = &input[1..];
            expr = Expression::Index { lhs: Box::new(expr), rhs: Box::new(rhs) };
            continue;
        }
        if input.starts_with('(') {
            *input = &input[1..];
            ws(input)?;
            let mut args = vec![];
            if !input.starts_with(')') {
                loop {
                    ws(input)?;
                    args.push(expression(input)?);
                    ws(input)?;
                    if input.starts_with(',') {
                        *input = &input[1..];
                        continue;
                    }
                    break;
                }
            }
            ws(input)?;
            if !input.starts_with(')') { return Err(cut(input)); }
            *input = &input[1..];
            expr = Expression::FunctionCall { function: Box::new(expr), arguments: args };
            continue;
        }
        if input.starts_with("++") || input.starts_with("--") {
            let op = if input.starts_with("++") { "++" } else { "--" };
            *input = &input[op.len()..];
            expr = Expression::Unary { op: op.to_string(), prefix: false, operand: Box::new(expr) };
            continue;
        }
        break;
    }
    Ok(expr)
}

/// `**` — right-associative, operand is postfix (function-call level)
fn pow(input: &mut &str) -> Result<Expression> {
    let base = postfix(input)?;
    // A newline after the operand separates statements; no `**` can follow.
    if !input.starts_with('\n') && !input.starts_with("\r\n") {
        ws(input)?;
    }
    if input.starts_with("**") {
        *input = &input[2..];
        ws(input)?;
        let rhs = pow(input)?; // right-assoc: rhs is another pow
        return Ok(Expression::Binary { lhs: Box::new(base), op: "**".into(), rhs: Box::new(rhs) });
    }
    Ok(base)
}

/// prefix `+`, `-`, `~`, `!` — operand is pow
fn unary(input: &mut &str) -> Result<Expression> {
    ws(input)?;
    // Never grab the operator part of compound assignments (`+=`, `-=`); those
    // belong to the assignment level. `++`/`--` are handled by `prefix_op` above.
    let op = if input.starts_with('+') && !input.starts_with("++") && !input.starts_with("+=") { Some("+") }
        else if input.starts_with('-') && !input.starts_with("--") && !input.starts_with("-=") { Some("-") }
        else if input.starts_with('~') { Some("~") }
        else if input.starts_with('!') { Some("!") }
        else { None };
    if let Some(op) = op {
        *input = &input[op.len()..];
        let operand = pow(input)?;
        return Ok(Expression::Unary { op: op.to_string(), prefix: true, operand: Box::new(operand) });
    }
    pow(input)
}

/// prefix `++`, `--` — operand is unary
fn prefix_op(input: &mut &str) -> Result<Expression> {
    ws(input)?;
    if input.starts_with("++") {
        *input = &input[2..];
        let operand = unary(input)?;
        return Ok(Expression::Unary { op: "++".into(), prefix: true, operand: Box::new(operand) });
    }
    if input.starts_with("--") {
        *input = &input[2..];
        let operand = unary(input)?;
        return Ok(Expression::Unary { op: "--".into(), prefix: true, operand: Box::new(operand) });
    }
    unary(input)
}

fn binary_left(
    input: &mut &str,
    operand: impl Fn(&mut &str) -> Result<Expression>,
    try_op: impl Fn(&str) -> Option<&str>,
) -> Result<Expression> {
    let mut lhs = operand(input)?;
    // If the remainder after the operand begins a new line, the expression is
    // complete: a statement separator follows. The caller's boundary check
    // must see that newline, so don't let ws() in the operator loop swallow
    // it — track whether the first loop iteration started at a newline.
    let started_at_newline = input.starts_with('\n') || input.starts_with("\r\n");
    loop {
        if started_at_newline {
            // No operator can follow a statement separator on the next line
            // in this grammar (no line continuation); stop before ws eats it.
            break;
        }
        ws(input)?;
        let before = *input;
        if let Some(op) = try_op(input) {
            *input = &input[op.len()..];
            let rhs = operand(input)?;
            lhs = Expression::Binary { lhs: Box::new(lhs), op: op.to_string(), rhs: Box::new(rhs) };
        } else {
            *input = before;
            break;
        }
    }
    Ok(lhs)
}

fn binary_right(
    input: &mut &str,
    operand: impl Fn(&mut &str) -> Result<Expression>,
    try_op: impl Fn(&str) -> Option<&str>,
) -> Result<Expression> {
    let lhs = operand(input)?;
    if !input.starts_with('\n') && !input.starts_with("\r\n") {
        ws(input)?;
    }
    if let Some(op) = try_op(input) {
        *input = &input[op.len()..];
        let rhs = binary_right(input, operand, try_op)?;
        return Ok(Expression::Binary { lhs: Box::new(lhs), op: op.to_string(), rhs: Box::new(rhs) });
    }
    Ok(lhs)
}

fn mul(input: &mut &str) -> Result<Expression> {
    binary_left(input, prefix_op, |s: &str| {
        // `**` is handled by `pow`; `*=` / `/=` / `%=` belong to the assignment level
        if s.starts_with('*') && !s[1..].starts_with('*') && !s[1..].starts_with('=') { return Some("*"); }
        if s.starts_with('/') && !s[1..].starts_with('=') { return Some("/"); }
        if s.starts_with('%') && !s[1..].starts_with('=') { return Some("%"); }
        None
    })
}

fn add(input: &mut &str) -> Result<Expression> {
    binary_left(input, mul, |s: &str| {
        // `+=` / `-=` belong to the assignment level
        if s.starts_with('+') && !s.starts_with("++") && !s.starts_with("+=") { return Some("+"); }
        if s.starts_with('-') && !s.starts_with("--") && !s.starts_with("-=") { return Some("-"); }
        None
    })
}

fn shift(input: &mut &str) -> Result<Expression> {
    binary_left(input, add, |s: &str| {
        if s.starts_with("<<") && !s.starts_with("<<=") { return Some("<<"); }
        if s.starts_with(">>") && !s.starts_with(">>=") { return Some(">>"); }
        None
    })
}

fn relational(input: &mut &str) -> Result<Expression> {
    binary_left(input, shift, |s: &str| {
        if s.starts_with("<=") { return Some("<="); }
        if s.starts_with(">=") { return Some(">="); }
        // `<<` is handled by `shift` above
        if s.starts_with('<') && !s[1..].starts_with('=') && !s[1..].starts_with('<') { return Some("<"); }
        if s.starts_with('>') && !s[1..].starts_with('=') && !s[1..].starts_with('>') { return Some(">"); }
        None
    })
}

fn equality(input: &mut &str) -> Result<Expression> {
    binary_left(input, relational, |s: &str| {
        if s.starts_with("===") { return Some("==="); }
        if s.starts_with("==") { return Some("=="); }
        if s.starts_with("!=") { return Some("!="); }
        None
    })
}

fn bit_and(input: &mut &str) -> Result<Expression> {
    binary_left(input, equality, |s: &str| {
        // `&&` is handled above; `&=` belongs to the assignment level
        if s.starts_with('&') && !s[1..].starts_with('&') && !s[1..].starts_with('=') { return Some("&"); }
        None
    })
}

fn bit_or(input: &mut &str) -> Result<Expression> {
    binary_left(input, bit_and, |s: &str| {
        // `||` is handled above; `|=` / `^=` belong to the assignment level
        if s.starts_with('|') && !s[1..].starts_with('|') && !s[1..].starts_with('=') { return Some("|"); }
        if s.starts_with('^') && !s[1..].starts_with('=') { return Some("^"); }
        None
    })
}

fn logical_and(input: &mut &str) -> Result<Expression> {
    binary_left(input, bit_or, |s: &str| {
        if s.starts_with("&&") { return Some("&&"); }
        if s.starts_with("and") && !s[3..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
            return Some("and");
        }
        None
    })
}

fn logical_or(input: &mut &str) -> Result<Expression> {
    binary_left(input, logical_and, |s: &str| {
        if s.starts_with("||") { return Some("||"); }
        if s.starts_with("or") && !s[2..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
            return Some("or");
        }
        None
    })
}

fn ternary(input: &mut &str) -> Result<Expression> {
    let cond = logical_or(input)?;
    // A newline after the condition separates statements; no ternary follows.
    if !input.starts_with('\n') && !input.starts_with("\r\n") {
        ws(input)?;
    }
    if !input.starts_with('?') { return Ok(cond); }
    *input = &input[1..];
    ws(input)?;
    let true_expr = expression(input)?;
    ws(input)?;
    if !input.starts_with(':') { return Err(cut(input)); }
    *input = &input[1..];
    ws(input)?;
    let false_expr = expression(input)?;
    Ok(Expression::Ternary {
        condition: Box::new(cond),
        true_expr: Box::new(true_expr),
        false_expr: Box::new(false_expr),
    })
}

fn assignment(input: &mut &str) -> Result<Expression> {
    binary_right(input, ternary, |s: &str| {
        if s.starts_with("*=") { return Some("*="); }
        if s.starts_with("/=") { return Some("/="); }
        if s.starts_with("%=") { return Some("%="); }
        if s.starts_with("+=") { return Some("+="); }
        if s.starts_with("-=") { return Some("-="); }
        if s.starts_with("<<=") { return Some("<<="); }
        if s.starts_with(">>=") { return Some(">>="); }
        if s.starts_with("&=") { return Some("&="); }
        if s.starts_with("^=") { return Some("^="); }
        if s.starts_with("|=") { return Some("|="); }
        if s.starts_with('=') && !s[1..].starts_with('=') { return Some("="); }
        None
    })
}

pub fn expression(input: &mut &str) -> Result<Expression> {
    assignment(input)
}

// ── Statements ────────────────────────────────────────────────────────────────

/// Variable declaration — supports two syntaxes:
///   1. `[var|const] name [: TypeName] [= expr]`
///   2. `TypeName name [= expr]`  (struct field style)
fn variable_declaration(input: &mut &str) -> Result<VariableDecl> {
    let before = *input;

    // Case 1: explicit specifier (var / const)
    if input.starts_with("const") && !input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[5..];
        ws(input)?;
        let name = identifier(input)?;
        ws(input)?;
        let mut ty = TypeName::auto();
        if input.starts_with(':') {
            *input = &input[1..];
            ws(input)?;
            ty = type_name(input)?;
            ws(input)?;
        }
        let mut dv = None;
        if input.starts_with('=') && !input[1..].starts_with('=') {
            *input = &input[1..];
            ws(input)?;
            dv = Some(expression(input)?);
            // Stop whitespace-skipping at a newline so decl_boundary can see
            // the statement separator.
            skip_inline_ws(input);
        }
        return Ok(VariableDecl { name, type_name: ty, default_value: dv, is_const: true });
    }
    if input.starts_with("var") && !input[3..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[3..];
        ws(input)?;
        let name = identifier(input)?;
        ws(input)?;
        let mut ty = TypeName::auto();
        if input.starts_with(':') {
            *input = &input[1..];
            ws(input)?;
            ty = type_name(input)?;
            ws(input)?;
        }
        let mut dv = None;
        if input.starts_with('=') && !input[1..].starts_with('=') {
            *input = &input[1..];
            ws(input)?;
            dv = Some(expression(input)?);
            // Stop whitespace-skipping at a newline so decl_boundary can see
            // the statement separator.
            skip_inline_ws(input);
        }
        return Ok(VariableDecl { name, type_name: ty, default_value: dv, is_const: false });
    }

    // Case 2: type-name syntax — `TypeName name [= expr]`
    // Only valid when NOT followed by '(' (which would indicate a function call)
    let mut ty = type_name(input)?;
    ws(input)?;

    // If the next token is '(' this is a function call, not a declaration
    if input.starts_with('(') {
        *input = before;
        return Err(bt(input));
    }

    let name = identifier(input)?;
    ws(input)?;

    // Optional `: Type` annotation (parameter style: `a: int`).
    if input.starts_with(':') {
        *input = &input[1..];
        ws(input)?;
        ty = type_name(input)?;
        ws(input)?;
    }

    let mut dv = None;
    if input.starts_with('=') && !input[1..].starts_with('=') {
        *input = &input[1..];
        ws(input)?;
        dv = Some(expression(input)?);
        skip_inline_ws(input);
    }

    Ok(VariableDecl { name, type_name: ty, default_value: dv, is_const: false })
}

fn block(input: &mut &str) -> Result<Block> {
    if !input.starts_with('{') { return Err(cut(input)); }
    *input = &input[1..];

    let mut statements = vec![];
    loop {
        ws(input)?;
        if input.is_empty() || input.starts_with('}') { break; }
        if input.starts_with(';') {
            *input = &input[1..];
            continue;
        }
        let stmt = statement(input)?;
        statements.push(stmt);
        ws(input)?;
        if input.starts_with(';') {
            *input = &input[1..];
        }
    }
    ws(input)?;
    if input.starts_with('}') {
        *input = &input[1..];
    }
    Ok(Block { statements })
}

fn branch(input: &mut &str) -> Result<Branch> {
    if !input.starts_with("if") || input[2..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[2..];
    ws(input)?;
    let condition = expression(input)?;
    ws(input)?;
    let if_block = block(input)?;
    ws(input)?;

    let mut else_block = None;
    if input.starts_with("else") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[4..];
        ws(input)?;
        else_block = Some(block(input)?);
        ws(input)?;
    }

    Ok(Branch { condition, if_block, else_block })
}

fn while_loop(input: &mut &str) -> Result<While> {
    if !input.starts_with("while") || input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[5..];
    ws(input)?;
    let condition = expression(input)?;
    ws(input)?;
    let block = block(input)?;
    ws(input)?;
    Ok(While { condition, block })
}

fn return_statement(input: &mut &str) -> Result<ReturnStatement> {
    if !input.starts_with("return") || input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[6..];
    ws(input)?;
    let expr = expression(input)?;
    ws(input)?;
    Ok(ReturnStatement { expr })
}

/// After a `TypeName name` style declaration the next token must be a boundary
/// (`;`, `=`, `}`, newline, or end of input) — otherwise it was an expression
/// all along.
fn decl_boundary(input: &mut &str) -> bool {
    // The raw (pre-ws) remainder starting with a newline separates statements
    // that omit semicolons; ws() would swallow it into the next token.
    if input.starts_with('\n') || input.starts_with("\r\n") {
        return true;
    }
    if ws(input).is_err() {
        return false;
    }
    let s = *input;
    s.is_empty()
        || s.starts_with(';')
        || s.starts_with('}')
        || s.starts_with('\n')
        || (s.starts_with('=') && !s.starts_with("=="))
}

fn statement(input: &mut &str) -> Result<Statement> {
    ws(input)?;

    if input.starts_with('{') {
        let b = block(input)?;
        return Ok(Statement::Block(b));
    }
    if input.starts_with("if") && !input[2..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Statement::Branch(branch(input)?));
    }
    if input.starts_with("while") && !input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Statement::While(while_loop(input)?));
    }
    if input.starts_with("return") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Statement::Return(return_statement(input)?));
    }
    // Variable declaration: `var`/`const` prefix OR `TypeName name = value` form
    let is_var_decl = (input.starts_with("var") && !input[3..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_'))
        || (input.starts_with("const") && !input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_'))
        || (input.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')
            && !input.starts_with("if") && !input.starts_with("while") && !input.starts_with("return")
            && !input.starts_with("struct") && !input.starts_with("extern")
            && !input.starts_with("import") && !input.starts_with("use")
            && !input.starts_with("true") && !input.starts_with("false")
            && !input.starts_with("sizeof") && !input.starts_with("and") && !input.starts_with("or")
            && !input.starts_with("new") && !input.starts_with("construct") && !input.starts_with("destruct")
            && !input.starts_with("static") && !input.starts_with("trait") && !input.starts_with("extend")
            && !input.starts_with('('));
    if is_var_decl {
        let before = *input;
        if let Ok(v) = variable_declaration(input) {
            // A real declaration must end at a boundary; otherwise what looked like
            // `type name` was really an expression such as `arr[idx] = 1`.
            if decl_boundary(input) {
                return Ok(Statement::Declaration(Declaration::Variable(v)));
            }
        }
        *input = before;
    }
    // otherwise: expression statement
    let expr = expression(input)?;
    ws(input)?;
    Ok(Statement::Expression(expr))
}

// ── Declarations ──────────────────────────────────────────────────────────────

fn function_parameters(input: &mut &str) -> Result<Vec<VariableDecl>> {
    if !input.starts_with('(') { return Err(cut(input)); }
    *input = &input[1..];
    let mut params = vec![];
    loop {
        ws(input)?;
        if input.starts_with(')') {
            *input = &input[1..];
            break;
        }
        // C++ param grammar (Parser.cpp:1094-1140): `name: Type [= expr]`,
        // or `this.<field> [= expr]` constructor params.
        if input.starts_with("this") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
            params.push(constructor_parameter(input)?);
        } else {
            params.push(typed_parameter(input)?);
        }
        ws(input)?;
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        if input.starts_with(')') {
            *input = &input[1..];
            break;
        }
        return Err(cut(input));
    }
    Ok(params)
}

/// Parameter in C++ grammar: `name: Type [= expr]` (Parser.cpp:1106-1139),
/// or C-style `Type name [= expr]` (used by the corpus, e.g. lib.pep's
/// `int sum(int x, int y)`).
fn typed_parameter(input: &mut &str) -> Result<VariableDecl> {
    let before = *input;
    // Colon style: `name: Type`.
    if let Ok(decl) = (|| {
        let name = identifier(input)?;
        ws(input)?;
        if !input.starts_with(':') {
            return Err(bt(input));
        }
        *input = &input[1..];
        ws(input)?;
        let ty = type_name(input)?;
        ws(input)?;
        Ok((name, ty))
    })() {
        let (name, ty) = decl;
        let mut dv = None;
        if input.starts_with('=') && !input[1..].starts_with('=') {
            *input = &input[1..];
            ws(input)?;
            dv = Some(expression(input)?);
            skip_inline_ws(input);
        }
        return Ok(VariableDecl { name, type_name: ty, default_value: dv, is_const: false });
    }
    // C style: `Type name`.
    *input = before;
    let ty = type_name(input)?;
    ws(input)?;
    let name = identifier(input)?;
    ws(input)?;
    let mut dv = None;
    if input.starts_with('=') && !input[1..].starts_with('=') {
        *input = &input[1..];
        ws(input)?;
        dv = Some(expression(input)?);
        skip_inline_ws(input);
    }
    Ok(VariableDecl { name, type_name: ty, default_value: dv, is_const: false })
}

fn generic_params(input: &mut &str) -> Result<Vec<TypeName>> {
    if !input.starts_with('<') { return Err(cut(input)); }
    *input = &input[1..];
    let mut types = vec![];
    loop {
        ws(input)?;
        if input.starts_with('>') {
            *input = &input[1..];
            break;
        }
        types.push(type_name(input)?);
        ws(input)?;
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        if input.starts_with('>') {
            *input = &input[1..];
            break;
        }
        return Err(cut(input));
    }
    Ok(types)
}

/// Function declaration — supports two syntaxes:
///   1. `name [generic_params] (params) [: TypeName] { body }`
///   2. `TypeName name (params) { body }`  (return-type prefix style)
fn function_declaration(input: &mut &str) -> Result<FunctionDecl> {
    let before = *input;

    // Parse first identifier
    let first = identifier(input)?;
    ws(input)?;

    // Determine which syntax based on what follows
    if input.starts_with('(') || input.starts_with('<') {
        // Syntax 1: `first` is the function name
        let generic_params = if input.starts_with('<') {
            generic_params(input)?
        } else {
            vec![]
        };
        ws(input)?;

        let parameters = if input.starts_with('(') {
            function_parameters(input)?
        } else {
            vec![]
        };
        ws(input)?;

        let mut return_type = TypeName::auto();
        if input.starts_with(':') {
            *input = &input[1..];
            ws(input)?;
            return_type = type_name(input)?;
            ws(input)?;
        }
        let body = block(input)?;
        ws(input)?;

        return Ok(FunctionDecl {
            name: first,
            generic_params,
            return_type,
            parameters,
            external: false,
            body: Some(body),
            is_static: false,
            is_indexer: false,
        });
    }

    // Syntax 2: `first` is the return type, next identifier is the name
    if input.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_') {
        let return_type = TypeName { name: first, generic_types: vec![] };
        let name = identifier(input)?;
        ws(input)?;

        let parameters = if input.starts_with('(') {
            function_parameters(input)?
        } else {
            vec![]
        };
        ws(input)?;

        // Optional trailing `: Type` return annotation.
        let mut effective_return = return_type;
        if input.starts_with(':') {
            *input = &input[1..];
            ws(input)?;
            effective_return = type_name(input)?;
            ws(input)?;
        }

        let body = block(input)?;
        ws(input)?;

        return Ok(FunctionDecl {
            name,
            generic_params: vec![],
            return_type: effective_return,
            parameters,
            external: false,
            body: Some(body),
            is_static: false,
            is_indexer: false,
        });
    }

    *input = before;
    Err(bt(input))
}

/// `TypeName` with an optional C-style pointer suffix (`char*`, `int**`),
/// matching the C++ grammar's `ExternTypeName`.
fn extern_type_name(input: &mut &str) -> Result<TypeName> {
    let mut ty = type_name(input)?;
    loop {
        if input.starts_with('*') {
            *input = &input[1..];
            ty.name.push('*');
        } else {
            break;
        }
    }
    Ok(ty)
}

/// Extern function parameters: `ExternTypeName Identifier` pairs (`char* str`).
fn extern_parameters(input: &mut &str) -> Result<Vec<VariableDecl>> {
    if !input.starts_with('(') { return Err(cut(input)); }
    *input = &input[1..];
    let mut params = vec![];
    loop {
        ws(input)?;
        if input.starts_with(')') { break; }
        let ty = extern_type_name(input)?;
        ws(input)?;
        let name = identifier(input)?;
        ws(input)?;
        params.push(VariableDecl { name, type_name: ty, default_value: None, is_const: false });
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        if !input.starts_with(')') { return Err(cut(input)); }
        break;
    }
    *input = &input[1..];
    ws(input)?;
    Ok(params)
}

fn extern_function_declaration(input: &mut &str) -> Result<FunctionDecl> {
    if !input.starts_with("extern") || input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[6..];
    ws(input)?;

    let return_type = extern_type_name(input)?;
    ws(input)?;
    let name = identifier(input)?;
    ws(input)?;
    let parameters = extern_parameters(input)?;
    ws(input)?;
    if input.starts_with(';') {
        *input = &input[1..];
    }

    Ok(FunctionDecl {
        name,
        generic_params: vec![],
        return_type,
        parameters,
        external: true,
        body: None,
        is_static: false,
        is_indexer: false,
    })
}

/// Constructor parameter — either `this.<field> = value` or a normal declaration.
fn constructor_parameter(input: &mut &str) -> Result<VariableDecl> {
    ws(input)?;
    if input.starts_with("this") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[4..];
        if !input.starts_with('.') { return Err(cut(input)); }
        *input = &input[1..];
        ws(input)?;
        let field = identifier(input)?;
        ws(input)?;
        if !input.starts_with('=') { return Err(cut(input)); }
        *input = &input[1..];
        ws(input)?;
        let value = expression(input)?;
        ws(input)?;
        return Ok(VariableDecl {
            name: format!("this.{}", field),
            type_name: TypeName::auto(),
            default_value: Some(value),
            is_const: false,
        });
    }
    variable_declaration(input)
}

/// A function with an already-parsed name: `name (params) [: TypeName] { body }`.
fn named_function(input: &mut &str, name: String) -> Result<FunctionDecl> {
    ws(input)?;
    let generic_params = if input.starts_with('<') {
        generic_params(input)?
    } else {
        vec![]
    };
    ws(input)?;
    let parameters = if input.starts_with('(') {
        function_parameters(input)?
    } else {
        vec![]
    };
    ws(input)?;
    let mut return_type = TypeName::auto();
    if input.starts_with(':') {
        *input = &input[1..];
        ws(input)?;
        return_type = type_name(input)?;
        ws(input)?;
    }
    let body = block(input)?;
    ws(input)?;
    Ok(FunctionDecl {
        name,
        generic_params,
        return_type,
        parameters,
        external: false,
        body: Some(body),
        is_static: false,
        is_indexer: false,
    })
}

/// A method inside a struct or `extend` block:
///   - `static` modifier
///   - indexer method: `T [](params) { body }`
///   - operator overload: `bool ==(x) { ... }` / `string +=(x) { ... }`
///   - `name(params) [: type] { body }` or `ReturnType name(params) { body }`
fn struct_method(input: &mut &str) -> Result<FunctionDecl> {
    ws(input)?;
    let is_static = if input.starts_with("static") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[6..];
        ws(input)?;
        true
    } else {
        false
    };

    // Indexer method: `T [](params) { body }`
    let before = *input;
    let mut after: &str = *input;
    if let Ok(ty) = type_name_base(&mut after) {
        ws(&mut after)?;
        if after.starts_with("[]") {
            after = &after[2..];
            ws(&mut after)?;
            if after.starts_with('(') {
                let parameters = function_parameters(&mut after)?;
                ws(&mut after)?;
                let body = block(&mut after)?;
                ws(&mut after)?;
                *input = after;
                return Ok(FunctionDecl {
                    name: if parameters.len() >= 2 { "__index_set".into() } else { "__index_get".into() },
                    generic_params: vec![],
                    return_type: ty,
                    parameters,
                    external: false,
                    body: Some(body),
                    is_static,
                    is_indexer: true,
                });
            }
        }
    }

    let name = match identifier(input) {
        Ok(n) => n,
        Err(e) => {
            *input = before;
            return Err(e);
        }
    };
    ws(input)?;

    if input.starts_with('(') {
        // `name(params) [: type] { body }`
        let mut f = named_function(input, name)?;
        f.is_static = is_static;
        return Ok(f);
    }

    // `ReturnType name(params) { body }` — the method name may be an overloadable
    // operator, and the return type may carry generic arguments (`__ptr<char> c_str()`).
    let mut after: &str = before;
    if let Ok(ty) = type_name_base(&mut after) {
        ws(&mut after)?;
        let name_ok = !after.is_empty()
            && (after.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')
                || OPERATORS.iter().any(|op| after.starts_with(op)));
        if name_ok {
            let mname = match identifier(&mut after) {
                Ok(n) => n,
                Err(_) => operator_name(&mut after)?,
            };
            ws(&mut after)?;
            let parameters = if after.starts_with('(') {
                function_parameters(&mut after)?
            } else {
                vec![]
            };
            ws(&mut after)?;
            let body = block(&mut after)?;
            ws(&mut after)?;
            *input = after;
            return Ok(FunctionDecl {
                name: mname,
                generic_params: vec![],
                return_type: ty,
                parameters,
                external: false,
                body: Some(body),
                is_static,
                is_indexer: false,
            });
        }
    }

    *input = before;
    Err(bt(input))
}

/// A trait method: like `struct_method` but the body is optional (`int getX();`).
fn trait_method(input: &mut &str) -> Result<FunctionDecl> {
    ws(input)?;
    let is_static = if input.starts_with("static") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[6..];
        ws(input)?;
        true
    } else {
        false
    };

    let before = *input;
    let first = match identifier(input) {
        Ok(n) => n,
        Err(e) => {
            *input = before;
            return Err(e);
        }
    };
    ws(input)?;

    fn optional_body(input: &mut &str) -> Result<Option<Block>> {
        if input.starts_with('{') {
            let b = block(input)?;
            ws(input)?;
            return Ok(Some(b));
        }
        if input.starts_with(';') {
            *input = &input[1..];
            ws(input)?;
            return Ok(None);
        }
        Err(cut(input))
    }

    if input.starts_with('(') {
        let parameters = function_parameters(input)?;
        ws(input)?;
        // optional return-type annotation: `name(params): Type` (lexy `[: type]`)
        let mut return_type = TypeName::auto();
        if input.starts_with(':') {
            *input = &input[1..];
            ws(input)?;
            return_type = type_name(input)?;
            ws(input)?;
        }
        let body = optional_body(input)?;
        return Ok(FunctionDecl {
            name: first,
            generic_params: vec![],
            return_type,
            parameters,
            external: false,
            body,
            is_static,
            is_indexer: false,
        });
    }

    let name_ok = input.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')
        || OPERATORS.iter().any(|op| input.starts_with(op));
    if name_ok {
        let return_type = TypeName { name: first, generic_types: vec![] };
        let name = match identifier(input) {
            Ok(n) => n,
            Err(_) => operator_name(input)?,
        };
        ws(input)?;
        let parameters = if input.starts_with('(') {
            function_parameters(input)?
        } else {
            vec![]
        };
        ws(input)?;
        let body = optional_body(input)?;
        return Ok(FunctionDecl {
            name,
            generic_params: vec![],
            return_type,
            parameters,
            external: false,
            body,
            is_static,
            is_indexer: false,
        });
    }

    *input = before;
    Err(bt(input))
}

/// `trait Name[<params>] { methods }`
fn trait_declaration(input: &mut &str) -> Result<TraitDecl> {
    if !input.starts_with("trait") || input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[5..];
    ws(input)?;
    let name = identifier(input)?;
    ws(input)?;
    let generic_params = if input.starts_with('<') {
        generic_params(input)?
    } else {
        vec![]
    };
    ws(input)?;
    if !input.starts_with('{') { return Err(cut(input)); }
    *input = &input[1..];

    let mut methods = vec![];
    loop {
        ws(input)?;
        if input.is_empty() || input.starts_with('}') { break; }
        if input.starts_with(';') {
            *input = &input[1..];
            continue;
        }
        methods.push(trait_method(input)?);
        ws(input)?;
        if input.starts_with(';') {
            *input = &input[1..];
        }
    }
    ws(input)?;
    if !input.starts_with('}') { return Err(cut(input)); }
    *input = &input[1..];

    Ok(TraitDecl { name, generic_params, methods })
}

/// `extend TypeName[<...>] [with Trait, ...] { methods }`
fn extend_declaration(input: &mut &str) -> Result<ExtendDecl> {
    if !input.starts_with("extend") || input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[6..];
    ws(input)?;
    let target = type_name(input)?;
    ws(input)?;

    let mut traits = vec![];
    if input.starts_with("with") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[4..];
        loop {
            ws(input)?;
            traits.push(type_name(input)?);
            ws(input)?;
            if input.starts_with(',') {
                *input = &input[1..];
                continue;
            }
            break;
        }
    }
    ws(input)?;
    if !input.starts_with('{') { return Err(cut(input)); }
    *input = &input[1..];

    let mut methods = vec![];
    loop {
        ws(input)?;
        if input.is_empty() || input.starts_with('}') { break; }
        if input.starts_with(';') {
            *input = &input[1..];
            continue;
        }
        methods.push(struct_method(input)?);
        ws(input)?;
        if input.starts_with(';') {
            *input = &input[1..];
        }
    }
    ws(input)?;
    if !input.starts_with('}') { return Err(cut(input)); }
    *input = &input[1..];

    Ok(ExtendDecl { target, traits, methods })
}

fn struct_declaration(input: &mut &str) -> Result<StructDecl> {
    if !input.starts_with("struct") || input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[6..];
    ws(input)?;

    let name = identifier(input)?;
    ws(input)?;

    let generic_params = if input.starts_with('<') {
        generic_params(input)?
    } else {
        vec![]
    };
    ws(input)?;

    if !input.starts_with('{') { return Err(cut(input)); }
    *input = &input[1..];

    let mut fields = vec![];
    let mut methods = vec![];
    let mut constructor = None;
    let mut destructor = None;

    loop {
        ws(input)?;
        if input.is_empty() || input.starts_with('}') { break; }
        if input.starts_with(';') {
            *input = &input[1..];
            continue;
        }

        // constructor: `new(params) { ... }` (docs also call this `construct`)
        if (input.starts_with("new") && !input[3..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_'))
            || (input.starts_with("construct") && !input[9..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_')) {
            *input = if input.starts_with("construct") { &input[9..] } else { &input[3..] };
            ws(input)?;
            if !input.starts_with('(') { return Err(cut(input)); }
            *input = &input[1..];
            let mut parameters = vec![];
            loop {
                ws(input)?;
                if input.starts_with(')') { break; }
                parameters.push(constructor_parameter(input)?);
                ws(input)?;
                if input.starts_with(',') {
                    *input = &input[1..];
                    continue;
                }
                if !input.starts_with(')') { return Err(cut(input)); }
                break;
            }
            *input = &input[1..];
            ws(input)?;
            let body = block(input)?;
            ws(input)?;
            constructor = Some(FunctionDecl {
                name: "new".into(),
                generic_params: vec![],
                return_type: TypeName::auto(),
                parameters,
                external: false,
                body: Some(body),
                is_static: false,
                is_indexer: false,
            });
            continue;
        }

        // destructor: `destruct { ... }`
        if input.starts_with("destruct") && !input[8..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
            *input = &input[8..];
            ws(input)?;
            destructor = Some(block(input)?);
            ws(input)?;
            continue;
        }

        if input.starts_with("extern") {
            let m = extern_function_declaration(input)?;
            ws(input)?;
            methods.push(m);
            continue;
        }

        let before = *input;
        if let Ok(m) = struct_method(input) {
            ws(input)?;
            methods.push(m);
            if input.starts_with(';') {
                *input = &input[1..];
            }
            continue;
        }
        *input = before;

        let f = variable_declaration(input)?;
        ws(input)?;
        if !decl_boundary(input) {
            *input = before;
            return Err(bt(input));
        }
        fields.push(f);
        if input.starts_with(';') {
            *input = &input[1..];
        }
    }

    ws(input)?;
    if !input.starts_with('}') { return Err(cut(input)); }
    *input = &input[1..];

    Ok(StructDecl { name, generic_params, fields, methods, constructor, destructor })
}

fn declaration(input: &mut &str) -> Result<Declaration> {
    ws(input)?;

    if input.starts_with("struct") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Declaration::Struct(struct_declaration(input)?));
    }
    if input.starts_with("trait") && !input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Declaration::Trait(trait_declaration(input)?));
    }
    if input.starts_with("extend") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Declaration::Extend(extend_declaration(input)?));
    }
    if input.starts_with("extern") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Declaration::Function(extern_function_declaration(input)?));
    }
    let before = *input;
    if let Ok(f) = function_declaration(input) {
        return Ok(Declaration::Function(f));
    }
    *input = before;

    let v = variable_declaration(input)?;
    if !decl_boundary(input) {
        return Err(bt(input));
    }
    Ok(Declaration::Variable(v))
}

// ── Imports ───────────────────────────────────────────────────────────────────

fn import(input: &mut &str) -> Result<Import> {
    ws(input)?;

    if input.starts_with("import") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[6..];
    } else if input.starts_with("use") && !input[3..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[3..];
    } else {
        return Err(bt(input));
    }
    ws(input)?;

    let (name, is_local) = if input.starts_with('"') {
        let lit = string_constant(input)?;
        if let Literal::String(s) = lit { (s, true) }
        else { return Err(cut(input)); }
    } else {
        (identifier(input)?, false)
    };
    ws(input)?;

    let alias = if input.starts_with("as") && !input[2..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[2..];
        ws(input)?;
        Some(identifier(input)?)
    } else {
        None
    };

    Ok(Import { name, alias, is_local })
}

// ── Module ────────────────────────────────────────────────────────────────────

/// Parse a complete Pepper source file into a `Module` AST.
pub fn parse_module(input: &mut &str) -> Result<Module> {
    ws(input)?;

    let mut imports = vec![];
    let mut declarations = vec![];
    loop {
        ws(input)?;
        if input.is_empty() { break; }

        // imports may appear between declarations
        if input.starts_with("import") || input.starts_with("use") {
            let before = *input;
            match import(input) {
                Ok(imp) => {
                    ws(input)?;
                    if input.starts_with(';') { *input = &input[1..]; }
                    imports.push(imp);
                    continue;
                }
                Err(_) => { *input = before; }
            }
        }

        let decl = declaration(input)?;
        ws(input)?;
        if input.starts_with(';') { *input = &input[1..]; }
        declarations.push(decl);
    }

    // The entire input must have been consumed; a partial parse is an error.
    ws(input)?;
    if !input.is_empty() {
        return Err(cut(input));
    }

    Ok(Module { imports, declarations })
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(s: &str) -> Module {
        let mut input = s;
        parse_module(&mut input).expect("parse should succeed")
    }

    fn parse_expr(s: &str) -> Expression {
        let mut input = s;
        expression(&mut input).expect("expression parse should succeed")
    }

    // ── Literals ──

    #[test]
    fn test_int_literal() {
        let e = parse_expr("42");
        match e {
            Expression::Literal(Literal::Integer(42)) => {}
            other => panic!("expected int 42, got {:?}", other),
        }
    }

    #[test]
    fn test_negative_int() {
        let e = parse_expr("-7");
        match e {
            Expression::Unary { op, prefix, operand } => {
                assert_eq!(op, "-");
                assert!(prefix);
                match *operand {
                    Expression::Literal(Literal::Integer(7)) => {}
                    other => panic!("expected 7, got {:?}", other),
                }
            }
            other => panic!("expected unary, got {:?}", other),
        }
    }

    #[test]
    fn test_float_literal() {
        let e = parse_expr("3.14");
        match e {
            Expression::Literal(Literal::Float(v)) => assert!((v - 3.14).abs() < 1e-9),
            other => panic!("expected float, got {:?}", other),
        }
    }

    #[test]
    fn test_bool_literals() {
        match parse_expr("true") {
            Expression::Literal(Literal::Bool(true)) => {}
            other => panic!("expected true, got {:?}", other),
        }
        match parse_expr("false") {
            Expression::Literal(Literal::Bool(false)) => {}
            other => panic!("expected false, got {:?}", other),
        }
    }

    #[test]
    fn test_string_literal() {
        let e = parse_expr("\"hello world\"");
        match e {
            Expression::Literal(Literal::String(s)) => assert_eq!(s, "hello world"),
            other => panic!("expected string, got {:?}", other),
        }
    }


    // ── Identifiers & refs ──

    #[test]
    fn test_symbol_ref() {
        let e = parse_expr("my_var");
        match e {
            Expression::SymbolRef(name) => assert_eq!(name, "my_var"),
            other => panic!("expected symbol ref, got {:?}", other),
        }
    }

    // ── Binary operators ──

    #[test]
    fn test_addition() {
        let e = parse_expr("1 + 2");
        match e {
            Expression::Binary { lhs, op, rhs } => {
                assert_eq!(op, "+");
                match *lhs { Expression::Literal(Literal::Integer(1)) => {}, o => panic!("{:?}", o) }
                match *rhs { Expression::Literal(Literal::Integer(2)) => {}, o => panic!("{:?}", o) }
            }
            other => panic!("expected binary +, got {:?}", other),
        }
    }

    #[test]
    fn test_precedence_mul_before_add() {
        // 1 + 2 * 3 should parse as 1 + (2 * 3), not (1 + 2) * 3
        let e = parse_expr("1 + 2 * 3");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "+", "top-level should be +"),
            other => panic!("expected binary, got {:?}", other),
        }
    }

    #[test]
    fn test_powers_right_assoc() {
        // 2 ** 3 ** 2 should parse as 2 ** (3 ** 2)
        let e = parse_expr("2 ** 3 ** 2");
        match e {
            Expression::Binary { op, rhs, .. } => {
                assert_eq!(op, "**");
                match *rhs {
                    Expression::Binary { op: inner_op, .. } => assert_eq!(inner_op, "**"),
                    other => panic!("expected nested **, got {:?}", other),
                }
            }
            other => panic!("expected **, got {:?}", other),
        }
    }

    #[test]
    fn test_comparison_ops() {
        for (src, expected_op) in [
            ("a == b", "=="),
            ("a != b", "!="),
            ("a < b", "<"),
            ("a > b", ">"),
            ("a <= b", "<="),
            ("a >= b", ">="),
        ] {
            let e = parse_expr(src);
            match e {
                Expression::Binary { op, .. } => assert_eq!(op, expected_op, "for src={}", src),
                other => panic!("expected binary {} for {}, got {:?}", expected_op, src, other),
            }
        }
    }

    #[test]
    fn test_logical_ops() {
        for (src, expected_op) in [
            ("a && b", "&&"),
            ("a || b", "||"),
            ("a and b", "and"),
            ("a or b", "or"),
        ] {
            let e = parse_expr(src);
            match e {
                Expression::Binary { op, .. } => assert_eq!(op, expected_op, "for src={}", src),
                other => panic!("expected binary {} for {}, got {:?}", expected_op, src, other),
            }
        }
    }

    // ── Assignment ──

    #[test]
    fn test_assignment() {
        let e = parse_expr("x = 42");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "="),
            other => panic!("expected =, got {:?}", other),
        }
    }

    #[test]
    fn test_compound_assignment() {
        for (src, expected_op) in [
            ("x += 1", "+="),
            ("x -= 1", "-="),
            ("x *= 2", "*="),
            ("x /= 2", "/="),
            ("x <<= 1", "<<="),
            ("x >>= 1", ">>="),
            ("x &= 1", "&="),
            ("x |= 1", "|="),
            ("x ^= 1", "^="),
        ] {
            let e = parse_expr(src);
            match e {
                Expression::Binary { op, .. } => assert_eq!(op, expected_op, "for src={}", src),
                other => panic!("expected {} for {}, got {:?}", expected_op, src, other),
            }
        }
    }

    #[test]
    fn test_shift_ops() {
        for (src, expected_op) in [("a << 2", "<<"), ("a >> 2", ">>"), ("a << b << c", "<<")] {
            let e = parse_expr(src);
            match e {
                Expression::Binary { op, .. } => assert_eq!(op, expected_op, "for src={}", src),
                other => panic!("expected {} for {}, got {:?}", expected_op, src, other),
            }
        }
    }

    #[test]
    fn test_shift_precedence() {
        // `a << b + c` binds `b + c` first
        let e = parse_expr("a << b + c");
        match e {
            Expression::Binary { op, rhs, .. } => {
                assert_eq!(op, "<<");
                match *rhs {
                    Expression::Binary { op, .. } => assert_eq!(op, "+"),
                    other => panic!("expected add in rhs, got {:?}", other),
                }
            }
            other => panic!("expected shift, got {:?}", other),
        }
    }

    #[test]
    fn test_compound_vs_binary_minus() {
        // `a - 1` must stay a binary minus, not trip over `-=` handling
        let e = parse_expr("a - 1");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "-"),
            other => panic!("expected binary minus, got {:?}", other),
        }
        // `a - -b` is binary minus applied to unary minus
        let e = parse_expr("a - -b");
        match e {
            Expression::Binary { op, rhs, .. } => {
                assert_eq!(op, "-");
                match *rhs {
                    Expression::Unary { .. } => {}
                    other => panic!("expected unary in rhs, got {:?}", other),
                }
            }
            other => panic!("expected binary minus, got {:?}", other),
        }
    }

    // ── Ternary ──

    #[test]
    fn test_ternary() {
        let e = parse_expr("a ? b : c");
        match e {
            Expression::Ternary { .. } => {}
            other => panic!("expected ternary, got {:?}", other),
        }
    }

    // ── Member access & indexing ──

    #[test]
    fn test_member_access() {
        let e = parse_expr("obj.field");
        match e {
            Expression::MemberAccess { name, .. } => assert_eq!(name, "field"),
            other => panic!("expected member access, got {:?}", other),
        }
    }

    #[test]
    fn test_index() {
        let e = parse_expr("arr[0]");
        match e {
            Expression::Index { .. } => {}
            other => panic!("expected index, got {:?}", other),
        }
    }

    // ── Function calls ──

    #[test]
    fn test_function_call_no_args() {
        let e = parse_expr("foo()");
        match e {
            Expression::FunctionCall { function, arguments } => {
                assert!(arguments.is_empty());
                match *function {
                    Expression::SymbolRef(n) => assert_eq!(n, "foo"),
                    other => panic!("{:?}", other),
                }
            }
            other => panic!("expected call, got {:?}", other),
        }
    }

    #[test]
    fn test_function_call_with_args() {
        let e = parse_expr("foo(1, 2, 3)");
        match e {
            Expression::FunctionCall { arguments, .. } => assert_eq!(arguments.len(), 3),
            other => panic!("expected call, got {:?}", other),
        }
    }

    // ── Parentheses ──

    #[test]
    fn test_parenthesized_expr() {
        let e = parse_expr("(1 + 2) * 3");
        // Top-level should be * (multiplication), not +
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "*"),
            other => panic!("expected *, got {:?}", other),
        }
    }

    // ── sizeof ──

    #[test]
    fn test_sizeof() {
        let e = parse_expr("sizeof<int>");
        match e {
            Expression::SizeOf(ty) => assert_eq!(ty.name, "int"),
            other => panic!("expected sizeof, got {:?}", other),
        }
    }

    #[test]
    fn test_sizeof_with_parens() {
        // Both `sizeof<T>` and `sizeof<T>()` must parse to a `SizeOf` node.
        let e = parse_expr("sizeof<int>()");
        match e {
            Expression::SizeOf(ty) => assert_eq!(ty.name, "int"),
            other => panic!("expected sizeof, got {:?}", other),
        }
        // `sizeof<T>()` inside a larger expression
        let e = parse_expr("malloc(4 * sizeof<int>())");
        match e {
            Expression::FunctionCall { .. } => {}
            other => panic!("expected call, got {:?}", other),
        }
    }

    // ── Type names ──

    #[test]
    fn test_type_name_simple() {
        let mut input = "int";
        let ty = type_name(&mut input).unwrap();
        assert_eq!(ty.name, "int");
        assert!(ty.generic_types.is_empty());
    }

    #[test]
    fn test_type_name_generic() {
        let mut input = "array<int>";
        let ty = type_name(&mut input).unwrap();
        assert_eq!(ty.name, "array");
        assert_eq!(ty.generic_types.len(), 1);
        assert_eq!(ty.generic_types[0].name, "int");
    }

    #[test]
    fn test_type_name_array() {
        let mut input = "int[]";
        let ty = type_name(&mut input).unwrap();
        assert_eq!(ty.name, "int[]");
    }

    // ── Variable declarations ──

    #[test]
    fn test_var_declaration() {
        let mut input = "var x: int = 42";
        let decl = variable_declaration(&mut input).unwrap();
        assert_eq!(decl.name, "x");
        assert_eq!(decl.type_name.name, "int");
        assert!(!decl.is_const);
        assert!(decl.default_value.is_some());
    }

    #[test]
    fn test_const_declaration() {
        let mut input = "const MAX = 100";
        let decl = variable_declaration(&mut input).unwrap();
        assert_eq!(decl.name, "MAX");
        assert!(decl.is_const);
    }

    #[test]
    fn test_type_name_declaration() {
        let mut input = "int count = 0";
        let decl = variable_declaration(&mut input).unwrap();
        assert_eq!(decl.name, "count");
        assert_eq!(decl.type_name.name, "int");
    }

    // ── Modules ──

    #[test]
    fn test_module_with_import() {
        let m = parse("import \"test\";\nfoo() {}");
        assert_eq!(m.imports.len(), 1);
        assert!(m.imports[0].is_local);
        assert_eq!(m.imports[0].name, "test");
    }

    #[test]
    fn test_module_with_package_import() {
        let m = parse("import mylib;\nfoo() {}");
        assert_eq!(m.imports.len(), 1);
        assert!(!m.imports[0].is_local);
        assert_eq!(m.imports[0].name, "mylib");
    }

    #[test]
    fn test_module_with_import_alias() {
        let m = parse("import mylib as m;\nfoo() {}");
        assert_eq!(m.imports.len(), 1);
        assert_eq!(m.imports[0].alias.as_deref(), Some("m"));
    }

    #[test]
    fn test_module_function() {
        let m = parse("main(): int {\n    return 42;\n}");
        assert_eq!(m.declarations.len(), 1);
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert_eq!(f.name, "main");
                assert_eq!(f.return_type.name, "int");
            }
            other => panic!("expected function, got {:?}", other),
        }
    }

    #[test]
    fn test_module_struct() {
        let m = parse("struct Point {\n    int x = 0;\n    int y = 0;\n}");
        assert_eq!(m.declarations.len(), 1);
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.name, "Point");
                assert_eq!(s.fields.len(), 2);
            }
            other => panic!("expected struct, got {:?}", other),
        }
    }

    #[test]
    fn test_module_struct_generic() {
        let m = parse("struct Pair<A, B> {\n    A first;\n    B second;\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.name, "Pair");
                assert_eq!(s.generic_params.len(), 2);
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_module_comments() {
        let src = "# this is a comment\nfoo() {} # another comment\n";
        let m = parse(src);
        assert_eq!(m.declarations.len(), 1);
    }

    #[test]
    fn test_extern_function() {
        let m = parse("extern int my_func(int a, int b);");
        assert_eq!(m.declarations.len(), 1);
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert!(f.external);
                assert_eq!(f.name, "my_func");
                assert_eq!(f.parameters.len(), 2);
            }
            other => panic!("{:?}", other),
        }
    }

    // ── Statements ──

    #[test]
    fn test_if_else() {
        let mut input = "if x > 0 {\n    y = 1;\n} else {\n    y = 2;\n}";
        let stmt = statement(&mut input).unwrap();
        match stmt {
            Statement::Branch(b) => {
                assert!(b.else_block.is_some());
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_while_loop() {
        let mut input = "while i < 10 {\n    i += 1;\n}";
        let stmt = statement(&mut input).unwrap();
        match stmt {
            Statement::While(_) => {}
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_return_statement() {
        let mut input = "return 42;";
        let stmt = statement(&mut input).unwrap();
        match stmt {
            Statement::Return(r) => {
                match r.expr {
                    Expression::Literal(Literal::Integer(42)) => {}
                    other => panic!("{:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_expression_statement() {
        let mut input = "print(\"hello\");";
        let stmt = statement(&mut input).unwrap();
        match stmt {
            Statement::Expression(e) => {
                match e {
                    Expression::FunctionCall { .. } => {}
                    other => panic!("{:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    // ── Struct features: constructors, destructors, static, indexers, operator overloads ──

    #[test]
    fn test_constructor_with_this_initializers() {
        let m = parse("struct S {\n    int x;\n    new(this.x = 0) {\n        x += 1;\n    }\n    destruct {\n        x = 0;\n    }\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.name, "S");
                let c = s.constructor.as_ref().expect("constructor");
                assert_eq!(c.name, "new");
                assert_eq!(c.parameters.len(), 1);
                assert_eq!(c.parameters[0].name, "this.x");
                assert!(c.parameters[0].default_value.is_some());
                assert!(s.destructor.is_some());
                assert_eq!(s.destructor.as_ref().unwrap().statements.len(), 1);
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_construct_alias() {
        // docs spell the constructor `construct`; both must be accepted
        let m = parse("struct S {\n    int x;\n    construct(this.x = 1) {}\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => assert!(s.constructor.is_some()),
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_static_and_indexer_methods() {
        let m = parse("struct S {\n    static helper(int v): int {\n        return v;\n    }\n    int [](int i) {\n        return i;\n    }\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.methods.len(), 2);
                assert!(s.methods[0].is_static);
                assert_eq!(s.methods[0].name, "helper");
                assert!(!s.methods[1].is_static);
                assert!(s.methods[1].is_indexer);
                assert_eq!(s.methods[1].name, "__index_get");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_operator_named_methods() {
        let m = parse("struct S {\n    int v;\n    bool ==(int o) {\n        return o;\n    }\n    S +=(int o) {\n        v += o;\n        return v;\n    }\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.methods.len(), 2);
                assert_eq!(s.methods[0].name, "==");
                assert_eq!(s.methods[1].name, "+=");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_null_literal() {
        let e = parse_expr("x = __null");
        match e {
            Expression::Binary { rhs, .. } => match *rhs {
                Expression::Literal(Literal::Null) => {}
                other => panic!("{:?}", other),
            },
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_identity_operator() {
        let e = parse_expr("a === b");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "==="),
            other => panic!("{:?}", other),
        }
        // `a == b` must not swallow a third `=` and vice versa
        let e = parse_expr("a == b");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "=="),
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_trait_and_extend() {
        let m = parse("trait XGetter {\n    getX(): int;\n}\nstruct Test {\n    int x;\n}\nextend Test with XGetter {\n    getX(): int {\n        return x;\n    }\n}");
        assert_eq!(m.declarations.len(), 3);
        match &m.declarations[0] {
            Declaration::Trait(t) => {
                assert_eq!(t.name, "XGetter");
                assert_eq!(t.methods.len(), 1);
                assert!(t.methods[0].body.is_none());
            }
            other => panic!("{:?}", other),
        }
        match &m.declarations[2] {
            Declaration::Extend(e) => {
                assert_eq!(e.target.name, "Test");
                assert_eq!(e.traits.len(), 1);
                assert_eq!(e.traits[0].name, "XGetter");
                assert_eq!(e.methods.len(), 1);
                assert!(e.methods[0].body.is_some());
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_generic_constructor_call() {
        // `array<int>()` is a type-literal call with generic argument
        let e = parse_expr("array<int>()");
        match e {
            Expression::FunctionCall { function, arguments } => {
                assert!(arguments.is_empty());
                match *function {
                    Expression::TypeLiteral(t) => {
                        assert_eq!(t.name, "array");
                        assert_eq!(t.generic_types.len(), 1);
                        assert_eq!(t.generic_types[0].name, "int");
                    }
                    other => panic!("{:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_extern_pointer_params() {
        let m = parse("extern int strncmp(char* a, char* b, uint n)");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert!(f.external);
                assert!(f.body.is_none());
                assert_eq!(f.parameters.len(), 3);
                assert_eq!(f.parameters[0].type_name.name, "char*");
                assert_eq!(f.parameters[1].type_name.name, "char*");
                assert_eq!(f.parameters[2].type_name.name, "uint");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_parse_rejects_garbage() {
        // `parse_module` must fail loudly instead of skipping over bad tokens
        let bad_sources = [
            "int x = 1 junk leftover",
            "struct S { int x = }",
            "int x = ;",
            "while { }",
        ];
        for src in bad_sources {
            let mut input = src;
            assert!(parse_module(&mut input).is_err(), "should reject: {}", src);
        }
        // and a valid program must still succeed
        let mut input = "int x = 1;";
        assert!(parse_module(&mut input).is_ok());
    }
}

