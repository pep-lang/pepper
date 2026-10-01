<!-- Generated from runtime/math/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# math/module.pep

Numbers beyond the operators: parsing them from text for now, and the
rest of the math library as it grows.

Bring it in with `import math`.

- [Parsing](math-parse.md): `parse_int`

**Example**
```pepper
    import math;

    main(): int {
        var port = math.parse_int("8080");
        assert(port.is_some() && port.value() == 8080, "parsed");
        return 0;
    }
```

Source: `runtime/math/module.pep`
