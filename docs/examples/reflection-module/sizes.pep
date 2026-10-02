export struct Pixel {
    var red: u8;
    var green: u8;
    var blue: u8;
    var alpha: u8;
}

export enum Channel {
    Red,
    Green,
    Blue,
    Alpha
}

# A module-scope `static` block runs once, while compiling. Each `const` at
# its top becomes a module-scope constant holding what the block computed;
# `export static` exports them.
export static {
    var bytes = 0;
    for (var field in reflect.properties<Pixel>()) {
        reflect.assert(reflect.is_same<field.Type, u8>(), $"'{field.name}' must be one byte");
        bytes += 1;
    }
    const PIXEL_BYTES = bytes;
    const LAST_CHANNEL = reflect.cases<Channel>()[reflect.cases<Channel>().count - 1].get();
}
