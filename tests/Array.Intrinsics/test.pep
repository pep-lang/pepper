
int main() {
    __ptr<int> arr = malloc(5 * sizeof<int>());
    int idx = 0;
    while (idx < 5) {
        arr[idx] = idx + 1;
        ++idx;
    }
    trace_ptr(arr, "arr2");
    int sum = 0;
    idx = 0;
    while (idx < 5) {
        sum += arr[idx];
        ++idx;
    }
    free(arr);
    return 15 - sum;
}
