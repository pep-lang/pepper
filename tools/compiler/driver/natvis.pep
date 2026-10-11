## Visualizers for a program's enums with payloads, for Visual Studio and
## WinDbg. The runtime's `pepper.natvis` covers its own types by name, but
## no natvis pattern matches every enum, so a `-g` build on Windows writes
## one entry per enum of the program and links it into the `.pdb` beside
## the runtime's (`link_objects`). gdb and lldb need none: their formatters
## (`runtime/debuggers/`) recognize an enum by its `__tag`, an enumeration
## of its cases (`codegen/debug_types.pep`).

import compiler.sema;

## The natvis file of `module`'s enums with payloads: each shows its case
## and that case's values (the payload field `width` of the case `Rect` is
## the member `Rect__width`), after a reference enum's counts.
##
## @param module the checked program
## @returns the file's text
export enum_natvis(module: sema.Module): String {
    var out = StringBuilder();
    out.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    out.append("<AutoVisualizer xmlns=\"http://schemas.microsoft.com/vstudio/debugger/natvis/2010\">\n");
    for (var st in module.structs) {
        if (!st.enum_cases.is_value()) {
            continue;
        }
        var shown = sema.display_name(sema.parse_type_string(st.name).display());
        # The runtime's `pepper.natvis` shows Optional.
        if (shown.starts_with("Optional<")) {
            continue;
        }
        out.append("  <Type Name=\"" + _xml(shown) + "\">\n");
        var items = StringBuilder();
        for (var c in st.enum_cases.value()) {
            var condition = "(int)__tag == " + $"{c.value}";
            var values = Array<String>();
            for (var (field, _) in c.payload) {
                values.append(field + "={" + c.name + "__" + field + "}");
                items.append(
                    "      <Item Name=\""
                        + _xml(field)
                        + "\" Condition=\""
                        + _xml(condition)
                        + "\">"
                        + c.name
                        + "__"
                        + field
                        + "</Item>\n"
                );
            }
            var display = values.is_empty ? c.name : c.name + " {{ " + ", ".join(values) + " }}";
            out.append(
                "    <DisplayString Condition=\"" + _xml(condition) + "\">" + _xml(display) + "</DisplayString>\n"
            );
        }
        out.append("    <Expand>\n");
        out.append("      <Item Name=\"[ref count]\" Optional=\"true\">__refcount</Item>\n");
        out.append("      <Item Name=\"[weak count]\" Optional=\"true\">__weakcount</Item>\n");
        out.append(items.to_string());
        out.append("    </Expand>\n");
        out.append("  </Type>\n");
    }
    out.append("</AutoVisualizer>\n");
    return out.to_string();
}

# `text` with XML's special characters escaped.
_xml(text: String): String {
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
}
