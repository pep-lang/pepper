# Formatters for Pepper's runtime types, for lldb. Load them with
#
#     (lldb) command script import <runtime>/debuggers/lldb_formatters.py
#
# or put that line in ~/.lldbinit. A variable of a struct type holds a
# reference, a pointer to the object, so each formatter accepts the
# reference as well as the object. Each shows the object's reference counts
# first, as `[ref count]` (strong references) and `[weak count]`. An
# Optional is a value, held inline, with no counts. Any other enum with
# payloads shows its case and that case's values.

import lldb

COUNTS = [("[ref count]", "__refcount"), ("[weak count]", "__weakcount")]


def _object(value):
    """The object `value` refers to, or None for a null reference: its raw
    fields, not the children a synthetic provider gives it."""
    value = value.GetNonSyntheticValue()
    if value.GetType().IsPointerType():
        if value.GetValueAsUnsigned() == 0:
            return None
        value = value.Dereference()
    return value.GetNonSyntheticValue()


def _renamed(field, name):
    """A copy of the value `field` under `name`."""
    return field.CreateValueFromData(name, field.GetData(), field.GetType())


class _Children:
    """The reference counts, then what `extra_count` and `extra_child`
    give a subclass, as an object's children."""

    def __init__(self, value, internal_dict):
        self.value = value
        self.update()

    def update(self):
        self.object = _object(self.value)
        return False

    def extra_count(self):
        return 0

    def extra_child(self, index):
        return None

    def extra_index(self, name):
        return -1

    def num_children(self):
        if self.object is None:
            return 0
        return len(COUNTS) + self.extra_count()

    def get_child_index(self, name):
        for index, (shown, _) in enumerate(COUNTS):
            if name == shown:
                return index
        extra = self.extra_index(name)
        return -1 if extra < 0 else len(COUNTS) + extra

    def get_child_at_index(self, index):
        if self.object is None or index < 0:
            return None
        if index < len(COUNTS):
            shown, field = COUNTS[index]
            return _renamed(self.object.GetChildMemberWithName(field), shown)
        return self.extra_child(index - len(COUNTS))

    def has_children(self):
        return self.object is not None


class StringChildren(_Children):
    """A String's reference counts."""


def string_summary(value, internal_dict):
    """A String as its quoted text."""
    string = _object(value)
    if string is None:
        return "null"
    size = string.GetChildMemberWithName("_size").GetValueAsUnsigned()
    data = string.GetChildMemberWithName("_data").GetValueAsUnsigned()
    if data == 0 or size == 0:
        return '""'
    error = lldb.SBError()
    text = value.GetProcess().ReadMemory(data, size, error)
    if not error.Success():
        return "<unreadable: %s>" % error.GetCString()
    return '"%s"' % text.decode("utf-8", "replace").replace("\\", "\\\\").replace('"', '\\"')


class ArrayChildren(_Children):
    """An Array's reference counts, then its elements."""

    def update(self):
        super().update()
        self.count = 0
        if self.object is not None:
            self.count = self.object.GetChildMemberWithName("_size").GetValueAsUnsigned()
            self.data = self.object.GetChildMemberWithName("_data")
            self.element = self.data.GetType().GetPointeeType()
        return False

    def extra_count(self):
        return self.count

    def extra_index(self, name):
        try:
            return int(name.lstrip("[").rstrip("]"))
        except ValueError:
            return -1

    def extra_child(self, index):
        if index >= self.count:
            return None
        address = self.data.GetValueAsUnsigned() + index * self.element.GetByteSize()
        return self.value.CreateValueFromAddress("[%d]" % index, address, self.element)


def array_summary(value, internal_dict):
    """An Array as its count."""
    array = _object(value)
    # An empty Array is null until something is added to it.
    if array is None:
        return "count=0"
    return "count=%d" % array.GetChildMemberWithName("_size").GetValueAsUnsigned()


class OptionalChildren:
    """A Value optional's value. An Optional is a value enum, held inline:
    its `__tag` is the case's position, and `Value__value` holds a Value's
    value."""

    def __init__(self, value, internal_dict):
        self.value = value
        self.update()

    def update(self):
        self.has = _has_value(self.value)
        return False

    def num_children(self):
        return 1 if self.has else 0

    def get_child_index(self, name):
        return 0 if name == "value" else -1

    def get_child_at_index(self, index):
        if index != 0 or not self.has:
            return None
        return _renamed(self.value.GetNonSyntheticValue().GetChildMemberWithName("Value__value"), "value")

    def has_children(self):
        return self.has


def _has_value(optional):
    """Whether `optional` is a Value optional, not Empty."""
    return optional.GetNonSyntheticValue().GetChildMemberWithName("__tag").GetValueAsUnsigned() == 1


def optional_summary(value, internal_dict):
    """An Optional as its case, `Empty` or `Value`."""
    return "Value" if _has_value(value) else "Empty"


def _enum_object(value):
    """The object of an enum with payloads, or None for a null reference."""
    return _object(value)


def _enum_case(object):
    """The case of an enum with payloads: its `__tag`'s enumerator."""
    return object.GetChildMemberWithName("__tag").GetValue()


def is_enum(sbtype, internal_dict):
    """Whether `sbtype`, or what it points to, is an enum with payloads: a
    struct whose `__tag` is an enumeration of its cases."""
    if sbtype.IsPointerType():
        sbtype = sbtype.GetPointeeType()
    for index in range(sbtype.GetNumberOfFields()):
        field = sbtype.GetFieldAtIndex(index)
        if field.GetName() == "__tag":
            return field.GetType().GetCanonicalType().GetTypeClass() == lldb.eTypeClassEnumeration
    return False


def enum_summary(value, internal_dict):
    """An enum with payloads as its case."""
    object = _enum_object(value)
    if object is None:
        return "null"
    return _enum_case(object)


class EnumChildren:
    """The counts of a reference enum with payloads, then its case's values:
    the payload field `value` of the case `Rect` is the member
    `Rect__value`."""

    def __init__(self, value, internal_dict):
        self.value = value
        self.update()

    def update(self):
        self.children = []
        object = _enum_object(self.value)
        if object is None:
            return False
        names = [object.GetChildAtIndex(index).GetName() for index in range(object.GetNumChildren())]
        if "__refcount" in names:
            for label, field in COUNTS:
                self.children.append(_renamed(object.GetChildMemberWithName(field), label))
        prefix = _enum_case(object) + "__"
        for name in names:
            if name.startswith(prefix):
                self.children.append(_renamed(object.GetChildMemberWithName(name), name[len(prefix):]))
        return False

    def num_children(self):
        return len(self.children)

    def get_child_index(self, name):
        for index, child in enumerate(self.children):
            if child.GetName() == name:
                return index
        return -1

    def get_child_at_index(self, index):
        return self.children[index] if 0 <= index < len(self.children) else None

    def has_children(self):
        return len(self.children) > 0


def __lldb_init_module(debugger, internal_dict):
    for pattern, summary, children in [
        ("^String$", "string_summary", "StringChildren"),
        ("^Array<.+>$", "array_summary", "ArrayChildren"),
        ("^Optional<.+>$", "optional_summary", "OptionalChildren"),
    ]:
        # `--expand` shows the children beside the summary.
        debugger.HandleCommand('type summary add -x "%s" -F %s.%s -w pepper --expand' % (pattern, __name__, summary))
        debugger.HandleCommand('type synthetic add -x "%s" -l %s.%s -w pepper' % (pattern, __name__, children))
    # Any other enum with payloads, recognized by its `__tag` (lldb 16 and
    # later).
    debugger.HandleCommand(
        "type summary add --recognizer-function -F %s.enum_summary -w pepper --expand %s.is_enum" % (__name__, __name__)
    )
    debugger.HandleCommand(
        "type synthetic add --recognizer-function -l %s.EnumChildren -w pepper %s.is_enum" % (__name__, __name__)
    )
    debugger.HandleCommand("type category enable pepper")
