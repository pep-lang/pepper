//! Chained indexing (`a[i][j]`, `a[i][j][k]`) through raw pointer elements:
//! `__ptr<__ptr<T>>`, `char**`, `Array<__ptr<T>>`, and a struct field of
//! pointer type. Each level strides by its own pointee, so neighbouring
//! elements are written with distinct values and read back. Raw pointer
//! slots carry no refcount, so every test frees its buffers and checks the
//! live-allocation count is back where it started.

use crate::support::jit_census as compile_jit_census;

#[test]
fn ptr_ptr_2d() {
    let (result, leaked) = compile_jit_census(
        r#"
test(): int {
    var rows: __ptr<__ptr<int>> = _pep_malloc(2 * sizeof<__ptr<int>>());
    rows[0] = _pep_malloc(3 * sizeof<int>());
    rows[1] = _pep_malloc(3 * sizeof<int>());
    var i = 0;
    while (i < 2) {
        var j = 0;
        while (j < 3) {
            rows[i][j] = i * 10 + j;
            j = j + 1;
        }
        i = i + 1;
    }
    var sum = rows[0][0] + rows[0][1] + rows[0][2] + rows[1][0] + rows[1][1] + rows[1][2];
    _pep_free(rows[0]);
    _pep_free(rows[1]);
    _pep_free(rows);
    return sum;
}
"#,
    );
    assert_eq!(result, 0 + 1 + 2 + 10 + 11 + 12);
    assert_eq!(leaked, 0);
}

#[test]
fn ptr_ptr_ptr_3d() {
    let (result, leaked) = compile_jit_census(
        r#"
test(): int {
    var c: __ptr<__ptr<__ptr<long>>> = _pep_malloc(2 * sizeof<__ptr<__ptr<long>>>());
    c[0] = _pep_malloc(2 * sizeof<__ptr<long>>());
    c[1] = _pep_malloc(2 * sizeof<__ptr<long>>());
    c[0][0] = _pep_malloc(2 * sizeof<long>());
    c[0][1] = _pep_malloc(2 * sizeof<long>());
    c[1][0] = _pep_malloc(2 * sizeof<long>());
    c[1][1] = _pep_malloc(2 * sizeof<long>());
    c[0][0][0] = 1;
    c[0][0][1] = 2;
    c[0][1][0] = 3;
    c[0][1][1] = 4;
    c[1][0][0] = 5;
    c[1][0][1] = 6;
    c[1][1][0] = 7;
    c[1][1][1] = 8;
    var r = c[0][0][0] * 1 + c[0][0][1] * 2 + c[0][1][0] * 3 + c[0][1][1] * 4
          + c[1][0][0] * 5 + c[1][0][1] * 6 + c[1][1][0] * 7 + c[1][1][1] * 8;
    _pep_free(c[0][0]);
    _pep_free(c[0][1]);
    _pep_free(c[1][0]);
    _pep_free(c[1][1]);
    _pep_free(c[0]);
    _pep_free(c[1]);
    _pep_free(c);
    return r as int;
}
"#,
    );
    assert_eq!(result, 1 + 4 + 9 + 16 + 25 + 36 + 49 + 64);
    assert_eq!(leaked, 0);
}

#[test]
fn char_ptr_ptr_2d() {
    // `char**` lowers to the same type as `__ptr<__ptr<char>>`; one-byte
    // elements catch a stride that is still pointer- or int-sized.
    let (result, leaked) = compile_jit_census(
        r#"
test(): int {
    var words: __ptr<__ptr<char>> = _pep_malloc(2 * sizeof<__ptr<char>>());
    words[0] = _pep_malloc(4);
    words[1] = _pep_malloc(4);
    words[0][0] = 97;
    words[0][1] = 98;
    words[0][2] = 99;
    words[1][0] = 120;
    words[1][1] = 121;
    if (words[0][1] != 98) { return 1; }
    if (words[0][2] != 99) { return 2; }
    if (words[1][0] != 120) { return 3; }
    if (words[1][2] != 0) { return 4; }
    if (strlen(words[0]) != 3) { return 5; }
    _pep_free(words[0]);
    _pep_free(words[1]);
    _pep_free(words);
    return 0;
}
extern ulong strlen(char* s);
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn array_of_ptr_2d_and_3d() {
    let (result, leaked) = compile_jit_census(
        r#"
test(): int {
    var rows = Array<__ptr<int>>();
    rows.append(_pep_malloc(3 * sizeof<int>()));
    rows.append(_pep_malloc(3 * sizeof<int>()));
    rows[0][2] = 3;
    rows[1][0] = 4;
    rows[1][2] = 5;
    if (rows[0][2] + rows[1][0] + rows[1][2] != 12) { return 1; }

    var cube = Array<__ptr<__ptr<int>>>();
    cube.append(_pep_malloc(2 * sizeof<__ptr<int>>()));
    cube[0][0] = _pep_malloc(2 * sizeof<int>());
    cube[0][1] = _pep_malloc(2 * sizeof<int>());
    cube[0][0][1] = 6;
    cube[0][1][0] = 7;
    cube[0][1][1] = 8;
    if (cube[0][0][1] + cube[0][1][0] + cube[0][1][1] != 21) { return 2; }

    _pep_free(rows[0]);
    _pep_free(rows[1]);
    _pep_free(cube[0][0]);
    _pep_free(cube[0][1]);
    _pep_free(cube[0]);
    return 0;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn struct_field_of_ptr_2d_and_3d() {
    let (result, leaked) = compile_jit_census(
        r#"
struct Grid {
    var cells: __ptr<__ptr<int>>;
    var cube: __ptr<__ptr<__ptr<int>>>;
}
test(): int {
    var g = Grid();
    g.cells = _pep_malloc(2 * sizeof<__ptr<int>>());
    g.cells[0] = _pep_malloc(2 * sizeof<int>());
    g.cells[1] = _pep_malloc(2 * sizeof<int>());
    g.cells[0][1] = 2;
    g.cells[1][0] = 3;
    g.cells[1][1] = 4;
    if (g.cells[0][1] + g.cells[1][0] + g.cells[1][1] != 9) { return 1; }

    g.cube = _pep_malloc(1 * sizeof<__ptr<__ptr<int>>>());
    g.cube[0] = _pep_malloc(2 * sizeof<__ptr<int>>());
    g.cube[0][1] = _pep_malloc(3 * sizeof<int>());
    g.cube[0][1][2] = 42;
    if (g.cube[0][1][2] != 42) { return 2; }

    _pep_free(g.cells[0]);
    _pep_free(g.cells[1]);
    _pep_free(g.cells);
    _pep_free(g.cube[0][1]);
    _pep_free(g.cube[0]);
    _pep_free(g.cube);
    return 0;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn array_of_array_still_indexes() {
    // The struct-element path (`Array<Array<int>>`) is unchanged.
    let (result, leaked) = compile_jit_census(
        r#"
test(): int {
    var grid = Array<Array<int>>();
    grid.append(Array<int>());
    grid.append(Array<int>());
    grid[0].append(1);
    grid[1].append(2);
    grid[1].append(3);
    grid[1][1] = 9;
    return grid[0][0] + grid[1][0] + grid[1][1];
}
"#,
    );
    assert_eq!(result, 12);
    assert_eq!(leaked, 0);
}
