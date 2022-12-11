using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using CommandLine;

namespace Pepper {
    public class Options {
        [Value(0, MetaName="CompilerPath", Required = true)]
        public string CompilerPath { get; set; } = String.Empty;

        [Value(1, MetaName="InputFiles", HelpText = "Input source files")]
        public IEnumerable<string> Input { get; set; } = new List<string>();

        [Option(shortName: 'o', longName: "output", Default = "bin/a.out", HelpText = "Output binary path")]
        public string Output { get; set; } = "bin/a.out";

        public string ModuleName {
            get {
                if (Output != "bin/a.out")
                {
                    Path.GetFileNameWithoutExtension(Output);
                }
                return Path.GetFileNameWithoutExtension(Input.First());
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
