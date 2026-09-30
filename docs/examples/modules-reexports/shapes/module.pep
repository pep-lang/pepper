# The shapes module: its interface is its files' exports, passed on whole or
# by name.
export * from "rect";                               # every export of rect.pep
export [perimeter as outline, Side] from "measure"; # two, one renamed
