# Pretty-printers for Pepper's runtime types, for gdb.
#
# A program built with `-g` on Linux carries this script in its
# `.debug_gdb_scripts` section, and gdb loads it when the program's
# directory is on its auto-load safe path:
#
#     gdb -iex "add-auto-load-safe-path ." ./main
#
# A variable of a struct type holds a reference, a pointer to the object,
# so each printer accepts the reference as well as the object. Each shows
# the object's reference counts first, as `[ref count]` (strong references)
# and `[weak count]`. An Optional is a value, held inline, with no counts.

import re

import gdb


def _object(value):
    """The object `value` refers to, or None for a null reference."""
    if value.type.strip_typedefs().code == gdb.TYPE_CODE_PTR:
        if int(value) == 0:
            return None
        return value.dereference()
    return value


def _counts(object):
    """The object's reference counts, as children."""
    if object is None:
        return
    yield "[ref count]", object["__refcount"]
    yield "[weak count]", object["__weakcount"]


class StringPrinter:
    """A String as its text."""

    def __init__(self, value, name):
        self.object = _object(value)

    def to_string(self):
        if self.object is None:
            return "null"
        data = self.object["_data"]
        if int(data) == 0:
            return '""'
        return data.lazy_string(encoding="utf-8", length=int(self.object["_size"]))

    def children(self):
        return _counts(self.object)


class ArrayPrinter:
    """An Array as its count and elements."""

    def __init__(self, value, name):
        self.object = _object(value)
        self.name = name

    def to_string(self):
        # An empty Array is null until something is added to it.
        if self.object is None:
            return "%s of count 0" % self.name
        return "%s of count %d" % (self.name, int(self.object["_size"]))

    def children(self):
        if self.object is None:
            return
        yield from _counts(self.object)
        data = self.object["_data"]
        for index in range(int(self.object["_size"])):
            yield "[%d]" % index, data[index]


class OptionalPrinter:
    """An Optional as its case, `Empty` or `Value`, and a Value's value.
    An Optional is a value enum, held inline: its `__tag` is the case's
    position, and `Value__value` holds a Value's value."""

    def __init__(self, value, name):
        self.value = value

    def _has_value(self):
        return int(self.value["__tag"]) == 1

    def to_string(self):
        return "Value" if self._has_value() else "Empty"

    def children(self):
        if self._has_value():
            yield "value", self.value["Value__value"]


_PRINTERS = [
    (re.compile(r"^String$"), StringPrinter),
    (re.compile(r"^Array<.*>$"), ArrayPrinter),
    (re.compile(r"^Optional<.*>$"), OptionalPrinter),
]


def _lookup(value):
    """The printer for `value`'s type: the object's, or a reference's."""
    type_ = value.type.strip_typedefs()
    if type_.code == gdb.TYPE_CODE_PTR:
        type_ = type_.target().strip_typedefs()
    name = type_.name or type_.tag
    if name is None:
        return None
    for pattern, printer in _PRINTERS:
        if pattern.match(name):
            return printer(value, name)
    return None


_objfile = gdb.current_objfile()
if _objfile is not None:
    _objfile.pretty_printers.append(_lookup)
else:
    gdb.pretty_printers.append(_lookup)
