using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    internal static class Log {
        private static void RawLog(string message) {
            Console.WriteLine(message);
            System.Diagnostics.Debug.WriteLine(message);
        }

        public static void Info(string message) {
            RawLog(message);
        }

        public static void Warn(string message) {
            message = $"Warning: ${message}";
            RawLog(message);
        }

        public static void Error(string message) {
            message = $"ERROR: ${message}";
            RawLog(message);
        }
    }
}
