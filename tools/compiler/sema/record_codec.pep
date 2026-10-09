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
    struct_named,
    summary_without_place,
    write_interface_checked_summaries,
    write_interface_summaries
] from "record";

## Decodes a function body a reader skipped (`RecordIn.lazy_bodies`).
##
## @param pending where the body is in its record
## @returns the body
export decode_body(pending: PendingBody): Block {
    return _m_Block_read(RecordIn.at(pending));
}

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
        _v105.append(_m_StructDef_read_lazy(input));
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
        _v114.append(_m_FunctionDef_read_lazy(input));
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
    } else if (out.pending_as_bytes and value.body_origin.is_value()) {
        # Hashed for a delta or an own interface: a body read from
        # a record is as the record wrote it, decoded or not.
        out.unsigned(2);
        out.pending(value.body_origin.value());
    } else {
        var _body = value.body;
        if (value.pending_body.is_value()) {
            _body = Optional<Block>.Value(decode_body(value.pending_body.value()));
        }
        if (_body.is_value()) {
            out.unsigned(1);
            var _mark = out.size_mark();
            _m_Block_write(out, _body.value());
            out.size_fill(_mark);
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
    return _m_FunctionDef_read_with(input, false);
}

_m_FunctionDef_read_lazy(input: RecordIn): FunctionDef {
    return _m_FunctionDef_read_with(input, input.lazy_bodies);
}

_m_FunctionDef_read_with(input: RecordIn, lazy: bool): FunctionDef {
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
    var _pending = Optional<PendingBody>.Empty;
    var _f300 = Optional<Block>.Empty;
    if (input.unsigned() == 1) {
        var _size = input.size();
        if (lazy) {
            # Present, as an empty block, until decoded.
            _pending = Optional<PendingBody>.Value(input.skip(_size));
            _f300 = Optional<Block>.Value(Block());
        } else {
            _f300 = Optional<Block>.Value(_m_Block_read(input));
        }
    }
    var _o301 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o301 = Optional<String>.Value(input.text());
    }
    var _f302 = _o301;
    var _f303 = input.flag();
    var _f304 = input.flag();
    var _f305 = input.flag();
    var _v306 = Array<ast.Attribute>();
    var _n307 = input.count();
    for (var _ in 0.._n307) {
        _v306.append(_a_Attribute_read(input));
    }
    var _f308 = _v306;
    var _f309 = input.loc();
    var _o310 = Optional<Array<String>>.Empty;
    if (input.unsigned() == 1) {
        var _v311 = Array<String>();
        var _n312 = input.count();
        for (var _ in 0.._n312) {
            _v311.append(input.text());
        }
        _o310 = Optional<Array<String>>.Value(_v311);
    }
    var _f313 = _o310;
    var _f314 = input.loc();
    var _function = FunctionDef(
        _f292, _f293, _f296, _f299, _f300, _f302, _f303, _f304, _f305, _f308, _f309, _f313, _f314
    );
    if (_pending.is_value()) {
        if (_function.is_generic_func or _function.generic_params.count > 0) {
            _function.body = Optional<Block>.Value(decode_body(_pending.value()));
        } else {
            _function.pending_body = _pending;
            _function.body_origin = _pending;
        }
    }
    return _function;
}

_a_Attribute_write(out: RecordOut, value: ast.Attribute) {
    _a_Expression_write(out, value.body);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Attribute_read(input: RecordIn): ast.Attribute {
    var _f315 = _a_Expression_read(input);
    var _s316 = input.unsigned();
    var _f317 = ast.Span(_s316, input.unsigned());
    var value = ast.Attribute(_f315, _f317);
    value.body = _f315;
    value.span = _f317;
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
            for (var _item359 in p1) {
                _a_Expression_write(out, _item359);
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
            for (var _item372 in p0) {
                _a_Expression_write(out, _item372);
            }
            out.unsigned(p1.count);
            for (var _item376 in p1) {
                _a_Label_write(out, _item376);
            }
            out.unsigned(out.blank_locs ? 0 : p2.start);
            out.unsigned(out.blank_locs ? 0 : p2.end);
        }
        ArrayLiteral(p0, p1) => {
            out.unsigned(14);
            out.unsigned(p0.count);
            for (var _item382 in p0) {
                _a_Expression_write(out, _item382);
            }
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
        MapLiteral(p0, p1) => {
            out.unsigned(15);
            out.unsigned(p0.count);
            for (var _item388 in p0) {
                _a_MapEntry_write(out, _item388);
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
            for (var _item401 in p0) {
                _a_StringPart_write(out, _item401);
            }
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
        }
        FormatString(p0, p1, p2, p3) => {
            out.unsigned(19);
            out.unsigned(p0.count);
            for (var _item407 in p0) {
                _a_StringPart_write(out, _item407);
            }
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
            out.unsigned(p2);
            out.unsigned(p3.count);
            for (var _item414 in p3) {
                out.unsigned(out.blank_locs ? 0 : _item414.start);
                out.unsigned(out.blank_locs ? 0 : _item414.end);
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
        var _f318 = _a_Literal_read(input);
        var _s319 = input.unsigned();
        var _f320 = ast.Span(_s319, input.unsigned());
        return ast.Expression.Literal(_f318, _f320);
    }
    if (tag == 1) {
        var _f321 = input.text();
        var _s322 = input.unsigned();
        var _f323 = ast.Span(_s322, input.unsigned());
        return ast.Expression.SymbolRef(_f321, _f323);
    }
    if (tag == 2) {
        var _f324 = _a_TypeName_read(input);
        return ast.Expression.TypeLiteral(_f324);
    }
    if (tag == 3) {
        var _f325 = _a_TypeName_read(input);
        return ast.Expression.SizeOf(_f325);
    }
    if (tag == 4) {
        var _f326 = input.text();
        var _f327 = input.flag();
        var _f328 = _a_Expression_read(input);
        var _s329 = input.unsigned();
        var _f330 = ast.Span(_s329, input.unsigned());
        return ast.Expression.Unary(_f326, _f327, _f328, _f330);
    }
    if (tag == 5) {
        var _f331 = _a_Expression_read(input);
        var _f332 = _a_TypeName_read(input);
        var _s333 = input.unsigned();
        var _f334 = ast.Span(_s333, input.unsigned());
        var _s335 = input.unsigned();
        var _f336 = ast.Span(_s335, input.unsigned());
        var _f337 = input.flag();
        return ast.Expression.Cast(_f331, _f332, _f334, _f336, _f337);
    }
    if (tag == 6) {
        var _f338 = _a_Expression_read(input);
        var _f339 = input.text();
        var _f340 = _a_Expression_read(input);
        var _s341 = input.unsigned();
        var _f342 = ast.Span(_s341, input.unsigned());
        return ast.Expression.Binary(_f338, _f339, _f340, _f342);
    }
    if (tag == 7) {
        var _f343 = _a_Expression_read(input);
        var _f344 = _a_Expression_read(input);
        var _f345 = _a_Expression_read(input);
        var _s346 = input.unsigned();
        var _f347 = ast.Span(_s346, input.unsigned());
        return ast.Expression.Ternary(_f343, _f344, _f345, _f347);
    }
    if (tag == 8) {
        var _f348 = _a_Expression_read(input);
        var _f349 = _a_Expression_read(input);
        var _s350 = input.unsigned();
        var _f351 = ast.Span(_s350, input.unsigned());
        return ast.Expression.Index(_f348, _f349, _f351);
    }
    if (tag == 9) {
        var _f352 = _a_Expression_read(input);
        var _f353 = input.text();
        var _s354 = input.unsigned();
        var _f355 = ast.Span(_s354, input.unsigned());
        var _s356 = input.unsigned();
        var _f357 = ast.Span(_s356, input.unsigned());
        return ast.Expression.MemberAccess(_f352, _f353, _f355, _f357);
    }
    if (tag == 10) {
        var _f358 = _a_Expression_read(input);
        var _v360 = Array<ast.Expression>();
        var _n361 = input.count();
        for (var _ in 0.._n361) {
            _v360.append(_a_Expression_read(input));
        }
        var _f362 = _v360;
        var _s363 = input.unsigned();
        var _f364 = ast.Span(_s363, input.unsigned());
        return ast.Expression.FunctionCall(_f358, _f362, _f364);
    }
    if (tag == 11) {
        var _f365 = input.text();
        var _s366 = input.unsigned();
        var _f367 = ast.Span(_s366, input.unsigned());
        var _f368 = _a_Expression_read(input);
        var _s369 = input.unsigned();
        var _f370 = ast.Span(_s369, input.unsigned());
        return ast.Expression.NamedArgument(_f365, _f367, _f368, _f370);
    }
    if (tag == 12) {
        var _f371 = _a_ClosureLiteral_read(input);
        return ast.Expression.Closure(_f371);
    }
    if (tag == 13) {
        var _v373 = Array<ast.Expression>();
        var _n374 = input.count();
        for (var _ in 0.._n374) {
            _v373.append(_a_Expression_read(input));
        }
        var _f375 = _v373;
        var _v377 = Array<ast.Label>();
        var _n378 = input.count();
        for (var _ in 0.._n378) {
            _v377.append(_a_Label_read(input));
        }
        var _f379 = _v377;
        var _s380 = input.unsigned();
        var _f381 = ast.Span(_s380, input.unsigned());
        return ast.Expression.Tuple(_f375, _f379, _f381);
    }
    if (tag == 14) {
        var _v383 = Array<ast.Expression>();
        var _n384 = input.count();
        for (var _ in 0.._n384) {
            _v383.append(_a_Expression_read(input));
        }
        var _f385 = _v383;
        var _s386 = input.unsigned();
        var _f387 = ast.Span(_s386, input.unsigned());
        return ast.Expression.ArrayLiteral(_f385, _f387);
    }
    if (tag == 15) {
        var _v389 = Array<ast.MapEntry>();
        var _n390 = input.count();
        for (var _ in 0.._n390) {
            _v389.append(_a_MapEntry_read(input));
        }
        var _f391 = _v389;
        var _s392 = input.unsigned();
        var _f393 = ast.Span(_s392, input.unsigned());
        return ast.Expression.MapLiteral(_f391, _f393);
    }
    if (tag == 16) {
        var _f394 = _a_MatchExpression_read(input);
        return ast.Expression.Match(_f394);
    }
    if (tag == 17) {
        var _f395 = _a_Expression_read(input);
        var _f396 = _a_Pattern_read(input);
        var _s397 = input.unsigned();
        var _f398 = ast.Span(_s397, input.unsigned());
        var _s399 = input.unsigned();
        var _f400 = ast.Span(_s399, input.unsigned());
        return ast.Expression.Is(_f395, _f396, _f398, _f400);
    }
    if (tag == 18) {
        var _v402 = Array<ast.StringPart>();
        var _n403 = input.count();
        for (var _ in 0.._n403) {
            _v402.append(_a_StringPart_read(input));
        }
        var _f404 = _v402;
        var _s405 = input.unsigned();
        var _f406 = ast.Span(_s405, input.unsigned());
        return ast.Expression.Interpolated(_f404, _f406);
    }
    if (tag == 19) {
        var _v408 = Array<ast.StringPart>();
        var _n409 = input.count();
        for (var _ in 0.._n409) {
            _v408.append(_a_StringPart_read(input));
        }
        var _f410 = _v408;
        var _s411 = input.unsigned();
        var _f412 = ast.Span(_s411, input.unsigned());
        var _f413 = input.unsigned();
        var _v415 = Array<ast.Span>();
        var _n416 = input.count();
        for (var _ in 0.._n416) {
            var _s417 = input.unsigned();
            _v415.append(ast.Span(_s417, input.unsigned()));
        }
        var _f418 = _v415;
        return ast.Expression.FormatString(_f410, _f412, _f413, _f418);
    }
    if (tag == 20) {
        var _f419 = _a_Expression_read(input);
        var _s420 = input.unsigned();
        var _f421 = ast.Span(_s420, input.unsigned());
        return ast.Expression.Parenthesized(_f419, _f421);
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
        var _f422 = input.text();
        var _s423 = input.unsigned();
        var _f424 = ast.Span(_s423, input.unsigned());
        return ast.StringPart.Text(_f422, _f424);
    }
    if (tag == 1) {
        var _f425 = _a_Expression_read(input);
        var _s426 = input.unsigned();
        var _f427 = ast.Span(_s426, input.unsigned());
        var _o428 = Optional<ast.FormatSpec>.Empty;
        if (input.unsigned() == 1) {
            _o428 = Optional<ast.FormatSpec>.Value(_a_FormatSpec_read(input));
        }
        var _f429 = _o428;
        return ast.StringPart.Hole(_f425, _f427, _f429);
    }
    if (tag == 2) {
        var _f430 = input.unsigned();
        var _s431 = input.unsigned();
        var _f432 = ast.Span(_s431, input.unsigned());
        var _s433 = input.unsigned();
        var _f434 = ast.Span(_s433, input.unsigned());
        var _o435 = Optional<ast.FormatSpec>.Empty;
        if (input.unsigned() == 1) {
            _o435 = Optional<ast.FormatSpec>.Value(_a_FormatSpec_read(input));
        }
        var _f436 = _o435;
        return ast.StringPart.Argument(_f430, _f432, _f434, _f436);
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
    var _f437 = input.text();
    var _f438 = input.signed();
    var _f439 = input.flag();
    var _o440 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s441 = input.unsigned();
        _o440 = Optional<ast.Span>.Value(ast.Span(_s441, input.unsigned()));
    }
    var _f442 = _o440;
    var _o443 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s444 = input.unsigned();
        _o443 = Optional<ast.Span>.Value(ast.Span(_s444, input.unsigned()));
    }
    var _f445 = _o443;
    var _f446 = input.signed();
    var _f447 = input.signed();
    var _o448 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s449 = input.unsigned();
        _o448 = Optional<ast.Span>.Value(ast.Span(_s449, input.unsigned()));
    }
    var _f450 = _o448;
    var _f451 = input.text();
    var _s452 = input.unsigned();
    var _f453 = ast.Span(_s452, input.unsigned());
    var value = ast.FormatSpec();
    value.fill = _f437;
    value.align = _f438;
    value.has_align = _f439;
    value.plus = _f442;
    value.zero = _f445;
    value.width = _f446;
    value.precision = _f447;
    value.point = _f450;
    value.kind = _f451;
    value.kind_span = _f453;
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
        for (var _item454 in value.elements.value()) {
            _a_Pattern_write(out, _item454);
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
        for (var _item455 in value.bindings.value()) {
            _a_Pattern_write(out, _item455);
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
    var _o456 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o456 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f457 = _o456;
    var _o458 = Optional<Array<ast.Pattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v459 = Array<ast.Pattern>();
        var _n460 = input.count();
        for (var _ in 0.._n460) {
            _v459.append(_a_Pattern_read(input));
        }
        _o458 = Optional<Array<ast.Pattern>>.Value(_v459);
    }
    var _f461 = _o458;
    var _o462 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o462 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f463 = _o462;
    var _f464 = input.text();
    var _s465 = input.unsigned();
    var _f466 = ast.Span(_s465, input.unsigned());
    var _o467 = Optional<Array<ast.Pattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v468 = Array<ast.Pattern>();
        var _n469 = input.count();
        for (var _ in 0.._n469) {
            _v468.append(_a_Pattern_read(input));
        }
        _o467 = Optional<Array<ast.Pattern>>.Value(_v468);
    }
    var _f470 = _o467;
    var _o471 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o471 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f472 = _o471;
    var _f473 = input.flag();
    var _o474 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o474 = Optional<String>.Value(input.text());
    }
    var _f475 = _o474;
    var _o476 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o476 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f477 = _o476;
    var _s478 = input.unsigned();
    var _f479 = ast.Span(_s478, input.unsigned());
    var value = ast.Pattern();
    value.literal = _f457;
    value.elements = _f461;
    value.qualifier = _f463;
    value.case_name = _f464;
    value.case_span = _f466;
    value.bindings = _f470;
    value.range_end = _f472;
    value.range_inclusive = _f473;
    value.constant = _f475;
    value.type_name = _f477;
    value.span = _f479;
    return value;
}

_a_TypeName_write(out: RecordOut, value: ast.TypeName) {
    out.text(value.name);
    out.unsigned(value.generic_types.count);
    for (var _item480 in value.generic_types) {
        _a_TypeName_write(out, _item480);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.labels.count);
    for (var _item481 in value.labels) {
        out.text(_item481);
    }
}

_a_TypeName_read(input: RecordIn): ast.TypeName {
    var _f482 = input.text();
    var _v483 = Array<ast.TypeName>();
    var _n484 = input.count();
    for (var _ in 0.._n484) {
        _v483.append(_a_TypeName_read(input));
    }
    var _f485 = _v483;
    var _s486 = input.unsigned();
    var _f487 = ast.Span(_s486, input.unsigned());
    var _v488 = Array<String>();
    var _n489 = input.count();
    for (var _ in 0.._n489) {
        _v488.append(input.text());
    }
    var _f490 = _v488;
    var value = ast.TypeName();
    value.name = _f482;
    value.generic_types = _f485;
    value.span = _f487;
    value.labels = _f490;
    return value;
}

_a_MatchExpression_write(out: RecordOut, value: ast.MatchExpression) {
    _a_Expression_write(out, value.value);
    out.unsigned(value.arms.count);
    for (var _item491 in value.arms) {
        _a_MatchValueArm_write(out, _item491);
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
    var _f492 = _a_Expression_read(input);
    var _v493 = Array<ast.MatchValueArm>();
    var _n494 = input.count();
    for (var _ in 0.._n494) {
        _v493.append(_a_MatchValueArm_read(input));
    }
    var _f495 = _v493;
    var _o496 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o496 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f497 = _o496;
    var _s498 = input.unsigned();
    var _f499 = ast.Span(_s498, input.unsigned());
    var _s500 = input.unsigned();
    var _f501 = ast.Span(_s500, input.unsigned());
    var _s502 = input.unsigned();
    var _f503 = ast.Span(_s502, input.unsigned());
    var value = ast.MatchExpression(_f492);
    value.value = _f492;
    value.arms = _f495;
    value.else_value = _f497;
    value.else_span = _f499;
    value.keyword_span = _f501;
    value.span = _f503;
    return value;
}

_a_MatchValueArm_write(out: RecordOut, value: ast.MatchValueArm) {
    out.unsigned(value.patterns.count);
    for (var _item504 in value.patterns) {
        _a_Pattern_write(out, _item504);
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
    var _v505 = Array<ast.Pattern>();
    var _n506 = input.count();
    for (var _ in 0.._n506) {
        _v505.append(_a_Pattern_read(input));
    }
    var _f507 = _v505;
    var _o508 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o508 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f509 = _o508;
    var _f510 = _a_Expression_read(input);
    var _s511 = input.unsigned();
    var _f512 = ast.Span(_s511, input.unsigned());
    var value = ast.MatchValueArm();
    value.patterns = _f507;
    value.guard = _f509;
    value.value = _f510;
    value.span = _f512;
    return value;
}

_a_MapEntry_write(out: RecordOut, value: ast.MapEntry) {
    _a_Expression_write(out, value.key);
    _a_Expression_write(out, value.value);
}

_a_MapEntry_read(input: RecordIn): ast.MapEntry {
    var _f513 = _a_Expression_read(input);
    var _f514 = _a_Expression_read(input);
    var value = ast.MapEntry(_f513, _f514);
    value.key = _f513;
    value.value = _f514;
    return value;
}

_a_Label_write(out: RecordOut, value: ast.Label) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Label_read(input: RecordIn): ast.Label {
    var _f515 = input.text();
    var _s516 = input.unsigned();
    var _f517 = ast.Span(_s516, input.unsigned());
    var value = ast.Label(_f515, _f517);
    value.name = _f515;
    value.span = _f517;
    return value;
}

_a_ClosureLiteral_write(out: RecordOut, value: ast.ClosureLiteral) {
    out.unsigned(value.parameters.count);
    for (var _item518 in value.parameters) {
        _a_VariableDecl_write(out, _item518);
    }
    _a_TypeName_write(out, value.return_type);
    _a_Block_write(out, value.body);
    out.flag(value.expression_body);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_ClosureLiteral_read(input: RecordIn): ast.ClosureLiteral {
    var _v519 = Array<ast.VariableDecl>();
    var _n520 = input.count();
    for (var _ in 0.._n520) {
        _v519.append(_a_VariableDecl_read(input));
    }
    var _f521 = _v519;
    var _f522 = _a_TypeName_read(input);
    var _f523 = _a_Block_read(input);
    var _f524 = input.flag();
    var _s525 = input.unsigned();
    var _f526 = ast.Span(_s525, input.unsigned());
    var value = ast.ClosureLiteral();
    value.parameters = _f521;
    value.return_type = _f522;
    value.body = _f523;
    value.expression_body = _f524;
    value.span = _f526;
    return value;
}

_a_Block_write(out: RecordOut, value: ast.Block) {
    out.unsigned(value.statements.count);
    for (var _item527 in value.statements) {
        _a_Statement_write(out, _item527);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item528 in value.attributes) {
        _a_Attribute_write(out, _item528);
    }
}

_a_Block_read(input: RecordIn): ast.Block {
    var _v529 = Array<ast.Statement>();
    var _n530 = input.count();
    for (var _ in 0.._n530) {
        _v529.append(_a_Statement_read(input));
    }
    var _f531 = _v529;
    var _s532 = input.unsigned();
    var _f533 = ast.Span(_s532, input.unsigned());
    var _v534 = Array<ast.Attribute>();
    var _n535 = input.count();
    for (var _ in 0.._n535) {
        _v534.append(_a_Attribute_read(input));
    }
    var _f536 = _v534;
    var value = ast.Block();
    value.statements = _f531;
    value.span = _f533;
    value.attributes = _f536;
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
            for (var _item551 in p1) {
                _a_DestructureBinding_write(out, _item551);
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
            for (var _item574 in p0) {
                _a_DestructureBinding_write(out, _item574);
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
        var _f537 = _a_Expression_read(input);
        return ast.Statement.Expression(_f537);
    }
    if (tag == 1) {
        var _f538 = _a_Block_read(input);
        return ast.Statement.Block(_f538);
    }
    if (tag == 2) {
        var _f539 = _a_Declaration_read(input);
        return ast.Statement.Declaration(_f539);
    }
    if (tag == 3) {
        var _f540 = _a_Expression_read(input);
        var _f541 = _a_Block_read(input);
        var _o542 = Optional<ast.Block>.Empty;
        if (input.unsigned() == 1) {
            _o542 = Optional<ast.Block>.Value(_a_Block_read(input));
        }
        var _f543 = _o542;
        var _s544 = input.unsigned();
        var _f545 = ast.Span(_s544, input.unsigned());
        return ast.Statement.Branch(_f540, _f541, _f543, _f545);
    }
    if (tag == 4) {
        var _f546 = _a_Expression_read(input);
        var _f547 = _a_Block_read(input);
        var _s548 = input.unsigned();
        var _f549 = ast.Span(_s548, input.unsigned());
        return ast.Statement.While(_f546, _f547, _f549);
    }
    if (tag == 5) {
        var _f550 = _a_VariableDecl_read(input);
        var _v552 = Array<ast.DestructureBinding>();
        var _n553 = input.count();
        for (var _ in 0.._n553) {
            _v552.append(_a_DestructureBinding_read(input));
        }
        var _f554 = _v552;
        var _f555 = _a_Expression_read(input);
        var _f556 = _a_Block_read(input);
        var _s557 = input.unsigned();
        var _f558 = ast.Span(_s557, input.unsigned());
        return ast.Statement.For(_f550, _f554, _f555, _f556, _f558);
    }
    if (tag == 6) {
        var _o559 = Optional<ast.VariableDecl>.Empty;
        if (input.unsigned() == 1) {
            _o559 = Optional<ast.VariableDecl>.Value(_a_VariableDecl_read(input));
        }
        var _f560 = _o559;
        var _f561 = _a_Expression_read(input);
        var _f562 = _a_Block_read(input);
        var _o563 = Optional<ast.Block>.Empty;
        if (input.unsigned() == 1) {
            _o563 = Optional<ast.Block>.Value(_a_Block_read(input));
        }
        var _f564 = _o563;
        var _s565 = input.unsigned();
        var _f566 = ast.Span(_s565, input.unsigned());
        return ast.Statement.With(_f560, _f561, _f562, _f564, _f566);
    }
    if (tag == 7) {
        var _o567 = Optional<ast.Expression>.Empty;
        if (input.unsigned() == 1) {
            _o567 = Optional<ast.Expression>.Value(_a_Expression_read(input));
        }
        var _f568 = _o567;
        var _s569 = input.unsigned();
        var _f570 = ast.Span(_s569, input.unsigned());
        return ast.Statement.Return(_f568, _f570);
    }
    if (tag == 8) {
        var _f571 = input.flag();
        var _s572 = input.unsigned();
        var _f573 = ast.Span(_s572, input.unsigned());
        return ast.Statement.LoopBreak(_f571, _f573);
    }
    if (tag == 9) {
        var _v575 = Array<ast.DestructureBinding>();
        var _n576 = input.count();
        for (var _ in 0.._n576) {
            _v575.append(_a_DestructureBinding_read(input));
        }
        var _f577 = _v575;
        var _f578 = _a_Expression_read(input);
        var _f579 = input.flag();
        var _s580 = input.unsigned();
        var _f581 = ast.Span(_s580, input.unsigned());
        return ast.Statement.Destructure(_f577, _f578, _f579, _f581);
    }
    if (tag == 10) {
        var _f582 = _a_Match_read(input);
        return ast.Statement.Match(_f582);
    }
    if (tag == 11) {
        var _f583 = _a_StaticBlock_read(input);
        return ast.Statement.Static(_f583);
    }
    input.fail("Statement", tag);
    return _a_Statement_read(input);
}

_a_StaticBlock_write(out: RecordOut, value: ast.StaticBlock) {
    out.unsigned(value.captures.count);
    for (var _item584 in value.captures) {
        _a_Label_write(out, _item584);
    }
    out.unsigned(value.written_captures.count);
    for (var _item585 in value.written_captures) {
        _a_Expression_write(out, _item585);
    }
    _a_Block_write(out, value.block);
    out.unsigned(out.blank_locs ? 0 : value.keyword_span.start);
    out.unsigned(out.blank_locs ? 0 : value.keyword_span.end);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item586 in value.attributes) {
        _a_Attribute_write(out, _item586);
    }
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_StaticBlock_read(input: RecordIn): ast.StaticBlock {
    var _v587 = Array<ast.Label>();
    var _n588 = input.count();
    for (var _ in 0.._n588) {
        _v587.append(_a_Label_read(input));
    }
    var _f589 = _v587;
    var _v590 = Array<ast.Expression>();
    var _n591 = input.count();
    for (var _ in 0.._n591) {
        _v590.append(_a_Expression_read(input));
    }
    var _f592 = _v590;
    var _f593 = _a_Block_read(input);
    var _s594 = input.unsigned();
    var _f595 = ast.Span(_s594, input.unsigned());
    var _s596 = input.unsigned();
    var _f597 = ast.Span(_s596, input.unsigned());
    var _v598 = Array<ast.Attribute>();
    var _n599 = input.count();
    for (var _ in 0.._n599) {
        _v598.append(_a_Attribute_read(input));
    }
    var _f600 = _v598;
    var _f601 = input.flag();
    var _f602 = input.flag();
    var value = ast.StaticBlock();
    value.captures = _f589;
    value.written_captures = _f592;
    value.block = _f593;
    value.keyword_span = _f595;
    value.span = _f597;
    value.attributes = _f600;
    value.is_exported = _f601;
    value.is_private = _f602;
    return value;
}

_a_Match_write(out: RecordOut, value: ast.Match) {
    _a_Expression_write(out, value.value);
    out.unsigned(value.arms.count);
    for (var _item603 in value.arms) {
        _a_MatchArm_write(out, _item603);
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
    var _f604 = _a_Expression_read(input);
    var _v605 = Array<ast.MatchArm>();
    var _n606 = input.count();
    for (var _ in 0.._n606) {
        _v605.append(_a_MatchArm_read(input));
    }
    var _f607 = _v605;
    var _o608 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o608 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f609 = _o608;
    var _s610 = input.unsigned();
    var _f611 = ast.Span(_s610, input.unsigned());
    var _s612 = input.unsigned();
    var _f613 = ast.Span(_s612, input.unsigned());
    var _s614 = input.unsigned();
    var _f615 = ast.Span(_s614, input.unsigned());
    var value = ast.Match(_f604);
    value.value = _f604;
    value.arms = _f607;
    value.else_block = _f609;
    value.else_span = _f611;
    value.keyword_span = _f613;
    value.span = _f615;
    return value;
}

_a_MatchArm_write(out: RecordOut, value: ast.MatchArm) {
    out.unsigned(value.patterns.count);
    for (var _item616 in value.patterns) {
        _a_Pattern_write(out, _item616);
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
    var _v617 = Array<ast.Pattern>();
    var _n618 = input.count();
    for (var _ in 0.._n618) {
        _v617.append(_a_Pattern_read(input));
    }
    var _f619 = _v617;
    var _o620 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o620 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f621 = _o620;
    var _f622 = _a_Block_read(input);
    var _s623 = input.unsigned();
    var _f624 = ast.Span(_s623, input.unsigned());
    var value = ast.MatchArm();
    value.patterns = _f619;
    value.guard = _f621;
    value.body = _f622;
    value.span = _f624;
    return value;
}

_a_DestructureBinding_write(out: RecordOut, value: ast.DestructureBinding) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    _a_TypeName_write(out, value.type_name);
    out.unsigned(value.nested.count);
    for (var _item625 in value.nested) {
        _a_DestructureBinding_write(out, _item625);
    }
}

_a_DestructureBinding_read(input: RecordIn): ast.DestructureBinding {
    var _f626 = input.text();
    var _s627 = input.unsigned();
    var _f628 = ast.Span(_s627, input.unsigned());
    var _f629 = _a_TypeName_read(input);
    var _v630 = Array<ast.DestructureBinding>();
    var _n631 = input.count();
    for (var _ in 0.._n631) {
        _v630.append(_a_DestructureBinding_read(input));
    }
    var _f632 = _v630;
    var value = ast.DestructureBinding();
    value.name = _f626;
    value.name_span = _f628;
    value.type_name = _f629;
    value.nested = _f632;
    return value;
}

_a_VariableDecl_write(out: RecordOut, value: ast.VariableDecl) {
    out.unsigned(value.attributes.count);
    for (var _item633 in value.attributes) {
        _a_Attribute_write(out, _item633);
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
    var _v634 = Array<ast.Attribute>();
    var _n635 = input.count();
    for (var _ in 0.._n635) {
        _v634.append(_a_Attribute_read(input));
    }
    var _f636 = _v634;
    var _f637 = input.text();
    var _s638 = input.unsigned();
    var _f639 = ast.Span(_s638, input.unsigned());
    var _f640 = _a_TypeName_read(input);
    var _o641 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o641 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f642 = _o641;
    var _f643 = input.flag();
    var _s644 = input.unsigned();
    var _f645 = ast.Span(_s644, input.unsigned());
    var _f646 = input.flag();
    var _f647 = input.flag();
    var value = ast.VariableDecl();
    value.attributes = _f636;
    value.name = _f637;
    value.name_span = _f639;
    value.type_name = _f640;
    value.default_value = _f642;
    value.is_const = _f643;
    value.span = _f645;
    value.is_exported = _f646;
    value.is_private = _f647;
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
        var _f648 = _a_VariableDecl_read(input);
        return ast.Declaration.Variable(_f648);
    }
    if (tag == 1) {
        var _f649 = _a_FunctionDecl_read(input);
        return ast.Declaration.Function(_f649);
    }
    if (tag == 2) {
        var _f650 = _a_StructDecl_read(input);
        return ast.Declaration.Struct(_f650);
    }
    if (tag == 3) {
        var _f651 = _a_TraitDecl_read(input);
        return ast.Declaration.Trait(_f651);
    }
    if (tag == 4) {
        var _f652 = _a_ExtendDecl_read(input);
        return ast.Declaration.Extend(_f652);
    }
    if (tag == 5) {
        var _f653 = _a_TypeAliasDecl_read(input);
        return ast.Declaration.TypeAlias(_f653);
    }
    if (tag == 6) {
        var _f654 = _a_StaticBlock_read(input);
        return ast.Declaration.Static(_f654);
    }
    input.fail("Declaration", tag);
    return _a_Declaration_read(input);
}

_a_TypeAliasDecl_write(out: RecordOut, value: ast.TypeAliasDecl) {
    out.unsigned(value.attributes.count);
    for (var _item655 in value.attributes) {
        _a_Attribute_write(out, _item655);
    }
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item656 in value.generic_params) {
        _a_GenericParam_write(out, _item656);
    }
    _a_TypeName_write(out, value.target);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_TypeAliasDecl_read(input: RecordIn): ast.TypeAliasDecl {
    var _v657 = Array<ast.Attribute>();
    var _n658 = input.count();
    for (var _ in 0.._n658) {
        _v657.append(_a_Attribute_read(input));
    }
    var _f659 = _v657;
    var _f660 = input.text();
    var _s661 = input.unsigned();
    var _f662 = ast.Span(_s661, input.unsigned());
    var _v663 = Array<ast.GenericParam>();
    var _n664 = input.count();
    for (var _ in 0.._n664) {
        _v663.append(_a_GenericParam_read(input));
    }
    var _f665 = _v663;
    var _f666 = _a_TypeName_read(input);
    var _s667 = input.unsigned();
    var _f668 = ast.Span(_s667, input.unsigned());
    var _f669 = input.flag();
    var _f670 = input.flag();
    var value = ast.TypeAliasDecl();
    value.attributes = _f659;
    value.name = _f660;
    value.name_span = _f662;
    value.generic_params = _f665;
    value.target = _f666;
    value.span = _f668;
    value.is_exported = _f669;
    value.is_private = _f670;
    return value;
}

_a_GenericParam_write(out: RecordOut, value: ast.GenericParam) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.bounds.count);
    for (var _item671 in value.bounds) {
        _a_TypeName_write(out, _item671);
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
    var _f672 = input.text();
    var _s673 = input.unsigned();
    var _f674 = ast.Span(_s673, input.unsigned());
    var _v675 = Array<ast.TypeName>();
    var _n676 = input.count();
    for (var _ in 0.._n676) {
        _v675.append(_a_TypeName_read(input));
    }
    var _f677 = _v675;
    var _o678 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o678 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f679 = _o678;
    var _f680 = input.flag();
    var value = ast.GenericParam(_f672, _f674);
    value.name = _f672;
    value.name_span = _f674;
    value.bounds = _f677;
    value.default = _f679;
    value.is_argument = _f680;
    return value;
}

_a_ExtendDecl_write(out: RecordOut, value: ast.ExtendDecl) {
    out.unsigned(value.attributes.count);
    for (var _item681 in value.attributes) {
        _a_Attribute_write(out, _item681);
    }
    _a_TypeName_write(out, value.target);
    out.unsigned(value.target_bounds.count);
    for (var _item682 in value.target_bounds) {
        out.unsigned(_item682.count);
        for (var _item683 in _item682) {
            _a_TypeName_write(out, _item683);
        }
    }
    out.unsigned(value.traits.count);
    for (var _item684 in value.traits) {
        _a_TypeName_write(out, _item684);
    }
    out.unsigned(value.methods.count);
    for (var _item685 in value.methods) {
        _a_FunctionDecl_write(out, _item685);
    }
    out.unsigned(value.properties.count);
    for (var _item686 in value.properties) {
        _a_PropertyDecl_write(out, _item686);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_ExtendDecl_read(input: RecordIn): ast.ExtendDecl {
    var _v687 = Array<ast.Attribute>();
    var _n688 = input.count();
    for (var _ in 0.._n688) {
        _v687.append(_a_Attribute_read(input));
    }
    var _f689 = _v687;
    var _f690 = _a_TypeName_read(input);
    var _v691 = Array<Array<ast.TypeName>>();
    var _n692 = input.count();
    for (var _ in 0.._n692) {
        var _v693 = Array<ast.TypeName>();
        var _n694 = input.count();
        for (var _ in 0.._n694) {
            _v693.append(_a_TypeName_read(input));
        }
        _v691.append(_v693);
    }
    var _f695 = _v691;
    var _v696 = Array<ast.TypeName>();
    var _n697 = input.count();
    for (var _ in 0.._n697) {
        _v696.append(_a_TypeName_read(input));
    }
    var _f698 = _v696;
    var _v699 = Array<ast.FunctionDecl>();
    var _n700 = input.count();
    for (var _ in 0.._n700) {
        _v699.append(_a_FunctionDecl_read(input));
    }
    var _f701 = _v699;
    var _v702 = Array<ast.PropertyDecl>();
    var _n703 = input.count();
    for (var _ in 0.._n703) {
        _v702.append(_a_PropertyDecl_read(input));
    }
    var _f704 = _v702;
    var _s705 = input.unsigned();
    var _f706 = ast.Span(_s705, input.unsigned());
    var _f707 = input.flag();
    var _f708 = input.flag();
    var value = ast.ExtendDecl();
    value.attributes = _f689;
    value.target = _f690;
    value.target_bounds = _f695;
    value.traits = _f698;
    value.methods = _f701;
    value.properties = _f704;
    value.span = _f706;
    value.is_exported = _f707;
    value.is_private = _f708;
    return value;
}

_a_PropertyDecl_write(out: RecordOut, value: ast.PropertyDecl) {
    out.unsigned(value.attributes.count);
    for (var _item709 in value.attributes) {
        _a_Attribute_write(out, _item709);
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
    var _v710 = Array<ast.Attribute>();
    var _n711 = input.count();
    for (var _ in 0.._n711) {
        _v710.append(_a_Attribute_read(input));
    }
    var _f712 = _v710;
    var _f713 = input.text();
    var _s714 = input.unsigned();
    var _f715 = ast.Span(_s714, input.unsigned());
    var _f716 = _a_TypeName_read(input);
    var _o717 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o717 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f718 = _o717;
    var _o719 = Optional<ast.Accessor>.Empty;
    if (input.unsigned() == 1) {
        _o719 = Optional<ast.Accessor>.Value(_a_Accessor_read(input));
    }
    var _f720 = _o719;
    var _o721 = Optional<ast.Accessor>.Empty;
    if (input.unsigned() == 1) {
        _o721 = Optional<ast.Accessor>.Value(_a_Accessor_read(input));
    }
    var _f722 = _o721;
    var _s723 = input.unsigned();
    var _f724 = ast.Span(_s723, input.unsigned());
    var value = ast.PropertyDecl();
    value.attributes = _f712;
    value.name = _f713;
    value.name_span = _f715;
    value.type_name = _f716;
    value.default_value = _f718;
    value.getter = _f720;
    value.setter = _f722;
    value.span = _f724;
    return value;
}

_a_Accessor_write(out: RecordOut, value: ast.Accessor) {
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    _a_FunctionDecl_write(out, value.function);
}

_a_Accessor_read(input: RecordIn): ast.Accessor {
    var _s725 = input.unsigned();
    var _f726 = ast.Span(_s725, input.unsigned());
    var _f727 = _a_FunctionDecl_read(input);
    var value = ast.Accessor(_f726, _f727);
    value.span = _f726;
    value.function = _f727;
    return value;
}

_a_FunctionDecl_write(out: RecordOut, value: ast.FunctionDecl) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item728 in value.generic_params) {
        _a_GenericParam_write(out, _item728);
    }
    _a_TypeName_write(out, value.return_type);
    out.unsigned(value.parameters.count);
    for (var _item729 in value.parameters) {
        _a_VariableDecl_write(out, _item729);
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
    for (var _item730 in value.attributes) {
        _a_Attribute_write(out, _item730);
    }
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_FunctionDecl_read(input: RecordIn): ast.FunctionDecl {
    var _f731 = input.text();
    var _s732 = input.unsigned();
    var _f733 = ast.Span(_s732, input.unsigned());
    var _v734 = Array<ast.GenericParam>();
    var _n735 = input.count();
    for (var _ in 0.._n735) {
        _v734.append(_a_GenericParam_read(input));
    }
    var _f736 = _v734;
    var _f737 = _a_TypeName_read(input);
    var _v738 = Array<ast.VariableDecl>();
    var _n739 = input.count();
    for (var _ in 0.._n739) {
        _v738.append(_a_VariableDecl_read(input));
    }
    var _f740 = _v738;
    var _f741 = input.flag();
    var _o742 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o742 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f743 = _o742;
    var _f744 = input.flag();
    var _f745 = input.flag();
    var _f746 = input.flag();
    var _s747 = input.unsigned();
    var _f748 = ast.Span(_s747, input.unsigned());
    var _v749 = Array<ast.Attribute>();
    var _n750 = input.count();
    for (var _ in 0.._n750) {
        _v749.append(_a_Attribute_read(input));
    }
    var _f751 = _v749;
    var _f752 = input.flag();
    var _f753 = input.flag();
    var value = ast.FunctionDecl();
    value.name = _f731;
    value.name_span = _f733;
    value.generic_params = _f736;
    value.return_type = _f737;
    value.parameters = _f740;
    value.external = _f741;
    value.body = _f743;
    value.is_static = _f744;
    value.is_indexer = _f745;
    value.is_variadic = _f746;
    value.span = _f748;
    value.attributes = _f751;
    value.is_exported = _f752;
    value.is_private = _f753;
    return value;
}

_a_TraitDecl_write(out: RecordOut, value: ast.TraitDecl) {
    out.unsigned(value.attributes.count);
    for (var _item754 in value.attributes) {
        _a_Attribute_write(out, _item754);
    }
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item755 in value.generic_params) {
        _a_GenericParam_write(out, _item755);
    }
    out.unsigned(value.methods.count);
    for (var _item756 in value.methods) {
        _a_FunctionDecl_write(out, _item756);
    }
    out.unsigned(value.properties.count);
    for (var _item757 in value.properties) {
        _a_PropertyDecl_write(out, _item757);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_TraitDecl_read(input: RecordIn): ast.TraitDecl {
    var _v758 = Array<ast.Attribute>();
    var _n759 = input.count();
    for (var _ in 0.._n759) {
        _v758.append(_a_Attribute_read(input));
    }
    var _f760 = _v758;
    var _f761 = input.text();
    var _s762 = input.unsigned();
    var _f763 = ast.Span(_s762, input.unsigned());
    var _v764 = Array<ast.GenericParam>();
    var _n765 = input.count();
    for (var _ in 0.._n765) {
        _v764.append(_a_GenericParam_read(input));
    }
    var _f766 = _v764;
    var _v767 = Array<ast.FunctionDecl>();
    var _n768 = input.count();
    for (var _ in 0.._n768) {
        _v767.append(_a_FunctionDecl_read(input));
    }
    var _f769 = _v767;
    var _v770 = Array<ast.PropertyDecl>();
    var _n771 = input.count();
    for (var _ in 0.._n771) {
        _v770.append(_a_PropertyDecl_read(input));
    }
    var _f772 = _v770;
    var _s773 = input.unsigned();
    var _f774 = ast.Span(_s773, input.unsigned());
    var _f775 = input.flag();
    var _f776 = input.flag();
    var value = ast.TraitDecl();
    value.attributes = _f760;
    value.name = _f761;
    value.name_span = _f763;
    value.generic_params = _f766;
    value.methods = _f769;
    value.properties = _f772;
    value.span = _f774;
    value.is_exported = _f775;
    value.is_private = _f776;
    return value;
}

_a_StructDecl_write(out: RecordOut, value: ast.StructDecl) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item777 in value.generic_params) {
        _a_GenericParam_write(out, _item777);
    }
    out.unsigned(value.fields.count);
    for (var _item778 in value.fields) {
        _a_VariableDecl_write(out, _item778);
    }
    out.unsigned(value.properties.count);
    for (var _item779 in value.properties) {
        _a_PropertyDecl_write(out, _item779);
    }
    out.unsigned(value.methods.count);
    for (var _item780 in value.methods) {
        _a_FunctionDecl_write(out, _item780);
    }
    out.unsigned(value.constructors.count);
    for (var _item781 in value.constructors) {
        _a_FunctionDecl_write(out, _item781);
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
    for (var _item782 in value.attributes) {
        _a_Attribute_write(out, _item782);
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
    var _f783 = input.text();
    var _s784 = input.unsigned();
    var _f785 = ast.Span(_s784, input.unsigned());
    var _v786 = Array<ast.GenericParam>();
    var _n787 = input.count();
    for (var _ in 0.._n787) {
        _v786.append(_a_GenericParam_read(input));
    }
    var _f788 = _v786;
    var _v789 = Array<ast.VariableDecl>();
    var _n790 = input.count();
    for (var _ in 0.._n790) {
        _v789.append(_a_VariableDecl_read(input));
    }
    var _f791 = _v789;
    var _v792 = Array<ast.PropertyDecl>();
    var _n793 = input.count();
    for (var _ in 0.._n793) {
        _v792.append(_a_PropertyDecl_read(input));
    }
    var _f794 = _v792;
    var _v795 = Array<ast.FunctionDecl>();
    var _n796 = input.count();
    for (var _ in 0.._n796) {
        _v795.append(_a_FunctionDecl_read(input));
    }
    var _f797 = _v795;
    var _v798 = Array<ast.FunctionDecl>();
    var _n799 = input.count();
    for (var _ in 0.._n799) {
        _v798.append(_a_FunctionDecl_read(input));
    }
    var _f800 = _v798;
    var _o801 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o801 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f802 = _o801;
    var _o803 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s804 = input.unsigned();
        _o803 = Optional<ast.Span>.Value(ast.Span(_s804, input.unsigned()));
    }
    var _f805 = _o803;
    var _s806 = input.unsigned();
    var _f807 = ast.Span(_s806, input.unsigned());
    var _v808 = Array<ast.Attribute>();
    var _n809 = input.count();
    for (var _ in 0.._n809) {
        _v808.append(_a_Attribute_read(input));
    }
    var _f810 = _v808;
    var _f811 = input.flag();
    var _f812 = input.flag();
    var _o813 = Optional<ast.EnumBody>.Empty;
    if (input.unsigned() == 1) {
        _o813 = Optional<ast.EnumBody>.Value(_a_EnumBody_read(input));
    }
    var _f814 = _o813;
    var value = ast.StructDecl();
    value.name = _f783;
    value.name_span = _f785;
    value.generic_params = _f788;
    value.fields = _f791;
    value.properties = _f794;
    value.methods = _f797;
    value.constructors = _f800;
    value.destructor = _f802;
    value.destruct_span = _f805;
    value.span = _f807;
    value.attributes = _f810;
    value.is_exported = _f811;
    value.is_private = _f812;
    value.enumeration = _f814;
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
    for (var _item815 in value.cases) {
        _a_EnumCase_write(out, _item815);
    }
}

_a_EnumBody_read(input: RecordIn): ast.EnumBody {
    var _o816 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o816 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f817 = _o816;
    var _v818 = Array<ast.EnumCase>();
    var _n819 = input.count();
    for (var _ in 0.._n819) {
        _v818.append(_a_EnumCase_read(input));
    }
    var _f820 = _v818;
    var value = ast.EnumBody();
    value.representation = _f817;
    value.cases = _f820;
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
        for (var _item821 in value.payload.value()) {
            _a_VariableDecl_write(out, _item821);
        }
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.attributes.count);
    for (var _item822 in value.attributes) {
        _a_Attribute_write(out, _item822);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_EnumCase_read(input: RecordIn): ast.EnumCase {
    var _f823 = input.text();
    var _s824 = input.unsigned();
    var _f825 = ast.Span(_s824, input.unsigned());
    var _o826 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o826 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f827 = _o826;
    var _o828 = Optional<Array<ast.VariableDecl>>.Empty;
    if (input.unsigned() == 1) {
        var _v829 = Array<ast.VariableDecl>();
        var _n830 = input.count();
        for (var _ in 0.._n830) {
            _v829.append(_a_VariableDecl_read(input));
        }
        _o828 = Optional<Array<ast.VariableDecl>>.Value(_v829);
    }
    var _f831 = _o828;
    var _v832 = Array<ast.Attribute>();
    var _n833 = input.count();
    for (var _ in 0.._n833) {
        _v832.append(_a_Attribute_read(input));
    }
    var _f834 = _v832;
    var _s835 = input.unsigned();
    var _f836 = ast.Span(_s835, input.unsigned());
    var value = ast.EnumCase();
    value.name = _f823;
    value.name_span = _f825;
    value.value = _f827;
    value.payload = _f831;
    value.attributes = _f834;
    value.span = _f836;
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
        var _f837 = input.text();
        return ast.Literal.String(_f837);
    }
    if (tag == 1) {
        var _f838 = input.signed();
        return ast.Literal.Integer(_f838);
    }
    if (tag == 2) {
        var _f839 = input.number();
        return ast.Literal.Float(_f839);
    }
    if (tag == 3) {
        var _f840 = input.flag();
        return ast.Literal.Bool(_f840);
    }
    if (tag == 4) {
        var _f841 = input.unsigned() as u8;
        return ast.Literal.Char(_f841);
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
    for (var _item842 in value.items) {
        _m_Statement_write(out, _item842);
    }
    out.unsigned(value.attributes.count);
    for (var _item843 in value.attributes) {
        _a_Attribute_write(out, _item843);
    }
}

_m_Block_read(input: RecordIn): Block {
    var _f844 = input.text();
    var _v845 = Array<Statement>();
    var _n846 = input.count();
    for (var _ in 0.._n846) {
        _v845.append(_m_Statement_read(input));
    }
    var _f847 = _v845;
    var _v848 = Array<ast.Attribute>();
    var _n849 = input.count();
    for (var _ in 0.._n849) {
        _v848.append(_a_Attribute_read(input));
    }
    var _f850 = _v848;
    return Block(_f844, _f847, _f850);
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
        var _f1263 = _m_Expression_read(input);
        return Statement.Expression(_f1263);
    }
    if (tag == 1) {
        var _f1264 = _m_Block_read(input);
        return Statement.Block(_f1264);
    }
    if (tag == 2) {
        var _f1265 = _m_Declaration_read(input);
        return Statement.Declaration(_f1265);
    }
    if (tag == 3) {
        var _f1266 = _m_Branch_read(input);
        return Statement.Branch(_f1266);
    }
    if (tag == 4) {
        var _f1267 = _m_While_read(input);
        return Statement.While(_f1267);
    }
    if (tag == 5) {
        var _f1268 = _m_ReturnStatement_read(input);
        return Statement.Return(_f1268);
    }
    if (tag == 6) {
        var _f1269 = _m_LoopBreak_read(input);
        return Statement.LoopBreak(_f1269);
    }
    if (tag == 7) {
        var _f1270 = _m_StaticBlock_read(input);
        return Statement.Static(_f1270);
    }
    if (tag == 8) {
        var _f1271 = _m_StaticPass_read(input);
        return Statement.StaticPass(_f1271);
    }
    input.fail("Statement", tag);
    return _m_Statement_read(input);
}

_m_StaticPass_write(out: RecordOut, value: StaticPass) {
    out.loc(value.loc);
    out.flag(value.stop);
    out.unsigned(value.values.count);
    for (var _item851 in value.values) {
        var (_t852, _t853) = _item851;
        out.text(_t852);
        _m_StaticConstant_write(out, _t853);
    }
    if (value.header.is_value()) {
        out.unsigned(1);
        out.unsigned(value.header.value() as ulong);
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.lines.count);
    for (var _item854 in value.lines) {
        var (_t855, _t856) = _item854;
        out.loc(_t855);
        out.unsigned(_t856 as ulong);
    }
}

_m_StaticPass_read(input: RecordIn): StaticPass {
    var _f857 = input.loc();
    var _f858 = input.flag();
    var _v859 = Array<(String, StaticConstant)>();
    var _n860 = input.count();
    for (var _ in 0.._n860) {
        var _t861 = input.text();
        var _t862 = _m_StaticConstant_read(input);
        _v859.append((_t861, _t862));
    }
    var _f863 = _v859;
    var _o864 = Optional<uint>.Empty;
    if (input.unsigned() == 1) {
        _o864 = Optional<uint>.Value(input.unsigned() as uint);
    }
    var _f865 = _o864;
    var _v866 = Array<(Loc, uint)>();
    var _n867 = input.count();
    for (var _ in 0.._n867) {
        var _t868 = input.loc();
        var _t869 = input.unsigned() as uint;
        _v866.append((_t868, _t869));
    }
    var _f870 = _v866;
    return StaticPass(_f857, _f858, _f863, _f865, _f870);
}

_m_RecordStaticConstant_write(out: RecordOut, value: RecordStaticConstant) {
    out.text(value.name);
    out.unsigned(value.fields.count);
    for (var _item1276 in value.fields) {
        var (_t1277, _t1278) = _item1276;
        out.text(_t1277);
        _m_StaticConstant_write(out, _t1278);
    }
}

_m_RecordStaticConstant_read(input: RecordIn): RecordStaticConstant {
    var _f1279 = input.text();
    var _v1280 = Array<(String, StaticConstant)>();
    var _n1281 = input.count();
    for (var _ in 0.._n1281) {
        var _t1282 = input.text();
        var _t1283 = _m_StaticConstant_read(input);
        _v1280.append((_t1282, _t1283));
    }
    var _f1284 = _v1280;
    return RecordStaticConstant(_f1279, _f1284);
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
        var _f1272 = input.signed();
        return StaticConstant.Int(_f1272);
    }
    if (tag == 1) {
        var _f1273 = input.number();
        return StaticConstant.Float(_f1273);
    }
    if (tag == 2) {
        var _f1274 = input.flag();
        return StaticConstant.Bool(_f1274);
    }
    if (tag == 3) {
        var _f1275 = input.text();
        return StaticConstant.String(_f1275);
    }
    if (tag == 4) {
        return StaticConstant.Record(_m_RecordStaticConstant_read(input));
    }
    input.fail("StaticConstant", tag);
    return _m_StaticConstant_read(input);
}

_m_StaticBlock_write(out: RecordOut, value: StaticBlock) {
    out.unsigned(value.captures.count);
    for (var _item871 in value.captures) {
        out.text(_item871);
    }
    out.unsigned(value.items.count);
    for (var _item872 in value.items) {
        _m_StaticItem_write(out, _item872);
    }
    out.unsigned(value.type_map.count);
    for (var _item873 in value.type_map) {
        var (_t874, _t875) = _item873;
        out.text(_t874);
        _m_TypeName_write(out, _t875);
    }
    out.loc(value.loc);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_StaticBlock_read(input: RecordIn): StaticBlock {
    var _v876 = Array<String>();
    var _n877 = input.count();
    for (var _ in 0.._n877) {
        _v876.append(input.text());
    }
    var _f878 = _v876;
    var _v879 = Array<StaticItem>();
    var _n880 = input.count();
    for (var _ in 0.._n880) {
        _v879.append(_m_StaticItem_read(input));
    }
    var _f881 = _v879;
    var _v882 = Array<(String, TypeName)>();
    var _n883 = input.count();
    for (var _ in 0.._n883) {
        var _t884 = input.text();
        var _t885 = _m_TypeName_read(input);
        _v882.append((_t884, _t885));
    }
    var _f886 = _v882;
    var _f887 = input.loc();
    var _s888 = input.unsigned();
    var _f889 = ast.Span(_s888, input.unsigned());
    return StaticBlock(_f878, _f881, _f886, _f887, _f889);
}

_m_TypeName_write(out: RecordOut, value: TypeName) {
    out.text(value.name);
    out.unsigned(value.sub_types.count);
    for (var _item890 in value.sub_types) {
        _m_TypeName_write(out, _item890);
    }
    _m_TypeFlags_write(out, value.flags);
    out.unsigned(value.labels.count);
    for (var _item891 in value.labels) {
        out.text(_item891);
    }
}

_m_TypeName_read(input: RecordIn): TypeName {
    var _f892 = input.text();
    var _v893 = Array<TypeName>();
    var _n894 = input.count();
    for (var _ in 0.._n894) {
        _v893.append(_m_TypeName_read(input));
    }
    var _f895 = _v893;
    var _f896 = _m_TypeFlags_read(input);
    var _v897 = Array<String>();
    var _n898 = input.count();
    for (var _ in 0.._n898) {
        _v897.append(input.text());
    }
    var _f899 = _v897;
    return TypeName(_f892, _f895, _f896, _f899);
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
    for (var _item1285 in value.body) {
        _m_StaticItem_write(out, _item1285);
    }
    out.loc(value.loc);
}

_m_ForStaticItem_read(input: RecordIn): ForStaticItem {
    var _f1286 = input.text();
    var _f1287 = _a_Expression_read(input);
    var _v1288 = Array<StaticItem>();
    var _n1289 = input.count();
    for (var _ in 0.._n1289) {
        _v1288.append(_m_StaticItem_read(input));
    }
    var _f1290 = _v1288;
    var _f1291 = input.loc();
    return ForStaticItem(_f1287, _f1286, _f1290, _f1291);
}

_m_WhileStaticItem_write(out: RecordOut, value: WhileStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.body.count);
    for (var _item1292 in value.body) {
        _m_StaticItem_write(out, _item1292);
    }
    out.loc(value.loc);
}

_m_WhileStaticItem_read(input: RecordIn): WhileStaticItem {
    var _f1293 = _a_Expression_read(input);
    var _v1294 = Array<StaticItem>();
    var _n1295 = input.count();
    for (var _ in 0.._n1295) {
        _v1294.append(_m_StaticItem_read(input));
    }
    var _f1296 = _v1294;
    var _f1297 = input.loc();
    return WhileStaticItem(_f1293, _f1296, _f1297);
}

_m_JumpStaticItem_write(out: RecordOut, value: JumpStaticItem) {
    _m_LoopBreakKind_write(out, value.kind);
    out.loc(value.loc);
}

_m_JumpStaticItem_read(input: RecordIn): JumpStaticItem {
    var _f1298 = _m_LoopBreakKind_read(input);
    var _f1299 = input.loc();
    return JumpStaticItem(_f1298, _f1299);
}

_m_IfStaticItem_write(out: RecordOut, value: IfStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1300 in value.then_items) {
        _m_StaticItem_write(out, _item1300);
    }
    out.unsigned(value.else_items.count);
    for (var _item1301 in value.else_items) {
        _m_StaticItem_write(out, _item1301);
    }
    out.loc(value.loc);
}

_m_IfStaticItem_read(input: RecordIn): IfStaticItem {
    var _f1302 = _a_Expression_read(input);
    var _v1303 = Array<StaticItem>();
    var _n1304 = input.count();
    for (var _ in 0.._n1304) {
        _v1303.append(_m_StaticItem_read(input));
    }
    var _f1305 = _v1303;
    var _v1306 = Array<StaticItem>();
    var _n1307 = input.count();
    for (var _ in 0.._n1307) {
        _v1306.append(_m_StaticItem_read(input));
    }
    var _f1308 = _v1306;
    var _f1309 = input.loc();
    return IfStaticItem(_f1302, _f1305, _f1308, _f1309);
}

_m_EmitIfStaticItem_write(out: RecordOut, value: EmitIfStaticItem) {
    _m_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1310 in value.then_items) {
        _m_StaticItem_write(out, _item1310);
    }
    out.unsigned(value.else_items.count);
    for (var _item1311 in value.else_items) {
        _m_StaticItem_write(out, _item1311);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_EmitIfStaticItem_read(input: RecordIn): EmitIfStaticItem {
    var _f1312 = _m_Expression_read(input);
    var _v1313 = Array<StaticItem>();
    var _n1314 = input.count();
    for (var _ in 0.._n1314) {
        _v1313.append(_m_StaticItem_read(input));
    }
    var _f1315 = _v1313;
    var _v1316 = Array<StaticItem>();
    var _n1317 = input.count();
    for (var _ in 0.._n1317) {
        _v1316.append(_m_StaticItem_read(input));
    }
    var _f1318 = _v1316;
    var _s1319 = input.unsigned();
    var _f1320 = ast.Span(_s1319, input.unsigned());
    return EmitIfStaticItem(_f1312, _f1315, _f1318, _f1320);
}

_m_VarStaticItem_write(out: RecordOut, value: VarStaticItem) {
    out.text(value.name);
    _a_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_VarStaticItem_read(input: RecordIn): VarStaticItem {
    var _f1325 = input.text();
    var _f1326 = _a_Expression_read(input);
    var _f1327 = input.loc();
    return VarStaticItem(_f1326, _f1325, _f1327);
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
            for (var _item1321 in v) {
                _m_StaticItem_write(out, _item1321);
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
        var _v1322 = Array<StaticItem>();
        var _n1323 = input.count();
        for (var _ in 0.._n1323) {
            _v1322.append(_m_StaticItem_read(input));
        }
        var _f1324 = _v1322;
        return StaticItem.Block(_f1324);
    }
    if (tag == 6) {
        return StaticItem.Var(_m_VarStaticItem_read(input));
    }
    if (tag == 7) {
        var _f1328 = _a_Expression_read(input);
        return StaticItem.Evaluate(_f1328);
    }
    if (tag == 8) {
        var _f1329 = _m_Statement_read(input);
        var _s1330 = input.unsigned();
        var _f1331 = ast.Span(_s1330, input.unsigned());
        return StaticItem.Emit(_f1329, _f1331);
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
    var _f1332 = input.text();
    var _f1333 = _m_TypeName_read(input);
    var _f1334 = input.loc();
    return SymbolRefExpression(_f1332, _f1333, _f1334);
}

_m_MemberRefExpression_write(out: RecordOut, value: MemberRefExpression) {
    _m_Expression_write(out, value.lhs);
    out.text(value.name);
    out.loc(value.loc);
}

_m_MemberRefExpression_read(input: RecordIn): MemberRefExpression {
    var _f1335 = _m_Expression_read(input);
    var _f1336 = input.text();
    var _f1337 = input.loc();
    return MemberRefExpression(_f1335, _f1336, _f1337);
}

_m_StringLiteralExpression_write(out: RecordOut, value: StringLiteralExpression) {
    out.text(value.value);
    out.flag(value.is_raw);
    out.loc(value.loc);
}

_m_StringLiteralExpression_read(input: RecordIn): StringLiteralExpression {
    var _f1341 = input.text();
    var _f1342 = input.flag();
    var _f1343 = input.loc();
    return StringLiteralExpression(_f1341, _f1342, _f1343);
}

_m_BinaryExpression_write(out: RecordOut, value: BinaryExpression) {
    _m_BinaryOp_write(out, value.op);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_BinaryExpression_read(input: RecordIn): BinaryExpression {
    var _f1344 = _m_BinaryOp_read(input);
    var _f1345 = _m_Expression_read(input);
    var _f1346 = _m_Expression_read(input);
    var _f1347 = input.loc();
    return BinaryExpression(_f1345, _f1346, _f1344, _f1347);
}

_m_UnaryExpression_write(out: RecordOut, value: UnaryExpression) {
    _m_UnaryOp_write(out, value.op);
    _m_Expression_write(out, value.operand);
    out.loc(value.loc);
}

_m_UnaryExpression_read(input: RecordIn): UnaryExpression {
    var _f1348 = _m_UnaryOp_read(input);
    var _f1349 = _m_Expression_read(input);
    var _f1350 = input.loc();
    return UnaryExpression(_f1349, _f1348, _f1350);
}

_m_CastExpression_write(out: RecordOut, value: CastExpression) {
    _m_Expression_write(out, value.expr);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
    _m_CastKind_write(out, value.kind);
}

_m_CastExpression_read(input: RecordIn): CastExpression {
    var _f1351 = _m_Expression_read(input);
    var _f1352 = _m_TypeName_read(input);
    var _f1353 = input.loc();
    var _f1354 = _m_CastKind_read(input);
    return CastExpression(_f1351, _f1352, _f1353, _f1354);
}

_m_TernaryExpression_write(out: RecordOut, value: TernaryExpression) {
    _m_Expression_write(out, value.condition);
    _m_Expression_write(out, value.true_expr);
    _m_Expression_write(out, value.false_expr);
}

_m_TernaryExpression_read(input: RecordIn): TernaryExpression {
    var _f1355 = _m_Expression_read(input);
    var _f1356 = _m_Expression_read(input);
    var _f1357 = _m_Expression_read(input);
    return TernaryExpression(_f1355, _f1356, _f1357);
}

_m_IndexExpression_write(out: RecordOut, value: IndexExpression) {
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_IndexExpression_read(input: RecordIn): IndexExpression {
    var _f1358 = _m_Expression_read(input);
    var _f1359 = _m_Expression_read(input);
    var _f1360 = input.loc();
    return IndexExpression(_f1358, _f1359, _f1360);
}

_m_ArrayIndexExpression_write(out: RecordOut, value: ArrayIndexExpression) {
    _m_TypeName_write(out, value.ty);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_ArrayIndexExpression_read(input: RecordIn): ArrayIndexExpression {
    var _f1361 = _m_TypeName_read(input);
    var _f1362 = _m_Expression_read(input);
    var _f1363 = _m_Expression_read(input);
    var _f1364 = input.loc();
    return ArrayIndexExpression(_f1362, _f1363, _f1361, _f1364);
}

_m_SimdExpression_write(out: RecordOut, value: SimdExpression) {
    _m_SimdOp_write(out, value.op);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1388 in value.args) {
        _m_Expression_write(out, _item1388);
    }
    out.loc(value.loc);
}

_m_SimdExpression_read(input: RecordIn): SimdExpression {
    var _f1389 = _m_SimdOp_read(input);
    var _f1390 = _m_TypeName_read(input);
    var _v1391 = Array<Expression>();
    var _n1392 = input.count();
    for (var _ in 0.._n1392) {
        _v1391.append(_m_Expression_read(input));
    }
    var _f1393 = _v1391;
    var _f1394 = input.loc();
    return SimdExpression(_f1389, _f1390, _f1393, _f1394);
}

_m_CountStepExpression_write(out: RecordOut, value: CountStepExpression) {
    _m_CountField_write(out, value.field);
    out.flag(value.increment);
    out.flag(value.atomic);
}

_m_CountStepExpression_read(input: RecordIn): CountStepExpression {
    var _f1398 = _m_CountField_read(input);
    var _f1399 = input.flag();
    var _f1400 = input.flag();
    return CountStepExpression(_f1398, _f1399, _f1400);
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
    var _o1401 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1401 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1402 = _o1401;
    var _f1403 = input.text();
    var _f1404 = input.loc();
    return FunctionPointerExpression(_f1402, _f1403, _f1404);
}

_m_FunctionCallExpression_write(out: RecordOut, value: FunctionCallExpression) {
    out.text(value.function);
    out.unsigned(value.args.count);
    for (var _item1405 in value.args) {
        _m_Expression_write(out, _item1405);
    }
    out.loc(value.loc);
}

_m_FunctionCallExpression_read(input: RecordIn): FunctionCallExpression {
    var _f1406 = input.text();
    var _v1407 = Array<Expression>();
    var _n1408 = input.count();
    for (var _ in 0.._n1408) {
        _v1407.append(_m_Expression_read(input));
    }
    var _f1409 = _v1407;
    var _f1410 = input.loc();
    return FunctionCallExpression(_f1406, _f1409, _f1410);
}

_m_NamedArgumentExpression_write(out: RecordOut, value: NamedArgumentExpression) {
    out.text(value.name);
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_NamedArgumentExpression_read(input: RecordIn): NamedArgumentExpression {
    var _f1411 = input.text();
    var _f1412 = _m_Expression_read(input);
    var _f1413 = input.loc();
    return NamedArgumentExpression(_f1412, _f1411, _f1413);
}

_m_DefaultArgumentExpression_write(out: RecordOut, value: DefaultArgumentExpression) {
    _m_TypeName_write(out, value.ty);
}

_m_DefaultArgumentExpression_read(input: RecordIn): DefaultArgumentExpression {
    var _f1414 = _m_TypeName_read(input);
    return DefaultArgumentExpression(_f1414);
}

_m_MethodCallExpression_write(out: RecordOut, value: MethodCallExpression) {
    _m_Expression_write(out, value.this_value);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item1415 in value.args) {
        _m_Expression_write(out, _item1415);
    }
    out.loc(value.loc);
}

_m_MethodCallExpression_read(input: RecordIn): MethodCallExpression {
    var _f1416 = _m_Expression_read(input);
    var _f1417 = input.text();
    var _v1418 = Array<Expression>();
    var _n1419 = input.count();
    for (var _ in 0.._n1419) {
        _v1418.append(_m_Expression_read(input));
    }
    var _f1420 = _v1418;
    var _f1421 = input.loc();
    return MethodCallExpression(_f1416, _f1417, _f1420, _f1421);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1422 = input.text();
    var _f1423 = _m_TypeName_read(input);
    var _f1424 = input.loc();
    return FunctionRefExpression(_f1422, _f1423, _f1424);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1425 in value.args) {
        _m_Expression_write(out, _item1425);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1426 = _m_Expression_read(input);
    var _v1427 = Array<Expression>();
    var _n1428 = input.count();
    for (var _ in 0.._n1428) {
        _v1427.append(_m_Expression_read(input));
    }
    var _f1429 = _v1427;
    return InvokeExpression(_f1426, _f1429);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1431 = _m_Expression_read(input);
    var _f1432 = input.text();
    var _f1433 = _m_TypeName_read(input);
    var _f1434 = input.loc();
    return MakeClosureExpression(_f1431, _f1432, _f1433, _f1434);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1436 in value.args) {
        _m_Expression_write(out, _item1436);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1437 = _m_Expression_read(input);
    var _v1438 = Array<Expression>();
    var _n1439 = input.count();
    for (var _ in 0.._n1439) {
        _v1438.append(_m_Expression_read(input));
    }
    var _f1440 = _v1438;
    return CallPointerExpression(_f1437, _f1440);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1443 = _m_Expression_read(input);
    var _f1444 = input.loc();
    return MoveExpression(_f1443, _f1444);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1445 = _m_Expression_read(input);
    var _f1446 = input.unsigned();
    var _f1447 = input.loc();
    return DestructureExpression(_f1445, _f1446, _f1447);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1450 = _m_TypeName_read(input);
    var _f1451 = input.signed();
    return StaticCaseExpression(_f1450, _f1451);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1452 = input.text();
    var _f1453 = input.loc();
    return StaticStringExpression(_f1452, _f1453);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1455 = input.unsigned();
    var _f1456 = _m_TypeName_read(input);
    var _f1457 = input.loc();
    return SubjectExpression(_f1455, _f1456, _f1457);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1458 = _m_Expression_read(input);
    var _f1459 = _m_TypeName_read(input);
    var _f1460 = _m_TypeName_read(input);
    var _f1461 = input.loc();
    return ToTraitExpression(_f1458, _f1459, _f1460, _f1461);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1462 in value.candidates) {
        _m_TypeName_write(out, _item1462);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1463 = _m_Expression_read(input);
    var _f1464 = _m_TypeName_read(input);
    var _f1465 = _m_TypeName_read(input);
    var _v1466 = Array<TypeName>();
    var _n1467 = input.count();
    for (var _ in 0.._n1467) {
        _v1466.append(_m_TypeName_read(input));
    }
    var _f1468 = _v1466;
    var _f1469 = input.flag();
    var _f1470 = input.loc();
    return FromTraitExpression(_f1463, _f1464, _f1465, _f1468, _f1469, _f1470);
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
        var _f1338 = input.flag();
        return Expression.BoolLiteral(_f1338);
    }
    if (tag == 4) {
        var _f1339 = input.signed();
        return Expression.IntLiteral(_f1339);
    }
    if (tag == 5) {
        var _f1340 = input.number();
        return Expression.FloatLiteral(_f1340);
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
        var _f1365 = _m_TypeName_read(input);
        return Expression.SizeOf(_f1365);
    }
    if (tag == 15) {
        var _f1366 = _m_TypeName_read(input);
        return Expression.IsPod(_f1366);
    }
    if (tag == 16) {
        var _f1367 = _m_TypeName_read(input);
        return Expression.Default(_f1367);
    }
    if (tag == 17) {
        var _f1368 = _m_TypeName_read(input);
        return Expression.Allocate(_f1368);
    }
    if (tag == 18) {
        var _f1369 = _m_TypeName_read(input);
        var _f1370 = _m_Expression_read(input);
        return Expression.RefCount(_f1369, _f1370);
    }
    if (tag == 19) {
        var _f1371 = _m_TypeName_read(input);
        var _f1372 = _m_Expression_read(input);
        return Expression.Address(_f1371, _f1372);
    }
    if (tag == 20) {
        var _f1373 = _m_TypeName_read(input);
        var _f1374 = _m_Expression_read(input);
        return Expression.AtomicLoad(_f1373, _f1374);
    }
    if (tag == 21) {
        var _f1375 = _m_TypeName_read(input);
        var _f1376 = _m_Expression_read(input);
        var _f1377 = _m_Expression_read(input);
        return Expression.AtomicStore(_f1375, _f1376, _f1377);
    }
    if (tag == 22) {
        var _f1378 = _m_Expression_read(input);
        var _f1379 = _m_Expression_read(input);
        return Expression.ConstructAt(_f1378, _f1379);
    }
    if (tag == 23) {
        var _f1380 = _m_TypeName_read(input);
        var _f1381 = _m_Expression_read(input);
        var _f1382 = _m_Expression_read(input);
        var _f1383 = _m_Expression_read(input);
        return Expression.AtomicCmpXchg(_f1380, _f1381, _f1382, _f1383);
    }
    if (tag == 24) {
        var _f1384 = _m_AtomicFetchOp_read(input);
        var _f1385 = _m_TypeName_read(input);
        var _f1386 = _m_Expression_read(input);
        var _f1387 = _m_Expression_read(input);
        return Expression.AtomicFetch(_f1384, _f1385, _f1386, _f1387);
    }
    if (tag == 25) {
        return Expression.Simd(_m_SimdExpression_read(input));
    }
    if (tag == 26) {
        var _f1395 = _m_WeakOp_read(input);
        var _f1396 = _m_TypeName_read(input);
        var _f1397 = _m_Expression_read(input);
        return Expression.Weak(_f1395, _f1396, _f1397);
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
        var _f1430 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1430);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1435 = input.text();
        return Expression.MethodAddress(_f1435);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1441 = _m_Expression_read(input);
        return Expression.ForIterator(_f1441);
    }
    if (tag == 40) {
        var _f1442 = _m_Expression_read(input);
        return Expression.WithEntered(_f1442);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1448 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1448);
    }
    if (tag == 44) {
        var _f1449 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1449);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1454 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1454);
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
        var _f1471 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1471);
    }
    if (tag == 53) {
        var _f1472 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1472);
    }
    input.fail("Expression", tag);
    return _m_Expression_read(input);
}

_m_StaticMember_write(out: RecordOut, value: StaticMember) {
    _a_Expression_write(out, value.member);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item900 in value.args) {
        _m_Expression_write(out, _item900);
    }
    out.loc(value.loc);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.argument_spans.count);
    for (var _item901 in value.argument_spans) {
        out.unsigned(out.blank_locs ? 0 : _item901.start);
        out.unsigned(out.blank_locs ? 0 : _item901.end);
    }
}

_m_StaticMember_read(input: RecordIn): StaticMember {
    var _f902 = _a_Expression_read(input);
    var _f903 = input.text();
    var _v904 = Array<Expression>();
    var _n905 = input.count();
    for (var _ in 0.._n905) {
        _v904.append(_m_Expression_read(input));
    }
    var _f906 = _v904;
    var _f907 = input.loc();
    var _s908 = input.unsigned();
    var _f909 = ast.Span(_s908, input.unsigned());
    var _v910 = Array<ast.Span>();
    var _n911 = input.count();
    for (var _ in 0.._n911) {
        var _s912 = input.unsigned();
        _v910.append(ast.Span(_s912, input.unsigned()));
    }
    var _f913 = _v910;
    return StaticMember(_f902, _f903, _f906, _f907, _f909, _f913);
}

_m_StaticValue_write(out: RecordOut, value: StaticValue) {
    _a_Expression_write(out, value.expr);
    out.loc(value.loc);
}

_m_StaticValue_read(input: RecordIn): StaticValue {
    var _f914 = _a_Expression_read(input);
    var _f915 = input.loc();
    return StaticValue(_f914, _f915);
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
    var _f916 = input.unsigned();
    var _f917 = _m_Expression_read(input);
    var _f918 = _m_Expression_read(input);
    var _o919 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o919 = Optional<String>.Value(input.text());
    }
    var _f920 = _o919;
    var _f921 = input.loc();
    return WithSubject(_f917, _f918, _f916, _f920, _f921);
}

_m_CaseValue_write(out: RecordOut, value: CaseValue) {
    _m_Expression_write(out, value.subject);
    out.text(value.name);
    out.unsigned(value.choices.count);
    for (var _item922 in value.choices) {
        _m_CaseChoice_write(out, _item922);
    }
    out.loc(value.loc);
}

_m_CaseValue_read(input: RecordIn): CaseValue {
    var _f923 = _m_Expression_read(input);
    var _f924 = input.text();
    var _v925 = Array<CaseChoice>();
    var _n926 = input.count();
    for (var _ in 0.._n926) {
        _v925.append(_m_CaseChoice_read(input));
    }
    var _f927 = _v925;
    var _f928 = input.loc();
    return CaseValue(_f923, _f924, _f927, _f928);
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
    for (var _item929 in value.bindings) {
        out.loc(_item929);
    }
    out.loc(value.loc);
}

_m_CaseChoice_read(input: RecordIn): CaseChoice {
    var _f930 = input.text();
    var _f931 = input.loc();
    var _o932 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o932 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f933 = _o932;
    var _f934 = input.unsigned();
    var _v935 = Array<Loc>();
    var _n936 = input.count();
    for (var _ in 0.._n936) {
        _v935.append(input.loc());
    }
    var _f937 = _v935;
    var _f938 = input.loc();
    return CaseChoice(_f930, _f931, _f933, _f934, _f937, _f938);
}

_m_MatchArmTest_write(out: RecordOut, value: MatchArmTest) {
    _m_Expression_write(out, value.subject);
    out.unsigned(value.patterns.count);
    for (var _item939 in value.patterns) {
        _m_CasePattern_write(out, _item939);
    }
    _m_MatchSite_write(out, value.site);
    out.unsigned(value.element_names.count);
    for (var _item940 in value.element_names) {
        _m_ElementName_write(out, _item940);
    }
    out.flag(value.guarded);
}

_m_MatchArmTest_read(input: RecordIn): MatchArmTest {
    var _f941 = _m_Expression_read(input);
    var _v942 = Array<CasePattern>();
    var _n943 = input.count();
    for (var _ in 0.._n943) {
        _v942.append(_m_CasePattern_read(input));
    }
    var _f944 = _v942;
    var _f945 = _m_MatchSite_read(input);
    var _v946 = Array<ElementName>();
    var _n947 = input.count();
    for (var _ in 0.._n947) {
        _v946.append(_m_ElementName_read(input));
    }
    var _f948 = _v946;
    var _f949 = input.flag();
    return MatchArmTest(_f941, _f944, _f945, _f948, _f949);
}

_m_ElementName_write(out: RecordOut, value: ElementName) {
    out.text(value.name);
    out.loc(value.loc);
    out.flag(value.declared);
    if (value.missing.is_value()) {
        out.unsigned(1);
        var (_t950, _t951) = value.missing.value();
        out.text(_t950);
        out.loc(_t951);
    } else {
        out.unsigned(0);
    }
}

_m_ElementName_read(input: RecordIn): ElementName {
    var _f952 = input.text();
    var _f953 = input.loc();
    var _f954 = input.flag();
    var _o955 = Optional<(String, Loc)>.Empty;
    if (input.unsigned() == 1) {
        var _t956 = input.text();
        var _t957 = input.loc();
        _o955 = Optional<(String, Loc)>.Value((_t956, _t957));
    }
    var _f958 = _o955;
    return ElementName(_f952, _f953, _f954, _f958);
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
    var _f959 = input.unsigned();
    var _f960 = input.loc();
    var _o961 = Optional<Loc>.Empty;
    if (input.unsigned() == 1) {
        _o961 = Optional<Loc>.Value(input.loc());
    }
    var _f962 = _o961;
    var _f963 = input.flag();
    var _f964 = input.flag();
    return MatchSite(_f959, _f960, _f962, _f963, _f964);
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
        for (var _item965 in value.bindings.value()) {
            _m_CasePattern_write(out, _item965);
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
        for (var _item966 in value.elements.value()) {
            _m_CasePattern_write(out, _item966);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.range);
    out.flag(value.constant);
    if (value.values.is_value()) {
        out.unsigned(1);
        var (_t967, _t968) = value.values.value();
        out.signed(_t967 as long);
        out.signed(_t968 as long);
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
    var _o969 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o969 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f970 = _o969;
    var _f971 = input.text();
    var _f972 = input.loc();
    var _o973 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v974 = Array<CasePattern>();
        var _n975 = input.count();
        for (var _ in 0.._n975) {
            _v974.append(_m_CasePattern_read(input));
        }
        _o973 = Optional<Array<CasePattern>>.Value(_v974);
    }
    var _f976 = _o973;
    var _o977 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o977 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f978 = _o977;
    var _o979 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v980 = Array<CasePattern>();
        var _n981 = input.count();
        for (var _ in 0.._n981) {
            _v980.append(_m_CasePattern_read(input));
        }
        _o979 = Optional<Array<CasePattern>>.Value(_v980);
    }
    var _f982 = _o979;
    var _f983 = input.flag();
    var _f984 = input.flag();
    var _o985 = Optional<(long, long)>.Empty;
    if (input.unsigned() == 1) {
        var _t986 = input.signed();
        var _t987 = input.signed();
        _o985 = Optional<(long, long)>.Value((_t986, _t987));
    }
    var _f988 = _o985;
    var _o989 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o989 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f990 = _o989;
    return CasePattern(_f970, _f971, _f972, _f976, _f978, _f982, _f983, _f984, _f988, _f990);
}

_m_ClosureLiteral_write(out: RecordOut, value: ClosureLiteral) {
    out.unsigned(value.parameters.count);
    for (var _item991 in value.parameters) {
        _m_VariableDef_write(out, _item991);
    }
    _m_TypeName_write(out, value.ty);
    _m_Block_write(out, value.body);
    out.flag(value.expression_body);
    out.loc(value.loc);
}

_m_ClosureLiteral_read(input: RecordIn): ClosureLiteral {
    var _v992 = Array<VariableDef>();
    var _n993 = input.count();
    for (var _ in 0.._n993) {
        _v992.append(_m_VariableDef_read(input));
    }
    var _f994 = _v992;
    var _f995 = _m_TypeName_read(input);
    var _f996 = _m_Block_read(input);
    var _f997 = input.flag();
    var _f998 = input.loc();
    return ClosureLiteral(_f994, _f995, _f996, _f997, _f998);
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
    for (var _item999 in value.attributes) {
        _a_Attribute_write(out, _item999);
    }
    out.loc(value.loc);
    out.loc(value.type_loc);
    out.flag(value.is_const);
}

_m_VariableDef_read(input: RecordIn): VariableDef {
    var _f1000 = input.text();
    var _f1001 = _m_TypeName_read(input);
    var _o1002 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o1002 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f1003 = _o1002;
    var _f1004 = input.flag();
    var _f1005 = _m_Kind_read(input);
    var _v1006 = Array<ast.Attribute>();
    var _n1007 = input.count();
    for (var _ in 0.._n1007) {
        _v1006.append(_a_Attribute_read(input));
    }
    var _f1008 = _v1006;
    var _f1009 = input.loc();
    var _f1010 = input.loc();
    var _f1011 = input.flag();
    return VariableDef(_f1000, _f1001, _f1003, _f1004, _f1005, _f1008, _f1009, _f1010, _f1011);
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
    var _f1012 = _m_LoopBreakKind_read(input);
    return LoopBreak(_f1012);
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
    var _o1013 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o1013 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f1014 = _o1013;
    var _f1015 = input.loc();
    return ReturnStatement(_f1014, _f1015);
}

_m_While_write(out: RecordOut, value: While) {
    _m_Expression_write(out, value.condition);
    _m_Block_write(out, value.block);
}

_m_While_read(input: RecordIn): While {
    var _f1016 = _m_Expression_read(input);
    var _f1017 = _m_Block_read(input);
    return While(_f1016, _f1017);
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
    var _f1018 = _m_Expression_read(input);
    var _f1019 = _m_Block_read(input);
    var _o1020 = Optional<Block>.Empty;
    if (input.unsigned() == 1) {
        _o1020 = Optional<Block>.Value(_m_Block_read(input));
    }
    var _f1021 = _o1020;
    return Branch(_f1018, _f1019, _f1021);
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
        var _f1473 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1473);
    }
    if (tag == 1) {
        var _f1474 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1474);
    }
    if (tag == 2) {
        var _f1475 = _m_StructDef_read(input);
        return Declaration.Struct(_f1475);
    }
    if (tag == 3) {
        var _f1476 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1476);
    }
    if (tag == 4) {
        var _f1477 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1477);
    }
    if (tag == 5) {
        var _f1478 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1478);
    }
    if (tag == 6) {
        var _f1479 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1479);
    }
    input.fail("Declaration", tag);
    return _m_Declaration_read(input);
}

_m_TypeAliasDef_write(out: RecordOut, value: TypeAliasDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1022 in value.generic_params) {
        _m_GenericParam_write(out, _item1022);
    }
    _m_TypeName_write(out, value.target);
    out.unsigned(value.attributes.count);
    for (var _item1023 in value.attributes) {
        _a_Attribute_write(out, _item1023);
    }
    out.loc(value.loc);
}

_m_TypeAliasDef_read(input: RecordIn): TypeAliasDef {
    var _f1024 = input.text();
    var _v1025 = Array<GenericParam>();
    var _n1026 = input.count();
    for (var _ in 0.._n1026) {
        _v1025.append(_m_GenericParam_read(input));
    }
    var _f1027 = _v1025;
    var _f1028 = _m_TypeName_read(input);
    var _v1029 = Array<ast.Attribute>();
    var _n1030 = input.count();
    for (var _ in 0.._n1030) {
        _v1029.append(_a_Attribute_read(input));
    }
    var _f1031 = _v1029;
    var _f1032 = input.loc();
    return TypeAliasDef(_f1024, _f1027, _f1028, _f1031, _f1032);
}

_m_GenericParam_write(out: RecordOut, value: GenericParam) {
    out.text(value.name);
    out.loc(value.loc);
    out.unsigned(value.bounds.count);
    for (var _item1033 in value.bounds) {
        _m_Bound_write(out, _item1033);
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
    var _f1034 = input.text();
    var _f1035 = input.loc();
    var _v1036 = Array<Bound>();
    var _n1037 = input.count();
    for (var _ in 0.._n1037) {
        _v1036.append(_m_Bound_read(input));
    }
    var _f1038 = _v1036;
    var _o1039 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1039 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1040 = _o1039;
    var _f1041 = input.loc();
    var _f1042 = input.flag();
    return GenericParam(_f1034, _f1035, _f1038, _f1040, _f1041, _f1042);
}

_m_Bound_write(out: RecordOut, value: Bound) {
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_Bound_read(input: RecordIn): Bound {
    var _f1043 = _m_TypeName_read(input);
    var _f1044 = input.loc();
    return Bound(_f1043, _f1044);
}

_m_ExternDef_write(out: RecordOut, value: ExternDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.parameters.count);
    for (var _item1045 in value.parameters) {
        _m_VariableDef_write(out, _item1045);
    }
    out.flag(value.is_variadic);
    out.unsigned(value.attributes.count);
    for (var _item1046 in value.attributes) {
        _a_Attribute_write(out, _item1046);
    }
    out.loc(value.loc);
}

_m_ExternDef_read(input: RecordIn): ExternDef {
    var _f1047 = input.text();
    var _f1048 = _m_TypeName_read(input);
    var _v1049 = Array<VariableDef>();
    var _n1050 = input.count();
    for (var _ in 0.._n1050) {
        _v1049.append(_m_VariableDef_read(input));
    }
    var _f1051 = _v1049;
    var _f1052 = input.flag();
    var _v1053 = Array<ast.Attribute>();
    var _n1054 = input.count();
    for (var _ in 0.._n1054) {
        _v1053.append(_a_Attribute_read(input));
    }
    var _f1055 = _v1053;
    var _f1056 = input.loc();
    return ExternDef(_f1047, _f1048, _f1051, _f1052, _f1055, _f1056);
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
    for (var _item1057 in value.traits) {
        _m_TypeName_write(out, _item1057);
    }
    out.unsigned(value.restated.count);
    for (var _item1058 in value.restated) {
        var (_t1059, _t1060) = _item1058;
        out.unsigned(_t1059);
        _m_Bound_write(out, _t1060);
    }
    out.unsigned(value.methods.count);
    for (var _item1061 in value.methods) {
        _m_FunctionDef_write(out, _item1061);
    }
    out.unsigned(value.attributes.count);
    for (var _item1062 in value.attributes) {
        _a_Attribute_write(out, _item1062);
    }
    out.loc(value.loc);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_m_ExtensionDef_read(input: RecordIn): ExtensionDef {
    var _f1063 = _m_TypeName_read(input);
    var _o1064 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1064 = Optional<String>.Value(input.text());
    }
    var _f1065 = _o1064;
    var _v1066 = Array<TypeName>();
    var _n1067 = input.count();
    for (var _ in 0.._n1067) {
        _v1066.append(_m_TypeName_read(input));
    }
    var _f1068 = _v1066;
    var _v1069 = Array<(ulong, Bound)>();
    var _n1070 = input.count();
    for (var _ in 0.._n1070) {
        var _t1071 = input.unsigned();
        var _t1072 = _m_Bound_read(input);
        _v1069.append((_t1071, _t1072));
    }
    var _f1073 = _v1069;
    var _v1074 = Array<FunctionDef>();
    var _n1075 = input.count();
    for (var _ in 0.._n1075) {
        _v1074.append(_m_FunctionDef_read(input));
    }
    var _f1076 = _v1074;
    var _v1077 = Array<ast.Attribute>();
    var _n1078 = input.count();
    for (var _ in 0.._n1078) {
        _v1077.append(_a_Attribute_read(input));
    }
    var _f1079 = _v1077;
    var _f1080 = input.loc();
    var _f1081 = input.flag();
    var _f1082 = input.flag();
    return ExtensionDef(_f1063, _f1065, _f1068, _f1073, _f1076, _f1079, _f1080, _f1081, _f1082);
}

_m_TraitDef_write(out: RecordOut, value: TraitDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1083 in value.generic_params) {
        _m_GenericParam_write(out, _item1083);
    }
    out.unsigned(value.methods.count);
    for (var _item1084 in value.methods) {
        _m_FunctionDef_write(out, _item1084);
    }
    out.unsigned(value.attributes.count);
    for (var _item1085 in value.attributes) {
        _a_Attribute_write(out, _item1085);
    }
    out.loc(value.loc);
}

_m_TraitDef_read(input: RecordIn): TraitDef {
    var _f1086 = input.text();
    var _v1087 = Array<GenericParam>();
    var _n1088 = input.count();
    for (var _ in 0.._n1088) {
        _v1087.append(_m_GenericParam_read(input));
    }
    var _f1089 = _v1087;
    var _v1090 = Array<FunctionDef>();
    var _n1091 = input.count();
    for (var _ in 0.._n1091) {
        _v1090.append(_m_FunctionDef_read(input));
    }
    var _f1092 = _v1090;
    var _v1093 = Array<ast.Attribute>();
    var _n1094 = input.count();
    for (var _ in 0.._n1094) {
        _v1093.append(_a_Attribute_read(input));
    }
    var _f1095 = _v1093;
    var _f1096 = input.loc();
    return TraitDef(_f1086, _f1089, _f1092, _f1095, _f1096);
}

_m_StructDef_write(out: RecordOut, value: StructDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.generic_params.count);
    for (var _item1097 in value.generic_params) {
        _m_GenericParam_write(out, _item1097);
    }
    out.unsigned(value.field_members.count);
    for (var _item1098 in value.field_members) {
        _m_VariableDef_write(out, _item1098);
    }
    out.unsigned(value.method_members.count);
    for (var _item1099 in value.method_members) {
        _m_FunctionDef_write(out, _item1099);
    }
    out.unsigned(value.generic_methods.count);
    for (var _item1100 in value.generic_methods) {
        _m_FunctionDef_write(out, _item1100);
    }
    out.unsigned(value.constructors.count);
    for (var _item1101 in value.constructors) {
        _m_FunctionDef_write(out, _item1101);
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    out.unsigned(value.traits.count);
    for (var _item1102 in value.traits) {
        _m_TypeName_write(out, _item1102);
    }
    out.unsigned(value.attributes.count);
    for (var _item1103 in value.attributes) {
        _a_Attribute_write(out, _item1103);
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item1104 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item1104);
        }
    } else {
        out.unsigned(0);
    }
}

_m_StructDef_read(input: RecordIn): StructDef {
    return _m_StructDef_read_with(input, false);
}

_m_StructDef_read_lazy(input: RecordIn): StructDef {
    return _m_StructDef_read_with(input, input.lazy_bodies);
}

_m_StructDef_read_with(input: RecordIn, lazy: bool): StructDef {
    var _f1105 = input.text();
    var _f1106 = _m_TypeName_read(input);
    var _v1107 = Array<GenericParam>();
    var _n1108 = input.count();
    for (var _ in 0.._n1108) {
        _v1107.append(_m_GenericParam_read(input));
    }
    var _f1109 = _v1107;
    var _v1110 = Array<VariableDef>();
    var _n1111 = input.count();
    for (var _ in 0.._n1111) {
        _v1110.append(_m_VariableDef_read(input));
    }
    var _f1112 = _v1110;
    var _v1113 = Array<FunctionDef>();
    var _n1114 = input.count();
    for (var _ in 0.._n1114) {
        _v1113.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1115 = _v1113;
    var _v1116 = Array<FunctionDef>();
    var _n1117 = input.count();
    for (var _ in 0.._n1117) {
        _v1116.append(_m_FunctionDef_read(input));
    }
    var _f1118 = _v1116;
    var _v1119 = Array<FunctionDef>();
    var _n1120 = input.count();
    for (var _ in 0.._n1120) {
        _v1119.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1121 = _v1119;
    var _f1122 = _m_FunctionDef_read_with(input, lazy);
    var _f1123 = _m_FunctionDef_read_with(input, lazy);
    var _f1124 = _m_FunctionDef_read_with(input, lazy);
    var _v1125 = Array<TypeName>();
    var _n1126 = input.count();
    for (var _ in 0.._n1126) {
        _v1125.append(_m_TypeName_read(input));
    }
    var _f1127 = _v1125;
    var _v1128 = Array<ast.Attribute>();
    var _n1129 = input.count();
    for (var _ in 0.._n1129) {
        _v1128.append(_a_Attribute_read(input));
    }
    var _f1130 = _v1128;
    var _f1131 = input.loc();
    var _o1132 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v1133 = Array<EnumCaseDef>();
        var _n1134 = input.count();
        for (var _ in 0.._n1134) {
            _v1133.append(_m_EnumCaseDef_read(input));
        }
        _o1132 = Optional<Array<EnumCaseDef>>.Value(_v1133);
    }
    var _f1135 = _o1132;
    return StructDef(
        _f1105, _f1106, _f1109, _f1112, _f1115, _f1118, _f1121, _f1122, _f1123, _f1124, _f1127, _f1130, _f1131, _f1135
    );
}

_m_EnumCaseDef_write(out: RecordOut, value: EnumCaseDef) {
    out.text(value.name);
    out.signed(value.value as long);
    out.unsigned(value.payload.count);
    for (var _item1136 in value.payload) {
        var (_t1137, _t1138) = _item1136;
        out.text(_t1137);
        out.loc(_t1138);
    }
    out.unsigned(value.attributes.count);
    for (var _item1139 in value.attributes) {
        _a_Attribute_write(out, _item1139);
    }
    out.loc(value.loc);
}

_m_EnumCaseDef_read(input: RecordIn): EnumCaseDef {
    var _f1140 = input.text();
    var _f1141 = input.signed();
    var _v1142 = Array<(String, Loc)>();
    var _n1143 = input.count();
    for (var _ in 0.._n1143) {
        var _t1144 = input.text();
        var _t1145 = input.loc();
        _v1142.append((_t1144, _t1145));
    }
    var _f1146 = _v1142;
    var _v1147 = Array<ast.Attribute>();
    var _n1148 = input.count();
    for (var _ in 0.._n1148) {
        _v1147.append(_a_Attribute_read(input));
    }
    var _f1149 = _v1147;
    var _f1150 = input.loc();
    return EnumCaseDef(_f1140, _f1141, _f1146, _f1149, _f1150);
}

_m_ExtensionScopes_write(out: RecordOut, value: ExtensionScopes) {
    var _keys1152 = Array<(u8[], u8[], uint)>();
    for (var _key1151 in value.prelude) {
        var _scratch1153 = out.scratch();
        _scratch1153.unsigned(_key1151 as ulong);
        var _vscratch1155 = out.scratch();
        _keys1152.append((_scratch1153.finish(), _vscratch1155.finish(), _key1151));
    }
    _keys1152.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys1152.count);
    for (var (_bytes1154, _, _key1151) in _keys1152) {
        out.unsigned(_key1151 as ulong);
    }
    out.unsigned(value.visible.count);
    for (var _item1156 in value.visible) {
        var _keys1158 = Array<(u8[], u8[], uint)>();
        for (var _key1157 in _item1156) {
            var _scratch1159 = out.scratch();
            _scratch1159.unsigned(_key1157 as ulong);
            var _vscratch1161 = out.scratch();
            _keys1158.append((_scratch1159.finish(), _vscratch1161.finish(), _key1157));
        }
        _keys1158.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1158.count);
        for (var (_bytes1160, _, _key1157) in _keys1158) {
            out.unsigned(_key1157 as ulong);
        }
    }
    out.unsigned(value.module.count);
    for (var _item1162 in value.module) {
        if (_item1162.is_value()) {
            out.unsigned(1);
            out.unsigned(_item1162.value() as ulong);
        } else {
            out.unsigned(0);
        }
    }
}

_m_ExtensionScopes_read(input: RecordIn): ExtensionScopes {
    var _v1163 = HashSet<uint>();
    var _n1164 = input.count();
    for (var _ in 0.._n1164) {
        _v1163.insert(input.unsigned() as uint);
    }
    var _f1165 = _v1163;
    var _v1166 = Array<HashSet<uint>>();
    var _n1167 = input.count();
    for (var _ in 0.._n1167) {
        var _v1168 = HashSet<uint>();
        var _n1169 = input.count();
        for (var _ in 0.._n1169) {
            _v1168.insert(input.unsigned() as uint);
        }
        _v1166.append(_v1168);
    }
    var _f1170 = _v1166;
    var _v1171 = Array<Optional<uint>>();
    var _n1172 = input.count();
    for (var _ in 0.._n1172) {
        var _o1173 = Optional<uint>.Empty;
        if (input.unsigned() == 1) {
            _o1173 = Optional<uint>.Value(input.unsigned() as uint);
        }
        _v1171.append(_o1173);
    }
    var _f1174 = _v1171;
    return ExtensionScopes(_f1165, _f1170, _f1174);
}

_m_Conversion_write(out: RecordOut, value: Conversion) {
    out.loc(value.at);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.constructor);
}

_m_Conversion_read(input: RecordIn): Conversion {
    var _f1175 = input.loc();
    var _f1176 = _m_TypeName_read(input);
    var _f1177 = _m_TypeName_read(input);
    var _f1178 = input.loc();
    return Conversion(_f1175, _f1176, _f1177, _f1178);
}

_m_TraitType_write(out: RecordOut, value: TraitType) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.methods.count);
    for (var _item1179 in value.methods) {
        _m_FunctionDef_write(out, _item1179);
    }
}

_m_TraitType_read(input: RecordIn): TraitType {
    var _f1180 = _m_TypeName_read(input);
    var _v1181 = Array<FunctionDef>();
    var _n1182 = input.count();
    for (var _ in 0.._n1182) {
        _v1181.append(_m_FunctionDef_read(input));
    }
    var _f1183 = _v1181;
    return TraitType(_f1180, _f1183);
}

_m_UseContext_write(out: RecordOut, value: UseContext) {
    out.unsigned(value.scope.count);
    for (var _item1184 in value.scope) {
        _m_GenericParam_write(out, _item1184);
    }
    if (value.extension.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.extension.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.conditions.count);
    for (var _item1185 in value.conditions) {
        _a_Attribute_write(out, _item1185);
    }
}

_m_UseContext_read(input: RecordIn): UseContext {
    var _v1186 = Array<GenericParam>();
    var _n1187 = input.count();
    for (var _ in 0.._n1187) {
        _v1186.append(_m_GenericParam_read(input));
    }
    var _f1188 = _v1186;
    var _o1189 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1189 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1190 = _o1189;
    var _v1191 = Array<ast.Attribute>();
    var _n1192 = input.count();
    for (var _ in 0.._n1192) {
        _v1191.append(_a_Attribute_read(input));
    }
    var _f1193 = _v1191;
    return UseContext(_f1188, _f1190, _f1193);
}

_m_TypeUse_write(out: RecordOut, value: TypeUse) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1194 in value.args) {
        out.loc(_item1194);
    }
    out.unsigned(value.context);
}

_m_TypeUse_read(input: RecordIn): TypeUse {
    var _f1195 = _m_TypeName_read(input);
    var _v1196 = Array<Loc>();
    var _n1197 = input.count();
    for (var _ in 0.._n1197) {
        _v1196.append(input.loc());
    }
    var _f1198 = _v1196;
    var _f1199 = input.unsigned();
    return TypeUse(_f1195, _f1198, _f1199);
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
    var _f1200 = input.text();
    var _f1201 = input.text();
    var _f1202 = input.flag();
    var _f1203 = input.loc();
    var _f1204 = _m_AccessorKind_read(input);
    var _o1205 = Optional<AccessorKind>.Empty;
    if (input.unsigned() == 1) {
        _o1205 = Optional<AccessorKind>.Value(_m_AccessorKind_read(input));
    }
    var _f1206 = _o1205;
    var _f1207 = input.loc();
    var _o1208 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1208 = Optional<String>.Value(input.text());
    }
    var _f1209 = _o1208;
    var _f1210 = input.flag();
    return PropertyDef(_f1200, _f1201, _f1202, _f1203, _f1204, _f1206, _f1207, _f1209, _f1210);
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
    var _f1211 = input.text();
    var _f1212 = input.text();
    var _f1213 = input.text();
    var _f1214 = input.unsigned();
    var _f1215 = _m_TypeName_read(input);
    var _f1216 = _m_TypeName_read(input);
    var _f1217 = input.loc();
    return Withheld(_f1211, _f1212, _f1213, _f1214, _f1215, _f1216, _f1217);
}

_m_EnumDef_write(out: RecordOut, value: EnumDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.representation);
    out.unsigned(value.cases.count);
    for (var _item1218 in value.cases) {
        _m_EnumCaseDef_write(out, _item1218);
    }
    out.unsigned(value.attributes.count);
    for (var _item1219 in value.attributes) {
        _a_Attribute_write(out, _item1219);
    }
    out.loc(value.loc);
}

_m_EnumDef_read(input: RecordIn): EnumDef {
    var _f1220 = input.text();
    var _f1221 = _m_TypeName_read(input);
    var _v1222 = Array<EnumCaseDef>();
    var _n1223 = input.count();
    for (var _ in 0.._n1223) {
        _v1222.append(_m_EnumCaseDef_read(input));
    }
    var _f1224 = _v1222;
    var _v1225 = Array<ast.Attribute>();
    var _n1226 = input.count();
    for (var _ in 0.._n1226) {
        _v1225.append(_a_Attribute_read(input));
    }
    var _f1227 = _v1225;
    var _f1228 = input.loc();
    return EnumDef(_f1220, _f1221, _f1224, _f1227, _f1228);
}

_m_ModuleStaticBlock_write(out: RecordOut, value: ModuleStaticBlock) {
    _m_StaticBlock_write(out, value.block);
    out.unsigned(value.constants.count);
    for (var _item1229 in value.constants) {
        var (_t1230, _t1231) = _item1229;
        out.text(_t1230);
        out.loc(_t1231);
    }
}

_m_ModuleStaticBlock_read(input: RecordIn): ModuleStaticBlock {
    var _f1232 = _m_StaticBlock_read(input);
    var _v1233 = Array<(String, Loc)>();
    var _n1234 = input.count();
    for (var _ in 0.._n1234) {
        var _t1235 = input.text();
        var _t1236 = input.loc();
        _v1233.append((_t1235, _t1236));
    }
    var _f1237 = _v1233;
    return ModuleStaticBlock(_f1232, _f1237);
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
        for (var _item1238 in value.symbols.value()) {
            _a_ImportedSymbol_write(out, _item1238);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.reexport);
    out.unsigned(value.attributes.count);
    for (var _item1239 in value.attributes) {
        _a_Attribute_write(out, _item1239);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Import_read(input: RecordIn): ast.Import {
    var _f1240 = input.text();
    var _s1241 = input.unsigned();
    var _f1242 = ast.Span(_s1241, input.unsigned());
    var _o1243 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1243 = Optional<String>.Value(input.text());
    }
    var _f1244 = _o1243;
    var _f1245 = input.flag();
    var _o1246 = Optional<Array<ast.ImportedSymbol>>.Empty;
    if (input.unsigned() == 1) {
        var _v1247 = Array<ast.ImportedSymbol>();
        var _n1248 = input.count();
        for (var _ in 0.._n1248) {
            _v1247.append(_a_ImportedSymbol_read(input));
        }
        _o1246 = Optional<Array<ast.ImportedSymbol>>.Value(_v1247);
    }
    var _f1249 = _o1246;
    var _f1250 = input.flag();
    var _v1251 = Array<ast.Attribute>();
    var _n1252 = input.count();
    for (var _ in 0.._n1252) {
        _v1251.append(_a_Attribute_read(input));
    }
    var _f1253 = _v1251;
    var _s1254 = input.unsigned();
    var _f1255 = ast.Span(_s1254, input.unsigned());
    var value = ast.Import();
    value.name = _f1240;
    value.name_span = _f1242;
    value.alias = _f1244;
    value.is_local = _f1245;
    value.symbols = _f1249;
    value.reexport = _f1250;
    value.attributes = _f1253;
    value.span = _f1255;
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
    var _f1256 = input.text();
    var _s1257 = input.unsigned();
    var _f1258 = ast.Span(_s1257, input.unsigned());
    var _o1259 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1259 = Optional<String>.Value(input.text());
    }
    var _f1260 = _o1259;
    var _s1261 = input.unsigned();
    var _f1262 = ast.Span(_s1261, input.unsigned());
    var value = ast.ImportedSymbol();
    value.name = _f1256;
    value.name_span = _f1258;
    value.alias = _f1260;
    value.span = _f1262;
    return value;
}

_m_Module_write_delta(out: RecordOut, value: Module, base: DeltaBase, next: DeltaBase) {
    ulong _mark = out.values.count;
    var _hs1486 = Array<String>();
    for (var _item1480 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1480);
        _hs1486.append(base.hash_of(scratch));
    }
    var _seq1487 = base.sequence("imports");
    ulong _bj1488 = 0;
    var _news1489 = Array<ulong>();
    for (var _i1490 in 0.._hs1486.count) {
        if (_bj1488 < _seq1487.count and _hs1486[_i1490] == _seq1487[_bj1488]) {
            _bj1488 += 1;
        } else {
            _news1489.append(_i1490);
        }
    }
    for (var _i1490 in 0.._hs1486.count) {
        next.add_hashed("imports", _hs1486[_i1490], _i1490);
    }
    if (_bj1488 == _seq1487.count) {
        out.unsigned(2);
        out.unsigned(_news1489.count);
        for (var _i1490 in _news1489) {
            out.unsigned(_i1490);
            _a_Import_write(out, value.imports[_i1490]);
            {
                var _own1491 = RecordOut();
                _own1491.blank_bodies = true;
                _own1491.blank_locs = true;
                _own1491.pending_as_bytes = true;
                _a_Import_write(_own1491, value.imports[_i1490]);
                base.own("imports", interface_text(_own1491));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1490 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1490]);
            {
                var _own1492 = RecordOut();
                _own1492.blank_bodies = true;
                _own1492.blank_locs = true;
                _own1492.pending_as_bytes = true;
                _a_Import_write(_own1492, value.imports[_i1490]);
                base.own("imports", interface_text(_own1492));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1502 = Array<String>();
    for (var _item1500 in value.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1500);
        _hs1502.append(base.hash_of(scratch));
    }
    var _seq1503 = base.sequence("s");
    var _seqn1504 = base.sequence("s#");
    ulong _bj1505 = 0;
    var _news1506 = Array<ulong>();
    var _patches1507 = Array<(ulong, ulong)>();
    for (var _i1508 in 0.._hs1502.count) {
        if (_bj1505 < _seq1503.count and _hs1502[_i1508] == _seq1503[_bj1505]) {
            _bj1505 += 1;
        } else if (_bj1505 < _seq1503.count
            and _bj1505 < _seqn1504.count
            and value.structs[_i1508].name == _seqn1504[_bj1505]) {
            _patches1507.append((_i1508, _bj1505));
            _bj1505 += 1;
        } else {
            _news1506.append(_i1508);
        }
    }
    if (_bj1505 == _seq1503.count) {
        out.unsigned(2);
        out.unsigned(_patches1507.count);
        for (var (_i1508, _b) in _patches1507) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1508].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1508], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1509 = RecordOut();
                _own1509.blank_bodies = true;
                _own1509.blank_locs = true;
                _own1509.pending_as_bytes = true;
                _m_StructDef_write(_own1509, value.structs[_i1508]);
                base.own("structs", interface_text(_own1509));
            }
        }
        out.unsigned(_news1506.count);
        for (var _i1508 in _news1506) {
            ulong _before = out.values.count;
            out.unsigned(_i1508);
            _m_StructDef_write(out, value.structs[_i1508]);
            base.count("s new", out.values.count - _before);
            {
                var _own1510 = RecordOut();
                _own1510.blank_bodies = true;
                _own1510.blank_locs = true;
                _own1510.pending_as_bytes = true;
                _m_StructDef_write(_own1510, value.structs[_i1508]);
                base.own("structs", interface_text(_own1510));
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1501 = HashSet<long>();
        out.unsigned(value.structs.count);
        for (var _i1508 in 0..value.structs.count) {
            var _item1500 = value.structs[_i1508];
            var at = base.find_hashed("s", _hs1502[_i1508]);
            var named = base.named("s", _item1500.name);
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1501.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1501.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1500, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1500);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1501.count);
    }
    for (var _i1508 in 0.._hs1502.count) {
        next.add_hashed("s", _hs1502[_i1508], _i1508);
        next.name("s", value.structs[_i1508].name, _i1508);
        _patch_s_index(value.structs[_i1508], next, _i1508);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1525 = Array<String>();
    for (var _item1519 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1519);
        _hs1525.append(base.hash_of(scratch));
    }
    var _seq1526 = base.sequence("traits");
    ulong _bj1527 = 0;
    var _news1528 = Array<ulong>();
    for (var _i1529 in 0.._hs1525.count) {
        if (_bj1527 < _seq1526.count and _hs1525[_i1529] == _seq1526[_bj1527]) {
            _bj1527 += 1;
        } else {
            _news1528.append(_i1529);
        }
    }
    for (var _i1529 in 0.._hs1525.count) {
        next.add_hashed("traits", _hs1525[_i1529], _i1529);
    }
    if (_bj1527 == _seq1526.count) {
        out.unsigned(2);
        out.unsigned(_news1528.count);
        for (var _i1529 in _news1528) {
            out.unsigned(_i1529);
            _m_TraitDef_write(out, value.traits[_i1529]);
            {
                var _own1530 = RecordOut();
                _own1530.blank_bodies = true;
                _own1530.blank_locs = true;
                _own1530.pending_as_bytes = true;
                _m_TraitDef_write(_own1530, value.traits[_i1529]);
                base.own("traits", interface_text(_own1530));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1529 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1529]);
            {
                var _own1531 = RecordOut();
                _own1531.blank_bodies = true;
                _own1531.blank_locs = true;
                _own1531.pending_as_bytes = true;
                _m_TraitDef_write(_own1531, value.traits[_i1529]);
                base.own("traits", interface_text(_own1531));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1545 = Array<String>();
    for (var _item1539 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1539);
        _hs1545.append(base.hash_of(scratch));
    }
    var _seq1546 = base.sequence("extensions");
    ulong _bj1547 = 0;
    var _news1548 = Array<ulong>();
    for (var _i1549 in 0.._hs1545.count) {
        if (_bj1547 < _seq1546.count and _hs1545[_i1549] == _seq1546[_bj1547]) {
            _bj1547 += 1;
        } else {
            _news1548.append(_i1549);
        }
    }
    for (var _i1549 in 0.._hs1545.count) {
        next.add_hashed("extensions", _hs1545[_i1549], _i1549);
    }
    if (_bj1547 == _seq1546.count) {
        out.unsigned(2);
        out.unsigned(_news1548.count);
        for (var _i1549 in _news1548) {
            out.unsigned(_i1549);
            _m_ExtensionDef_write(out, value.extensions[_i1549]);
            {
                var _own1550 = RecordOut();
                _own1550.blank_bodies = true;
                _own1550.blank_locs = true;
                _own1550.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1550, value.extensions[_i1549]);
                base.own("extensions", interface_text(_own1550));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1549 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1549]);
            {
                var _own1551 = RecordOut();
                _own1551.blank_bodies = true;
                _own1551.blank_locs = true;
                _own1551.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1551, value.extensions[_i1549]);
                base.own("extensions", interface_text(_own1551));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1565 = Array<String>();
    for (var _item1559 in value.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1559);
        _hs1565.append(base.hash_of(scratch));
    }
    var _seq1566 = base.sequence("functions");
    ulong _bj1567 = 0;
    var _news1568 = Array<ulong>();
    var _changed1560 = Array<(ulong, ulong)>();
    var _seqn1561 = base.sequence("functions" + "#");
    for (var _i1569 in 0.._hs1565.count) {
        if (_bj1567 < _seq1566.count and _hs1565[_i1569] == _seq1566[_bj1567]) {
            _bj1567 += 1;
        } else if (_bj1567 < _seqn1561.count and value.functions[_i1569].name == _seqn1561[_bj1567]) {
            _changed1560.append((_i1569, _bj1567));
            _bj1567 += 1;
        } else {
            _news1568.append(_i1569);
        }
    }
    for (var _i1569 in 0.._hs1565.count) {
        next.add_hashed("functions", _hs1565[_i1569], _i1569);
        next.name("functions", value.functions[_i1569].name, _i1569);
    }
    if (_bj1567 == _seq1566.count) {
        out.unsigned(2);
        out.unsigned(_changed1560.count);
        for (var (_i1569, _b) in _changed1560) {
            out.text(value.functions[_i1569].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1569]);
            {
                var _own1570 = RecordOut();
                _own1570.blank_bodies = true;
                _own1570.blank_locs = true;
                _own1570.pending_as_bytes = true;
                _m_FunctionDef_write(_own1570, value.functions[_i1569]);
                base.own("functions", interface_text(_own1570));
            }
        }
        base.count("functions" + " changed", _changed1560.count);
        out.unsigned(_news1568.count);
        for (var _i1569 in _news1568) {
            out.unsigned(_i1569);
            _m_FunctionDef_write(out, value.functions[_i1569]);
            {
                var _own1571 = RecordOut();
                _own1571.blank_bodies = true;
                _own1571.blank_locs = true;
                _own1571.pending_as_bytes = true;
                _m_FunctionDef_write(_own1571, value.functions[_i1569]);
                base.own("functions", interface_text(_own1571));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1569 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1569]);
            {
                var _own1572 = RecordOut();
                _own1572.blank_bodies = true;
                _own1572.blank_locs = true;
                _own1572.pending_as_bytes = true;
                _m_FunctionDef_write(_own1572, value.functions[_i1569]);
                base.own("functions", interface_text(_own1572));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1586 = Array<String>();
    for (var _item1580 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1580);
        _hs1586.append(base.hash_of(scratch));
    }
    var _seq1587 = base.sequence("externs");
    ulong _bj1588 = 0;
    var _news1589 = Array<ulong>();
    for (var _i1590 in 0.._hs1586.count) {
        if (_bj1588 < _seq1587.count and _hs1586[_i1590] == _seq1587[_bj1588]) {
            _bj1588 += 1;
        } else {
            _news1589.append(_i1590);
        }
    }
    for (var _i1590 in 0.._hs1586.count) {
        next.add_hashed("externs", _hs1586[_i1590], _i1590);
    }
    if (_bj1588 == _seq1587.count) {
        out.unsigned(2);
        out.unsigned(_news1589.count);
        for (var _i1590 in _news1589) {
            out.unsigned(_i1590);
            _m_ExternDef_write(out, value.externs[_i1590]);
            {
                var _own1591 = RecordOut();
                _own1591.blank_bodies = true;
                _own1591.blank_locs = true;
                _own1591.pending_as_bytes = true;
                _m_ExternDef_write(_own1591, value.externs[_i1590]);
                base.own("externs", interface_text(_own1591));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1590 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1590]);
            {
                var _own1592 = RecordOut();
                _own1592.blank_bodies = true;
                _own1592.blank_locs = true;
                _own1592.pending_as_bytes = true;
                _m_ExternDef_write(_own1592, value.externs[_i1590]);
                base.own("externs", interface_text(_own1592));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1606 = Array<String>();
    for (var _item1600 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1600);
        _hs1606.append(base.hash_of(scratch));
    }
    var _seq1607 = base.sequence("globals");
    ulong _bj1608 = 0;
    var _news1609 = Array<ulong>();
    for (var _i1610 in 0.._hs1606.count) {
        if (_bj1608 < _seq1607.count and _hs1606[_i1610] == _seq1607[_bj1608]) {
            _bj1608 += 1;
        } else {
            _news1609.append(_i1610);
        }
    }
    for (var _i1610 in 0.._hs1606.count) {
        next.add_hashed("globals", _hs1606[_i1610], _i1610);
    }
    if (_bj1608 == _seq1607.count) {
        out.unsigned(2);
        out.unsigned(_news1609.count);
        for (var _i1610 in _news1609) {
            out.unsigned(_i1610);
            _m_VariableDef_write(out, value.globals[_i1610]);
            {
                var _own1611 = RecordOut();
                _own1611.blank_bodies = true;
                _own1611.blank_locs = true;
                _own1611.pending_as_bytes = true;
                _m_VariableDef_write(_own1611, value.globals[_i1610]);
                base.own("globals", interface_text(_own1611));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1610 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1610]);
            {
                var _own1612 = RecordOut();
                _own1612.blank_bodies = true;
                _own1612.blank_locs = true;
                _own1612.pending_as_bytes = true;
                _m_VariableDef_write(_own1612, value.globals[_i1610]);
                base.own("globals", interface_text(_own1612));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1626 = Array<String>();
    for (var _item1620 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1620);
        _hs1626.append(base.hash_of(scratch));
    }
    var _seq1627 = base.sequence("static_blocks");
    ulong _bj1628 = 0;
    var _news1629 = Array<ulong>();
    for (var _i1630 in 0.._hs1626.count) {
        if (_bj1628 < _seq1627.count and _hs1626[_i1630] == _seq1627[_bj1628]) {
            _bj1628 += 1;
        } else {
            _news1629.append(_i1630);
        }
    }
    for (var _i1630 in 0.._hs1626.count) {
        next.add_hashed("static_blocks", _hs1626[_i1630], _i1630);
    }
    if (_bj1628 == _seq1627.count) {
        out.unsigned(2);
        out.unsigned(_news1629.count);
        for (var _i1630 in _news1629) {
            out.unsigned(_i1630);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1630]);
            {
                var _own1631 = RecordOut();
                _own1631.blank_bodies = true;
                _own1631.blank_locs = true;
                _own1631.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1631, value.static_blocks[_i1630]);
                base.own("static_blocks", interface_text(_own1631));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1630 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1630]);
            {
                var _own1632 = RecordOut();
                _own1632.blank_bodies = true;
                _own1632.blank_locs = true;
                _own1632.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1632, value.static_blocks[_i1630]);
                base.own("static_blocks", interface_text(_own1632));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1646 = Array<String>();
    for (var _item1640 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1640);
        _hs1646.append(base.hash_of(scratch));
    }
    var _seq1647 = base.sequence("enums");
    ulong _bj1648 = 0;
    var _news1649 = Array<ulong>();
    for (var _i1650 in 0.._hs1646.count) {
        if (_bj1648 < _seq1647.count and _hs1646[_i1650] == _seq1647[_bj1648]) {
            _bj1648 += 1;
        } else {
            _news1649.append(_i1650);
        }
    }
    for (var _i1650 in 0.._hs1646.count) {
        next.add_hashed("enums", _hs1646[_i1650], _i1650);
    }
    if (_bj1648 == _seq1647.count) {
        out.unsigned(2);
        out.unsigned(_news1649.count);
        for (var _i1650 in _news1649) {
            out.unsigned(_i1650);
            _m_EnumDef_write(out, value.enums[_i1650]);
            {
                var _own1651 = RecordOut();
                _own1651.blank_bodies = true;
                _own1651.blank_locs = true;
                _own1651.pending_as_bytes = true;
                _m_EnumDef_write(_own1651, value.enums[_i1650]);
                base.own("enums", interface_text(_own1651));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1650 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1650]);
            {
                var _own1652 = RecordOut();
                _own1652.blank_bodies = true;
                _own1652.blank_locs = true;
                _own1652.pending_as_bytes = true;
                _m_EnumDef_write(_own1652, value.enums[_i1650]);
                base.own("enums", interface_text(_own1652));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1666 = Array<String>();
    for (var _item1660 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1660);
        _hs1666.append(base.hash_of(scratch));
    }
    var _seq1667 = base.sequence("struct_specs");
    ulong _bj1668 = 0;
    var _news1669 = Array<ulong>();
    for (var _i1670 in 0.._hs1666.count) {
        if (_bj1668 < _seq1667.count and _hs1666[_i1670] == _seq1667[_bj1668]) {
            _bj1668 += 1;
        } else {
            _news1669.append(_i1670);
        }
    }
    for (var _i1670 in 0.._hs1666.count) {
        next.add_hashed("struct_specs", _hs1666[_i1670], _i1670);
    }
    if (_bj1668 == _seq1667.count) {
        out.unsigned(2);
        out.unsigned(_news1669.count);
        for (var _i1670 in _news1669) {
            out.unsigned(_i1670);
            _m_TypeName_write(out, value.struct_specs[_i1670]);
            {
                var _own1671 = RecordOut();
                _own1671.blank_bodies = true;
                _own1671.blank_locs = true;
                _own1671.pending_as_bytes = true;
                _m_TypeName_write(_own1671, value.struct_specs[_i1670]);
                base.own("struct_specs", interface_text(_own1671));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1670 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1670]);
            {
                var _own1672 = RecordOut();
                _own1672.blank_bodies = true;
                _own1672.blank_locs = true;
                _own1672.pending_as_bytes = true;
                _m_TypeName_write(_own1672, value.struct_specs[_i1670]);
                base.own("struct_specs", interface_text(_own1672));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1686 = Array<String>();
    for (var _item1680 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1680);
        _hs1686.append(base.hash_of(scratch));
    }
    var _seq1687 = base.sequence("func_specs");
    ulong _bj1688 = 0;
    var _news1689 = Array<ulong>();
    for (var _i1690 in 0.._hs1686.count) {
        if (_bj1688 < _seq1687.count and _hs1686[_i1690] == _seq1687[_bj1688]) {
            _bj1688 += 1;
        } else {
            _news1689.append(_i1690);
        }
    }
    for (var _i1690 in 0.._hs1686.count) {
        next.add_hashed("func_specs", _hs1686[_i1690], _i1690);
    }
    if (_bj1688 == _seq1687.count) {
        out.unsigned(2);
        out.unsigned(_news1689.count);
        for (var _i1690 in _news1689) {
            out.unsigned(_i1690);
            _m_TypeName_write(out, value.func_specs[_i1690]);
            {
                var _own1691 = RecordOut();
                _own1691.blank_bodies = true;
                _own1691.blank_locs = true;
                _own1691.pending_as_bytes = true;
                _m_TypeName_write(_own1691, value.func_specs[_i1690]);
                base.own("func_specs", interface_text(_own1691));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1690 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1690]);
            {
                var _own1692 = RecordOut();
                _own1692.blank_bodies = true;
                _own1692.blank_locs = true;
                _own1692.pending_as_bytes = true;
                _m_TypeName_write(_own1692, value.func_specs[_i1690]);
                base.own("func_specs", interface_text(_own1692));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1704 = HashSet<long>();
    ulong _nj1705 = 0;
    out.unsigned(value.type_aliases.count);
    for (var _item1700 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1700);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1704.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1700);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1704.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1716 = Array<String>();
    for (var _item1710 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1710);
        _hs1716.append(base.hash_of(scratch));
    }
    var _seq1717 = base.sequence("withheld");
    ulong _bj1718 = 0;
    var _news1719 = Array<ulong>();
    for (var _i1720 in 0.._hs1716.count) {
        if (_bj1718 < _seq1717.count and _hs1716[_i1720] == _seq1717[_bj1718]) {
            _bj1718 += 1;
        } else {
            _news1719.append(_i1720);
        }
    }
    for (var _i1720 in 0.._hs1716.count) {
        next.add_hashed("withheld", _hs1716[_i1720], _i1720);
    }
    if (_bj1718 == _seq1717.count) {
        out.unsigned(2);
        out.unsigned(_news1719.count);
        for (var _i1720 in _news1719) {
            out.unsigned(_i1720);
            _m_Withheld_write(out, value.withheld[_i1720]);
            {
                var _own1721 = RecordOut();
                _own1721.blank_bodies = true;
                _own1721.blank_locs = true;
                _own1721.pending_as_bytes = true;
                _m_Withheld_write(_own1721, value.withheld[_i1720]);
                base.own("withheld", interface_text(_own1721));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1720 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1720]);
            {
                var _own1722 = RecordOut();
                _own1722.blank_bodies = true;
                _own1722.blank_locs = true;
                _own1722.pending_as_bytes = true;
                _m_Withheld_write(_own1722, value.withheld[_i1720]);
                base.own("withheld", interface_text(_own1722));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1736 = Array<String>();
    for (var _item1730 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1730);
        _hs1736.append(base.hash_of(scratch));
    }
    var _seq1737 = base.sequence("properties");
    ulong _bj1738 = 0;
    var _news1739 = Array<ulong>();
    for (var _i1740 in 0.._hs1736.count) {
        if (_bj1738 < _seq1737.count and _hs1736[_i1740] == _seq1737[_bj1738]) {
            _bj1738 += 1;
        } else {
            _news1739.append(_i1740);
        }
    }
    for (var _i1740 in 0.._hs1736.count) {
        next.add_hashed("properties", _hs1736[_i1740], _i1740);
    }
    if (_bj1738 == _seq1737.count) {
        out.unsigned(2);
        out.unsigned(_news1739.count);
        for (var _i1740 in _news1739) {
            out.unsigned(_i1740);
            _m_PropertyDef_write(out, value.properties[_i1740]);
            {
                var _own1741 = RecordOut();
                _own1741.blank_bodies = true;
                _own1741.blank_locs = true;
                _own1741.pending_as_bytes = true;
                _m_PropertyDef_write(_own1741, value.properties[_i1740]);
                base.own("properties", interface_text(_own1741));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1740 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1740]);
            {
                var _own1742 = RecordOut();
                _own1742.blank_bodies = true;
                _own1742.blank_locs = true;
                _own1742.pending_as_bytes = true;
                _m_PropertyDef_write(_own1742, value.properties[_i1740]);
                base.own("properties", interface_text(_own1742));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1756 = Array<String>();
    for (var _item1750 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1750);
        _hs1756.append(base.hash_of(scratch));
    }
    var _seq1757 = base.sequence("type_uses");
    ulong _bj1758 = 0;
    var _news1759 = Array<ulong>();
    for (var _i1760 in 0.._hs1756.count) {
        if (_bj1758 < _seq1757.count and _hs1756[_i1760] == _seq1757[_bj1758]) {
            _bj1758 += 1;
        } else {
            _news1759.append(_i1760);
        }
    }
    for (var _i1760 in 0.._hs1756.count) {
        next.add_hashed("type_uses", _hs1756[_i1760], _i1760);
    }
    if (_bj1758 == _seq1757.count) {
        out.unsigned(2);
        out.unsigned(_news1759.count);
        for (var _i1760 in _news1759) {
            out.unsigned(_i1760);
            _m_TypeUse_write(out, value.type_uses[_i1760]);
            {
                var _own1761 = RecordOut();
                _own1761.blank_bodies = true;
                _own1761.blank_locs = true;
                _own1761.pending_as_bytes = true;
                _m_TypeUse_write(_own1761, value.type_uses[_i1760]);
                base.own("type_uses", interface_text(_own1761));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1760 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1760]);
            {
                var _own1762 = RecordOut();
                _own1762.blank_bodies = true;
                _own1762.blank_locs = true;
                _own1762.pending_as_bytes = true;
                _m_TypeUse_write(_own1762, value.type_uses[_i1760]);
                base.own("type_uses", interface_text(_own1762));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1776 = Array<String>();
    for (var _item1770 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1770);
        _hs1776.append(base.hash_of(scratch));
    }
    var _seq1777 = base.sequence("use_contexts");
    ulong _bj1778 = 0;
    var _news1779 = Array<ulong>();
    for (var _i1780 in 0.._hs1776.count) {
        if (_bj1778 < _seq1777.count and _hs1776[_i1780] == _seq1777[_bj1778]) {
            _bj1778 += 1;
        } else {
            _news1779.append(_i1780);
        }
    }
    for (var _i1780 in 0.._hs1776.count) {
        next.add_hashed("use_contexts", _hs1776[_i1780], _i1780);
    }
    if (_bj1778 == _seq1777.count) {
        out.unsigned(2);
        out.unsigned(_news1779.count);
        for (var _i1780 in _news1779) {
            out.unsigned(_i1780);
            _m_UseContext_write(out, value.use_contexts[_i1780]);
            {
                var _own1781 = RecordOut();
                _own1781.blank_bodies = true;
                _own1781.blank_locs = true;
                _own1781.pending_as_bytes = true;
                _m_UseContext_write(_own1781, value.use_contexts[_i1780]);
                base.own("use_contexts", interface_text(_own1781));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1780 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1780]);
            {
                var _own1782 = RecordOut();
                _own1782.blank_bodies = true;
                _own1782.blank_locs = true;
                _own1782.pending_as_bytes = true;
                _m_UseContext_write(_own1782, value.use_contexts[_i1780]);
                base.own("use_contexts", interface_text(_own1782));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1792 = base.size("literal_args");
    var _scratch1791 = base.scratch();
    if (value.literal_args.count >= _n1792) {
        for (var _i1793 in 0.._n1792) {
            var (_t1794, _t1795, _t1796) = value.literal_args[_i1793];
            _scratch1791.loc(_t1794);
            _scratch1791.unsigned(_t1795);
            _scratch1791.loc(_t1796);
        }
    }
    if (value.literal_args.count >= _n1792 and base.same_list("literal_args", _scratch1791)) {
        out.unsigned(1);
        out.unsigned(_n1792);
        out.unsigned(value.literal_args.count - _n1792);
        for (var _i1793 in _n1792..value.literal_args.count) {
            var (_t1797, _t1798, _t1799) = value.literal_args[_i1793];
            out.loc(_t1797);
            out.unsigned(_t1798);
            out.loc(_t1799);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1800 in value.literal_args) {
            var (_t1801, _t1802, _t1803) = _item1800;
            out.loc(_t1801);
            out.unsigned(_t1802);
            out.loc(_t1803);
        }
        base.count("literal_args whole", 0);
    }
    var _xscratch1816 = next.scratch();
    for (var _xitem1817 in value.literal_args) {
        var (_t1818, _t1819, _t1820) = _xitem1817;
        _xscratch1816.loc(_t1818);
        _xscratch1816.unsigned(_t1819);
        _xscratch1816.loc(_t1820);
    }
    next.keep_list("literal_args", value.literal_args.count, _xscratch1816);
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1827 = Array<String>();
    for (var _item1821 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1821);
        _hs1827.append(base.hash_of(scratch));
    }
    var _seq1828 = base.sequence("constrained_aliases");
    ulong _bj1829 = 0;
    var _news1830 = Array<ulong>();
    for (var _i1831 in 0.._hs1827.count) {
        if (_bj1829 < _seq1828.count and _hs1827[_i1831] == _seq1828[_bj1829]) {
            _bj1829 += 1;
        } else {
            _news1830.append(_i1831);
        }
    }
    for (var _i1831 in 0.._hs1827.count) {
        next.add_hashed("constrained_aliases", _hs1827[_i1831], _i1831);
    }
    if (_bj1829 == _seq1828.count) {
        out.unsigned(2);
        out.unsigned(_news1830.count);
        for (var _i1831 in _news1830) {
            out.unsigned(_i1831);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1831]);
            {
                var _own1832 = RecordOut();
                _own1832.blank_bodies = true;
                _own1832.blank_locs = true;
                _own1832.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1832, value.constrained_aliases[_i1831]);
                base.own("constrained_aliases", interface_text(_own1832));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1831 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1831]);
            {
                var _own1833 = RecordOut();
                _own1833.blank_bodies = true;
                _own1833.blank_locs = true;
                _own1833.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1833, value.constrained_aliases[_i1831]);
                base.own("constrained_aliases", interface_text(_own1833));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1847 = Array<String>();
    for (var _item1841 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1841);
        _hs1847.append(base.hash_of(scratch));
    }
    var _seq1848 = base.sequence("trait_types");
    ulong _bj1849 = 0;
    var _news1850 = Array<ulong>();
    for (var _i1851 in 0.._hs1847.count) {
        if (_bj1849 < _seq1848.count and _hs1847[_i1851] == _seq1848[_bj1849]) {
            _bj1849 += 1;
        } else {
            _news1850.append(_i1851);
        }
    }
    for (var _i1851 in 0.._hs1847.count) {
        next.add_hashed("trait_types", _hs1847[_i1851], _i1851);
    }
    if (_bj1849 == _seq1848.count) {
        out.unsigned(2);
        out.unsigned(_news1850.count);
        for (var _i1851 in _news1850) {
            out.unsigned(_i1851);
            _m_TraitType_write(out, value.trait_types[_i1851]);
            {
                var _own1852 = RecordOut();
                _own1852.blank_bodies = true;
                _own1852.blank_locs = true;
                _own1852.pending_as_bytes = true;
                _m_TraitType_write(_own1852, value.trait_types[_i1851]);
                base.own("trait_types", interface_text(_own1852));
            }
        }
        base.count("trait_types" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("trait_types" + " whole", 0);
        out.unsigned(value.trait_types.count);
        for (var _i1851 in 0..value.trait_types.count) {
            _m_TraitType_write(out, value.trait_types[_i1851]);
            {
                var _own1853 = RecordOut();
                _own1853.blank_bodies = true;
                _own1853.blank_locs = true;
                _own1853.pending_as_bytes = true;
                _m_TraitType_write(_own1853, value.trait_types[_i1851]);
                base.own("trait_types", interface_text(_own1853));
            }
        }
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    out.unsigned(value.conversions.count);
    for (var _item1861 in value.conversions) {
        _m_Conversion_write(out, _item1861);
    }
    for (var _conv1862 in value.conversions) {
        var _own1863 = RecordOut();
        _own1863.blank_locs = true;
        _m_Conversion_write(_own1863, _conv1862);
        var _h = interface_text(_own1863);
        if (base.find_hashed("conversions", _h) < 0) {
            base.own("conversions", _h);
        }
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1871 = 0;
    var _news1872 = Map<String, Array<String>>();
    for (var (_key1868, _) in value.overload_sets) {
        var _kscratch1869 = base.scratch();
        _kscratch1869.text(_key1868);
        var _vscratch1870 = base.scratch();
        _vscratch1870.unsigned(value.overload_sets[_key1868].count);
        for (var _item1873 in value.overload_sets[_key1868]) {
            _vscratch1870.text(_item1873);
        }
        var _had = base.entry("overload_sets", _kscratch1869, _vscratch1870);
        if (_had >= 0) {
            _kept1871 += 1;
        }
        if (_had != 1) {
            _news1872[_key1868] = value.overload_sets[_key1868];
        }
    }
    if (_kept1871 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1875 = Array<(u8[], u8[], String)>();
        for (var (_key1874, _) in _news1872) {
            var _scratch1876 = out.scratch();
            _scratch1876.text(_key1874);
            var _vscratch1878 = out.scratch();
            _vscratch1878.unsigned(_news1872[_key1874].count);
            for (var _item1879 in _news1872[_key1874]) {
                _vscratch1878.text(_item1879);
            }
            _keys1875.append((_scratch1876.finish(), _vscratch1878.finish(), _key1874));
        }
        _keys1875.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1875.count);
        for (var (_bytes1877, _, _key1874) in _keys1875) {
            out.text(_key1874);
            out.unsigned(_news1872[_key1874].count);
            for (var _item1880 in _news1872[_key1874]) {
                out.text(_item1880);
            }
        }
        for (var (_okey1881, _) in _news1872) {
            var _own1882 = RecordOut();
            _own1882.blank_bodies = true;
            _own1882.blank_locs = true;
            _own1882.pending_as_bytes = true;
            _own1882.text(_okey1881);
            _own1882.unsigned(_news1872[_okey1881].count);
            for (var _item1883 in _news1872[_okey1881]) {
                _own1882.text(_item1883);
            }
            base.own("overload_sets", interface_text(_own1882));
        }
    } else {
        out.unsigned(0);
        var _keys1885 = Array<(u8[], u8[], String)>();
        for (var (_key1884, _) in value.overload_sets) {
            var _scratch1886 = out.scratch();
            _scratch1886.text(_key1884);
            var _vscratch1888 = out.scratch();
            _vscratch1888.unsigned(value.overload_sets[_key1884].count);
            for (var _item1889 in value.overload_sets[_key1884]) {
                _vscratch1888.text(_item1889);
            }
            _keys1885.append((_scratch1886.finish(), _vscratch1888.finish(), _key1884));
        }
        _keys1885.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1885.count);
        for (var (_bytes1887, _, _key1884) in _keys1885) {
            out.text(_key1884);
            out.unsigned(value.overload_sets[_key1884].count);
            for (var _item1890 in value.overload_sets[_key1884]) {
                out.text(_item1890);
            }
        }
        for (var (_okey1891, _) in value.overload_sets) {
            var _own1892 = RecordOut();
            _own1892.blank_bodies = true;
            _own1892.blank_locs = true;
            _own1892.pending_as_bytes = true;
            _own1892.text(_okey1891);
            _own1892.unsigned(value.overload_sets[_okey1891].count);
            for (var _item1893 in value.overload_sets[_okey1891]) {
                _own1892.text(_item1893);
            }
            base.own("overload_sets", interface_text(_own1892));
        }
        base.count("overload_sets whole", 0);
    }
    for (var (_key1868, _) in value.overload_sets) {
        var _kscratch1869 = next.scratch();
        _kscratch1869.text(_key1868);
        var _vscratch1870 = next.scratch();
        _vscratch1870.unsigned(value.overload_sets[_key1868].count);
        for (var _item1907 in value.overload_sets[_key1868]) {
            _vscratch1870.text(_item1907);
        }
        next.keep_entry("overload_sets", _kscratch1869, _vscratch1870);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1911 = 0;
    var _news1912 = Map<String, Array<Array<String>>>();
    for (var (_key1908, _) in value.overload_unions) {
        var _kscratch1909 = base.scratch();
        _kscratch1909.text(_key1908);
        var _vscratch1910 = base.scratch();
        _vscratch1910.unsigned(value.overload_unions[_key1908].count);
        for (var _item1913 in value.overload_unions[_key1908]) {
            _vscratch1910.unsigned(_item1913.count);
            for (var _item1914 in _item1913) {
                _vscratch1910.text(_item1914);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1909, _vscratch1910);
        if (_had >= 0) {
            _kept1911 += 1;
        }
        if (_had != 1) {
            _news1912[_key1908] = value.overload_unions[_key1908];
        }
    }
    if (_kept1911 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1916 = Array<(u8[], u8[], String)>();
        for (var (_key1915, _) in _news1912) {
            var _scratch1917 = out.scratch();
            _scratch1917.text(_key1915);
            var _vscratch1919 = out.scratch();
            _vscratch1919.unsigned(_news1912[_key1915].count);
            for (var _item1920 in _news1912[_key1915]) {
                _vscratch1919.unsigned(_item1920.count);
                for (var _item1921 in _item1920) {
                    _vscratch1919.text(_item1921);
                }
            }
            _keys1916.append((_scratch1917.finish(), _vscratch1919.finish(), _key1915));
        }
        _keys1916.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1916.count);
        for (var (_bytes1918, _, _key1915) in _keys1916) {
            out.text(_key1915);
            out.unsigned(_news1912[_key1915].count);
            for (var _item1922 in _news1912[_key1915]) {
                out.unsigned(_item1922.count);
                for (var _item1923 in _item1922) {
                    out.text(_item1923);
                }
            }
        }
        for (var (_okey1924, _) in _news1912) {
            var _own1925 = RecordOut();
            _own1925.blank_bodies = true;
            _own1925.blank_locs = true;
            _own1925.pending_as_bytes = true;
            _own1925.text(_okey1924);
            _own1925.unsigned(_news1912[_okey1924].count);
            for (var _item1926 in _news1912[_okey1924]) {
                _own1925.unsigned(_item1926.count);
                for (var _item1927 in _item1926) {
                    _own1925.text(_item1927);
                }
            }
            base.own("overload_unions", interface_text(_own1925));
        }
    } else {
        out.unsigned(0);
        var _keys1929 = Array<(u8[], u8[], String)>();
        for (var (_key1928, _) in value.overload_unions) {
            var _scratch1930 = out.scratch();
            _scratch1930.text(_key1928);
            var _vscratch1932 = out.scratch();
            _vscratch1932.unsigned(value.overload_unions[_key1928].count);
            for (var _item1933 in value.overload_unions[_key1928]) {
                _vscratch1932.unsigned(_item1933.count);
                for (var _item1934 in _item1933) {
                    _vscratch1932.text(_item1934);
                }
            }
            _keys1929.append((_scratch1930.finish(), _vscratch1932.finish(), _key1928));
        }
        _keys1929.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1929.count);
        for (var (_bytes1931, _, _key1928) in _keys1929) {
            out.text(_key1928);
            out.unsigned(value.overload_unions[_key1928].count);
            for (var _item1935 in value.overload_unions[_key1928]) {
                out.unsigned(_item1935.count);
                for (var _item1936 in _item1935) {
                    out.text(_item1936);
                }
            }
        }
        for (var (_okey1937, _) in value.overload_unions) {
            var _own1938 = RecordOut();
            _own1938.blank_bodies = true;
            _own1938.blank_locs = true;
            _own1938.pending_as_bytes = true;
            _own1938.text(_okey1937);
            _own1938.unsigned(value.overload_unions[_okey1937].count);
            for (var _item1939 in value.overload_unions[_okey1937]) {
                _own1938.unsigned(_item1939.count);
                for (var _item1940 in _item1939) {
                    _own1938.text(_item1940);
                }
            }
            base.own("overload_unions", interface_text(_own1938));
        }
        base.count("overload_unions whole", 0);
    }
    for (var (_key1908, _) in value.overload_unions) {
        var _kscratch1909 = next.scratch();
        _kscratch1909.text(_key1908);
        var _vscratch1910 = next.scratch();
        _vscratch1910.unsigned(value.overload_unions[_key1908].count);
        for (var _item1958 in value.overload_unions[_key1908]) {
            _vscratch1910.unsigned(_item1958.count);
            for (var _item1959 in _item1958) {
                _vscratch1910.text(_item1959);
            }
        }
        next.keep_entry("overload_unions", _kscratch1909, _vscratch1910);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1963 = 0;
    var _news1964 = Map<String, Map<String, Array<String>>>();
    for (var (_key1960, _) in value.method_overload_sets) {
        var _kscratch1961 = base.scratch();
        _kscratch1961.text(_key1960);
        var _vscratch1962 = base.scratch();
        var _keys1966 = Array<(u8[], u8[], String)>();
        for (var (_key1965, _) in value.method_overload_sets[_key1960]) {
            var _scratch1967 = _vscratch1962.scratch();
            _scratch1967.text(_key1965);
            var _vscratch1969 = _vscratch1962.scratch();
            _vscratch1969.unsigned(value.method_overload_sets[_key1960][_key1965].count);
            for (var _item1970 in value.method_overload_sets[_key1960][_key1965]) {
                _vscratch1969.text(_item1970);
            }
            _keys1966.append((_scratch1967.finish(), _vscratch1969.finish(), _key1965));
        }
        _keys1966.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1962.unsigned(_keys1966.count);
        for (var (_bytes1968, _, _key1965) in _keys1966) {
            _vscratch1962.text(_key1965);
            _vscratch1962.unsigned(value.method_overload_sets[_key1960][_key1965].count);
            for (var _item1971 in value.method_overload_sets[_key1960][_key1965]) {
                _vscratch1962.text(_item1971);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1961, _vscratch1962);
        if (_had >= 0) {
            _kept1963 += 1;
        }
        if (_had != 1) {
            _news1964[_key1960] = value.method_overload_sets[_key1960];
        }
    }
    if (_kept1963 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1973 = Array<(u8[], u8[], String)>();
        for (var (_key1972, _) in _news1964) {
            var _scratch1974 = out.scratch();
            _scratch1974.text(_key1972);
            var _vscratch1976 = out.scratch();
            var _keys1978 = Array<(u8[], u8[], String)>();
            for (var (_key1977, _) in _news1964[_key1972]) {
                var _scratch1979 = _vscratch1976.scratch();
                _scratch1979.text(_key1977);
                var _vscratch1981 = _vscratch1976.scratch();
                _vscratch1981.unsigned(_news1964[_key1972][_key1977].count);
                for (var _item1982 in _news1964[_key1972][_key1977]) {
                    _vscratch1981.text(_item1982);
                }
                _keys1978.append((_scratch1979.finish(), _vscratch1981.finish(), _key1977));
            }
            _keys1978.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1976.unsigned(_keys1978.count);
            for (var (_bytes1980, _, _key1977) in _keys1978) {
                _vscratch1976.text(_key1977);
                _vscratch1976.unsigned(_news1964[_key1972][_key1977].count);
                for (var _item1983 in _news1964[_key1972][_key1977]) {
                    _vscratch1976.text(_item1983);
                }
            }
            _keys1973.append((_scratch1974.finish(), _vscratch1976.finish(), _key1972));
        }
        _keys1973.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1973.count);
        for (var (_bytes1975, _, _key1972) in _keys1973) {
            out.text(_key1972);
            var _keys1985 = Array<(u8[], u8[], String)>();
            for (var (_key1984, _) in _news1964[_key1972]) {
                var _scratch1986 = out.scratch();
                _scratch1986.text(_key1984);
                var _vscratch1988 = out.scratch();
                _vscratch1988.unsigned(_news1964[_key1972][_key1984].count);
                for (var _item1989 in _news1964[_key1972][_key1984]) {
                    _vscratch1988.text(_item1989);
                }
                _keys1985.append((_scratch1986.finish(), _vscratch1988.finish(), _key1984));
            }
            _keys1985.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1985.count);
            for (var (_bytes1987, _, _key1984) in _keys1985) {
                out.text(_key1984);
                out.unsigned(_news1964[_key1972][_key1984].count);
                for (var _item1990 in _news1964[_key1972][_key1984]) {
                    out.text(_item1990);
                }
            }
        }
        for (var (_okey1991, _) in _news1964) {
            var _own1992 = RecordOut();
            _own1992.blank_bodies = true;
            _own1992.blank_locs = true;
            _own1992.pending_as_bytes = true;
            _own1992.text(_okey1991);
            var _keys1994 = Array<(u8[], u8[], String)>();
            for (var (_key1993, _) in _news1964[_okey1991]) {
                var _scratch1995 = _own1992.scratch();
                _scratch1995.text(_key1993);
                var _vscratch1997 = _own1992.scratch();
                _vscratch1997.unsigned(_news1964[_okey1991][_key1993].count);
                for (var _item1998 in _news1964[_okey1991][_key1993]) {
                    _vscratch1997.text(_item1998);
                }
                _keys1994.append((_scratch1995.finish(), _vscratch1997.finish(), _key1993));
            }
            _keys1994.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own1992.unsigned(_keys1994.count);
            for (var (_bytes1996, _, _key1993) in _keys1994) {
                _own1992.text(_key1993);
                _own1992.unsigned(_news1964[_okey1991][_key1993].count);
                for (var _item1999 in _news1964[_okey1991][_key1993]) {
                    _own1992.text(_item1999);
                }
            }
            base.own("method_overload_sets", interface_text(_own1992));
        }
    } else {
        out.unsigned(0);
        var _keys2001 = Array<(u8[], u8[], String)>();
        for (var (_key2000, _) in value.method_overload_sets) {
            var _scratch2002 = out.scratch();
            _scratch2002.text(_key2000);
            var _vscratch2004 = out.scratch();
            var _keys2006 = Array<(u8[], u8[], String)>();
            for (var (_key2005, _) in value.method_overload_sets[_key2000]) {
                var _scratch2007 = _vscratch2004.scratch();
                _scratch2007.text(_key2005);
                var _vscratch2009 = _vscratch2004.scratch();
                _vscratch2009.unsigned(value.method_overload_sets[_key2000][_key2005].count);
                for (var _item2010 in value.method_overload_sets[_key2000][_key2005]) {
                    _vscratch2009.text(_item2010);
                }
                _keys2006.append((_scratch2007.finish(), _vscratch2009.finish(), _key2005));
            }
            _keys2006.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2004.unsigned(_keys2006.count);
            for (var (_bytes2008, _, _key2005) in _keys2006) {
                _vscratch2004.text(_key2005);
                _vscratch2004.unsigned(value.method_overload_sets[_key2000][_key2005].count);
                for (var _item2011 in value.method_overload_sets[_key2000][_key2005]) {
                    _vscratch2004.text(_item2011);
                }
            }
            _keys2001.append((_scratch2002.finish(), _vscratch2004.finish(), _key2000));
        }
        _keys2001.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2001.count);
        for (var (_bytes2003, _, _key2000) in _keys2001) {
            out.text(_key2000);
            var _keys2013 = Array<(u8[], u8[], String)>();
            for (var (_key2012, _) in value.method_overload_sets[_key2000]) {
                var _scratch2014 = out.scratch();
                _scratch2014.text(_key2012);
                var _vscratch2016 = out.scratch();
                _vscratch2016.unsigned(value.method_overload_sets[_key2000][_key2012].count);
                for (var _item2017 in value.method_overload_sets[_key2000][_key2012]) {
                    _vscratch2016.text(_item2017);
                }
                _keys2013.append((_scratch2014.finish(), _vscratch2016.finish(), _key2012));
            }
            _keys2013.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2013.count);
            for (var (_bytes2015, _, _key2012) in _keys2013) {
                out.text(_key2012);
                out.unsigned(value.method_overload_sets[_key2000][_key2012].count);
                for (var _item2018 in value.method_overload_sets[_key2000][_key2012]) {
                    out.text(_item2018);
                }
            }
        }
        for (var (_okey2019, _) in value.method_overload_sets) {
            var _own2020 = RecordOut();
            _own2020.blank_bodies = true;
            _own2020.blank_locs = true;
            _own2020.pending_as_bytes = true;
            _own2020.text(_okey2019);
            var _keys2022 = Array<(u8[], u8[], String)>();
            for (var (_key2021, _) in value.method_overload_sets[_okey2019]) {
                var _scratch2023 = _own2020.scratch();
                _scratch2023.text(_key2021);
                var _vscratch2025 = _own2020.scratch();
                _vscratch2025.unsigned(value.method_overload_sets[_okey2019][_key2021].count);
                for (var _item2026 in value.method_overload_sets[_okey2019][_key2021]) {
                    _vscratch2025.text(_item2026);
                }
                _keys2022.append((_scratch2023.finish(), _vscratch2025.finish(), _key2021));
            }
            _keys2022.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own2020.unsigned(_keys2022.count);
            for (var (_bytes2024, _, _key2021) in _keys2022) {
                _own2020.text(_key2021);
                _own2020.unsigned(value.method_overload_sets[_okey2019][_key2021].count);
                for (var _item2027 in value.method_overload_sets[_okey2019][_key2021]) {
                    _own2020.text(_item2027);
                }
            }
            base.own("method_overload_sets", interface_text(_own2020));
        }
        base.count("method_overload_sets whole", 0);
    }
    for (var (_key1960, _) in value.method_overload_sets) {
        var _kscratch1961 = next.scratch();
        _kscratch1961.text(_key1960);
        var _vscratch1962 = next.scratch();
        var _keys2048 = Array<(u8[], u8[], String)>();
        for (var (_key2047, _) in value.method_overload_sets[_key1960]) {
            var _scratch2049 = _vscratch1962.scratch();
            _scratch2049.text(_key2047);
            var _vscratch2051 = _vscratch1962.scratch();
            _vscratch2051.unsigned(value.method_overload_sets[_key1960][_key2047].count);
            for (var _item2052 in value.method_overload_sets[_key1960][_key2047]) {
                _vscratch2051.text(_item2052);
            }
            _keys2048.append((_scratch2049.finish(), _vscratch2051.finish(), _key2047));
        }
        _keys2048.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1962.unsigned(_keys2048.count);
        for (var (_bytes2050, _, _key2047) in _keys2048) {
            _vscratch1962.text(_key2047);
            _vscratch1962.unsigned(value.method_overload_sets[_key1960][_key2047].count);
            for (var _item2053 in value.method_overload_sets[_key1960][_key2047]) {
                _vscratch1962.text(_item2053);
            }
        }
        next.keep_entry("method_overload_sets", _kscratch1961, _vscratch1962);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2058 = 0;
    var _news2059 = HashSet<Loc>();
    for (var _key2055 in value.private_functions) {
        var _kscratch2056 = base.scratch();
        _kscratch2056.loc(_key2055);
        var _vscratch2057 = base.scratch();
        var _had = base.entry("private_functions", _kscratch2056, _vscratch2057);
        if (_had >= 0) {
            _kept2058 += 1;
        }
        if (_had != 1) {
            _news2059.insert(_key2055);
        }
    }
    if (_kept2058 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys2061 = Array<(u8[], u8[], Loc)>();
        for (var _key2060 in _news2059) {
            var _scratch2062 = out.scratch();
            _scratch2062.loc(_key2060);
            var _vscratch2064 = out.scratch();
            _keys2061.append((_scratch2062.finish(), _vscratch2064.finish(), _key2060));
        }
        _keys2061.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2061.count);
        for (var (_bytes2063, _, _key2060) in _keys2061) {
            out.loc(_key2060);
        }
        for (var _okey2065 in _news2059) {
            var _own2066 = RecordOut();
            _own2066.blank_bodies = true;
            _own2066.blank_locs = true;
            _own2066.pending_as_bytes = true;
            _own2066.loc(_okey2065);
            base.own("private_functions", interface_text(_own2066));
        }
    } else {
        out.unsigned(0);
        var _keys2068 = Array<(u8[], u8[], Loc)>();
        for (var _key2067 in value.private_functions) {
            var _scratch2069 = out.scratch();
            _scratch2069.loc(_key2067);
            var _vscratch2071 = out.scratch();
            _keys2068.append((_scratch2069.finish(), _vscratch2071.finish(), _key2067));
        }
        _keys2068.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2068.count);
        for (var (_bytes2070, _, _key2067) in _keys2068) {
            out.loc(_key2067);
        }
        for (var _okey2072 in value.private_functions) {
            var _own2073 = RecordOut();
            _own2073.blank_bodies = true;
            _own2073.blank_locs = true;
            _own2073.pending_as_bytes = true;
            _own2073.loc(_okey2072);
            base.own("private_functions", interface_text(_own2073));
        }
        base.count("private_functions whole", 0);
    }
    for (var _key2055 in value.private_functions) {
        var _kscratch2056 = next.scratch();
        _kscratch2056.loc(_key2055);
        var _vscratch2057 = next.scratch();
        next.keep_entry("private_functions", _kscratch2056, _vscratch2057);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2084 = 0;
    var _news2085 = HashSet<Loc>();
    for (var _key2081 in value.file_private_functions) {
        var _kscratch2082 = base.scratch();
        _kscratch2082.loc(_key2081);
        var _vscratch2083 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch2082, _vscratch2083);
        if (_had >= 0) {
            _kept2084 += 1;
        }
        if (_had != 1) {
            _news2085.insert(_key2081);
        }
    }
    if (_kept2084 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys2087 = Array<(u8[], u8[], Loc)>();
        for (var _key2086 in _news2085) {
            var _scratch2088 = out.scratch();
            _scratch2088.loc(_key2086);
            var _vscratch2090 = out.scratch();
            _keys2087.append((_scratch2088.finish(), _vscratch2090.finish(), _key2086));
        }
        _keys2087.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2087.count);
        for (var (_bytes2089, _, _key2086) in _keys2087) {
            out.loc(_key2086);
        }
        for (var _okey2091 in _news2085) {
            var _own2092 = RecordOut();
            _own2092.blank_bodies = true;
            _own2092.blank_locs = true;
            _own2092.pending_as_bytes = true;
            _own2092.loc(_okey2091);
            base.own("file_private_functions", interface_text(_own2092));
        }
    } else {
        out.unsigned(0);
        var _keys2094 = Array<(u8[], u8[], Loc)>();
        for (var _key2093 in value.file_private_functions) {
            var _scratch2095 = out.scratch();
            _scratch2095.loc(_key2093);
            var _vscratch2097 = out.scratch();
            _keys2094.append((_scratch2095.finish(), _vscratch2097.finish(), _key2093));
        }
        _keys2094.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2094.count);
        for (var (_bytes2096, _, _key2093) in _keys2094) {
            out.loc(_key2093);
        }
        for (var _okey2098 in value.file_private_functions) {
            var _own2099 = RecordOut();
            _own2099.blank_bodies = true;
            _own2099.blank_locs = true;
            _own2099.pending_as_bytes = true;
            _own2099.loc(_okey2098);
            base.own("file_private_functions", interface_text(_own2099));
        }
        base.count("file_private_functions whole", 0);
    }
    for (var _key2081 in value.file_private_functions) {
        var _kscratch2082 = next.scratch();
        _kscratch2082.loc(_key2081);
        var _vscratch2083 = next.scratch();
        next.keep_entry("file_private_functions", _kscratch2082, _vscratch2083);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n2109 = base.size("call_targets");
    var _scratch2108 = base.scratch();
    if (value.call_targets.count >= _n2109) {
        for (var _i2110 in 0.._n2109) {
            var (_t2111, _t2112) = value.call_targets[_i2110];
            _scratch2108.loc(_t2111);
            _scratch2108.text(_t2112);
        }
    }
    if (value.call_targets.count >= _n2109 and base.same_list("call_targets", _scratch2108)) {
        out.unsigned(1);
        out.unsigned(_n2109);
        out.unsigned(value.call_targets.count - _n2109);
        for (var _i2110 in _n2109..value.call_targets.count) {
            var (_t2113, _t2114) = value.call_targets[_i2110];
            out.loc(_t2113);
            out.text(_t2114);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item2115 in value.call_targets) {
            var (_t2116, _t2117) = _item2115;
            out.loc(_t2116);
            out.text(_t2117);
        }
        base.count("call_targets whole", 0);
    }
    var _xscratch2128 = next.scratch();
    for (var _xitem2129 in value.call_targets) {
        var (_t2130, _t2131) = _xitem2129;
        _xscratch2128.loc(_t2130);
        _xscratch2128.text(_t2131);
    }
    next.keep_list("call_targets", value.call_targets.count, _xscratch2128);
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2134 = 0;
    var _news2135 = Array<(Loc, String)>();
    for (var _item2132 in value.argument_names) {
        var _escratch2133 = base.scratch();
        var (_t2136, _t2137) = _item2132;
        _escratch2133.loc(_t2136);
        _escratch2133.text(_t2137);
        if (base.entry("argument_names", _escratch2133, base.scratch()) >= 0) {
            _kept2134 += 1;
        } else {
            _news2135.append(_item2132);
        }
    }
    if (_kept2134 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2135.count);
        for (var _item2138 in _news2135) {
            var (_t2139, _t2140) = _item2138;
            out.loc(_t2139);
            out.text(_t2140);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2141 in value.argument_names) {
            var (_t2142, _t2143) = _item2141;
            out.loc(_t2142);
            out.text(_t2143);
        }
        base.count("argument_names whole", 0);
    }
    for (var _item2132 in value.argument_names) {
        var _escratch2133 = next.scratch();
        var (_t2154, _t2155) = _item2132;
        _escratch2133.loc(_t2154);
        _escratch2133.text(_t2155);
        next.keep_entry("argument_names", _escratch2133, next.scratch());
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2158 = base.size("namespaces");
    var _scratch2157 = base.scratch();
    if (value.namespaces.count >= _n2158) {
        for (var _i2159 in 0.._n2158) {
            _scratch2157.text(value.namespaces[_i2159]);
        }
    }
    if (value.namespaces.count >= _n2158 and base.same_list("namespaces", _scratch2157)) {
        out.unsigned(1);
        out.unsigned(_n2158);
        out.unsigned(value.namespaces.count - _n2158);
        for (var _i2159 in _n2158..value.namespaces.count) {
            out.text(value.namespaces[_i2159]);
            {
                var _own2160 = RecordOut();
                _own2160.blank_bodies = true;
                _own2160.blank_locs = true;
                _own2160.pending_as_bytes = true;
                _own2160.text(value.namespaces[_i2159]);
                base.own("namespaces", interface_text(_own2160));
            }
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2161 in value.namespaces) {
            out.text(_item2161);
        }
        for (var _i2159 in 0..value.namespaces.count) {
            {
                var _own2162 = RecordOut();
                _own2162.blank_bodies = true;
                _own2162.blank_locs = true;
                _own2162.pending_as_bytes = true;
                _own2162.text(value.namespaces[_i2159]);
                base.own("namespaces", interface_text(_own2162));
            }
        }
        base.count("namespaces whole", 0);
    }
    var _xscratch2169 = next.scratch();
    for (var _xitem2170 in value.namespaces) {
        _xscratch2169.text(_xitem2170);
    }
    next.keep_list("namespaces", value.namespaces.count, _xscratch2169);
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2173 = base.size("cached_files");
    var _scratch2172 = base.scratch();
    if (value.cached_files.count >= _n2173) {
        for (var _i2174 in 0.._n2173) {
            _scratch2172.flag(value.cached_files[_i2174]);
        }
    }
    if (value.cached_files.count >= _n2173 and base.same_list("cached_files", _scratch2172)) {
        out.unsigned(1);
        out.unsigned(_n2173);
        out.unsigned(value.cached_files.count - _n2173);
        for (var _i2174 in _n2173..value.cached_files.count) {
            out.flag(value.cached_files[_i2174]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2175 in value.cached_files) {
            out.flag(_item2175);
        }
        base.count("cached_files whole", 0);
    }
    var _xscratch2182 = next.scratch();
    for (var _xitem2183 in value.cached_files) {
        _xscratch2182.flag(_xitem2183);
    }
    next.keep_list("cached_files", value.cached_files.count, _xscratch2182);
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2187 = 0;
    var _news2188 = HashMap<Loc, String>();
    for (var (_key2184, _) in value.recorded_summaries) {
        var _kscratch2185 = base.scratch();
        _kscratch2185.loc(_key2184);
        var _vscratch2186 = base.scratch();
        _vscratch2186.text(value.recorded_summaries[_key2184]);
        var _had = base.entry("recorded_summaries", _kscratch2185, _vscratch2186);
        if (_had >= 0) {
            _kept2187 += 1;
        }
        if (_had != 1) {
            _news2188[_key2184] = value.recorded_summaries[_key2184];
        }
    }
    if (_kept2187 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2190 = Array<(u8[], u8[], Loc)>();
        for (var (_key2189, _) in _news2188) {
            var _scratch2191 = out.scratch();
            _scratch2191.loc(_key2189);
            var _vscratch2193 = out.scratch();
            _vscratch2193.text(_news2188[_key2189]);
            _keys2190.append((_scratch2191.finish(), _vscratch2193.finish(), _key2189));
        }
        _keys2190.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2190.count);
        for (var (_bytes2192, _, _key2189) in _keys2190) {
            out.loc(_key2189);
            out.text(_news2188[_key2189]);
        }
    } else {
        out.unsigned(0);
        var _keys2195 = Array<(u8[], u8[], Loc)>();
        for (var (_key2194, _) in value.recorded_summaries) {
            var _scratch2196 = out.scratch();
            _scratch2196.loc(_key2194);
            var _vscratch2198 = out.scratch();
            _vscratch2198.text(value.recorded_summaries[_key2194]);
            _keys2195.append((_scratch2196.finish(), _vscratch2198.finish(), _key2194));
        }
        _keys2195.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2195.count);
        for (var (_bytes2197, _, _key2194) in _keys2195) {
            out.loc(_key2194);
            out.text(value.recorded_summaries[_key2194]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2211 = 0;
    var _news2212 = HashSet<Loc>();
    for (var _key2208 in value.stripped) {
        var _kscratch2209 = base.scratch();
        _kscratch2209.loc(_key2208);
        var _vscratch2210 = base.scratch();
        var _had = base.entry("stripped", _kscratch2209, _vscratch2210);
        if (_had >= 0) {
            _kept2211 += 1;
        }
        if (_had != 1) {
            _news2212.insert(_key2208);
        }
    }
    if (_kept2211 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2214 = Array<(u8[], u8[], Loc)>();
        for (var _key2213 in _news2212) {
            var _scratch2215 = out.scratch();
            _scratch2215.loc(_key2213);
            var _vscratch2217 = out.scratch();
            _keys2214.append((_scratch2215.finish(), _vscratch2217.finish(), _key2213));
        }
        _keys2214.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2214.count);
        for (var (_bytes2216, _, _key2213) in _keys2214) {
            out.loc(_key2213);
        }
    } else {
        out.unsigned(0);
        var _keys2219 = Array<(u8[], u8[], Loc)>();
        for (var _key2218 in value.stripped) {
            var _scratch2220 = out.scratch();
            _scratch2220.loc(_key2218);
            var _vscratch2222 = out.scratch();
            _keys2219.append((_scratch2220.finish(), _vscratch2222.finish(), _key2218));
        }
        _keys2219.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2219.count);
        for (var (_bytes2221, _, _key2218) in _keys2219) {
            out.loc(_key2218);
        }
        base.count("stripped whole", 0);
    }
    for (var _key2208 in value.stripped) {
        var _kscratch2209 = next.scratch();
        _kscratch2209.loc(_key2208);
        var _vscratch2210 = next.scratch();
        next.keep_entry("stripped", _kscratch2209, _vscratch2210);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _hs2232 = Array<String>();
    for (var _item2230 in value.templates.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item2230);
        _hs2232.append(base.hash_of(scratch));
    }
    var _seq2233 = base.sequence("t");
    var _seqn2234 = base.sequence("t#");
    ulong _bj2235 = 0;
    var _news2236 = Array<ulong>();
    var _patches2237 = Array<(ulong, ulong)>();
    for (var _i2238 in 0.._hs2232.count) {
        if (_bj2235 < _seq2233.count and _hs2232[_i2238] == _seq2233[_bj2235]) {
            _bj2235 += 1;
        } else if (_bj2235 < _seq2233.count
            and _bj2235 < _seqn2234.count
            and value.templates.structs[_i2238].name == _seqn2234[_bj2235]) {
            _patches2237.append((_i2238, _bj2235));
            _bj2235 += 1;
        } else {
            _news2236.append(_i2238);
        }
    }
    if (_bj2235 == _seq2233.count) {
        out.unsigned(2);
        out.unsigned(_patches2237.count);
        for (var (_i2238, _b) in _patches2237) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2238].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2238], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2239 = RecordOut();
                _own2239.blank_bodies = false;
                _own2239.blank_locs = true;
                _own2239.pending_as_bytes = true;
                _m_StructDef_write(_own2239, value.templates.structs[_i2238]);
                base.own("templates structs", interface_text(_own2239));
            }
        }
        out.unsigned(_news2236.count);
        for (var _i2238 in _news2236) {
            ulong _before = out.values.count;
            out.unsigned(_i2238);
            _m_StructDef_write(out, value.templates.structs[_i2238]);
            base.count("t new", out.values.count - _before);
            {
                var _own2240 = RecordOut();
                _own2240.blank_bodies = false;
                _own2240.blank_locs = true;
                _own2240.pending_as_bytes = true;
                _m_StructDef_write(_own2240, value.templates.structs[_i2238]);
                base.own("templates structs", interface_text(_own2240));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2231 = HashSet<long>();
        out.unsigned(value.templates.structs.count);
        for (var _i2238 in 0..value.templates.structs.count) {
            var _item2230 = value.templates.structs[_i2238];
            var at = base.find_hashed("t", _hs2232[_i2238]);
            var named = base.named("t", _item2230.name);
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2231.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2231.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2230, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2230);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2231.count);
    }
    for (var _i2238 in 0.._hs2232.count) {
        next.add_hashed("t", _hs2232[_i2238], _i2238);
        next.name("t", value.templates.structs[_i2238].name, _i2238);
        _patch_t_index(value.templates.structs[_i2238], next, _i2238);
    }
    var _hs2255 = Array<String>();
    for (var _item2249 in value.templates.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2249);
        _hs2255.append(base.hash_of(scratch));
    }
    var _seq2256 = base.sequence("tf");
    ulong _bj2257 = 0;
    var _news2258 = Array<ulong>();
    var _changed2250 = Array<(ulong, ulong)>();
    var _seqn2251 = base.sequence("tf" + "#");
    for (var _i2259 in 0.._hs2255.count) {
        if (_bj2257 < _seq2256.count and _hs2255[_i2259] == _seq2256[_bj2257]) {
            _bj2257 += 1;
        } else if (_bj2257 < _seqn2251.count and value.templates.functions[_i2259].name == _seqn2251[_bj2257]) {
            _changed2250.append((_i2259, _bj2257));
            _bj2257 += 1;
        } else {
            _news2258.append(_i2259);
        }
    }
    for (var _i2259 in 0.._hs2255.count) {
        next.add_hashed("tf", _hs2255[_i2259], _i2259);
        next.name("tf", value.templates.functions[_i2259].name, _i2259);
    }
    if (_bj2257 == _seq2256.count) {
        out.unsigned(2);
        out.unsigned(_changed2250.count);
        for (var (_i2259, _b) in _changed2250) {
            out.text(value.templates.functions[_i2259].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2259]);
            {
                var _own2260 = RecordOut();
                _own2260.blank_bodies = false;
                _own2260.blank_locs = true;
                _own2260.pending_as_bytes = true;
                _m_FunctionDef_write(_own2260, value.templates.functions[_i2259]);
                base.own("templates functions", interface_text(_own2260));
            }
        }
        base.count("tf" + " changed", _changed2250.count);
        out.unsigned(_news2258.count);
        for (var _i2259 in _news2258) {
            out.unsigned(_i2259);
            _m_FunctionDef_write(out, value.templates.functions[_i2259]);
            {
                var _own2261 = RecordOut();
                _own2261.blank_bodies = false;
                _own2261.blank_locs = true;
                _own2261.pending_as_bytes = true;
                _m_FunctionDef_write(_own2261, value.templates.functions[_i2259]);
                base.own("templates functions", interface_text(_own2261));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2259 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2259]);
            {
                var _own2262 = RecordOut();
                _own2262.blank_bodies = false;
                _own2262.blank_locs = true;
                _own2262.pending_as_bytes = true;
                _m_FunctionDef_write(_own2262, value.templates.functions[_i2259]);
                base.own("templates functions", interface_text(_own2262));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    next.keep_checked(value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2275 = 0;
    var _news2276 = HashMap<String, SpecRequest>();
    for (var (_key2272, _) in value.spec_requests) {
        var _kscratch2273 = base.scratch();
        _kscratch2273.text(_key2272);
        var _vscratch2274 = base.scratch();
        _m_SpecRequest_write(_vscratch2274, value.spec_requests[_key2272]);
        var _had = base.entry("spec_requests", _kscratch2273, _vscratch2274);
        if (_had >= 0) {
            _kept2275 += 1;
        }
        if (_had != 1) {
            _news2276[_key2272] = value.spec_requests[_key2272];
        }
    }
    if (_kept2275 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2278 = Array<(u8[], u8[], String)>();
        for (var (_key2277, _) in _news2276) {
            var _scratch2279 = out.scratch();
            _scratch2279.text(_key2277);
            var _vscratch2281 = out.scratch();
            _m_SpecRequest_write(_vscratch2281, _news2276[_key2277]);
            _keys2278.append((_scratch2279.finish(), _vscratch2281.finish(), _key2277));
        }
        _keys2278.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2278.count);
        for (var (_bytes2280, _, _key2277) in _keys2278) {
            out.text(_key2277);
            _m_SpecRequest_write(out, _news2276[_key2277]);
        }
        for (var (_okey2282, _) in _news2276) {
            var _own2283 = RecordOut();
            _own2283.blank_bodies = true;
            _own2283.blank_locs = true;
            _own2283.pending_as_bytes = true;
            _own2283.text(_okey2282);
            _m_SpecRequest_write(_own2283, _news2276[_okey2282]);
            base.own("spec_requests", interface_text(_own2283));
        }
    } else {
        out.unsigned(0);
        var _keys2285 = Array<(u8[], u8[], String)>();
        for (var (_key2284, _) in value.spec_requests) {
            var _scratch2286 = out.scratch();
            _scratch2286.text(_key2284);
            var _vscratch2288 = out.scratch();
            _m_SpecRequest_write(_vscratch2288, value.spec_requests[_key2284]);
            _keys2285.append((_scratch2286.finish(), _vscratch2288.finish(), _key2284));
        }
        _keys2285.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2285.count);
        for (var (_bytes2287, _, _key2284) in _keys2285) {
            out.text(_key2284);
            _m_SpecRequest_write(out, value.spec_requests[_key2284]);
        }
        for (var (_okey2289, _) in value.spec_requests) {
            var _own2290 = RecordOut();
            _own2290.blank_bodies = true;
            _own2290.blank_locs = true;
            _own2290.pending_as_bytes = true;
            _own2290.text(_okey2289);
            _m_SpecRequest_write(_own2290, value.spec_requests[_okey2289]);
            base.own("spec_requests", interface_text(_own2290));
        }
        base.count("spec_requests whole", 0);
    }
    for (var (_key2272, _) in value.spec_requests) {
        var _kscratch2273 = next.scratch();
        _kscratch2273.text(_key2272);
        var _vscratch2274 = next.scratch();
        _m_SpecRequest_write(_vscratch2274, value.spec_requests[_key2272]);
        next.keep_entry("spec_requests", _kscratch2273, _vscratch2274);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2303 = base.size("summaries_to_record");
    var _scratch2302 = base.scratch();
    if (value.summaries_to_record.count >= _n2303) {
        for (var _i2304 in 0.._n2303) {
            var (_t2305, _t2306) = value.summaries_to_record[_i2304];
            _scratch2302.loc(_t2305);
            _scratch2302.text(_t2306);
        }
    }
    if (value.summaries_to_record.count >= _n2303 and base.same_list("summaries_to_record", _scratch2302)) {
        out.unsigned(1);
        out.unsigned(_n2303);
        out.unsigned(value.summaries_to_record.count - _n2303);
        for (var _i2304 in _n2303..value.summaries_to_record.count) {
            var (_t2307, _t2308) = value.summaries_to_record[_i2304];
            out.loc(_t2307);
            out.text(_t2308);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2309 in value.summaries_to_record) {
            var (_t2310, _t2311) = _item2309;
            out.loc(_t2310);
            out.text(_t2311);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2329 = 0;
    var _news2330 = HashMap<String, Array<bool>>();
    for (var (_key2326, _) in value.caller_copies) {
        var _kscratch2327 = base.scratch();
        _kscratch2327.text(_key2326);
        var _vscratch2328 = base.scratch();
        _vscratch2328.unsigned(value.caller_copies[_key2326].count);
        for (var _item2331 in value.caller_copies[_key2326]) {
            _vscratch2328.flag(_item2331);
        }
        var _had = base.entry("caller_copies", _kscratch2327, _vscratch2328);
        if (_had >= 0) {
            _kept2329 += 1;
        }
        if (_had != 1) {
            _news2330[_key2326] = value.caller_copies[_key2326];
        }
    }
    if (_kept2329 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2333 = Array<(u8[], u8[], String)>();
        for (var (_key2332, _) in _news2330) {
            var _scratch2334 = out.scratch();
            _scratch2334.text(_key2332);
            var _vscratch2336 = out.scratch();
            _vscratch2336.unsigned(_news2330[_key2332].count);
            for (var _item2337 in _news2330[_key2332]) {
                _vscratch2336.flag(_item2337);
            }
            _keys2333.append((_scratch2334.finish(), _vscratch2336.finish(), _key2332));
        }
        _keys2333.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2333.count);
        for (var (_bytes2335, _, _key2332) in _keys2333) {
            out.text(_key2332);
            out.unsigned(_news2330[_key2332].count);
            for (var _item2338 in _news2330[_key2332]) {
                out.flag(_item2338);
            }
        }
        for (var (_okey2339, _) in _news2330) {
            var _own2340 = RecordOut();
            _own2340.blank_bodies = true;
            _own2340.blank_locs = true;
            _own2340.pending_as_bytes = true;
            _own2340.text(_okey2339);
            _own2340.unsigned(_news2330[_okey2339].count);
            for (var _item2341 in _news2330[_okey2339]) {
                _own2340.flag(_item2341);
            }
            base.own("caller_copies", interface_text(_own2340));
        }
    } else {
        out.unsigned(0);
        var _keys2343 = Array<(u8[], u8[], String)>();
        for (var (_key2342, _) in value.caller_copies) {
            var _scratch2344 = out.scratch();
            _scratch2344.text(_key2342);
            var _vscratch2346 = out.scratch();
            _vscratch2346.unsigned(value.caller_copies[_key2342].count);
            for (var _item2347 in value.caller_copies[_key2342]) {
                _vscratch2346.flag(_item2347);
            }
            _keys2343.append((_scratch2344.finish(), _vscratch2346.finish(), _key2342));
        }
        _keys2343.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2343.count);
        for (var (_bytes2345, _, _key2342) in _keys2343) {
            out.text(_key2342);
            out.unsigned(value.caller_copies[_key2342].count);
            for (var _item2348 in value.caller_copies[_key2342]) {
                out.flag(_item2348);
            }
        }
        for (var (_okey2349, _) in value.caller_copies) {
            var _own2350 = RecordOut();
            _own2350.blank_bodies = true;
            _own2350.blank_locs = true;
            _own2350.pending_as_bytes = true;
            _own2350.text(_okey2349);
            _own2350.unsigned(value.caller_copies[_okey2349].count);
            for (var _item2351 in value.caller_copies[_okey2349]) {
                _own2350.flag(_item2351);
            }
            base.own("caller_copies", interface_text(_own2350));
        }
        base.count("caller_copies whole", 0);
    }
    for (var (_key2326, _) in value.caller_copies) {
        var _kscratch2327 = next.scratch();
        _kscratch2327.text(_key2326);
        var _vscratch2328 = next.scratch();
        _vscratch2328.unsigned(value.caller_copies[_key2326].count);
        for (var _item2365 in value.caller_copies[_key2326]) {
            _vscratch2328.flag(_item2365);
        }
        next.keep_entry("caller_copies", _kscratch2327, _vscratch2328);
    }
    base.stat("caller_copies", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.linked);
    base.stat("linked", out.values.count - _mark);
    _mark = out.values.count;
}

_m_Module_read_delta(input: RecordIn, base: Module): Module {
    var _f1493 = Array<ast.Import>();
    var _mode1496 = input.unsigned();
    if (_mode1496 == 2) {
        var _changed1481 = HashMap<ulong, ast.Import>();
        ulong _bi1497 = 0;
        var _n1494 = input.count();
        for (var _ in 0.._n1494) {
            var _at1498 = input.unsigned();
            while (_f1493.count < _at1498 or (input.merging and _bi1497 < base.imports.count)) {
                var _c = _changed1481.try_get(_bi1497);
                _f1493.append(_c.is_value() ? _c.value() : base.imports[_bi1497]);
                _bi1497 += 1;
            }
            _f1493.append(_a_Import_read(input));
        }
        while (_bi1497 < base.imports.count) {
            var _c = _changed1481.try_get(_bi1497);
            _f1493.append(_c.is_value() ? _c.value() : base.imports[_bi1497]);
            _bi1497 += 1;
        }
    } else if (_mode1496 == 3) {
        var _n1494 = input.count();
        for (var _ in 0.._n1494) {
            _f1493.append(_a_Import_read(input));
        }
    } else {
        var _n1494 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1494) {
            var _tag1495 = input.unsigned();
            if (_tag1495 & 1 == 1) {
                if (!input.merging) {
                    _f1493.append(base.imports[_tag1495 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1493.append(_read);
                }
            }
        }
    }
    var _f1511 = Array<StructDef>();
    var _mode1514 = input.unsigned();
    if (_mode1514 == 2) {
        var _patched1517 = HashMap<ulong, StructDef>();
        var _n1512 = input.count();
        for (var _ in 0.._n1512) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1517[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1515 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1516 = input.unsigned();
            while (_f1511.count < _at1516 or (input.merging and _bi1515 < base.structs.count)) {
                var _p = _patched1517.try_get(_bi1515);
                _f1511.append(_p.is_value() ? _p.value() : base.structs[_bi1515]);
                _bi1515 += 1;
            }
            _f1511.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1515 < base.structs.count) {
            var _p = _patched1517.try_get(_bi1515);
            _f1511.append(_p.is_value() ? _p.value() : base.structs[_bi1515]);
            _bi1515 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1512 = input.count();
        for (var _ in 0.._n1512) {
            var _tag1513 = input.unsigned();
            if (_tag1513 & 1 == 1) {
                _f1511.append(base.structs[(_tag1513 >> 1) < base.structs.count ? _tag1513 >> 1 : 0]);
            } else if (_tag1513 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1511.append(_patch_s_read(input, _was));
            } else {
                _f1511.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1532 = Array<TraitDef>();
    var _mode1535 = input.unsigned();
    if (_mode1535 == 2) {
        var _changed1520 = HashMap<ulong, TraitDef>();
        ulong _bi1536 = 0;
        var _n1533 = input.count();
        for (var _ in 0.._n1533) {
            var _at1537 = input.unsigned();
            while (_f1532.count < _at1537 or (input.merging and _bi1536 < base.traits.count)) {
                var _c = _changed1520.try_get(_bi1536);
                _f1532.append(_c.is_value() ? _c.value() : base.traits[_bi1536]);
                _bi1536 += 1;
            }
            _f1532.append(_m_TraitDef_read(input));
        }
        while (_bi1536 < base.traits.count) {
            var _c = _changed1520.try_get(_bi1536);
            _f1532.append(_c.is_value() ? _c.value() : base.traits[_bi1536]);
            _bi1536 += 1;
        }
    } else if (_mode1535 == 3) {
        var _n1533 = input.count();
        for (var _ in 0.._n1533) {
            _f1532.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1533 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1533) {
            var _tag1534 = input.unsigned();
            if (_tag1534 & 1 == 1) {
                if (!input.merging) {
                    _f1532.append(base.traits[_tag1534 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1532.append(_read);
                }
            }
        }
    }
    var _f1552 = Array<ExtensionDef>();
    var _mode1555 = input.unsigned();
    if (_mode1555 == 2) {
        var _changed1540 = HashMap<ulong, ExtensionDef>();
        ulong _bi1556 = 0;
        var _n1553 = input.count();
        for (var _ in 0.._n1553) {
            var _at1557 = input.unsigned();
            while (_f1552.count < _at1557 or (input.merging and _bi1556 < base.extensions.count)) {
                var _c = _changed1540.try_get(_bi1556);
                _f1552.append(_c.is_value() ? _c.value() : base.extensions[_bi1556]);
                _bi1556 += 1;
            }
            _f1552.append(_m_ExtensionDef_read(input));
        }
        while (_bi1556 < base.extensions.count) {
            var _c = _changed1540.try_get(_bi1556);
            _f1552.append(_c.is_value() ? _c.value() : base.extensions[_bi1556]);
            _bi1556 += 1;
        }
    } else if (_mode1555 == 3) {
        var _n1553 = input.count();
        for (var _ in 0.._n1553) {
            _f1552.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1553 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1553) {
            var _tag1554 = input.unsigned();
            if (_tag1554 & 1 == 1) {
                if (!input.merging) {
                    _f1552.append(base.extensions[_tag1554 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1552.append(_read);
                }
            }
        }
    }
    var _f1573 = Array<FunctionDef>();
    var _mode1576 = input.unsigned();
    if (_mode1576 == 2) {
        var _changed1560 = HashMap<ulong, FunctionDef>();
        var _nc1562 = input.count();
        for (var _ in 0.._nc1562) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = base.functions.count;
                for (var _k in 0..base.functions.count) {
                    if (base.functions[_k].name == _name) {
                        _slot = _k;
                        break;
                    }
                }
            }
            var _el = _m_FunctionDef_read_lazy(input);
            if (_slot < base.functions.count) {
                _changed1560[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1577 = 0;
        var _n1574 = input.count();
        for (var _ in 0.._n1574) {
            var _at1578 = input.unsigned();
            while (_f1573.count < _at1578 or (input.merging and _bi1577 < base.functions.count)) {
                var _c = _changed1560.try_get(_bi1577);
                _f1573.append(_c.is_value() ? _c.value() : base.functions[_bi1577]);
                _bi1577 += 1;
            }
            _f1573.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1577 < base.functions.count) {
            var _c = _changed1560.try_get(_bi1577);
            _f1573.append(_c.is_value() ? _c.value() : base.functions[_bi1577]);
            _bi1577 += 1;
        }
    } else if (_mode1576 == 3) {
        var _n1574 = input.count();
        for (var _ in 0.._n1574) {
            _f1573.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1574 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1574) {
            var _tag1575 = input.unsigned();
            if (_tag1575 & 1 == 1) {
                if (!input.merging) {
                    _f1573.append(base.functions[_tag1575 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1573.append(_read);
                }
            }
        }
    }
    var _f1593 = Array<ExternDef>();
    var _mode1596 = input.unsigned();
    if (_mode1596 == 2) {
        var _changed1581 = HashMap<ulong, ExternDef>();
        ulong _bi1597 = 0;
        var _n1594 = input.count();
        for (var _ in 0.._n1594) {
            var _at1598 = input.unsigned();
            while (_f1593.count < _at1598 or (input.merging and _bi1597 < base.externs.count)) {
                var _c = _changed1581.try_get(_bi1597);
                _f1593.append(_c.is_value() ? _c.value() : base.externs[_bi1597]);
                _bi1597 += 1;
            }
            _f1593.append(_m_ExternDef_read(input));
        }
        while (_bi1597 < base.externs.count) {
            var _c = _changed1581.try_get(_bi1597);
            _f1593.append(_c.is_value() ? _c.value() : base.externs[_bi1597]);
            _bi1597 += 1;
        }
    } else if (_mode1596 == 3) {
        var _n1594 = input.count();
        for (var _ in 0.._n1594) {
            _f1593.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1594 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1594) {
            var _tag1595 = input.unsigned();
            if (_tag1595 & 1 == 1) {
                if (!input.merging) {
                    _f1593.append(base.externs[_tag1595 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1593.append(_read);
                }
            }
        }
    }
    var _f1613 = Array<VariableDef>();
    var _mode1616 = input.unsigned();
    if (_mode1616 == 2) {
        var _changed1601 = HashMap<ulong, VariableDef>();
        ulong _bi1617 = 0;
        var _n1614 = input.count();
        for (var _ in 0.._n1614) {
            var _at1618 = input.unsigned();
            while (_f1613.count < _at1618 or (input.merging and _bi1617 < base.globals.count)) {
                var _c = _changed1601.try_get(_bi1617);
                _f1613.append(_c.is_value() ? _c.value() : base.globals[_bi1617]);
                _bi1617 += 1;
            }
            _f1613.append(_m_VariableDef_read(input));
        }
        while (_bi1617 < base.globals.count) {
            var _c = _changed1601.try_get(_bi1617);
            _f1613.append(_c.is_value() ? _c.value() : base.globals[_bi1617]);
            _bi1617 += 1;
        }
    } else if (_mode1616 == 3) {
        var _n1614 = input.count();
        for (var _ in 0.._n1614) {
            _f1613.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1614 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1614) {
            var _tag1615 = input.unsigned();
            if (_tag1615 & 1 == 1) {
                if (!input.merging) {
                    _f1613.append(base.globals[_tag1615 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1613.append(_read);
                }
            }
        }
    }
    var _f1633 = Array<ModuleStaticBlock>();
    var _mode1636 = input.unsigned();
    if (_mode1636 == 2) {
        var _changed1621 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1637 = 0;
        var _n1634 = input.count();
        for (var _ in 0.._n1634) {
            var _at1638 = input.unsigned();
            while (_f1633.count < _at1638 or (input.merging and _bi1637 < base.static_blocks.count)) {
                var _c = _changed1621.try_get(_bi1637);
                _f1633.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1637]);
                _bi1637 += 1;
            }
            _f1633.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1637 < base.static_blocks.count) {
            var _c = _changed1621.try_get(_bi1637);
            _f1633.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1637]);
            _bi1637 += 1;
        }
    } else if (_mode1636 == 3) {
        var _n1634 = input.count();
        for (var _ in 0.._n1634) {
            _f1633.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1634 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1634) {
            var _tag1635 = input.unsigned();
            if (_tag1635 & 1 == 1) {
                if (!input.merging) {
                    _f1633.append(base.static_blocks[_tag1635 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1633.append(_read);
                }
            }
        }
    }
    var _f1653 = Array<EnumDef>();
    var _mode1656 = input.unsigned();
    if (_mode1656 == 2) {
        var _changed1641 = HashMap<ulong, EnumDef>();
        ulong _bi1657 = 0;
        var _n1654 = input.count();
        for (var _ in 0.._n1654) {
            var _at1658 = input.unsigned();
            while (_f1653.count < _at1658 or (input.merging and _bi1657 < base.enums.count)) {
                var _c = _changed1641.try_get(_bi1657);
                _f1653.append(_c.is_value() ? _c.value() : base.enums[_bi1657]);
                _bi1657 += 1;
            }
            _f1653.append(_m_EnumDef_read(input));
        }
        while (_bi1657 < base.enums.count) {
            var _c = _changed1641.try_get(_bi1657);
            _f1653.append(_c.is_value() ? _c.value() : base.enums[_bi1657]);
            _bi1657 += 1;
        }
    } else if (_mode1656 == 3) {
        var _n1654 = input.count();
        for (var _ in 0.._n1654) {
            _f1653.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1654 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1654) {
            var _tag1655 = input.unsigned();
            if (_tag1655 & 1 == 1) {
                if (!input.merging) {
                    _f1653.append(base.enums[_tag1655 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1653.append(_read);
                }
            }
        }
    }
    var _f1673 = Array<TypeName>();
    var _mode1676 = input.unsigned();
    if (_mode1676 == 2) {
        var _changed1661 = HashMap<ulong, TypeName>();
        ulong _bi1677 = 0;
        var _n1674 = input.count();
        for (var _ in 0.._n1674) {
            var _at1678 = input.unsigned();
            while (_f1673.count < _at1678 or (input.merging and _bi1677 < base.struct_specs.count)) {
                var _c = _changed1661.try_get(_bi1677);
                _f1673.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1677]);
                _bi1677 += 1;
            }
            _f1673.append(_m_TypeName_read(input));
        }
        while (_bi1677 < base.struct_specs.count) {
            var _c = _changed1661.try_get(_bi1677);
            _f1673.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1677]);
            _bi1677 += 1;
        }
    } else if (_mode1676 == 3) {
        var _n1674 = input.count();
        for (var _ in 0.._n1674) {
            _f1673.append(_m_TypeName_read(input));
        }
    } else {
        var _n1674 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1674) {
            var _tag1675 = input.unsigned();
            if (_tag1675 & 1 == 1) {
                if (!input.merging) {
                    _f1673.append(base.struct_specs[_tag1675 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1673.append(_read);
                }
            }
        }
    }
    var _f1693 = Array<TypeName>();
    var _mode1696 = input.unsigned();
    if (_mode1696 == 2) {
        var _changed1681 = HashMap<ulong, TypeName>();
        ulong _bi1697 = 0;
        var _n1694 = input.count();
        for (var _ in 0.._n1694) {
            var _at1698 = input.unsigned();
            while (_f1693.count < _at1698 or (input.merging and _bi1697 < base.func_specs.count)) {
                var _c = _changed1681.try_get(_bi1697);
                _f1693.append(_c.is_value() ? _c.value() : base.func_specs[_bi1697]);
                _bi1697 += 1;
            }
            _f1693.append(_m_TypeName_read(input));
        }
        while (_bi1697 < base.func_specs.count) {
            var _c = _changed1681.try_get(_bi1697);
            _f1693.append(_c.is_value() ? _c.value() : base.func_specs[_bi1697]);
            _bi1697 += 1;
        }
    } else if (_mode1696 == 3) {
        var _n1694 = input.count();
        for (var _ in 0.._n1694) {
            _f1693.append(_m_TypeName_read(input));
        }
    } else {
        var _n1694 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1694) {
            var _tag1695 = input.unsigned();
            if (_tag1695 & 1 == 1) {
                if (!input.merging) {
                    _f1693.append(base.func_specs[_tag1695 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1693.append(_read);
                }
            }
        }
    }
    var _f1706 = Array<TypeAliasDef>();
    var _n1707 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1706.append(_b);
        }
    }
    for (var _ in 0.._n1707) {
        var _tag1708 = input.unsigned();
        if (_tag1708 & 1 == 1) {
            if (!input.merging) {
                _f1706.append(base.type_aliases[_tag1708 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1706.append(_read);
            }
        }
    }
    var _f1723 = Array<Withheld>();
    var _mode1726 = input.unsigned();
    if (_mode1726 == 2) {
        var _changed1711 = HashMap<ulong, Withheld>();
        ulong _bi1727 = 0;
        var _n1724 = input.count();
        for (var _ in 0.._n1724) {
            var _at1728 = input.unsigned();
            while (_f1723.count < _at1728 or (input.merging and _bi1727 < base.withheld.count)) {
                var _c = _changed1711.try_get(_bi1727);
                _f1723.append(_c.is_value() ? _c.value() : base.withheld[_bi1727]);
                _bi1727 += 1;
            }
            _f1723.append(_m_Withheld_read(input));
        }
        while (_bi1727 < base.withheld.count) {
            var _c = _changed1711.try_get(_bi1727);
            _f1723.append(_c.is_value() ? _c.value() : base.withheld[_bi1727]);
            _bi1727 += 1;
        }
    } else if (_mode1726 == 3) {
        var _n1724 = input.count();
        for (var _ in 0.._n1724) {
            _f1723.append(_m_Withheld_read(input));
        }
    } else {
        var _n1724 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1724) {
            var _tag1725 = input.unsigned();
            if (_tag1725 & 1 == 1) {
                if (!input.merging) {
                    _f1723.append(base.withheld[_tag1725 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1723.append(_read);
                }
            }
        }
    }
    var _f1743 = Array<PropertyDef>();
    var _mode1746 = input.unsigned();
    if (_mode1746 == 2) {
        var _changed1731 = HashMap<ulong, PropertyDef>();
        ulong _bi1747 = 0;
        var _n1744 = input.count();
        for (var _ in 0.._n1744) {
            var _at1748 = input.unsigned();
            while (_f1743.count < _at1748 or (input.merging and _bi1747 < base.properties.count)) {
                var _c = _changed1731.try_get(_bi1747);
                _f1743.append(_c.is_value() ? _c.value() : base.properties[_bi1747]);
                _bi1747 += 1;
            }
            _f1743.append(_m_PropertyDef_read(input));
        }
        while (_bi1747 < base.properties.count) {
            var _c = _changed1731.try_get(_bi1747);
            _f1743.append(_c.is_value() ? _c.value() : base.properties[_bi1747]);
            _bi1747 += 1;
        }
    } else if (_mode1746 == 3) {
        var _n1744 = input.count();
        for (var _ in 0.._n1744) {
            _f1743.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1744 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1744) {
            var _tag1745 = input.unsigned();
            if (_tag1745 & 1 == 1) {
                if (!input.merging) {
                    _f1743.append(base.properties[_tag1745 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1743.append(_read);
                }
            }
        }
    }
    var _f1763 = Array<TypeUse>();
    var _mode1766 = input.unsigned();
    if (_mode1766 == 2) {
        var _changed1751 = HashMap<ulong, TypeUse>();
        ulong _bi1767 = 0;
        var _n1764 = input.count();
        for (var _ in 0.._n1764) {
            var _at1768 = input.unsigned();
            while (_f1763.count < _at1768 or (input.merging and _bi1767 < base.type_uses.count)) {
                var _c = _changed1751.try_get(_bi1767);
                _f1763.append(_c.is_value() ? _c.value() : base.type_uses[_bi1767]);
                _bi1767 += 1;
            }
            _f1763.append(_m_TypeUse_read(input));
        }
        while (_bi1767 < base.type_uses.count) {
            var _c = _changed1751.try_get(_bi1767);
            _f1763.append(_c.is_value() ? _c.value() : base.type_uses[_bi1767]);
            _bi1767 += 1;
        }
    } else if (_mode1766 == 3) {
        var _n1764 = input.count();
        for (var _ in 0.._n1764) {
            _f1763.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1764 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1764) {
            var _tag1765 = input.unsigned();
            if (_tag1765 & 1 == 1) {
                if (!input.merging) {
                    _f1763.append(base.type_uses[_tag1765 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1763.append(_read);
                }
            }
        }
    }
    var _f1783 = Array<UseContext>();
    var _mode1786 = input.unsigned();
    if (_mode1786 == 2) {
        var _changed1771 = HashMap<ulong, UseContext>();
        ulong _bi1787 = 0;
        var _n1784 = input.count();
        for (var _ in 0.._n1784) {
            var _at1788 = input.unsigned();
            while (_f1783.count < _at1788 or (input.merging and _bi1787 < base.use_contexts.count)) {
                var _c = _changed1771.try_get(_bi1787);
                _f1783.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1787]);
                _bi1787 += 1;
            }
            _f1783.append(_m_UseContext_read(input));
        }
        while (_bi1787 < base.use_contexts.count) {
            var _c = _changed1771.try_get(_bi1787);
            _f1783.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1787]);
            _bi1787 += 1;
        }
    } else if (_mode1786 == 3) {
        var _n1784 = input.count();
        for (var _ in 0.._n1784) {
            _f1783.append(_m_UseContext_read(input));
        }
    } else {
        var _n1784 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1784) {
            var _tag1785 = input.unsigned();
            if (_tag1785 & 1 == 1) {
                if (!input.merging) {
                    _f1783.append(base.use_contexts[_tag1785 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1783.append(_read);
                }
            }
        }
    }
    var _f1804 = Array<(Loc, ulong, Loc)>();
    var _tag1805 = input.unsigned();
    if (_tag1805 == 1) {
        input.unsigned();
        for (var _i1793 in 0..base.literal_args.count) {
            _f1804.append(base.literal_args[_i1793]);
        }
        var _more1807 = input.count();
        for (var _ in 0.._more1807) {
            var _t1808 = input.loc();
            var _t1809 = input.unsigned();
            var _t1810 = input.loc();
            _f1804.append((_t1808, _t1809, _t1810));
        }
    } else {
        var _v1811 = Array<(Loc, ulong, Loc)>();
        var _n1812 = input.count();
        for (var _ in 0.._n1812) {
            var _t1813 = input.loc();
            var _t1814 = input.unsigned();
            var _t1815 = input.loc();
            _v1811.append((_t1813, _t1814, _t1815));
        }
        _f1804 = _v1811;
    }
    var _f1834 = Array<TypeAliasDef>();
    var _mode1837 = input.unsigned();
    if (_mode1837 == 2) {
        var _changed1822 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1838 = 0;
        var _n1835 = input.count();
        for (var _ in 0.._n1835) {
            var _at1839 = input.unsigned();
            while (_f1834.count < _at1839 or (input.merging and _bi1838 < base.constrained_aliases.count)) {
                var _c = _changed1822.try_get(_bi1838);
                _f1834.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1838]);
                _bi1838 += 1;
            }
            _f1834.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1838 < base.constrained_aliases.count) {
            var _c = _changed1822.try_get(_bi1838);
            _f1834.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1838]);
            _bi1838 += 1;
        }
    } else if (_mode1837 == 3) {
        var _n1835 = input.count();
        for (var _ in 0.._n1835) {
            _f1834.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1835 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1835) {
            var _tag1836 = input.unsigned();
            if (_tag1836 & 1 == 1) {
                if (!input.merging) {
                    _f1834.append(base.constrained_aliases[_tag1836 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1834.append(_read);
                }
            }
        }
    }
    var _f1854 = Array<TraitType>();
    var _mode1857 = input.unsigned();
    if (_mode1857 == 2) {
        var _changed1842 = HashMap<ulong, TraitType>();
        ulong _bi1858 = 0;
        var _n1855 = input.count();
        for (var _ in 0.._n1855) {
            var _at1859 = input.unsigned();
            while (_f1854.count < _at1859 or (input.merging and _bi1858 < base.trait_types.count)) {
                var _c = _changed1842.try_get(_bi1858);
                _f1854.append(_c.is_value() ? _c.value() : base.trait_types[_bi1858]);
                _bi1858 += 1;
            }
            _f1854.append(_m_TraitType_read(input));
        }
        while (_bi1858 < base.trait_types.count) {
            var _c = _changed1842.try_get(_bi1858);
            _f1854.append(_c.is_value() ? _c.value() : base.trait_types[_bi1858]);
            _bi1858 += 1;
        }
    } else if (_mode1857 == 3) {
        var _n1855 = input.count();
        for (var _ in 0.._n1855) {
            _f1854.append(_m_TraitType_read(input));
        }
    } else {
        var _n1855 = input.count();
        if (input.merging) {
            input.error = "trait_types" + " written by place";
        }
        for (var _ in 0.._n1855) {
            var _tag1856 = input.unsigned();
            if (_tag1856 & 1 == 1) {
                if (!input.merging) {
                    _f1854.append(base.trait_types[_tag1856 >> 1]);
                }
            } else {
                var _read = _m_TraitType_read(input);
                if (!input.merging or true) {
                    _f1854.append(_read);
                }
            }
        }
    }
    var _v1865 = Array<Conversion>();
    var _n1866 = input.count();
    for (var _ in 0.._n1866) {
        _v1865.append(_m_Conversion_read(input));
    }
    var _f1867 = _v1865;
    var _f1894 = Map<String, Array<String>>();
    var _tag1895 = input.unsigned();
    if (_tag1895 == 1) {
        for (var (_bk1896, _bv) in base.overload_sets) {
            _f1894[_bk1896] = _bv;
        }
        var _v1897 = Map<String, Array<String>>();
        var _n1898 = input.count();
        for (var _ in 0.._n1898) {
            var _k1899 = input.text();
            var _v1900 = Array<String>();
            var _n1901 = input.count();
            for (var _ in 0.._n1901) {
                _v1900.append(input.text());
            }
            _v1897[_k1899] = _v1900;
        }
        for (var (_bk1896, _av) in _v1897) {
            _f1894[_bk1896] = _av;
        }
    } else {
        var _v1902 = Map<String, Array<String>>();
        var _n1903 = input.count();
        for (var _ in 0.._n1903) {
            var _k1904 = input.text();
            var _v1905 = Array<String>();
            var _n1906 = input.count();
            for (var _ in 0.._n1906) {
                _v1905.append(input.text());
            }
            _v1902[_k1904] = _v1905;
        }
        _f1894 = _v1902;
    }
    var _f1941 = Map<String, Array<Array<String>>>();
    var _tag1942 = input.unsigned();
    if (_tag1942 == 1) {
        for (var (_bk1943, _bv) in base.overload_unions) {
            _f1941[_bk1943] = _bv;
        }
        var _v1944 = Map<String, Array<Array<String>>>();
        var _n1945 = input.count();
        for (var _ in 0.._n1945) {
            var _k1946 = input.text();
            var _v1947 = Array<Array<String>>();
            var _n1948 = input.count();
            for (var _ in 0.._n1948) {
                var _v1949 = Array<String>();
                var _n1950 = input.count();
                for (var _ in 0.._n1950) {
                    _v1949.append(input.text());
                }
                _v1947.append(_v1949);
            }
            _v1944[_k1946] = _v1947;
        }
        for (var (_bk1943, _av) in _v1944) {
            _f1941[_bk1943] = _av;
        }
    } else {
        var _v1951 = Map<String, Array<Array<String>>>();
        var _n1952 = input.count();
        for (var _ in 0.._n1952) {
            var _k1953 = input.text();
            var _v1954 = Array<Array<String>>();
            var _n1955 = input.count();
            for (var _ in 0.._n1955) {
                var _v1956 = Array<String>();
                var _n1957 = input.count();
                for (var _ in 0.._n1957) {
                    _v1956.append(input.text());
                }
                _v1954.append(_v1956);
            }
            _v1951[_k1953] = _v1954;
        }
        _f1941 = _v1951;
    }
    var _f2028 = Map<String, Map<String, Array<String>>>();
    var _tag2029 = input.unsigned();
    if (_tag2029 == 1) {
        for (var (_bk2030, _bv) in base.method_overload_sets) {
            _f2028[_bk2030] = _bv;
        }
        var _v2031 = Map<String, Map<String, Array<String>>>();
        var _n2032 = input.count();
        for (var _ in 0.._n2032) {
            var _k2033 = input.text();
            var _v2034 = Map<String, Array<String>>();
            var _n2035 = input.count();
            for (var _ in 0.._n2035) {
                var _k2036 = input.text();
                var _v2037 = Array<String>();
                var _n2038 = input.count();
                for (var _ in 0.._n2038) {
                    _v2037.append(input.text());
                }
                _v2034[_k2036] = _v2037;
            }
            _v2031[_k2033] = _v2034;
        }
        for (var (_bk2030, _av) in _v2031) {
            _f2028[_bk2030] = _av;
        }
    } else {
        var _v2039 = Map<String, Map<String, Array<String>>>();
        var _n2040 = input.count();
        for (var _ in 0.._n2040) {
            var _k2041 = input.text();
            var _v2042 = Map<String, Array<String>>();
            var _n2043 = input.count();
            for (var _ in 0.._n2043) {
                var _k2044 = input.text();
                var _v2045 = Array<String>();
                var _n2046 = input.count();
                for (var _ in 0.._n2046) {
                    _v2045.append(input.text());
                }
                _v2042[_k2044] = _v2045;
            }
            _v2039[_k2041] = _v2042;
        }
        _f2028 = _v2039;
    }
    var _f2054 = _m_ExtensionScopes_read(input);
    var _f2074 = HashSet<Loc>();
    var _tag2075 = input.unsigned();
    if (_tag2075 == 1) {
        for (var _bk2076 in base.private_functions) {
            _f2074.insert(_bk2076);
        }
        var _v2077 = HashSet<Loc>();
        var _n2078 = input.count();
        for (var _ in 0.._n2078) {
            _v2077.insert(input.loc());
        }
        for (var _bk2076 in _v2077) {
            _f2074.insert(_bk2076);
        }
    } else {
        var _v2079 = HashSet<Loc>();
        var _n2080 = input.count();
        for (var _ in 0.._n2080) {
            _v2079.insert(input.loc());
        }
        _f2074 = _v2079;
    }
    var _f2100 = HashSet<Loc>();
    var _tag2101 = input.unsigned();
    if (_tag2101 == 1) {
        for (var _bk2102 in base.file_private_functions) {
            _f2100.insert(_bk2102);
        }
        var _v2103 = HashSet<Loc>();
        var _n2104 = input.count();
        for (var _ in 0.._n2104) {
            _v2103.insert(input.loc());
        }
        for (var _bk2102 in _v2103) {
            _f2100.insert(_bk2102);
        }
    } else {
        var _v2105 = HashSet<Loc>();
        var _n2106 = input.count();
        for (var _ in 0.._n2106) {
            _v2105.insert(input.loc());
        }
        _f2100 = _v2105;
    }
    var _f2118 = Array<(Loc, String)>();
    var _tag2119 = input.unsigned();
    if (_tag2119 == 1) {
        input.unsigned();
        for (var _i2110 in 0..base.call_targets.count) {
            _f2118.append(base.call_targets[_i2110]);
        }
        var _more2121 = input.count();
        for (var _ in 0.._more2121) {
            var _t2122 = input.loc();
            var _t2123 = input.text();
            _f2118.append((_t2122, _t2123));
        }
    } else {
        var _v2124 = Array<(Loc, String)>();
        var _n2125 = input.count();
        for (var _ in 0.._n2125) {
            var _t2126 = input.loc();
            var _t2127 = input.text();
            _v2124.append((_t2126, _t2127));
        }
        _f2118 = _v2124;
    }
    var _f2144 = Array<(Loc, String)>();
    var _tag2145 = input.unsigned();
    if (_tag2145 == 1) {
        var _v2146 = Array<(Loc, String)>();
        var _n2147 = input.count();
        for (var _ in 0.._n2147) {
            var _t2148 = input.loc();
            var _t2149 = input.text();
            _v2146.append((_t2148, _t2149));
        }
        _f2144 = merge_by_place(base.argument_names, _v2146);
    } else {
        var _v2150 = Array<(Loc, String)>();
        var _n2151 = input.count();
        for (var _ in 0.._n2151) {
            var _t2152 = input.loc();
            var _t2153 = input.text();
            _v2150.append((_t2152, _t2153));
        }
        _f2144 = _v2150;
    }
    var _f2163 = Array<String>();
    var _tag2164 = input.unsigned();
    if (_tag2164 == 1) {
        input.unsigned();
        for (var _i2159 in 0..base.namespaces.count) {
            _f2163.append(base.namespaces[_i2159]);
        }
        var _more2166 = input.count();
        for (var _ in 0.._more2166) {
            _f2163.append(input.text());
        }
    } else {
        var _v2167 = Array<String>();
        var _n2168 = input.count();
        for (var _ in 0.._n2168) {
            _v2167.append(input.text());
        }
        _f2163 = _v2167;
    }
    var _f2176 = Array<bool>();
    var _tag2177 = input.unsigned();
    if (_tag2177 == 1) {
        input.unsigned();
        for (var _i2174 in 0..base.cached_files.count) {
            _f2176.append(base.cached_files[_i2174]);
        }
        var _more2179 = input.count();
        for (var _ in 0.._more2179) {
            _f2176.append(input.flag());
        }
    } else {
        var _v2180 = Array<bool>();
        var _n2181 = input.count();
        for (var _ in 0.._n2181) {
            _v2180.append(input.flag());
        }
        _f2176 = _v2180;
    }
    var _f2199 = HashMap<Loc, String>();
    var _tag2200 = input.unsigned();
    if (_tag2200 == 1) {
        for (var (_bk2201, _bv) in base.recorded_summaries) {
            _f2199[_bk2201] = _bv;
        }
        var _v2202 = HashMap<Loc, String>();
        var _n2203 = input.count();
        for (var _ in 0.._n2203) {
            var _k2204 = input.loc();
            _v2202[_k2204] = input.text();
        }
        for (var (_bk2201, _av) in _v2202) {
            _f2199[_bk2201] = _av;
        }
    } else {
        var _v2205 = HashMap<Loc, String>();
        var _n2206 = input.count();
        for (var _ in 0.._n2206) {
            var _k2207 = input.loc();
            _v2205[_k2207] = input.text();
        }
        _f2199 = _v2205;
    }
    var _f2223 = HashSet<Loc>();
    var _tag2224 = input.unsigned();
    if (_tag2224 == 1) {
        for (var _bk2225 in base.stripped) {
            _f2223.insert(_bk2225);
        }
        var _v2226 = HashSet<Loc>();
        var _n2227 = input.count();
        for (var _ in 0.._n2227) {
            _v2226.insert(input.loc());
        }
        for (var _bk2225 in _v2226) {
            _f2223.insert(_bk2225);
        }
    } else {
        var _v2228 = HashSet<Loc>();
        var _n2229 = input.count();
        for (var _ in 0.._n2229) {
            _v2228.insert(input.loc());
        }
        _f2223 = _v2228;
    }
    var _frozen = input.flag();
    var _f2241 = Array<StructDef>();
    var _mode2244 = input.unsigned();
    if (_mode2244 == 2) {
        var _patched2247 = HashMap<ulong, StructDef>();
        var _n2242 = input.count();
        for (var _ in 0.._n2242) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2247[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2245 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2246 = input.unsigned();
            while (_f2241.count < _at2246 or (input.merging and _bi2245 < base.templates.structs.count)) {
                var _p = _patched2247.try_get(_bi2245);
                _f2241.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2245]);
                _bi2245 += 1;
            }
            _f2241.append(_m_StructDef_read(input));
        }
        while (_bi2245 < base.templates.structs.count) {
            var _p = _patched2247.try_get(_bi2245);
            _f2241.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2245]);
            _bi2245 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2242 = input.count();
        for (var _ in 0.._n2242) {
            var _tag2243 = input.unsigned();
            if (_tag2243 & 1 == 1) {
                _f2241.append(
                    base.templates.structs[(_tag2243 >> 1) < base.templates.structs.count ? _tag2243 >> 1 : 0]
                );
            } else if (_tag2243 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2241.append(_patch_t_read(input, _was));
            } else {
                _f2241.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2263 = Array<FunctionDef>();
    var _mode2266 = input.unsigned();
    if (_mode2266 == 2) {
        var _changed2250 = HashMap<ulong, FunctionDef>();
        var _nc2252 = input.count();
        for (var _ in 0.._nc2252) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = base.templates.functions.count;
                for (var _k in 0..base.templates.functions.count) {
                    if (base.templates.functions[_k].name == _name) {
                        _slot = _k;
                        break;
                    }
                }
            }
            var _el = _m_FunctionDef_read(input);
            if (_slot < base.templates.functions.count) {
                _changed2250[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2267 = 0;
        var _n2264 = input.count();
        for (var _ in 0.._n2264) {
            var _at2268 = input.unsigned();
            while (_f2263.count < _at2268 or (input.merging and _bi2267 < base.templates.functions.count)) {
                var _c = _changed2250.try_get(_bi2267);
                _f2263.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2267]);
                _bi2267 += 1;
            }
            _f2263.append(_m_FunctionDef_read(input));
        }
        while (_bi2267 < base.templates.functions.count) {
            var _c = _changed2250.try_get(_bi2267);
            _f2263.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2267]);
            _bi2267 += 1;
        }
    } else if (_mode2266 == 3) {
        var _n2264 = input.count();
        for (var _ in 0.._n2264) {
            _f2263.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2264 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2264) {
            var _tag2265 = input.unsigned();
            if (_tag2265 & 1 == 1) {
                if (!input.merging) {
                    _f2263.append(base.templates.functions[_tag2265 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2263.append(_read);
                }
            }
        }
    }
    var _f2270 = Templates(_frozen, _f2241, _f2263);
    var _f2271 = DeltaBase.read_checked(input, base.checked);
    var _f2291 = HashMap<String, SpecRequest>();
    var _tag2292 = input.unsigned();
    if (_tag2292 == 1) {
        for (var (_bk2293, _bv) in base.spec_requests) {
            _f2291[_bk2293] = _bv;
        }
        var _v2294 = HashMap<String, SpecRequest>();
        var _n2295 = input.count();
        for (var _ in 0.._n2295) {
            var _k2296 = input.text();
            _v2294[_k2296] = _m_SpecRequest_read(input);
        }
        for (var (_bk2293, _av) in _v2294) {
            _f2291[_bk2293] = _av;
        }
    } else {
        var _v2297 = HashMap<String, SpecRequest>();
        var _n2298 = input.count();
        for (var _ in 0.._n2298) {
            var _k2299 = input.text();
            _v2297[_k2299] = _m_SpecRequest_read(input);
        }
        _f2291 = _v2297;
    }
    var _f2300 = input.flag();
    var _f2312 = Array<(Loc, String)>();
    var _tag2313 = input.unsigned();
    if (_tag2313 == 1) {
        input.unsigned();
        for (var _i2304 in 0..base.summaries_to_record.count) {
            _f2312.append(base.summaries_to_record[_i2304]);
        }
        var _more2315 = input.count();
        for (var _ in 0.._more2315) {
            var _t2316 = input.loc();
            var _t2317 = input.text();
            _f2312.append((_t2316, _t2317));
        }
    } else {
        var _v2318 = Array<(Loc, String)>();
        var _n2319 = input.count();
        for (var _ in 0.._n2319) {
            var _t2320 = input.loc();
            var _t2321 = input.text();
            _v2318.append((_t2320, _t2321));
        }
        _f2312 = _v2318;
    }
    var _f2352 = HashMap<String, Array<bool>>();
    var _tag2353 = input.unsigned();
    if (_tag2353 == 1) {
        for (var (_bk2354, _bv) in base.caller_copies) {
            _f2352[_bk2354] = _bv;
        }
        var _v2355 = HashMap<String, Array<bool>>();
        var _n2356 = input.count();
        for (var _ in 0.._n2356) {
            var _k2357 = input.text();
            var _v2358 = Array<bool>();
            var _n2359 = input.count();
            for (var _ in 0.._n2359) {
                _v2358.append(input.flag());
            }
            _v2355[_k2357] = _v2358;
        }
        for (var (_bk2354, _av) in _v2355) {
            _f2352[_bk2354] = _av;
        }
    } else {
        var _v2360 = HashMap<String, Array<bool>>();
        var _n2361 = input.count();
        for (var _ in 0.._n2361) {
            var _k2362 = input.text();
            var _v2363 = Array<bool>();
            var _n2364 = input.count();
            for (var _ in 0.._n2364) {
                _v2363.append(input.flag());
            }
            _v2360[_k2362] = _v2363;
        }
        _f2352 = _v2360;
    }
    var _f2366 = input.flag();
    return Module(
        _f1493,
        _f1511,
        _f1532,
        _f1552,
        _f1573,
        _f1593,
        _f1613,
        _f1633,
        _f1653,
        _f1673,
        _f1693,
        _f1706,
        _f1723,
        _f1743,
        _f1763,
        _f1783,
        _f1804,
        _f1834,
        _f1854,
        _f1867,
        _f1894,
        _f1941,
        _f2028,
        _f2054,
        _f2074,
        _f2100,
        _f2118,
        _f2144,
        _f2163,
        _f2176,
        _f2199,
        _f2223,
        _f2270,
        _f2271,
        _f2291,
        _f2300,
        _f2312,
        _f2352,
        _f2366
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1499 = 0;
    for (var _item1480 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1480);
        base.add("imports", scratch, _j1499);
        _j1499 += 1;
    }
    ulong _j1518 = 0;
    for (var _item1500 in value.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1500);
        base.add("s", scratch, _j1518);
        base.name("s", _item1500.name, _j1518);
        _patch_s_index(_item1500, base, _j1518);
        _j1518 += 1;
    }
    ulong _j1538 = 0;
    for (var _item1519 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1519);
        base.add("traits", scratch, _j1538);
        _j1538 += 1;
    }
    ulong _j1558 = 0;
    for (var _item1539 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1539);
        base.add("extensions", scratch, _j1558);
        _j1558 += 1;
    }
    ulong _j1579 = 0;
    for (var _item1559 in value.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1559);
        base.add("functions", scratch, _j1579);
        base.name("functions", _item1559.name, _j1579);
        _j1579 += 1;
    }
    ulong _j1599 = 0;
    for (var _item1580 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1580);
        base.add("externs", scratch, _j1599);
        _j1599 += 1;
    }
    ulong _j1619 = 0;
    for (var _item1600 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1600);
        base.add("globals", scratch, _j1619);
        _j1619 += 1;
    }
    ulong _j1639 = 0;
    for (var _item1620 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1620);
        base.add("static_blocks", scratch, _j1639);
        _j1639 += 1;
    }
    ulong _j1659 = 0;
    for (var _item1640 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1640);
        base.add("enums", scratch, _j1659);
        _j1659 += 1;
    }
    ulong _j1679 = 0;
    for (var _item1660 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1660);
        base.add("struct_specs", scratch, _j1679);
        _j1679 += 1;
    }
    ulong _j1699 = 0;
    for (var _item1680 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1680);
        base.add("func_specs", scratch, _j1699);
        _j1699 += 1;
    }
    ulong _j1709 = 0;
    for (var _item1700 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1700);
        base.add("type_aliases", scratch, _j1709);
        _j1709 += 1;
    }
    ulong _j1729 = 0;
    for (var _item1710 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1710);
        base.add("withheld", scratch, _j1729);
        _j1729 += 1;
    }
    ulong _j1749 = 0;
    for (var _item1730 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1730);
        base.add("properties", scratch, _j1749);
        _j1749 += 1;
    }
    ulong _j1769 = 0;
    for (var _item1750 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1750);
        base.add("type_uses", scratch, _j1769);
        _j1769 += 1;
    }
    ulong _j1789 = 0;
    for (var _item1770 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1770);
        base.add("use_contexts", scratch, _j1789);
        _j1789 += 1;
    }
    var _xscratch1816 = base.scratch();
    for (var _xitem1817 in value.literal_args) {
        var (_t1818, _t1819, _t1820) = _xitem1817;
        _xscratch1816.loc(_t1818);
        _xscratch1816.unsigned(_t1819);
        _xscratch1816.loc(_t1820);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1816);
    ulong _j1840 = 0;
    for (var _item1821 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1821);
        base.add("constrained_aliases", scratch, _j1840);
        _j1840 += 1;
    }
    ulong _j1860 = 0;
    for (var _item1841 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1841);
        base.add("trait_types", scratch, _j1860);
        _j1860 += 1;
    }
    ulong _cj1864 = 0;
    for (var _conv1862 in value.conversions) {
        var _own1863 = RecordOut();
        _own1863.blank_locs = true;
        _m_Conversion_write(_own1863, _conv1862);
        base.add_hashed("conversions", interface_text(_own1863), _cj1864);
        _cj1864 += 1;
    }
    for (var (_key1868, _) in value.overload_sets) {
        var _kscratch1869 = base.scratch();
        _kscratch1869.text(_key1868);
        var _vscratch1870 = base.scratch();
        _vscratch1870.unsigned(value.overload_sets[_key1868].count);
        for (var _item1907 in value.overload_sets[_key1868]) {
            _vscratch1870.text(_item1907);
        }
        base.keep_entry("overload_sets", _kscratch1869, _vscratch1870);
    }
    for (var (_key1908, _) in value.overload_unions) {
        var _kscratch1909 = base.scratch();
        _kscratch1909.text(_key1908);
        var _vscratch1910 = base.scratch();
        _vscratch1910.unsigned(value.overload_unions[_key1908].count);
        for (var _item1958 in value.overload_unions[_key1908]) {
            _vscratch1910.unsigned(_item1958.count);
            for (var _item1959 in _item1958) {
                _vscratch1910.text(_item1959);
            }
        }
        base.keep_entry("overload_unions", _kscratch1909, _vscratch1910);
    }
    for (var (_key1960, _) in value.method_overload_sets) {
        var _kscratch1961 = base.scratch();
        _kscratch1961.text(_key1960);
        var _vscratch1962 = base.scratch();
        var _keys2048 = Array<(u8[], u8[], String)>();
        for (var (_key2047, _) in value.method_overload_sets[_key1960]) {
            var _scratch2049 = _vscratch1962.scratch();
            _scratch2049.text(_key2047);
            var _vscratch2051 = _vscratch1962.scratch();
            _vscratch2051.unsigned(value.method_overload_sets[_key1960][_key2047].count);
            for (var _item2052 in value.method_overload_sets[_key1960][_key2047]) {
                _vscratch2051.text(_item2052);
            }
            _keys2048.append((_scratch2049.finish(), _vscratch2051.finish(), _key2047));
        }
        _keys2048.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1962.unsigned(_keys2048.count);
        for (var (_bytes2050, _, _key2047) in _keys2048) {
            _vscratch1962.text(_key2047);
            _vscratch1962.unsigned(value.method_overload_sets[_key1960][_key2047].count);
            for (var _item2053 in value.method_overload_sets[_key1960][_key2047]) {
                _vscratch1962.text(_item2053);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1961, _vscratch1962);
    }
    for (var _key2055 in value.private_functions) {
        var _kscratch2056 = base.scratch();
        _kscratch2056.loc(_key2055);
        var _vscratch2057 = base.scratch();
        base.keep_entry("private_functions", _kscratch2056, _vscratch2057);
    }
    for (var _key2081 in value.file_private_functions) {
        var _kscratch2082 = base.scratch();
        _kscratch2082.loc(_key2081);
        var _vscratch2083 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch2082, _vscratch2083);
    }
    var _xscratch2128 = base.scratch();
    for (var _xitem2129 in value.call_targets) {
        var (_t2130, _t2131) = _xitem2129;
        _xscratch2128.loc(_t2130);
        _xscratch2128.text(_t2131);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2128);
    for (var _item2132 in value.argument_names) {
        var _escratch2133 = base.scratch();
        var (_t2154, _t2155) = _item2132;
        _escratch2133.loc(_t2154);
        _escratch2133.text(_t2155);
        base.keep_entry("argument_names", _escratch2133, base.scratch());
    }
    var _xscratch2169 = base.scratch();
    for (var _xitem2170 in value.namespaces) {
        _xscratch2169.text(_xitem2170);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2169);
    var _xscratch2182 = base.scratch();
    for (var _xitem2183 in value.cached_files) {
        _xscratch2182.flag(_xitem2183);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2182);
    for (var (_key2184, _) in value.recorded_summaries) {
        var _kscratch2185 = base.scratch();
        _kscratch2185.loc(_key2184);
        var _vscratch2186 = base.scratch();
        _vscratch2186.text(value.recorded_summaries[_key2184]);
        base.keep_entry("recorded_summaries", _kscratch2185, _vscratch2186);
    }
    for (var _key2208 in value.stripped) {
        var _kscratch2209 = base.scratch();
        _kscratch2209.loc(_key2208);
        var _vscratch2210 = base.scratch();
        base.keep_entry("stripped", _kscratch2209, _vscratch2210);
    }
    ulong _j2248 = 0;
    for (var _item2230 in value.templates.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item2230);
        base.add("t", scratch, _j2248);
        base.name("t", _item2230.name, _j2248);
        _patch_t_index(_item2230, base, _j2248);
        _j2248 += 1;
    }
    ulong _j2269 = 0;
    for (var _item2249 in value.templates.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2249);
        base.add("tf", scratch, _j2269);
        base.name("tf", _item2249.name, _j2269);
        _j2269 += 1;
    }
    base.keep_checked(value.checked);
    for (var (_key2272, _) in value.spec_requests) {
        var _kscratch2273 = base.scratch();
        _kscratch2273.text(_key2272);
        var _vscratch2274 = base.scratch();
        _m_SpecRequest_write(_vscratch2274, value.spec_requests[_key2272]);
        base.keep_entry("spec_requests", _kscratch2273, _vscratch2274);
    }
    var _xscratch2322 = base.scratch();
    for (var _xitem2323 in value.summaries_to_record) {
        var (_t2324, _t2325) = _xitem2323;
        _xscratch2322.loc(_t2324);
        _xscratch2322.text(_t2325);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2322);
    for (var (_key2326, _) in value.caller_copies) {
        var _kscratch2327 = base.scratch();
        _kscratch2327.text(_key2326);
        var _vscratch2328 = base.scratch();
        _vscratch2328.unsigned(value.caller_copies[_key2326].count);
        for (var _item2365 in value.caller_copies[_key2326]) {
            _vscratch2328.flag(_item2365);
        }
        base.keep_entry("caller_copies", _kscratch2327, _vscratch2328);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1709 = 0;
    for (var _item1700 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1700);
        base.add("type_aliases", scratch, _j1709);
        _j1709 += 1;
    }
    for (var (_key2184, _) in value.recorded_summaries) {
        var _kscratch2185 = base.scratch();
        _kscratch2185.loc(_key2184);
        var _vscratch2186 = base.scratch();
        _vscratch2186.text(value.recorded_summaries[_key2184]);
        base.keep_entry("recorded_summaries", _kscratch2185, _vscratch2186);
    }
    var _xscratch2322 = base.scratch();
    for (var _xitem2323 in value.summaries_to_record) {
        var (_t2324, _t2325) = _xitem2323;
        _xscratch2322.loc(_t2324);
        _xscratch2322.text(_t2325);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2322);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _hs2375 = Array<String>();
    for (var _item2369 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2369);
        _hs2375.append(base.hash_of(scratch));
    }
    var _seq2376 = base.sequence($"s.{slot}.generic_params");
    ulong _bj2377 = 0;
    var _news2378 = Array<ulong>();
    for (var _i2379 in 0.._hs2375.count) {
        if (_bj2377 < _seq2376.count and _hs2375[_i2379] == _seq2376[_bj2377]) {
            _bj2377 += 1;
        } else {
            _news2378.append(_i2379);
        }
    }
    if (_bj2377 == _seq2376.count) {
        out.unsigned(2);
        out.unsigned(_news2378.count);
        for (var _i2379 in _news2378) {
            out.unsigned(_i2379);
            _m_GenericParam_write(out, value.generic_params[_i2379]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2379 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2379]);
        }
    }
    var _hs2393 = Array<String>();
    for (var _item2387 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2387);
        _hs2393.append(base.hash_of(scratch));
    }
    var _seq2394 = base.sequence($"s.{slot}.field_members");
    ulong _bj2395 = 0;
    var _news2396 = Array<ulong>();
    for (var _i2397 in 0.._hs2393.count) {
        if (_bj2395 < _seq2394.count and _hs2393[_i2397] == _seq2394[_bj2395]) {
            _bj2395 += 1;
        } else {
            _news2396.append(_i2397);
        }
    }
    if (_bj2395 == _seq2394.count) {
        out.unsigned(2);
        out.unsigned(_news2396.count);
        for (var _i2397 in _news2396) {
            out.unsigned(_i2397);
            _m_VariableDef_write(out, value.field_members[_i2397]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2397 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2397]);
        }
    }
    var _hs2411 = Array<String>();
    for (var _item2405 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2405);
        _hs2411.append(base.hash_of(scratch));
    }
    var _seq2412 = base.sequence($"s.{slot}.method_members");
    ulong _bj2413 = 0;
    var _news2414 = Array<ulong>();
    for (var _i2415 in 0.._hs2411.count) {
        if (_bj2413 < _seq2412.count and _hs2411[_i2415] == _seq2412[_bj2413]) {
            _bj2413 += 1;
        } else {
            _news2414.append(_i2415);
        }
    }
    if (_bj2413 == _seq2412.count) {
        out.unsigned(2);
        out.unsigned(_news2414.count);
        for (var _i2415 in _news2414) {
            out.unsigned(_i2415);
            _m_FunctionDef_write(out, value.method_members[_i2415]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2415 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2415]);
        }
    }
    var _hs2429 = Array<String>();
    for (var _item2423 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2423);
        _hs2429.append(base.hash_of(scratch));
    }
    var _seq2430 = base.sequence($"s.{slot}.generic_methods");
    ulong _bj2431 = 0;
    var _news2432 = Array<ulong>();
    for (var _i2433 in 0.._hs2429.count) {
        if (_bj2431 < _seq2430.count and _hs2429[_i2433] == _seq2430[_bj2431]) {
            _bj2431 += 1;
        } else {
            _news2432.append(_i2433);
        }
    }
    if (_bj2431 == _seq2430.count) {
        out.unsigned(2);
        out.unsigned(_news2432.count);
        for (var _i2433 in _news2432) {
            out.unsigned(_i2433);
            _m_FunctionDef_write(out, value.generic_methods[_i2433]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2433 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2433]);
        }
    }
    var _hs2447 = Array<String>();
    for (var _item2441 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2441);
        _hs2447.append(base.hash_of(scratch));
    }
    var _seq2448 = base.sequence($"s.{slot}.constructors");
    ulong _bj2449 = 0;
    var _news2450 = Array<ulong>();
    for (var _i2451 in 0.._hs2447.count) {
        if (_bj2449 < _seq2448.count and _hs2447[_i2451] == _seq2448[_bj2449]) {
            _bj2449 += 1;
        } else {
            _news2450.append(_i2451);
        }
    }
    if (_bj2449 == _seq2448.count) {
        out.unsigned(2);
        out.unsigned(_news2450.count);
        for (var _i2451 in _news2450) {
            out.unsigned(_i2451);
            _m_FunctionDef_write(out, value.constructors[_i2451]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2451 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2451]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _hs2468 = Array<String>();
    for (var _item2462 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2462);
        _hs2468.append(base.hash_of(scratch));
    }
    var _seq2469 = base.sequence($"s.{slot}.traits");
    ulong _bj2470 = 0;
    var _news2471 = Array<ulong>();
    for (var _i2472 in 0.._hs2468.count) {
        if (_bj2470 < _seq2469.count and _hs2468[_i2472] == _seq2469[_bj2470]) {
            _bj2470 += 1;
        } else {
            _news2471.append(_i2472);
        }
    }
    if (_bj2470 == _seq2469.count) {
        out.unsigned(2);
        out.unsigned(_news2471.count);
        for (var _i2472 in _news2471) {
            out.unsigned(_i2472);
            _m_TypeName_write(out, value.traits[_i2472]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2472 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2472]);
        }
    }
    var _hs2486 = Array<String>();
    for (var _item2480 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2480);
        _hs2486.append(base.hash_of(scratch));
    }
    var _seq2487 = base.sequence($"s.{slot}.attributes");
    ulong _bj2488 = 0;
    var _news2489 = Array<ulong>();
    for (var _i2490 in 0.._hs2486.count) {
        if (_bj2488 < _seq2487.count and _hs2486[_i2490] == _seq2487[_bj2488]) {
            _bj2488 += 1;
        } else {
            _news2489.append(_i2490);
        }
    }
    if (_bj2488 == _seq2487.count) {
        out.unsigned(2);
        out.unsigned(_news2489.count);
        for (var _i2490 in _news2489) {
            out.unsigned(_i2490);
            _a_Attribute_write(out, value.attributes[_i2490]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2490 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2490]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2499 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2499);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2367 = input.text();
    var _f2368 = _m_TypeName_read(input);
    var _f2380 = Array<GenericParam>();
    var _mode2383 = input.unsigned();
    if (_mode2383 == 2) {
        var _changed2370 = HashMap<ulong, GenericParam>();
        ulong _bi2384 = 0;
        var _n2381 = input.count();
        for (var _ in 0.._n2381) {
            var _at2385 = input.unsigned();
            while (_f2380.count < _at2385 or (input.merging and _bi2384 < was.generic_params.count)) {
                var _c = _changed2370.try_get(_bi2384);
                _f2380.append(_c.is_value() ? _c.value() : was.generic_params[_bi2384]);
                _bi2384 += 1;
            }
            _f2380.append(_m_GenericParam_read(input));
        }
        while (_bi2384 < was.generic_params.count) {
            var _c = _changed2370.try_get(_bi2384);
            _f2380.append(_c.is_value() ? _c.value() : was.generic_params[_bi2384]);
            _bi2384 += 1;
        }
    } else if (_mode2383 == 3) {
        var _n2381 = input.count();
        for (var _ in 0.._n2381) {
            _f2380.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2381 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2381) {
            var _tag2382 = input.unsigned();
            if (_tag2382 & 1 == 1) {
                if (!input.merging) {
                    _f2380.append(was.generic_params[_tag2382 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2380.append(_read);
                }
            }
        }
    }
    var _f2398 = Array<VariableDef>();
    var _mode2401 = input.unsigned();
    if (_mode2401 == 2) {
        var _changed2388 = HashMap<ulong, VariableDef>();
        ulong _bi2402 = 0;
        var _n2399 = input.count();
        for (var _ in 0.._n2399) {
            var _at2403 = input.unsigned();
            while (_f2398.count < _at2403 or (input.merging and _bi2402 < was.field_members.count)) {
                var _c = _changed2388.try_get(_bi2402);
                _f2398.append(_c.is_value() ? _c.value() : was.field_members[_bi2402]);
                _bi2402 += 1;
            }
            _f2398.append(_m_VariableDef_read(input));
        }
        while (_bi2402 < was.field_members.count) {
            var _c = _changed2388.try_get(_bi2402);
            _f2398.append(_c.is_value() ? _c.value() : was.field_members[_bi2402]);
            _bi2402 += 1;
        }
    } else if (_mode2401 == 3) {
        var _n2399 = input.count();
        for (var _ in 0.._n2399) {
            _f2398.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2399 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2399) {
            var _tag2400 = input.unsigned();
            if (_tag2400 & 1 == 1) {
                if (!input.merging) {
                    _f2398.append(was.field_members[_tag2400 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2398.append(_read);
                }
            }
        }
    }
    var _f2416 = Array<FunctionDef>();
    var _mode2419 = input.unsigned();
    if (_mode2419 == 2) {
        var _changed2406 = HashMap<ulong, FunctionDef>();
        ulong _bi2420 = 0;
        var _n2417 = input.count();
        for (var _ in 0.._n2417) {
            var _at2421 = input.unsigned();
            while (_f2416.count < _at2421 or (input.merging and _bi2420 < was.method_members.count)) {
                var _c = _changed2406.try_get(_bi2420);
                _f2416.append(_c.is_value() ? _c.value() : was.method_members[_bi2420]);
                _bi2420 += 1;
            }
            _f2416.append(_m_FunctionDef_read(input));
        }
        while (_bi2420 < was.method_members.count) {
            var _c = _changed2406.try_get(_bi2420);
            _f2416.append(_c.is_value() ? _c.value() : was.method_members[_bi2420]);
            _bi2420 += 1;
        }
    } else if (_mode2419 == 3) {
        var _n2417 = input.count();
        for (var _ in 0.._n2417) {
            _f2416.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2417 = input.count();
        if (input.merging) {
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2417) {
            var _tag2418 = input.unsigned();
            if (_tag2418 & 1 == 1) {
                if (!input.merging) {
                    _f2416.append(was.method_members[_tag2418 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2416.append(_read);
                }
            }
        }
    }
    var _f2434 = Array<FunctionDef>();
    var _mode2437 = input.unsigned();
    if (_mode2437 == 2) {
        var _changed2424 = HashMap<ulong, FunctionDef>();
        ulong _bi2438 = 0;
        var _n2435 = input.count();
        for (var _ in 0.._n2435) {
            var _at2439 = input.unsigned();
            while (_f2434.count < _at2439 or (input.merging and _bi2438 < was.generic_methods.count)) {
                var _c = _changed2424.try_get(_bi2438);
                _f2434.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2438]);
                _bi2438 += 1;
            }
            _f2434.append(_m_FunctionDef_read(input));
        }
        while (_bi2438 < was.generic_methods.count) {
            var _c = _changed2424.try_get(_bi2438);
            _f2434.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2438]);
            _bi2438 += 1;
        }
    } else if (_mode2437 == 3) {
        var _n2435 = input.count();
        for (var _ in 0.._n2435) {
            _f2434.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2435 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2435) {
            var _tag2436 = input.unsigned();
            if (_tag2436 & 1 == 1) {
                if (!input.merging) {
                    _f2434.append(was.generic_methods[_tag2436 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2434.append(_read);
                }
            }
        }
    }
    var _f2452 = Array<FunctionDef>();
    var _mode2455 = input.unsigned();
    if (_mode2455 == 2) {
        var _changed2442 = HashMap<ulong, FunctionDef>();
        ulong _bi2456 = 0;
        var _n2453 = input.count();
        for (var _ in 0.._n2453) {
            var _at2457 = input.unsigned();
            while (_f2452.count < _at2457 or (input.merging and _bi2456 < was.constructors.count)) {
                var _c = _changed2442.try_get(_bi2456);
                _f2452.append(_c.is_value() ? _c.value() : was.constructors[_bi2456]);
                _bi2456 += 1;
            }
            _f2452.append(_m_FunctionDef_read(input));
        }
        while (_bi2456 < was.constructors.count) {
            var _c = _changed2442.try_get(_bi2456);
            _f2452.append(_c.is_value() ? _c.value() : was.constructors[_bi2456]);
            _bi2456 += 1;
        }
    } else if (_mode2455 == 3) {
        var _n2453 = input.count();
        for (var _ in 0.._n2453) {
            _f2452.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2453 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2453) {
            var _tag2454 = input.unsigned();
            if (_tag2454 & 1 == 1) {
                if (!input.merging) {
                    _f2452.append(was.constructors[_tag2454 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2452.append(_read);
                }
            }
        }
    }
    var _f2459 = _m_FunctionDef_read(input);
    var _f2460 = _m_FunctionDef_read(input);
    var _f2461 = _m_FunctionDef_read(input);
    var _f2473 = Array<TypeName>();
    var _mode2476 = input.unsigned();
    if (_mode2476 == 2) {
        var _changed2463 = HashMap<ulong, TypeName>();
        ulong _bi2477 = 0;
        var _n2474 = input.count();
        for (var _ in 0.._n2474) {
            var _at2478 = input.unsigned();
            while (_f2473.count < _at2478 or (input.merging and _bi2477 < was.traits.count)) {
                var _c = _changed2463.try_get(_bi2477);
                _f2473.append(_c.is_value() ? _c.value() : was.traits[_bi2477]);
                _bi2477 += 1;
            }
            _f2473.append(_m_TypeName_read(input));
        }
        while (_bi2477 < was.traits.count) {
            var _c = _changed2463.try_get(_bi2477);
            _f2473.append(_c.is_value() ? _c.value() : was.traits[_bi2477]);
            _bi2477 += 1;
        }
    } else if (_mode2476 == 3) {
        var _n2474 = input.count();
        for (var _ in 0.._n2474) {
            _f2473.append(_m_TypeName_read(input));
        }
    } else {
        var _n2474 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2474) {
            var _tag2475 = input.unsigned();
            if (_tag2475 & 1 == 1) {
                if (!input.merging) {
                    _f2473.append(was.traits[_tag2475 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2473.append(_read);
                }
            }
        }
    }
    var _f2491 = Array<ast.Attribute>();
    var _mode2494 = input.unsigned();
    if (_mode2494 == 2) {
        var _changed2481 = HashMap<ulong, ast.Attribute>();
        ulong _bi2495 = 0;
        var _n2492 = input.count();
        for (var _ in 0.._n2492) {
            var _at2496 = input.unsigned();
            while (_f2491.count < _at2496 or (input.merging and _bi2495 < was.attributes.count)) {
                var _c = _changed2481.try_get(_bi2495);
                _f2491.append(_c.is_value() ? _c.value() : was.attributes[_bi2495]);
                _bi2495 += 1;
            }
            _f2491.append(_a_Attribute_read(input));
        }
        while (_bi2495 < was.attributes.count) {
            var _c = _changed2481.try_get(_bi2495);
            _f2491.append(_c.is_value() ? _c.value() : was.attributes[_bi2495]);
            _bi2495 += 1;
        }
    } else if (_mode2494 == 3) {
        var _n2492 = input.count();
        for (var _ in 0.._n2492) {
            _f2491.append(_a_Attribute_read(input));
        }
    } else {
        var _n2492 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2492) {
            var _tag2493 = input.unsigned();
            if (_tag2493 & 1 == 1) {
                if (!input.merging) {
                    _f2491.append(was.attributes[_tag2493 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2491.append(_read);
                }
            }
        }
    }
    var _f2498 = input.loc();
    var _o2500 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2501 = Array<EnumCaseDef>();
        var _n2502 = input.count();
        for (var _ in 0.._n2502) {
            _v2501.append(_m_EnumCaseDef_read(input));
        }
        _o2500 = Optional<Array<EnumCaseDef>>.Value(_v2501);
    }
    var _f2503 = _o2500;
    return StructDef(
        _f2367, _f2368, _f2380, _f2398, _f2416, _f2434, _f2452, _f2459, _f2460, _f2461, _f2473, _f2491, _f2498, _f2503
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    ulong _j2386 = 0;
    for (var _item2369 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2369);
        base.add($"s.{slot}.generic_params", scratch, _j2386);
        _j2386 += 1;
    }
    ulong _j2404 = 0;
    for (var _item2387 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2387);
        base.add($"s.{slot}.field_members", scratch, _j2404);
        _j2404 += 1;
    }
    ulong _j2422 = 0;
    for (var _item2405 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2405);
        base.add($"s.{slot}.method_members", scratch, _j2422);
        _j2422 += 1;
    }
    ulong _j2440 = 0;
    for (var _item2423 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2423);
        base.add($"s.{slot}.generic_methods", scratch, _j2440);
        _j2440 += 1;
    }
    ulong _j2458 = 0;
    for (var _item2441 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2441);
        base.add($"s.{slot}.constructors", scratch, _j2458);
        _j2458 += 1;
    }
    ulong _j2479 = 0;
    for (var _item2462 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2462);
        base.add($"s.{slot}.traits", scratch, _j2479);
        _j2479 += 1;
    }
    ulong _j2497 = 0;
    for (var _item2480 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2480);
        base.add($"s.{slot}.attributes", scratch, _j2497);
        _j2497 += 1;
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _hs2512 = Array<String>();
    for (var _item2506 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2506);
        _hs2512.append(base.hash_of(scratch));
    }
    var _seq2513 = base.sequence($"t.{slot}.generic_params");
    ulong _bj2514 = 0;
    var _news2515 = Array<ulong>();
    for (var _i2516 in 0.._hs2512.count) {
        if (_bj2514 < _seq2513.count and _hs2512[_i2516] == _seq2513[_bj2514]) {
            _bj2514 += 1;
        } else {
            _news2515.append(_i2516);
        }
    }
    if (_bj2514 == _seq2513.count) {
        out.unsigned(2);
        out.unsigned(_news2515.count);
        for (var _i2516 in _news2515) {
            out.unsigned(_i2516);
            _m_GenericParam_write(out, value.generic_params[_i2516]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2516 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2516]);
        }
    }
    var _hs2530 = Array<String>();
    for (var _item2524 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2524);
        _hs2530.append(base.hash_of(scratch));
    }
    var _seq2531 = base.sequence($"t.{slot}.field_members");
    ulong _bj2532 = 0;
    var _news2533 = Array<ulong>();
    for (var _i2534 in 0.._hs2530.count) {
        if (_bj2532 < _seq2531.count and _hs2530[_i2534] == _seq2531[_bj2532]) {
            _bj2532 += 1;
        } else {
            _news2533.append(_i2534);
        }
    }
    if (_bj2532 == _seq2531.count) {
        out.unsigned(2);
        out.unsigned(_news2533.count);
        for (var _i2534 in _news2533) {
            out.unsigned(_i2534);
            _m_VariableDef_write(out, value.field_members[_i2534]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2534 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2534]);
        }
    }
    var _hs2548 = Array<String>();
    for (var _item2542 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2542);
        _hs2548.append(base.hash_of(scratch));
    }
    var _seq2549 = base.sequence($"t.{slot}.method_members");
    ulong _bj2550 = 0;
    var _news2551 = Array<ulong>();
    for (var _i2552 in 0.._hs2548.count) {
        if (_bj2550 < _seq2549.count and _hs2548[_i2552] == _seq2549[_bj2550]) {
            _bj2550 += 1;
        } else {
            _news2551.append(_i2552);
        }
    }
    if (_bj2550 == _seq2549.count) {
        out.unsigned(2);
        out.unsigned(_news2551.count);
        for (var _i2552 in _news2551) {
            out.unsigned(_i2552);
            _m_FunctionDef_write(out, value.method_members[_i2552]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2552 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2552]);
        }
    }
    var _hs2566 = Array<String>();
    for (var _item2560 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2560);
        _hs2566.append(base.hash_of(scratch));
    }
    var _seq2567 = base.sequence($"t.{slot}.generic_methods");
    ulong _bj2568 = 0;
    var _news2569 = Array<ulong>();
    for (var _i2570 in 0.._hs2566.count) {
        if (_bj2568 < _seq2567.count and _hs2566[_i2570] == _seq2567[_bj2568]) {
            _bj2568 += 1;
        } else {
            _news2569.append(_i2570);
        }
    }
    if (_bj2568 == _seq2567.count) {
        out.unsigned(2);
        out.unsigned(_news2569.count);
        for (var _i2570 in _news2569) {
            out.unsigned(_i2570);
            _m_FunctionDef_write(out, value.generic_methods[_i2570]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2570 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2570]);
        }
    }
    var _hs2584 = Array<String>();
    for (var _item2578 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2578);
        _hs2584.append(base.hash_of(scratch));
    }
    var _seq2585 = base.sequence($"t.{slot}.constructors");
    ulong _bj2586 = 0;
    var _news2587 = Array<ulong>();
    for (var _i2588 in 0.._hs2584.count) {
        if (_bj2586 < _seq2585.count and _hs2584[_i2588] == _seq2585[_bj2586]) {
            _bj2586 += 1;
        } else {
            _news2587.append(_i2588);
        }
    }
    if (_bj2586 == _seq2585.count) {
        out.unsigned(2);
        out.unsigned(_news2587.count);
        for (var _i2588 in _news2587) {
            out.unsigned(_i2588);
            _m_FunctionDef_write(out, value.constructors[_i2588]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2588 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2588]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _hs2605 = Array<String>();
    for (var _item2599 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2599);
        _hs2605.append(base.hash_of(scratch));
    }
    var _seq2606 = base.sequence($"t.{slot}.traits");
    ulong _bj2607 = 0;
    var _news2608 = Array<ulong>();
    for (var _i2609 in 0.._hs2605.count) {
        if (_bj2607 < _seq2606.count and _hs2605[_i2609] == _seq2606[_bj2607]) {
            _bj2607 += 1;
        } else {
            _news2608.append(_i2609);
        }
    }
    if (_bj2607 == _seq2606.count) {
        out.unsigned(2);
        out.unsigned(_news2608.count);
        for (var _i2609 in _news2608) {
            out.unsigned(_i2609);
            _m_TypeName_write(out, value.traits[_i2609]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2609 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2609]);
        }
    }
    var _hs2623 = Array<String>();
    for (var _item2617 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2617);
        _hs2623.append(base.hash_of(scratch));
    }
    var _seq2624 = base.sequence($"t.{slot}.attributes");
    ulong _bj2625 = 0;
    var _news2626 = Array<ulong>();
    for (var _i2627 in 0.._hs2623.count) {
        if (_bj2625 < _seq2624.count and _hs2623[_i2627] == _seq2624[_bj2625]) {
            _bj2625 += 1;
        } else {
            _news2626.append(_i2627);
        }
    }
    if (_bj2625 == _seq2624.count) {
        out.unsigned(2);
        out.unsigned(_news2626.count);
        for (var _i2627 in _news2626) {
            out.unsigned(_i2627);
            _a_Attribute_write(out, value.attributes[_i2627]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2627 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2627]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2636 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2636);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2504 = input.text();
    var _f2505 = _m_TypeName_read(input);
    var _f2517 = Array<GenericParam>();
    var _mode2520 = input.unsigned();
    if (_mode2520 == 2) {
        var _changed2507 = HashMap<ulong, GenericParam>();
        ulong _bi2521 = 0;
        var _n2518 = input.count();
        for (var _ in 0.._n2518) {
            var _at2522 = input.unsigned();
            while (_f2517.count < _at2522 or (input.merging and _bi2521 < was.generic_params.count)) {
                var _c = _changed2507.try_get(_bi2521);
                _f2517.append(_c.is_value() ? _c.value() : was.generic_params[_bi2521]);
                _bi2521 += 1;
            }
            _f2517.append(_m_GenericParam_read(input));
        }
        while (_bi2521 < was.generic_params.count) {
            var _c = _changed2507.try_get(_bi2521);
            _f2517.append(_c.is_value() ? _c.value() : was.generic_params[_bi2521]);
            _bi2521 += 1;
        }
    } else if (_mode2520 == 3) {
        var _n2518 = input.count();
        for (var _ in 0.._n2518) {
            _f2517.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2518 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2518) {
            var _tag2519 = input.unsigned();
            if (_tag2519 & 1 == 1) {
                if (!input.merging) {
                    _f2517.append(was.generic_params[_tag2519 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2517.append(_read);
                }
            }
        }
    }
    var _f2535 = Array<VariableDef>();
    var _mode2538 = input.unsigned();
    if (_mode2538 == 2) {
        var _changed2525 = HashMap<ulong, VariableDef>();
        ulong _bi2539 = 0;
        var _n2536 = input.count();
        for (var _ in 0.._n2536) {
            var _at2540 = input.unsigned();
            while (_f2535.count < _at2540 or (input.merging and _bi2539 < was.field_members.count)) {
                var _c = _changed2525.try_get(_bi2539);
                _f2535.append(_c.is_value() ? _c.value() : was.field_members[_bi2539]);
                _bi2539 += 1;
            }
            _f2535.append(_m_VariableDef_read(input));
        }
        while (_bi2539 < was.field_members.count) {
            var _c = _changed2525.try_get(_bi2539);
            _f2535.append(_c.is_value() ? _c.value() : was.field_members[_bi2539]);
            _bi2539 += 1;
        }
    } else if (_mode2538 == 3) {
        var _n2536 = input.count();
        for (var _ in 0.._n2536) {
            _f2535.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2536 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2536) {
            var _tag2537 = input.unsigned();
            if (_tag2537 & 1 == 1) {
                if (!input.merging) {
                    _f2535.append(was.field_members[_tag2537 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2535.append(_read);
                }
            }
        }
    }
    var _f2553 = Array<FunctionDef>();
    var _mode2556 = input.unsigned();
    if (_mode2556 == 2) {
        var _changed2543 = HashMap<ulong, FunctionDef>();
        ulong _bi2557 = 0;
        var _n2554 = input.count();
        for (var _ in 0.._n2554) {
            var _at2558 = input.unsigned();
            while (_f2553.count < _at2558 or (input.merging and _bi2557 < was.method_members.count)) {
                var _c = _changed2543.try_get(_bi2557);
                _f2553.append(_c.is_value() ? _c.value() : was.method_members[_bi2557]);
                _bi2557 += 1;
            }
            _f2553.append(_m_FunctionDef_read(input));
        }
        while (_bi2557 < was.method_members.count) {
            var _c = _changed2543.try_get(_bi2557);
            _f2553.append(_c.is_value() ? _c.value() : was.method_members[_bi2557]);
            _bi2557 += 1;
        }
    } else if (_mode2556 == 3) {
        var _n2554 = input.count();
        for (var _ in 0.._n2554) {
            _f2553.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2554 = input.count();
        if (input.merging) {
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2554) {
            var _tag2555 = input.unsigned();
            if (_tag2555 & 1 == 1) {
                if (!input.merging) {
                    _f2553.append(was.method_members[_tag2555 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2553.append(_read);
                }
            }
        }
    }
    var _f2571 = Array<FunctionDef>();
    var _mode2574 = input.unsigned();
    if (_mode2574 == 2) {
        var _changed2561 = HashMap<ulong, FunctionDef>();
        ulong _bi2575 = 0;
        var _n2572 = input.count();
        for (var _ in 0.._n2572) {
            var _at2576 = input.unsigned();
            while (_f2571.count < _at2576 or (input.merging and _bi2575 < was.generic_methods.count)) {
                var _c = _changed2561.try_get(_bi2575);
                _f2571.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2575]);
                _bi2575 += 1;
            }
            _f2571.append(_m_FunctionDef_read(input));
        }
        while (_bi2575 < was.generic_methods.count) {
            var _c = _changed2561.try_get(_bi2575);
            _f2571.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2575]);
            _bi2575 += 1;
        }
    } else if (_mode2574 == 3) {
        var _n2572 = input.count();
        for (var _ in 0.._n2572) {
            _f2571.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2572 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2572) {
            var _tag2573 = input.unsigned();
            if (_tag2573 & 1 == 1) {
                if (!input.merging) {
                    _f2571.append(was.generic_methods[_tag2573 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2571.append(_read);
                }
            }
        }
    }
    var _f2589 = Array<FunctionDef>();
    var _mode2592 = input.unsigned();
    if (_mode2592 == 2) {
        var _changed2579 = HashMap<ulong, FunctionDef>();
        ulong _bi2593 = 0;
        var _n2590 = input.count();
        for (var _ in 0.._n2590) {
            var _at2594 = input.unsigned();
            while (_f2589.count < _at2594 or (input.merging and _bi2593 < was.constructors.count)) {
                var _c = _changed2579.try_get(_bi2593);
                _f2589.append(_c.is_value() ? _c.value() : was.constructors[_bi2593]);
                _bi2593 += 1;
            }
            _f2589.append(_m_FunctionDef_read(input));
        }
        while (_bi2593 < was.constructors.count) {
            var _c = _changed2579.try_get(_bi2593);
            _f2589.append(_c.is_value() ? _c.value() : was.constructors[_bi2593]);
            _bi2593 += 1;
        }
    } else if (_mode2592 == 3) {
        var _n2590 = input.count();
        for (var _ in 0.._n2590) {
            _f2589.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2590 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2590) {
            var _tag2591 = input.unsigned();
            if (_tag2591 & 1 == 1) {
                if (!input.merging) {
                    _f2589.append(was.constructors[_tag2591 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2589.append(_read);
                }
            }
        }
    }
    var _f2596 = _m_FunctionDef_read(input);
    var _f2597 = _m_FunctionDef_read(input);
    var _f2598 = _m_FunctionDef_read(input);
    var _f2610 = Array<TypeName>();
    var _mode2613 = input.unsigned();
    if (_mode2613 == 2) {
        var _changed2600 = HashMap<ulong, TypeName>();
        ulong _bi2614 = 0;
        var _n2611 = input.count();
        for (var _ in 0.._n2611) {
            var _at2615 = input.unsigned();
            while (_f2610.count < _at2615 or (input.merging and _bi2614 < was.traits.count)) {
                var _c = _changed2600.try_get(_bi2614);
                _f2610.append(_c.is_value() ? _c.value() : was.traits[_bi2614]);
                _bi2614 += 1;
            }
            _f2610.append(_m_TypeName_read(input));
        }
        while (_bi2614 < was.traits.count) {
            var _c = _changed2600.try_get(_bi2614);
            _f2610.append(_c.is_value() ? _c.value() : was.traits[_bi2614]);
            _bi2614 += 1;
        }
    } else if (_mode2613 == 3) {
        var _n2611 = input.count();
        for (var _ in 0.._n2611) {
            _f2610.append(_m_TypeName_read(input));
        }
    } else {
        var _n2611 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2611) {
            var _tag2612 = input.unsigned();
            if (_tag2612 & 1 == 1) {
                if (!input.merging) {
                    _f2610.append(was.traits[_tag2612 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2610.append(_read);
                }
            }
        }
    }
    var _f2628 = Array<ast.Attribute>();
    var _mode2631 = input.unsigned();
    if (_mode2631 == 2) {
        var _changed2618 = HashMap<ulong, ast.Attribute>();
        ulong _bi2632 = 0;
        var _n2629 = input.count();
        for (var _ in 0.._n2629) {
            var _at2633 = input.unsigned();
            while (_f2628.count < _at2633 or (input.merging and _bi2632 < was.attributes.count)) {
                var _c = _changed2618.try_get(_bi2632);
                _f2628.append(_c.is_value() ? _c.value() : was.attributes[_bi2632]);
                _bi2632 += 1;
            }
            _f2628.append(_a_Attribute_read(input));
        }
        while (_bi2632 < was.attributes.count) {
            var _c = _changed2618.try_get(_bi2632);
            _f2628.append(_c.is_value() ? _c.value() : was.attributes[_bi2632]);
            _bi2632 += 1;
        }
    } else if (_mode2631 == 3) {
        var _n2629 = input.count();
        for (var _ in 0.._n2629) {
            _f2628.append(_a_Attribute_read(input));
        }
    } else {
        var _n2629 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2629) {
            var _tag2630 = input.unsigned();
            if (_tag2630 & 1 == 1) {
                if (!input.merging) {
                    _f2628.append(was.attributes[_tag2630 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2628.append(_read);
                }
            }
        }
    }
    var _f2635 = input.loc();
    var _o2637 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2638 = Array<EnumCaseDef>();
        var _n2639 = input.count();
        for (var _ in 0.._n2639) {
            _v2638.append(_m_EnumCaseDef_read(input));
        }
        _o2637 = Optional<Array<EnumCaseDef>>.Value(_v2638);
    }
    var _f2640 = _o2637;
    return StructDef(
        _f2504, _f2505, _f2517, _f2535, _f2553, _f2571, _f2589, _f2596, _f2597, _f2598, _f2610, _f2628, _f2635, _f2640
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    ulong _j2523 = 0;
    for (var _item2506 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2506);
        base.add($"t.{slot}.generic_params", scratch, _j2523);
        _j2523 += 1;
    }
    ulong _j2541 = 0;
    for (var _item2524 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2524);
        base.add($"t.{slot}.field_members", scratch, _j2541);
        _j2541 += 1;
    }
    ulong _j2559 = 0;
    for (var _item2542 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2542);
        base.add($"t.{slot}.method_members", scratch, _j2559);
        _j2559 += 1;
    }
    ulong _j2577 = 0;
    for (var _item2560 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2560);
        base.add($"t.{slot}.generic_methods", scratch, _j2577);
        _j2577 += 1;
    }
    ulong _j2595 = 0;
    for (var _item2578 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2578);
        base.add($"t.{slot}.constructors", scratch, _j2595);
        _j2595 += 1;
    }
    ulong _j2616 = 0;
    for (var _item2599 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2599);
        base.add($"t.{slot}.traits", scratch, _j2616);
        _j2616 += 1;
    }
    ulong _j2634 = 0;
    for (var _item2617 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2617);
        base.add($"t.{slot}.attributes", scratch, _j2634);
        _j2634 += 1;
    }
}

_m_Module_interface_fields(value: Module, interface: bool): Array<(String, String)> {
    var found = Array<(String, String)>();
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.imports.count);
        for (var _item2641 in value.imports) {
            _a_Import_write(out, _item2641);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2642 in value.structs) {
            _m_StructDef_write(out, _item2642);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.traits.count);
        for (var _item2643 in value.traits) {
            _m_TraitDef_write(out, _item2643);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2644 in value.extensions) {
            _m_ExtensionDef_write(out, _item2644);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2645 in value.functions) {
            _m_FunctionDef_write(out, _item2645);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2646 in value.externs) {
            _m_ExternDef_write(out, _item2646);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2647 in value.globals) {
            _m_VariableDef_write(out, _item2647);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2648 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2648);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2649 in value.enums) {
            _m_EnumDef_write(out, _item2649);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2650 in value.struct_specs) {
            _m_TypeName_write(out, _item2650);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2651 in value.func_specs) {
            _m_TypeName_write(out, _item2651);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2652 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2652);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2653 in value.withheld) {
            _m_Withheld_write(out, _item2653);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2654 in value.properties) {
            _m_PropertyDef_write(out, _item2654);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2655 in value.type_uses) {
            _m_TypeUse_write(out, _item2655);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2656 in value.use_contexts) {
            _m_UseContext_write(out, _item2656);
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
            for (var _item2657 in value.literal_args) {
                var (_t2658, _t2659, _t2660) = _item2657;
                out.loc(_t2658);
                out.unsigned(_t2659);
                out.loc(_t2660);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2661 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2661);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2662 in value.trait_types) {
            _m_TraitType_write(out, _item2662);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2663 in value.conversions) {
            _m_Conversion_write(out, _item2663);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2665 = Array<(u8[], u8[], String)>();
        for (var (_key2664, _) in value.overload_sets) {
            var _scratch2666 = out.scratch();
            _scratch2666.text(_key2664);
            var _vscratch2668 = out.scratch();
            _vscratch2668.unsigned(value.overload_sets[_key2664].count);
            for (var _item2669 in value.overload_sets[_key2664]) {
                _vscratch2668.text(_item2669);
            }
            _keys2665.append((_scratch2666.finish(), _vscratch2668.finish(), _key2664));
        }
        _keys2665.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2665.count);
        for (var (_bytes2667, _, _key2664) in _keys2665) {
            out.text(_key2664);
            out.unsigned(value.overload_sets[_key2664].count);
            for (var _item2670 in value.overload_sets[_key2664]) {
                out.text(_item2670);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2672 = Array<(u8[], u8[], String)>();
        for (var (_key2671, _) in value.overload_unions) {
            var _scratch2673 = out.scratch();
            _scratch2673.text(_key2671);
            var _vscratch2675 = out.scratch();
            _vscratch2675.unsigned(value.overload_unions[_key2671].count);
            for (var _item2676 in value.overload_unions[_key2671]) {
                _vscratch2675.unsigned(_item2676.count);
                for (var _item2677 in _item2676) {
                    _vscratch2675.text(_item2677);
                }
            }
            _keys2672.append((_scratch2673.finish(), _vscratch2675.finish(), _key2671));
        }
        _keys2672.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2672.count);
        for (var (_bytes2674, _, _key2671) in _keys2672) {
            out.text(_key2671);
            out.unsigned(value.overload_unions[_key2671].count);
            for (var _item2678 in value.overload_unions[_key2671]) {
                out.unsigned(_item2678.count);
                for (var _item2679 in _item2678) {
                    out.text(_item2679);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2681 = Array<(u8[], u8[], String)>();
        for (var (_key2680, _) in value.method_overload_sets) {
            var _scratch2682 = out.scratch();
            _scratch2682.text(_key2680);
            var _vscratch2684 = out.scratch();
            var _keys2686 = Array<(u8[], u8[], String)>();
            for (var (_key2685, _) in value.method_overload_sets[_key2680]) {
                var _scratch2687 = _vscratch2684.scratch();
                _scratch2687.text(_key2685);
                var _vscratch2689 = _vscratch2684.scratch();
                _vscratch2689.unsigned(value.method_overload_sets[_key2680][_key2685].count);
                for (var _item2690 in value.method_overload_sets[_key2680][_key2685]) {
                    _vscratch2689.text(_item2690);
                }
                _keys2686.append((_scratch2687.finish(), _vscratch2689.finish(), _key2685));
            }
            _keys2686.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2684.unsigned(_keys2686.count);
            for (var (_bytes2688, _, _key2685) in _keys2686) {
                _vscratch2684.text(_key2685);
                _vscratch2684.unsigned(value.method_overload_sets[_key2680][_key2685].count);
                for (var _item2691 in value.method_overload_sets[_key2680][_key2685]) {
                    _vscratch2684.text(_item2691);
                }
            }
            _keys2681.append((_scratch2682.finish(), _vscratch2684.finish(), _key2680));
        }
        _keys2681.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2681.count);
        for (var (_bytes2683, _, _key2680) in _keys2681) {
            out.text(_key2680);
            var _keys2693 = Array<(u8[], u8[], String)>();
            for (var (_key2692, _) in value.method_overload_sets[_key2680]) {
                var _scratch2694 = out.scratch();
                _scratch2694.text(_key2692);
                var _vscratch2696 = out.scratch();
                _vscratch2696.unsigned(value.method_overload_sets[_key2680][_key2692].count);
                for (var _item2697 in value.method_overload_sets[_key2680][_key2692]) {
                    _vscratch2696.text(_item2697);
                }
                _keys2693.append((_scratch2694.finish(), _vscratch2696.finish(), _key2692));
            }
            _keys2693.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2693.count);
            for (var (_bytes2695, _, _key2692) in _keys2693) {
                out.text(_key2692);
                out.unsigned(value.method_overload_sets[_key2680][_key2692].count);
                for (var _item2698 in value.method_overload_sets[_key2680][_key2692]) {
                    out.text(_item2698);
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
        var _keys2700 = Array<(u8[], u8[], Loc)>();
        for (var _key2699 in value.private_functions) {
            var _scratch2701 = out.scratch();
            _scratch2701.loc(_key2699);
            var _vscratch2703 = out.scratch();
            _keys2700.append((_scratch2701.finish(), _vscratch2703.finish(), _key2699));
        }
        _keys2700.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2700.count);
        for (var (_bytes2702, _, _key2699) in _keys2700) {
            out.loc(_key2699);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2705 = Array<(u8[], u8[], Loc)>();
        for (var _key2704 in value.file_private_functions) {
            var _scratch2706 = out.scratch();
            _scratch2706.loc(_key2704);
            var _vscratch2708 = out.scratch();
            _keys2705.append((_scratch2706.finish(), _vscratch2708.finish(), _key2704));
        }
        _keys2705.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2705.count);
        for (var (_bytes2707, _, _key2704) in _keys2705) {
            out.loc(_key2704);
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
            for (var _item2709 in value.call_targets) {
                var (_t2710, _t2711) = _item2709;
                out.loc(_t2710);
                out.text(_t2711);
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
            for (var _item2712 in value.argument_names) {
                var (_t2713, _t2714) = _item2712;
                out.loc(_t2713);
                out.text(_t2714);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2715 in value.namespaces) {
            out.text(_item2715);
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
            for (var _item2716 in value.cached_files) {
                out.flag(_item2716);
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
            var _keys2718 = Array<(u8[], u8[], Loc)>();
            for (var (_key2717, _) in value.recorded_summaries) {
                var _scratch2719 = out.scratch();
                _scratch2719.loc(_key2717);
                var _vscratch2721 = out.scratch();
                _vscratch2721.text(value.recorded_summaries[_key2717]);
                _keys2718.append((_scratch2719.finish(), _vscratch2721.finish(), _key2717));
            }
            _keys2718.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2718.count);
            for (var (_bytes2720, _, _key2717) in _keys2718) {
                out.loc(_key2717);
                out.text(value.recorded_summaries[_key2717]);
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
            var _keys2723 = Array<(u8[], u8[], Loc)>();
            for (var _key2722 in value.stripped) {
                var _scratch2724 = out.scratch();
                _scratch2724.loc(_key2722);
                var _vscratch2726 = out.scratch();
                _keys2723.append((_scratch2724.finish(), _vscratch2726.finish(), _key2722));
            }
            _keys2723.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2723.count);
            for (var (_bytes2725, _, _key2722) in _keys2723) {
                out.loc(_key2722);
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
        var _keys2728 = Array<(u8[], u8[], String)>();
        for (var (_key2727, _) in value.spec_requests) {
            var _scratch2729 = out.scratch();
            _scratch2729.text(_key2727);
            var _vscratch2731 = out.scratch();
            _m_SpecRequest_write(_vscratch2731, value.spec_requests[_key2727]);
            _keys2728.append((_scratch2729.finish(), _vscratch2731.finish(), _key2727));
        }
        _keys2728.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2728.count);
        for (var (_bytes2730, _, _key2727) in _keys2728) {
            out.text(_key2727);
            _m_SpecRequest_write(out, value.spec_requests[_key2727]);
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
            for (var _item2732 in value.summaries_to_record) {
                var (_t2733, _t2734) = _item2732;
                out.loc(_t2733);
                out.text(_t2734);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2736 = Array<(u8[], u8[], String)>();
        for (var (_key2735, _) in value.caller_copies) {
            var _scratch2737 = out.scratch();
            _scratch2737.text(_key2735);
            var _vscratch2739 = out.scratch();
            _vscratch2739.unsigned(value.caller_copies[_key2735].count);
            for (var _item2740 in value.caller_copies[_key2735]) {
                _vscratch2739.flag(_item2740);
            }
            _keys2736.append((_scratch2737.finish(), _vscratch2739.finish(), _key2735));
        }
        _keys2736.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2736.count);
        for (var (_bytes2738, _, _key2735) in _keys2736) {
            out.text(_key2735);
            out.unsigned(value.caller_copies[_key2735].count);
            for (var _item2741 in value.caller_copies[_key2735]) {
                out.flag(_item2741);
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
    for (var _item2742 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2742);
        found.append(("structs " + _item2742.name, interface_text(out)));
    }
    for (var _item2743 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2743);
        found.append(("functions " + _item2743.name, interface_text(out)));
    }
    return found;
}
