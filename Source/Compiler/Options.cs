using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using CommandLine;

namespace Pepper {
    public class Options {
        [Value(index: 0, Required = true)]
        public string CompilerPath { get; set; } = String.Empty;

        [Value(index: 1, Required = true, HelpText = "Input source files")]
        public string Input { get; set; } = String.Empty;

        [Option(shortName: 'o', longName: "output", Default = "bin/a.out", HelpText = "Output binary path")]
        public string Output { get; set; } = "bin/a.out";

        public string ModuleName {
            get {
                return Path.GetFileNameWithoutExtension(Output);
            }
        }

        public static Options Parse() {
            return Parse(Environment.GetCommandLineArgs());
        }

        public static Options Parse(IEnumerable<string> args) {
            return CommandLine.Parser.Default.ParseArguments<Options>(args)
                .MapResult(
                    options => {
                        return options;
                    },
                    errors => {
                        throw new ArgumentException(
                            errors.Select(e => e.ToString())
                                .Aggregate("Error parsing arguments:\n", (contents, error) => String.Join("\n", contents, error), errors => errors)
                        );
                    });
        }
    }
}
