<!-- Generated from runtime/regex/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# The regex module

Regular expressions: test whether text matches a pattern, find the
matches and their capture groups, and replace or split by a pattern.

Bring it in with `import regex`. The syntax is RE2's, and matching takes
time linear in the size of the text whatever the pattern.

- [Regex and Match](regex-regex.md): `Regex`, `Match`, `Matches`

**Example**
```pepper
    import regex;

    main(): int {
        var word = regex.Regex("\\b(\\w)(\\w*)\\b");
        assert(word.replace_all("hello big world", "${1}.") == "h. b. w.", "initials");
        return 0;
    }
```

Source: `runtime/regex/module.pep`
