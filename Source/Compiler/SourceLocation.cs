
namespace Pepper {
    public class SourceLocation {
        public static SourceLocation Current { get; set; } = new SourceLocation("", 0);
        public static string Context { get; set; } = "Startup";

        public string Path { get; private set; }
        public int Line { get; private set; }
        public int Column { get; private set; }
        public SourceLocation(string path, int line, int column = -1) {
            Path = path;
            Line = line;
            Column = column;
        }

        public override string ToString() {
            var column = Column >= 0 ? $",{Column}" : "";
            return $"{Path}({Line}{column})";
        }
    }
}
