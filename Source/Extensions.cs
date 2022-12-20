using Pepper.AST;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics.CodeAnalysis;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
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
                foreach (var seq in seqs) {
                    while (seq.Etor.MoveNext()) {
                        yield return seq.Etor.Current;
                    }
                }
            }
        }

        public static IEnumerable<T> NonNull<T>(this IEnumerable<T?> seq) {
            return seq.Where(t => t != null).Select(t => t!);
        }

        //public static IEnumerable<T> As<T>(this System.Collections.IEnumerable seq) {
        //    return seq.Cast<T>();
        //}

        public static IEnumerable<T> OfType<T, U>(this IEnumerable<U> seq) where U : T {
            return seq.Where(i => i is T).Select(i => (T)i);
        }

        public static void ForAll<T>(this IEnumerable<T> seq, Action<T> action) {
            foreach (var i in seq) {
                action(i);
            }
        }

        public static int IndexOf<T>(this IEnumerable<T> seq, T item) where T : notnull {
            int idx = 0;
            seq.First(t => {
                if (t.Equals(item)) return true;
                ++idx;
                return false;
            });
            return idx;
        }

        public static OrderedMap<TKey, TValue> ToOrderedMap<TKey, TValue>(this IEnumerable<KeyValuePair<TKey, TValue>> source)
            where TKey : notnull {
            return new OrderedMap<TKey, TValue>(source);
        }

        public static OrderedMap<TKey, TValue> ToOrderedMap<TKey, TValue>(this IEnumerable<TValue> source, Func<TValue, TKey> keySelector) 
            where TKey : notnull {
            return new OrderedMap<TKey, TValue>(source.Select(v => new KeyValuePair<TKey, TValue>(keySelector(v), v)));
        }

        public static OrderedMap<TKey, TValue> ToOrderedMap<TKey, TValue, TSource>(this IEnumerable<TSource> source, Func<TSource, TKey> keySelector, Func<TSource, TValue> valueSelector) 
            where TKey : notnull {
            return new OrderedMap<TKey, TValue>(source.Select(s => new KeyValuePair<TKey, TValue>(keySelector(s), valueSelector(s))));
        }
    }

    public class OrderedMap<TKey, TValue> : OrderedDictionary, IEnumerable<KeyValuePair<TKey, TValue>> where TKey : notnull {
        public OrderedMap() : base() { }
        public OrderedMap(IEnumerable<KeyValuePair<TKey, TValue>> pairs) : base() {
            pairs.ForAll(pair => {
                this[pair.Key] = pair.Value;
            });
        }

        public TValue this[TKey key] {
            get {
                return (TValue)base[key]!;
            }
            set {
                base[key] = value;
            }
        }

        public bool TryGetValue(TKey key, [MaybeNullWhen(false)] out TValue value) {
            var objVal = base[key];
            if (objVal != null) {
                value = (TValue)objVal;
                return true;
            }
            value = default;
            return false;
        }

        public void Add(TKey key, TValue value) {
            base.Add(key, value);
        }

        public int IndexOf(TKey key) => base.Keys.Cast<TKey>().IndexOf(key);

        public new IEnumerable<TKey> Keys => base.Keys.Cast<TKey>();
        public new IEnumerable<TValue> Values => base.Values.Cast<TValue>();

        public new IEnumerator GetEnumerator() => new Enumerator(this, base.GetEnumerator());

        IEnumerator<KeyValuePair<TKey, TValue>> IEnumerable<KeyValuePair<TKey, TValue>>.GetEnumerator() =>
            new Enumerator(this, base.GetEnumerator());

        public struct Enumerator : IEnumerator<KeyValuePair<TKey, TValue>>, IDictionaryEnumerator {
            IEnumerator Etor;

            public Enumerator(OrderedMap<TKey, TValue> map, IEnumerator etor) {
                Etor = etor;
            }

            public void Dispose() {

            }

            public KeyValuePair<TKey, TValue> Current => (KeyValuePair <TKey, TValue>)Etor.Current;
            public bool MoveNext() => Etor.MoveNext();
            public void Reset() => Etor.Reset();

            object? IEnumerator.Current => Etor.Current;
            DictionaryEntry IDictionaryEnumerator.Entry => new DictionaryEntry(Current.Key, Current.Value);
            object IDictionaryEnumerator.Key => Current.Key;
            object? IDictionaryEnumerator.Value => Current.Value;
        }
    }
}
