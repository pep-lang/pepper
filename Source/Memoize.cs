using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    public static class Memoizer {
        public static Func<TInput, TResult> Memoized<TInput, TResult>(Func<TInput, TResult> fn) where TInput : notnull => fn.Memoize();
        public static Func<TInput, TResult> Memoize<TInput, TResult>(this Func<TInput, TResult> func) where TInput : notnull {
            // create cache ("memo")
            var memo = new Dictionary<TInput, TResult>();

            // wrap provided function with cache handling
            return input => {
                // check if result for set input was already cached
                if (memo.TryGetValue(input, out var fromMemo))
                    // if yes, return value
                    return fromMemo;

                // if no, call function
                var result = func(input);

                // cache the result
                memo.Add(input, result);

                // return result
                return result;
            };
        }
    }
}
