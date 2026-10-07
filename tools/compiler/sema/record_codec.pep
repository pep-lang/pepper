## Saving and loading a checked module: a binary writer and reader for
## every type `Module` reaches, the AST nodes it holds included. Generated
## by `scripts/gen-sema-record.py`; do not edit.

import compiler.ast;
import [Loc] from "loc";
import [
    compare_bytes,
    DeltaBase,
    interface_text,
    merge_by_place,
    RecordIn,
    RecordOut,
    write_interface_checked_summaries,
    write_interface_summaries
] from "record";

## Writes `module` to `out`.
##
## @param out the record
## @param module the module
export write_module(out: RecordOut, module: Module) {
    _m_Module_write(out, module);
}

## Reads a module from `input`, as `write_module` wrote it.
##
## @param input the record
## @returns the module
export read_module(input: RecordIn): Module {
    return _m_Module_read(input);
}

## Writes `module` to `out` as a delta on the module `base` indexes: each
## element of its lists that the base holds as it is becomes a reference.
##
## @param out the record
## @param module the module
## @param base the index of the module it is written on
## @param next filled with the index of `module`, as `index_module` would,
##     but for the fields `index_resumed` indexes
export write_module_delta(out: RecordOut, module: Module, base: DeltaBase, next: DeltaBase) {
    _m_Module_write_delta(out, module, base, next);
}

## Reads a module from `input`, as `write_module_delta` wrote it on `base`.
## The elements it refers to are `base`'s own, not copies.
##
## @param input the record
## @param base the module it was written on, as read back
## @returns the module
export read_module_delta(input: RecordIn, base: Module): Module {
    return _m_Module_read_delta(input, base);
}

## Indexes `module`'s list elements into `base`, for `write_module_delta`.
##
## @param module the module a later delta is written on
## @param base the index
export index_module(module: Module, base: DeltaBase) {
    _m_Module_index(module, base);
}

## Indexes into `base` the fields of `module` that `resume_checked` replaces,
## which `write_module_delta` leaves out of its `next`.
##
## @param module the module, resumed
## @param base the index
export index_resumed(module: Module, base: DeltaBase) {
    _m_Module_index_resumed(module, base);
}

## Returns the interface hash of each field of `module`, and of each
## struct and function by name, for `PEPC_TRACE_INTERFACE`; or with
## `interface` false, the hash of each as it is written in full.
##
## @param module the module
## @param interface whether to hash the interface
## @returns (what, hash) pairs
export interface_fields(module: Module, interface: bool = true): Array<(String, String)> {
    return _m_Module_interface_fields(module, interface);
}

## Writes a type alias to `out`.
##
## @param out the record
## @param alias the alias
export write_type_alias(out: RecordOut, alias: TypeAliasDef) {
    _m_TypeAliasDef_write(out, alias);
}

## Reads a type alias from `input`, as `write_type_alias` wrote it.
##
## @param input the record
## @returns the alias
export read_type_alias(input: RecordIn): TypeAliasDef {
    return _m_TypeAliasDef_read(input);
}

_m_Module_write(out: RecordOut, value: Module) {
    out.unsigned(value.imports.count);
    for (var _item1 in value.imports) {
        _a_Import_write(out, _item1);
    }
    out.unsigned(value.structs.count);
    for (var _item2 in value.structs) {
        _m_StructDef_write(out, _item2);
    }
    out.unsigned(value.traits.count);
    for (var _item3 in value.traits) {
        _m_TraitDef_write(out, _item3);
    }
    out.unsigned(value.extensions.count);
    for (var _item4 in value.extensions) {
        _m_ExtensionDef_write(out, _item4);
    }
    out.unsigned(value.functions.count);
    for (var _item5 in value.functions) {
        _m_FunctionDef_write(out, _item5);
    }
    out.unsigned(value.externs.count);
    for (var _item6 in value.externs) {
        _m_ExternDef_write(out, _item6);
    }
    out.unsigned(value.globals.count);
    for (var _item7 in value.globals) {
        _m_VariableDef_write(out, _item7);
    }
    out.unsigned(value.static_blocks.count);
    for (var _item8 in value.static_blocks) {
        _m_ModuleStaticBlock_write(out, _item8);
    }
    out.unsigned(value.enums.count);
    for (var _item9 in value.enums) {
        _m_EnumDef_write(out, _item9);
    }
    out.unsigned(value.struct_specs.count);
    for (var _item10 in value.struct_specs) {
        _m_TypeName_write(out, _item10);
    }
    out.unsigned(value.func_specs.count);
    for (var _item11 in value.func_specs) {
        _m_TypeName_write(out, _item11);
    }
    out.unsigned(value.type_aliases.count);
    for (var _item12 in value.type_aliases) {
        _m_TypeAliasDef_write(out, _item12);
    }
    out.unsigned(value.withheld.count);
    for (var _item13 in value.withheld) {
        _m_Withheld_write(out, _item13);
    }
    out.unsigned(value.properties.count);
    for (var _item14 in value.properties) {
        _m_PropertyDef_write(out, _item14);
    }
    out.unsigned(value.type_uses.count);
    for (var _item15 in value.type_uses) {
        _m_TypeUse_write(out, _item15);
    }
    out.unsigned(value.use_contexts.count);
    for (var _item16 in value.use_contexts) {
        _m_UseContext_write(out, _item16);
    }
    if (out.blank_bodies) {
        out.unsigned(0);
    } else {
        out.unsigned(value.literal_args.count);
        for (var _item17 in value.literal_args) {
            var (_t18, _t19, _t20) = _item17;
            out.loc(_t18);
            out.unsigned(_t19);
            out.loc(_t20);
        }
    }
    out.unsigned(value.constrained_aliases.count);
    for (var _item21 in value.constrained_aliases) {
        _m_TypeAliasDef_write(out, _item21);
    }
    out.unsigned(value.trait_types.count);
    for (var _item22 in value.trait_types) {
        _m_TraitType_write(out, _item22);
    }
    out.unsigned(value.conversions.count);
    for (var _item23 in value.conversions) {
        _m_Conversion_write(out, _item23);
    }
    var _keys25 = Array<(u8[], u8[], String)>();
    for (var (_key24, _) in value.overload_sets) {
        var _scratch26 = out.scratch();
        _scratch26.text(_key24);
        var _vscratch28 = out.scratch();
        _vscratch28.unsigned(value.overload_sets[_key24].count);
        for (var _item29 in value.overload_sets[_key24]) {
            _vscratch28.text(_item29);
        }
        _keys25.append((_scratch26.finish(), _vscratch28.finish(), _key24));
    }
    _keys25.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys25.count);
    for (var (_bytes27, _, _key24) in _keys25) {
        out.text(_key24);
        out.unsigned(value.overload_sets[_key24].count);
        for (var _item30 in value.overload_sets[_key24]) {
            out.text(_item30);
        }
    }
    var _keys32 = Array<(u8[], u8[], String)>();
    for (var (_key31, _) in value.overload_unions) {
        var _scratch33 = out.scratch();
        _scratch33.text(_key31);
        var _vscratch35 = out.scratch();
        _vscratch35.unsigned(value.overload_unions[_key31].count);
        for (var _item36 in value.overload_unions[_key31]) {
            _vscratch35.unsigned(_item36.count);
            for (var _item37 in _item36) {
                _vscratch35.text(_item37);
            }
        }
        _keys32.append((_scratch33.finish(), _vscratch35.finish(), _key31));
    }
    _keys32.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys32.count);
    for (var (_bytes34, _, _key31) in _keys32) {
        out.text(_key31);
        out.unsigned(value.overload_unions[_key31].count);
        for (var _item38 in value.overload_unions[_key31]) {
            out.unsigned(_item38.count);
            for (var _item39 in _item38) {
                out.text(_item39);
            }
        }
    }
    var _keys41 = Array<(u8[], u8[], String)>();
    for (var (_key40, _) in value.method_overload_sets) {
        var _scratch42 = out.scratch();
        _scratch42.text(_key40);
        var _vscratch44 = out.scratch();
        var _keys46 = Array<(u8[], u8[], String)>();
        for (var (_key45, _) in value.method_overload_sets[_key40]) {
            var _scratch47 = _vscratch44.scratch();
            _scratch47.text(_key45);
            var _vscratch49 = _vscratch44.scratch();
            _vscratch49.unsigned(value.method_overload_sets[_key40][_key45].count);
            for (var _item50 in value.method_overload_sets[_key40][_key45]) {
                _vscratch49.text(_item50);
            }
            _keys46.append((_scratch47.finish(), _vscratch49.finish(), _key45));
        }
        _keys46.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch44.unsigned(_keys46.count);
        for (var (_bytes48, _, _key45) in _keys46) {
            _vscratch44.text(_key45);
            _vscratch44.unsigned(value.method_overload_sets[_key40][_key45].count);
            for (var _item51 in value.method_overload_sets[_key40][_key45]) {
                _vscratch44.text(_item51);
            }
        }
        _keys41.append((_scratch42.finish(), _vscratch44.finish(), _key40));
    }
    _keys41.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys41.count);
    for (var (_bytes43, _, _key40) in _keys41) {
        out.text(_key40);
        var _keys53 = Array<(u8[], u8[], String)>();
        for (var (_key52, _) in value.method_overload_sets[_key40]) {
            var _scratch54 = out.scratch();
            _scratch54.text(_key52);
            var _vscratch56 = out.scratch();
            _vscratch56.unsigned(value.method_overload_sets[_key40][_key52].count);
            for (var _item57 in value.method_overload_sets[_key40][_key52]) {
                _vscratch56.text(_item57);
            }
            _keys53.append((_scratch54.finish(), _vscratch56.finish(), _key52));
        }
        _keys53.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys53.count);
        for (var (_bytes55, _, _key52) in _keys53) {
            out.text(_key52);
            out.unsigned(value.method_overload_sets[_key40][_key52].count);
            for (var _item58 in value.method_overload_sets[_key40][_key52]) {
                out.text(_item58);
            }
        }
    }
    _m_ExtensionScopes_write(out, value.extension_scopes);
    var _keys60 = Array<(u8[], u8[], Loc)>();
    for (var _key59 in value.private_functions) {
        var _scratch61 = out.scratch();
        _scratch61.loc(_key59);
        var _vscratch63 = out.scratch();
        _keys60.append((_scratch61.finish(), _vscratch63.finish(), _key59));
    }
    _keys60.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys60.count);
    for (var (_bytes62, _, _key59) in _keys60) {
        out.loc(_key59);
    }
    var _keys65 = Array<(u8[], u8[], Loc)>();
    for (var _key64 in value.file_private_functions) {
        var _scratch66 = out.scratch();
        _scratch66.loc(_key64);
        var _vscratch68 = out.scratch();
        _keys65.append((_scratch66.finish(), _vscratch68.finish(), _key64));
    }
    _keys65.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys65.count);
    for (var (_bytes67, _, _key64) in _keys65) {
        out.loc(_key64);
    }
    if (out.blank_bodies) {
        out.unsigned(0);
    } else {
        out.unsigned(value.call_targets.count);
        for (var _item69 in value.call_targets) {
            var (_t70, _t71) = _item69;
            out.loc(_t70);
            out.text(_t71);
        }
    }
    if (out.blank_bodies) {
        out.unsigned(0);
    } else {
        out.unsigned(value.argument_names.count);
        for (var _item72 in value.argument_names) {
            var (_t73, _t74) = _item72;
            out.loc(_t73);
            out.text(_t74);
        }
    }
    out.unsigned(value.namespaces.count);
    for (var _item75 in value.namespaces) {
        out.text(_item75);
    }
    if (out.blank_bodies) {
        out.unsigned(0);
    } else {
        out.unsigned(value.cached_files.count);
        for (var _item76 in value.cached_files) {
            out.flag(_item76);
        }
    }
    if (out.blank_locs) {
        write_interface_summaries(out, value.recorded_summaries);
    } else {
        var _keys78 = Array<(u8[], u8[], Loc)>();
        for (var (_key77, _) in value.recorded_summaries) {
            var _scratch79 = out.scratch();
            _scratch79.loc(_key77);
            var _vscratch81 = out.scratch();
            _vscratch81.text(value.recorded_summaries[_key77]);
            _keys78.append((_scratch79.finish(), _vscratch81.finish(), _key77));
        }
        _keys78.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys78.count);
        for (var (_bytes80, _, _key77) in _keys78) {
            out.loc(_key77);
            out.text(value.recorded_summaries[_key77]);
        }
    }
    if (out.blank_bodies) {
        out.unsigned(0);
    } else {
        var _keys83 = Array<(u8[], u8[], Loc)>();
        for (var _key82 in value.stripped) {
            var _scratch84 = out.scratch();
            _scratch84.loc(_key82);
            var _vscratch86 = out.scratch();
            _keys83.append((_scratch84.finish(), _vscratch86.finish(), _key82));
        }
        _keys83.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys83.count);
        for (var (_bytes85, _, _key82) in _keys83) {
            out.loc(_key82);
        }
    }
    var _blank = out.blank_bodies;
    out.blank_bodies = false;
    _m_Templates_write(out, value.templates);
    out.blank_bodies = _blank;
    _m_Checked_write(out, value.checked);
    var _keys88 = Array<(u8[], u8[], String)>();
    for (var (_key87, _) in value.spec_requests) {
        var _scratch89 = out.scratch();
        _scratch89.text(_key87);
        var _vscratch91 = out.scratch();
        _m_SpecRequest_write(_vscratch91, value.spec_requests[_key87]);
        _keys88.append((_scratch89.finish(), _vscratch91.finish(), _key87));
    }
    _keys88.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys88.count);
    for (var (_bytes90, _, _key87) in _keys88) {
        out.text(_key87);
        _m_SpecRequest_write(out, value.spec_requests[_key87]);
    }
    out.flag(value.record_summaries);
    if (out.blank_bodies) {
        out.unsigned(0);
    } else {
        out.unsigned(value.summaries_to_record.count);
        for (var _item92 in value.summaries_to_record) {
            var (_t93, _t94) = _item92;
            out.loc(_t93);
            out.text(_t94);
        }
    }
    var _keys96 = Array<(u8[], u8[], String)>();
    for (var (_key95, _) in value.caller_copies) {
        var _scratch97 = out.scratch();
        _scratch97.text(_key95);
        var _vscratch99 = out.scratch();
        _vscratch99.unsigned(value.caller_copies[_key95].count);
        for (var _item100 in value.caller_copies[_key95]) {
            _vscratch99.flag(_item100);
        }
        _keys96.append((_scratch97.finish(), _vscratch99.finish(), _key95));
    }
    _keys96.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys96.count);
    for (var (_bytes98, _, _key95) in _keys96) {
        out.text(_key95);
        out.unsigned(value.caller_copies[_key95].count);
        for (var _item101 in value.caller_copies[_key95]) {
            out.flag(_item101);
        }
    }
    out.flag(value.linked);
}

_m_Module_read(input: RecordIn): Module {
    var _v102 = Array<ast.Import>();
    var _n103 = input.count();
    for (var _ in 0.._n103) {
        _v102.append(_a_Import_read(input));
    }
    var _f104 = _v102;
    var _v105 = Array<StructDef>();
    var _n106 = input.count();
    for (var _ in 0.._n106) {
        _v105.append(_m_StructDef_read(input));
    }
    var _f107 = _v105;
    var _v108 = Array<TraitDef>();
    var _n109 = input.count();
    for (var _ in 0.._n109) {
        _v108.append(_m_TraitDef_read(input));
    }
    var _f110 = _v108;
    var _v111 = Array<ExtensionDef>();
    var _n112 = input.count();
    for (var _ in 0.._n112) {
        _v111.append(_m_ExtensionDef_read(input));
    }
    var _f113 = _v111;
    var _v114 = Array<FunctionDef>();
    var _n115 = input.count();
    for (var _ in 0.._n115) {
        _v114.append(_m_FunctionDef_read(input));
    }
    var _f116 = _v114;
    var _v117 = Array<ExternDef>();
    var _n118 = input.count();
    for (var _ in 0.._n118) {
        _v117.append(_m_ExternDef_read(input));
    }
    var _f119 = _v117;
    var _v120 = Array<VariableDef>();
    var _n121 = input.count();
    for (var _ in 0.._n121) {
        _v120.append(_m_VariableDef_read(input));
    }
    var _f122 = _v120;
    var _v123 = Array<ModuleStaticBlock>();
    var _n124 = input.count();
    for (var _ in 0.._n124) {
        _v123.append(_m_ModuleStaticBlock_read(input));
    }
    var _f125 = _v123;
    var _v126 = Array<EnumDef>();
    var _n127 = input.count();
    for (var _ in 0.._n127) {
        _v126.append(_m_EnumDef_read(input));
    }
    var _f128 = _v126;
    var _v129 = Array<TypeName>();
    var _n130 = input.count();
    for (var _ in 0.._n130) {
        _v129.append(_m_TypeName_read(input));
    }
    var _f131 = _v129;
    var _v132 = Array<TypeName>();
    var _n133 = input.count();
    for (var _ in 0.._n133) {
        _v132.append(_m_TypeName_read(input));
    }
    var _f134 = _v132;
    var _v135 = Array<TypeAliasDef>();
    var _n136 = input.count();
    for (var _ in 0.._n136) {
        _v135.append(_m_TypeAliasDef_read(input));
    }
    var _f137 = _v135;
    var _v138 = Array<Withheld>();
    var _n139 = input.count();
    for (var _ in 0.._n139) {
        _v138.append(_m_Withheld_read(input));
    }
    var _f140 = _v138;
    var _v141 = Array<PropertyDef>();
    var _n142 = input.count();
    for (var _ in 0.._n142) {
        _v141.append(_m_PropertyDef_read(input));
    }
    var _f143 = _v141;
    var _v144 = Array<TypeUse>();
    var _n145 = input.count();
    for (var _ in 0.._n145) {
        _v144.append(_m_TypeUse_read(input));
    }
    var _f146 = _v144;
    var _v147 = Array<UseContext>();
    var _n148 = input.count();
    for (var _ in 0.._n148) {
        _v147.append(_m_UseContext_read(input));
    }
    var _f149 = _v147;
    var _v150 = Array<(Loc, ulong, Loc)>();
    var _n151 = input.count();
    for (var _ in 0.._n151) {
        var _t152 = input.loc();
        var _t153 = input.unsigned();
        var _t154 = input.loc();
        _v150.append((_t152, _t153, _t154));
    }
    var _f155 = _v150;
    var _v156 = Array<TypeAliasDef>();
    var _n157 = input.count();
    for (var _ in 0.._n157) {
        _v156.append(_m_TypeAliasDef_read(input));
    }
    var _f158 = _v156;
    var _v159 = Array<TraitType>();
    var _n160 = input.count();
    for (var _ in 0.._n160) {
        _v159.append(_m_TraitType_read(input));
    }
    var _f161 = _v159;
    var _v162 = Array<Conversion>();
    var _n163 = input.count();
    for (var _ in 0.._n163) {
        _v162.append(_m_Conversion_read(input));
    }
    var _f164 = _v162;
    var _v165 = Map<String, Array<String>>();
    var _n166 = input.count();
    for (var _ in 0.._n166) {
        var _k167 = input.text();
        var _v168 = Array<String>();
        var _n169 = input.count();
        for (var _ in 0.._n169) {
            _v168.append(input.text());
        }
        _v165[_k167] = _v168;
    }
    var _f170 = _v165;
    var _v171 = Map<String, Array<Array<String>>>();
    var _n172 = input.count();
    for (var _ in 0.._n172) {
        var _k173 = input.text();
        var _v174 = Array<Array<String>>();
        var _n175 = input.count();
        for (var _ in 0.._n175) {
            var _v176 = Array<String>();
            var _n177 = input.count();
            for (var _ in 0.._n177) {
                _v176.append(input.text());
            }
            _v174.append(_v176);
        }
        _v171[_k173] = _v174;
    }
    var _f178 = _v171;
    var _v179 = Map<String, Map<String, Array<String>>>();
    var _n180 = input.count();
    for (var _ in 0.._n180) {
        var _k181 = input.text();
        var _v182 = Map<String, Array<String>>();
        var _n183 = input.count();
        for (var _ in 0.._n183) {
            var _k184 = input.text();
            var _v185 = Array<String>();
            var _n186 = input.count();
            for (var _ in 0.._n186) {
                _v185.append(input.text());
            }
            _v182[_k184] = _v185;
        }
        _v179[_k181] = _v182;
    }
    var _f187 = _v179;
    var _f188 = _m_ExtensionScopes_read(input);
    var _v189 = HashSet<Loc>();
    var _n190 = input.count();
    for (var _ in 0.._n190) {
        _v189.insert(input.loc());
    }
    var _f191 = _v189;
    var _v192 = HashSet<Loc>();
    var _n193 = input.count();
    for (var _ in 0.._n193) {
        _v192.insert(input.loc());
    }
    var _f194 = _v192;
    var _v195 = Array<(Loc, String)>();
    var _n196 = input.count();
    for (var _ in 0.._n196) {
        var _t197 = input.loc();
        var _t198 = input.text();
        _v195.append((_t197, _t198));
    }
    var _f199 = _v195;
    var _v200 = Array<(Loc, String)>();
    var _n201 = input.count();
    for (var _ in 0.._n201) {
        var _t202 = input.loc();
        var _t203 = input.text();
        _v200.append((_t202, _t203));
    }
    var _f204 = _v200;
    var _v205 = Array<String>();
    var _n206 = input.count();
    for (var _ in 0.._n206) {
        _v205.append(input.text());
    }
    var _f207 = _v205;
    var _v208 = Array<bool>();
    var _n209 = input.count();
    for (var _ in 0.._n209) {
        _v208.append(input.flag());
    }
    var _f210 = _v208;
    var _v211 = HashMap<Loc, String>();
    var _n212 = input.count();
    for (var _ in 0.._n212) {
        var _k213 = input.loc();
        _v211[_k213] = input.text();
    }
    var _f214 = _v211;
    var _v215 = HashSet<Loc>();
    var _n216 = input.count();
    for (var _ in 0.._n216) {
        _v215.insert(input.loc());
    }
    var _f217 = _v215;
    var _f218 = _m_Templates_read(input);
    var _f219 = _m_Checked_read(input);
    var _v220 = HashMap<String, SpecRequest>();
    var _n221 = input.count();
    for (var _ in 0.._n221) {
        var _k222 = input.text();
        _v220[_k222] = _m_SpecRequest_read(input);
    }
    var _f223 = _v220;
    var _f224 = input.flag();
    var _v225 = Array<(Loc, String)>();
    var _n226 = input.count();
    for (var _ in 0.._n226) {
        var _t227 = input.loc();
        var _t228 = input.text();
        _v225.append((_t227, _t228));
    }
    var _f229 = _v225;
    var _v230 = HashMap<String, Array<bool>>();
    var _n231 = input.count();
    for (var _ in 0.._n231) {
        var _k232 = input.text();
        var _v233 = Array<bool>();
        var _n234 = input.count();
        for (var _ in 0.._n234) {
            _v233.append(input.flag());
        }
        _v230[_k232] = _v233;
    }
    var _f235 = _v230;
    var _f236 = input.flag();
    return Module(
        _f104,
        _f107,
        _f110,
        _f113,
        _f116,
        _f119,
        _f122,
        _f125,
        _f128,
        _f131,
        _f134,
        _f137,
        _f140,
        _f143,
        _f146,
        _f149,
        _f155,
        _f158,
        _f161,
        _f164,
        _f170,
        _f178,
        _f187,
        _f188,
        _f191,
        _f194,
        _f199,
        _f204,
        _f207,
        _f210,
        _f214,
        _f217,
        _f218,
        _f219,
        _f223,
        _f224,
        _f229,
        _f235,
        _f236
    );
}

_m_SpecRequest_write(out: RecordOut, value: SpecRequest) {
    out.text(value.by);
    out.loc(value.loc);
}

_m_SpecRequest_read(input: RecordIn): SpecRequest {
    var _f237 = input.text();
    var _f238 = input.loc();
    return SpecRequest(_f237, _f238);
}

_m_Checked_write(out: RecordOut, value: Checked) {
    var _keys240 = Array<(u8[], u8[], String)>();
    for (var _key239 in value.structs) {
        var _scratch241 = out.scratch();
        _scratch241.text(_key239);
        var _vscratch243 = out.scratch();
        _keys240.append((_scratch241.finish(), _vscratch243.finish(), _key239));
    }
    _keys240.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys240.count);
    for (var (_bytes242, _, _key239) in _keys240) {
        out.text(_key239);
    }
    var _keys245 = Array<(u8[], u8[], String)>();
    for (var _key244 in value.functions) {
        var _scratch246 = out.scratch();
        _scratch246.text(_key244);
        var _vscratch248 = out.scratch();
        _keys245.append((_scratch246.finish(), _vscratch248.finish(), _key244));
    }
    _keys245.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys245.count);
    for (var (_bytes247, _, _key244) in _keys245) {
        out.text(_key244);
    }
    var _keys250 = Array<(u8[], u8[], String)>();
    for (var _key249 in value.globals) {
        var _scratch251 = out.scratch();
        _scratch251.text(_key249);
        var _vscratch253 = out.scratch();
        _keys250.append((_scratch251.finish(), _vscratch253.finish(), _key249));
    }
    _keys250.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys250.count);
    for (var (_bytes252, _, _key249) in _keys250) {
        out.text(_key249);
    }
    out.unsigned(value.extensions);
    if (out.blank_locs) {
        write_interface_checked_summaries(out, value.summaries);
    } else {
        var _keys255 = Array<(u8[], u8[], String)>();
        for (var (_key254, _) in value.summaries) {
            var _scratch256 = out.scratch();
            _scratch256.text(_key254);
            var _vscratch258 = out.scratch();
            var (_t259, _t260) = value.summaries[_key254];
            _vscratch258.loc(_t259);
            _vscratch258.text(_t260);
            _keys255.append((_scratch256.finish(), _vscratch258.finish(), _key254));
        }
        _keys255.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys255.count);
        for (var (_bytes257, _, _key254) in _keys255) {
            out.text(_key254);
            var (_t261, _t262) = value.summaries[_key254];
            out.loc(_t261);
            out.text(_t262);
        }
    }
}

_m_Checked_read(input: RecordIn): Checked {
    var _v263 = HashSet<String>();
    var _n264 = input.count();
    for (var _ in 0.._n264) {
        _v263.insert(input.text());
    }
    var _f265 = _v263;
    var _v266 = HashSet<String>();
    var _n267 = input.count();
    for (var _ in 0.._n267) {
        _v266.insert(input.text());
    }
    var _f268 = _v266;
    var _v269 = HashSet<String>();
    var _n270 = input.count();
    for (var _ in 0.._n270) {
        _v269.insert(input.text());
    }
    var _f271 = _v269;
    var _f272 = input.unsigned();
    var _v273 = HashMap<String, (Loc, String)>();
    var _n274 = input.count();
    for (var _ in 0.._n274) {
        var _k275 = input.text();
        var _t276 = input.loc();
        var _t277 = input.text();
        _v273[_k275] = (_t276, _t277);
    }
    var _f278 = _v273;
    return Checked(_f265, _f268, _f271, _f272, _f278);
}

_m_Templates_write(out: RecordOut, value: Templates) {
    out.flag(value.frozen);
    out.unsigned(value.structs.count);
    for (var _item279 in value.structs) {
        _m_StructDef_write(out, _item279);
    }
    out.unsigned(value.functions.count);
    for (var _item280 in value.functions) {
        _m_FunctionDef_write(out, _item280);
    }
}

_m_Templates_read(input: RecordIn): Templates {
    var _f281 = input.flag();
    var _v282 = Array<StructDef>();
    var _n283 = input.count();
    for (var _ in 0.._n283) {
        _v282.append(_m_StructDef_read(input));
    }
    var _f284 = _v282;
    var _v285 = Array<FunctionDef>();
    var _n286 = input.count();
    for (var _ in 0.._n286) {
        _v285.append(_m_FunctionDef_read(input));
    }
    var _f287 = _v285;
    return Templates(_f281, _f284, _f287);
}

_m_FunctionDef_write(out: RecordOut, value: FunctionDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.generic_params.count);
    for (var _item288 in value.generic_params) {
        _m_GenericParam_write(out, _item288);
    }
    out.unsigned(value.parameters.count);
    for (var _item289 in value.parameters) {
        _m_VariableDef_write(out, _item289);
    }
    if (out.blank_bodies and !value.is_generic_func and value.generic_params.count == 0) {
        out.unsigned(0);
    } else {
        if (value.body.is_value()) {
            out.unsigned(1);
            _m_Block_write(out, value.body.value());
        } else {
            out.unsigned(0);
        }
    }
    if (value.parent.is_value()) {
        out.unsigned(1);
        out.text(value.parent.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.is_static);
    out.flag(value.is_indexer);
    out.flag(value.is_generic_func);
    out.unsigned(value.attributes.count);
    for (var _item290 in value.attributes) {
        _a_Attribute_write(out, _item290);
    }
    out.loc(value.loc);
    if (value.trait_default.is_value()) {
        out.unsigned(1);
        out.unsigned(value.trait_default.value().count);
        for (var _item291 in value.trait_default.value()) {
            out.text(_item291);
        }
    } else {
        out.unsigned(0);
    }
    out.loc(value.owner);
}

_m_FunctionDef_read(input: RecordIn): FunctionDef {
    var _f292 = input.text();
    var _f293 = _m_TypeName_read(input);
    var _v294 = Array<GenericParam>();
    var _n295 = input.count();
    for (var _ in 0.._n295) {
        _v294.append(_m_GenericParam_read(input));
    }
    var _f296 = _v294;
    var _v297 = Array<VariableDef>();
    var _n298 = input.count();
    for (var _ in 0.._n298) {
        _v297.append(_m_VariableDef_read(input));
    }
    var _f299 = _v297;
    var _o300 = Optional<Block>.Empty;
    if (input.unsigned() == 1) {
        _o300 = Optional<Block>.Value(_m_Block_read(input));
    }
    var _f301 = _o300;
    var _o302 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o302 = Optional<String>.Value(input.text());
    }
    var _f303 = _o302;
    var _f304 = input.flag();
    var _f305 = input.flag();
    var _f306 = input.flag();
    var _v307 = Array<ast.Attribute>();
    var _n308 = input.count();
    for (var _ in 0.._n308) {
        _v307.append(_a_Attribute_read(input));
    }
    var _f309 = _v307;
    var _f310 = input.loc();
    var _o311 = Optional<Array<String>>.Empty;
    if (input.unsigned() == 1) {
        var _v312 = Array<String>();
        var _n313 = input.count();
        for (var _ in 0.._n313) {
            _v312.append(input.text());
        }
        _o311 = Optional<Array<String>>.Value(_v312);
    }
    var _f314 = _o311;
    var _f315 = input.loc();
    return FunctionDef(_f292, _f293, _f296, _f299, _f301, _f303, _f304, _f305, _f306, _f309, _f310, _f314, _f315);
}

_a_Attribute_write(out: RecordOut, value: ast.Attribute) {
    _a_Expression_write(out, value.body);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Attribute_read(input: RecordIn): ast.Attribute {
    var _f316 = _a_Expression_read(input);
    var _s317 = input.unsigned();
    var _f318 = ast.Span(_s317, input.unsigned());
    var value = ast.Attribute(_f316, _f318);
    value.body = _f316;
    value.span = _f318;
    return value;
}

_a_Expression_write(out: RecordOut, value: ast.Expression) {
    match (value) {
        Literal(p0, p1) => {
            out.unsigned(0);
            _a_Literal_write(out, p0);
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
        SymbolRef(p0, p1) => {
            out.unsigned(1);
            out.text(p0);
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
        TypeLiteral(p0) => {
            out.unsigned(2);
            _a_TypeName_write(out, p0);
        }
        SizeOf(p0) => {
            out.unsigned(3);
            _a_TypeName_write(out, p0);
        }
        Unary(p0, p1, p2, p3) => {
            out.unsigned(4);
            out.text(p0);
            out.flag(p1);
            _a_Expression_write(out, p2);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        Cast(p0, p1, p2, p3, p4) => {
            out.unsigned(5);
            _a_Expression_write(out, p0);
            _a_TypeName_write(out, p1);
            out.unsigned(out.blank_locs ? 0 : p2.start);
            out.unsigned(out.blank_locs ? 0 : p2.end);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
            out.flag(p4);
        }
        Binary(p0, p1, p2, p3) => {
            out.unsigned(6);
            _a_Expression_write(out, p0);
            out.text(p1);
            _a_Expression_write(out, p2);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        Ternary(p0, p1, p2, p3) => {
            out.unsigned(7);
            _a_Expression_write(out, p0);
            _a_Expression_write(out, p1);
            _a_Expression_write(out, p2);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        Index(p0, p1, p2) => {
            out.unsigned(8);
            _a_Expression_write(out, p0);
            _a_Expression_write(out, p1);
            out.unsigned(out.blank_locs ? 0 : p2.start);
            out.unsigned(out.blank_locs ? 0 : p2.end);
        }
        MemberAccess(p0, p1, p2, p3) => {
            out.unsigned(9);
            _a_Expression_write(out, p0);
            out.text(p1);
            out.unsigned(out.blank_locs ? 0 : p2.start);
            out.unsigned(out.blank_locs ? 0 : p2.end);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        FunctionCall(p0, p1, p2) => {
            out.unsigned(10);
            _a_Expression_write(out, p0);
            out.unsigned(p1.count);
            for (var _item360 in p1) {
                _a_Expression_write(out, _item360);
            }
            out.unsigned(out.blank_locs ? 0 : p2.start);
            out.unsigned(out.blank_locs ? 0 : p2.end);
        }
        NamedArgument(p0, p1, p2, p3) => {
            out.unsigned(11);
            out.text(p0);
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
            _a_Expression_write(out, p2);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        Closure(p0) => {
            out.unsigned(12);
            _a_ClosureLiteral_write(out, p0);
        }
        Tuple(p0, p1, p2) => {
            out.unsigned(13);
            out.unsigned(p0.count);
            for (var _item373 in p0) {
                _a_Expression_write(out, _item373);
            }
            out.unsigned(p1.count);
            for (var _item377 in p1) {
                _a_Label_write(out, _item377);
            }
            out.unsigned(out.blank_locs ? 0 : p2.start);
            out.unsigned(out.blank_locs ? 0 : p2.end);
        }
        ArrayLiteral(p0, p1) => {
            out.unsigned(14);
            out.unsigned(p0.count);
            for (var _item383 in p0) {
                _a_Expression_write(out, _item383);
            }
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
        MapLiteral(p0, p1) => {
            out.unsigned(15);
            out.unsigned(p0.count);
            for (var _item389 in p0) {
                _a_MapEntry_write(out, _item389);
            }
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
        Match(p0) => {
            out.unsigned(16);
            _a_MatchExpression_write(out, p0);
        }
        Is(p0, p1, p2, p3) => {
            out.unsigned(17);
            _a_Expression_write(out, p0);
            _a_Pattern_write(out, p1);
            out.unsigned(out.blank_locs ? 0 : p2.start);
            out.unsigned(out.blank_locs ? 0 : p2.end);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        Interpolated(p0, p1) => {
            out.unsigned(18);
            out.unsigned(p0.count);
            for (var _item402 in p0) {
                _a_StringPart_write(out, _item402);
            }
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
        FormatString(p0, p1, p2, p3) => {
            out.unsigned(19);
            out.unsigned(p0.count);
            for (var _item408 in p0) {
                _a_StringPart_write(out, _item408);
            }
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
            out.unsigned(p2);
            out.unsigned(p3.count);
            for (var _item415 in p3) {
                out.unsigned(out.blank_locs ? 0 : _item415.start);
                out.unsigned(out.blank_locs ? 0 : _item415.end);
            }
        }
        Parenthesized(p0, p1) => {
            out.unsigned(20);
            _a_Expression_write(out, p0);
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
    }
}

_a_Expression_read(input: RecordIn): ast.Expression {
    var tag = input.unsigned();
    if (tag == 0) {
        var _f319 = _a_Literal_read(input);
        var _s320 = input.unsigned();
        var _f321 = ast.Span(_s320, input.unsigned());
        return ast.Expression.Literal(_f319, _f321);
    }
    if (tag == 1) {
        var _f322 = input.text();
        var _s323 = input.unsigned();
        var _f324 = ast.Span(_s323, input.unsigned());
        return ast.Expression.SymbolRef(_f322, _f324);
    }
    if (tag == 2) {
        var _f325 = _a_TypeName_read(input);
        return ast.Expression.TypeLiteral(_f325);
    }
    if (tag == 3) {
        var _f326 = _a_TypeName_read(input);
        return ast.Expression.SizeOf(_f326);
    }
    if (tag == 4) {
        var _f327 = input.text();
        var _f328 = input.flag();
        var _f329 = _a_Expression_read(input);
        var _s330 = input.unsigned();
        var _f331 = ast.Span(_s330, input.unsigned());
        return ast.Expression.Unary(_f327, _f328, _f329, _f331);
    }
    if (tag == 5) {
        var _f332 = _a_Expression_read(input);
        var _f333 = _a_TypeName_read(input);
        var _s334 = input.unsigned();
        var _f335 = ast.Span(_s334, input.unsigned());
        var _s336 = input.unsigned();
        var _f337 = ast.Span(_s336, input.unsigned());
        var _f338 = input.flag();
        return ast.Expression.Cast(_f332, _f333, _f335, _f337, _f338);
    }
    if (tag == 6) {
        var _f339 = _a_Expression_read(input);
        var _f340 = input.text();
        var _f341 = _a_Expression_read(input);
        var _s342 = input.unsigned();
        var _f343 = ast.Span(_s342, input.unsigned());
        return ast.Expression.Binary(_f339, _f340, _f341, _f343);
    }
    if (tag == 7) {
        var _f344 = _a_Expression_read(input);
        var _f345 = _a_Expression_read(input);
        var _f346 = _a_Expression_read(input);
        var _s347 = input.unsigned();
        var _f348 = ast.Span(_s347, input.unsigned());
        return ast.Expression.Ternary(_f344, _f345, _f346, _f348);
    }
    if (tag == 8) {
        var _f349 = _a_Expression_read(input);
        var _f350 = _a_Expression_read(input);
        var _s351 = input.unsigned();
        var _f352 = ast.Span(_s351, input.unsigned());
        return ast.Expression.Index(_f349, _f350, _f352);
    }
    if (tag == 9) {
        var _f353 = _a_Expression_read(input);
        var _f354 = input.text();
        var _s355 = input.unsigned();
        var _f356 = ast.Span(_s355, input.unsigned());
        var _s357 = input.unsigned();
        var _f358 = ast.Span(_s357, input.unsigned());
        return ast.Expression.MemberAccess(_f353, _f354, _f356, _f358);
    }
    if (tag == 10) {
        var _f359 = _a_Expression_read(input);
        var _v361 = Array<ast.Expression>();
        var _n362 = input.count();
        for (var _ in 0.._n362) {
            _v361.append(_a_Expression_read(input));
        }
        var _f363 = _v361;
        var _s364 = input.unsigned();
        var _f365 = ast.Span(_s364, input.unsigned());
        return ast.Expression.FunctionCall(_f359, _f363, _f365);
    }
    if (tag == 11) {
        var _f366 = input.text();
        var _s367 = input.unsigned();
        var _f368 = ast.Span(_s367, input.unsigned());
        var _f369 = _a_Expression_read(input);
        var _s370 = input.unsigned();
        var _f371 = ast.Span(_s370, input.unsigned());
        return ast.Expression.NamedArgument(_f366, _f368, _f369, _f371);
    }
    if (tag == 12) {
        var _f372 = _a_ClosureLiteral_read(input);
        return ast.Expression.Closure(_f372);
    }
    if (tag == 13) {
        var _v374 = Array<ast.Expression>();
        var _n375 = input.count();
        for (var _ in 0.._n375) {
            _v374.append(_a_Expression_read(input));
        }
        var _f376 = _v374;
        var _v378 = Array<ast.Label>();
        var _n379 = input.count();
        for (var _ in 0.._n379) {
            _v378.append(_a_Label_read(input));
        }
        var _f380 = _v378;
        var _s381 = input.unsigned();
        var _f382 = ast.Span(_s381, input.unsigned());
        return ast.Expression.Tuple(_f376, _f380, _f382);
    }
    if (tag == 14) {
        var _v384 = Array<ast.Expression>();
        var _n385 = input.count();
        for (var _ in 0.._n385) {
            _v384.append(_a_Expression_read(input));
        }
        var _f386 = _v384;
        var _s387 = input.unsigned();
        var _f388 = ast.Span(_s387, input.unsigned());
        return ast.Expression.ArrayLiteral(_f386, _f388);
    }
    if (tag == 15) {
        var _v390 = Array<ast.MapEntry>();
        var _n391 = input.count();
        for (var _ in 0.._n391) {
            _v390.append(_a_MapEntry_read(input));
        }
        var _f392 = _v390;
        var _s393 = input.unsigned();
        var _f394 = ast.Span(_s393, input.unsigned());
        return ast.Expression.MapLiteral(_f392, _f394);
    }
    if (tag == 16) {
        var _f395 = _a_MatchExpression_read(input);
        return ast.Expression.Match(_f395);
    }
    if (tag == 17) {
        var _f396 = _a_Expression_read(input);
        var _f397 = _a_Pattern_read(input);
        var _s398 = input.unsigned();
        var _f399 = ast.Span(_s398, input.unsigned());
        var _s400 = input.unsigned();
        var _f401 = ast.Span(_s400, input.unsigned());
        return ast.Expression.Is(_f396, _f397, _f399, _f401);
    }
    if (tag == 18) {
        var _v403 = Array<ast.StringPart>();
        var _n404 = input.count();
        for (var _ in 0.._n404) {
            _v403.append(_a_StringPart_read(input));
        }
        var _f405 = _v403;
        var _s406 = input.unsigned();
        var _f407 = ast.Span(_s406, input.unsigned());
        return ast.Expression.Interpolated(_f405, _f407);
    }
    if (tag == 19) {
        var _v409 = Array<ast.StringPart>();
        var _n410 = input.count();
        for (var _ in 0.._n410) {
            _v409.append(_a_StringPart_read(input));
        }
        var _f411 = _v409;
        var _s412 = input.unsigned();
        var _f413 = ast.Span(_s412, input.unsigned());
        var _f414 = input.unsigned();
        var _v416 = Array<ast.Span>();
        var _n417 = input.count();
        for (var _ in 0.._n417) {
            var _s418 = input.unsigned();
            _v416.append(ast.Span(_s418, input.unsigned()));
        }
        var _f419 = _v416;
        return ast.Expression.FormatString(_f411, _f413, _f414, _f419);
    }
    if (tag == 20) {
        var _f420 = _a_Expression_read(input);
        var _s421 = input.unsigned();
        var _f422 = ast.Span(_s421, input.unsigned());
        return ast.Expression.Parenthesized(_f420, _f422);
    }
    input.fail("Expression", tag);
    return _a_Expression_read(input);
}

_a_StringPart_write(out: RecordOut, value: ast.StringPart) {
    match (value) {
        Text(p0, p1) => {
            out.unsigned(0);
            out.text(p0);
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
        Hole(p0, p1, p2) => {
            out.unsigned(1);
            _a_Expression_write(out, p0);
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
            if (p2.is_value()) {
                out.unsigned(1);
                _a_FormatSpec_write(out, p2.value());
            } else {
                out.unsigned(0);
            }
        }
        Argument(p0, p1, p2, p3) => {
            out.unsigned(2);
            out.unsigned(p0);
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
            out.unsigned(out.blank_locs ? 0 : p2.start);
            out.unsigned(out.blank_locs ? 0 : p2.end);
            if (p3.is_value()) {
                out.unsigned(1);
                _a_FormatSpec_write(out, p3.value());
            } else {
                out.unsigned(0);
            }
        }
    }
}

_a_StringPart_read(input: RecordIn): ast.StringPart {
    var tag = input.unsigned();
    if (tag == 0) {
        var _f423 = input.text();
        var _s424 = input.unsigned();
        var _f425 = ast.Span(_s424, input.unsigned());
        return ast.StringPart.Text(_f423, _f425);
    }
    if (tag == 1) {
        var _f426 = _a_Expression_read(input);
        var _s427 = input.unsigned();
        var _f428 = ast.Span(_s427, input.unsigned());
        var _o429 = Optional<ast.FormatSpec>.Empty;
        if (input.unsigned() == 1) {
            _o429 = Optional<ast.FormatSpec>.Value(_a_FormatSpec_read(input));
        }
        var _f430 = _o429;
        return ast.StringPart.Hole(_f426, _f428, _f430);
    }
    if (tag == 2) {
        var _f431 = input.unsigned();
        var _s432 = input.unsigned();
        var _f433 = ast.Span(_s432, input.unsigned());
        var _s434 = input.unsigned();
        var _f435 = ast.Span(_s434, input.unsigned());
        var _o436 = Optional<ast.FormatSpec>.Empty;
        if (input.unsigned() == 1) {
            _o436 = Optional<ast.FormatSpec>.Value(_a_FormatSpec_read(input));
        }
        var _f437 = _o436;
        return ast.StringPart.Argument(_f431, _f433, _f435, _f437);
    }
    input.fail("StringPart", tag);
    return _a_StringPart_read(input);
}

_a_FormatSpec_write(out: RecordOut, value: ast.FormatSpec) {
    out.text(value.fill);
    out.signed(value.align as long);
    out.flag(value.has_align);
    if (value.plus.is_value()) {
        out.unsigned(1);
        out.unsigned(out.blank_locs ? 0 : value.plus.value().start);
        out.unsigned(out.blank_locs ? 0 : value.plus.value().end);
    } else {
        out.unsigned(0);
    }
    if (value.zero.is_value()) {
        out.unsigned(1);
        out.unsigned(out.blank_locs ? 0 : value.zero.value().start);
        out.unsigned(out.blank_locs ? 0 : value.zero.value().end);
    } else {
        out.unsigned(0);
    }
    out.signed(value.width as long);
    out.signed(value.precision as long);
    if (value.point.is_value()) {
        out.unsigned(1);
        out.unsigned(out.blank_locs ? 0 : value.point.value().start);
        out.unsigned(out.blank_locs ? 0 : value.point.value().end);
    } else {
        out.unsigned(0);
    }
    out.text(value.kind);
    out.unsigned(out.blank_locs ? 0 : value.kind_span.start);
    out.unsigned(out.blank_locs ? 0 : value.kind_span.end);
}

_a_FormatSpec_read(input: RecordIn): ast.FormatSpec {
    var _f438 = input.text();
    var _f439 = input.signed();
    var _f440 = input.flag();
    var _o441 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s442 = input.unsigned();
        _o441 = Optional<ast.Span>.Value(ast.Span(_s442, input.unsigned()));
    }
    var _f443 = _o441;
    var _o444 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s445 = input.unsigned();
        _o444 = Optional<ast.Span>.Value(ast.Span(_s445, input.unsigned()));
    }
    var _f446 = _o444;
    var _f447 = input.signed();
    var _f448 = input.signed();
    var _o449 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s450 = input.unsigned();
        _o449 = Optional<ast.Span>.Value(ast.Span(_s450, input.unsigned()));
    }
    var _f451 = _o449;
    var _f452 = input.text();
    var _s453 = input.unsigned();
    var _f454 = ast.Span(_s453, input.unsigned());
    var value = ast.FormatSpec();
    value.fill = _f438;
    value.align = _f439;
    value.has_align = _f440;
    value.plus = _f443;
    value.zero = _f446;
    value.width = _f447;
    value.precision = _f448;
    value.point = _f451;
    value.kind = _f452;
    value.kind_span = _f454;
    return value;
}

_a_Pattern_write(out: RecordOut, value: ast.Pattern) {
    if (value.literal.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.literal.value());
    } else {
        out.unsigned(0);
    }
    if (value.elements.is_value()) {
        out.unsigned(1);
        out.unsigned(value.elements.value().count);
        for (var _item455 in value.elements.value()) {
            _a_Pattern_write(out, _item455);
        }
    } else {
        out.unsigned(0);
    }
    if (value.qualifier.is_value()) {
        out.unsigned(1);
        _a_TypeName_write(out, value.qualifier.value());
    } else {
        out.unsigned(0);
    }
    out.text(value.case_name);
    out.unsigned(out.blank_locs ? 0 : value.case_span.start);
    out.unsigned(out.blank_locs ? 0 : value.case_span.end);
    if (value.bindings.is_value()) {
        out.unsigned(1);
        out.unsigned(value.bindings.value().count);
        for (var _item456 in value.bindings.value()) {
            _a_Pattern_write(out, _item456);
        }
    } else {
        out.unsigned(0);
    }
    if (value.range_end.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.range_end.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.range_inclusive);
    if (value.constant.is_value()) {
        out.unsigned(1);
        out.text(value.constant.value());
    } else {
        out.unsigned(0);
    }
    if (value.type_name.is_value()) {
        out.unsigned(1);
        _a_TypeName_write(out, value.type_name.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Pattern_read(input: RecordIn): ast.Pattern {
    var _o457 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o457 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f458 = _o457;
    var _o459 = Optional<Array<ast.Pattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v460 = Array<ast.Pattern>();
        var _n461 = input.count();
        for (var _ in 0.._n461) {
            _v460.append(_a_Pattern_read(input));
        }
        _o459 = Optional<Array<ast.Pattern>>.Value(_v460);
    }
    var _f462 = _o459;
    var _o463 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o463 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f464 = _o463;
    var _f465 = input.text();
    var _s466 = input.unsigned();
    var _f467 = ast.Span(_s466, input.unsigned());
    var _o468 = Optional<Array<ast.Pattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v469 = Array<ast.Pattern>();
        var _n470 = input.count();
        for (var _ in 0.._n470) {
            _v469.append(_a_Pattern_read(input));
        }
        _o468 = Optional<Array<ast.Pattern>>.Value(_v469);
    }
    var _f471 = _o468;
    var _o472 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o472 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f473 = _o472;
    var _f474 = input.flag();
    var _o475 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o475 = Optional<String>.Value(input.text());
    }
    var _f476 = _o475;
    var _o477 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o477 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f478 = _o477;
    var _s479 = input.unsigned();
    var _f480 = ast.Span(_s479, input.unsigned());
    var value = ast.Pattern();
    value.literal = _f458;
    value.elements = _f462;
    value.qualifier = _f464;
    value.case_name = _f465;
    value.case_span = _f467;
    value.bindings = _f471;
    value.range_end = _f473;
    value.range_inclusive = _f474;
    value.constant = _f476;
    value.type_name = _f478;
    value.span = _f480;
    return value;
}

_a_TypeName_write(out: RecordOut, value: ast.TypeName) {
    out.text(value.name);
    out.unsigned(value.generic_types.count);
    for (var _item481 in value.generic_types) {
        _a_TypeName_write(out, _item481);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.labels.count);
    for (var _item482 in value.labels) {
        out.text(_item482);
    }
}

_a_TypeName_read(input: RecordIn): ast.TypeName {
    var _f483 = input.text();
    var _v484 = Array<ast.TypeName>();
    var _n485 = input.count();
    for (var _ in 0.._n485) {
        _v484.append(_a_TypeName_read(input));
    }
    var _f486 = _v484;
    var _s487 = input.unsigned();
    var _f488 = ast.Span(_s487, input.unsigned());
    var _v489 = Array<String>();
    var _n490 = input.count();
    for (var _ in 0.._n490) {
        _v489.append(input.text());
    }
    var _f491 = _v489;
    var value = ast.TypeName();
    value.name = _f483;
    value.generic_types = _f486;
    value.span = _f488;
    value.labels = _f491;
    return value;
}

_a_MatchExpression_write(out: RecordOut, value: ast.MatchExpression) {
    _a_Expression_write(out, value.value);
    out.unsigned(value.arms.count);
    for (var _item492 in value.arms) {
        _a_MatchValueArm_write(out, _item492);
    }
    if (value.else_value.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.else_value.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(out.blank_locs ? 0 : value.else_span.start);
    out.unsigned(out.blank_locs ? 0 : value.else_span.end);
    out.unsigned(out.blank_locs ? 0 : value.keyword_span.start);
    out.unsigned(out.blank_locs ? 0 : value.keyword_span.end);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_MatchExpression_read(input: RecordIn): ast.MatchExpression {
    var _f493 = _a_Expression_read(input);
    var _v494 = Array<ast.MatchValueArm>();
    var _n495 = input.count();
    for (var _ in 0.._n495) {
        _v494.append(_a_MatchValueArm_read(input));
    }
    var _f496 = _v494;
    var _o497 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o497 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f498 = _o497;
    var _s499 = input.unsigned();
    var _f500 = ast.Span(_s499, input.unsigned());
    var _s501 = input.unsigned();
    var _f502 = ast.Span(_s501, input.unsigned());
    var _s503 = input.unsigned();
    var _f504 = ast.Span(_s503, input.unsigned());
    var value = ast.MatchExpression(_f493);
    value.value = _f493;
    value.arms = _f496;
    value.else_value = _f498;
    value.else_span = _f500;
    value.keyword_span = _f502;
    value.span = _f504;
    return value;
}

_a_MatchValueArm_write(out: RecordOut, value: ast.MatchValueArm) {
    out.unsigned(value.patterns.count);
    for (var _item505 in value.patterns) {
        _a_Pattern_write(out, _item505);
    }
    if (value.guard.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.guard.value());
    } else {
        out.unsigned(0);
    }
    _a_Expression_write(out, value.value);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_MatchValueArm_read(input: RecordIn): ast.MatchValueArm {
    var _v506 = Array<ast.Pattern>();
    var _n507 = input.count();
    for (var _ in 0.._n507) {
        _v506.append(_a_Pattern_read(input));
    }
    var _f508 = _v506;
    var _o509 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o509 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f510 = _o509;
    var _f511 = _a_Expression_read(input);
    var _s512 = input.unsigned();
    var _f513 = ast.Span(_s512, input.unsigned());
    var value = ast.MatchValueArm();
    value.patterns = _f508;
    value.guard = _f510;
    value.value = _f511;
    value.span = _f513;
    return value;
}

_a_MapEntry_write(out: RecordOut, value: ast.MapEntry) {
    _a_Expression_write(out, value.key);
    _a_Expression_write(out, value.value);
}

_a_MapEntry_read(input: RecordIn): ast.MapEntry {
    var _f514 = _a_Expression_read(input);
    var _f515 = _a_Expression_read(input);
    var value = ast.MapEntry(_f514, _f515);
    value.key = _f514;
    value.value = _f515;
    return value;
}

_a_Label_write(out: RecordOut, value: ast.Label) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Label_read(input: RecordIn): ast.Label {
    var _f516 = input.text();
    var _s517 = input.unsigned();
    var _f518 = ast.Span(_s517, input.unsigned());
    var value = ast.Label(_f516, _f518);
    value.name = _f516;
    value.span = _f518;
    return value;
}

_a_ClosureLiteral_write(out: RecordOut, value: ast.ClosureLiteral) {
    out.unsigned(value.parameters.count);
    for (var _item519 in value.parameters) {
        _a_VariableDecl_write(out, _item519);
    }
    _a_TypeName_write(out, value.return_type);
    _a_Block_write(out, value.body);
    out.flag(value.expression_body);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_ClosureLiteral_read(input: RecordIn): ast.ClosureLiteral {
    var _v520 = Array<ast.VariableDecl>();
    var _n521 = input.count();
    for (var _ in 0.._n521) {
        _v520.append(_a_VariableDecl_read(input));
    }
    var _f522 = _v520;
    var _f523 = _a_TypeName_read(input);
    var _f524 = _a_Block_read(input);
    var _f525 = input.flag();
    var _s526 = input.unsigned();
    var _f527 = ast.Span(_s526, input.unsigned());
    var value = ast.ClosureLiteral();
    value.parameters = _f522;
    value.return_type = _f523;
    value.body = _f524;
    value.expression_body = _f525;
    value.span = _f527;
    return value;
}

_a_Block_write(out: RecordOut, value: ast.Block) {
    out.unsigned(value.statements.count);
    for (var _item528 in value.statements) {
        _a_Statement_write(out, _item528);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item529 in value.attributes) {
        _a_Attribute_write(out, _item529);
    }
}

_a_Block_read(input: RecordIn): ast.Block {
    var _v530 = Array<ast.Statement>();
    var _n531 = input.count();
    for (var _ in 0.._n531) {
        _v530.append(_a_Statement_read(input));
    }
    var _f532 = _v530;
    var _s533 = input.unsigned();
    var _f534 = ast.Span(_s533, input.unsigned());
    var _v535 = Array<ast.Attribute>();
    var _n536 = input.count();
    for (var _ in 0.._n536) {
        _v535.append(_a_Attribute_read(input));
    }
    var _f537 = _v535;
    var value = ast.Block();
    value.statements = _f532;
    value.span = _f534;
    value.attributes = _f537;
    return value;
}

_a_Statement_write(out: RecordOut, value: ast.Statement) {
    match (value) {
        Expression(p0) => {
            out.unsigned(0);
            _a_Expression_write(out, p0);
        }
        Block(p0) => {
            out.unsigned(1);
            _a_Block_write(out, p0);
        }
        Declaration(p0) => {
            out.unsigned(2);
            _a_Declaration_write(out, p0);
        }
        Branch(p0, p1, p2, p3) => {
            out.unsigned(3);
            _a_Expression_write(out, p0);
            _a_Block_write(out, p1);
            if (p2.is_value()) {
                out.unsigned(1);
                _a_Block_write(out, p2.value());
            } else {
                out.unsigned(0);
            }
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        While(p0, p1, p2) => {
            out.unsigned(4);
            _a_Expression_write(out, p0);
            _a_Block_write(out, p1);
            out.unsigned(out.blank_locs ? 0 : p2.start);
            out.unsigned(out.blank_locs ? 0 : p2.end);
        }
        For(p0, p1, p2, p3, p4) => {
            out.unsigned(5);
            _a_VariableDecl_write(out, p0);
            out.unsigned(p1.count);
            for (var _item552 in p1) {
                _a_DestructureBinding_write(out, _item552);
            }
            _a_Expression_write(out, p2);
            _a_Block_write(out, p3);
            out.unsigned(out.blank_locs ? 0 : p4.start);
            out.unsigned(out.blank_locs ? 0 : p4.end);
        }
        With(p0, p1, p2, p3, p4) => {
            out.unsigned(6);
            if (p0.is_value()) {
                out.unsigned(1);
                _a_VariableDecl_write(out, p0.value());
            } else {
                out.unsigned(0);
            }
            _a_Expression_write(out, p1);
            _a_Block_write(out, p2);
            if (p3.is_value()) {
                out.unsigned(1);
                _a_Block_write(out, p3.value());
            } else {
                out.unsigned(0);
            }
            out.unsigned(out.blank_locs ? 0 : p4.start);
            out.unsigned(out.blank_locs ? 0 : p4.end);
        }
        Return(p0, p1) => {
            out.unsigned(7);
            if (p0.is_value()) {
                out.unsigned(1);
                _a_Expression_write(out, p0.value());
            } else {
                out.unsigned(0);
            }
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
        LoopBreak(p0, p1) => {
            out.unsigned(8);
            out.flag(p0);
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
        Destructure(p0, p1, p2, p3) => {
            out.unsigned(9);
            out.unsigned(p0.count);
            for (var _item575 in p0) {
                _a_DestructureBinding_write(out, _item575);
            }
            _a_Expression_write(out, p1);
            out.flag(p2);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        Match(p0) => {
            out.unsigned(10);
            _a_Match_write(out, p0);
        }
        Static(p0) => {
            out.unsigned(11);
            _a_StaticBlock_write(out, p0);
        }
    }
}

_a_Statement_read(input: RecordIn): ast.Statement {
    var tag = input.unsigned();
    if (tag == 0) {
        var _f538 = _a_Expression_read(input);
        return ast.Statement.Expression(_f538);
    }
    if (tag == 1) {
        var _f539 = _a_Block_read(input);
        return ast.Statement.Block(_f539);
    }
    if (tag == 2) {
        var _f540 = _a_Declaration_read(input);
        return ast.Statement.Declaration(_f540);
    }
    if (tag == 3) {
        var _f541 = _a_Expression_read(input);
        var _f542 = _a_Block_read(input);
        var _o543 = Optional<ast.Block>.Empty;
        if (input.unsigned() == 1) {
            _o543 = Optional<ast.Block>.Value(_a_Block_read(input));
        }
        var _f544 = _o543;
        var _s545 = input.unsigned();
        var _f546 = ast.Span(_s545, input.unsigned());
        return ast.Statement.Branch(_f541, _f542, _f544, _f546);
    }
    if (tag == 4) {
        var _f547 = _a_Expression_read(input);
        var _f548 = _a_Block_read(input);
        var _s549 = input.unsigned();
        var _f550 = ast.Span(_s549, input.unsigned());
        return ast.Statement.While(_f547, _f548, _f550);
    }
    if (tag == 5) {
        var _f551 = _a_VariableDecl_read(input);
        var _v553 = Array<ast.DestructureBinding>();
        var _n554 = input.count();
        for (var _ in 0.._n554) {
            _v553.append(_a_DestructureBinding_read(input));
        }
        var _f555 = _v553;
        var _f556 = _a_Expression_read(input);
        var _f557 = _a_Block_read(input);
        var _s558 = input.unsigned();
        var _f559 = ast.Span(_s558, input.unsigned());
        return ast.Statement.For(_f551, _f555, _f556, _f557, _f559);
    }
    if (tag == 6) {
        var _o560 = Optional<ast.VariableDecl>.Empty;
        if (input.unsigned() == 1) {
            _o560 = Optional<ast.VariableDecl>.Value(_a_VariableDecl_read(input));
        }
        var _f561 = _o560;
        var _f562 = _a_Expression_read(input);
        var _f563 = _a_Block_read(input);
        var _o564 = Optional<ast.Block>.Empty;
        if (input.unsigned() == 1) {
            _o564 = Optional<ast.Block>.Value(_a_Block_read(input));
        }
        var _f565 = _o564;
        var _s566 = input.unsigned();
        var _f567 = ast.Span(_s566, input.unsigned());
        return ast.Statement.With(_f561, _f562, _f563, _f565, _f567);
    }
    if (tag == 7) {
        var _o568 = Optional<ast.Expression>.Empty;
        if (input.unsigned() == 1) {
            _o568 = Optional<ast.Expression>.Value(_a_Expression_read(input));
        }
        var _f569 = _o568;
        var _s570 = input.unsigned();
        var _f571 = ast.Span(_s570, input.unsigned());
        return ast.Statement.Return(_f569, _f571);
    }
    if (tag == 8) {
        var _f572 = input.flag();
        var _s573 = input.unsigned();
        var _f574 = ast.Span(_s573, input.unsigned());
        return ast.Statement.LoopBreak(_f572, _f574);
    }
    if (tag == 9) {
        var _v576 = Array<ast.DestructureBinding>();
        var _n577 = input.count();
        for (var _ in 0.._n577) {
            _v576.append(_a_DestructureBinding_read(input));
        }
        var _f578 = _v576;
        var _f579 = _a_Expression_read(input);
        var _f580 = input.flag();
        var _s581 = input.unsigned();
        var _f582 = ast.Span(_s581, input.unsigned());
        return ast.Statement.Destructure(_f578, _f579, _f580, _f582);
    }
    if (tag == 10) {
        var _f583 = _a_Match_read(input);
        return ast.Statement.Match(_f583);
    }
    if (tag == 11) {
        var _f584 = _a_StaticBlock_read(input);
        return ast.Statement.Static(_f584);
    }
    input.fail("Statement", tag);
    return _a_Statement_read(input);
}

_a_StaticBlock_write(out: RecordOut, value: ast.StaticBlock) {
    out.unsigned(value.captures.count);
    for (var _item585 in value.captures) {
        _a_Label_write(out, _item585);
    }
    out.unsigned(value.written_captures.count);
    for (var _item586 in value.written_captures) {
        _a_Expression_write(out, _item586);
    }
    _a_Block_write(out, value.block);
    out.unsigned(out.blank_locs ? 0 : value.keyword_span.start);
    out.unsigned(out.blank_locs ? 0 : value.keyword_span.end);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item587 in value.attributes) {
        _a_Attribute_write(out, _item587);
    }
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_StaticBlock_read(input: RecordIn): ast.StaticBlock {
    var _v588 = Array<ast.Label>();
    var _n589 = input.count();
    for (var _ in 0.._n589) {
        _v588.append(_a_Label_read(input));
    }
    var _f590 = _v588;
    var _v591 = Array<ast.Expression>();
    var _n592 = input.count();
    for (var _ in 0.._n592) {
        _v591.append(_a_Expression_read(input));
    }
    var _f593 = _v591;
    var _f594 = _a_Block_read(input);
    var _s595 = input.unsigned();
    var _f596 = ast.Span(_s595, input.unsigned());
    var _s597 = input.unsigned();
    var _f598 = ast.Span(_s597, input.unsigned());
    var _v599 = Array<ast.Attribute>();
    var _n600 = input.count();
    for (var _ in 0.._n600) {
        _v599.append(_a_Attribute_read(input));
    }
    var _f601 = _v599;
    var _f602 = input.flag();
    var _f603 = input.flag();
    var value = ast.StaticBlock();
    value.captures = _f590;
    value.written_captures = _f593;
    value.block = _f594;
    value.keyword_span = _f596;
    value.span = _f598;
    value.attributes = _f601;
    value.is_exported = _f602;
    value.is_private = _f603;
    return value;
}

_a_Match_write(out: RecordOut, value: ast.Match) {
    _a_Expression_write(out, value.value);
    out.unsigned(value.arms.count);
    for (var _item604 in value.arms) {
        _a_MatchArm_write(out, _item604);
    }
    if (value.else_block.is_value()) {
        out.unsigned(1);
        _a_Block_write(out, value.else_block.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(out.blank_locs ? 0 : value.else_span.start);
    out.unsigned(out.blank_locs ? 0 : value.else_span.end);
    out.unsigned(out.blank_locs ? 0 : value.keyword_span.start);
    out.unsigned(out.blank_locs ? 0 : value.keyword_span.end);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Match_read(input: RecordIn): ast.Match {
    var _f605 = _a_Expression_read(input);
    var _v606 = Array<ast.MatchArm>();
    var _n607 = input.count();
    for (var _ in 0.._n607) {
        _v606.append(_a_MatchArm_read(input));
    }
    var _f608 = _v606;
    var _o609 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o609 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f610 = _o609;
    var _s611 = input.unsigned();
    var _f612 = ast.Span(_s611, input.unsigned());
    var _s613 = input.unsigned();
    var _f614 = ast.Span(_s613, input.unsigned());
    var _s615 = input.unsigned();
    var _f616 = ast.Span(_s615, input.unsigned());
    var value = ast.Match(_f605);
    value.value = _f605;
    value.arms = _f608;
    value.else_block = _f610;
    value.else_span = _f612;
    value.keyword_span = _f614;
    value.span = _f616;
    return value;
}

_a_MatchArm_write(out: RecordOut, value: ast.MatchArm) {
    out.unsigned(value.patterns.count);
    for (var _item617 in value.patterns) {
        _a_Pattern_write(out, _item617);
    }
    if (value.guard.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.guard.value());
    } else {
        out.unsigned(0);
    }
    _a_Block_write(out, value.body);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_MatchArm_read(input: RecordIn): ast.MatchArm {
    var _v618 = Array<ast.Pattern>();
    var _n619 = input.count();
    for (var _ in 0.._n619) {
        _v618.append(_a_Pattern_read(input));
    }
    var _f620 = _v618;
    var _o621 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o621 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f622 = _o621;
    var _f623 = _a_Block_read(input);
    var _s624 = input.unsigned();
    var _f625 = ast.Span(_s624, input.unsigned());
    var value = ast.MatchArm();
    value.patterns = _f620;
    value.guard = _f622;
    value.body = _f623;
    value.span = _f625;
    return value;
}

_a_DestructureBinding_write(out: RecordOut, value: ast.DestructureBinding) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    _a_TypeName_write(out, value.type_name);
    out.unsigned(value.nested.count);
    for (var _item626 in value.nested) {
        _a_DestructureBinding_write(out, _item626);
    }
}

_a_DestructureBinding_read(input: RecordIn): ast.DestructureBinding {
    var _f627 = input.text();
    var _s628 = input.unsigned();
    var _f629 = ast.Span(_s628, input.unsigned());
    var _f630 = _a_TypeName_read(input);
    var _v631 = Array<ast.DestructureBinding>();
    var _n632 = input.count();
    for (var _ in 0.._n632) {
        _v631.append(_a_DestructureBinding_read(input));
    }
    var _f633 = _v631;
    var value = ast.DestructureBinding();
    value.name = _f627;
    value.name_span = _f629;
    value.type_name = _f630;
    value.nested = _f633;
    return value;
}

_a_VariableDecl_write(out: RecordOut, value: ast.VariableDecl) {
    out.unsigned(value.attributes.count);
    for (var _item634 in value.attributes) {
        _a_Attribute_write(out, _item634);
    }
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    _a_TypeName_write(out, value.type_name);
    if (value.default_value.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.default_value.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.is_const);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_VariableDecl_read(input: RecordIn): ast.VariableDecl {
    var _v635 = Array<ast.Attribute>();
    var _n636 = input.count();
    for (var _ in 0.._n636) {
        _v635.append(_a_Attribute_read(input));
    }
    var _f637 = _v635;
    var _f638 = input.text();
    var _s639 = input.unsigned();
    var _f640 = ast.Span(_s639, input.unsigned());
    var _f641 = _a_TypeName_read(input);
    var _o642 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o642 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f643 = _o642;
    var _f644 = input.flag();
    var _s645 = input.unsigned();
    var _f646 = ast.Span(_s645, input.unsigned());
    var _f647 = input.flag();
    var _f648 = input.flag();
    var value = ast.VariableDecl();
    value.attributes = _f637;
    value.name = _f638;
    value.name_span = _f640;
    value.type_name = _f641;
    value.default_value = _f643;
    value.is_const = _f644;
    value.span = _f646;
    value.is_exported = _f647;
    value.is_private = _f648;
    return value;
}

_a_Declaration_write(out: RecordOut, value: ast.Declaration) {
    match (value) {
        Variable(p0) => {
            out.unsigned(0);
            _a_VariableDecl_write(out, p0);
        }
        Function(p0) => {
            out.unsigned(1);
            _a_FunctionDecl_write(out, p0);
        }
        Struct(p0) => {
            out.unsigned(2);
            _a_StructDecl_write(out, p0);
        }
        Trait(p0) => {
            out.unsigned(3);
            _a_TraitDecl_write(out, p0);
        }
        Extend(p0) => {
            out.unsigned(4);
            _a_ExtendDecl_write(out, p0);
        }
        TypeAlias(p0) => {
            out.unsigned(5);
            _a_TypeAliasDecl_write(out, p0);
        }
        Static(p0) => {
            out.unsigned(6);
            _a_StaticBlock_write(out, p0);
        }
    }
}

_a_Declaration_read(input: RecordIn): ast.Declaration {
    var tag = input.unsigned();
    if (tag == 0) {
        var _f649 = _a_VariableDecl_read(input);
        return ast.Declaration.Variable(_f649);
    }
    if (tag == 1) {
        var _f650 = _a_FunctionDecl_read(input);
        return ast.Declaration.Function(_f650);
    }
    if (tag == 2) {
        var _f651 = _a_StructDecl_read(input);
        return ast.Declaration.Struct(_f651);
    }
    if (tag == 3) {
        var _f652 = _a_TraitDecl_read(input);
        return ast.Declaration.Trait(_f652);
    }
    if (tag == 4) {
        var _f653 = _a_ExtendDecl_read(input);
        return ast.Declaration.Extend(_f653);
    }
    if (tag == 5) {
        var _f654 = _a_TypeAliasDecl_read(input);
        return ast.Declaration.TypeAlias(_f654);
    }
    if (tag == 6) {
        var _f655 = _a_StaticBlock_read(input);
        return ast.Declaration.Static(_f655);
    }
    input.fail("Declaration", tag);
    return _a_Declaration_read(input);
}

_a_TypeAliasDecl_write(out: RecordOut, value: ast.TypeAliasDecl) {
    out.unsigned(value.attributes.count);
    for (var _item656 in value.attributes) {
        _a_Attribute_write(out, _item656);
    }
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item657 in value.generic_params) {
        _a_GenericParam_write(out, _item657);
    }
    _a_TypeName_write(out, value.target);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_TypeAliasDecl_read(input: RecordIn): ast.TypeAliasDecl {
    var _v658 = Array<ast.Attribute>();
    var _n659 = input.count();
    for (var _ in 0.._n659) {
        _v658.append(_a_Attribute_read(input));
    }
    var _f660 = _v658;
    var _f661 = input.text();
    var _s662 = input.unsigned();
    var _f663 = ast.Span(_s662, input.unsigned());
    var _v664 = Array<ast.GenericParam>();
    var _n665 = input.count();
    for (var _ in 0.._n665) {
        _v664.append(_a_GenericParam_read(input));
    }
    var _f666 = _v664;
    var _f667 = _a_TypeName_read(input);
    var _s668 = input.unsigned();
    var _f669 = ast.Span(_s668, input.unsigned());
    var _f670 = input.flag();
    var _f671 = input.flag();
    var value = ast.TypeAliasDecl();
    value.attributes = _f660;
    value.name = _f661;
    value.name_span = _f663;
    value.generic_params = _f666;
    value.target = _f667;
    value.span = _f669;
    value.is_exported = _f670;
    value.is_private = _f671;
    return value;
}

_a_GenericParam_write(out: RecordOut, value: ast.GenericParam) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.bounds.count);
    for (var _item672 in value.bounds) {
        _a_TypeName_write(out, _item672);
    }
    if (value.default.is_value()) {
        out.unsigned(1);
        _a_TypeName_write(out, value.default.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.is_argument);
}

_a_GenericParam_read(input: RecordIn): ast.GenericParam {
    var _f673 = input.text();
    var _s674 = input.unsigned();
    var _f675 = ast.Span(_s674, input.unsigned());
    var _v676 = Array<ast.TypeName>();
    var _n677 = input.count();
    for (var _ in 0.._n677) {
        _v676.append(_a_TypeName_read(input));
    }
    var _f678 = _v676;
    var _o679 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o679 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f680 = _o679;
    var _f681 = input.flag();
    var value = ast.GenericParam(_f673, _f675);
    value.name = _f673;
    value.name_span = _f675;
    value.bounds = _f678;
    value.default = _f680;
    value.is_argument = _f681;
    return value;
}

_a_ExtendDecl_write(out: RecordOut, value: ast.ExtendDecl) {
    out.unsigned(value.attributes.count);
    for (var _item682 in value.attributes) {
        _a_Attribute_write(out, _item682);
    }
    _a_TypeName_write(out, value.target);
    out.unsigned(value.target_bounds.count);
    for (var _item683 in value.target_bounds) {
        out.unsigned(_item683.count);
        for (var _item684 in _item683) {
            _a_TypeName_write(out, _item684);
        }
    }
    out.unsigned(value.traits.count);
    for (var _item685 in value.traits) {
        _a_TypeName_write(out, _item685);
    }
    out.unsigned(value.methods.count);
    for (var _item686 in value.methods) {
        _a_FunctionDecl_write(out, _item686);
    }
    out.unsigned(value.properties.count);
    for (var _item687 in value.properties) {
        _a_PropertyDecl_write(out, _item687);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_ExtendDecl_read(input: RecordIn): ast.ExtendDecl {
    var _v688 = Array<ast.Attribute>();
    var _n689 = input.count();
    for (var _ in 0.._n689) {
        _v688.append(_a_Attribute_read(input));
    }
    var _f690 = _v688;
    var _f691 = _a_TypeName_read(input);
    var _v692 = Array<Array<ast.TypeName>>();
    var _n693 = input.count();
    for (var _ in 0.._n693) {
        var _v694 = Array<ast.TypeName>();
        var _n695 = input.count();
        for (var _ in 0.._n695) {
            _v694.append(_a_TypeName_read(input));
        }
        _v692.append(_v694);
    }
    var _f696 = _v692;
    var _v697 = Array<ast.TypeName>();
    var _n698 = input.count();
    for (var _ in 0.._n698) {
        _v697.append(_a_TypeName_read(input));
    }
    var _f699 = _v697;
    var _v700 = Array<ast.FunctionDecl>();
    var _n701 = input.count();
    for (var _ in 0.._n701) {
        _v700.append(_a_FunctionDecl_read(input));
    }
    var _f702 = _v700;
    var _v703 = Array<ast.PropertyDecl>();
    var _n704 = input.count();
    for (var _ in 0.._n704) {
        _v703.append(_a_PropertyDecl_read(input));
    }
    var _f705 = _v703;
    var _s706 = input.unsigned();
    var _f707 = ast.Span(_s706, input.unsigned());
    var _f708 = input.flag();
    var _f709 = input.flag();
    var value = ast.ExtendDecl();
    value.attributes = _f690;
    value.target = _f691;
    value.target_bounds = _f696;
    value.traits = _f699;
    value.methods = _f702;
    value.properties = _f705;
    value.span = _f707;
    value.is_exported = _f708;
    value.is_private = _f709;
    return value;
}

_a_PropertyDecl_write(out: RecordOut, value: ast.PropertyDecl) {
    out.unsigned(value.attributes.count);
    for (var _item710 in value.attributes) {
        _a_Attribute_write(out, _item710);
    }
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    _a_TypeName_write(out, value.type_name);
    if (value.default_value.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.default_value.value());
    } else {
        out.unsigned(0);
    }
    if (value.getter.is_value()) {
        out.unsigned(1);
        _a_Accessor_write(out, value.getter.value());
    } else {
        out.unsigned(0);
    }
    if (value.setter.is_value()) {
        out.unsigned(1);
        _a_Accessor_write(out, value.setter.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_PropertyDecl_read(input: RecordIn): ast.PropertyDecl {
    var _v711 = Array<ast.Attribute>();
    var _n712 = input.count();
    for (var _ in 0.._n712) {
        _v711.append(_a_Attribute_read(input));
    }
    var _f713 = _v711;
    var _f714 = input.text();
    var _s715 = input.unsigned();
    var _f716 = ast.Span(_s715, input.unsigned());
    var _f717 = _a_TypeName_read(input);
    var _o718 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o718 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f719 = _o718;
    var _o720 = Optional<ast.Accessor>.Empty;
    if (input.unsigned() == 1) {
        _o720 = Optional<ast.Accessor>.Value(_a_Accessor_read(input));
    }
    var _f721 = _o720;
    var _o722 = Optional<ast.Accessor>.Empty;
    if (input.unsigned() == 1) {
        _o722 = Optional<ast.Accessor>.Value(_a_Accessor_read(input));
    }
    var _f723 = _o722;
    var _s724 = input.unsigned();
    var _f725 = ast.Span(_s724, input.unsigned());
    var value = ast.PropertyDecl();
    value.attributes = _f713;
    value.name = _f714;
    value.name_span = _f716;
    value.type_name = _f717;
    value.default_value = _f719;
    value.getter = _f721;
    value.setter = _f723;
    value.span = _f725;
    return value;
}

_a_Accessor_write(out: RecordOut, value: ast.Accessor) {
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    _a_FunctionDecl_write(out, value.function);
}

_a_Accessor_read(input: RecordIn): ast.Accessor {
    var _s726 = input.unsigned();
    var _f727 = ast.Span(_s726, input.unsigned());
    var _f728 = _a_FunctionDecl_read(input);
    var value = ast.Accessor(_f727, _f728);
    value.span = _f727;
    value.function = _f728;
    return value;
}

_a_FunctionDecl_write(out: RecordOut, value: ast.FunctionDecl) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item729 in value.generic_params) {
        _a_GenericParam_write(out, _item729);
    }
    _a_TypeName_write(out, value.return_type);
    out.unsigned(value.parameters.count);
    for (var _item730 in value.parameters) {
        _a_VariableDecl_write(out, _item730);
    }
    out.flag(value.external);
    if (value.body.is_value()) {
        out.unsigned(1);
        _a_Block_write(out, value.body.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.is_static);
    out.flag(value.is_indexer);
    out.flag(value.is_variadic);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item731 in value.attributes) {
        _a_Attribute_write(out, _item731);
    }
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_FunctionDecl_read(input: RecordIn): ast.FunctionDecl {
    var _f732 = input.text();
    var _s733 = input.unsigned();
    var _f734 = ast.Span(_s733, input.unsigned());
    var _v735 = Array<ast.GenericParam>();
    var _n736 = input.count();
    for (var _ in 0.._n736) {
        _v735.append(_a_GenericParam_read(input));
    }
    var _f737 = _v735;
    var _f738 = _a_TypeName_read(input);
    var _v739 = Array<ast.VariableDecl>();
    var _n740 = input.count();
    for (var _ in 0.._n740) {
        _v739.append(_a_VariableDecl_read(input));
    }
    var _f741 = _v739;
    var _f742 = input.flag();
    var _o743 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o743 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f744 = _o743;
    var _f745 = input.flag();
    var _f746 = input.flag();
    var _f747 = input.flag();
    var _s748 = input.unsigned();
    var _f749 = ast.Span(_s748, input.unsigned());
    var _v750 = Array<ast.Attribute>();
    var _n751 = input.count();
    for (var _ in 0.._n751) {
        _v750.append(_a_Attribute_read(input));
    }
    var _f752 = _v750;
    var _f753 = input.flag();
    var _f754 = input.flag();
    var value = ast.FunctionDecl();
    value.name = _f732;
    value.name_span = _f734;
    value.generic_params = _f737;
    value.return_type = _f738;
    value.parameters = _f741;
    value.external = _f742;
    value.body = _f744;
    value.is_static = _f745;
    value.is_indexer = _f746;
    value.is_variadic = _f747;
    value.span = _f749;
    value.attributes = _f752;
    value.is_exported = _f753;
    value.is_private = _f754;
    return value;
}

_a_TraitDecl_write(out: RecordOut, value: ast.TraitDecl) {
    out.unsigned(value.attributes.count);
    for (var _item755 in value.attributes) {
        _a_Attribute_write(out, _item755);
    }
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item756 in value.generic_params) {
        _a_GenericParam_write(out, _item756);
    }
    out.unsigned(value.methods.count);
    for (var _item757 in value.methods) {
        _a_FunctionDecl_write(out, _item757);
    }
    out.unsigned(value.properties.count);
    for (var _item758 in value.properties) {
        _a_PropertyDecl_write(out, _item758);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_TraitDecl_read(input: RecordIn): ast.TraitDecl {
    var _v759 = Array<ast.Attribute>();
    var _n760 = input.count();
    for (var _ in 0.._n760) {
        _v759.append(_a_Attribute_read(input));
    }
    var _f761 = _v759;
    var _f762 = input.text();
    var _s763 = input.unsigned();
    var _f764 = ast.Span(_s763, input.unsigned());
    var _v765 = Array<ast.GenericParam>();
    var _n766 = input.count();
    for (var _ in 0.._n766) {
        _v765.append(_a_GenericParam_read(input));
    }
    var _f767 = _v765;
    var _v768 = Array<ast.FunctionDecl>();
    var _n769 = input.count();
    for (var _ in 0.._n769) {
        _v768.append(_a_FunctionDecl_read(input));
    }
    var _f770 = _v768;
    var _v771 = Array<ast.PropertyDecl>();
    var _n772 = input.count();
    for (var _ in 0.._n772) {
        _v771.append(_a_PropertyDecl_read(input));
    }
    var _f773 = _v771;
    var _s774 = input.unsigned();
    var _f775 = ast.Span(_s774, input.unsigned());
    var _f776 = input.flag();
    var _f777 = input.flag();
    var value = ast.TraitDecl();
    value.attributes = _f761;
    value.name = _f762;
    value.name_span = _f764;
    value.generic_params = _f767;
    value.methods = _f770;
    value.properties = _f773;
    value.span = _f775;
    value.is_exported = _f776;
    value.is_private = _f777;
    return value;
}

_a_StructDecl_write(out: RecordOut, value: ast.StructDecl) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item778 in value.generic_params) {
        _a_GenericParam_write(out, _item778);
    }
    out.unsigned(value.fields.count);
    for (var _item779 in value.fields) {
        _a_VariableDecl_write(out, _item779);
    }
    out.unsigned(value.properties.count);
    for (var _item780 in value.properties) {
        _a_PropertyDecl_write(out, _item780);
    }
    out.unsigned(value.methods.count);
    for (var _item781 in value.methods) {
        _a_FunctionDecl_write(out, _item781);
    }
    out.unsigned(value.constructors.count);
    for (var _item782 in value.constructors) {
        _a_FunctionDecl_write(out, _item782);
    }
    if (value.destructor.is_value()) {
        out.unsigned(1);
        _a_Block_write(out, value.destructor.value());
    } else {
        out.unsigned(0);
    }
    if (value.destruct_span.is_value()) {
        out.unsigned(1);
        out.unsigned(out.blank_locs ? 0 : value.destruct_span.value().start);
        out.unsigned(out.blank_locs ? 0 : value.destruct_span.value().end);
    } else {
        out.unsigned(0);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item783 in value.attributes) {
        _a_Attribute_write(out, _item783);
    }
    out.flag(value.is_exported);
    out.flag(value.is_private);
    if (value.enumeration.is_value()) {
        out.unsigned(1);
        _a_EnumBody_write(out, value.enumeration.value());
    } else {
        out.unsigned(0);
    }
}

_a_StructDecl_read(input: RecordIn): ast.StructDecl {
    var _f784 = input.text();
    var _s785 = input.unsigned();
    var _f786 = ast.Span(_s785, input.unsigned());
    var _v787 = Array<ast.GenericParam>();
    var _n788 = input.count();
    for (var _ in 0.._n788) {
        _v787.append(_a_GenericParam_read(input));
    }
    var _f789 = _v787;
    var _v790 = Array<ast.VariableDecl>();
    var _n791 = input.count();
    for (var _ in 0.._n791) {
        _v790.append(_a_VariableDecl_read(input));
    }
    var _f792 = _v790;
    var _v793 = Array<ast.PropertyDecl>();
    var _n794 = input.count();
    for (var _ in 0.._n794) {
        _v793.append(_a_PropertyDecl_read(input));
    }
    var _f795 = _v793;
    var _v796 = Array<ast.FunctionDecl>();
    var _n797 = input.count();
    for (var _ in 0.._n797) {
        _v796.append(_a_FunctionDecl_read(input));
    }
    var _f798 = _v796;
    var _v799 = Array<ast.FunctionDecl>();
    var _n800 = input.count();
    for (var _ in 0.._n800) {
        _v799.append(_a_FunctionDecl_read(input));
    }
    var _f801 = _v799;
    var _o802 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o802 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f803 = _o802;
    var _o804 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s805 = input.unsigned();
        _o804 = Optional<ast.Span>.Value(ast.Span(_s805, input.unsigned()));
    }
    var _f806 = _o804;
    var _s807 = input.unsigned();
    var _f808 = ast.Span(_s807, input.unsigned());
    var _v809 = Array<ast.Attribute>();
    var _n810 = input.count();
    for (var _ in 0.._n810) {
        _v809.append(_a_Attribute_read(input));
    }
    var _f811 = _v809;
    var _f812 = input.flag();
    var _f813 = input.flag();
    var _o814 = Optional<ast.EnumBody>.Empty;
    if (input.unsigned() == 1) {
        _o814 = Optional<ast.EnumBody>.Value(_a_EnumBody_read(input));
    }
    var _f815 = _o814;
    var value = ast.StructDecl();
    value.name = _f784;
    value.name_span = _f786;
    value.generic_params = _f789;
    value.fields = _f792;
    value.properties = _f795;
    value.methods = _f798;
    value.constructors = _f801;
    value.destructor = _f803;
    value.destruct_span = _f806;
    value.span = _f808;
    value.attributes = _f811;
    value.is_exported = _f812;
    value.is_private = _f813;
    value.enumeration = _f815;
    return value;
}

_a_EnumBody_write(out: RecordOut, value: ast.EnumBody) {
    if (value.representation.is_value()) {
        out.unsigned(1);
        _a_TypeName_write(out, value.representation.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.cases.count);
    for (var _item816 in value.cases) {
        _a_EnumCase_write(out, _item816);
    }
}

_a_EnumBody_read(input: RecordIn): ast.EnumBody {
    var _o817 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o817 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f818 = _o817;
    var _v819 = Array<ast.EnumCase>();
    var _n820 = input.count();
    for (var _ in 0.._n820) {
        _v819.append(_a_EnumCase_read(input));
    }
    var _f821 = _v819;
    var value = ast.EnumBody();
    value.representation = _f818;
    value.cases = _f821;
    return value;
}

_a_EnumCase_write(out: RecordOut, value: ast.EnumCase) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    if (value.value.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.value.value());
    } else {
        out.unsigned(0);
    }
    if (value.payload.is_value()) {
        out.unsigned(1);
        out.unsigned(value.payload.value().count);
        for (var _item822 in value.payload.value()) {
            _a_VariableDecl_write(out, _item822);
        }
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.attributes.count);
    for (var _item823 in value.attributes) {
        _a_Attribute_write(out, _item823);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_EnumCase_read(input: RecordIn): ast.EnumCase {
    var _f824 = input.text();
    var _s825 = input.unsigned();
    var _f826 = ast.Span(_s825, input.unsigned());
    var _o827 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o827 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f828 = _o827;
    var _o829 = Optional<Array<ast.VariableDecl>>.Empty;
    if (input.unsigned() == 1) {
        var _v830 = Array<ast.VariableDecl>();
        var _n831 = input.count();
        for (var _ in 0.._n831) {
            _v830.append(_a_VariableDecl_read(input));
        }
        _o829 = Optional<Array<ast.VariableDecl>>.Value(_v830);
    }
    var _f832 = _o829;
    var _v833 = Array<ast.Attribute>();
    var _n834 = input.count();
    for (var _ in 0.._n834) {
        _v833.append(_a_Attribute_read(input));
    }
    var _f835 = _v833;
    var _s836 = input.unsigned();
    var _f837 = ast.Span(_s836, input.unsigned());
    var value = ast.EnumCase();
    value.name = _f824;
    value.name_span = _f826;
    value.value = _f828;
    value.payload = _f832;
    value.attributes = _f835;
    value.span = _f837;
    return value;
}

_a_Literal_write(out: RecordOut, value: ast.Literal) {
    match (value) {
        String(p0) => {
            out.unsigned(0);
            out.text(p0);
        }
        Integer(p0) => {
            out.unsigned(1);
            out.signed(p0 as long);
        }
        Float(p0) => {
            out.unsigned(2);
            out.number(p0);
        }
        Bool(p0) => {
            out.unsigned(3);
            out.flag(p0);
        }
        Char(p0) => {
            out.unsigned(4);
            out.unsigned(p0 as ulong);
        }
        Null => {
            out.unsigned(5);
        }
    }
}

_a_Literal_read(input: RecordIn): ast.Literal {
    var tag = input.unsigned();
    if (tag == 0) {
        var _f838 = input.text();
        return ast.Literal.String(_f838);
    }
    if (tag == 1) {
        var _f839 = input.signed();
        return ast.Literal.Integer(_f839);
    }
    if (tag == 2) {
        var _f840 = input.number();
        return ast.Literal.Float(_f840);
    }
    if (tag == 3) {
        var _f841 = input.flag();
        return ast.Literal.Bool(_f841);
    }
    if (tag == 4) {
        var _f842 = input.unsigned() as u8;
        return ast.Literal.Char(_f842);
    }
    if (tag == 5) {
        return ast.Literal.Null;
    }
    input.fail("Literal", tag);
    return _a_Literal_read(input);
}

_m_Block_write(out: RecordOut, value: Block) {
    out.text(value.name);
    out.unsigned(value.items.count);
    for (var _item843 in value.items) {
        _m_Statement_write(out, _item843);
    }
    out.unsigned(value.attributes.count);
    for (var _item844 in value.attributes) {
        _a_Attribute_write(out, _item844);
    }
}

_m_Block_read(input: RecordIn): Block {
    var _f845 = input.text();
    var _v846 = Array<Statement>();
    var _n847 = input.count();
    for (var _ in 0.._n847) {
        _v846.append(_m_Statement_read(input));
    }
    var _f848 = _v846;
    var _v849 = Array<ast.Attribute>();
    var _n850 = input.count();
    for (var _ in 0.._n850) {
        _v849.append(_a_Attribute_read(input));
    }
    var _f851 = _v849;
    return Block(_f845, _f848, _f851);
}

_m_Statement_write(out: RecordOut, value: Statement) {
    match (value) {
        Expression(v) => {
            out.unsigned(0);
            _m_Expression_write(out, v);
        }
        Block(v) => {
            out.unsigned(1);
            _m_Block_write(out, v);
        }
        Declaration(v) => {
            out.unsigned(2);
            _m_Declaration_write(out, v);
        }
        Branch(v) => {
            out.unsigned(3);
            _m_Branch_write(out, v);
        }
        While(v) => {
            out.unsigned(4);
            _m_While_write(out, v);
        }
        Return(v) => {
            out.unsigned(5);
            _m_ReturnStatement_write(out, v);
        }
        LoopBreak(v) => {
            out.unsigned(6);
            _m_LoopBreak_write(out, v);
        }
        Static(v) => {
            out.unsigned(7);
            _m_StaticBlock_write(out, v);
        }
        StaticPass(v) => {
            out.unsigned(8);
            _m_StaticPass_write(out, v);
        }
    }
}

_m_Statement_read(input: RecordIn): Statement {
    var tag = input.unsigned();
    if (tag == 0) {
        var _f1264 = _m_Expression_read(input);
        return Statement.Expression(_f1264);
    }
    if (tag == 1) {
        var _f1265 = _m_Block_read(input);
        return Statement.Block(_f1265);
    }
    if (tag == 2) {
        var _f1266 = _m_Declaration_read(input);
        return Statement.Declaration(_f1266);
    }
    if (tag == 3) {
        var _f1267 = _m_Branch_read(input);
        return Statement.Branch(_f1267);
    }
    if (tag == 4) {
        var _f1268 = _m_While_read(input);
        return Statement.While(_f1268);
    }
    if (tag == 5) {
        var _f1269 = _m_ReturnStatement_read(input);
        return Statement.Return(_f1269);
    }
    if (tag == 6) {
        var _f1270 = _m_LoopBreak_read(input);
        return Statement.LoopBreak(_f1270);
    }
    if (tag == 7) {
        var _f1271 = _m_StaticBlock_read(input);
        return Statement.Static(_f1271);
    }
    if (tag == 8) {
        var _f1272 = _m_StaticPass_read(input);
        return Statement.StaticPass(_f1272);
    }
    input.fail("Statement", tag);
    return _m_Statement_read(input);
}

_m_StaticPass_write(out: RecordOut, value: StaticPass) {
    out.loc(value.loc);
    out.flag(value.stop);
    out.unsigned(value.values.count);
    for (var _item852 in value.values) {
        var (_t853, _t854) = _item852;
        out.text(_t853);
        _m_StaticConstant_write(out, _t854);
    }
    if (value.header.is_value()) {
        out.unsigned(1);
        out.unsigned(value.header.value() as ulong);
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.lines.count);
    for (var _item855 in value.lines) {
        var (_t856, _t857) = _item855;
        out.loc(_t856);
        out.unsigned(_t857 as ulong);
    }
}

_m_StaticPass_read(input: RecordIn): StaticPass {
    var _f858 = input.loc();
    var _f859 = input.flag();
    var _v860 = Array<(String, StaticConstant)>();
    var _n861 = input.count();
    for (var _ in 0.._n861) {
        var _t862 = input.text();
        var _t863 = _m_StaticConstant_read(input);
        _v860.append((_t862, _t863));
    }
    var _f864 = _v860;
    var _o865 = Optional<uint>.Empty;
    if (input.unsigned() == 1) {
        _o865 = Optional<uint>.Value(input.unsigned() as uint);
    }
    var _f866 = _o865;
    var _v867 = Array<(Loc, uint)>();
    var _n868 = input.count();
    for (var _ in 0.._n868) {
        var _t869 = input.loc();
        var _t870 = input.unsigned() as uint;
        _v867.append((_t869, _t870));
    }
    var _f871 = _v867;
    return StaticPass(_f858, _f859, _f864, _f866, _f871);
}

_m_RecordStaticConstant_write(out: RecordOut, value: RecordStaticConstant) {
    out.text(value.name);
    out.unsigned(value.fields.count);
    for (var _item1277 in value.fields) {
        var (_t1278, _t1279) = _item1277;
        out.text(_t1278);
        _m_StaticConstant_write(out, _t1279);
    }
}

_m_RecordStaticConstant_read(input: RecordIn): RecordStaticConstant {
    var _f1280 = input.text();
    var _v1281 = Array<(String, StaticConstant)>();
    var _n1282 = input.count();
    for (var _ in 0.._n1282) {
        var _t1283 = input.text();
        var _t1284 = _m_StaticConstant_read(input);
        _v1281.append((_t1283, _t1284));
    }
    var _f1285 = _v1281;
    return RecordStaticConstant(_f1280, _f1285);
}

_m_StaticConstant_write(out: RecordOut, value: StaticConstant) {
    match (value) {
        Int(v) => {
            out.unsigned(0);
            out.signed(v as long);
        }
        Float(v) => {
            out.unsigned(1);
            out.number(v);
        }
        Bool(v) => {
            out.unsigned(2);
            out.flag(v);
        }
        String(v) => {
            out.unsigned(3);
            out.text(v);
        }
        Record(node) => {
            out.unsigned(4);
            _m_RecordStaticConstant_write(out, node);
        }
    }
}

_m_StaticConstant_read(input: RecordIn): StaticConstant {
    var tag = input.unsigned();
    if (tag == 0) {
        var _f1273 = input.signed();
        return StaticConstant.Int(_f1273);
    }
    if (tag == 1) {
        var _f1274 = input.number();
        return StaticConstant.Float(_f1274);
    }
    if (tag == 2) {
        var _f1275 = input.flag();
        return StaticConstant.Bool(_f1275);
    }
    if (tag == 3) {
        var _f1276 = input.text();
        return StaticConstant.String(_f1276);
    }
    if (tag == 4) {
        return StaticConstant.Record(_m_RecordStaticConstant_read(input));
    }
    input.fail("StaticConstant", tag);
    return _m_StaticConstant_read(input);
}

_m_StaticBlock_write(out: RecordOut, value: StaticBlock) {
    out.unsigned(value.captures.count);
    for (var _item872 in value.captures) {
        out.text(_item872);
    }
    out.unsigned(value.items.count);
    for (var _item873 in value.items) {
        _m_StaticItem_write(out, _item873);
    }
    out.unsigned(value.type_map.count);
    for (var _item874 in value.type_map) {
        var (_t875, _t876) = _item874;
        out.text(_t875);
        _m_TypeName_write(out, _t876);
    }
    out.loc(value.loc);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_StaticBlock_read(input: RecordIn): StaticBlock {
    var _v877 = Array<String>();
    var _n878 = input.count();
    for (var _ in 0.._n878) {
        _v877.append(input.text());
    }
    var _f879 = _v877;
    var _v880 = Array<StaticItem>();
    var _n881 = input.count();
    for (var _ in 0.._n881) {
        _v880.append(_m_StaticItem_read(input));
    }
    var _f882 = _v880;
    var _v883 = Array<(String, TypeName)>();
    var _n884 = input.count();
    for (var _ in 0.._n884) {
        var _t885 = input.text();
        var _t886 = _m_TypeName_read(input);
        _v883.append((_t885, _t886));
    }
    var _f887 = _v883;
    var _f888 = input.loc();
    var _s889 = input.unsigned();
    var _f890 = ast.Span(_s889, input.unsigned());
    return StaticBlock(_f879, _f882, _f887, _f888, _f890);
}

_m_TypeName_write(out: RecordOut, value: TypeName) {
    out.text(value.name);
    out.unsigned(value.sub_types.count);
    for (var _item891 in value.sub_types) {
        _m_TypeName_write(out, _item891);
    }
    _m_TypeFlags_write(out, value.flags);
    out.unsigned(value.labels.count);
    for (var _item892 in value.labels) {
        out.text(_item892);
    }
}

_m_TypeName_read(input: RecordIn): TypeName {
    var _f893 = input.text();
    var _v894 = Array<TypeName>();
    var _n895 = input.count();
    for (var _ in 0.._n895) {
        _v894.append(_m_TypeName_read(input));
    }
    var _f896 = _v894;
    var _f897 = _m_TypeFlags_read(input);
    var _v898 = Array<String>();
    var _n899 = input.count();
    for (var _ in 0.._n899) {
        _v898.append(input.text());
    }
    var _f900 = _v898;
    return TypeName(_f893, _f896, _f897, _f900);
}

_m_TypeFlags_write(out: RecordOut, value: TypeFlags) {
    match (value) {
        Scalar => {
            out.unsigned(0);
        }
        Function => {
            out.unsigned(1);
        }
    }
}

_m_TypeFlags_read(input: RecordIn): TypeFlags {
    var tag = input.unsigned();
    if (tag == 0) {
        return TypeFlags.Scalar;
    }
    if (tag == 1) {
        return TypeFlags.Function;
    }
    input.fail("TypeFlags", tag);
    return TypeFlags.Scalar;
}

_m_ForStaticItem_write(out: RecordOut, value: ForStaticItem) {
    out.text(value.name);
    _a_Expression_write(out, value.iterable);
    out.unsigned(value.body.count);
    for (var _item1286 in value.body) {
        _m_StaticItem_write(out, _item1286);
    }
    out.loc(value.loc);
}

_m_ForStaticItem_read(input: RecordIn): ForStaticItem {
    var _f1287 = input.text();
    var _f1288 = _a_Expression_read(input);
    var _v1289 = Array<StaticItem>();
    var _n1290 = input.count();
    for (var _ in 0.._n1290) {
        _v1289.append(_m_StaticItem_read(input));
    }
    var _f1291 = _v1289;
    var _f1292 = input.loc();
    return ForStaticItem(_f1288, _f1287, _f1291, _f1292);
}

_m_WhileStaticItem_write(out: RecordOut, value: WhileStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.body.count);
    for (var _item1293 in value.body) {
        _m_StaticItem_write(out, _item1293);
    }
    out.loc(value.loc);
}

_m_WhileStaticItem_read(input: RecordIn): WhileStaticItem {
    var _f1294 = _a_Expression_read(input);
    var _v1295 = Array<StaticItem>();
    var _n1296 = input.count();
    for (var _ in 0.._n1296) {
        _v1295.append(_m_StaticItem_read(input));
    }
    var _f1297 = _v1295;
    var _f1298 = input.loc();
    return WhileStaticItem(_f1294, _f1297, _f1298);
}

_m_JumpStaticItem_write(out: RecordOut, value: JumpStaticItem) {
    _m_LoopBreakKind_write(out, value.kind);
    out.loc(value.loc);
}

_m_JumpStaticItem_read(input: RecordIn): JumpStaticItem {
    var _f1299 = _m_LoopBreakKind_read(input);
    var _f1300 = input.loc();
    return JumpStaticItem(_f1299, _f1300);
}

_m_IfStaticItem_write(out: RecordOut, value: IfStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1301 in value.then_items) {
        _m_StaticItem_write(out, _item1301);
    }
    out.unsigned(value.else_items.count);
    for (var _item1302 in value.else_items) {
        _m_StaticItem_write(out, _item1302);
    }
    out.loc(value.loc);
}

_m_IfStaticItem_read(input: RecordIn): IfStaticItem {
    var _f1303 = _a_Expression_read(input);
    var _v1304 = Array<StaticItem>();
    var _n1305 = input.count();
    for (var _ in 0.._n1305) {
        _v1304.append(_m_StaticItem_read(input));
    }
    var _f1306 = _v1304;
    var _v1307 = Array<StaticItem>();
    var _n1308 = input.count();
    for (var _ in 0.._n1308) {
        _v1307.append(_m_StaticItem_read(input));
    }
    var _f1309 = _v1307;
    var _f1310 = input.loc();
    return IfStaticItem(_f1303, _f1306, _f1309, _f1310);
}

_m_EmitIfStaticItem_write(out: RecordOut, value: EmitIfStaticItem) {
    _m_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1311 in value.then_items) {
        _m_StaticItem_write(out, _item1311);
    }
    out.unsigned(value.else_items.count);
    for (var _item1312 in value.else_items) {
        _m_StaticItem_write(out, _item1312);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_EmitIfStaticItem_read(input: RecordIn): EmitIfStaticItem {
    var _f1313 = _m_Expression_read(input);
    var _v1314 = Array<StaticItem>();
    var _n1315 = input.count();
    for (var _ in 0.._n1315) {
        _v1314.append(_m_StaticItem_read(input));
    }
    var _f1316 = _v1314;
    var _v1317 = Array<StaticItem>();
    var _n1318 = input.count();
    for (var _ in 0.._n1318) {
        _v1317.append(_m_StaticItem_read(input));
    }
    var _f1319 = _v1317;
    var _s1320 = input.unsigned();
    var _f1321 = ast.Span(_s1320, input.unsigned());
    return EmitIfStaticItem(_f1313, _f1316, _f1319, _f1321);
}

_m_VarStaticItem_write(out: RecordOut, value: VarStaticItem) {
    out.text(value.name);
    _a_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_VarStaticItem_read(input: RecordIn): VarStaticItem {
    var _f1326 = input.text();
    var _f1327 = _a_Expression_read(input);
    var _f1328 = input.loc();
    return VarStaticItem(_f1327, _f1326, _f1328);
}

_m_StaticItem_write(out: RecordOut, value: StaticItem) {
    match (value) {
        For(node) => {
            out.unsigned(0);
            _m_ForStaticItem_write(out, node);
        }
        While(node) => {
            out.unsigned(1);
            _m_WhileStaticItem_write(out, node);
        }
        Jump(node) => {
            out.unsigned(2);
            _m_JumpStaticItem_write(out, node);
        }
        If(node) => {
            out.unsigned(3);
            _m_IfStaticItem_write(out, node);
        }
        EmitIf(node) => {
            out.unsigned(4);
            _m_EmitIfStaticItem_write(out, node);
        }
        Block(v) => {
            out.unsigned(5);
            out.unsigned(v.count);
            for (var _item1322 in v) {
                _m_StaticItem_write(out, _item1322);
            }
        }
        Var(node) => {
            out.unsigned(6);
            _m_VarStaticItem_write(out, node);
        }
        Evaluate(v) => {
            out.unsigned(7);
            _a_Expression_write(out, v);
        }
        Emit(v0, v1) => {
            out.unsigned(8);
            _m_Statement_write(out, v0);
            out.unsigned(out.blank_locs ? 0 : v1.start);
            out.unsigned(out.blank_locs ? 0 : v1.end);
        }
    }
}

_m_StaticItem_read(input: RecordIn): StaticItem {
    var tag = input.unsigned();
    if (tag == 0) {
        return StaticItem.For(_m_ForStaticItem_read(input));
    }
    if (tag == 1) {
        return StaticItem.While(_m_WhileStaticItem_read(input));
    }
    if (tag == 2) {
        return StaticItem.Jump(_m_JumpStaticItem_read(input));
    }
    if (tag == 3) {
        return StaticItem.If(_m_IfStaticItem_read(input));
    }
    if (tag == 4) {
        return StaticItem.EmitIf(_m_EmitIfStaticItem_read(input));
    }
    if (tag == 5) {
        var _v1323 = Array<StaticItem>();
        var _n1324 = input.count();
        for (var _ in 0.._n1324) {
            _v1323.append(_m_StaticItem_read(input));
        }
        var _f1325 = _v1323;
        return StaticItem.Block(_f1325);
    }
    if (tag == 6) {
        return StaticItem.Var(_m_VarStaticItem_read(input));
    }
    if (tag == 7) {
        var _f1329 = _a_Expression_read(input);
        return StaticItem.Evaluate(_f1329);
    }
    if (tag == 8) {
        var _f1330 = _m_Statement_read(input);
        var _s1331 = input.unsigned();
        var _f1332 = ast.Span(_s1331, input.unsigned());
        return StaticItem.Emit(_f1330, _f1332);
    }
    input.fail("StaticItem", tag);
    return _m_StaticItem_read(input);
}

_m_SymbolRefExpression_write(out: RecordOut, value: SymbolRefExpression) {
    out.text(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SymbolRefExpression_read(input: RecordIn): SymbolRefExpression {
    var _f1333 = input.text();
    var _f1334 = _m_TypeName_read(input);
    var _f1335 = input.loc();
    return SymbolRefExpression(_f1333, _f1334, _f1335);
}

_m_MemberRefExpression_write(out: RecordOut, value: MemberRefExpression) {
    _m_Expression_write(out, value.lhs);
    out.text(value.name);
    out.loc(value.loc);
}

_m_MemberRefExpression_read(input: RecordIn): MemberRefExpression {
    var _f1336 = _m_Expression_read(input);
    var _f1337 = input.text();
    var _f1338 = input.loc();
    return MemberRefExpression(_f1336, _f1337, _f1338);
}

_m_StringLiteralExpression_write(out: RecordOut, value: StringLiteralExpression) {
    out.text(value.value);
    out.flag(value.is_raw);
    out.loc(value.loc);
}

_m_StringLiteralExpression_read(input: RecordIn): StringLiteralExpression {
    var _f1342 = input.text();
    var _f1343 = input.flag();
    var _f1344 = input.loc();
    return StringLiteralExpression(_f1342, _f1343, _f1344);
}

_m_BinaryExpression_write(out: RecordOut, value: BinaryExpression) {
    _m_BinaryOp_write(out, value.op);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_BinaryExpression_read(input: RecordIn): BinaryExpression {
    var _f1345 = _m_BinaryOp_read(input);
    var _f1346 = _m_Expression_read(input);
    var _f1347 = _m_Expression_read(input);
    var _f1348 = input.loc();
    return BinaryExpression(_f1346, _f1347, _f1345, _f1348);
}

_m_UnaryExpression_write(out: RecordOut, value: UnaryExpression) {
    _m_UnaryOp_write(out, value.op);
    _m_Expression_write(out, value.operand);
    out.loc(value.loc);
}

_m_UnaryExpression_read(input: RecordIn): UnaryExpression {
    var _f1349 = _m_UnaryOp_read(input);
    var _f1350 = _m_Expression_read(input);
    var _f1351 = input.loc();
    return UnaryExpression(_f1350, _f1349, _f1351);
}

_m_CastExpression_write(out: RecordOut, value: CastExpression) {
    _m_Expression_write(out, value.expr);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
    _m_CastKind_write(out, value.kind);
}

_m_CastExpression_read(input: RecordIn): CastExpression {
    var _f1352 = _m_Expression_read(input);
    var _f1353 = _m_TypeName_read(input);
    var _f1354 = input.loc();
    var _f1355 = _m_CastKind_read(input);
    return CastExpression(_f1352, _f1353, _f1354, _f1355);
}

_m_TernaryExpression_write(out: RecordOut, value: TernaryExpression) {
    _m_Expression_write(out, value.condition);
    _m_Expression_write(out, value.true_expr);
    _m_Expression_write(out, value.false_expr);
}

_m_TernaryExpression_read(input: RecordIn): TernaryExpression {
    var _f1356 = _m_Expression_read(input);
    var _f1357 = _m_Expression_read(input);
    var _f1358 = _m_Expression_read(input);
    return TernaryExpression(_f1356, _f1357, _f1358);
}

_m_IndexExpression_write(out: RecordOut, value: IndexExpression) {
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_IndexExpression_read(input: RecordIn): IndexExpression {
    var _f1359 = _m_Expression_read(input);
    var _f1360 = _m_Expression_read(input);
    var _f1361 = input.loc();
    return IndexExpression(_f1359, _f1360, _f1361);
}

_m_ArrayIndexExpression_write(out: RecordOut, value: ArrayIndexExpression) {
    _m_TypeName_write(out, value.ty);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_ArrayIndexExpression_read(input: RecordIn): ArrayIndexExpression {
    var _f1362 = _m_TypeName_read(input);
    var _f1363 = _m_Expression_read(input);
    var _f1364 = _m_Expression_read(input);
    var _f1365 = input.loc();
    return ArrayIndexExpression(_f1363, _f1364, _f1362, _f1365);
}

_m_SimdExpression_write(out: RecordOut, value: SimdExpression) {
    _m_SimdOp_write(out, value.op);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1389 in value.args) {
        _m_Expression_write(out, _item1389);
    }
    out.loc(value.loc);
}

_m_SimdExpression_read(input: RecordIn): SimdExpression {
    var _f1390 = _m_SimdOp_read(input);
    var _f1391 = _m_TypeName_read(input);
    var _v1392 = Array<Expression>();
    var _n1393 = input.count();
    for (var _ in 0.._n1393) {
        _v1392.append(_m_Expression_read(input));
    }
    var _f1394 = _v1392;
    var _f1395 = input.loc();
    return SimdExpression(_f1390, _f1391, _f1394, _f1395);
}

_m_CountStepExpression_write(out: RecordOut, value: CountStepExpression) {
    _m_CountField_write(out, value.field);
    out.flag(value.increment);
    out.flag(value.atomic);
}

_m_CountStepExpression_read(input: RecordIn): CountStepExpression {
    var _f1399 = _m_CountField_read(input);
    var _f1400 = input.flag();
    var _f1401 = input.flag();
    return CountStepExpression(_f1399, _f1400, _f1401);
}

_m_FunctionPointerExpression_write(out: RecordOut, value: FunctionPointerExpression) {
    if (value.owner.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.owner.value());
    } else {
        out.unsigned(0);
    }
    out.text(value.function);
    out.loc(value.loc);
}

_m_FunctionPointerExpression_read(input: RecordIn): FunctionPointerExpression {
    var _o1402 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1402 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1403 = _o1402;
    var _f1404 = input.text();
    var _f1405 = input.loc();
    return FunctionPointerExpression(_f1403, _f1404, _f1405);
}

_m_FunctionCallExpression_write(out: RecordOut, value: FunctionCallExpression) {
    out.text(value.function);
    out.unsigned(value.args.count);
    for (var _item1406 in value.args) {
        _m_Expression_write(out, _item1406);
    }
    out.loc(value.loc);
}

_m_FunctionCallExpression_read(input: RecordIn): FunctionCallExpression {
    var _f1407 = input.text();
    var _v1408 = Array<Expression>();
    var _n1409 = input.count();
    for (var _ in 0.._n1409) {
        _v1408.append(_m_Expression_read(input));
    }
    var _f1410 = _v1408;
    var _f1411 = input.loc();
    return FunctionCallExpression(_f1407, _f1410, _f1411);
}

_m_NamedArgumentExpression_write(out: RecordOut, value: NamedArgumentExpression) {
    out.text(value.name);
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_NamedArgumentExpression_read(input: RecordIn): NamedArgumentExpression {
    var _f1412 = input.text();
    var _f1413 = _m_Expression_read(input);
    var _f1414 = input.loc();
    return NamedArgumentExpression(_f1413, _f1412, _f1414);
}

_m_DefaultArgumentExpression_write(out: RecordOut, value: DefaultArgumentExpression) {
    _m_TypeName_write(out, value.ty);
}

_m_DefaultArgumentExpression_read(input: RecordIn): DefaultArgumentExpression {
    var _f1415 = _m_TypeName_read(input);
    return DefaultArgumentExpression(_f1415);
}

_m_MethodCallExpression_write(out: RecordOut, value: MethodCallExpression) {
    _m_Expression_write(out, value.this_value);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item1416 in value.args) {
        _m_Expression_write(out, _item1416);
    }
    out.loc(value.loc);
}

_m_MethodCallExpression_read(input: RecordIn): MethodCallExpression {
    var _f1417 = _m_Expression_read(input);
    var _f1418 = input.text();
    var _v1419 = Array<Expression>();
    var _n1420 = input.count();
    for (var _ in 0.._n1420) {
        _v1419.append(_m_Expression_read(input));
    }
    var _f1421 = _v1419;
    var _f1422 = input.loc();
    return MethodCallExpression(_f1417, _f1418, _f1421, _f1422);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1423 = input.text();
    var _f1424 = _m_TypeName_read(input);
    var _f1425 = input.loc();
    return FunctionRefExpression(_f1423, _f1424, _f1425);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1426 in value.args) {
        _m_Expression_write(out, _item1426);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1427 = _m_Expression_read(input);
    var _v1428 = Array<Expression>();
    var _n1429 = input.count();
    for (var _ in 0.._n1429) {
        _v1428.append(_m_Expression_read(input));
    }
    var _f1430 = _v1428;
    return InvokeExpression(_f1427, _f1430);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1432 = _m_Expression_read(input);
    var _f1433 = input.text();
    var _f1434 = _m_TypeName_read(input);
    var _f1435 = input.loc();
    return MakeClosureExpression(_f1432, _f1433, _f1434, _f1435);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1437 in value.args) {
        _m_Expression_write(out, _item1437);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1438 = _m_Expression_read(input);
    var _v1439 = Array<Expression>();
    var _n1440 = input.count();
    for (var _ in 0.._n1440) {
        _v1439.append(_m_Expression_read(input));
    }
    var _f1441 = _v1439;
    return CallPointerExpression(_f1438, _f1441);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1444 = _m_Expression_read(input);
    var _f1445 = input.loc();
    return MoveExpression(_f1444, _f1445);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1446 = _m_Expression_read(input);
    var _f1447 = input.unsigned();
    var _f1448 = input.loc();
    return DestructureExpression(_f1446, _f1447, _f1448);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1451 = _m_TypeName_read(input);
    var _f1452 = input.signed();
    return StaticCaseExpression(_f1451, _f1452);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1453 = input.text();
    var _f1454 = input.loc();
    return StaticStringExpression(_f1453, _f1454);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1456 = input.unsigned();
    var _f1457 = _m_TypeName_read(input);
    var _f1458 = input.loc();
    return SubjectExpression(_f1456, _f1457, _f1458);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1459 = _m_Expression_read(input);
    var _f1460 = _m_TypeName_read(input);
    var _f1461 = _m_TypeName_read(input);
    var _f1462 = input.loc();
    return ToTraitExpression(_f1459, _f1460, _f1461, _f1462);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1463 in value.candidates) {
        _m_TypeName_write(out, _item1463);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1464 = _m_Expression_read(input);
    var _f1465 = _m_TypeName_read(input);
    var _f1466 = _m_TypeName_read(input);
    var _v1467 = Array<TypeName>();
    var _n1468 = input.count();
    for (var _ in 0.._n1468) {
        _v1467.append(_m_TypeName_read(input));
    }
    var _f1469 = _v1467;
    var _f1470 = input.flag();
    var _f1471 = input.loc();
    return FromTraitExpression(_f1464, _f1465, _f1466, _f1469, _f1470, _f1471);
}

_m_Expression_write(out: RecordOut, value: Expression) {
    match (value) {
        SymbolRef(node) => {
            out.unsigned(0);
            _m_SymbolRefExpression_write(out, node);
        }
        ThisRef => {
            out.unsigned(1);
        }
        MemberRef(node) => {
            out.unsigned(2);
            _m_MemberRefExpression_write(out, node);
        }
        BoolLiteral(v) => {
            out.unsigned(3);
            out.flag(v);
        }
        IntLiteral(v) => {
            out.unsigned(4);
            out.signed(v as long);
        }
        FloatLiteral(v) => {
            out.unsigned(5);
            out.number(v);
        }
        StringLiteral(node) => {
            out.unsigned(6);
            _m_StringLiteralExpression_write(out, node);
        }
        PointerLiteral => {
            out.unsigned(7);
        }
        Binary(node) => {
            out.unsigned(8);
            _m_BinaryExpression_write(out, node);
        }
        Unary(node) => {
            out.unsigned(9);
            _m_UnaryExpression_write(out, node);
        }
        Cast(node) => {
            out.unsigned(10);
            _m_CastExpression_write(out, node);
        }
        Ternary(node) => {
            out.unsigned(11);
            _m_TernaryExpression_write(out, node);
        }
        Index(node) => {
            out.unsigned(12);
            _m_IndexExpression_write(out, node);
        }
        ArrayIndex(node) => {
            out.unsigned(13);
            _m_ArrayIndexExpression_write(out, node);
        }
        SizeOf(v) => {
            out.unsigned(14);
            _m_TypeName_write(out, v);
        }
        IsPod(v) => {
            out.unsigned(15);
            _m_TypeName_write(out, v);
        }
        Default(v) => {
            out.unsigned(16);
            _m_TypeName_write(out, v);
        }
        Allocate(v) => {
            out.unsigned(17);
            _m_TypeName_write(out, v);
        }
        RefCount(v0, v1) => {
            out.unsigned(18);
            _m_TypeName_write(out, v0);
            _m_Expression_write(out, v1);
        }
        Address(v0, v1) => {
            out.unsigned(19);
            _m_TypeName_write(out, v0);
            _m_Expression_write(out, v1);
        }
        AtomicLoad(v0, v1) => {
            out.unsigned(20);
            _m_TypeName_write(out, v0);
            _m_Expression_write(out, v1);
        }
        AtomicStore(v0, v1, v2) => {
            out.unsigned(21);
            _m_TypeName_write(out, v0);
            _m_Expression_write(out, v1);
            _m_Expression_write(out, v2);
        }
        ConstructAt(v0, v1) => {
            out.unsigned(22);
            _m_Expression_write(out, v0);
            _m_Expression_write(out, v1);
        }
        AtomicCmpXchg(v0, v1, v2, v3) => {
            out.unsigned(23);
            _m_TypeName_write(out, v0);
            _m_Expression_write(out, v1);
            _m_Expression_write(out, v2);
            _m_Expression_write(out, v3);
        }
        AtomicFetch(v0, v1, v2, v3) => {
            out.unsigned(24);
            _m_AtomicFetchOp_write(out, v0);
            _m_TypeName_write(out, v1);
            _m_Expression_write(out, v2);
            _m_Expression_write(out, v3);
        }
        Simd(node) => {
            out.unsigned(25);
            _m_SimdExpression_write(out, node);
        }
        Weak(v0, v1, v2) => {
            out.unsigned(26);
            _m_WeakOp_write(out, v0);
            _m_TypeName_write(out, v1);
            _m_Expression_write(out, v2);
        }
        CountStep(node) => {
            out.unsigned(27);
            _m_CountStepExpression_write(out, node);
        }
        FunctionPointer(node) => {
            out.unsigned(28);
            _m_FunctionPointerExpression_write(out, node);
        }
        FunctionCall(node) => {
            out.unsigned(29);
            _m_FunctionCallExpression_write(out, node);
        }
        NamedArgument(node) => {
            out.unsigned(30);
            _m_NamedArgumentExpression_write(out, node);
        }
        DefaultArgument(node) => {
            out.unsigned(31);
            _m_DefaultArgumentExpression_write(out, node);
        }
        MethodCall(node) => {
            out.unsigned(32);
            _m_MethodCallExpression_write(out, node);
        }
        FunctionRef(node) => {
            out.unsigned(33);
            _m_FunctionRefExpression_write(out, node);
        }
        Invoke(node) => {
            out.unsigned(34);
            _m_InvokeExpression_write(out, node);
        }
        ClosureLiteral(v) => {
            out.unsigned(35);
            _m_ClosureLiteral_write(out, v);
        }
        MakeClosure(node) => {
            out.unsigned(36);
            _m_MakeClosureExpression_write(out, node);
        }
        MethodAddress(v) => {
            out.unsigned(37);
            out.text(v);
        }
        CallPointer(node) => {
            out.unsigned(38);
            _m_CallPointerExpression_write(out, node);
        }
        ForIterator(v) => {
            out.unsigned(39);
            _m_Expression_write(out, v);
        }
        WithEntered(v) => {
            out.unsigned(40);
            _m_Expression_write(out, v);
        }
        Move(node) => {
            out.unsigned(41);
            _m_MoveExpression_write(out, node);
        }
        Destructure(node) => {
            out.unsigned(42);
            _m_DestructureExpression_write(out, node);
        }
        MatchArm(v) => {
            out.unsigned(43);
            _m_MatchArmTest_write(out, v);
        }
        CaseValue(v) => {
            out.unsigned(44);
            _m_CaseValue_write(out, v);
        }
        StaticCase(node) => {
            out.unsigned(45);
            _m_StaticCaseExpression_write(out, node);
        }
        StaticString(node) => {
            out.unsigned(46);
            _m_StaticStringExpression_write(out, node);
        }
        WithSubject(v) => {
            out.unsigned(47);
            _m_WithSubject_write(out, v);
        }
        Subject(node) => {
            out.unsigned(48);
            _m_SubjectExpression_write(out, node);
        }
        NoMatch => {
            out.unsigned(49);
        }
        ToTrait(node) => {
            out.unsigned(50);
            _m_ToTraitExpression_write(out, node);
        }
        FromTrait(node) => {
            out.unsigned(51);
            _m_FromTraitExpression_write(out, node);
        }
        StaticValue(v) => {
            out.unsigned(52);
            _m_StaticValue_write(out, v);
        }
        StaticMember(v) => {
            out.unsigned(53);
            _m_StaticMember_write(out, v);
        }
    }
}

_m_Expression_read(input: RecordIn): Expression {
    var tag = input.unsigned();
    if (tag == 0) {
        return Expression.SymbolRef(_m_SymbolRefExpression_read(input));
    }
    if (tag == 1) {
        return Expression.ThisRef;
    }
    if (tag == 2) {
        return Expression.MemberRef(_m_MemberRefExpression_read(input));
    }
    if (tag == 3) {
        var _f1339 = input.flag();
        return Expression.BoolLiteral(_f1339);
    }
    if (tag == 4) {
        var _f1340 = input.signed();
        return Expression.IntLiteral(_f1340);
    }
    if (tag == 5) {
        var _f1341 = input.number();
        return Expression.FloatLiteral(_f1341);
    }
    if (tag == 6) {
        return Expression.StringLiteral(_m_StringLiteralExpression_read(input));
    }
    if (tag == 7) {
        return Expression.PointerLiteral;
    }
    if (tag == 8) {
        return Expression.Binary(_m_BinaryExpression_read(input));
    }
    if (tag == 9) {
        return Expression.Unary(_m_UnaryExpression_read(input));
    }
    if (tag == 10) {
        return Expression.Cast(_m_CastExpression_read(input));
    }
    if (tag == 11) {
        return Expression.Ternary(_m_TernaryExpression_read(input));
    }
    if (tag == 12) {
        return Expression.Index(_m_IndexExpression_read(input));
    }
    if (tag == 13) {
        return Expression.ArrayIndex(_m_ArrayIndexExpression_read(input));
    }
    if (tag == 14) {
        var _f1366 = _m_TypeName_read(input);
        return Expression.SizeOf(_f1366);
    }
    if (tag == 15) {
        var _f1367 = _m_TypeName_read(input);
        return Expression.IsPod(_f1367);
    }
    if (tag == 16) {
        var _f1368 = _m_TypeName_read(input);
        return Expression.Default(_f1368);
    }
    if (tag == 17) {
        var _f1369 = _m_TypeName_read(input);
        return Expression.Allocate(_f1369);
    }
    if (tag == 18) {
        var _f1370 = _m_TypeName_read(input);
        var _f1371 = _m_Expression_read(input);
        return Expression.RefCount(_f1370, _f1371);
    }
    if (tag == 19) {
        var _f1372 = _m_TypeName_read(input);
        var _f1373 = _m_Expression_read(input);
        return Expression.Address(_f1372, _f1373);
    }
    if (tag == 20) {
        var _f1374 = _m_TypeName_read(input);
        var _f1375 = _m_Expression_read(input);
        return Expression.AtomicLoad(_f1374, _f1375);
    }
    if (tag == 21) {
        var _f1376 = _m_TypeName_read(input);
        var _f1377 = _m_Expression_read(input);
        var _f1378 = _m_Expression_read(input);
        return Expression.AtomicStore(_f1376, _f1377, _f1378);
    }
    if (tag == 22) {
        var _f1379 = _m_Expression_read(input);
        var _f1380 = _m_Expression_read(input);
        return Expression.ConstructAt(_f1379, _f1380);
    }
    if (tag == 23) {
        var _f1381 = _m_TypeName_read(input);
        var _f1382 = _m_Expression_read(input);
        var _f1383 = _m_Expression_read(input);
        var _f1384 = _m_Expression_read(input);
        return Expression.AtomicCmpXchg(_f1381, _f1382, _f1383, _f1384);
    }
    if (tag == 24) {
        var _f1385 = _m_AtomicFetchOp_read(input);
        var _f1386 = _m_TypeName_read(input);
        var _f1387 = _m_Expression_read(input);
        var _f1388 = _m_Expression_read(input);
        return Expression.AtomicFetch(_f1385, _f1386, _f1387, _f1388);
    }
    if (tag == 25) {
        return Expression.Simd(_m_SimdExpression_read(input));
    }
    if (tag == 26) {
        var _f1396 = _m_WeakOp_read(input);
        var _f1397 = _m_TypeName_read(input);
        var _f1398 = _m_Expression_read(input);
        return Expression.Weak(_f1396, _f1397, _f1398);
    }
    if (tag == 27) {
        return Expression.CountStep(_m_CountStepExpression_read(input));
    }
    if (tag == 28) {
        return Expression.FunctionPointer(_m_FunctionPointerExpression_read(input));
    }
    if (tag == 29) {
        return Expression.FunctionCall(_m_FunctionCallExpression_read(input));
    }
    if (tag == 30) {
        return Expression.NamedArgument(_m_NamedArgumentExpression_read(input));
    }
    if (tag == 31) {
        return Expression.DefaultArgument(_m_DefaultArgumentExpression_read(input));
    }
    if (tag == 32) {
        return Expression.MethodCall(_m_MethodCallExpression_read(input));
    }
    if (tag == 33) {
        return Expression.FunctionRef(_m_FunctionRefExpression_read(input));
    }
    if (tag == 34) {
        return Expression.Invoke(_m_InvokeExpression_read(input));
    }
    if (tag == 35) {
        var _f1431 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1431);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1436 = input.text();
        return Expression.MethodAddress(_f1436);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1442 = _m_Expression_read(input);
        return Expression.ForIterator(_f1442);
    }
    if (tag == 40) {
        var _f1443 = _m_Expression_read(input);
        return Expression.WithEntered(_f1443);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1449 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1449);
    }
    if (tag == 44) {
        var _f1450 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1450);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1455 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1455);
    }
    if (tag == 48) {
        return Expression.Subject(_m_SubjectExpression_read(input));
    }
    if (tag == 49) {
        return Expression.NoMatch;
    }
    if (tag == 50) {
        return Expression.ToTrait(_m_ToTraitExpression_read(input));
    }
    if (tag == 51) {
        return Expression.FromTrait(_m_FromTraitExpression_read(input));
    }
    if (tag == 52) {
        var _f1472 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1472);
    }
    if (tag == 53) {
        var _f1473 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1473);
    }
    input.fail("Expression", tag);
    return _m_Expression_read(input);
}

_m_StaticMember_write(out: RecordOut, value: StaticMember) {
    _a_Expression_write(out, value.member);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item901 in value.args) {
        _m_Expression_write(out, _item901);
    }
    out.loc(value.loc);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.argument_spans.count);
    for (var _item902 in value.argument_spans) {
        out.unsigned(out.blank_locs ? 0 : _item902.start);
        out.unsigned(out.blank_locs ? 0 : _item902.end);
    }
}

_m_StaticMember_read(input: RecordIn): StaticMember {
    var _f903 = _a_Expression_read(input);
    var _f904 = input.text();
    var _v905 = Array<Expression>();
    var _n906 = input.count();
    for (var _ in 0.._n906) {
        _v905.append(_m_Expression_read(input));
    }
    var _f907 = _v905;
    var _f908 = input.loc();
    var _s909 = input.unsigned();
    var _f910 = ast.Span(_s909, input.unsigned());
    var _v911 = Array<ast.Span>();
    var _n912 = input.count();
    for (var _ in 0.._n912) {
        var _s913 = input.unsigned();
        _v911.append(ast.Span(_s913, input.unsigned()));
    }
    var _f914 = _v911;
    return StaticMember(_f903, _f904, _f907, _f908, _f910, _f914);
}

_m_StaticValue_write(out: RecordOut, value: StaticValue) {
    _a_Expression_write(out, value.expr);
    out.loc(value.loc);
}

_m_StaticValue_read(input: RecordIn): StaticValue {
    var _f915 = _a_Expression_read(input);
    var _f916 = input.loc();
    return StaticValue(_f915, _f916);
}

_m_WithSubject_write(out: RecordOut, value: WithSubject) {
    out.unsigned(value.id);
    _m_Expression_write(out, value.subject);
    _m_Expression_write(out, value.body);
    if (value.null_message.is_value()) {
        out.unsigned(1);
        out.text(value.null_message.value());
    } else {
        out.unsigned(0);
    }
    out.loc(value.loc);
}

_m_WithSubject_read(input: RecordIn): WithSubject {
    var _f917 = input.unsigned();
    var _f918 = _m_Expression_read(input);
    var _f919 = _m_Expression_read(input);
    var _o920 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o920 = Optional<String>.Value(input.text());
    }
    var _f921 = _o920;
    var _f922 = input.loc();
    return WithSubject(_f918, _f919, _f917, _f921, _f922);
}

_m_CaseValue_write(out: RecordOut, value: CaseValue) {
    _m_Expression_write(out, value.subject);
    out.text(value.name);
    out.unsigned(value.choices.count);
    for (var _item923 in value.choices) {
        _m_CaseChoice_write(out, _item923);
    }
    out.loc(value.loc);
}

_m_CaseValue_read(input: RecordIn): CaseValue {
    var _f924 = _m_Expression_read(input);
    var _f925 = input.text();
    var _v926 = Array<CaseChoice>();
    var _n927 = input.count();
    for (var _ in 0.._n927) {
        _v926.append(_m_CaseChoice_read(input));
    }
    var _f928 = _v926;
    var _f929 = input.loc();
    return CaseValue(_f924, _f925, _f928, _f929);
}

_m_CaseChoice_write(out: RecordOut, value: CaseChoice) {
    out.text(value.case);
    out.loc(value.case_loc);
    if (value.ty.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.ty.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.index);
    out.unsigned(value.bindings.count);
    for (var _item930 in value.bindings) {
        out.loc(_item930);
    }
    out.loc(value.loc);
}

_m_CaseChoice_read(input: RecordIn): CaseChoice {
    var _f931 = input.text();
    var _f932 = input.loc();
    var _o933 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o933 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f934 = _o933;
    var _f935 = input.unsigned();
    var _v936 = Array<Loc>();
    var _n937 = input.count();
    for (var _ in 0.._n937) {
        _v936.append(input.loc());
    }
    var _f938 = _v936;
    var _f939 = input.loc();
    return CaseChoice(_f931, _f932, _f934, _f935, _f938, _f939);
}

_m_MatchArmTest_write(out: RecordOut, value: MatchArmTest) {
    _m_Expression_write(out, value.subject);
    out.unsigned(value.patterns.count);
    for (var _item940 in value.patterns) {
        _m_CasePattern_write(out, _item940);
    }
    _m_MatchSite_write(out, value.site);
    out.unsigned(value.element_names.count);
    for (var _item941 in value.element_names) {
        _m_ElementName_write(out, _item941);
    }
    out.flag(value.guarded);
}

_m_MatchArmTest_read(input: RecordIn): MatchArmTest {
    var _f942 = _m_Expression_read(input);
    var _v943 = Array<CasePattern>();
    var _n944 = input.count();
    for (var _ in 0.._n944) {
        _v943.append(_m_CasePattern_read(input));
    }
    var _f945 = _v943;
    var _f946 = _m_MatchSite_read(input);
    var _v947 = Array<ElementName>();
    var _n948 = input.count();
    for (var _ in 0.._n948) {
        _v947.append(_m_ElementName_read(input));
    }
    var _f949 = _v947;
    var _f950 = input.flag();
    return MatchArmTest(_f942, _f945, _f946, _f949, _f950);
}

_m_ElementName_write(out: RecordOut, value: ElementName) {
    out.text(value.name);
    out.loc(value.loc);
    out.flag(value.declared);
    if (value.missing.is_value()) {
        out.unsigned(1);
        var (_t951, _t952) = value.missing.value();
        out.text(_t951);
        out.loc(_t952);
    } else {
        out.unsigned(0);
    }
}

_m_ElementName_read(input: RecordIn): ElementName {
    var _f953 = input.text();
    var _f954 = input.loc();
    var _f955 = input.flag();
    var _o956 = Optional<(String, Loc)>.Empty;
    if (input.unsigned() == 1) {
        var _t957 = input.text();
        var _t958 = input.loc();
        _o956 = Optional<(String, Loc)>.Value((_t957, _t958));
    }
    var _f959 = _o956;
    return ElementName(_f953, _f954, _f955, _f959);
}

_m_MatchSite_write(out: RecordOut, value: MatchSite) {
    out.unsigned(value.id);
    out.loc(value.keyword);
    if (value.else_arm.is_value()) {
        out.unsigned(1);
        out.loc(value.else_arm.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.partial);
    out.flag(value.no_bindings);
}

_m_MatchSite_read(input: RecordIn): MatchSite {
    var _f960 = input.unsigned();
    var _f961 = input.loc();
    var _o962 = Optional<Loc>.Empty;
    if (input.unsigned() == 1) {
        _o962 = Optional<Loc>.Value(input.loc());
    }
    var _f963 = _o962;
    var _f964 = input.flag();
    var _f965 = input.flag();
    return MatchSite(_f960, _f961, _f963, _f964, _f965);
}

_m_CasePattern_write(out: RecordOut, value: CasePattern) {
    if (value.qualifier.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.qualifier.value());
    } else {
        out.unsigned(0);
    }
    out.text(value.case);
    out.loc(value.loc);
    if (value.bindings.is_value()) {
        out.unsigned(1);
        out.unsigned(value.bindings.value().count);
        for (var _item966 in value.bindings.value()) {
            _m_CasePattern_write(out, _item966);
        }
    } else {
        out.unsigned(0);
    }
    if (value.literal.is_value()) {
        out.unsigned(1);
        _m_Expression_write(out, value.literal.value());
    } else {
        out.unsigned(0);
    }
    if (value.elements.is_value()) {
        out.unsigned(1);
        out.unsigned(value.elements.value().count);
        for (var _item967 in value.elements.value()) {
            _m_CasePattern_write(out, _item967);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.range);
    out.flag(value.constant);
    if (value.values.is_value()) {
        out.unsigned(1);
        var (_t968, _t969) = value.values.value();
        out.signed(_t968 as long);
        out.signed(_t969 as long);
    } else {
        out.unsigned(0);
    }
    if (value.ty.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.ty.value());
    } else {
        out.unsigned(0);
    }
}

_m_CasePattern_read(input: RecordIn): CasePattern {
    var _o970 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o970 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f971 = _o970;
    var _f972 = input.text();
    var _f973 = input.loc();
    var _o974 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v975 = Array<CasePattern>();
        var _n976 = input.count();
        for (var _ in 0.._n976) {
            _v975.append(_m_CasePattern_read(input));
        }
        _o974 = Optional<Array<CasePattern>>.Value(_v975);
    }
    var _f977 = _o974;
    var _o978 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o978 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f979 = _o978;
    var _o980 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v981 = Array<CasePattern>();
        var _n982 = input.count();
        for (var _ in 0.._n982) {
            _v981.append(_m_CasePattern_read(input));
        }
        _o980 = Optional<Array<CasePattern>>.Value(_v981);
    }
    var _f983 = _o980;
    var _f984 = input.flag();
    var _f985 = input.flag();
    var _o986 = Optional<(long, long)>.Empty;
    if (input.unsigned() == 1) {
        var _t987 = input.signed();
        var _t988 = input.signed();
        _o986 = Optional<(long, long)>.Value((_t987, _t988));
    }
    var _f989 = _o986;
    var _o990 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o990 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f991 = _o990;
    return CasePattern(_f971, _f972, _f973, _f977, _f979, _f983, _f984, _f985, _f989, _f991);
}

_m_ClosureLiteral_write(out: RecordOut, value: ClosureLiteral) {
    out.unsigned(value.parameters.count);
    for (var _item992 in value.parameters) {
        _m_VariableDef_write(out, _item992);
    }
    _m_TypeName_write(out, value.ty);
    _m_Block_write(out, value.body);
    out.flag(value.expression_body);
    out.loc(value.loc);
}

_m_ClosureLiteral_read(input: RecordIn): ClosureLiteral {
    var _v993 = Array<VariableDef>();
    var _n994 = input.count();
    for (var _ in 0.._n994) {
        _v993.append(_m_VariableDef_read(input));
    }
    var _f995 = _v993;
    var _f996 = _m_TypeName_read(input);
    var _f997 = _m_Block_read(input);
    var _f998 = input.flag();
    var _f999 = input.loc();
    return ClosureLiteral(_f995, _f996, _f997, _f998, _f999);
}

_m_VariableDef_write(out: RecordOut, value: VariableDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    if (value.default.is_value()) {
        out.unsigned(1);
        _m_Expression_write(out, value.default.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.hidden);
    _m_Kind_write(out, value.kind);
    out.unsigned(value.attributes.count);
    for (var _item1000 in value.attributes) {
        _a_Attribute_write(out, _item1000);
    }
    out.loc(value.loc);
    out.loc(value.type_loc);
    out.flag(value.is_const);
}

_m_VariableDef_read(input: RecordIn): VariableDef {
    var _f1001 = input.text();
    var _f1002 = _m_TypeName_read(input);
    var _o1003 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o1003 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f1004 = _o1003;
    var _f1005 = input.flag();
    var _f1006 = _m_Kind_read(input);
    var _v1007 = Array<ast.Attribute>();
    var _n1008 = input.count();
    for (var _ in 0.._n1008) {
        _v1007.append(_a_Attribute_read(input));
    }
    var _f1009 = _v1007;
    var _f1010 = input.loc();
    var _f1011 = input.loc();
    var _f1012 = input.flag();
    return VariableDef(_f1001, _f1002, _f1004, _f1005, _f1006, _f1009, _f1010, _f1011, _f1012);
}

_m_Kind_write(out: RecordOut, value: Kind) {
    match (value) {
        Variable => {
            out.unsigned(0);
        }
        Field => {
            out.unsigned(1);
        }
        Param => {
            out.unsigned(2);
        }
    }
}

_m_Kind_read(input: RecordIn): Kind {
    var tag = input.unsigned();
    if (tag == 0) {
        return Kind.Variable;
    }
    if (tag == 1) {
        return Kind.Field;
    }
    if (tag == 2) {
        return Kind.Param;
    }
    input.fail("Kind", tag);
    return Kind.Variable;
}

_m_CountField_write(out: RecordOut, value: CountField) {
    match (value) {
        Strong => {
            out.unsigned(0);
        }
        Weak => {
            out.unsigned(1);
        }
    }
}

_m_CountField_read(input: RecordIn): CountField {
    var tag = input.unsigned();
    if (tag == 0) {
        return CountField.Strong;
    }
    if (tag == 1) {
        return CountField.Weak;
    }
    input.fail("CountField", tag);
    return CountField.Strong;
}

_m_WeakOp_write(out: RecordOut, value: WeakOp) {
    match (value) {
        From => {
            out.unsigned(0);
        }
        Upgrade => {
            out.unsigned(1);
        }
        Expired => {
            out.unsigned(2);
        }
    }
}

_m_WeakOp_read(input: RecordIn): WeakOp {
    var tag = input.unsigned();
    if (tag == 0) {
        return WeakOp.From;
    }
    if (tag == 1) {
        return WeakOp.Upgrade;
    }
    if (tag == 2) {
        return WeakOp.Expired;
    }
    input.fail("WeakOp", tag);
    return WeakOp.From;
}

_m_SimdOp_write(out: RecordOut, value: SimdOp) {
    match (value) {
        Splat => {
            out.unsigned(0);
        }
        Add => {
            out.unsigned(1);
        }
        Subtract => {
            out.unsigned(2);
        }
        Multiply => {
            out.unsigned(3);
        }
        Divide => {
            out.unsigned(4);
        }
        Remainder => {
            out.unsigned(5);
        }
        And => {
            out.unsigned(6);
        }
        Or => {
            out.unsigned(7);
        }
        Xor => {
            out.unsigned(8);
        }
        ShiftLeft => {
            out.unsigned(9);
        }
        ShiftRight => {
            out.unsigned(10);
        }
        Negate => {
            out.unsigned(11);
        }
        Not => {
            out.unsigned(12);
        }
        Equal => {
            out.unsigned(13);
        }
        NotEqual => {
            out.unsigned(14);
        }
        Less => {
            out.unsigned(15);
        }
        LessEqual => {
            out.unsigned(16);
        }
        Greater => {
            out.unsigned(17);
        }
        GreaterEqual => {
            out.unsigned(18);
        }
        Select => {
            out.unsigned(19);
        }
        Minimum => {
            out.unsigned(20);
        }
        Maximum => {
            out.unsigned(21);
        }
        Abs => {
            out.unsigned(22);
        }
        RotateLeft => {
            out.unsigned(23);
        }
        RotateRight => {
            out.unsigned(24);
        }
        SquareRoot => {
            out.unsigned(25);
        }
        Floor => {
            out.unsigned(26);
        }
        Ceiling => {
            out.unsigned(27);
        }
        Sum => {
            out.unsigned(28);
        }
        ReduceMinimum => {
            out.unsigned(29);
        }
        ReduceMaximum => {
            out.unsigned(30);
        }
        Any => {
            out.unsigned(31);
        }
        All => {
            out.unsigned(32);
        }
        ToBits => {
            out.unsigned(33);
        }
        Extract => {
            out.unsigned(34);
        }
        Insert => {
            out.unsigned(35);
        }
        Shuffle => {
            out.unsigned(36);
        }
        Reverse => {
            out.unsigned(37);
        }
        InterleaveLow => {
            out.unsigned(38);
        }
        InterleaveHigh => {
            out.unsigned(39);
        }
        Load => {
            out.unsigned(40);
        }
        LoadAligned => {
            out.unsigned(41);
        }
        Store => {
            out.unsigned(42);
        }
        StoreAligned => {
            out.unsigned(43);
        }
        Convert => {
            out.unsigned(44);
        }
        Reinterpret => {
            out.unsigned(45);
        }
        Lanes => {
            out.unsigned(46);
        }
        LaneBits => {
            out.unsigned(47);
        }
        IsSigned => {
            out.unsigned(48);
        }
    }
}

_m_SimdOp_read(input: RecordIn): SimdOp {
    var tag = input.unsigned();
    if (tag == 0) {
        return SimdOp.Splat;
    }
    if (tag == 1) {
        return SimdOp.Add;
    }
    if (tag == 2) {
        return SimdOp.Subtract;
    }
    if (tag == 3) {
        return SimdOp.Multiply;
    }
    if (tag == 4) {
        return SimdOp.Divide;
    }
    if (tag == 5) {
        return SimdOp.Remainder;
    }
    if (tag == 6) {
        return SimdOp.And;
    }
    if (tag == 7) {
        return SimdOp.Or;
    }
    if (tag == 8) {
        return SimdOp.Xor;
    }
    if (tag == 9) {
        return SimdOp.ShiftLeft;
    }
    if (tag == 10) {
        return SimdOp.ShiftRight;
    }
    if (tag == 11) {
        return SimdOp.Negate;
    }
    if (tag == 12) {
        return SimdOp.Not;
    }
    if (tag == 13) {
        return SimdOp.Equal;
    }
    if (tag == 14) {
        return SimdOp.NotEqual;
    }
    if (tag == 15) {
        return SimdOp.Less;
    }
    if (tag == 16) {
        return SimdOp.LessEqual;
    }
    if (tag == 17) {
        return SimdOp.Greater;
    }
    if (tag == 18) {
        return SimdOp.GreaterEqual;
    }
    if (tag == 19) {
        return SimdOp.Select;
    }
    if (tag == 20) {
        return SimdOp.Minimum;
    }
    if (tag == 21) {
        return SimdOp.Maximum;
    }
    if (tag == 22) {
        return SimdOp.Abs;
    }
    if (tag == 23) {
        return SimdOp.RotateLeft;
    }
    if (tag == 24) {
        return SimdOp.RotateRight;
    }
    if (tag == 25) {
        return SimdOp.SquareRoot;
    }
    if (tag == 26) {
        return SimdOp.Floor;
    }
    if (tag == 27) {
        return SimdOp.Ceiling;
    }
    if (tag == 28) {
        return SimdOp.Sum;
    }
    if (tag == 29) {
        return SimdOp.ReduceMinimum;
    }
    if (tag == 30) {
        return SimdOp.ReduceMaximum;
    }
    if (tag == 31) {
        return SimdOp.Any;
    }
    if (tag == 32) {
        return SimdOp.All;
    }
    if (tag == 33) {
        return SimdOp.ToBits;
    }
    if (tag == 34) {
        return SimdOp.Extract;
    }
    if (tag == 35) {
        return SimdOp.Insert;
    }
    if (tag == 36) {
        return SimdOp.Shuffle;
    }
    if (tag == 37) {
        return SimdOp.Reverse;
    }
    if (tag == 38) {
        return SimdOp.InterleaveLow;
    }
    if (tag == 39) {
        return SimdOp.InterleaveHigh;
    }
    if (tag == 40) {
        return SimdOp.Load;
    }
    if (tag == 41) {
        return SimdOp.LoadAligned;
    }
    if (tag == 42) {
        return SimdOp.Store;
    }
    if (tag == 43) {
        return SimdOp.StoreAligned;
    }
    if (tag == 44) {
        return SimdOp.Convert;
    }
    if (tag == 45) {
        return SimdOp.Reinterpret;
    }
    if (tag == 46) {
        return SimdOp.Lanes;
    }
    if (tag == 47) {
        return SimdOp.LaneBits;
    }
    if (tag == 48) {
        return SimdOp.IsSigned;
    }
    input.fail("SimdOp", tag);
    return SimdOp.Splat;
}

_m_AtomicFetchOp_write(out: RecordOut, value: AtomicFetchOp) {
    match (value) {
        Add => {
            out.unsigned(0);
        }
        Sub => {
            out.unsigned(1);
        }
        And => {
            out.unsigned(2);
        }
        Or => {
            out.unsigned(3);
        }
        Xor => {
            out.unsigned(4);
        }
    }
}

_m_AtomicFetchOp_read(input: RecordIn): AtomicFetchOp {
    var tag = input.unsigned();
    if (tag == 0) {
        return AtomicFetchOp.Add;
    }
    if (tag == 1) {
        return AtomicFetchOp.Sub;
    }
    if (tag == 2) {
        return AtomicFetchOp.And;
    }
    if (tag == 3) {
        return AtomicFetchOp.Or;
    }
    if (tag == 4) {
        return AtomicFetchOp.Xor;
    }
    input.fail("AtomicFetchOp", tag);
    return AtomicFetchOp.Add;
}

_m_CastKind_write(out: RecordOut, value: CastKind) {
    match (value) {
        Static => {
            out.unsigned(0);
        }
        Unsafe => {
            out.unsigned(1);
        }
        Synthesized => {
            out.unsigned(2);
        }
    }
}

_m_CastKind_read(input: RecordIn): CastKind {
    var tag = input.unsigned();
    if (tag == 0) {
        return CastKind.Static;
    }
    if (tag == 1) {
        return CastKind.Unsafe;
    }
    if (tag == 2) {
        return CastKind.Synthesized;
    }
    input.fail("CastKind", tag);
    return CastKind.Static;
}

_m_UnaryOp_write(out: RecordOut, value: UnaryOp) {
    match (value) {
        Neg => {
            out.unsigned(0);
        }
        Pos => {
            out.unsigned(1);
        }
        PreInc => {
            out.unsigned(2);
        }
        PostInc => {
            out.unsigned(3);
        }
        PreDec => {
            out.unsigned(4);
        }
        PostDec => {
            out.unsigned(5);
        }
        LogicalNot => {
            out.unsigned(6);
        }
        BitNot => {
            out.unsigned(7);
        }
    }
}

_m_UnaryOp_read(input: RecordIn): UnaryOp {
    var tag = input.unsigned();
    if (tag == 0) {
        return UnaryOp.Neg;
    }
    if (tag == 1) {
        return UnaryOp.Pos;
    }
    if (tag == 2) {
        return UnaryOp.PreInc;
    }
    if (tag == 3) {
        return UnaryOp.PostInc;
    }
    if (tag == 4) {
        return UnaryOp.PreDec;
    }
    if (tag == 5) {
        return UnaryOp.PostDec;
    }
    if (tag == 6) {
        return UnaryOp.LogicalNot;
    }
    if (tag == 7) {
        return UnaryOp.BitNot;
    }
    input.fail("UnaryOp", tag);
    return UnaryOp.Neg;
}

_m_BinaryOp_write(out: RecordOut, value: BinaryOp) {
    match (value) {
        Add => {
            out.unsigned(0);
        }
        Sub => {
            out.unsigned(1);
        }
        Mul => {
            out.unsigned(2);
        }
        Div => {
            out.unsigned(3);
        }
        Mod => {
            out.unsigned(4);
        }
        Pow => {
            out.unsigned(5);
        }
        Identical => {
            out.unsigned(6);
        }
        NotIdentical => {
            out.unsigned(7);
        }
        Equal => {
            out.unsigned(8);
        }
        NotEqual => {
            out.unsigned(9);
        }
        Less => {
            out.unsigned(10);
        }
        LessEqual => {
            out.unsigned(11);
        }
        Greater => {
            out.unsigned(12);
        }
        GreaterEqual => {
            out.unsigned(13);
        }
        LShift => {
            out.unsigned(14);
        }
        RShift => {
            out.unsigned(15);
        }
        BitAnd => {
            out.unsigned(16);
        }
        BitOr => {
            out.unsigned(17);
        }
        BitXor => {
            out.unsigned(18);
        }
        LogicalAnd => {
            out.unsigned(19);
        }
        LogicalOr => {
            out.unsigned(20);
        }
        Assign => {
            out.unsigned(21);
        }
        AddAssign => {
            out.unsigned(22);
        }
        SubAssign => {
            out.unsigned(23);
        }
        MulAssign => {
            out.unsigned(24);
        }
        DivAssign => {
            out.unsigned(25);
        }
        ModAssign => {
            out.unsigned(26);
        }
        LShiftAssign => {
            out.unsigned(27);
        }
        RShiftAssign => {
            out.unsigned(28);
        }
        BitAndAssign => {
            out.unsigned(29);
        }
        BitOrAssign => {
            out.unsigned(30);
        }
        BitXorAssign => {
            out.unsigned(31);
        }
        WrappingAdd => {
            out.unsigned(32);
        }
        WrappingSub => {
            out.unsigned(33);
        }
        WrappingMul => {
            out.unsigned(34);
        }
        AddOverflows => {
            out.unsigned(35);
        }
        SubOverflows => {
            out.unsigned(36);
        }
        MulOverflows => {
            out.unsigned(37);
        }
    }
}

_m_BinaryOp_read(input: RecordIn): BinaryOp {
    var tag = input.unsigned();
    if (tag == 0) {
        return BinaryOp.Add;
    }
    if (tag == 1) {
        return BinaryOp.Sub;
    }
    if (tag == 2) {
        return BinaryOp.Mul;
    }
    if (tag == 3) {
        return BinaryOp.Div;
    }
    if (tag == 4) {
        return BinaryOp.Mod;
    }
    if (tag == 5) {
        return BinaryOp.Pow;
    }
    if (tag == 6) {
        return BinaryOp.Identical;
    }
    if (tag == 7) {
        return BinaryOp.NotIdentical;
    }
    if (tag == 8) {
        return BinaryOp.Equal;
    }
    if (tag == 9) {
        return BinaryOp.NotEqual;
    }
    if (tag == 10) {
        return BinaryOp.Less;
    }
    if (tag == 11) {
        return BinaryOp.LessEqual;
    }
    if (tag == 12) {
        return BinaryOp.Greater;
    }
    if (tag == 13) {
        return BinaryOp.GreaterEqual;
    }
    if (tag == 14) {
        return BinaryOp.LShift;
    }
    if (tag == 15) {
        return BinaryOp.RShift;
    }
    if (tag == 16) {
        return BinaryOp.BitAnd;
    }
    if (tag == 17) {
        return BinaryOp.BitOr;
    }
    if (tag == 18) {
        return BinaryOp.BitXor;
    }
    if (tag == 19) {
        return BinaryOp.LogicalAnd;
    }
    if (tag == 20) {
        return BinaryOp.LogicalOr;
    }
    if (tag == 21) {
        return BinaryOp.Assign;
    }
    if (tag == 22) {
        return BinaryOp.AddAssign;
    }
    if (tag == 23) {
        return BinaryOp.SubAssign;
    }
    if (tag == 24) {
        return BinaryOp.MulAssign;
    }
    if (tag == 25) {
        return BinaryOp.DivAssign;
    }
    if (tag == 26) {
        return BinaryOp.ModAssign;
    }
    if (tag == 27) {
        return BinaryOp.LShiftAssign;
    }
    if (tag == 28) {
        return BinaryOp.RShiftAssign;
    }
    if (tag == 29) {
        return BinaryOp.BitAndAssign;
    }
    if (tag == 30) {
        return BinaryOp.BitOrAssign;
    }
    if (tag == 31) {
        return BinaryOp.BitXorAssign;
    }
    if (tag == 32) {
        return BinaryOp.WrappingAdd;
    }
    if (tag == 33) {
        return BinaryOp.WrappingSub;
    }
    if (tag == 34) {
        return BinaryOp.WrappingMul;
    }
    if (tag == 35) {
        return BinaryOp.AddOverflows;
    }
    if (tag == 36) {
        return BinaryOp.SubOverflows;
    }
    if (tag == 37) {
        return BinaryOp.MulOverflows;
    }
    input.fail("BinaryOp", tag);
    return BinaryOp.Add;
}

_m_LoopBreakKind_write(out: RecordOut, value: LoopBreakKind) {
    match (value) {
        Break => {
            out.unsigned(0);
        }
        Continue => {
            out.unsigned(1);
        }
    }
}

_m_LoopBreakKind_read(input: RecordIn): LoopBreakKind {
    var tag = input.unsigned();
    if (tag == 0) {
        return LoopBreakKind.Break;
    }
    if (tag == 1) {
        return LoopBreakKind.Continue;
    }
    input.fail("LoopBreakKind", tag);
    return LoopBreakKind.Break;
}

_m_LoopBreak_write(out: RecordOut, value: LoopBreak) {
    _m_LoopBreakKind_write(out, value.kind);
}

_m_LoopBreak_read(input: RecordIn): LoopBreak {
    var _f1013 = _m_LoopBreakKind_read(input);
    return LoopBreak(_f1013);
}

_m_ReturnStatement_write(out: RecordOut, value: ReturnStatement) {
    if (value.expr.is_value()) {
        out.unsigned(1);
        _m_Expression_write(out, value.expr.value());
    } else {
        out.unsigned(0);
    }
    out.loc(value.loc);
}

_m_ReturnStatement_read(input: RecordIn): ReturnStatement {
    var _o1014 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o1014 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f1015 = _o1014;
    var _f1016 = input.loc();
    return ReturnStatement(_f1015, _f1016);
}

_m_While_write(out: RecordOut, value: While) {
    _m_Expression_write(out, value.condition);
    _m_Block_write(out, value.block);
}

_m_While_read(input: RecordIn): While {
    var _f1017 = _m_Expression_read(input);
    var _f1018 = _m_Block_read(input);
    return While(_f1017, _f1018);
}

_m_Branch_write(out: RecordOut, value: Branch) {
    _m_Expression_write(out, value.condition);
    _m_Block_write(out, value.if_block);
    if (value.else_block.is_value()) {
        out.unsigned(1);
        _m_Block_write(out, value.else_block.value());
    } else {
        out.unsigned(0);
    }
}

_m_Branch_read(input: RecordIn): Branch {
    var _f1019 = _m_Expression_read(input);
    var _f1020 = _m_Block_read(input);
    var _o1021 = Optional<Block>.Empty;
    if (input.unsigned() == 1) {
        _o1021 = Optional<Block>.Value(_m_Block_read(input));
    }
    var _f1022 = _o1021;
    return Branch(_f1019, _f1020, _f1022);
}

_m_Declaration_write(out: RecordOut, value: Declaration) {
    match (value) {
        Variable(v) => {
            out.unsigned(0);
            _m_VariableDef_write(out, v);
        }
        Function(v) => {
            out.unsigned(1);
            _m_FunctionDef_write(out, v);
        }
        Struct(v) => {
            out.unsigned(2);
            _m_StructDef_write(out, v);
        }
        Trait(v) => {
            out.unsigned(3);
            _m_TraitDef_write(out, v);
        }
        Extension(v) => {
            out.unsigned(4);
            _m_ExtensionDef_write(out, v);
        }
        Extern(v) => {
            out.unsigned(5);
            _m_ExternDef_write(out, v);
        }
        TypeAlias(v) => {
            out.unsigned(6);
            _m_TypeAliasDef_write(out, v);
        }
    }
}

_m_Declaration_read(input: RecordIn): Declaration {
    var tag = input.unsigned();
    if (tag == 0) {
        var _f1474 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1474);
    }
    if (tag == 1) {
        var _f1475 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1475);
    }
    if (tag == 2) {
        var _f1476 = _m_StructDef_read(input);
        return Declaration.Struct(_f1476);
    }
    if (tag == 3) {
        var _f1477 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1477);
    }
    if (tag == 4) {
        var _f1478 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1478);
    }
    if (tag == 5) {
        var _f1479 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1479);
    }
    if (tag == 6) {
        var _f1480 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1480);
    }
    input.fail("Declaration", tag);
    return _m_Declaration_read(input);
}

_m_TypeAliasDef_write(out: RecordOut, value: TypeAliasDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1023 in value.generic_params) {
        _m_GenericParam_write(out, _item1023);
    }
    _m_TypeName_write(out, value.target);
    out.unsigned(value.attributes.count);
    for (var _item1024 in value.attributes) {
        _a_Attribute_write(out, _item1024);
    }
    out.loc(value.loc);
}

_m_TypeAliasDef_read(input: RecordIn): TypeAliasDef {
    var _f1025 = input.text();
    var _v1026 = Array<GenericParam>();
    var _n1027 = input.count();
    for (var _ in 0.._n1027) {
        _v1026.append(_m_GenericParam_read(input));
    }
    var _f1028 = _v1026;
    var _f1029 = _m_TypeName_read(input);
    var _v1030 = Array<ast.Attribute>();
    var _n1031 = input.count();
    for (var _ in 0.._n1031) {
        _v1030.append(_a_Attribute_read(input));
    }
    var _f1032 = _v1030;
    var _f1033 = input.loc();
    return TypeAliasDef(_f1025, _f1028, _f1029, _f1032, _f1033);
}

_m_GenericParam_write(out: RecordOut, value: GenericParam) {
    out.text(value.name);
    out.loc(value.loc);
    out.unsigned(value.bounds.count);
    for (var _item1034 in value.bounds) {
        _m_Bound_write(out, _item1034);
    }
    if (value.default.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.default.value());
    } else {
        out.unsigned(0);
    }
    out.loc(value.default_loc);
    out.flag(value.is_argument);
}

_m_GenericParam_read(input: RecordIn): GenericParam {
    var _f1035 = input.text();
    var _f1036 = input.loc();
    var _v1037 = Array<Bound>();
    var _n1038 = input.count();
    for (var _ in 0.._n1038) {
        _v1037.append(_m_Bound_read(input));
    }
    var _f1039 = _v1037;
    var _o1040 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1040 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1041 = _o1040;
    var _f1042 = input.loc();
    var _f1043 = input.flag();
    return GenericParam(_f1035, _f1036, _f1039, _f1041, _f1042, _f1043);
}

_m_Bound_write(out: RecordOut, value: Bound) {
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_Bound_read(input: RecordIn): Bound {
    var _f1044 = _m_TypeName_read(input);
    var _f1045 = input.loc();
    return Bound(_f1044, _f1045);
}

_m_ExternDef_write(out: RecordOut, value: ExternDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.parameters.count);
    for (var _item1046 in value.parameters) {
        _m_VariableDef_write(out, _item1046);
    }
    out.flag(value.is_variadic);
    out.unsigned(value.attributes.count);
    for (var _item1047 in value.attributes) {
        _a_Attribute_write(out, _item1047);
    }
    out.loc(value.loc);
}

_m_ExternDef_read(input: RecordIn): ExternDef {
    var _f1048 = input.text();
    var _f1049 = _m_TypeName_read(input);
    var _v1050 = Array<VariableDef>();
    var _n1051 = input.count();
    for (var _ in 0.._n1051) {
        _v1050.append(_m_VariableDef_read(input));
    }
    var _f1052 = _v1050;
    var _f1053 = input.flag();
    var _v1054 = Array<ast.Attribute>();
    var _n1055 = input.count();
    for (var _ in 0.._n1055) {
        _v1054.append(_a_Attribute_read(input));
    }
    var _f1056 = _v1054;
    var _f1057 = input.loc();
    return ExternDef(_f1048, _f1049, _f1052, _f1053, _f1056, _f1057);
}

_m_ExtensionDef_write(out: RecordOut, value: ExtensionDef) {
    _m_TypeName_write(out, value.target);
    if (value.resolved.is_value()) {
        out.unsigned(1);
        out.text(value.resolved.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.traits.count);
    for (var _item1058 in value.traits) {
        _m_TypeName_write(out, _item1058);
    }
    out.unsigned(value.restated.count);
    for (var _item1059 in value.restated) {
        var (_t1060, _t1061) = _item1059;
        out.unsigned(_t1060);
        _m_Bound_write(out, _t1061);
    }
    out.unsigned(value.methods.count);
    for (var _item1062 in value.methods) {
        _m_FunctionDef_write(out, _item1062);
    }
    out.unsigned(value.attributes.count);
    for (var _item1063 in value.attributes) {
        _a_Attribute_write(out, _item1063);
    }
    out.loc(value.loc);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_m_ExtensionDef_read(input: RecordIn): ExtensionDef {
    var _f1064 = _m_TypeName_read(input);
    var _o1065 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1065 = Optional<String>.Value(input.text());
    }
    var _f1066 = _o1065;
    var _v1067 = Array<TypeName>();
    var _n1068 = input.count();
    for (var _ in 0.._n1068) {
        _v1067.append(_m_TypeName_read(input));
    }
    var _f1069 = _v1067;
    var _v1070 = Array<(ulong, Bound)>();
    var _n1071 = input.count();
    for (var _ in 0.._n1071) {
        var _t1072 = input.unsigned();
        var _t1073 = _m_Bound_read(input);
        _v1070.append((_t1072, _t1073));
    }
    var _f1074 = _v1070;
    var _v1075 = Array<FunctionDef>();
    var _n1076 = input.count();
    for (var _ in 0.._n1076) {
        _v1075.append(_m_FunctionDef_read(input));
    }
    var _f1077 = _v1075;
    var _v1078 = Array<ast.Attribute>();
    var _n1079 = input.count();
    for (var _ in 0.._n1079) {
        _v1078.append(_a_Attribute_read(input));
    }
    var _f1080 = _v1078;
    var _f1081 = input.loc();
    var _f1082 = input.flag();
    var _f1083 = input.flag();
    return ExtensionDef(_f1064, _f1066, _f1069, _f1074, _f1077, _f1080, _f1081, _f1082, _f1083);
}

_m_TraitDef_write(out: RecordOut, value: TraitDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1084 in value.generic_params) {
        _m_GenericParam_write(out, _item1084);
    }
    out.unsigned(value.methods.count);
    for (var _item1085 in value.methods) {
        _m_FunctionDef_write(out, _item1085);
    }
    out.unsigned(value.attributes.count);
    for (var _item1086 in value.attributes) {
        _a_Attribute_write(out, _item1086);
    }
    out.loc(value.loc);
}

_m_TraitDef_read(input: RecordIn): TraitDef {
    var _f1087 = input.text();
    var _v1088 = Array<GenericParam>();
    var _n1089 = input.count();
    for (var _ in 0.._n1089) {
        _v1088.append(_m_GenericParam_read(input));
    }
    var _f1090 = _v1088;
    var _v1091 = Array<FunctionDef>();
    var _n1092 = input.count();
    for (var _ in 0.._n1092) {
        _v1091.append(_m_FunctionDef_read(input));
    }
    var _f1093 = _v1091;
    var _v1094 = Array<ast.Attribute>();
    var _n1095 = input.count();
    for (var _ in 0.._n1095) {
        _v1094.append(_a_Attribute_read(input));
    }
    var _f1096 = _v1094;
    var _f1097 = input.loc();
    return TraitDef(_f1087, _f1090, _f1093, _f1096, _f1097);
}

_m_StructDef_write(out: RecordOut, value: StructDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.generic_params.count);
    for (var _item1098 in value.generic_params) {
        _m_GenericParam_write(out, _item1098);
    }
    out.unsigned(value.field_members.count);
    for (var _item1099 in value.field_members) {
        _m_VariableDef_write(out, _item1099);
    }
    out.unsigned(value.method_members.count);
    for (var _item1100 in value.method_members) {
        _m_FunctionDef_write(out, _item1100);
    }
    out.unsigned(value.generic_methods.count);
    for (var _item1101 in value.generic_methods) {
        _m_FunctionDef_write(out, _item1101);
    }
    out.unsigned(value.constructors.count);
    for (var _item1102 in value.constructors) {
        _m_FunctionDef_write(out, _item1102);
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    out.unsigned(value.traits.count);
    for (var _item1103 in value.traits) {
        _m_TypeName_write(out, _item1103);
    }
    out.unsigned(value.attributes.count);
    for (var _item1104 in value.attributes) {
        _a_Attribute_write(out, _item1104);
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item1105 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item1105);
        }
    } else {
        out.unsigned(0);
    }
}

_m_StructDef_read(input: RecordIn): StructDef {
    var _f1106 = input.text();
    var _f1107 = _m_TypeName_read(input);
    var _v1108 = Array<GenericParam>();
    var _n1109 = input.count();
    for (var _ in 0.._n1109) {
        _v1108.append(_m_GenericParam_read(input));
    }
    var _f1110 = _v1108;
    var _v1111 = Array<VariableDef>();
    var _n1112 = input.count();
    for (var _ in 0.._n1112) {
        _v1111.append(_m_VariableDef_read(input));
    }
    var _f1113 = _v1111;
    var _v1114 = Array<FunctionDef>();
    var _n1115 = input.count();
    for (var _ in 0.._n1115) {
        _v1114.append(_m_FunctionDef_read(input));
    }
    var _f1116 = _v1114;
    var _v1117 = Array<FunctionDef>();
    var _n1118 = input.count();
    for (var _ in 0.._n1118) {
        _v1117.append(_m_FunctionDef_read(input));
    }
    var _f1119 = _v1117;
    var _v1120 = Array<FunctionDef>();
    var _n1121 = input.count();
    for (var _ in 0.._n1121) {
        _v1120.append(_m_FunctionDef_read(input));
    }
    var _f1122 = _v1120;
    var _f1123 = _m_FunctionDef_read(input);
    var _f1124 = _m_FunctionDef_read(input);
    var _f1125 = _m_FunctionDef_read(input);
    var _v1126 = Array<TypeName>();
    var _n1127 = input.count();
    for (var _ in 0.._n1127) {
        _v1126.append(_m_TypeName_read(input));
    }
    var _f1128 = _v1126;
    var _v1129 = Array<ast.Attribute>();
    var _n1130 = input.count();
    for (var _ in 0.._n1130) {
        _v1129.append(_a_Attribute_read(input));
    }
    var _f1131 = _v1129;
    var _f1132 = input.loc();
    var _o1133 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v1134 = Array<EnumCaseDef>();
        var _n1135 = input.count();
        for (var _ in 0.._n1135) {
            _v1134.append(_m_EnumCaseDef_read(input));
        }
        _o1133 = Optional<Array<EnumCaseDef>>.Value(_v1134);
    }
    var _f1136 = _o1133;
    return StructDef(
        _f1106, _f1107, _f1110, _f1113, _f1116, _f1119, _f1122, _f1123, _f1124, _f1125, _f1128, _f1131, _f1132, _f1136
    );
}

_m_EnumCaseDef_write(out: RecordOut, value: EnumCaseDef) {
    out.text(value.name);
    out.signed(value.value as long);
    out.unsigned(value.payload.count);
    for (var _item1137 in value.payload) {
        var (_t1138, _t1139) = _item1137;
        out.text(_t1138);
        out.loc(_t1139);
    }
    out.unsigned(value.attributes.count);
    for (var _item1140 in value.attributes) {
        _a_Attribute_write(out, _item1140);
    }
    out.loc(value.loc);
}

_m_EnumCaseDef_read(input: RecordIn): EnumCaseDef {
    var _f1141 = input.text();
    var _f1142 = input.signed();
    var _v1143 = Array<(String, Loc)>();
    var _n1144 = input.count();
    for (var _ in 0.._n1144) {
        var _t1145 = input.text();
        var _t1146 = input.loc();
        _v1143.append((_t1145, _t1146));
    }
    var _f1147 = _v1143;
    var _v1148 = Array<ast.Attribute>();
    var _n1149 = input.count();
    for (var _ in 0.._n1149) {
        _v1148.append(_a_Attribute_read(input));
    }
    var _f1150 = _v1148;
    var _f1151 = input.loc();
    return EnumCaseDef(_f1141, _f1142, _f1147, _f1150, _f1151);
}

_m_ExtensionScopes_write(out: RecordOut, value: ExtensionScopes) {
    var _keys1153 = Array<(u8[], u8[], uint)>();
    for (var _key1152 in value.prelude) {
        var _scratch1154 = out.scratch();
        _scratch1154.unsigned(_key1152 as ulong);
        var _vscratch1156 = out.scratch();
        _keys1153.append((_scratch1154.finish(), _vscratch1156.finish(), _key1152));
    }
    _keys1153.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys1153.count);
    for (var (_bytes1155, _, _key1152) in _keys1153) {
        out.unsigned(_key1152 as ulong);
    }
    out.unsigned(value.visible.count);
    for (var _item1157 in value.visible) {
        var _keys1159 = Array<(u8[], u8[], uint)>();
        for (var _key1158 in _item1157) {
            var _scratch1160 = out.scratch();
            _scratch1160.unsigned(_key1158 as ulong);
            var _vscratch1162 = out.scratch();
            _keys1159.append((_scratch1160.finish(), _vscratch1162.finish(), _key1158));
        }
        _keys1159.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1159.count);
        for (var (_bytes1161, _, _key1158) in _keys1159) {
            out.unsigned(_key1158 as ulong);
        }
    }
    out.unsigned(value.module.count);
    for (var _item1163 in value.module) {
        if (_item1163.is_value()) {
            out.unsigned(1);
            out.unsigned(_item1163.value() as ulong);
        } else {
            out.unsigned(0);
        }
    }
}

_m_ExtensionScopes_read(input: RecordIn): ExtensionScopes {
    var _v1164 = HashSet<uint>();
    var _n1165 = input.count();
    for (var _ in 0.._n1165) {
        _v1164.insert(input.unsigned() as uint);
    }
    var _f1166 = _v1164;
    var _v1167 = Array<HashSet<uint>>();
    var _n1168 = input.count();
    for (var _ in 0.._n1168) {
        var _v1169 = HashSet<uint>();
        var _n1170 = input.count();
        for (var _ in 0.._n1170) {
            _v1169.insert(input.unsigned() as uint);
        }
        _v1167.append(_v1169);
    }
    var _f1171 = _v1167;
    var _v1172 = Array<Optional<uint>>();
    var _n1173 = input.count();
    for (var _ in 0.._n1173) {
        var _o1174 = Optional<uint>.Empty;
        if (input.unsigned() == 1) {
            _o1174 = Optional<uint>.Value(input.unsigned() as uint);
        }
        _v1172.append(_o1174);
    }
    var _f1175 = _v1172;
    return ExtensionScopes(_f1166, _f1171, _f1175);
}

_m_Conversion_write(out: RecordOut, value: Conversion) {
    out.loc(value.at);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.constructor);
}

_m_Conversion_read(input: RecordIn): Conversion {
    var _f1176 = input.loc();
    var _f1177 = _m_TypeName_read(input);
    var _f1178 = _m_TypeName_read(input);
    var _f1179 = input.loc();
    return Conversion(_f1176, _f1177, _f1178, _f1179);
}

_m_TraitType_write(out: RecordOut, value: TraitType) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.methods.count);
    for (var _item1180 in value.methods) {
        _m_FunctionDef_write(out, _item1180);
    }
}

_m_TraitType_read(input: RecordIn): TraitType {
    var _f1181 = _m_TypeName_read(input);
    var _v1182 = Array<FunctionDef>();
    var _n1183 = input.count();
    for (var _ in 0.._n1183) {
        _v1182.append(_m_FunctionDef_read(input));
    }
    var _f1184 = _v1182;
    return TraitType(_f1181, _f1184);
}

_m_UseContext_write(out: RecordOut, value: UseContext) {
    out.unsigned(value.scope.count);
    for (var _item1185 in value.scope) {
        _m_GenericParam_write(out, _item1185);
    }
    if (value.extension.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.extension.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.conditions.count);
    for (var _item1186 in value.conditions) {
        _a_Attribute_write(out, _item1186);
    }
}

_m_UseContext_read(input: RecordIn): UseContext {
    var _v1187 = Array<GenericParam>();
    var _n1188 = input.count();
    for (var _ in 0.._n1188) {
        _v1187.append(_m_GenericParam_read(input));
    }
    var _f1189 = _v1187;
    var _o1190 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1190 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1191 = _o1190;
    var _v1192 = Array<ast.Attribute>();
    var _n1193 = input.count();
    for (var _ in 0.._n1193) {
        _v1192.append(_a_Attribute_read(input));
    }
    var _f1194 = _v1192;
    return UseContext(_f1189, _f1191, _f1194);
}

_m_TypeUse_write(out: RecordOut, value: TypeUse) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1195 in value.args) {
        out.loc(_item1195);
    }
    out.unsigned(value.context);
}

_m_TypeUse_read(input: RecordIn): TypeUse {
    var _f1196 = _m_TypeName_read(input);
    var _v1197 = Array<Loc>();
    var _n1198 = input.count();
    for (var _ in 0.._n1198) {
        _v1197.append(input.loc());
    }
    var _f1199 = _v1197;
    var _f1200 = input.unsigned();
    return TypeUse(_f1196, _f1199, _f1200);
}

_m_PropertyDef_write(out: RecordOut, value: PropertyDef) {
    out.text(value.name);
    out.text(value.owner);
    out.flag(value.in_trait);
    out.loc(value.loc);
    _m_AccessorKind_write(out, value.get);
    if (value.set.is_value()) {
        out.unsigned(1);
        _m_AccessorKind_write(out, value.set.value());
    } else {
        out.unsigned(0);
    }
    out.loc(value.set_loc);
    if (value.storage.is_value()) {
        out.unsigned(1);
        out.text(value.storage.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.shared);
}

_m_PropertyDef_read(input: RecordIn): PropertyDef {
    var _f1201 = input.text();
    var _f1202 = input.text();
    var _f1203 = input.flag();
    var _f1204 = input.loc();
    var _f1205 = _m_AccessorKind_read(input);
    var _o1206 = Optional<AccessorKind>.Empty;
    if (input.unsigned() == 1) {
        _o1206 = Optional<AccessorKind>.Value(_m_AccessorKind_read(input));
    }
    var _f1207 = _o1206;
    var _f1208 = input.loc();
    var _o1209 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1209 = Optional<String>.Value(input.text());
    }
    var _f1210 = _o1209;
    var _f1211 = input.flag();
    return PropertyDef(_f1201, _f1202, _f1203, _f1204, _f1205, _f1207, _f1208, _f1210, _f1211);
}

_m_AccessorKind_write(out: RecordOut, value: AccessorKind) {
    match (value) {
        Default => {
            out.unsigned(0);
        }
        Body => {
            out.unsigned(1);
        }
    }
}

_m_AccessorKind_read(input: RecordIn): AccessorKind {
    var tag = input.unsigned();
    if (tag == 0) {
        return AccessorKind.Default;
    }
    if (tag == 1) {
        return AccessorKind.Body;
    }
    input.fail("AccessorKind", tag);
    return AccessorKind.Default;
}

_m_Withheld_write(out: RecordOut, value: Withheld) {
    out.text(value.owner);
    out.text(value.member);
    out.text(value.name);
    out.unsigned(value.params);
    _m_TypeName_write(out, value.arg);
    _m_TypeName_write(out, value.bound);
    out.loc(value.at);
}

_m_Withheld_read(input: RecordIn): Withheld {
    var _f1212 = input.text();
    var _f1213 = input.text();
    var _f1214 = input.text();
    var _f1215 = input.unsigned();
    var _f1216 = _m_TypeName_read(input);
    var _f1217 = _m_TypeName_read(input);
    var _f1218 = input.loc();
    return Withheld(_f1212, _f1213, _f1214, _f1215, _f1216, _f1217, _f1218);
}

_m_EnumDef_write(out: RecordOut, value: EnumDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.representation);
    out.unsigned(value.cases.count);
    for (var _item1219 in value.cases) {
        _m_EnumCaseDef_write(out, _item1219);
    }
    out.unsigned(value.attributes.count);
    for (var _item1220 in value.attributes) {
        _a_Attribute_write(out, _item1220);
    }
    out.loc(value.loc);
}

_m_EnumDef_read(input: RecordIn): EnumDef {
    var _f1221 = input.text();
    var _f1222 = _m_TypeName_read(input);
    var _v1223 = Array<EnumCaseDef>();
    var _n1224 = input.count();
    for (var _ in 0.._n1224) {
        _v1223.append(_m_EnumCaseDef_read(input));
    }
    var _f1225 = _v1223;
    var _v1226 = Array<ast.Attribute>();
    var _n1227 = input.count();
    for (var _ in 0.._n1227) {
        _v1226.append(_a_Attribute_read(input));
    }
    var _f1228 = _v1226;
    var _f1229 = input.loc();
    return EnumDef(_f1221, _f1222, _f1225, _f1228, _f1229);
}

_m_ModuleStaticBlock_write(out: RecordOut, value: ModuleStaticBlock) {
    _m_StaticBlock_write(out, value.block);
    out.unsigned(value.constants.count);
    for (var _item1230 in value.constants) {
        var (_t1231, _t1232) = _item1230;
        out.text(_t1231);
        out.loc(_t1232);
    }
}

_m_ModuleStaticBlock_read(input: RecordIn): ModuleStaticBlock {
    var _f1233 = _m_StaticBlock_read(input);
    var _v1234 = Array<(String, Loc)>();
    var _n1235 = input.count();
    for (var _ in 0.._n1235) {
        var _t1236 = input.text();
        var _t1237 = input.loc();
        _v1234.append((_t1236, _t1237));
    }
    var _f1238 = _v1234;
    return ModuleStaticBlock(_f1233, _f1238);
}

_a_Import_write(out: RecordOut, value: ast.Import) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    if (value.alias.is_value()) {
        out.unsigned(1);
        out.text(value.alias.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.is_local);
    if (value.symbols.is_value()) {
        out.unsigned(1);
        out.unsigned(value.symbols.value().count);
        for (var _item1239 in value.symbols.value()) {
            _a_ImportedSymbol_write(out, _item1239);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.reexport);
    out.unsigned(value.attributes.count);
    for (var _item1240 in value.attributes) {
        _a_Attribute_write(out, _item1240);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Import_read(input: RecordIn): ast.Import {
    var _f1241 = input.text();
    var _s1242 = input.unsigned();
    var _f1243 = ast.Span(_s1242, input.unsigned());
    var _o1244 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1244 = Optional<String>.Value(input.text());
    }
    var _f1245 = _o1244;
    var _f1246 = input.flag();
    var _o1247 = Optional<Array<ast.ImportedSymbol>>.Empty;
    if (input.unsigned() == 1) {
        var _v1248 = Array<ast.ImportedSymbol>();
        var _n1249 = input.count();
        for (var _ in 0.._n1249) {
            _v1248.append(_a_ImportedSymbol_read(input));
        }
        _o1247 = Optional<Array<ast.ImportedSymbol>>.Value(_v1248);
    }
    var _f1250 = _o1247;
    var _f1251 = input.flag();
    var _v1252 = Array<ast.Attribute>();
    var _n1253 = input.count();
    for (var _ in 0.._n1253) {
        _v1252.append(_a_Attribute_read(input));
    }
    var _f1254 = _v1252;
    var _s1255 = input.unsigned();
    var _f1256 = ast.Span(_s1255, input.unsigned());
    var value = ast.Import();
    value.name = _f1241;
    value.name_span = _f1243;
    value.alias = _f1245;
    value.is_local = _f1246;
    value.symbols = _f1250;
    value.reexport = _f1251;
    value.attributes = _f1254;
    value.span = _f1256;
    return value;
}

_a_ImportedSymbol_write(out: RecordOut, value: ast.ImportedSymbol) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    if (value.alias.is_value()) {
        out.unsigned(1);
        out.text(value.alias.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_ImportedSymbol_read(input: RecordIn): ast.ImportedSymbol {
    var _f1257 = input.text();
    var _s1258 = input.unsigned();
    var _f1259 = ast.Span(_s1258, input.unsigned());
    var _o1260 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1260 = Optional<String>.Value(input.text());
    }
    var _f1261 = _o1260;
    var _s1262 = input.unsigned();
    var _f1263 = ast.Span(_s1262, input.unsigned());
    var value = ast.ImportedSymbol();
    value.name = _f1257;
    value.name_span = _f1259;
    value.alias = _f1261;
    value.span = _f1263;
    return value;
}

_m_Module_write_delta(out: RecordOut, value: Module, base: DeltaBase, next: DeltaBase) {
    ulong _mark = out.values.count;
    var _hits1482 = HashSet<long>();
    ulong _nj1483 = 0;
    out.unsigned(value.imports.count);
    for (var _item1481 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1481);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("imports", hash);
        next.add_hashed("imports", hash, _nj1483);
        _nj1483 += 1;
        if (at >= 0) {
            _hits1482.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _a_Import_write(out, _item1481);
        }
    }
    base.missed("imports", "imports", _hits1482.count);
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _struct_hits1489 = HashSet<long>();
    ulong _nj1490 = 0;
    out.unsigned(value.structs.count);
    for (var _item1488 in value.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1488);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("s", hash);
        var named = base.named("s", _item1488.name);
        next.add_hashed("s", hash, _nj1490);
        next.name("s", _item1488.name, _nj1490);
        _patch_s_index(_item1488, next, _nj1490);
        _nj1490 += 1;
        ulong _before = out.values.count;
        if (at >= 0) {
            _struct_hits1489.insert(at);
        } else if (named >= 0) {
            _struct_hits1489.insert(named);
        }
        if (at >= 0) {
            out.unsigned((at as ulong) * 2 + 1);
        } else if (named >= 0) {
            out.unsigned(2);
            out.unsigned(named as ulong);
            _patch_s_write(out, _item1488, base, named as ulong);
            base.count("s patched", out.values.count - _before);
        } else {
            out.unsigned(0);
            _m_StructDef_write(out, _item1488);
            base.count("s new", out.values.count - _before);
        }
    }
    base.missed("s", "s", _struct_hits1489.count);
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1496 = HashSet<long>();
    ulong _nj1497 = 0;
    out.unsigned(value.traits.count);
    for (var _item1495 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1495);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("traits", hash);
        next.add_hashed("traits", hash, _nj1497);
        _nj1497 += 1;
        if (at >= 0) {
            _hits1496.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TraitDef_write(out, _item1495);
        }
    }
    base.missed("traits", "traits", _hits1496.count);
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1503 = HashSet<long>();
    ulong _nj1504 = 0;
    out.unsigned(value.extensions.count);
    for (var _item1502 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1502);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("extensions", hash);
        next.add_hashed("extensions", hash, _nj1504);
        _nj1504 += 1;
        if (at >= 0) {
            _hits1503.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_ExtensionDef_write(out, _item1502);
        }
    }
    base.missed("extensions", "extensions", _hits1503.count);
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1510 = HashSet<long>();
    ulong _nj1511 = 0;
    out.unsigned(value.functions.count);
    for (var _item1509 in value.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1509);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("functions", hash);
        next.add_hashed("functions", hash, _nj1511);
        _nj1511 += 1;
        if (at >= 0) {
            _hits1510.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item1509);
        }
    }
    base.missed("functions", "functions", _hits1510.count);
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1517 = HashSet<long>();
    ulong _nj1518 = 0;
    out.unsigned(value.externs.count);
    for (var _item1516 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1516);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("externs", hash);
        next.add_hashed("externs", hash, _nj1518);
        _nj1518 += 1;
        if (at >= 0) {
            _hits1517.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_ExternDef_write(out, _item1516);
        }
    }
    base.missed("externs", "externs", _hits1517.count);
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1524 = HashSet<long>();
    ulong _nj1525 = 0;
    out.unsigned(value.globals.count);
    for (var _item1523 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1523);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("globals", hash);
        next.add_hashed("globals", hash, _nj1525);
        _nj1525 += 1;
        if (at >= 0) {
            _hits1524.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_VariableDef_write(out, _item1523);
        }
    }
    base.missed("globals", "globals", _hits1524.count);
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1531 = HashSet<long>();
    ulong _nj1532 = 0;
    out.unsigned(value.static_blocks.count);
    for (var _item1530 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1530);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("static_blocks", hash);
        next.add_hashed("static_blocks", hash, _nj1532);
        _nj1532 += 1;
        if (at >= 0) {
            _hits1531.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_ModuleStaticBlock_write(out, _item1530);
        }
    }
    base.missed("static_blocks", "static_blocks", _hits1531.count);
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1538 = HashSet<long>();
    ulong _nj1539 = 0;
    out.unsigned(value.enums.count);
    for (var _item1537 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1537);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("enums", hash);
        next.add_hashed("enums", hash, _nj1539);
        _nj1539 += 1;
        if (at >= 0) {
            _hits1538.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_EnumDef_write(out, _item1537);
        }
    }
    base.missed("enums", "enums", _hits1538.count);
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1545 = HashSet<long>();
    ulong _nj1546 = 0;
    out.unsigned(value.struct_specs.count);
    for (var _item1544 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1544);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("struct_specs", hash);
        next.add_hashed("struct_specs", hash, _nj1546);
        _nj1546 += 1;
        if (at >= 0) {
            _hits1545.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeName_write(out, _item1544);
        }
    }
    base.missed("struct_specs", "struct_specs", _hits1545.count);
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1552 = HashSet<long>();
    ulong _nj1553 = 0;
    out.unsigned(value.func_specs.count);
    for (var _item1551 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1551);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("func_specs", hash);
        next.add_hashed("func_specs", hash, _nj1553);
        _nj1553 += 1;
        if (at >= 0) {
            _hits1552.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeName_write(out, _item1551);
        }
    }
    base.missed("func_specs", "func_specs", _hits1552.count);
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1559 = HashSet<long>();
    ulong _nj1560 = 0;
    out.unsigned(value.type_aliases.count);
    for (var _item1558 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1558);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1559.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1558);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1559.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1566 = HashSet<long>();
    ulong _nj1567 = 0;
    out.unsigned(value.withheld.count);
    for (var _item1565 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1565);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("withheld", hash);
        next.add_hashed("withheld", hash, _nj1567);
        _nj1567 += 1;
        if (at >= 0) {
            _hits1566.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_Withheld_write(out, _item1565);
        }
    }
    base.missed("withheld", "withheld", _hits1566.count);
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1573 = HashSet<long>();
    ulong _nj1574 = 0;
    out.unsigned(value.properties.count);
    for (var _item1572 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1572);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("properties", hash);
        next.add_hashed("properties", hash, _nj1574);
        _nj1574 += 1;
        if (at >= 0) {
            _hits1573.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_PropertyDef_write(out, _item1572);
        }
    }
    base.missed("properties", "properties", _hits1573.count);
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1580 = HashSet<long>();
    ulong _nj1581 = 0;
    out.unsigned(value.type_uses.count);
    for (var _item1579 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1579);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_uses", hash);
        next.add_hashed("type_uses", hash, _nj1581);
        _nj1581 += 1;
        if (at >= 0) {
            _hits1580.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeUse_write(out, _item1579);
        }
    }
    base.missed("type_uses", "type_uses", _hits1580.count);
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1587 = HashSet<long>();
    ulong _nj1588 = 0;
    out.unsigned(value.use_contexts.count);
    for (var _item1586 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1586);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("use_contexts", hash);
        next.add_hashed("use_contexts", hash, _nj1588);
        _nj1588 += 1;
        if (at >= 0) {
            _hits1587.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_UseContext_write(out, _item1586);
        }
    }
    base.missed("use_contexts", "use_contexts", _hits1587.count);
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1595 = base.size("literal_args");
    var _scratch1594 = base.scratch();
    if (value.literal_args.count >= _n1595) {
        for (var _i1596 in 0.._n1595) {
            var (_t1597, _t1598, _t1599) = value.literal_args[_i1596];
            _scratch1594.loc(_t1597);
            _scratch1594.unsigned(_t1598);
            _scratch1594.loc(_t1599);
        }
    }
    if (value.literal_args.count >= _n1595 and base.same_list("literal_args", _scratch1594)) {
        out.unsigned(1);
        out.unsigned(_n1595);
        out.unsigned(value.literal_args.count - _n1595);
        for (var _i1596 in _n1595..value.literal_args.count) {
            var (_t1600, _t1601, _t1602) = value.literal_args[_i1596];
            out.loc(_t1600);
            out.unsigned(_t1601);
            out.loc(_t1602);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1603 in value.literal_args) {
            var (_t1604, _t1605, _t1606) = _item1603;
            out.loc(_t1604);
            out.unsigned(_t1605);
            out.loc(_t1606);
        }
        base.count("literal_args whole", 0);
    }
    var _xscratch1619 = next.scratch();
    for (var _xitem1620 in value.literal_args) {
        var (_t1621, _t1622, _t1623) = _xitem1620;
        _xscratch1619.loc(_t1621);
        _xscratch1619.unsigned(_t1622);
        _xscratch1619.loc(_t1623);
    }
    next.keep_list("literal_args", value.literal_args.count, _xscratch1619);
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1625 = HashSet<long>();
    ulong _nj1626 = 0;
    out.unsigned(value.constrained_aliases.count);
    for (var _item1624 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1624);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("constrained_aliases", hash);
        next.add_hashed("constrained_aliases", hash, _nj1626);
        _nj1626 += 1;
        if (at >= 0) {
            _hits1625.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1624);
        }
    }
    base.missed("constrained_aliases", "constrained_aliases", _hits1625.count);
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1632 = HashSet<long>();
    ulong _nj1633 = 0;
    out.unsigned(value.trait_types.count);
    for (var _item1631 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1631);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("trait_types", hash);
        next.add_hashed("trait_types", hash, _nj1633);
        _nj1633 += 1;
        if (at >= 0) {
            _hits1632.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TraitType_write(out, _item1631);
        }
    }
    base.missed("trait_types", "trait_types", _hits1632.count);
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1639 = HashSet<long>();
    ulong _nj1640 = 0;
    out.unsigned(value.conversions.count);
    for (var _item1638 in value.conversions) {
        var scratch = base.scratch();
        _m_Conversion_write(scratch, _item1638);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("conversions", hash);
        next.add_hashed("conversions", hash, _nj1640);
        _nj1640 += 1;
        if (at >= 0) {
            _hits1639.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_Conversion_write(out, _item1638);
        }
    }
    base.missed("conversions", "conversions", _hits1639.count);
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1648 = 0;
    var _news1649 = Map<String, Array<String>>();
    for (var (_key1645, _) in value.overload_sets) {
        var _kscratch1646 = base.scratch();
        _kscratch1646.text(_key1645);
        var _vscratch1647 = base.scratch();
        _vscratch1647.unsigned(value.overload_sets[_key1645].count);
        for (var _item1650 in value.overload_sets[_key1645]) {
            _vscratch1647.text(_item1650);
        }
        var _had = base.entry("overload_sets", _kscratch1646, _vscratch1647);
        if (_had >= 0) {
            _kept1648 += 1;
        }
        if (_had != 1) {
            _news1649[_key1645] = value.overload_sets[_key1645];
        }
    }
    if (_kept1648 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1652 = Array<(u8[], u8[], String)>();
        for (var (_key1651, _) in _news1649) {
            var _scratch1653 = out.scratch();
            _scratch1653.text(_key1651);
            var _vscratch1655 = out.scratch();
            _vscratch1655.unsigned(_news1649[_key1651].count);
            for (var _item1656 in _news1649[_key1651]) {
                _vscratch1655.text(_item1656);
            }
            _keys1652.append((_scratch1653.finish(), _vscratch1655.finish(), _key1651));
        }
        _keys1652.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1652.count);
        for (var (_bytes1654, _, _key1651) in _keys1652) {
            out.text(_key1651);
            out.unsigned(_news1649[_key1651].count);
            for (var _item1657 in _news1649[_key1651]) {
                out.text(_item1657);
            }
        }
    } else {
        out.unsigned(0);
        var _keys1659 = Array<(u8[], u8[], String)>();
        for (var (_key1658, _) in value.overload_sets) {
            var _scratch1660 = out.scratch();
            _scratch1660.text(_key1658);
            var _vscratch1662 = out.scratch();
            _vscratch1662.unsigned(value.overload_sets[_key1658].count);
            for (var _item1663 in value.overload_sets[_key1658]) {
                _vscratch1662.text(_item1663);
            }
            _keys1659.append((_scratch1660.finish(), _vscratch1662.finish(), _key1658));
        }
        _keys1659.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1659.count);
        for (var (_bytes1661, _, _key1658) in _keys1659) {
            out.text(_key1658);
            out.unsigned(value.overload_sets[_key1658].count);
            for (var _item1664 in value.overload_sets[_key1658]) {
                out.text(_item1664);
            }
        }
        base.count("overload_sets whole", 0);
    }
    for (var (_key1645, _) in value.overload_sets) {
        var _kscratch1646 = next.scratch();
        _kscratch1646.text(_key1645);
        var _vscratch1647 = next.scratch();
        _vscratch1647.unsigned(value.overload_sets[_key1645].count);
        for (var _item1678 in value.overload_sets[_key1645]) {
            _vscratch1647.text(_item1678);
        }
        next.keep_entry("overload_sets", _kscratch1646, _vscratch1647);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1682 = 0;
    var _news1683 = Map<String, Array<Array<String>>>();
    for (var (_key1679, _) in value.overload_unions) {
        var _kscratch1680 = base.scratch();
        _kscratch1680.text(_key1679);
        var _vscratch1681 = base.scratch();
        _vscratch1681.unsigned(value.overload_unions[_key1679].count);
        for (var _item1684 in value.overload_unions[_key1679]) {
            _vscratch1681.unsigned(_item1684.count);
            for (var _item1685 in _item1684) {
                _vscratch1681.text(_item1685);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1680, _vscratch1681);
        if (_had >= 0) {
            _kept1682 += 1;
        }
        if (_had != 1) {
            _news1683[_key1679] = value.overload_unions[_key1679];
        }
    }
    if (_kept1682 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1687 = Array<(u8[], u8[], String)>();
        for (var (_key1686, _) in _news1683) {
            var _scratch1688 = out.scratch();
            _scratch1688.text(_key1686);
            var _vscratch1690 = out.scratch();
            _vscratch1690.unsigned(_news1683[_key1686].count);
            for (var _item1691 in _news1683[_key1686]) {
                _vscratch1690.unsigned(_item1691.count);
                for (var _item1692 in _item1691) {
                    _vscratch1690.text(_item1692);
                }
            }
            _keys1687.append((_scratch1688.finish(), _vscratch1690.finish(), _key1686));
        }
        _keys1687.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1687.count);
        for (var (_bytes1689, _, _key1686) in _keys1687) {
            out.text(_key1686);
            out.unsigned(_news1683[_key1686].count);
            for (var _item1693 in _news1683[_key1686]) {
                out.unsigned(_item1693.count);
                for (var _item1694 in _item1693) {
                    out.text(_item1694);
                }
            }
        }
    } else {
        out.unsigned(0);
        var _keys1696 = Array<(u8[], u8[], String)>();
        for (var (_key1695, _) in value.overload_unions) {
            var _scratch1697 = out.scratch();
            _scratch1697.text(_key1695);
            var _vscratch1699 = out.scratch();
            _vscratch1699.unsigned(value.overload_unions[_key1695].count);
            for (var _item1700 in value.overload_unions[_key1695]) {
                _vscratch1699.unsigned(_item1700.count);
                for (var _item1701 in _item1700) {
                    _vscratch1699.text(_item1701);
                }
            }
            _keys1696.append((_scratch1697.finish(), _vscratch1699.finish(), _key1695));
        }
        _keys1696.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1696.count);
        for (var (_bytes1698, _, _key1695) in _keys1696) {
            out.text(_key1695);
            out.unsigned(value.overload_unions[_key1695].count);
            for (var _item1702 in value.overload_unions[_key1695]) {
                out.unsigned(_item1702.count);
                for (var _item1703 in _item1702) {
                    out.text(_item1703);
                }
            }
        }
        base.count("overload_unions whole", 0);
    }
    for (var (_key1679, _) in value.overload_unions) {
        var _kscratch1680 = next.scratch();
        _kscratch1680.text(_key1679);
        var _vscratch1681 = next.scratch();
        _vscratch1681.unsigned(value.overload_unions[_key1679].count);
        for (var _item1721 in value.overload_unions[_key1679]) {
            _vscratch1681.unsigned(_item1721.count);
            for (var _item1722 in _item1721) {
                _vscratch1681.text(_item1722);
            }
        }
        next.keep_entry("overload_unions", _kscratch1680, _vscratch1681);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1726 = 0;
    var _news1727 = Map<String, Map<String, Array<String>>>();
    for (var (_key1723, _) in value.method_overload_sets) {
        var _kscratch1724 = base.scratch();
        _kscratch1724.text(_key1723);
        var _vscratch1725 = base.scratch();
        var _keys1729 = Array<(u8[], u8[], String)>();
        for (var (_key1728, _) in value.method_overload_sets[_key1723]) {
            var _scratch1730 = _vscratch1725.scratch();
            _scratch1730.text(_key1728);
            var _vscratch1732 = _vscratch1725.scratch();
            _vscratch1732.unsigned(value.method_overload_sets[_key1723][_key1728].count);
            for (var _item1733 in value.method_overload_sets[_key1723][_key1728]) {
                _vscratch1732.text(_item1733);
            }
            _keys1729.append((_scratch1730.finish(), _vscratch1732.finish(), _key1728));
        }
        _keys1729.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1725.unsigned(_keys1729.count);
        for (var (_bytes1731, _, _key1728) in _keys1729) {
            _vscratch1725.text(_key1728);
            _vscratch1725.unsigned(value.method_overload_sets[_key1723][_key1728].count);
            for (var _item1734 in value.method_overload_sets[_key1723][_key1728]) {
                _vscratch1725.text(_item1734);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1724, _vscratch1725);
        if (_had >= 0) {
            _kept1726 += 1;
        }
        if (_had != 1) {
            _news1727[_key1723] = value.method_overload_sets[_key1723];
        }
    }
    if (_kept1726 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1736 = Array<(u8[], u8[], String)>();
        for (var (_key1735, _) in _news1727) {
            var _scratch1737 = out.scratch();
            _scratch1737.text(_key1735);
            var _vscratch1739 = out.scratch();
            var _keys1741 = Array<(u8[], u8[], String)>();
            for (var (_key1740, _) in _news1727[_key1735]) {
                var _scratch1742 = _vscratch1739.scratch();
                _scratch1742.text(_key1740);
                var _vscratch1744 = _vscratch1739.scratch();
                _vscratch1744.unsigned(_news1727[_key1735][_key1740].count);
                for (var _item1745 in _news1727[_key1735][_key1740]) {
                    _vscratch1744.text(_item1745);
                }
                _keys1741.append((_scratch1742.finish(), _vscratch1744.finish(), _key1740));
            }
            _keys1741.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1739.unsigned(_keys1741.count);
            for (var (_bytes1743, _, _key1740) in _keys1741) {
                _vscratch1739.text(_key1740);
                _vscratch1739.unsigned(_news1727[_key1735][_key1740].count);
                for (var _item1746 in _news1727[_key1735][_key1740]) {
                    _vscratch1739.text(_item1746);
                }
            }
            _keys1736.append((_scratch1737.finish(), _vscratch1739.finish(), _key1735));
        }
        _keys1736.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1736.count);
        for (var (_bytes1738, _, _key1735) in _keys1736) {
            out.text(_key1735);
            var _keys1748 = Array<(u8[], u8[], String)>();
            for (var (_key1747, _) in _news1727[_key1735]) {
                var _scratch1749 = out.scratch();
                _scratch1749.text(_key1747);
                var _vscratch1751 = out.scratch();
                _vscratch1751.unsigned(_news1727[_key1735][_key1747].count);
                for (var _item1752 in _news1727[_key1735][_key1747]) {
                    _vscratch1751.text(_item1752);
                }
                _keys1748.append((_scratch1749.finish(), _vscratch1751.finish(), _key1747));
            }
            _keys1748.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1748.count);
            for (var (_bytes1750, _, _key1747) in _keys1748) {
                out.text(_key1747);
                out.unsigned(_news1727[_key1735][_key1747].count);
                for (var _item1753 in _news1727[_key1735][_key1747]) {
                    out.text(_item1753);
                }
            }
        }
    } else {
        out.unsigned(0);
        var _keys1755 = Array<(u8[], u8[], String)>();
        for (var (_key1754, _) in value.method_overload_sets) {
            var _scratch1756 = out.scratch();
            _scratch1756.text(_key1754);
            var _vscratch1758 = out.scratch();
            var _keys1760 = Array<(u8[], u8[], String)>();
            for (var (_key1759, _) in value.method_overload_sets[_key1754]) {
                var _scratch1761 = _vscratch1758.scratch();
                _scratch1761.text(_key1759);
                var _vscratch1763 = _vscratch1758.scratch();
                _vscratch1763.unsigned(value.method_overload_sets[_key1754][_key1759].count);
                for (var _item1764 in value.method_overload_sets[_key1754][_key1759]) {
                    _vscratch1763.text(_item1764);
                }
                _keys1760.append((_scratch1761.finish(), _vscratch1763.finish(), _key1759));
            }
            _keys1760.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1758.unsigned(_keys1760.count);
            for (var (_bytes1762, _, _key1759) in _keys1760) {
                _vscratch1758.text(_key1759);
                _vscratch1758.unsigned(value.method_overload_sets[_key1754][_key1759].count);
                for (var _item1765 in value.method_overload_sets[_key1754][_key1759]) {
                    _vscratch1758.text(_item1765);
                }
            }
            _keys1755.append((_scratch1756.finish(), _vscratch1758.finish(), _key1754));
        }
        _keys1755.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1755.count);
        for (var (_bytes1757, _, _key1754) in _keys1755) {
            out.text(_key1754);
            var _keys1767 = Array<(u8[], u8[], String)>();
            for (var (_key1766, _) in value.method_overload_sets[_key1754]) {
                var _scratch1768 = out.scratch();
                _scratch1768.text(_key1766);
                var _vscratch1770 = out.scratch();
                _vscratch1770.unsigned(value.method_overload_sets[_key1754][_key1766].count);
                for (var _item1771 in value.method_overload_sets[_key1754][_key1766]) {
                    _vscratch1770.text(_item1771);
                }
                _keys1767.append((_scratch1768.finish(), _vscratch1770.finish(), _key1766));
            }
            _keys1767.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1767.count);
            for (var (_bytes1769, _, _key1766) in _keys1767) {
                out.text(_key1766);
                out.unsigned(value.method_overload_sets[_key1754][_key1766].count);
                for (var _item1772 in value.method_overload_sets[_key1754][_key1766]) {
                    out.text(_item1772);
                }
            }
        }
        base.count("method_overload_sets whole", 0);
    }
    for (var (_key1723, _) in value.method_overload_sets) {
        var _kscratch1724 = next.scratch();
        _kscratch1724.text(_key1723);
        var _vscratch1725 = next.scratch();
        var _keys1793 = Array<(u8[], u8[], String)>();
        for (var (_key1792, _) in value.method_overload_sets[_key1723]) {
            var _scratch1794 = _vscratch1725.scratch();
            _scratch1794.text(_key1792);
            var _vscratch1796 = _vscratch1725.scratch();
            _vscratch1796.unsigned(value.method_overload_sets[_key1723][_key1792].count);
            for (var _item1797 in value.method_overload_sets[_key1723][_key1792]) {
                _vscratch1796.text(_item1797);
            }
            _keys1793.append((_scratch1794.finish(), _vscratch1796.finish(), _key1792));
        }
        _keys1793.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1725.unsigned(_keys1793.count);
        for (var (_bytes1795, _, _key1792) in _keys1793) {
            _vscratch1725.text(_key1792);
            _vscratch1725.unsigned(value.method_overload_sets[_key1723][_key1792].count);
            for (var _item1798 in value.method_overload_sets[_key1723][_key1792]) {
                _vscratch1725.text(_item1798);
            }
        }
        next.keep_entry("method_overload_sets", _kscratch1724, _vscratch1725);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1803 = 0;
    var _news1804 = HashSet<Loc>();
    for (var _key1800 in value.private_functions) {
        var _kscratch1801 = base.scratch();
        _kscratch1801.loc(_key1800);
        var _vscratch1802 = base.scratch();
        var _had = base.entry("private_functions", _kscratch1801, _vscratch1802);
        if (_had >= 0) {
            _kept1803 += 1;
        }
        if (_had != 1) {
            _news1804.insert(_key1800);
        }
    }
    if (_kept1803 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys1806 = Array<(u8[], u8[], Loc)>();
        for (var _key1805 in _news1804) {
            var _scratch1807 = out.scratch();
            _scratch1807.loc(_key1805);
            var _vscratch1809 = out.scratch();
            _keys1806.append((_scratch1807.finish(), _vscratch1809.finish(), _key1805));
        }
        _keys1806.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1806.count);
        for (var (_bytes1808, _, _key1805) in _keys1806) {
            out.loc(_key1805);
        }
    } else {
        out.unsigned(0);
        var _keys1811 = Array<(u8[], u8[], Loc)>();
        for (var _key1810 in value.private_functions) {
            var _scratch1812 = out.scratch();
            _scratch1812.loc(_key1810);
            var _vscratch1814 = out.scratch();
            _keys1811.append((_scratch1812.finish(), _vscratch1814.finish(), _key1810));
        }
        _keys1811.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1811.count);
        for (var (_bytes1813, _, _key1810) in _keys1811) {
            out.loc(_key1810);
        }
        base.count("private_functions whole", 0);
    }
    for (var _key1800 in value.private_functions) {
        var _kscratch1801 = next.scratch();
        _kscratch1801.loc(_key1800);
        var _vscratch1802 = next.scratch();
        next.keep_entry("private_functions", _kscratch1801, _vscratch1802);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1825 = 0;
    var _news1826 = HashSet<Loc>();
    for (var _key1822 in value.file_private_functions) {
        var _kscratch1823 = base.scratch();
        _kscratch1823.loc(_key1822);
        var _vscratch1824 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch1823, _vscratch1824);
        if (_had >= 0) {
            _kept1825 += 1;
        }
        if (_had != 1) {
            _news1826.insert(_key1822);
        }
    }
    if (_kept1825 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys1828 = Array<(u8[], u8[], Loc)>();
        for (var _key1827 in _news1826) {
            var _scratch1829 = out.scratch();
            _scratch1829.loc(_key1827);
            var _vscratch1831 = out.scratch();
            _keys1828.append((_scratch1829.finish(), _vscratch1831.finish(), _key1827));
        }
        _keys1828.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1828.count);
        for (var (_bytes1830, _, _key1827) in _keys1828) {
            out.loc(_key1827);
        }
    } else {
        out.unsigned(0);
        var _keys1833 = Array<(u8[], u8[], Loc)>();
        for (var _key1832 in value.file_private_functions) {
            var _scratch1834 = out.scratch();
            _scratch1834.loc(_key1832);
            var _vscratch1836 = out.scratch();
            _keys1833.append((_scratch1834.finish(), _vscratch1836.finish(), _key1832));
        }
        _keys1833.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1833.count);
        for (var (_bytes1835, _, _key1832) in _keys1833) {
            out.loc(_key1832);
        }
        base.count("file_private_functions whole", 0);
    }
    for (var _key1822 in value.file_private_functions) {
        var _kscratch1823 = next.scratch();
        _kscratch1823.loc(_key1822);
        var _vscratch1824 = next.scratch();
        next.keep_entry("file_private_functions", _kscratch1823, _vscratch1824);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n1846 = base.size("call_targets");
    var _scratch1845 = base.scratch();
    if (value.call_targets.count >= _n1846) {
        for (var _i1847 in 0.._n1846) {
            var (_t1848, _t1849) = value.call_targets[_i1847];
            _scratch1845.loc(_t1848);
            _scratch1845.text(_t1849);
        }
    }
    if (value.call_targets.count >= _n1846 and base.same_list("call_targets", _scratch1845)) {
        out.unsigned(1);
        out.unsigned(_n1846);
        out.unsigned(value.call_targets.count - _n1846);
        for (var _i1847 in _n1846..value.call_targets.count) {
            var (_t1850, _t1851) = value.call_targets[_i1847];
            out.loc(_t1850);
            out.text(_t1851);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item1852 in value.call_targets) {
            var (_t1853, _t1854) = _item1852;
            out.loc(_t1853);
            out.text(_t1854);
        }
        base.count("call_targets whole", 0);
    }
    var _xscratch1865 = next.scratch();
    for (var _xitem1866 in value.call_targets) {
        var (_t1867, _t1868) = _xitem1866;
        _xscratch1865.loc(_t1867);
        _xscratch1865.text(_t1868);
    }
    next.keep_list("call_targets", value.call_targets.count, _xscratch1865);
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1871 = 0;
    var _news1872 = Array<(Loc, String)>();
    for (var _item1869 in value.argument_names) {
        var _escratch1870 = base.scratch();
        var (_t1873, _t1874) = _item1869;
        _escratch1870.loc(_t1873);
        _escratch1870.text(_t1874);
        if (base.entry("argument_names", _escratch1870, base.scratch()) >= 0) {
            _kept1871 += 1;
        } else {
            _news1872.append(_item1869);
        }
    }
    if (_kept1871 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news1872.count);
        for (var _item1875 in _news1872) {
            var (_t1876, _t1877) = _item1875;
            out.loc(_t1876);
            out.text(_t1877);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item1878 in value.argument_names) {
            var (_t1879, _t1880) = _item1878;
            out.loc(_t1879);
            out.text(_t1880);
        }
        base.count("argument_names whole", 0);
    }
    for (var _item1869 in value.argument_names) {
        var _escratch1870 = next.scratch();
        var (_t1891, _t1892) = _item1869;
        _escratch1870.loc(_t1891);
        _escratch1870.text(_t1892);
        next.keep_entry("argument_names", _escratch1870, next.scratch());
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n1895 = base.size("namespaces");
    var _scratch1894 = base.scratch();
    if (value.namespaces.count >= _n1895) {
        for (var _i1896 in 0.._n1895) {
            _scratch1894.text(value.namespaces[_i1896]);
        }
    }
    if (value.namespaces.count >= _n1895 and base.same_list("namespaces", _scratch1894)) {
        out.unsigned(1);
        out.unsigned(_n1895);
        out.unsigned(value.namespaces.count - _n1895);
        for (var _i1896 in _n1895..value.namespaces.count) {
            out.text(value.namespaces[_i1896]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item1897 in value.namespaces) {
            out.text(_item1897);
        }
        base.count("namespaces whole", 0);
    }
    var _xscratch1904 = next.scratch();
    for (var _xitem1905 in value.namespaces) {
        _xscratch1904.text(_xitem1905);
    }
    next.keep_list("namespaces", value.namespaces.count, _xscratch1904);
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n1908 = base.size("cached_files");
    var _scratch1907 = base.scratch();
    if (value.cached_files.count >= _n1908) {
        for (var _i1909 in 0.._n1908) {
            _scratch1907.flag(value.cached_files[_i1909]);
        }
    }
    if (value.cached_files.count >= _n1908 and base.same_list("cached_files", _scratch1907)) {
        out.unsigned(1);
        out.unsigned(_n1908);
        out.unsigned(value.cached_files.count - _n1908);
        for (var _i1909 in _n1908..value.cached_files.count) {
            out.flag(value.cached_files[_i1909]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item1910 in value.cached_files) {
            out.flag(_item1910);
        }
        base.count("cached_files whole", 0);
    }
    var _xscratch1917 = next.scratch();
    for (var _xitem1918 in value.cached_files) {
        _xscratch1917.flag(_xitem1918);
    }
    next.keep_list("cached_files", value.cached_files.count, _xscratch1917);
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1922 = 0;
    var _news1923 = HashMap<Loc, String>();
    for (var (_key1919, _) in value.recorded_summaries) {
        var _kscratch1920 = base.scratch();
        _kscratch1920.loc(_key1919);
        var _vscratch1921 = base.scratch();
        _vscratch1921.text(value.recorded_summaries[_key1919]);
        var _had = base.entry("recorded_summaries", _kscratch1920, _vscratch1921);
        if (_had >= 0) {
            _kept1922 += 1;
        }
        if (_had != 1) {
            _news1923[_key1919] = value.recorded_summaries[_key1919];
        }
    }
    if (_kept1922 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys1925 = Array<(u8[], u8[], Loc)>();
        for (var (_key1924, _) in _news1923) {
            var _scratch1926 = out.scratch();
            _scratch1926.loc(_key1924);
            var _vscratch1928 = out.scratch();
            _vscratch1928.text(_news1923[_key1924]);
            _keys1925.append((_scratch1926.finish(), _vscratch1928.finish(), _key1924));
        }
        _keys1925.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1925.count);
        for (var (_bytes1927, _, _key1924) in _keys1925) {
            out.loc(_key1924);
            out.text(_news1923[_key1924]);
        }
    } else {
        out.unsigned(0);
        var _keys1930 = Array<(u8[], u8[], Loc)>();
        for (var (_key1929, _) in value.recorded_summaries) {
            var _scratch1931 = out.scratch();
            _scratch1931.loc(_key1929);
            var _vscratch1933 = out.scratch();
            _vscratch1933.text(value.recorded_summaries[_key1929]);
            _keys1930.append((_scratch1931.finish(), _vscratch1933.finish(), _key1929));
        }
        _keys1930.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1930.count);
        for (var (_bytes1932, _, _key1929) in _keys1930) {
            out.loc(_key1929);
            out.text(value.recorded_summaries[_key1929]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1946 = 0;
    var _news1947 = HashSet<Loc>();
    for (var _key1943 in value.stripped) {
        var _kscratch1944 = base.scratch();
        _kscratch1944.loc(_key1943);
        var _vscratch1945 = base.scratch();
        var _had = base.entry("stripped", _kscratch1944, _vscratch1945);
        if (_had >= 0) {
            _kept1946 += 1;
        }
        if (_had != 1) {
            _news1947.insert(_key1943);
        }
    }
    if (_kept1946 == base.size("stripped")) {
        out.unsigned(1);
        var _keys1949 = Array<(u8[], u8[], Loc)>();
        for (var _key1948 in _news1947) {
            var _scratch1950 = out.scratch();
            _scratch1950.loc(_key1948);
            var _vscratch1952 = out.scratch();
            _keys1949.append((_scratch1950.finish(), _vscratch1952.finish(), _key1948));
        }
        _keys1949.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1949.count);
        for (var (_bytes1951, _, _key1948) in _keys1949) {
            out.loc(_key1948);
        }
    } else {
        out.unsigned(0);
        var _keys1954 = Array<(u8[], u8[], Loc)>();
        for (var _key1953 in value.stripped) {
            var _scratch1955 = out.scratch();
            _scratch1955.loc(_key1953);
            var _vscratch1957 = out.scratch();
            _keys1954.append((_scratch1955.finish(), _vscratch1957.finish(), _key1953));
        }
        _keys1954.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1954.count);
        for (var (_bytes1956, _, _key1953) in _keys1954) {
            out.loc(_key1953);
        }
        base.count("stripped whole", 0);
    }
    for (var _key1943 in value.stripped) {
        var _kscratch1944 = next.scratch();
        _kscratch1944.loc(_key1943);
        var _vscratch1945 = next.scratch();
        next.keep_entry("stripped", _kscratch1944, _vscratch1945);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _struct_hits1966 = HashSet<long>();
    ulong _nj1967 = 0;
    out.unsigned(value.templates.structs.count);
    for (var _item1965 in value.templates.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1965);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("t", hash);
        var named = base.named("t", _item1965.name);
        next.add_hashed("t", hash, _nj1967);
        next.name("t", _item1965.name, _nj1967);
        _patch_t_index(_item1965, next, _nj1967);
        _nj1967 += 1;
        ulong _before = out.values.count;
        if (at >= 0) {
            _struct_hits1966.insert(at);
        } else if (named >= 0) {
            _struct_hits1966.insert(named);
        }
        if (at >= 0) {
            out.unsigned((at as ulong) * 2 + 1);
        } else if (named >= 0) {
            out.unsigned(2);
            out.unsigned(named as ulong);
            _patch_t_write(out, _item1965, base, named as ulong);
            base.count("t patched", out.values.count - _before);
        } else {
            out.unsigned(0);
            _m_StructDef_write(out, _item1965);
            base.count("t new", out.values.count - _before);
        }
    }
    base.missed("t", "t", _struct_hits1966.count);
    var _hits1973 = HashSet<long>();
    ulong _nj1974 = 0;
    out.unsigned(value.templates.functions.count);
    for (var _item1972 in value.templates.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1972);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("tf", hash);
        next.add_hashed("tf", hash, _nj1974);
        _nj1974 += 1;
        if (at >= 0) {
            _hits1973.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item1972);
        }
    }
    base.missed("tf", "tf", _hits1973.count);
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    next.keep_checked(value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1984 = 0;
    var _news1985 = HashMap<String, SpecRequest>();
    for (var (_key1981, _) in value.spec_requests) {
        var _kscratch1982 = base.scratch();
        _kscratch1982.text(_key1981);
        var _vscratch1983 = base.scratch();
        _m_SpecRequest_write(_vscratch1983, value.spec_requests[_key1981]);
        var _had = base.entry("spec_requests", _kscratch1982, _vscratch1983);
        if (_had >= 0) {
            _kept1984 += 1;
        }
        if (_had != 1) {
            _news1985[_key1981] = value.spec_requests[_key1981];
        }
    }
    if (_kept1984 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys1987 = Array<(u8[], u8[], String)>();
        for (var (_key1986, _) in _news1985) {
            var _scratch1988 = out.scratch();
            _scratch1988.text(_key1986);
            var _vscratch1990 = out.scratch();
            _m_SpecRequest_write(_vscratch1990, _news1985[_key1986]);
            _keys1987.append((_scratch1988.finish(), _vscratch1990.finish(), _key1986));
        }
        _keys1987.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1987.count);
        for (var (_bytes1989, _, _key1986) in _keys1987) {
            out.text(_key1986);
            _m_SpecRequest_write(out, _news1985[_key1986]);
        }
    } else {
        out.unsigned(0);
        var _keys1992 = Array<(u8[], u8[], String)>();
        for (var (_key1991, _) in value.spec_requests) {
            var _scratch1993 = out.scratch();
            _scratch1993.text(_key1991);
            var _vscratch1995 = out.scratch();
            _m_SpecRequest_write(_vscratch1995, value.spec_requests[_key1991]);
            _keys1992.append((_scratch1993.finish(), _vscratch1995.finish(), _key1991));
        }
        _keys1992.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1992.count);
        for (var (_bytes1994, _, _key1991) in _keys1992) {
            out.text(_key1991);
            _m_SpecRequest_write(out, value.spec_requests[_key1991]);
        }
        base.count("spec_requests whole", 0);
    }
    for (var (_key1981, _) in value.spec_requests) {
        var _kscratch1982 = next.scratch();
        _kscratch1982.text(_key1981);
        var _vscratch1983 = next.scratch();
        _m_SpecRequest_write(_vscratch1983, value.spec_requests[_key1981]);
        next.keep_entry("spec_requests", _kscratch1982, _vscratch1983);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2008 = base.size("summaries_to_record");
    var _scratch2007 = base.scratch();
    if (value.summaries_to_record.count >= _n2008) {
        for (var _i2009 in 0.._n2008) {
            var (_t2010, _t2011) = value.summaries_to_record[_i2009];
            _scratch2007.loc(_t2010);
            _scratch2007.text(_t2011);
        }
    }
    if (value.summaries_to_record.count >= _n2008 and base.same_list("summaries_to_record", _scratch2007)) {
        out.unsigned(1);
        out.unsigned(_n2008);
        out.unsigned(value.summaries_to_record.count - _n2008);
        for (var _i2009 in _n2008..value.summaries_to_record.count) {
            var (_t2012, _t2013) = value.summaries_to_record[_i2009];
            out.loc(_t2012);
            out.text(_t2013);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2014 in value.summaries_to_record) {
            var (_t2015, _t2016) = _item2014;
            out.loc(_t2015);
            out.text(_t2016);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2034 = 0;
    var _news2035 = HashMap<String, Array<bool>>();
    for (var (_key2031, _) in value.caller_copies) {
        var _kscratch2032 = base.scratch();
        _kscratch2032.text(_key2031);
        var _vscratch2033 = base.scratch();
        _vscratch2033.unsigned(value.caller_copies[_key2031].count);
        for (var _item2036 in value.caller_copies[_key2031]) {
            _vscratch2033.flag(_item2036);
        }
        var _had = base.entry("caller_copies", _kscratch2032, _vscratch2033);
        if (_had >= 0) {
            _kept2034 += 1;
        }
        if (_had != 1) {
            _news2035[_key2031] = value.caller_copies[_key2031];
        }
    }
    if (_kept2034 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2038 = Array<(u8[], u8[], String)>();
        for (var (_key2037, _) in _news2035) {
            var _scratch2039 = out.scratch();
            _scratch2039.text(_key2037);
            var _vscratch2041 = out.scratch();
            _vscratch2041.unsigned(_news2035[_key2037].count);
            for (var _item2042 in _news2035[_key2037]) {
                _vscratch2041.flag(_item2042);
            }
            _keys2038.append((_scratch2039.finish(), _vscratch2041.finish(), _key2037));
        }
        _keys2038.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2038.count);
        for (var (_bytes2040, _, _key2037) in _keys2038) {
            out.text(_key2037);
            out.unsigned(_news2035[_key2037].count);
            for (var _item2043 in _news2035[_key2037]) {
                out.flag(_item2043);
            }
        }
    } else {
        out.unsigned(0);
        var _keys2045 = Array<(u8[], u8[], String)>();
        for (var (_key2044, _) in value.caller_copies) {
            var _scratch2046 = out.scratch();
            _scratch2046.text(_key2044);
            var _vscratch2048 = out.scratch();
            _vscratch2048.unsigned(value.caller_copies[_key2044].count);
            for (var _item2049 in value.caller_copies[_key2044]) {
                _vscratch2048.flag(_item2049);
            }
            _keys2045.append((_scratch2046.finish(), _vscratch2048.finish(), _key2044));
        }
        _keys2045.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2045.count);
        for (var (_bytes2047, _, _key2044) in _keys2045) {
            out.text(_key2044);
            out.unsigned(value.caller_copies[_key2044].count);
            for (var _item2050 in value.caller_copies[_key2044]) {
                out.flag(_item2050);
            }
        }
        base.count("caller_copies whole", 0);
    }
    for (var (_key2031, _) in value.caller_copies) {
        var _kscratch2032 = next.scratch();
        _kscratch2032.text(_key2031);
        var _vscratch2033 = next.scratch();
        _vscratch2033.unsigned(value.caller_copies[_key2031].count);
        for (var _item2064 in value.caller_copies[_key2031]) {
            _vscratch2033.flag(_item2064);
        }
        next.keep_entry("caller_copies", _kscratch2032, _vscratch2033);
    }
    base.stat("caller_copies", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.linked);
    base.stat("linked", out.values.count - _mark);
    _mark = out.values.count;
}

_m_Module_read_delta(input: RecordIn, base: Module): Module {
    var _f1484 = Array<ast.Import>();
    var _n1485 = input.count();
    for (var _ in 0.._n1485) {
        var _tag1486 = input.unsigned();
        if (_tag1486 & 1 == 1) {
            _f1484.append(base.imports[_tag1486 >> 1]);
        } else {
            _f1484.append(_a_Import_read(input));
        }
    }
    var _f1491 = Array<StructDef>();
    var _n1492 = input.count();
    for (var _ in 0.._n1492) {
        var _tag1493 = input.unsigned();
        if (_tag1493 & 1 == 1) {
            _f1491.append(base.structs[_tag1493 >> 1]);
        } else if (_tag1493 == 2) {
            var _was = base.structs[input.unsigned()];
            _f1491.append(_patch_s_read(input, _was));
        } else {
            _f1491.append(_m_StructDef_read(input));
        }
    }
    var _f1498 = Array<TraitDef>();
    var _n1499 = input.count();
    for (var _ in 0.._n1499) {
        var _tag1500 = input.unsigned();
        if (_tag1500 & 1 == 1) {
            _f1498.append(base.traits[_tag1500 >> 1]);
        } else {
            _f1498.append(_m_TraitDef_read(input));
        }
    }
    var _f1505 = Array<ExtensionDef>();
    var _n1506 = input.count();
    for (var _ in 0.._n1506) {
        var _tag1507 = input.unsigned();
        if (_tag1507 & 1 == 1) {
            _f1505.append(base.extensions[_tag1507 >> 1]);
        } else {
            _f1505.append(_m_ExtensionDef_read(input));
        }
    }
    var _f1512 = Array<FunctionDef>();
    var _n1513 = input.count();
    for (var _ in 0.._n1513) {
        var _tag1514 = input.unsigned();
        if (_tag1514 & 1 == 1) {
            _f1512.append(base.functions[_tag1514 >> 1]);
        } else {
            _f1512.append(_m_FunctionDef_read(input));
        }
    }
    var _f1519 = Array<ExternDef>();
    var _n1520 = input.count();
    for (var _ in 0.._n1520) {
        var _tag1521 = input.unsigned();
        if (_tag1521 & 1 == 1) {
            _f1519.append(base.externs[_tag1521 >> 1]);
        } else {
            _f1519.append(_m_ExternDef_read(input));
        }
    }
    var _f1526 = Array<VariableDef>();
    var _n1527 = input.count();
    for (var _ in 0.._n1527) {
        var _tag1528 = input.unsigned();
        if (_tag1528 & 1 == 1) {
            _f1526.append(base.globals[_tag1528 >> 1]);
        } else {
            _f1526.append(_m_VariableDef_read(input));
        }
    }
    var _f1533 = Array<ModuleStaticBlock>();
    var _n1534 = input.count();
    for (var _ in 0.._n1534) {
        var _tag1535 = input.unsigned();
        if (_tag1535 & 1 == 1) {
            _f1533.append(base.static_blocks[_tag1535 >> 1]);
        } else {
            _f1533.append(_m_ModuleStaticBlock_read(input));
        }
    }
    var _f1540 = Array<EnumDef>();
    var _n1541 = input.count();
    for (var _ in 0.._n1541) {
        var _tag1542 = input.unsigned();
        if (_tag1542 & 1 == 1) {
            _f1540.append(base.enums[_tag1542 >> 1]);
        } else {
            _f1540.append(_m_EnumDef_read(input));
        }
    }
    var _f1547 = Array<TypeName>();
    var _n1548 = input.count();
    for (var _ in 0.._n1548) {
        var _tag1549 = input.unsigned();
        if (_tag1549 & 1 == 1) {
            _f1547.append(base.struct_specs[_tag1549 >> 1]);
        } else {
            _f1547.append(_m_TypeName_read(input));
        }
    }
    var _f1554 = Array<TypeName>();
    var _n1555 = input.count();
    for (var _ in 0.._n1555) {
        var _tag1556 = input.unsigned();
        if (_tag1556 & 1 == 1) {
            _f1554.append(base.func_specs[_tag1556 >> 1]);
        } else {
            _f1554.append(_m_TypeName_read(input));
        }
    }
    var _f1561 = Array<TypeAliasDef>();
    var _n1562 = input.count();
    for (var _ in 0.._n1562) {
        var _tag1563 = input.unsigned();
        if (_tag1563 & 1 == 1) {
            _f1561.append(base.type_aliases[_tag1563 >> 1]);
        } else {
            _f1561.append(_m_TypeAliasDef_read(input));
        }
    }
    var _f1568 = Array<Withheld>();
    var _n1569 = input.count();
    for (var _ in 0.._n1569) {
        var _tag1570 = input.unsigned();
        if (_tag1570 & 1 == 1) {
            _f1568.append(base.withheld[_tag1570 >> 1]);
        } else {
            _f1568.append(_m_Withheld_read(input));
        }
    }
    var _f1575 = Array<PropertyDef>();
    var _n1576 = input.count();
    for (var _ in 0.._n1576) {
        var _tag1577 = input.unsigned();
        if (_tag1577 & 1 == 1) {
            _f1575.append(base.properties[_tag1577 >> 1]);
        } else {
            _f1575.append(_m_PropertyDef_read(input));
        }
    }
    var _f1582 = Array<TypeUse>();
    var _n1583 = input.count();
    for (var _ in 0.._n1583) {
        var _tag1584 = input.unsigned();
        if (_tag1584 & 1 == 1) {
            _f1582.append(base.type_uses[_tag1584 >> 1]);
        } else {
            _f1582.append(_m_TypeUse_read(input));
        }
    }
    var _f1589 = Array<UseContext>();
    var _n1590 = input.count();
    for (var _ in 0.._n1590) {
        var _tag1591 = input.unsigned();
        if (_tag1591 & 1 == 1) {
            _f1589.append(base.use_contexts[_tag1591 >> 1]);
        } else {
            _f1589.append(_m_UseContext_read(input));
        }
    }
    var _f1607 = Array<(Loc, ulong, Loc)>();
    var _tag1608 = input.unsigned();
    if (_tag1608 == 1) {
        input.unsigned();
        for (var _i1596 in 0..base.literal_args.count) {
            _f1607.append(base.literal_args[_i1596]);
        }
        var _more1610 = input.count();
        for (var _ in 0.._more1610) {
            var _t1611 = input.loc();
            var _t1612 = input.unsigned();
            var _t1613 = input.loc();
            _f1607.append((_t1611, _t1612, _t1613));
        }
    } else {
        var _v1614 = Array<(Loc, ulong, Loc)>();
        var _n1615 = input.count();
        for (var _ in 0.._n1615) {
            var _t1616 = input.loc();
            var _t1617 = input.unsigned();
            var _t1618 = input.loc();
            _v1614.append((_t1616, _t1617, _t1618));
        }
        _f1607 = _v1614;
    }
    var _f1627 = Array<TypeAliasDef>();
    var _n1628 = input.count();
    for (var _ in 0.._n1628) {
        var _tag1629 = input.unsigned();
        if (_tag1629 & 1 == 1) {
            _f1627.append(base.constrained_aliases[_tag1629 >> 1]);
        } else {
            _f1627.append(_m_TypeAliasDef_read(input));
        }
    }
    var _f1634 = Array<TraitType>();
    var _n1635 = input.count();
    for (var _ in 0.._n1635) {
        var _tag1636 = input.unsigned();
        if (_tag1636 & 1 == 1) {
            _f1634.append(base.trait_types[_tag1636 >> 1]);
        } else {
            _f1634.append(_m_TraitType_read(input));
        }
    }
    var _f1641 = Array<Conversion>();
    var _n1642 = input.count();
    for (var _ in 0.._n1642) {
        var _tag1643 = input.unsigned();
        if (_tag1643 & 1 == 1) {
            _f1641.append(base.conversions[_tag1643 >> 1]);
        } else {
            _f1641.append(_m_Conversion_read(input));
        }
    }
    var _f1665 = Map<String, Array<String>>();
    var _tag1666 = input.unsigned();
    if (_tag1666 == 1) {
        for (var (_bk1667, _bv) in base.overload_sets) {
            _f1665[_bk1667] = _bv;
        }
        var _v1668 = Map<String, Array<String>>();
        var _n1669 = input.count();
        for (var _ in 0.._n1669) {
            var _k1670 = input.text();
            var _v1671 = Array<String>();
            var _n1672 = input.count();
            for (var _ in 0.._n1672) {
                _v1671.append(input.text());
            }
            _v1668[_k1670] = _v1671;
        }
        for (var (_bk1667, _av) in _v1668) {
            _f1665[_bk1667] = _av;
        }
    } else {
        var _v1673 = Map<String, Array<String>>();
        var _n1674 = input.count();
        for (var _ in 0.._n1674) {
            var _k1675 = input.text();
            var _v1676 = Array<String>();
            var _n1677 = input.count();
            for (var _ in 0.._n1677) {
                _v1676.append(input.text());
            }
            _v1673[_k1675] = _v1676;
        }
        _f1665 = _v1673;
    }
    var _f1704 = Map<String, Array<Array<String>>>();
    var _tag1705 = input.unsigned();
    if (_tag1705 == 1) {
        for (var (_bk1706, _bv) in base.overload_unions) {
            _f1704[_bk1706] = _bv;
        }
        var _v1707 = Map<String, Array<Array<String>>>();
        var _n1708 = input.count();
        for (var _ in 0.._n1708) {
            var _k1709 = input.text();
            var _v1710 = Array<Array<String>>();
            var _n1711 = input.count();
            for (var _ in 0.._n1711) {
                var _v1712 = Array<String>();
                var _n1713 = input.count();
                for (var _ in 0.._n1713) {
                    _v1712.append(input.text());
                }
                _v1710.append(_v1712);
            }
            _v1707[_k1709] = _v1710;
        }
        for (var (_bk1706, _av) in _v1707) {
            _f1704[_bk1706] = _av;
        }
    } else {
        var _v1714 = Map<String, Array<Array<String>>>();
        var _n1715 = input.count();
        for (var _ in 0.._n1715) {
            var _k1716 = input.text();
            var _v1717 = Array<Array<String>>();
            var _n1718 = input.count();
            for (var _ in 0.._n1718) {
                var _v1719 = Array<String>();
                var _n1720 = input.count();
                for (var _ in 0.._n1720) {
                    _v1719.append(input.text());
                }
                _v1717.append(_v1719);
            }
            _v1714[_k1716] = _v1717;
        }
        _f1704 = _v1714;
    }
    var _f1773 = Map<String, Map<String, Array<String>>>();
    var _tag1774 = input.unsigned();
    if (_tag1774 == 1) {
        for (var (_bk1775, _bv) in base.method_overload_sets) {
            _f1773[_bk1775] = _bv;
        }
        var _v1776 = Map<String, Map<String, Array<String>>>();
        var _n1777 = input.count();
        for (var _ in 0.._n1777) {
            var _k1778 = input.text();
            var _v1779 = Map<String, Array<String>>();
            var _n1780 = input.count();
            for (var _ in 0.._n1780) {
                var _k1781 = input.text();
                var _v1782 = Array<String>();
                var _n1783 = input.count();
                for (var _ in 0.._n1783) {
                    _v1782.append(input.text());
                }
                _v1779[_k1781] = _v1782;
            }
            _v1776[_k1778] = _v1779;
        }
        for (var (_bk1775, _av) in _v1776) {
            _f1773[_bk1775] = _av;
        }
    } else {
        var _v1784 = Map<String, Map<String, Array<String>>>();
        var _n1785 = input.count();
        for (var _ in 0.._n1785) {
            var _k1786 = input.text();
            var _v1787 = Map<String, Array<String>>();
            var _n1788 = input.count();
            for (var _ in 0.._n1788) {
                var _k1789 = input.text();
                var _v1790 = Array<String>();
                var _n1791 = input.count();
                for (var _ in 0.._n1791) {
                    _v1790.append(input.text());
                }
                _v1787[_k1789] = _v1790;
            }
            _v1784[_k1786] = _v1787;
        }
        _f1773 = _v1784;
    }
    var _f1799 = _m_ExtensionScopes_read(input);
    var _f1815 = HashSet<Loc>();
    var _tag1816 = input.unsigned();
    if (_tag1816 == 1) {
        for (var _bk1817 in base.private_functions) {
            _f1815.insert(_bk1817);
        }
        var _v1818 = HashSet<Loc>();
        var _n1819 = input.count();
        for (var _ in 0.._n1819) {
            _v1818.insert(input.loc());
        }
        for (var _bk1817 in _v1818) {
            _f1815.insert(_bk1817);
        }
    } else {
        var _v1820 = HashSet<Loc>();
        var _n1821 = input.count();
        for (var _ in 0.._n1821) {
            _v1820.insert(input.loc());
        }
        _f1815 = _v1820;
    }
    var _f1837 = HashSet<Loc>();
    var _tag1838 = input.unsigned();
    if (_tag1838 == 1) {
        for (var _bk1839 in base.file_private_functions) {
            _f1837.insert(_bk1839);
        }
        var _v1840 = HashSet<Loc>();
        var _n1841 = input.count();
        for (var _ in 0.._n1841) {
            _v1840.insert(input.loc());
        }
        for (var _bk1839 in _v1840) {
            _f1837.insert(_bk1839);
        }
    } else {
        var _v1842 = HashSet<Loc>();
        var _n1843 = input.count();
        for (var _ in 0.._n1843) {
            _v1842.insert(input.loc());
        }
        _f1837 = _v1842;
    }
    var _f1855 = Array<(Loc, String)>();
    var _tag1856 = input.unsigned();
    if (_tag1856 == 1) {
        input.unsigned();
        for (var _i1847 in 0..base.call_targets.count) {
            _f1855.append(base.call_targets[_i1847]);
        }
        var _more1858 = input.count();
        for (var _ in 0.._more1858) {
            var _t1859 = input.loc();
            var _t1860 = input.text();
            _f1855.append((_t1859, _t1860));
        }
    } else {
        var _v1861 = Array<(Loc, String)>();
        var _n1862 = input.count();
        for (var _ in 0.._n1862) {
            var _t1863 = input.loc();
            var _t1864 = input.text();
            _v1861.append((_t1863, _t1864));
        }
        _f1855 = _v1861;
    }
    var _f1881 = Array<(Loc, String)>();
    var _tag1882 = input.unsigned();
    if (_tag1882 == 1) {
        var _v1883 = Array<(Loc, String)>();
        var _n1884 = input.count();
        for (var _ in 0.._n1884) {
            var _t1885 = input.loc();
            var _t1886 = input.text();
            _v1883.append((_t1885, _t1886));
        }
        _f1881 = merge_by_place(base.argument_names, _v1883);
    } else {
        var _v1887 = Array<(Loc, String)>();
        var _n1888 = input.count();
        for (var _ in 0.._n1888) {
            var _t1889 = input.loc();
            var _t1890 = input.text();
            _v1887.append((_t1889, _t1890));
        }
        _f1881 = _v1887;
    }
    var _f1898 = Array<String>();
    var _tag1899 = input.unsigned();
    if (_tag1899 == 1) {
        input.unsigned();
        for (var _i1896 in 0..base.namespaces.count) {
            _f1898.append(base.namespaces[_i1896]);
        }
        var _more1901 = input.count();
        for (var _ in 0.._more1901) {
            _f1898.append(input.text());
        }
    } else {
        var _v1902 = Array<String>();
        var _n1903 = input.count();
        for (var _ in 0.._n1903) {
            _v1902.append(input.text());
        }
        _f1898 = _v1902;
    }
    var _f1911 = Array<bool>();
    var _tag1912 = input.unsigned();
    if (_tag1912 == 1) {
        input.unsigned();
        for (var _i1909 in 0..base.cached_files.count) {
            _f1911.append(base.cached_files[_i1909]);
        }
        var _more1914 = input.count();
        for (var _ in 0.._more1914) {
            _f1911.append(input.flag());
        }
    } else {
        var _v1915 = Array<bool>();
        var _n1916 = input.count();
        for (var _ in 0.._n1916) {
            _v1915.append(input.flag());
        }
        _f1911 = _v1915;
    }
    var _f1934 = HashMap<Loc, String>();
    var _tag1935 = input.unsigned();
    if (_tag1935 == 1) {
        for (var (_bk1936, _bv) in base.recorded_summaries) {
            _f1934[_bk1936] = _bv;
        }
        var _v1937 = HashMap<Loc, String>();
        var _n1938 = input.count();
        for (var _ in 0.._n1938) {
            var _k1939 = input.loc();
            _v1937[_k1939] = input.text();
        }
        for (var (_bk1936, _av) in _v1937) {
            _f1934[_bk1936] = _av;
        }
    } else {
        var _v1940 = HashMap<Loc, String>();
        var _n1941 = input.count();
        for (var _ in 0.._n1941) {
            var _k1942 = input.loc();
            _v1940[_k1942] = input.text();
        }
        _f1934 = _v1940;
    }
    var _f1958 = HashSet<Loc>();
    var _tag1959 = input.unsigned();
    if (_tag1959 == 1) {
        for (var _bk1960 in base.stripped) {
            _f1958.insert(_bk1960);
        }
        var _v1961 = HashSet<Loc>();
        var _n1962 = input.count();
        for (var _ in 0.._n1962) {
            _v1961.insert(input.loc());
        }
        for (var _bk1960 in _v1961) {
            _f1958.insert(_bk1960);
        }
    } else {
        var _v1963 = HashSet<Loc>();
        var _n1964 = input.count();
        for (var _ in 0.._n1964) {
            _v1963.insert(input.loc());
        }
        _f1958 = _v1963;
    }
    var _frozen = input.flag();
    var _f1968 = Array<StructDef>();
    var _n1969 = input.count();
    for (var _ in 0.._n1969) {
        var _tag1970 = input.unsigned();
        if (_tag1970 & 1 == 1) {
            _f1968.append(base.templates.structs[_tag1970 >> 1]);
        } else if (_tag1970 == 2) {
            var _was = base.templates.structs[input.unsigned()];
            _f1968.append(_patch_t_read(input, _was));
        } else {
            _f1968.append(_m_StructDef_read(input));
        }
    }
    var _f1975 = Array<FunctionDef>();
    var _n1976 = input.count();
    for (var _ in 0.._n1976) {
        var _tag1977 = input.unsigned();
        if (_tag1977 & 1 == 1) {
            _f1975.append(base.templates.functions[_tag1977 >> 1]);
        } else {
            _f1975.append(_m_FunctionDef_read(input));
        }
    }
    var _f1979 = Templates(_frozen, _f1968, _f1975);
    var _f1980 = DeltaBase.read_checked(input, base.checked);
    var _f1996 = HashMap<String, SpecRequest>();
    var _tag1997 = input.unsigned();
    if (_tag1997 == 1) {
        for (var (_bk1998, _bv) in base.spec_requests) {
            _f1996[_bk1998] = _bv;
        }
        var _v1999 = HashMap<String, SpecRequest>();
        var _n2000 = input.count();
        for (var _ in 0.._n2000) {
            var _k2001 = input.text();
            _v1999[_k2001] = _m_SpecRequest_read(input);
        }
        for (var (_bk1998, _av) in _v1999) {
            _f1996[_bk1998] = _av;
        }
    } else {
        var _v2002 = HashMap<String, SpecRequest>();
        var _n2003 = input.count();
        for (var _ in 0.._n2003) {
            var _k2004 = input.text();
            _v2002[_k2004] = _m_SpecRequest_read(input);
        }
        _f1996 = _v2002;
    }
    var _f2005 = input.flag();
    var _f2017 = Array<(Loc, String)>();
    var _tag2018 = input.unsigned();
    if (_tag2018 == 1) {
        input.unsigned();
        for (var _i2009 in 0..base.summaries_to_record.count) {
            _f2017.append(base.summaries_to_record[_i2009]);
        }
        var _more2020 = input.count();
        for (var _ in 0.._more2020) {
            var _t2021 = input.loc();
            var _t2022 = input.text();
            _f2017.append((_t2021, _t2022));
        }
    } else {
        var _v2023 = Array<(Loc, String)>();
        var _n2024 = input.count();
        for (var _ in 0.._n2024) {
            var _t2025 = input.loc();
            var _t2026 = input.text();
            _v2023.append((_t2025, _t2026));
        }
        _f2017 = _v2023;
    }
    var _f2051 = HashMap<String, Array<bool>>();
    var _tag2052 = input.unsigned();
    if (_tag2052 == 1) {
        for (var (_bk2053, _bv) in base.caller_copies) {
            _f2051[_bk2053] = _bv;
        }
        var _v2054 = HashMap<String, Array<bool>>();
        var _n2055 = input.count();
        for (var _ in 0.._n2055) {
            var _k2056 = input.text();
            var _v2057 = Array<bool>();
            var _n2058 = input.count();
            for (var _ in 0.._n2058) {
                _v2057.append(input.flag());
            }
            _v2054[_k2056] = _v2057;
        }
        for (var (_bk2053, _av) in _v2054) {
            _f2051[_bk2053] = _av;
        }
    } else {
        var _v2059 = HashMap<String, Array<bool>>();
        var _n2060 = input.count();
        for (var _ in 0.._n2060) {
            var _k2061 = input.text();
            var _v2062 = Array<bool>();
            var _n2063 = input.count();
            for (var _ in 0.._n2063) {
                _v2062.append(input.flag());
            }
            _v2059[_k2061] = _v2062;
        }
        _f2051 = _v2059;
    }
    var _f2065 = input.flag();
    return Module(
        _f1484,
        _f1491,
        _f1498,
        _f1505,
        _f1512,
        _f1519,
        _f1526,
        _f1533,
        _f1540,
        _f1547,
        _f1554,
        _f1561,
        _f1568,
        _f1575,
        _f1582,
        _f1589,
        _f1607,
        _f1627,
        _f1634,
        _f1641,
        _f1665,
        _f1704,
        _f1773,
        _f1799,
        _f1815,
        _f1837,
        _f1855,
        _f1881,
        _f1898,
        _f1911,
        _f1934,
        _f1958,
        _f1979,
        _f1980,
        _f1996,
        _f2005,
        _f2017,
        _f2051,
        _f2065
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1487 = 0;
    for (var _item1481 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1481);
        base.add("imports", scratch, _j1487);
        _j1487 += 1;
    }
    ulong _j1494 = 0;
    for (var _item1488 in value.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1488);
        base.add("s", scratch, _j1494);
        base.name("s", _item1488.name, _j1494);
        _patch_s_index(_item1488, base, _j1494);
        _j1494 += 1;
    }
    ulong _j1501 = 0;
    for (var _item1495 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1495);
        base.add("traits", scratch, _j1501);
        _j1501 += 1;
    }
    ulong _j1508 = 0;
    for (var _item1502 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1502);
        base.add("extensions", scratch, _j1508);
        _j1508 += 1;
    }
    ulong _j1515 = 0;
    for (var _item1509 in value.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1509);
        base.add("functions", scratch, _j1515);
        _j1515 += 1;
    }
    ulong _j1522 = 0;
    for (var _item1516 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1516);
        base.add("externs", scratch, _j1522);
        _j1522 += 1;
    }
    ulong _j1529 = 0;
    for (var _item1523 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1523);
        base.add("globals", scratch, _j1529);
        _j1529 += 1;
    }
    ulong _j1536 = 0;
    for (var _item1530 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1530);
        base.add("static_blocks", scratch, _j1536);
        _j1536 += 1;
    }
    ulong _j1543 = 0;
    for (var _item1537 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1537);
        base.add("enums", scratch, _j1543);
        _j1543 += 1;
    }
    ulong _j1550 = 0;
    for (var _item1544 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1544);
        base.add("struct_specs", scratch, _j1550);
        _j1550 += 1;
    }
    ulong _j1557 = 0;
    for (var _item1551 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1551);
        base.add("func_specs", scratch, _j1557);
        _j1557 += 1;
    }
    ulong _j1564 = 0;
    for (var _item1558 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1558);
        base.add("type_aliases", scratch, _j1564);
        _j1564 += 1;
    }
    ulong _j1571 = 0;
    for (var _item1565 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1565);
        base.add("withheld", scratch, _j1571);
        _j1571 += 1;
    }
    ulong _j1578 = 0;
    for (var _item1572 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1572);
        base.add("properties", scratch, _j1578);
        _j1578 += 1;
    }
    ulong _j1585 = 0;
    for (var _item1579 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1579);
        base.add("type_uses", scratch, _j1585);
        _j1585 += 1;
    }
    ulong _j1592 = 0;
    for (var _item1586 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1586);
        base.add("use_contexts", scratch, _j1592);
        _j1592 += 1;
    }
    var _xscratch1619 = base.scratch();
    for (var _xitem1620 in value.literal_args) {
        var (_t1621, _t1622, _t1623) = _xitem1620;
        _xscratch1619.loc(_t1621);
        _xscratch1619.unsigned(_t1622);
        _xscratch1619.loc(_t1623);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1619);
    ulong _j1630 = 0;
    for (var _item1624 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1624);
        base.add("constrained_aliases", scratch, _j1630);
        _j1630 += 1;
    }
    ulong _j1637 = 0;
    for (var _item1631 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1631);
        base.add("trait_types", scratch, _j1637);
        _j1637 += 1;
    }
    ulong _j1644 = 0;
    for (var _item1638 in value.conversions) {
        var scratch = base.scratch();
        _m_Conversion_write(scratch, _item1638);
        base.add("conversions", scratch, _j1644);
        _j1644 += 1;
    }
    for (var (_key1645, _) in value.overload_sets) {
        var _kscratch1646 = base.scratch();
        _kscratch1646.text(_key1645);
        var _vscratch1647 = base.scratch();
        _vscratch1647.unsigned(value.overload_sets[_key1645].count);
        for (var _item1678 in value.overload_sets[_key1645]) {
            _vscratch1647.text(_item1678);
        }
        base.keep_entry("overload_sets", _kscratch1646, _vscratch1647);
    }
    for (var (_key1679, _) in value.overload_unions) {
        var _kscratch1680 = base.scratch();
        _kscratch1680.text(_key1679);
        var _vscratch1681 = base.scratch();
        _vscratch1681.unsigned(value.overload_unions[_key1679].count);
        for (var _item1721 in value.overload_unions[_key1679]) {
            _vscratch1681.unsigned(_item1721.count);
            for (var _item1722 in _item1721) {
                _vscratch1681.text(_item1722);
            }
        }
        base.keep_entry("overload_unions", _kscratch1680, _vscratch1681);
    }
    for (var (_key1723, _) in value.method_overload_sets) {
        var _kscratch1724 = base.scratch();
        _kscratch1724.text(_key1723);
        var _vscratch1725 = base.scratch();
        var _keys1793 = Array<(u8[], u8[], String)>();
        for (var (_key1792, _) in value.method_overload_sets[_key1723]) {
            var _scratch1794 = _vscratch1725.scratch();
            _scratch1794.text(_key1792);
            var _vscratch1796 = _vscratch1725.scratch();
            _vscratch1796.unsigned(value.method_overload_sets[_key1723][_key1792].count);
            for (var _item1797 in value.method_overload_sets[_key1723][_key1792]) {
                _vscratch1796.text(_item1797);
            }
            _keys1793.append((_scratch1794.finish(), _vscratch1796.finish(), _key1792));
        }
        _keys1793.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1725.unsigned(_keys1793.count);
        for (var (_bytes1795, _, _key1792) in _keys1793) {
            _vscratch1725.text(_key1792);
            _vscratch1725.unsigned(value.method_overload_sets[_key1723][_key1792].count);
            for (var _item1798 in value.method_overload_sets[_key1723][_key1792]) {
                _vscratch1725.text(_item1798);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1724, _vscratch1725);
    }
    for (var _key1800 in value.private_functions) {
        var _kscratch1801 = base.scratch();
        _kscratch1801.loc(_key1800);
        var _vscratch1802 = base.scratch();
        base.keep_entry("private_functions", _kscratch1801, _vscratch1802);
    }
    for (var _key1822 in value.file_private_functions) {
        var _kscratch1823 = base.scratch();
        _kscratch1823.loc(_key1822);
        var _vscratch1824 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch1823, _vscratch1824);
    }
    var _xscratch1865 = base.scratch();
    for (var _xitem1866 in value.call_targets) {
        var (_t1867, _t1868) = _xitem1866;
        _xscratch1865.loc(_t1867);
        _xscratch1865.text(_t1868);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch1865);
    for (var _item1869 in value.argument_names) {
        var _escratch1870 = base.scratch();
        var (_t1891, _t1892) = _item1869;
        _escratch1870.loc(_t1891);
        _escratch1870.text(_t1892);
        base.keep_entry("argument_names", _escratch1870, base.scratch());
    }
    var _xscratch1904 = base.scratch();
    for (var _xitem1905 in value.namespaces) {
        _xscratch1904.text(_xitem1905);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch1904);
    var _xscratch1917 = base.scratch();
    for (var _xitem1918 in value.cached_files) {
        _xscratch1917.flag(_xitem1918);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch1917);
    for (var (_key1919, _) in value.recorded_summaries) {
        var _kscratch1920 = base.scratch();
        _kscratch1920.loc(_key1919);
        var _vscratch1921 = base.scratch();
        _vscratch1921.text(value.recorded_summaries[_key1919]);
        base.keep_entry("recorded_summaries", _kscratch1920, _vscratch1921);
    }
    for (var _key1943 in value.stripped) {
        var _kscratch1944 = base.scratch();
        _kscratch1944.loc(_key1943);
        var _vscratch1945 = base.scratch();
        base.keep_entry("stripped", _kscratch1944, _vscratch1945);
    }
    ulong _j1971 = 0;
    for (var _item1965 in value.templates.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1965);
        base.add("t", scratch, _j1971);
        base.name("t", _item1965.name, _j1971);
        _patch_t_index(_item1965, base, _j1971);
        _j1971 += 1;
    }
    ulong _j1978 = 0;
    for (var _item1972 in value.templates.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1972);
        base.add("tf", scratch, _j1978);
        _j1978 += 1;
    }
    base.keep_checked(value.checked);
    for (var (_key1981, _) in value.spec_requests) {
        var _kscratch1982 = base.scratch();
        _kscratch1982.text(_key1981);
        var _vscratch1983 = base.scratch();
        _m_SpecRequest_write(_vscratch1983, value.spec_requests[_key1981]);
        base.keep_entry("spec_requests", _kscratch1982, _vscratch1983);
    }
    var _xscratch2027 = base.scratch();
    for (var _xitem2028 in value.summaries_to_record) {
        var (_t2029, _t2030) = _xitem2028;
        _xscratch2027.loc(_t2029);
        _xscratch2027.text(_t2030);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2027);
    for (var (_key2031, _) in value.caller_copies) {
        var _kscratch2032 = base.scratch();
        _kscratch2032.text(_key2031);
        var _vscratch2033 = base.scratch();
        _vscratch2033.unsigned(value.caller_copies[_key2031].count);
        for (var _item2064 in value.caller_copies[_key2031]) {
            _vscratch2033.flag(_item2064);
        }
        base.keep_entry("caller_copies", _kscratch2032, _vscratch2033);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1564 = 0;
    for (var _item1558 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1558);
        base.add("type_aliases", scratch, _j1564);
        _j1564 += 1;
    }
    for (var (_key1919, _) in value.recorded_summaries) {
        var _kscratch1920 = base.scratch();
        _kscratch1920.loc(_key1919);
        var _vscratch1921 = base.scratch();
        _vscratch1921.text(value.recorded_summaries[_key1919]);
        base.keep_entry("recorded_summaries", _kscratch1920, _vscratch1921);
    }
    var _xscratch2027 = base.scratch();
    for (var _xitem2028 in value.summaries_to_record) {
        var (_t2029, _t2030) = _xitem2028;
        _xscratch2027.loc(_t2029);
        _xscratch2027.text(_t2030);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2027);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _hits2069 = HashSet<long>();
    ulong _nj2070 = 0;
    out.unsigned(value.generic_params.count);
    for (var _item2068 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2068);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.generic_params", hash);
        if (at >= 0) {
            _hits2069.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_GenericParam_write(out, _item2068);
        }
    }
    base.missed("s.*.generic_params", $"s.{slot}.generic_params", _hits2069.count);
    var _hits2076 = HashSet<long>();
    ulong _nj2077 = 0;
    out.unsigned(value.field_members.count);
    for (var _item2075 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2075);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.field_members", hash);
        if (at >= 0) {
            _hits2076.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_VariableDef_write(out, _item2075);
        }
    }
    base.missed("s.*.field_members", $"s.{slot}.field_members", _hits2076.count);
    var _hits2083 = HashSet<long>();
    ulong _nj2084 = 0;
    out.unsigned(value.method_members.count);
    for (var _item2082 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2082);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.method_members", hash);
        if (at >= 0) {
            _hits2083.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2082);
        }
    }
    base.missed("s.*.method_members", $"s.{slot}.method_members", _hits2083.count);
    var _hits2090 = HashSet<long>();
    ulong _nj2091 = 0;
    out.unsigned(value.generic_methods.count);
    for (var _item2089 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2089);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.generic_methods", hash);
        if (at >= 0) {
            _hits2090.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2089);
        }
    }
    base.missed("s.*.generic_methods", $"s.{slot}.generic_methods", _hits2090.count);
    var _hits2097 = HashSet<long>();
    ulong _nj2098 = 0;
    out.unsigned(value.constructors.count);
    for (var _item2096 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2096);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.constructors", hash);
        if (at >= 0) {
            _hits2097.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2096);
        }
    }
    base.missed("s.*.constructors", $"s.{slot}.constructors", _hits2097.count);
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _hits2107 = HashSet<long>();
    ulong _nj2108 = 0;
    out.unsigned(value.traits.count);
    for (var _item2106 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2106);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.traits", hash);
        if (at >= 0) {
            _hits2107.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeName_write(out, _item2106);
        }
    }
    base.missed("s.*.traits", $"s.{slot}.traits", _hits2107.count);
    var _hits2114 = HashSet<long>();
    ulong _nj2115 = 0;
    out.unsigned(value.attributes.count);
    for (var _item2113 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2113);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.attributes", hash);
        if (at >= 0) {
            _hits2114.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _a_Attribute_write(out, _item2113);
        }
    }
    base.missed("s.*.attributes", $"s.{slot}.attributes", _hits2114.count);
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2121 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2121);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2066 = input.text();
    var _f2067 = _m_TypeName_read(input);
    var _f2071 = Array<GenericParam>();
    var _n2072 = input.count();
    for (var _ in 0.._n2072) {
        var _tag2073 = input.unsigned();
        if (_tag2073 & 1 == 1) {
            _f2071.append(was.generic_params[_tag2073 >> 1]);
        } else {
            _f2071.append(_m_GenericParam_read(input));
        }
    }
    var _f2078 = Array<VariableDef>();
    var _n2079 = input.count();
    for (var _ in 0.._n2079) {
        var _tag2080 = input.unsigned();
        if (_tag2080 & 1 == 1) {
            _f2078.append(was.field_members[_tag2080 >> 1]);
        } else {
            _f2078.append(_m_VariableDef_read(input));
        }
    }
    var _f2085 = Array<FunctionDef>();
    var _n2086 = input.count();
    for (var _ in 0.._n2086) {
        var _tag2087 = input.unsigned();
        if (_tag2087 & 1 == 1) {
            _f2085.append(was.method_members[_tag2087 >> 1]);
        } else {
            _f2085.append(_m_FunctionDef_read(input));
        }
    }
    var _f2092 = Array<FunctionDef>();
    var _n2093 = input.count();
    for (var _ in 0.._n2093) {
        var _tag2094 = input.unsigned();
        if (_tag2094 & 1 == 1) {
            _f2092.append(was.generic_methods[_tag2094 >> 1]);
        } else {
            _f2092.append(_m_FunctionDef_read(input));
        }
    }
    var _f2099 = Array<FunctionDef>();
    var _n2100 = input.count();
    for (var _ in 0.._n2100) {
        var _tag2101 = input.unsigned();
        if (_tag2101 & 1 == 1) {
            _f2099.append(was.constructors[_tag2101 >> 1]);
        } else {
            _f2099.append(_m_FunctionDef_read(input));
        }
    }
    var _f2103 = _m_FunctionDef_read(input);
    var _f2104 = _m_FunctionDef_read(input);
    var _f2105 = _m_FunctionDef_read(input);
    var _f2109 = Array<TypeName>();
    var _n2110 = input.count();
    for (var _ in 0.._n2110) {
        var _tag2111 = input.unsigned();
        if (_tag2111 & 1 == 1) {
            _f2109.append(was.traits[_tag2111 >> 1]);
        } else {
            _f2109.append(_m_TypeName_read(input));
        }
    }
    var _f2116 = Array<ast.Attribute>();
    var _n2117 = input.count();
    for (var _ in 0.._n2117) {
        var _tag2118 = input.unsigned();
        if (_tag2118 & 1 == 1) {
            _f2116.append(was.attributes[_tag2118 >> 1]);
        } else {
            _f2116.append(_a_Attribute_read(input));
        }
    }
    var _f2120 = input.loc();
    var _o2122 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2123 = Array<EnumCaseDef>();
        var _n2124 = input.count();
        for (var _ in 0.._n2124) {
            _v2123.append(_m_EnumCaseDef_read(input));
        }
        _o2122 = Optional<Array<EnumCaseDef>>.Value(_v2123);
    }
    var _f2125 = _o2122;
    return StructDef(
        _f2066, _f2067, _f2071, _f2078, _f2085, _f2092, _f2099, _f2103, _f2104, _f2105, _f2109, _f2116, _f2120, _f2125
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    ulong _j2074 = 0;
    for (var _item2068 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2068);
        base.add($"s.{slot}.generic_params", scratch, _j2074);
        _j2074 += 1;
    }
    ulong _j2081 = 0;
    for (var _item2075 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2075);
        base.add($"s.{slot}.field_members", scratch, _j2081);
        _j2081 += 1;
    }
    ulong _j2088 = 0;
    for (var _item2082 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2082);
        base.add($"s.{slot}.method_members", scratch, _j2088);
        _j2088 += 1;
    }
    ulong _j2095 = 0;
    for (var _item2089 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2089);
        base.add($"s.{slot}.generic_methods", scratch, _j2095);
        _j2095 += 1;
    }
    ulong _j2102 = 0;
    for (var _item2096 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2096);
        base.add($"s.{slot}.constructors", scratch, _j2102);
        _j2102 += 1;
    }
    ulong _j2112 = 0;
    for (var _item2106 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2106);
        base.add($"s.{slot}.traits", scratch, _j2112);
        _j2112 += 1;
    }
    ulong _j2119 = 0;
    for (var _item2113 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2113);
        base.add($"s.{slot}.attributes", scratch, _j2119);
        _j2119 += 1;
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _hits2129 = HashSet<long>();
    ulong _nj2130 = 0;
    out.unsigned(value.generic_params.count);
    for (var _item2128 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2128);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.generic_params", hash);
        if (at >= 0) {
            _hits2129.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_GenericParam_write(out, _item2128);
        }
    }
    base.missed("t.*.generic_params", $"t.{slot}.generic_params", _hits2129.count);
    var _hits2136 = HashSet<long>();
    ulong _nj2137 = 0;
    out.unsigned(value.field_members.count);
    for (var _item2135 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2135);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.field_members", hash);
        if (at >= 0) {
            _hits2136.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_VariableDef_write(out, _item2135);
        }
    }
    base.missed("t.*.field_members", $"t.{slot}.field_members", _hits2136.count);
    var _hits2143 = HashSet<long>();
    ulong _nj2144 = 0;
    out.unsigned(value.method_members.count);
    for (var _item2142 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2142);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.method_members", hash);
        if (at >= 0) {
            _hits2143.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2142);
        }
    }
    base.missed("t.*.method_members", $"t.{slot}.method_members", _hits2143.count);
    var _hits2150 = HashSet<long>();
    ulong _nj2151 = 0;
    out.unsigned(value.generic_methods.count);
    for (var _item2149 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2149);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.generic_methods", hash);
        if (at >= 0) {
            _hits2150.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2149);
        }
    }
    base.missed("t.*.generic_methods", $"t.{slot}.generic_methods", _hits2150.count);
    var _hits2157 = HashSet<long>();
    ulong _nj2158 = 0;
    out.unsigned(value.constructors.count);
    for (var _item2156 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2156);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.constructors", hash);
        if (at >= 0) {
            _hits2157.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2156);
        }
    }
    base.missed("t.*.constructors", $"t.{slot}.constructors", _hits2157.count);
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _hits2167 = HashSet<long>();
    ulong _nj2168 = 0;
    out.unsigned(value.traits.count);
    for (var _item2166 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2166);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.traits", hash);
        if (at >= 0) {
            _hits2167.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeName_write(out, _item2166);
        }
    }
    base.missed("t.*.traits", $"t.{slot}.traits", _hits2167.count);
    var _hits2174 = HashSet<long>();
    ulong _nj2175 = 0;
    out.unsigned(value.attributes.count);
    for (var _item2173 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2173);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.attributes", hash);
        if (at >= 0) {
            _hits2174.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _a_Attribute_write(out, _item2173);
        }
    }
    base.missed("t.*.attributes", $"t.{slot}.attributes", _hits2174.count);
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2181 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2181);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2126 = input.text();
    var _f2127 = _m_TypeName_read(input);
    var _f2131 = Array<GenericParam>();
    var _n2132 = input.count();
    for (var _ in 0.._n2132) {
        var _tag2133 = input.unsigned();
        if (_tag2133 & 1 == 1) {
            _f2131.append(was.generic_params[_tag2133 >> 1]);
        } else {
            _f2131.append(_m_GenericParam_read(input));
        }
    }
    var _f2138 = Array<VariableDef>();
    var _n2139 = input.count();
    for (var _ in 0.._n2139) {
        var _tag2140 = input.unsigned();
        if (_tag2140 & 1 == 1) {
            _f2138.append(was.field_members[_tag2140 >> 1]);
        } else {
            _f2138.append(_m_VariableDef_read(input));
        }
    }
    var _f2145 = Array<FunctionDef>();
    var _n2146 = input.count();
    for (var _ in 0.._n2146) {
        var _tag2147 = input.unsigned();
        if (_tag2147 & 1 == 1) {
            _f2145.append(was.method_members[_tag2147 >> 1]);
        } else {
            _f2145.append(_m_FunctionDef_read(input));
        }
    }
    var _f2152 = Array<FunctionDef>();
    var _n2153 = input.count();
    for (var _ in 0.._n2153) {
        var _tag2154 = input.unsigned();
        if (_tag2154 & 1 == 1) {
            _f2152.append(was.generic_methods[_tag2154 >> 1]);
        } else {
            _f2152.append(_m_FunctionDef_read(input));
        }
    }
    var _f2159 = Array<FunctionDef>();
    var _n2160 = input.count();
    for (var _ in 0.._n2160) {
        var _tag2161 = input.unsigned();
        if (_tag2161 & 1 == 1) {
            _f2159.append(was.constructors[_tag2161 >> 1]);
        } else {
            _f2159.append(_m_FunctionDef_read(input));
        }
    }
    var _f2163 = _m_FunctionDef_read(input);
    var _f2164 = _m_FunctionDef_read(input);
    var _f2165 = _m_FunctionDef_read(input);
    var _f2169 = Array<TypeName>();
    var _n2170 = input.count();
    for (var _ in 0.._n2170) {
        var _tag2171 = input.unsigned();
        if (_tag2171 & 1 == 1) {
            _f2169.append(was.traits[_tag2171 >> 1]);
        } else {
            _f2169.append(_m_TypeName_read(input));
        }
    }
    var _f2176 = Array<ast.Attribute>();
    var _n2177 = input.count();
    for (var _ in 0.._n2177) {
        var _tag2178 = input.unsigned();
        if (_tag2178 & 1 == 1) {
            _f2176.append(was.attributes[_tag2178 >> 1]);
        } else {
            _f2176.append(_a_Attribute_read(input));
        }
    }
    var _f2180 = input.loc();
    var _o2182 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2183 = Array<EnumCaseDef>();
        var _n2184 = input.count();
        for (var _ in 0.._n2184) {
            _v2183.append(_m_EnumCaseDef_read(input));
        }
        _o2182 = Optional<Array<EnumCaseDef>>.Value(_v2183);
    }
    var _f2185 = _o2182;
    return StructDef(
        _f2126, _f2127, _f2131, _f2138, _f2145, _f2152, _f2159, _f2163, _f2164, _f2165, _f2169, _f2176, _f2180, _f2185
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    ulong _j2134 = 0;
    for (var _item2128 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2128);
        base.add($"t.{slot}.generic_params", scratch, _j2134);
        _j2134 += 1;
    }
    ulong _j2141 = 0;
    for (var _item2135 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2135);
        base.add($"t.{slot}.field_members", scratch, _j2141);
        _j2141 += 1;
    }
    ulong _j2148 = 0;
    for (var _item2142 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2142);
        base.add($"t.{slot}.method_members", scratch, _j2148);
        _j2148 += 1;
    }
    ulong _j2155 = 0;
    for (var _item2149 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2149);
        base.add($"t.{slot}.generic_methods", scratch, _j2155);
        _j2155 += 1;
    }
    ulong _j2162 = 0;
    for (var _item2156 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2156);
        base.add($"t.{slot}.constructors", scratch, _j2162);
        _j2162 += 1;
    }
    ulong _j2172 = 0;
    for (var _item2166 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2166);
        base.add($"t.{slot}.traits", scratch, _j2172);
        _j2172 += 1;
    }
    ulong _j2179 = 0;
    for (var _item2173 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2173);
        base.add($"t.{slot}.attributes", scratch, _j2179);
        _j2179 += 1;
    }
}

_m_Module_interface_fields(value: Module, interface: bool): Array<(String, String)> {
    var found = Array<(String, String)>();
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.imports.count);
        for (var _item2186 in value.imports) {
            _a_Import_write(out, _item2186);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2187 in value.structs) {
            _m_StructDef_write(out, _item2187);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.traits.count);
        for (var _item2188 in value.traits) {
            _m_TraitDef_write(out, _item2188);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2189 in value.extensions) {
            _m_ExtensionDef_write(out, _item2189);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2190 in value.functions) {
            _m_FunctionDef_write(out, _item2190);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2191 in value.externs) {
            _m_ExternDef_write(out, _item2191);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2192 in value.globals) {
            _m_VariableDef_write(out, _item2192);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2193 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2193);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2194 in value.enums) {
            _m_EnumDef_write(out, _item2194);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2195 in value.struct_specs) {
            _m_TypeName_write(out, _item2195);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2196 in value.func_specs) {
            _m_TypeName_write(out, _item2196);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2197 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2197);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2198 in value.withheld) {
            _m_Withheld_write(out, _item2198);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2199 in value.properties) {
            _m_PropertyDef_write(out, _item2199);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2200 in value.type_uses) {
            _m_TypeUse_write(out, _item2200);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2201 in value.use_contexts) {
            _m_UseContext_write(out, _item2201);
        }
        found.append(("use_contexts", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        if (interface) {
            out.unsigned(0);
        } else {
            out.unsigned(value.literal_args.count);
            for (var _item2202 in value.literal_args) {
                var (_t2203, _t2204, _t2205) = _item2202;
                out.loc(_t2203);
                out.unsigned(_t2204);
                out.loc(_t2205);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2206 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2206);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2207 in value.trait_types) {
            _m_TraitType_write(out, _item2207);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2208 in value.conversions) {
            _m_Conversion_write(out, _item2208);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2210 = Array<(u8[], u8[], String)>();
        for (var (_key2209, _) in value.overload_sets) {
            var _scratch2211 = out.scratch();
            _scratch2211.text(_key2209);
            var _vscratch2213 = out.scratch();
            _vscratch2213.unsigned(value.overload_sets[_key2209].count);
            for (var _item2214 in value.overload_sets[_key2209]) {
                _vscratch2213.text(_item2214);
            }
            _keys2210.append((_scratch2211.finish(), _vscratch2213.finish(), _key2209));
        }
        _keys2210.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2210.count);
        for (var (_bytes2212, _, _key2209) in _keys2210) {
            out.text(_key2209);
            out.unsigned(value.overload_sets[_key2209].count);
            for (var _item2215 in value.overload_sets[_key2209]) {
                out.text(_item2215);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2217 = Array<(u8[], u8[], String)>();
        for (var (_key2216, _) in value.overload_unions) {
            var _scratch2218 = out.scratch();
            _scratch2218.text(_key2216);
            var _vscratch2220 = out.scratch();
            _vscratch2220.unsigned(value.overload_unions[_key2216].count);
            for (var _item2221 in value.overload_unions[_key2216]) {
                _vscratch2220.unsigned(_item2221.count);
                for (var _item2222 in _item2221) {
                    _vscratch2220.text(_item2222);
                }
            }
            _keys2217.append((_scratch2218.finish(), _vscratch2220.finish(), _key2216));
        }
        _keys2217.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2217.count);
        for (var (_bytes2219, _, _key2216) in _keys2217) {
            out.text(_key2216);
            out.unsigned(value.overload_unions[_key2216].count);
            for (var _item2223 in value.overload_unions[_key2216]) {
                out.unsigned(_item2223.count);
                for (var _item2224 in _item2223) {
                    out.text(_item2224);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2226 = Array<(u8[], u8[], String)>();
        for (var (_key2225, _) in value.method_overload_sets) {
            var _scratch2227 = out.scratch();
            _scratch2227.text(_key2225);
            var _vscratch2229 = out.scratch();
            var _keys2231 = Array<(u8[], u8[], String)>();
            for (var (_key2230, _) in value.method_overload_sets[_key2225]) {
                var _scratch2232 = _vscratch2229.scratch();
                _scratch2232.text(_key2230);
                var _vscratch2234 = _vscratch2229.scratch();
                _vscratch2234.unsigned(value.method_overload_sets[_key2225][_key2230].count);
                for (var _item2235 in value.method_overload_sets[_key2225][_key2230]) {
                    _vscratch2234.text(_item2235);
                }
                _keys2231.append((_scratch2232.finish(), _vscratch2234.finish(), _key2230));
            }
            _keys2231.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2229.unsigned(_keys2231.count);
            for (var (_bytes2233, _, _key2230) in _keys2231) {
                _vscratch2229.text(_key2230);
                _vscratch2229.unsigned(value.method_overload_sets[_key2225][_key2230].count);
                for (var _item2236 in value.method_overload_sets[_key2225][_key2230]) {
                    _vscratch2229.text(_item2236);
                }
            }
            _keys2226.append((_scratch2227.finish(), _vscratch2229.finish(), _key2225));
        }
        _keys2226.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2226.count);
        for (var (_bytes2228, _, _key2225) in _keys2226) {
            out.text(_key2225);
            var _keys2238 = Array<(u8[], u8[], String)>();
            for (var (_key2237, _) in value.method_overload_sets[_key2225]) {
                var _scratch2239 = out.scratch();
                _scratch2239.text(_key2237);
                var _vscratch2241 = out.scratch();
                _vscratch2241.unsigned(value.method_overload_sets[_key2225][_key2237].count);
                for (var _item2242 in value.method_overload_sets[_key2225][_key2237]) {
                    _vscratch2241.text(_item2242);
                }
                _keys2238.append((_scratch2239.finish(), _vscratch2241.finish(), _key2237));
            }
            _keys2238.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2238.count);
            for (var (_bytes2240, _, _key2237) in _keys2238) {
                out.text(_key2237);
                out.unsigned(value.method_overload_sets[_key2225][_key2237].count);
                for (var _item2243 in value.method_overload_sets[_key2225][_key2237]) {
                    out.text(_item2243);
                }
            }
        }
        found.append(("method_overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_ExtensionScopes_write(out, value.extension_scopes);
        found.append(("extension_scopes", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2245 = Array<(u8[], u8[], Loc)>();
        for (var _key2244 in value.private_functions) {
            var _scratch2246 = out.scratch();
            _scratch2246.loc(_key2244);
            var _vscratch2248 = out.scratch();
            _keys2245.append((_scratch2246.finish(), _vscratch2248.finish(), _key2244));
        }
        _keys2245.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2245.count);
        for (var (_bytes2247, _, _key2244) in _keys2245) {
            out.loc(_key2244);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2250 = Array<(u8[], u8[], Loc)>();
        for (var _key2249 in value.file_private_functions) {
            var _scratch2251 = out.scratch();
            _scratch2251.loc(_key2249);
            var _vscratch2253 = out.scratch();
            _keys2250.append((_scratch2251.finish(), _vscratch2253.finish(), _key2249));
        }
        _keys2250.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2250.count);
        for (var (_bytes2252, _, _key2249) in _keys2250) {
            out.loc(_key2249);
        }
        found.append(("file_private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        if (interface) {
            out.unsigned(0);
        } else {
            out.unsigned(value.call_targets.count);
            for (var _item2254 in value.call_targets) {
                var (_t2255, _t2256) = _item2254;
                out.loc(_t2255);
                out.text(_t2256);
            }
        }
        found.append(("call_targets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        if (interface) {
            out.unsigned(0);
        } else {
            out.unsigned(value.argument_names.count);
            for (var _item2257 in value.argument_names) {
                var (_t2258, _t2259) = _item2257;
                out.loc(_t2258);
                out.text(_t2259);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2260 in value.namespaces) {
            out.text(_item2260);
        }
        found.append(("namespaces", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        if (interface) {
            out.unsigned(0);
        } else {
            out.unsigned(value.cached_files.count);
            for (var _item2261 in value.cached_files) {
                out.flag(_item2261);
            }
        }
        found.append(("cached_files", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        if (interface) {
            write_interface_summaries(out, value.recorded_summaries);
        } else {
            var _keys2263 = Array<(u8[], u8[], Loc)>();
            for (var (_key2262, _) in value.recorded_summaries) {
                var _scratch2264 = out.scratch();
                _scratch2264.loc(_key2262);
                var _vscratch2266 = out.scratch();
                _vscratch2266.text(value.recorded_summaries[_key2262]);
                _keys2263.append((_scratch2264.finish(), _vscratch2266.finish(), _key2262));
            }
            _keys2263.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2263.count);
            for (var (_bytes2265, _, _key2262) in _keys2263) {
                out.loc(_key2262);
                out.text(value.recorded_summaries[_key2262]);
            }
        }
        found.append(("recorded_summaries", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        if (interface) {
            out.unsigned(0);
        } else {
            var _keys2268 = Array<(u8[], u8[], Loc)>();
            for (var _key2267 in value.stripped) {
                var _scratch2269 = out.scratch();
                _scratch2269.loc(_key2267);
                var _vscratch2271 = out.scratch();
                _keys2268.append((_scratch2269.finish(), _vscratch2271.finish(), _key2267));
            }
            _keys2268.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2268.count);
            for (var (_bytes2270, _, _key2267) in _keys2268) {
                out.loc(_key2267);
            }
        }
        found.append(("stripped", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.blank_bodies = false;
        _m_Templates_write(out, value.templates);
        found.append(("templates", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_Checked_write(out, value.checked);
        found.append(("checked", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2273 = Array<(u8[], u8[], String)>();
        for (var (_key2272, _) in value.spec_requests) {
            var _scratch2274 = out.scratch();
            _scratch2274.text(_key2272);
            var _vscratch2276 = out.scratch();
            _m_SpecRequest_write(_vscratch2276, value.spec_requests[_key2272]);
            _keys2273.append((_scratch2274.finish(), _vscratch2276.finish(), _key2272));
        }
        _keys2273.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2273.count);
        for (var (_bytes2275, _, _key2272) in _keys2273) {
            out.text(_key2272);
            _m_SpecRequest_write(out, value.spec_requests[_key2272]);
        }
        found.append(("spec_requests", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.flag(value.record_summaries);
        found.append(("record_summaries", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        if (interface) {
            out.unsigned(0);
        } else {
            out.unsigned(value.summaries_to_record.count);
            for (var _item2277 in value.summaries_to_record) {
                var (_t2278, _t2279) = _item2277;
                out.loc(_t2278);
                out.text(_t2279);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2281 = Array<(u8[], u8[], String)>();
        for (var (_key2280, _) in value.caller_copies) {
            var _scratch2282 = out.scratch();
            _scratch2282.text(_key2280);
            var _vscratch2284 = out.scratch();
            _vscratch2284.unsigned(value.caller_copies[_key2280].count);
            for (var _item2285 in value.caller_copies[_key2280]) {
                _vscratch2284.flag(_item2285);
            }
            _keys2281.append((_scratch2282.finish(), _vscratch2284.finish(), _key2280));
        }
        _keys2281.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2281.count);
        for (var (_bytes2283, _, _key2280) in _keys2281) {
            out.text(_key2280);
            out.unsigned(value.caller_copies[_key2280].count);
            for (var _item2286 in value.caller_copies[_key2280]) {
                out.flag(_item2286);
            }
        }
        found.append(("caller_copies", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.flag(value.linked);
        found.append(("linked", interface_text(out)));
    }
    for (var _item2287 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2287);
        found.append(("structs " + _item2287.name, interface_text(out)));
    }
    for (var _item2288 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2288);
        found.append(("functions " + _item2288.name, interface_text(out)));
    }
    return found;
}
