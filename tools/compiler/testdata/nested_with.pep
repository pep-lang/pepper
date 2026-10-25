import async;

const names = async.Mutex<Array<String>>(Array<String>());
const other = async.Mutex<Array<String>>(Array<String>());

# A local of an enclosing `with` block may hold that block's locked value and
# copies of an inner block's; a local of the inner block may hold its value.
main(): int {
    var count = 0;
    with (var list = names.lock()) {
        list.append("a");
        var mine = list;
        var taken = Array<String>();
        for (var i in 0..2) {
            with (var o = other.lock()) {
                var held = o;
                held.append("b");
                taken = copy(o);
                mine.append(copy(o[0]));
            }
        }
        count = (mine.count * 10 + taken.count) as int;
    }
    print($"{count}");
    return 0;
}
