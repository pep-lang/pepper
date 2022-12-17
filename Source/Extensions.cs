using Pepper.AST;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    public static class Extensions {
        public static List<System.Type> GetSubclasses<T>(this Assembly assembly) {
            return assembly.GetTypes().Where(t => {
                return t.IsClass && !t.IsAbstract && typeof(T).IsAssignableFrom(t);
            }).ToList();
        }

        public static List<T> RegisterSubclasses<T>(this Assembly assembly) {
            return assembly.GetSubclasses<T>().Select(t => (T)Activator.CreateInstance(t)!).ToList();
        }
    }
}
