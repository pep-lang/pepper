#!/usr/bin/env python3
"""Adds `import "<sibling>";` wherever a file of a module uses another file of
its module without importing it, as `pepc` reports.

Usage: scripts/add-module-imports.py <repo> <pepc> <pep-fmt>

Checks every module folder under runtime/, tools/, docs/examples/ and tests/
(through a program that imports it) and every *_test.pep under runtime/ and
tools/ with `pepc --emit-checked`, adds the imports the errors name, formats
the files it changed, and repeats until no file needs one. Files that
platform selection drops on this host are not checked.
"""
import os, re, subprocess, sys, tempfile
from collections import defaultdict
repo, pepc, fmt = sys.argv[1], sys.argv[2], sys.argv[3]
runtime = os.path.join(repo, 'runtime')
ERR = re.compile(r"^(?P<file>\S+?\.pep):\d+:\d+: error: '[^']+' is declared in (?:an extension in )?(?P<other>\S+?\.pep)(?:, another file of this module)?, which this file does not import; add an import for it")
skip_dirs = {'.pep', 'target', '.git', 'node_modules'}

def module_roots():
    roots = []
    for base in ['runtime', 'tools', 'docs/examples', 'tests']:
        for d, dirs, files in os.walk(os.path.join(repo, base)):
            dirs[:] = [x for x in dirs if x not in skip_dirs]
            if 'module.pep' in files:
                roots.append(d)
    return roots

def outer(root):
    # The nearest folder above `root` that is not itself a module.
    a = os.path.dirname(root)
    while os.path.isfile(os.path.join(a, 'module.pep')):
        a = os.path.dirname(a)
    return a

def runs():
    out = []
    for root in module_roots():
        a = outer(root)
        name = os.path.relpath(root, a).replace(os.sep, '.')
        out.append(('module', root, a, name))
    for base in ['runtime', 'tools']:
        for d, dirs, files in os.walk(os.path.join(repo, base)):
            dirs[:] = [x for x in dirs if x not in skip_dirs]
            for f in files:
                if f.endswith('_test.pep'):
                    out.append(('test', os.path.join(d, f), None, None))
    return out

def check(run, tmp):
    kind, path, a, name = run
    env = dict(os.environ, PEPPER_RUNTIME=runtime)
    if kind == 'module':
        compiler = os.path.join(repo, 'tools', 'compiler')
        if path.startswith(compiler + os.sep):
            # In the compiler's project, whose pep.toml brings `llvm`.
            name = 'compiler.' + os.path.relpath(path, compiler).replace(os.sep, '.')
            main = os.path.join(compiler, '_add_imports_main.pep')
            a = os.path.join(repo, 'tools')
            cwd = compiler
        else:
            main = os.path.join(tmp, 'main.pep')
            cwd = tmp
        open(main, 'w').write(f'import {name};\nmain(): int {{\n    return 0;\n}}\n')
        args = [pepc, '--emit-checked', '-I', a, '-I', os.path.join(repo, 'tools'), main]
    else:
        args = [pepc, '--emit-checked', '--test', '-I', os.path.join(repo, 'tools'), path]
        cwd = os.path.dirname(path)
    try:
        r = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=600)
    finally:
        if kind == 'module' and cwd != tmp:
            os.remove(main)
    return r.stdout + r.stderr, cwd

def add(missing):
    changed = []
    for f, others in missing.items():
        text = open(f).read()
        lines = []
        for o in sorted(others):
            rel = os.path.relpath(o, os.path.dirname(f))
            if rel.endswith('.pep'):
                rel = rel[:-4]
            lines.append(f'import "{rel}";\n')
        lines = [l for l in lines if l not in text]
        if not lines:
            continue
        # Before the first import, else before the first declaration (after
        # the leading comment block).
        m = re.search(r'^(?:\[[^\n]*\]\s*\n)?(?:export\s+[^\n]*\bfrom\b|import)\b', text, re.M)
        if m:
            at = m.start()
        else:
            # Before the first declaration's doc comment, after the file's.
            at = 0
            for mm in re.finditer(r'^(?!#|\s*$)', text, re.M):
                at = mm.start(); break
            while True:
                before = text.rfind('\n', 0, max(at - 1, 0))
                line = text[before + 1:at]
                if at > 0 and line.startswith('##'):
                    at = before + 1
                else:
                    break
        text = text[:at] + ''.join(lines) + ('\n' if not m else '') + text[at:]
        open(f, 'w').write(text)
        changed.append(f)
    if changed:
        subprocess.run([fmt, '-w'] + changed, check=False)
    return changed

def main():
    all_runs = runs()
    print(f'{len(all_runs)} runs', flush=True)
    for round_ in range(6):
        missing = defaultdict(set); other_errors = 0
        with tempfile.TemporaryDirectory() as tmp:
            for run in all_runs:
                out, cwd = check(run, tmp)
                for line in out.splitlines():
                    m = ERR.match(line)
                    if m:
                        f = os.path.normpath(os.path.join(cwd, m.group('file')))
                        o = os.path.normpath(os.path.join(cwd, m.group('other')))
                        missing[f].add(o)
                    elif ': error:' in line:
                        other_errors += 1
                        if other_errors <= 5:
                            print('  other:', run[1], line[:200], flush=True)
        changed = add(missing)
        print(f'round {round_}: {sum(len(v) for v in missing.values())} imports in {len(changed)} files; other errors {other_errors}', flush=True)
        if not changed:
            break
main()
