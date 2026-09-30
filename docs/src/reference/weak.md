<!-- Generated from runtime/weak.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Weak

Weak references: `Weak<T>` points at an object without keeping it alive.

Source: `runtime/weak.pep`

## Weak

```pepper
struct Weak<T>
```

A reference to a struct object that does not keep it alive, for back
pointers (a child's parent, an observer's subject) that would otherwise
form a reference cycle and leak.

The object is reached only through a `with` block, which upgrades the weak
reference to an ordinary strong one for the length of the block. Once the
object has been destroyed the upgrade fails: the body is skipped and the
`else` block runs instead.

A `Weak<T>` never changes what it points at, so copies of it can be shared
freely.

**Type parameters**
- `T` — the struct type pointed at

**See also**
- `Scoped`

**Example**
```pepper
    struct Child {
        Weak<Parent> Owner;

        construct(Parent owner) {
            Owner = Weak<Parent>(owner);
        }

        String owner_name() {
            with (var parent = Owner) {
                return parent.Name;
            } else {
                return "(gone)";
            }
            return "";
        }
    }
```

### Constructor

#### Weak()

```pepper
construct(T target)
```

Creates a weak reference to `target`'s object.

**Parameters**
- `target` — the object to point at; a null reference makes a weak reference that is always expired

### Methods

#### expired

```pepper
bool expired()
```

Reports whether the object has been destroyed.

A `false` result can be out of date by the time it is used; enter the
reference with `with` to use the object.

**Returns**
- true once the object has been destroyed, or if the reference was made from null

#### enter

```pepper
T enter()
```

Upgrades the weak reference for a `with` block.

**Returns**
- a new strong reference to the object, or null once it has been destroyed

#### exit

```pepper
void exit()
```

Leaves the scope. The strong reference `enter()` returned is released
by the `with` block itself, so there is nothing to do.
