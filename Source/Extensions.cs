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

        public static IEnumerable<T> Mix<T>(this IEnumerable<T> start, params IEnumerable<T>[] sequences) {
            var seqs = sequences.Prepend(start).Select(x => new { Etor = x.GetEnumerator(), Count = x.Count() });
            bool flag = true;

            while (flag) {
                foreach (var seq in seqs)
                    for (int i = 0; i < seq.Count && (flag |= seq.Etor.MoveNext()); i++)
                        yield return seq.Etor.Current;
            }
        }

        public static IEnumerable<T> NonNull<T>(this IEnumerable<T?> seq) {
            return seq.Where(t => t != null).Select(t => t!);
        }

        public static IEnumerable<T> As<T>(this IEnumerable<T> seq) {
            return seq.Select(t => t);
        }
    }
}
