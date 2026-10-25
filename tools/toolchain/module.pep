## Pepper toolchains installed side by side, as `pep-install` manages them
## and the `pepper` entry point runs them: their versions, where they are
## installed, and which one a folder uses; the check of a package
## `pep-package vendor` copied into a project, which the compiler runs too;
## where a package's build script is; and the major version a
## dependency's range starts in, which picks its copy when a graph holds
## several majors of one package.
export * from "build_script";
export * from "version";
export * from "home";
export * from "choose";
export * from "vendor";
export * from "major";
