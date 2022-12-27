define i32 @main(i32 %0, i8* %1) {
entry:
  %2 = alloca i1, align 1
  %3 = alloca i32, align 4
  store i1 false, i1* %2, align 1
  store i1* %2, i32* %3, align 8
  %4 = load i32, i32* %3, align 4
  ret i32 %4
}
