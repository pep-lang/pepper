# `Circle` is both a case of `Shape` and a type of its own.
[Value]
export enum Shape {
    Circle(radius: int),
    Square(side: int),
    Dot,
}

export enum Circle {
    Big,
}
