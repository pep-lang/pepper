

int main() {
    int[] arr = malloc(4 * sizeof<int>());
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
    free(arr);
    return 10 - sum;
}

