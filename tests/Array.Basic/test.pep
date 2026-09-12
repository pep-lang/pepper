

main(): int {
    int[] arr = _pep_malloc(4 * sizeof<int>());
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    arr[3] = 4;
    var i = 0;
    var sum = 0;
    sum += arr[0];
    sum += arr[1];
    sum += arr[2];
    sum += arr[3];
    _pep_free(arr);
    return 10 - sum;
}
