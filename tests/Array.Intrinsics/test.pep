
int main() {
    __ptr<int> arr = _pep_malloc(5 * sizeof<int>());
    int idx = 0;
    while (idx < 5) {
        arr[idx] = idx + 1;
        ++idx;
    }
    int sum = 0;
    idx = 0;
    while (idx < 5) {
        sum += arr[idx];
        ++idx;
    }
    _pep_free(arr);
    return 15 - sum;
}
