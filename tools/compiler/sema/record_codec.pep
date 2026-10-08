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

## Returns the interface hash of each element of `module`'s lists, each
## entry of its sets and maps, and each other field whole, as (field, hash)
## pairs: a layer's own interface is what these gain and lose across it.
##
## @param module the module
## @returns (field, hash) pairs
export interface_elements(module: Module): Array<(String, String)> {
    return _m_Module_interface_elements(module);
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
    var _hs1483 = Array<String>();
    for (var _item1480 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1480);
        _hs1483.append(base.hash_of(scratch));
    }
    var _seq1484 = base.sequence("imports");
    ulong _bj1485 = 0;
    var _news1486 = Array<ulong>();
    for (var _i1487 in 0.._hs1483.count) {
        if (_bj1485 < _seq1484.count and _hs1483[_i1487] == _seq1484[_bj1485]) {
            _bj1485 += 1;
        } else {
            _news1486.append(_i1487);
        }
    }
    for (var _i1487 in 0.._hs1483.count) {
        next.add_hashed("imports", _hs1483[_i1487], _i1487);
    }
    if (_bj1485 == _seq1484.count) {
        out.unsigned(2);
        out.unsigned(_news1486.count);
        for (var _i1487 in _news1486) {
            out.unsigned(_i1487);
            _a_Import_write(out, value.imports[_i1487]);
        }
        base.count("imports" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("imports" + " by place", 0);
        var _hits1481 = HashSet<long>();
        out.unsigned(value.imports.count);
        for (var _i1487 in 0..value.imports.count) {
            var at = base.find_hashed("imports", _hs1483[_i1487]);
            if (at >= 0) {
                _hits1481.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _a_Import_write(out, value.imports[_i1487]);
            }
        }
        base.missed("imports", "imports", _hits1481.count);
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1497 = Array<String>();
    for (var _item1495 in value.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1495);
        _hs1497.append(base.hash_of(scratch));
    }
    var _seq1498 = base.sequence("s");
    var _seqn1499 = base.sequence("s#");
    ulong _bj1500 = 0;
    var _news1501 = Array<ulong>();
    var _patches1502 = Array<(ulong, ulong)>();
    for (var _i1503 in 0.._hs1497.count) {
        if (_bj1500 < _seq1498.count and _hs1497[_i1503] == _seq1498[_bj1500]) {
            _bj1500 += 1;
        } else if (_bj1500 < _seq1498.count
            and _bj1500 < _seqn1499.count
            and value.structs[_i1503].name == _seqn1499[_bj1500]) {
            _patches1502.append((_i1503, _bj1500));
            _bj1500 += 1;
        } else {
            _news1501.append(_i1503);
        }
    }
    if (_bj1500 == _seq1498.count) {
        out.unsigned(2);
        out.unsigned(_patches1502.count);
        for (var (_i1503, _b) in _patches1502) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1503].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1503], base, _b);
            base.count("s patched", out.values.count - _before);
        }
        out.unsigned(_news1501.count);
        for (var _i1503 in _news1501) {
            ulong _before = out.values.count;
            out.unsigned(_i1503);
            _m_StructDef_write(out, value.structs[_i1503]);
            base.count("s new", out.values.count - _before);
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1496 = HashSet<long>();
        out.unsigned(value.structs.count);
        for (var _i1503 in 0..value.structs.count) {
            var _item1495 = value.structs[_i1503];
            var at = base.find_hashed("s", _hs1497[_i1503]);
            var named = base.named("s", _item1495.name);
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1496.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1496.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1495, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1495);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1496.count);
    }
    for (var _i1503 in 0.._hs1497.count) {
        next.add_hashed("s", _hs1497[_i1503], _i1503);
        next.name("s", value.structs[_i1503].name, _i1503);
        _patch_s_index(value.structs[_i1503], next, _i1503);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1515 = Array<String>();
    for (var _item1512 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1512);
        _hs1515.append(base.hash_of(scratch));
    }
    var _seq1516 = base.sequence("traits");
    ulong _bj1517 = 0;
    var _news1518 = Array<ulong>();
    for (var _i1519 in 0.._hs1515.count) {
        if (_bj1517 < _seq1516.count and _hs1515[_i1519] == _seq1516[_bj1517]) {
            _bj1517 += 1;
        } else {
            _news1518.append(_i1519);
        }
    }
    for (var _i1519 in 0.._hs1515.count) {
        next.add_hashed("traits", _hs1515[_i1519], _i1519);
    }
    if (_bj1517 == _seq1516.count) {
        out.unsigned(2);
        out.unsigned(_news1518.count);
        for (var _i1519 in _news1518) {
            out.unsigned(_i1519);
            _m_TraitDef_write(out, value.traits[_i1519]);
        }
        base.count("traits" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("traits" + " by place", 0);
        var _hits1513 = HashSet<long>();
        out.unsigned(value.traits.count);
        for (var _i1519 in 0..value.traits.count) {
            var at = base.find_hashed("traits", _hs1515[_i1519]);
            if (at >= 0) {
                _hits1513.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_TraitDef_write(out, value.traits[_i1519]);
            }
        }
        base.missed("traits", "traits", _hits1513.count);
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1530 = Array<String>();
    for (var _item1527 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1527);
        _hs1530.append(base.hash_of(scratch));
    }
    var _seq1531 = base.sequence("extensions");
    ulong _bj1532 = 0;
    var _news1533 = Array<ulong>();
    for (var _i1534 in 0.._hs1530.count) {
        if (_bj1532 < _seq1531.count and _hs1530[_i1534] == _seq1531[_bj1532]) {
            _bj1532 += 1;
        } else {
            _news1533.append(_i1534);
        }
    }
    for (var _i1534 in 0.._hs1530.count) {
        next.add_hashed("extensions", _hs1530[_i1534], _i1534);
    }
    if (_bj1532 == _seq1531.count) {
        out.unsigned(2);
        out.unsigned(_news1533.count);
        for (var _i1534 in _news1533) {
            out.unsigned(_i1534);
            _m_ExtensionDef_write(out, value.extensions[_i1534]);
        }
        base.count("extensions" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("extensions" + " by place", 0);
        var _hits1528 = HashSet<long>();
        out.unsigned(value.extensions.count);
        for (var _i1534 in 0..value.extensions.count) {
            var at = base.find_hashed("extensions", _hs1530[_i1534]);
            if (at >= 0) {
                _hits1528.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_ExtensionDef_write(out, value.extensions[_i1534]);
            }
        }
        base.missed("extensions", "extensions", _hits1528.count);
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1545 = Array<String>();
    for (var _item1542 in value.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1542);
        _hs1545.append(base.hash_of(scratch));
    }
    var _seq1546 = base.sequence("functions");
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
        next.add_hashed("functions", _hs1545[_i1549], _i1549);
    }
    if (_bj1547 == _seq1546.count) {
        out.unsigned(2);
        out.unsigned(_news1548.count);
        for (var _i1549 in _news1548) {
            out.unsigned(_i1549);
            _m_FunctionDef_write(out, value.functions[_i1549]);
        }
        base.count("functions" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("functions" + " by place", 0);
        var _hits1543 = HashSet<long>();
        out.unsigned(value.functions.count);
        for (var _i1549 in 0..value.functions.count) {
            var at = base.find_hashed("functions", _hs1545[_i1549]);
            if (at >= 0) {
                _hits1543.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_FunctionDef_write(out, value.functions[_i1549]);
            }
        }
        base.missed("functions", "functions", _hits1543.count);
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1560 = Array<String>();
    for (var _item1557 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1557);
        _hs1560.append(base.hash_of(scratch));
    }
    var _seq1561 = base.sequence("externs");
    ulong _bj1562 = 0;
    var _news1563 = Array<ulong>();
    for (var _i1564 in 0.._hs1560.count) {
        if (_bj1562 < _seq1561.count and _hs1560[_i1564] == _seq1561[_bj1562]) {
            _bj1562 += 1;
        } else {
            _news1563.append(_i1564);
        }
    }
    for (var _i1564 in 0.._hs1560.count) {
        next.add_hashed("externs", _hs1560[_i1564], _i1564);
    }
    if (_bj1562 == _seq1561.count) {
        out.unsigned(2);
        out.unsigned(_news1563.count);
        for (var _i1564 in _news1563) {
            out.unsigned(_i1564);
            _m_ExternDef_write(out, value.externs[_i1564]);
        }
        base.count("externs" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("externs" + " by place", 0);
        var _hits1558 = HashSet<long>();
        out.unsigned(value.externs.count);
        for (var _i1564 in 0..value.externs.count) {
            var at = base.find_hashed("externs", _hs1560[_i1564]);
            if (at >= 0) {
                _hits1558.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_ExternDef_write(out, value.externs[_i1564]);
            }
        }
        base.missed("externs", "externs", _hits1558.count);
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1575 = Array<String>();
    for (var _item1572 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1572);
        _hs1575.append(base.hash_of(scratch));
    }
    var _seq1576 = base.sequence("globals");
    ulong _bj1577 = 0;
    var _news1578 = Array<ulong>();
    for (var _i1579 in 0.._hs1575.count) {
        if (_bj1577 < _seq1576.count and _hs1575[_i1579] == _seq1576[_bj1577]) {
            _bj1577 += 1;
        } else {
            _news1578.append(_i1579);
        }
    }
    for (var _i1579 in 0.._hs1575.count) {
        next.add_hashed("globals", _hs1575[_i1579], _i1579);
    }
    if (_bj1577 == _seq1576.count) {
        out.unsigned(2);
        out.unsigned(_news1578.count);
        for (var _i1579 in _news1578) {
            out.unsigned(_i1579);
            _m_VariableDef_write(out, value.globals[_i1579]);
        }
        base.count("globals" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("globals" + " by place", 0);
        var _hits1573 = HashSet<long>();
        out.unsigned(value.globals.count);
        for (var _i1579 in 0..value.globals.count) {
            var at = base.find_hashed("globals", _hs1575[_i1579]);
            if (at >= 0) {
                _hits1573.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_VariableDef_write(out, value.globals[_i1579]);
            }
        }
        base.missed("globals", "globals", _hits1573.count);
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1590 = Array<String>();
    for (var _item1587 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1587);
        _hs1590.append(base.hash_of(scratch));
    }
    var _seq1591 = base.sequence("static_blocks");
    ulong _bj1592 = 0;
    var _news1593 = Array<ulong>();
    for (var _i1594 in 0.._hs1590.count) {
        if (_bj1592 < _seq1591.count and _hs1590[_i1594] == _seq1591[_bj1592]) {
            _bj1592 += 1;
        } else {
            _news1593.append(_i1594);
        }
    }
    for (var _i1594 in 0.._hs1590.count) {
        next.add_hashed("static_blocks", _hs1590[_i1594], _i1594);
    }
    if (_bj1592 == _seq1591.count) {
        out.unsigned(2);
        out.unsigned(_news1593.count);
        for (var _i1594 in _news1593) {
            out.unsigned(_i1594);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1594]);
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("static_blocks" + " by place", 0);
        var _hits1588 = HashSet<long>();
        out.unsigned(value.static_blocks.count);
        for (var _i1594 in 0..value.static_blocks.count) {
            var at = base.find_hashed("static_blocks", _hs1590[_i1594]);
            if (at >= 0) {
                _hits1588.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_ModuleStaticBlock_write(out, value.static_blocks[_i1594]);
            }
        }
        base.missed("static_blocks", "static_blocks", _hits1588.count);
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1605 = Array<String>();
    for (var _item1602 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1602);
        _hs1605.append(base.hash_of(scratch));
    }
    var _seq1606 = base.sequence("enums");
    ulong _bj1607 = 0;
    var _news1608 = Array<ulong>();
    for (var _i1609 in 0.._hs1605.count) {
        if (_bj1607 < _seq1606.count and _hs1605[_i1609] == _seq1606[_bj1607]) {
            _bj1607 += 1;
        } else {
            _news1608.append(_i1609);
        }
    }
    for (var _i1609 in 0.._hs1605.count) {
        next.add_hashed("enums", _hs1605[_i1609], _i1609);
    }
    if (_bj1607 == _seq1606.count) {
        out.unsigned(2);
        out.unsigned(_news1608.count);
        for (var _i1609 in _news1608) {
            out.unsigned(_i1609);
            _m_EnumDef_write(out, value.enums[_i1609]);
        }
        base.count("enums" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("enums" + " by place", 0);
        var _hits1603 = HashSet<long>();
        out.unsigned(value.enums.count);
        for (var _i1609 in 0..value.enums.count) {
            var at = base.find_hashed("enums", _hs1605[_i1609]);
            if (at >= 0) {
                _hits1603.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_EnumDef_write(out, value.enums[_i1609]);
            }
        }
        base.missed("enums", "enums", _hits1603.count);
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1620 = Array<String>();
    for (var _item1617 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1617);
        _hs1620.append(base.hash_of(scratch));
    }
    var _seq1621 = base.sequence("struct_specs");
    ulong _bj1622 = 0;
    var _news1623 = Array<ulong>();
    for (var _i1624 in 0.._hs1620.count) {
        if (_bj1622 < _seq1621.count and _hs1620[_i1624] == _seq1621[_bj1622]) {
            _bj1622 += 1;
        } else {
            _news1623.append(_i1624);
        }
    }
    for (var _i1624 in 0.._hs1620.count) {
        next.add_hashed("struct_specs", _hs1620[_i1624], _i1624);
    }
    if (_bj1622 == _seq1621.count) {
        out.unsigned(2);
        out.unsigned(_news1623.count);
        for (var _i1624 in _news1623) {
            out.unsigned(_i1624);
            _m_TypeName_write(out, value.struct_specs[_i1624]);
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("struct_specs" + " by place", 0);
        var _hits1618 = HashSet<long>();
        out.unsigned(value.struct_specs.count);
        for (var _i1624 in 0..value.struct_specs.count) {
            var at = base.find_hashed("struct_specs", _hs1620[_i1624]);
            if (at >= 0) {
                _hits1618.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_TypeName_write(out, value.struct_specs[_i1624]);
            }
        }
        base.missed("struct_specs", "struct_specs", _hits1618.count);
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1635 = Array<String>();
    for (var _item1632 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1632);
        _hs1635.append(base.hash_of(scratch));
    }
    var _seq1636 = base.sequence("func_specs");
    ulong _bj1637 = 0;
    var _news1638 = Array<ulong>();
    for (var _i1639 in 0.._hs1635.count) {
        if (_bj1637 < _seq1636.count and _hs1635[_i1639] == _seq1636[_bj1637]) {
            _bj1637 += 1;
        } else {
            _news1638.append(_i1639);
        }
    }
    for (var _i1639 in 0.._hs1635.count) {
        next.add_hashed("func_specs", _hs1635[_i1639], _i1639);
    }
    if (_bj1637 == _seq1636.count) {
        out.unsigned(2);
        out.unsigned(_news1638.count);
        for (var _i1639 in _news1638) {
            out.unsigned(_i1639);
            _m_TypeName_write(out, value.func_specs[_i1639]);
        }
        base.count("func_specs" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("func_specs" + " by place", 0);
        var _hits1633 = HashSet<long>();
        out.unsigned(value.func_specs.count);
        for (var _i1639 in 0..value.func_specs.count) {
            var at = base.find_hashed("func_specs", _hs1635[_i1639]);
            if (at >= 0) {
                _hits1633.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_TypeName_write(out, value.func_specs[_i1639]);
            }
        }
        base.missed("func_specs", "func_specs", _hits1633.count);
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1648 = HashSet<long>();
    ulong _nj1649 = 0;
    out.unsigned(value.type_aliases.count);
    for (var _item1647 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1647);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1648.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1647);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1648.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1657 = Array<String>();
    for (var _item1654 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1654);
        _hs1657.append(base.hash_of(scratch));
    }
    var _seq1658 = base.sequence("withheld");
    ulong _bj1659 = 0;
    var _news1660 = Array<ulong>();
    for (var _i1661 in 0.._hs1657.count) {
        if (_bj1659 < _seq1658.count and _hs1657[_i1661] == _seq1658[_bj1659]) {
            _bj1659 += 1;
        } else {
            _news1660.append(_i1661);
        }
    }
    for (var _i1661 in 0.._hs1657.count) {
        next.add_hashed("withheld", _hs1657[_i1661], _i1661);
    }
    if (_bj1659 == _seq1658.count) {
        out.unsigned(2);
        out.unsigned(_news1660.count);
        for (var _i1661 in _news1660) {
            out.unsigned(_i1661);
            _m_Withheld_write(out, value.withheld[_i1661]);
        }
        base.count("withheld" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("withheld" + " by place", 0);
        var _hits1655 = HashSet<long>();
        out.unsigned(value.withheld.count);
        for (var _i1661 in 0..value.withheld.count) {
            var at = base.find_hashed("withheld", _hs1657[_i1661]);
            if (at >= 0) {
                _hits1655.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_Withheld_write(out, value.withheld[_i1661]);
            }
        }
        base.missed("withheld", "withheld", _hits1655.count);
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1672 = Array<String>();
    for (var _item1669 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1669);
        _hs1672.append(base.hash_of(scratch));
    }
    var _seq1673 = base.sequence("properties");
    ulong _bj1674 = 0;
    var _news1675 = Array<ulong>();
    for (var _i1676 in 0.._hs1672.count) {
        if (_bj1674 < _seq1673.count and _hs1672[_i1676] == _seq1673[_bj1674]) {
            _bj1674 += 1;
        } else {
            _news1675.append(_i1676);
        }
    }
    for (var _i1676 in 0.._hs1672.count) {
        next.add_hashed("properties", _hs1672[_i1676], _i1676);
    }
    if (_bj1674 == _seq1673.count) {
        out.unsigned(2);
        out.unsigned(_news1675.count);
        for (var _i1676 in _news1675) {
            out.unsigned(_i1676);
            _m_PropertyDef_write(out, value.properties[_i1676]);
        }
        base.count("properties" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("properties" + " by place", 0);
        var _hits1670 = HashSet<long>();
        out.unsigned(value.properties.count);
        for (var _i1676 in 0..value.properties.count) {
            var at = base.find_hashed("properties", _hs1672[_i1676]);
            if (at >= 0) {
                _hits1670.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_PropertyDef_write(out, value.properties[_i1676]);
            }
        }
        base.missed("properties", "properties", _hits1670.count);
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1687 = Array<String>();
    for (var _item1684 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1684);
        _hs1687.append(base.hash_of(scratch));
    }
    var _seq1688 = base.sequence("type_uses");
    ulong _bj1689 = 0;
    var _news1690 = Array<ulong>();
    for (var _i1691 in 0.._hs1687.count) {
        if (_bj1689 < _seq1688.count and _hs1687[_i1691] == _seq1688[_bj1689]) {
            _bj1689 += 1;
        } else {
            _news1690.append(_i1691);
        }
    }
    for (var _i1691 in 0.._hs1687.count) {
        next.add_hashed("type_uses", _hs1687[_i1691], _i1691);
    }
    if (_bj1689 == _seq1688.count) {
        out.unsigned(2);
        out.unsigned(_news1690.count);
        for (var _i1691 in _news1690) {
            out.unsigned(_i1691);
            _m_TypeUse_write(out, value.type_uses[_i1691]);
        }
        base.count("type_uses" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("type_uses" + " by place", 0);
        var _hits1685 = HashSet<long>();
        out.unsigned(value.type_uses.count);
        for (var _i1691 in 0..value.type_uses.count) {
            var at = base.find_hashed("type_uses", _hs1687[_i1691]);
            if (at >= 0) {
                _hits1685.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_TypeUse_write(out, value.type_uses[_i1691]);
            }
        }
        base.missed("type_uses", "type_uses", _hits1685.count);
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1702 = Array<String>();
    for (var _item1699 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1699);
        _hs1702.append(base.hash_of(scratch));
    }
    var _seq1703 = base.sequence("use_contexts");
    ulong _bj1704 = 0;
    var _news1705 = Array<ulong>();
    for (var _i1706 in 0.._hs1702.count) {
        if (_bj1704 < _seq1703.count and _hs1702[_i1706] == _seq1703[_bj1704]) {
            _bj1704 += 1;
        } else {
            _news1705.append(_i1706);
        }
    }
    for (var _i1706 in 0.._hs1702.count) {
        next.add_hashed("use_contexts", _hs1702[_i1706], _i1706);
    }
    if (_bj1704 == _seq1703.count) {
        out.unsigned(2);
        out.unsigned(_news1705.count);
        for (var _i1706 in _news1705) {
            out.unsigned(_i1706);
            _m_UseContext_write(out, value.use_contexts[_i1706]);
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("use_contexts" + " by place", 0);
        var _hits1700 = HashSet<long>();
        out.unsigned(value.use_contexts.count);
        for (var _i1706 in 0..value.use_contexts.count) {
            var at = base.find_hashed("use_contexts", _hs1702[_i1706]);
            if (at >= 0) {
                _hits1700.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_UseContext_write(out, value.use_contexts[_i1706]);
            }
        }
        base.missed("use_contexts", "use_contexts", _hits1700.count);
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1716 = base.size("literal_args");
    var _scratch1715 = base.scratch();
    if (value.literal_args.count >= _n1716) {
        for (var _i1717 in 0.._n1716) {
            var (_t1718, _t1719, _t1720) = value.literal_args[_i1717];
            _scratch1715.loc(_t1718);
            _scratch1715.unsigned(_t1719);
            _scratch1715.loc(_t1720);
        }
    }
    if (value.literal_args.count >= _n1716 and base.same_list("literal_args", _scratch1715)) {
        out.unsigned(1);
        out.unsigned(_n1716);
        out.unsigned(value.literal_args.count - _n1716);
        for (var _i1717 in _n1716..value.literal_args.count) {
            var (_t1721, _t1722, _t1723) = value.literal_args[_i1717];
            out.loc(_t1721);
            out.unsigned(_t1722);
            out.loc(_t1723);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1724 in value.literal_args) {
            var (_t1725, _t1726, _t1727) = _item1724;
            out.loc(_t1725);
            out.unsigned(_t1726);
            out.loc(_t1727);
        }
        base.count("literal_args whole", 0);
    }
    var _xscratch1740 = next.scratch();
    for (var _xitem1741 in value.literal_args) {
        var (_t1742, _t1743, _t1744) = _xitem1741;
        _xscratch1740.loc(_t1742);
        _xscratch1740.unsigned(_t1743);
        _xscratch1740.loc(_t1744);
    }
    next.keep_list("literal_args", value.literal_args.count, _xscratch1740);
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1748 = Array<String>();
    for (var _item1745 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1745);
        _hs1748.append(base.hash_of(scratch));
    }
    var _seq1749 = base.sequence("constrained_aliases");
    ulong _bj1750 = 0;
    var _news1751 = Array<ulong>();
    for (var _i1752 in 0.._hs1748.count) {
        if (_bj1750 < _seq1749.count and _hs1748[_i1752] == _seq1749[_bj1750]) {
            _bj1750 += 1;
        } else {
            _news1751.append(_i1752);
        }
    }
    for (var _i1752 in 0.._hs1748.count) {
        next.add_hashed("constrained_aliases", _hs1748[_i1752], _i1752);
    }
    if (_bj1750 == _seq1749.count) {
        out.unsigned(2);
        out.unsigned(_news1751.count);
        for (var _i1752 in _news1751) {
            out.unsigned(_i1752);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1752]);
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("constrained_aliases" + " by place", 0);
        var _hits1746 = HashSet<long>();
        out.unsigned(value.constrained_aliases.count);
        for (var _i1752 in 0..value.constrained_aliases.count) {
            var at = base.find_hashed("constrained_aliases", _hs1748[_i1752]);
            if (at >= 0) {
                _hits1746.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_TypeAliasDef_write(out, value.constrained_aliases[_i1752]);
            }
        }
        base.missed("constrained_aliases", "constrained_aliases", _hits1746.count);
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1763 = Array<String>();
    for (var _item1760 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1760);
        _hs1763.append(base.hash_of(scratch));
    }
    var _seq1764 = base.sequence("trait_types");
    ulong _bj1765 = 0;
    var _news1766 = Array<ulong>();
    for (var _i1767 in 0.._hs1763.count) {
        if (_bj1765 < _seq1764.count and _hs1763[_i1767] == _seq1764[_bj1765]) {
            _bj1765 += 1;
        } else {
            _news1766.append(_i1767);
        }
    }
    for (var _i1767 in 0.._hs1763.count) {
        next.add_hashed("trait_types", _hs1763[_i1767], _i1767);
    }
    if (_bj1765 == _seq1764.count) {
        out.unsigned(2);
        out.unsigned(_news1766.count);
        for (var _i1767 in _news1766) {
            out.unsigned(_i1767);
            _m_TraitType_write(out, value.trait_types[_i1767]);
        }
        base.count("trait_types" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("trait_types" + " by place", 0);
        var _hits1761 = HashSet<long>();
        out.unsigned(value.trait_types.count);
        for (var _i1767 in 0..value.trait_types.count) {
            var at = base.find_hashed("trait_types", _hs1763[_i1767]);
            if (at >= 0) {
                _hits1761.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_TraitType_write(out, value.trait_types[_i1767]);
            }
        }
        base.missed("trait_types", "trait_types", _hits1761.count);
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1778 = Array<String>();
    for (var _item1775 in value.conversions) {
        var scratch = base.scratch();
        _m_Conversion_write(scratch, _item1775);
        _hs1778.append(base.hash_of(scratch));
    }
    var _seq1779 = base.sequence("conversions");
    ulong _bj1780 = 0;
    var _news1781 = Array<ulong>();
    for (var _i1782 in 0.._hs1778.count) {
        if (_bj1780 < _seq1779.count and _hs1778[_i1782] == _seq1779[_bj1780]) {
            _bj1780 += 1;
        } else {
            _news1781.append(_i1782);
        }
    }
    for (var _i1782 in 0.._hs1778.count) {
        next.add_hashed("conversions", _hs1778[_i1782], _i1782);
    }
    if (_bj1780 == _seq1779.count) {
        out.unsigned(2);
        out.unsigned(_news1781.count);
        for (var _i1782 in _news1781) {
            out.unsigned(_i1782);
            _m_Conversion_write(out, value.conversions[_i1782]);
        }
        base.count("conversions" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("conversions" + " by place", 0);
        var _hits1776 = HashSet<long>();
        out.unsigned(value.conversions.count);
        for (var _i1782 in 0..value.conversions.count) {
            var at = base.find_hashed("conversions", _hs1778[_i1782]);
            if (at >= 0) {
                _hits1776.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_Conversion_write(out, value.conversions[_i1782]);
            }
        }
        base.missed("conversions", "conversions", _hits1776.count);
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1793 = 0;
    var _news1794 = Map<String, Array<String>>();
    for (var (_key1790, _) in value.overload_sets) {
        var _kscratch1791 = base.scratch();
        _kscratch1791.text(_key1790);
        var _vscratch1792 = base.scratch();
        _vscratch1792.unsigned(value.overload_sets[_key1790].count);
        for (var _item1795 in value.overload_sets[_key1790]) {
            _vscratch1792.text(_item1795);
        }
        var _had = base.entry("overload_sets", _kscratch1791, _vscratch1792);
        if (_had >= 0) {
            _kept1793 += 1;
        }
        if (_had != 1) {
            _news1794[_key1790] = value.overload_sets[_key1790];
        }
    }
    if (_kept1793 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1797 = Array<(u8[], u8[], String)>();
        for (var (_key1796, _) in _news1794) {
            var _scratch1798 = out.scratch();
            _scratch1798.text(_key1796);
            var _vscratch1800 = out.scratch();
            _vscratch1800.unsigned(_news1794[_key1796].count);
            for (var _item1801 in _news1794[_key1796]) {
                _vscratch1800.text(_item1801);
            }
            _keys1797.append((_scratch1798.finish(), _vscratch1800.finish(), _key1796));
        }
        _keys1797.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1797.count);
        for (var (_bytes1799, _, _key1796) in _keys1797) {
            out.text(_key1796);
            out.unsigned(_news1794[_key1796].count);
            for (var _item1802 in _news1794[_key1796]) {
                out.text(_item1802);
            }
        }
    } else {
        out.unsigned(0);
        var _keys1804 = Array<(u8[], u8[], String)>();
        for (var (_key1803, _) in value.overload_sets) {
            var _scratch1805 = out.scratch();
            _scratch1805.text(_key1803);
            var _vscratch1807 = out.scratch();
            _vscratch1807.unsigned(value.overload_sets[_key1803].count);
            for (var _item1808 in value.overload_sets[_key1803]) {
                _vscratch1807.text(_item1808);
            }
            _keys1804.append((_scratch1805.finish(), _vscratch1807.finish(), _key1803));
        }
        _keys1804.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1804.count);
        for (var (_bytes1806, _, _key1803) in _keys1804) {
            out.text(_key1803);
            out.unsigned(value.overload_sets[_key1803].count);
            for (var _item1809 in value.overload_sets[_key1803]) {
                out.text(_item1809);
            }
        }
        base.count("overload_sets whole", 0);
    }
    for (var (_key1790, _) in value.overload_sets) {
        var _kscratch1791 = next.scratch();
        _kscratch1791.text(_key1790);
        var _vscratch1792 = next.scratch();
        _vscratch1792.unsigned(value.overload_sets[_key1790].count);
        for (var _item1823 in value.overload_sets[_key1790]) {
            _vscratch1792.text(_item1823);
        }
        next.keep_entry("overload_sets", _kscratch1791, _vscratch1792);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1827 = 0;
    var _news1828 = Map<String, Array<Array<String>>>();
    for (var (_key1824, _) in value.overload_unions) {
        var _kscratch1825 = base.scratch();
        _kscratch1825.text(_key1824);
        var _vscratch1826 = base.scratch();
        _vscratch1826.unsigned(value.overload_unions[_key1824].count);
        for (var _item1829 in value.overload_unions[_key1824]) {
            _vscratch1826.unsigned(_item1829.count);
            for (var _item1830 in _item1829) {
                _vscratch1826.text(_item1830);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1825, _vscratch1826);
        if (_had >= 0) {
            _kept1827 += 1;
        }
        if (_had != 1) {
            _news1828[_key1824] = value.overload_unions[_key1824];
        }
    }
    if (_kept1827 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1832 = Array<(u8[], u8[], String)>();
        for (var (_key1831, _) in _news1828) {
            var _scratch1833 = out.scratch();
            _scratch1833.text(_key1831);
            var _vscratch1835 = out.scratch();
            _vscratch1835.unsigned(_news1828[_key1831].count);
            for (var _item1836 in _news1828[_key1831]) {
                _vscratch1835.unsigned(_item1836.count);
                for (var _item1837 in _item1836) {
                    _vscratch1835.text(_item1837);
                }
            }
            _keys1832.append((_scratch1833.finish(), _vscratch1835.finish(), _key1831));
        }
        _keys1832.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1832.count);
        for (var (_bytes1834, _, _key1831) in _keys1832) {
            out.text(_key1831);
            out.unsigned(_news1828[_key1831].count);
            for (var _item1838 in _news1828[_key1831]) {
                out.unsigned(_item1838.count);
                for (var _item1839 in _item1838) {
                    out.text(_item1839);
                }
            }
        }
    } else {
        out.unsigned(0);
        var _keys1841 = Array<(u8[], u8[], String)>();
        for (var (_key1840, _) in value.overload_unions) {
            var _scratch1842 = out.scratch();
            _scratch1842.text(_key1840);
            var _vscratch1844 = out.scratch();
            _vscratch1844.unsigned(value.overload_unions[_key1840].count);
            for (var _item1845 in value.overload_unions[_key1840]) {
                _vscratch1844.unsigned(_item1845.count);
                for (var _item1846 in _item1845) {
                    _vscratch1844.text(_item1846);
                }
            }
            _keys1841.append((_scratch1842.finish(), _vscratch1844.finish(), _key1840));
        }
        _keys1841.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1841.count);
        for (var (_bytes1843, _, _key1840) in _keys1841) {
            out.text(_key1840);
            out.unsigned(value.overload_unions[_key1840].count);
            for (var _item1847 in value.overload_unions[_key1840]) {
                out.unsigned(_item1847.count);
                for (var _item1848 in _item1847) {
                    out.text(_item1848);
                }
            }
        }
        base.count("overload_unions whole", 0);
    }
    for (var (_key1824, _) in value.overload_unions) {
        var _kscratch1825 = next.scratch();
        _kscratch1825.text(_key1824);
        var _vscratch1826 = next.scratch();
        _vscratch1826.unsigned(value.overload_unions[_key1824].count);
        for (var _item1866 in value.overload_unions[_key1824]) {
            _vscratch1826.unsigned(_item1866.count);
            for (var _item1867 in _item1866) {
                _vscratch1826.text(_item1867);
            }
        }
        next.keep_entry("overload_unions", _kscratch1825, _vscratch1826);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1871 = 0;
    var _news1872 = Map<String, Map<String, Array<String>>>();
    for (var (_key1868, _) in value.method_overload_sets) {
        var _kscratch1869 = base.scratch();
        _kscratch1869.text(_key1868);
        var _vscratch1870 = base.scratch();
        var _keys1874 = Array<(u8[], u8[], String)>();
        for (var (_key1873, _) in value.method_overload_sets[_key1868]) {
            var _scratch1875 = _vscratch1870.scratch();
            _scratch1875.text(_key1873);
            var _vscratch1877 = _vscratch1870.scratch();
            _vscratch1877.unsigned(value.method_overload_sets[_key1868][_key1873].count);
            for (var _item1878 in value.method_overload_sets[_key1868][_key1873]) {
                _vscratch1877.text(_item1878);
            }
            _keys1874.append((_scratch1875.finish(), _vscratch1877.finish(), _key1873));
        }
        _keys1874.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1870.unsigned(_keys1874.count);
        for (var (_bytes1876, _, _key1873) in _keys1874) {
            _vscratch1870.text(_key1873);
            _vscratch1870.unsigned(value.method_overload_sets[_key1868][_key1873].count);
            for (var _item1879 in value.method_overload_sets[_key1868][_key1873]) {
                _vscratch1870.text(_item1879);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1869, _vscratch1870);
        if (_had >= 0) {
            _kept1871 += 1;
        }
        if (_had != 1) {
            _news1872[_key1868] = value.method_overload_sets[_key1868];
        }
    }
    if (_kept1871 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1881 = Array<(u8[], u8[], String)>();
        for (var (_key1880, _) in _news1872) {
            var _scratch1882 = out.scratch();
            _scratch1882.text(_key1880);
            var _vscratch1884 = out.scratch();
            var _keys1886 = Array<(u8[], u8[], String)>();
            for (var (_key1885, _) in _news1872[_key1880]) {
                var _scratch1887 = _vscratch1884.scratch();
                _scratch1887.text(_key1885);
                var _vscratch1889 = _vscratch1884.scratch();
                _vscratch1889.unsigned(_news1872[_key1880][_key1885].count);
                for (var _item1890 in _news1872[_key1880][_key1885]) {
                    _vscratch1889.text(_item1890);
                }
                _keys1886.append((_scratch1887.finish(), _vscratch1889.finish(), _key1885));
            }
            _keys1886.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1884.unsigned(_keys1886.count);
            for (var (_bytes1888, _, _key1885) in _keys1886) {
                _vscratch1884.text(_key1885);
                _vscratch1884.unsigned(_news1872[_key1880][_key1885].count);
                for (var _item1891 in _news1872[_key1880][_key1885]) {
                    _vscratch1884.text(_item1891);
                }
            }
            _keys1881.append((_scratch1882.finish(), _vscratch1884.finish(), _key1880));
        }
        _keys1881.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1881.count);
        for (var (_bytes1883, _, _key1880) in _keys1881) {
            out.text(_key1880);
            var _keys1893 = Array<(u8[], u8[], String)>();
            for (var (_key1892, _) in _news1872[_key1880]) {
                var _scratch1894 = out.scratch();
                _scratch1894.text(_key1892);
                var _vscratch1896 = out.scratch();
                _vscratch1896.unsigned(_news1872[_key1880][_key1892].count);
                for (var _item1897 in _news1872[_key1880][_key1892]) {
                    _vscratch1896.text(_item1897);
                }
                _keys1893.append((_scratch1894.finish(), _vscratch1896.finish(), _key1892));
            }
            _keys1893.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1893.count);
            for (var (_bytes1895, _, _key1892) in _keys1893) {
                out.text(_key1892);
                out.unsigned(_news1872[_key1880][_key1892].count);
                for (var _item1898 in _news1872[_key1880][_key1892]) {
                    out.text(_item1898);
                }
            }
        }
    } else {
        out.unsigned(0);
        var _keys1900 = Array<(u8[], u8[], String)>();
        for (var (_key1899, _) in value.method_overload_sets) {
            var _scratch1901 = out.scratch();
            _scratch1901.text(_key1899);
            var _vscratch1903 = out.scratch();
            var _keys1905 = Array<(u8[], u8[], String)>();
            for (var (_key1904, _) in value.method_overload_sets[_key1899]) {
                var _scratch1906 = _vscratch1903.scratch();
                _scratch1906.text(_key1904);
                var _vscratch1908 = _vscratch1903.scratch();
                _vscratch1908.unsigned(value.method_overload_sets[_key1899][_key1904].count);
                for (var _item1909 in value.method_overload_sets[_key1899][_key1904]) {
                    _vscratch1908.text(_item1909);
                }
                _keys1905.append((_scratch1906.finish(), _vscratch1908.finish(), _key1904));
            }
            _keys1905.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1903.unsigned(_keys1905.count);
            for (var (_bytes1907, _, _key1904) in _keys1905) {
                _vscratch1903.text(_key1904);
                _vscratch1903.unsigned(value.method_overload_sets[_key1899][_key1904].count);
                for (var _item1910 in value.method_overload_sets[_key1899][_key1904]) {
                    _vscratch1903.text(_item1910);
                }
            }
            _keys1900.append((_scratch1901.finish(), _vscratch1903.finish(), _key1899));
        }
        _keys1900.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1900.count);
        for (var (_bytes1902, _, _key1899) in _keys1900) {
            out.text(_key1899);
            var _keys1912 = Array<(u8[], u8[], String)>();
            for (var (_key1911, _) in value.method_overload_sets[_key1899]) {
                var _scratch1913 = out.scratch();
                _scratch1913.text(_key1911);
                var _vscratch1915 = out.scratch();
                _vscratch1915.unsigned(value.method_overload_sets[_key1899][_key1911].count);
                for (var _item1916 in value.method_overload_sets[_key1899][_key1911]) {
                    _vscratch1915.text(_item1916);
                }
                _keys1912.append((_scratch1913.finish(), _vscratch1915.finish(), _key1911));
            }
            _keys1912.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1912.count);
            for (var (_bytes1914, _, _key1911) in _keys1912) {
                out.text(_key1911);
                out.unsigned(value.method_overload_sets[_key1899][_key1911].count);
                for (var _item1917 in value.method_overload_sets[_key1899][_key1911]) {
                    out.text(_item1917);
                }
            }
        }
        base.count("method_overload_sets whole", 0);
    }
    for (var (_key1868, _) in value.method_overload_sets) {
        var _kscratch1869 = next.scratch();
        _kscratch1869.text(_key1868);
        var _vscratch1870 = next.scratch();
        var _keys1938 = Array<(u8[], u8[], String)>();
        for (var (_key1937, _) in value.method_overload_sets[_key1868]) {
            var _scratch1939 = _vscratch1870.scratch();
            _scratch1939.text(_key1937);
            var _vscratch1941 = _vscratch1870.scratch();
            _vscratch1941.unsigned(value.method_overload_sets[_key1868][_key1937].count);
            for (var _item1942 in value.method_overload_sets[_key1868][_key1937]) {
                _vscratch1941.text(_item1942);
            }
            _keys1938.append((_scratch1939.finish(), _vscratch1941.finish(), _key1937));
        }
        _keys1938.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1870.unsigned(_keys1938.count);
        for (var (_bytes1940, _, _key1937) in _keys1938) {
            _vscratch1870.text(_key1937);
            _vscratch1870.unsigned(value.method_overload_sets[_key1868][_key1937].count);
            for (var _item1943 in value.method_overload_sets[_key1868][_key1937]) {
                _vscratch1870.text(_item1943);
            }
        }
        next.keep_entry("method_overload_sets", _kscratch1869, _vscratch1870);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1948 = 0;
    var _news1949 = HashSet<Loc>();
    for (var _key1945 in value.private_functions) {
        var _kscratch1946 = base.scratch();
        _kscratch1946.loc(_key1945);
        var _vscratch1947 = base.scratch();
        var _had = base.entry("private_functions", _kscratch1946, _vscratch1947);
        if (_had >= 0) {
            _kept1948 += 1;
        }
        if (_had != 1) {
            _news1949.insert(_key1945);
        }
    }
    if (_kept1948 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys1951 = Array<(u8[], u8[], Loc)>();
        for (var _key1950 in _news1949) {
            var _scratch1952 = out.scratch();
            _scratch1952.loc(_key1950);
            var _vscratch1954 = out.scratch();
            _keys1951.append((_scratch1952.finish(), _vscratch1954.finish(), _key1950));
        }
        _keys1951.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1951.count);
        for (var (_bytes1953, _, _key1950) in _keys1951) {
            out.loc(_key1950);
        }
    } else {
        out.unsigned(0);
        var _keys1956 = Array<(u8[], u8[], Loc)>();
        for (var _key1955 in value.private_functions) {
            var _scratch1957 = out.scratch();
            _scratch1957.loc(_key1955);
            var _vscratch1959 = out.scratch();
            _keys1956.append((_scratch1957.finish(), _vscratch1959.finish(), _key1955));
        }
        _keys1956.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1956.count);
        for (var (_bytes1958, _, _key1955) in _keys1956) {
            out.loc(_key1955);
        }
        base.count("private_functions whole", 0);
    }
    for (var _key1945 in value.private_functions) {
        var _kscratch1946 = next.scratch();
        _kscratch1946.loc(_key1945);
        var _vscratch1947 = next.scratch();
        next.keep_entry("private_functions", _kscratch1946, _vscratch1947);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1970 = 0;
    var _news1971 = HashSet<Loc>();
    for (var _key1967 in value.file_private_functions) {
        var _kscratch1968 = base.scratch();
        _kscratch1968.loc(_key1967);
        var _vscratch1969 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch1968, _vscratch1969);
        if (_had >= 0) {
            _kept1970 += 1;
        }
        if (_had != 1) {
            _news1971.insert(_key1967);
        }
    }
    if (_kept1970 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys1973 = Array<(u8[], u8[], Loc)>();
        for (var _key1972 in _news1971) {
            var _scratch1974 = out.scratch();
            _scratch1974.loc(_key1972);
            var _vscratch1976 = out.scratch();
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
            out.loc(_key1972);
        }
    } else {
        out.unsigned(0);
        var _keys1978 = Array<(u8[], u8[], Loc)>();
        for (var _key1977 in value.file_private_functions) {
            var _scratch1979 = out.scratch();
            _scratch1979.loc(_key1977);
            var _vscratch1981 = out.scratch();
            _keys1978.append((_scratch1979.finish(), _vscratch1981.finish(), _key1977));
        }
        _keys1978.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1978.count);
        for (var (_bytes1980, _, _key1977) in _keys1978) {
            out.loc(_key1977);
        }
        base.count("file_private_functions whole", 0);
    }
    for (var _key1967 in value.file_private_functions) {
        var _kscratch1968 = next.scratch();
        _kscratch1968.loc(_key1967);
        var _vscratch1969 = next.scratch();
        next.keep_entry("file_private_functions", _kscratch1968, _vscratch1969);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n1991 = base.size("call_targets");
    var _scratch1990 = base.scratch();
    if (value.call_targets.count >= _n1991) {
        for (var _i1992 in 0.._n1991) {
            var (_t1993, _t1994) = value.call_targets[_i1992];
            _scratch1990.loc(_t1993);
            _scratch1990.text(_t1994);
        }
    }
    if (value.call_targets.count >= _n1991 and base.same_list("call_targets", _scratch1990)) {
        out.unsigned(1);
        out.unsigned(_n1991);
        out.unsigned(value.call_targets.count - _n1991);
        for (var _i1992 in _n1991..value.call_targets.count) {
            var (_t1995, _t1996) = value.call_targets[_i1992];
            out.loc(_t1995);
            out.text(_t1996);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item1997 in value.call_targets) {
            var (_t1998, _t1999) = _item1997;
            out.loc(_t1998);
            out.text(_t1999);
        }
        base.count("call_targets whole", 0);
    }
    var _xscratch2010 = next.scratch();
    for (var _xitem2011 in value.call_targets) {
        var (_t2012, _t2013) = _xitem2011;
        _xscratch2010.loc(_t2012);
        _xscratch2010.text(_t2013);
    }
    next.keep_list("call_targets", value.call_targets.count, _xscratch2010);
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2016 = 0;
    var _news2017 = Array<(Loc, String)>();
    for (var _item2014 in value.argument_names) {
        var _escratch2015 = base.scratch();
        var (_t2018, _t2019) = _item2014;
        _escratch2015.loc(_t2018);
        _escratch2015.text(_t2019);
        if (base.entry("argument_names", _escratch2015, base.scratch()) >= 0) {
            _kept2016 += 1;
        } else {
            _news2017.append(_item2014);
        }
    }
    if (_kept2016 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2017.count);
        for (var _item2020 in _news2017) {
            var (_t2021, _t2022) = _item2020;
            out.loc(_t2021);
            out.text(_t2022);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2023 in value.argument_names) {
            var (_t2024, _t2025) = _item2023;
            out.loc(_t2024);
            out.text(_t2025);
        }
        base.count("argument_names whole", 0);
    }
    for (var _item2014 in value.argument_names) {
        var _escratch2015 = next.scratch();
        var (_t2036, _t2037) = _item2014;
        _escratch2015.loc(_t2036);
        _escratch2015.text(_t2037);
        next.keep_entry("argument_names", _escratch2015, next.scratch());
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2040 = base.size("namespaces");
    var _scratch2039 = base.scratch();
    if (value.namespaces.count >= _n2040) {
        for (var _i2041 in 0.._n2040) {
            _scratch2039.text(value.namespaces[_i2041]);
        }
    }
    if (value.namespaces.count >= _n2040 and base.same_list("namespaces", _scratch2039)) {
        out.unsigned(1);
        out.unsigned(_n2040);
        out.unsigned(value.namespaces.count - _n2040);
        for (var _i2041 in _n2040..value.namespaces.count) {
            out.text(value.namespaces[_i2041]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2042 in value.namespaces) {
            out.text(_item2042);
        }
        base.count("namespaces whole", 0);
    }
    var _xscratch2049 = next.scratch();
    for (var _xitem2050 in value.namespaces) {
        _xscratch2049.text(_xitem2050);
    }
    next.keep_list("namespaces", value.namespaces.count, _xscratch2049);
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2053 = base.size("cached_files");
    var _scratch2052 = base.scratch();
    if (value.cached_files.count >= _n2053) {
        for (var _i2054 in 0.._n2053) {
            _scratch2052.flag(value.cached_files[_i2054]);
        }
    }
    if (value.cached_files.count >= _n2053 and base.same_list("cached_files", _scratch2052)) {
        out.unsigned(1);
        out.unsigned(_n2053);
        out.unsigned(value.cached_files.count - _n2053);
        for (var _i2054 in _n2053..value.cached_files.count) {
            out.flag(value.cached_files[_i2054]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2055 in value.cached_files) {
            out.flag(_item2055);
        }
        base.count("cached_files whole", 0);
    }
    var _xscratch2062 = next.scratch();
    for (var _xitem2063 in value.cached_files) {
        _xscratch2062.flag(_xitem2063);
    }
    next.keep_list("cached_files", value.cached_files.count, _xscratch2062);
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2067 = 0;
    var _news2068 = HashMap<Loc, String>();
    for (var (_key2064, _) in value.recorded_summaries) {
        var _kscratch2065 = base.scratch();
        _kscratch2065.loc(_key2064);
        var _vscratch2066 = base.scratch();
        _vscratch2066.text(value.recorded_summaries[_key2064]);
        var _had = base.entry("recorded_summaries", _kscratch2065, _vscratch2066);
        if (_had >= 0) {
            _kept2067 += 1;
        }
        if (_had != 1) {
            _news2068[_key2064] = value.recorded_summaries[_key2064];
        }
    }
    if (_kept2067 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2070 = Array<(u8[], u8[], Loc)>();
        for (var (_key2069, _) in _news2068) {
            var _scratch2071 = out.scratch();
            _scratch2071.loc(_key2069);
            var _vscratch2073 = out.scratch();
            _vscratch2073.text(_news2068[_key2069]);
            _keys2070.append((_scratch2071.finish(), _vscratch2073.finish(), _key2069));
        }
        _keys2070.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2070.count);
        for (var (_bytes2072, _, _key2069) in _keys2070) {
            out.loc(_key2069);
            out.text(_news2068[_key2069]);
        }
    } else {
        out.unsigned(0);
        var _keys2075 = Array<(u8[], u8[], Loc)>();
        for (var (_key2074, _) in value.recorded_summaries) {
            var _scratch2076 = out.scratch();
            _scratch2076.loc(_key2074);
            var _vscratch2078 = out.scratch();
            _vscratch2078.text(value.recorded_summaries[_key2074]);
            _keys2075.append((_scratch2076.finish(), _vscratch2078.finish(), _key2074));
        }
        _keys2075.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2075.count);
        for (var (_bytes2077, _, _key2074) in _keys2075) {
            out.loc(_key2074);
            out.text(value.recorded_summaries[_key2074]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2091 = 0;
    var _news2092 = HashSet<Loc>();
    for (var _key2088 in value.stripped) {
        var _kscratch2089 = base.scratch();
        _kscratch2089.loc(_key2088);
        var _vscratch2090 = base.scratch();
        var _had = base.entry("stripped", _kscratch2089, _vscratch2090);
        if (_had >= 0) {
            _kept2091 += 1;
        }
        if (_had != 1) {
            _news2092.insert(_key2088);
        }
    }
    if (_kept2091 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2094 = Array<(u8[], u8[], Loc)>();
        for (var _key2093 in _news2092) {
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
    } else {
        out.unsigned(0);
        var _keys2099 = Array<(u8[], u8[], Loc)>();
        for (var _key2098 in value.stripped) {
            var _scratch2100 = out.scratch();
            _scratch2100.loc(_key2098);
            var _vscratch2102 = out.scratch();
            _keys2099.append((_scratch2100.finish(), _vscratch2102.finish(), _key2098));
        }
        _keys2099.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2099.count);
        for (var (_bytes2101, _, _key2098) in _keys2099) {
            out.loc(_key2098);
        }
        base.count("stripped whole", 0);
    }
    for (var _key2088 in value.stripped) {
        var _kscratch2089 = next.scratch();
        _kscratch2089.loc(_key2088);
        var _vscratch2090 = next.scratch();
        next.keep_entry("stripped", _kscratch2089, _vscratch2090);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _hs2112 = Array<String>();
    for (var _item2110 in value.templates.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item2110);
        _hs2112.append(base.hash_of(scratch));
    }
    var _seq2113 = base.sequence("t");
    var _seqn2114 = base.sequence("t#");
    ulong _bj2115 = 0;
    var _news2116 = Array<ulong>();
    var _patches2117 = Array<(ulong, ulong)>();
    for (var _i2118 in 0.._hs2112.count) {
        if (_bj2115 < _seq2113.count and _hs2112[_i2118] == _seq2113[_bj2115]) {
            _bj2115 += 1;
        } else if (_bj2115 < _seq2113.count
            and _bj2115 < _seqn2114.count
            and value.templates.structs[_i2118].name == _seqn2114[_bj2115]) {
            _patches2117.append((_i2118, _bj2115));
            _bj2115 += 1;
        } else {
            _news2116.append(_i2118);
        }
    }
    if (_bj2115 == _seq2113.count) {
        out.unsigned(2);
        out.unsigned(_patches2117.count);
        for (var (_i2118, _b) in _patches2117) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2118].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2118], base, _b);
            base.count("t patched", out.values.count - _before);
        }
        out.unsigned(_news2116.count);
        for (var _i2118 in _news2116) {
            ulong _before = out.values.count;
            out.unsigned(_i2118);
            _m_StructDef_write(out, value.templates.structs[_i2118]);
            base.count("t new", out.values.count - _before);
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2111 = HashSet<long>();
        out.unsigned(value.templates.structs.count);
        for (var _i2118 in 0..value.templates.structs.count) {
            var _item2110 = value.templates.structs[_i2118];
            var at = base.find_hashed("t", _hs2112[_i2118]);
            var named = base.named("t", _item2110.name);
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2111.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2111.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2110, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2110);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2111.count);
    }
    for (var _i2118 in 0.._hs2112.count) {
        next.add_hashed("t", _hs2112[_i2118], _i2118);
        next.name("t", value.templates.structs[_i2118].name, _i2118);
        _patch_t_index(value.templates.structs[_i2118], next, _i2118);
    }
    var _hs2130 = Array<String>();
    for (var _item2127 in value.templates.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2127);
        _hs2130.append(base.hash_of(scratch));
    }
    var _seq2131 = base.sequence("tf");
    ulong _bj2132 = 0;
    var _news2133 = Array<ulong>();
    for (var _i2134 in 0.._hs2130.count) {
        if (_bj2132 < _seq2131.count and _hs2130[_i2134] == _seq2131[_bj2132]) {
            _bj2132 += 1;
        } else {
            _news2133.append(_i2134);
        }
    }
    for (var _i2134 in 0.._hs2130.count) {
        next.add_hashed("tf", _hs2130[_i2134], _i2134);
    }
    if (_bj2132 == _seq2131.count) {
        out.unsigned(2);
        out.unsigned(_news2133.count);
        for (var _i2134 in _news2133) {
            out.unsigned(_i2134);
            _m_FunctionDef_write(out, value.templates.functions[_i2134]);
        }
        base.count("tf" + " merged", 0);
    } else {
        out.unsigned(1);
        base.count("tf" + " by place", 0);
        var _hits2128 = HashSet<long>();
        out.unsigned(value.templates.functions.count);
        for (var _i2134 in 0..value.templates.functions.count) {
            var at = base.find_hashed("tf", _hs2130[_i2134]);
            if (at >= 0) {
                _hits2128.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else {
                out.unsigned(0);
                _m_FunctionDef_write(out, value.templates.functions[_i2134]);
            }
        }
        base.missed("tf", "tf", _hits2128.count);
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    next.keep_checked(value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2147 = 0;
    var _news2148 = HashMap<String, SpecRequest>();
    for (var (_key2144, _) in value.spec_requests) {
        var _kscratch2145 = base.scratch();
        _kscratch2145.text(_key2144);
        var _vscratch2146 = base.scratch();
        _m_SpecRequest_write(_vscratch2146, value.spec_requests[_key2144]);
        var _had = base.entry("spec_requests", _kscratch2145, _vscratch2146);
        if (_had >= 0) {
            _kept2147 += 1;
        }
        if (_had != 1) {
            _news2148[_key2144] = value.spec_requests[_key2144];
        }
    }
    if (_kept2147 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2150 = Array<(u8[], u8[], String)>();
        for (var (_key2149, _) in _news2148) {
            var _scratch2151 = out.scratch();
            _scratch2151.text(_key2149);
            var _vscratch2153 = out.scratch();
            _m_SpecRequest_write(_vscratch2153, _news2148[_key2149]);
            _keys2150.append((_scratch2151.finish(), _vscratch2153.finish(), _key2149));
        }
        _keys2150.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2150.count);
        for (var (_bytes2152, _, _key2149) in _keys2150) {
            out.text(_key2149);
            _m_SpecRequest_write(out, _news2148[_key2149]);
        }
    } else {
        out.unsigned(0);
        var _keys2155 = Array<(u8[], u8[], String)>();
        for (var (_key2154, _) in value.spec_requests) {
            var _scratch2156 = out.scratch();
            _scratch2156.text(_key2154);
            var _vscratch2158 = out.scratch();
            _m_SpecRequest_write(_vscratch2158, value.spec_requests[_key2154]);
            _keys2155.append((_scratch2156.finish(), _vscratch2158.finish(), _key2154));
        }
        _keys2155.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2155.count);
        for (var (_bytes2157, _, _key2154) in _keys2155) {
            out.text(_key2154);
            _m_SpecRequest_write(out, value.spec_requests[_key2154]);
        }
        base.count("spec_requests whole", 0);
    }
    for (var (_key2144, _) in value.spec_requests) {
        var _kscratch2145 = next.scratch();
        _kscratch2145.text(_key2144);
        var _vscratch2146 = next.scratch();
        _m_SpecRequest_write(_vscratch2146, value.spec_requests[_key2144]);
        next.keep_entry("spec_requests", _kscratch2145, _vscratch2146);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2171 = base.size("summaries_to_record");
    var _scratch2170 = base.scratch();
    if (value.summaries_to_record.count >= _n2171) {
        for (var _i2172 in 0.._n2171) {
            var (_t2173, _t2174) = value.summaries_to_record[_i2172];
            _scratch2170.loc(_t2173);
            _scratch2170.text(_t2174);
        }
    }
    if (value.summaries_to_record.count >= _n2171 and base.same_list("summaries_to_record", _scratch2170)) {
        out.unsigned(1);
        out.unsigned(_n2171);
        out.unsigned(value.summaries_to_record.count - _n2171);
        for (var _i2172 in _n2171..value.summaries_to_record.count) {
            var (_t2175, _t2176) = value.summaries_to_record[_i2172];
            out.loc(_t2175);
            out.text(_t2176);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2177 in value.summaries_to_record) {
            var (_t2178, _t2179) = _item2177;
            out.loc(_t2178);
            out.text(_t2179);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2197 = 0;
    var _news2198 = HashMap<String, Array<bool>>();
    for (var (_key2194, _) in value.caller_copies) {
        var _kscratch2195 = base.scratch();
        _kscratch2195.text(_key2194);
        var _vscratch2196 = base.scratch();
        _vscratch2196.unsigned(value.caller_copies[_key2194].count);
        for (var _item2199 in value.caller_copies[_key2194]) {
            _vscratch2196.flag(_item2199);
        }
        var _had = base.entry("caller_copies", _kscratch2195, _vscratch2196);
        if (_had >= 0) {
            _kept2197 += 1;
        }
        if (_had != 1) {
            _news2198[_key2194] = value.caller_copies[_key2194];
        }
    }
    if (_kept2197 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2201 = Array<(u8[], u8[], String)>();
        for (var (_key2200, _) in _news2198) {
            var _scratch2202 = out.scratch();
            _scratch2202.text(_key2200);
            var _vscratch2204 = out.scratch();
            _vscratch2204.unsigned(_news2198[_key2200].count);
            for (var _item2205 in _news2198[_key2200]) {
                _vscratch2204.flag(_item2205);
            }
            _keys2201.append((_scratch2202.finish(), _vscratch2204.finish(), _key2200));
        }
        _keys2201.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2201.count);
        for (var (_bytes2203, _, _key2200) in _keys2201) {
            out.text(_key2200);
            out.unsigned(_news2198[_key2200].count);
            for (var _item2206 in _news2198[_key2200]) {
                out.flag(_item2206);
            }
        }
    } else {
        out.unsigned(0);
        var _keys2208 = Array<(u8[], u8[], String)>();
        for (var (_key2207, _) in value.caller_copies) {
            var _scratch2209 = out.scratch();
            _scratch2209.text(_key2207);
            var _vscratch2211 = out.scratch();
            _vscratch2211.unsigned(value.caller_copies[_key2207].count);
            for (var _item2212 in value.caller_copies[_key2207]) {
                _vscratch2211.flag(_item2212);
            }
            _keys2208.append((_scratch2209.finish(), _vscratch2211.finish(), _key2207));
        }
        _keys2208.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2208.count);
        for (var (_bytes2210, _, _key2207) in _keys2208) {
            out.text(_key2207);
            out.unsigned(value.caller_copies[_key2207].count);
            for (var _item2213 in value.caller_copies[_key2207]) {
                out.flag(_item2213);
            }
        }
        base.count("caller_copies whole", 0);
    }
    for (var (_key2194, _) in value.caller_copies) {
        var _kscratch2195 = next.scratch();
        _kscratch2195.text(_key2194);
        var _vscratch2196 = next.scratch();
        _vscratch2196.unsigned(value.caller_copies[_key2194].count);
        for (var _item2227 in value.caller_copies[_key2194]) {
            _vscratch2196.flag(_item2227);
        }
        next.keep_entry("caller_copies", _kscratch2195, _vscratch2196);
    }
    base.stat("caller_copies", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.linked);
    base.stat("linked", out.values.count - _mark);
    _mark = out.values.count;
}

_m_Module_read_delta(input: RecordIn, base: Module): Module {
    var _f1488 = Array<ast.Import>();
    var _mode1491 = input.unsigned();
    if (_mode1491 == 2) {
        ulong _bi1492 = 0;
        var _n1489 = input.count();
        for (var _ in 0.._n1489) {
            var _at1493 = input.unsigned();
            while (_f1488.count < _at1493) {
                _f1488.append(base.imports[_bi1492]);
                _bi1492 += 1;
            }
            _f1488.append(_a_Import_read(input));
        }
        while (_bi1492 < base.imports.count) {
            _f1488.append(base.imports[_bi1492]);
            _bi1492 += 1;
        }
    } else {
        var _n1489 = input.count();
        for (var _ in 0.._n1489) {
            var _tag1490 = input.unsigned();
            if (_tag1490 & 1 == 1) {
                _f1488.append(base.imports[_tag1490 >> 1]);
            } else {
                _f1488.append(_a_Import_read(input));
            }
        }
    }
    var _f1504 = Array<StructDef>();
    var _mode1507 = input.unsigned();
    if (_mode1507 == 2) {
        var _patched1510 = HashMap<ulong, StructDef>();
        var _n1505 = input.count();
        for (var _ in 0.._n1505) {
            input.text();
            var _slot = input.unsigned();
            _patched1510[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1508 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1509 = input.unsigned();
            while (_f1504.count < _at1509) {
                var _p = _patched1510.try_get(_bi1508);
                _f1504.append(_p.is_value() ? _p.value() : base.structs[_bi1508]);
                _bi1508 += 1;
            }
            _f1504.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1508 < base.structs.count) {
            var _p = _patched1510.try_get(_bi1508);
            _f1504.append(_p.is_value() ? _p.value() : base.structs[_bi1508]);
            _bi1508 += 1;
        }
    } else {
        var _n1505 = input.count();
        for (var _ in 0.._n1505) {
            var _tag1506 = input.unsigned();
            if (_tag1506 & 1 == 1) {
                _f1504.append(base.structs[_tag1506 >> 1]);
            } else if (_tag1506 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1504.append(_patch_s_read(input, _was));
            } else {
                _f1504.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1520 = Array<TraitDef>();
    var _mode1523 = input.unsigned();
    if (_mode1523 == 2) {
        ulong _bi1524 = 0;
        var _n1521 = input.count();
        for (var _ in 0.._n1521) {
            var _at1525 = input.unsigned();
            while (_f1520.count < _at1525) {
                _f1520.append(base.traits[_bi1524]);
                _bi1524 += 1;
            }
            _f1520.append(_m_TraitDef_read(input));
        }
        while (_bi1524 < base.traits.count) {
            _f1520.append(base.traits[_bi1524]);
            _bi1524 += 1;
        }
    } else {
        var _n1521 = input.count();
        for (var _ in 0.._n1521) {
            var _tag1522 = input.unsigned();
            if (_tag1522 & 1 == 1) {
                _f1520.append(base.traits[_tag1522 >> 1]);
            } else {
                _f1520.append(_m_TraitDef_read(input));
            }
        }
    }
    var _f1535 = Array<ExtensionDef>();
    var _mode1538 = input.unsigned();
    if (_mode1538 == 2) {
        ulong _bi1539 = 0;
        var _n1536 = input.count();
        for (var _ in 0.._n1536) {
            var _at1540 = input.unsigned();
            while (_f1535.count < _at1540) {
                _f1535.append(base.extensions[_bi1539]);
                _bi1539 += 1;
            }
            _f1535.append(_m_ExtensionDef_read(input));
        }
        while (_bi1539 < base.extensions.count) {
            _f1535.append(base.extensions[_bi1539]);
            _bi1539 += 1;
        }
    } else {
        var _n1536 = input.count();
        for (var _ in 0.._n1536) {
            var _tag1537 = input.unsigned();
            if (_tag1537 & 1 == 1) {
                _f1535.append(base.extensions[_tag1537 >> 1]);
            } else {
                _f1535.append(_m_ExtensionDef_read(input));
            }
        }
    }
    var _f1550 = Array<FunctionDef>();
    var _mode1553 = input.unsigned();
    if (_mode1553 == 2) {
        ulong _bi1554 = 0;
        var _n1551 = input.count();
        for (var _ in 0.._n1551) {
            var _at1555 = input.unsigned();
            while (_f1550.count < _at1555) {
                _f1550.append(base.functions[_bi1554]);
                _bi1554 += 1;
            }
            _f1550.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1554 < base.functions.count) {
            _f1550.append(base.functions[_bi1554]);
            _bi1554 += 1;
        }
    } else {
        var _n1551 = input.count();
        for (var _ in 0.._n1551) {
            var _tag1552 = input.unsigned();
            if (_tag1552 & 1 == 1) {
                _f1550.append(base.functions[_tag1552 >> 1]);
            } else {
                _f1550.append(_m_FunctionDef_read_lazy(input));
            }
        }
    }
    var _f1565 = Array<ExternDef>();
    var _mode1568 = input.unsigned();
    if (_mode1568 == 2) {
        ulong _bi1569 = 0;
        var _n1566 = input.count();
        for (var _ in 0.._n1566) {
            var _at1570 = input.unsigned();
            while (_f1565.count < _at1570) {
                _f1565.append(base.externs[_bi1569]);
                _bi1569 += 1;
            }
            _f1565.append(_m_ExternDef_read(input));
        }
        while (_bi1569 < base.externs.count) {
            _f1565.append(base.externs[_bi1569]);
            _bi1569 += 1;
        }
    } else {
        var _n1566 = input.count();
        for (var _ in 0.._n1566) {
            var _tag1567 = input.unsigned();
            if (_tag1567 & 1 == 1) {
                _f1565.append(base.externs[_tag1567 >> 1]);
            } else {
                _f1565.append(_m_ExternDef_read(input));
            }
        }
    }
    var _f1580 = Array<VariableDef>();
    var _mode1583 = input.unsigned();
    if (_mode1583 == 2) {
        ulong _bi1584 = 0;
        var _n1581 = input.count();
        for (var _ in 0.._n1581) {
            var _at1585 = input.unsigned();
            while (_f1580.count < _at1585) {
                _f1580.append(base.globals[_bi1584]);
                _bi1584 += 1;
            }
            _f1580.append(_m_VariableDef_read(input));
        }
        while (_bi1584 < base.globals.count) {
            _f1580.append(base.globals[_bi1584]);
            _bi1584 += 1;
        }
    } else {
        var _n1581 = input.count();
        for (var _ in 0.._n1581) {
            var _tag1582 = input.unsigned();
            if (_tag1582 & 1 == 1) {
                _f1580.append(base.globals[_tag1582 >> 1]);
            } else {
                _f1580.append(_m_VariableDef_read(input));
            }
        }
    }
    var _f1595 = Array<ModuleStaticBlock>();
    var _mode1598 = input.unsigned();
    if (_mode1598 == 2) {
        ulong _bi1599 = 0;
        var _n1596 = input.count();
        for (var _ in 0.._n1596) {
            var _at1600 = input.unsigned();
            while (_f1595.count < _at1600) {
                _f1595.append(base.static_blocks[_bi1599]);
                _bi1599 += 1;
            }
            _f1595.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1599 < base.static_blocks.count) {
            _f1595.append(base.static_blocks[_bi1599]);
            _bi1599 += 1;
        }
    } else {
        var _n1596 = input.count();
        for (var _ in 0.._n1596) {
            var _tag1597 = input.unsigned();
            if (_tag1597 & 1 == 1) {
                _f1595.append(base.static_blocks[_tag1597 >> 1]);
            } else {
                _f1595.append(_m_ModuleStaticBlock_read(input));
            }
        }
    }
    var _f1610 = Array<EnumDef>();
    var _mode1613 = input.unsigned();
    if (_mode1613 == 2) {
        ulong _bi1614 = 0;
        var _n1611 = input.count();
        for (var _ in 0.._n1611) {
            var _at1615 = input.unsigned();
            while (_f1610.count < _at1615) {
                _f1610.append(base.enums[_bi1614]);
                _bi1614 += 1;
            }
            _f1610.append(_m_EnumDef_read(input));
        }
        while (_bi1614 < base.enums.count) {
            _f1610.append(base.enums[_bi1614]);
            _bi1614 += 1;
        }
    } else {
        var _n1611 = input.count();
        for (var _ in 0.._n1611) {
            var _tag1612 = input.unsigned();
            if (_tag1612 & 1 == 1) {
                _f1610.append(base.enums[_tag1612 >> 1]);
            } else {
                _f1610.append(_m_EnumDef_read(input));
            }
        }
    }
    var _f1625 = Array<TypeName>();
    var _mode1628 = input.unsigned();
    if (_mode1628 == 2) {
        ulong _bi1629 = 0;
        var _n1626 = input.count();
        for (var _ in 0.._n1626) {
            var _at1630 = input.unsigned();
            while (_f1625.count < _at1630) {
                _f1625.append(base.struct_specs[_bi1629]);
                _bi1629 += 1;
            }
            _f1625.append(_m_TypeName_read(input));
        }
        while (_bi1629 < base.struct_specs.count) {
            _f1625.append(base.struct_specs[_bi1629]);
            _bi1629 += 1;
        }
    } else {
        var _n1626 = input.count();
        for (var _ in 0.._n1626) {
            var _tag1627 = input.unsigned();
            if (_tag1627 & 1 == 1) {
                _f1625.append(base.struct_specs[_tag1627 >> 1]);
            } else {
                _f1625.append(_m_TypeName_read(input));
            }
        }
    }
    var _f1640 = Array<TypeName>();
    var _mode1643 = input.unsigned();
    if (_mode1643 == 2) {
        ulong _bi1644 = 0;
        var _n1641 = input.count();
        for (var _ in 0.._n1641) {
            var _at1645 = input.unsigned();
            while (_f1640.count < _at1645) {
                _f1640.append(base.func_specs[_bi1644]);
                _bi1644 += 1;
            }
            _f1640.append(_m_TypeName_read(input));
        }
        while (_bi1644 < base.func_specs.count) {
            _f1640.append(base.func_specs[_bi1644]);
            _bi1644 += 1;
        }
    } else {
        var _n1641 = input.count();
        for (var _ in 0.._n1641) {
            var _tag1642 = input.unsigned();
            if (_tag1642 & 1 == 1) {
                _f1640.append(base.func_specs[_tag1642 >> 1]);
            } else {
                _f1640.append(_m_TypeName_read(input));
            }
        }
    }
    var _f1650 = Array<TypeAliasDef>();
    var _n1651 = input.count();
    for (var _ in 0.._n1651) {
        var _tag1652 = input.unsigned();
        if (_tag1652 & 1 == 1) {
            _f1650.append(base.type_aliases[_tag1652 >> 1]);
        } else {
            _f1650.append(_m_TypeAliasDef_read(input));
        }
    }
    var _f1662 = Array<Withheld>();
    var _mode1665 = input.unsigned();
    if (_mode1665 == 2) {
        ulong _bi1666 = 0;
        var _n1663 = input.count();
        for (var _ in 0.._n1663) {
            var _at1667 = input.unsigned();
            while (_f1662.count < _at1667) {
                _f1662.append(base.withheld[_bi1666]);
                _bi1666 += 1;
            }
            _f1662.append(_m_Withheld_read(input));
        }
        while (_bi1666 < base.withheld.count) {
            _f1662.append(base.withheld[_bi1666]);
            _bi1666 += 1;
        }
    } else {
        var _n1663 = input.count();
        for (var _ in 0.._n1663) {
            var _tag1664 = input.unsigned();
            if (_tag1664 & 1 == 1) {
                _f1662.append(base.withheld[_tag1664 >> 1]);
            } else {
                _f1662.append(_m_Withheld_read(input));
            }
        }
    }
    var _f1677 = Array<PropertyDef>();
    var _mode1680 = input.unsigned();
    if (_mode1680 == 2) {
        ulong _bi1681 = 0;
        var _n1678 = input.count();
        for (var _ in 0.._n1678) {
            var _at1682 = input.unsigned();
            while (_f1677.count < _at1682) {
                _f1677.append(base.properties[_bi1681]);
                _bi1681 += 1;
            }
            _f1677.append(_m_PropertyDef_read(input));
        }
        while (_bi1681 < base.properties.count) {
            _f1677.append(base.properties[_bi1681]);
            _bi1681 += 1;
        }
    } else {
        var _n1678 = input.count();
        for (var _ in 0.._n1678) {
            var _tag1679 = input.unsigned();
            if (_tag1679 & 1 == 1) {
                _f1677.append(base.properties[_tag1679 >> 1]);
            } else {
                _f1677.append(_m_PropertyDef_read(input));
            }
        }
    }
    var _f1692 = Array<TypeUse>();
    var _mode1695 = input.unsigned();
    if (_mode1695 == 2) {
        ulong _bi1696 = 0;
        var _n1693 = input.count();
        for (var _ in 0.._n1693) {
            var _at1697 = input.unsigned();
            while (_f1692.count < _at1697) {
                _f1692.append(base.type_uses[_bi1696]);
                _bi1696 += 1;
            }
            _f1692.append(_m_TypeUse_read(input));
        }
        while (_bi1696 < base.type_uses.count) {
            _f1692.append(base.type_uses[_bi1696]);
            _bi1696 += 1;
        }
    } else {
        var _n1693 = input.count();
        for (var _ in 0.._n1693) {
            var _tag1694 = input.unsigned();
            if (_tag1694 & 1 == 1) {
                _f1692.append(base.type_uses[_tag1694 >> 1]);
            } else {
                _f1692.append(_m_TypeUse_read(input));
            }
        }
    }
    var _f1707 = Array<UseContext>();
    var _mode1710 = input.unsigned();
    if (_mode1710 == 2) {
        ulong _bi1711 = 0;
        var _n1708 = input.count();
        for (var _ in 0.._n1708) {
            var _at1712 = input.unsigned();
            while (_f1707.count < _at1712) {
                _f1707.append(base.use_contexts[_bi1711]);
                _bi1711 += 1;
            }
            _f1707.append(_m_UseContext_read(input));
        }
        while (_bi1711 < base.use_contexts.count) {
            _f1707.append(base.use_contexts[_bi1711]);
            _bi1711 += 1;
        }
    } else {
        var _n1708 = input.count();
        for (var _ in 0.._n1708) {
            var _tag1709 = input.unsigned();
            if (_tag1709 & 1 == 1) {
                _f1707.append(base.use_contexts[_tag1709 >> 1]);
            } else {
                _f1707.append(_m_UseContext_read(input));
            }
        }
    }
    var _f1728 = Array<(Loc, ulong, Loc)>();
    var _tag1729 = input.unsigned();
    if (_tag1729 == 1) {
        input.unsigned();
        for (var _i1717 in 0..base.literal_args.count) {
            _f1728.append(base.literal_args[_i1717]);
        }
        var _more1731 = input.count();
        for (var _ in 0.._more1731) {
            var _t1732 = input.loc();
            var _t1733 = input.unsigned();
            var _t1734 = input.loc();
            _f1728.append((_t1732, _t1733, _t1734));
        }
    } else {
        var _v1735 = Array<(Loc, ulong, Loc)>();
        var _n1736 = input.count();
        for (var _ in 0.._n1736) {
            var _t1737 = input.loc();
            var _t1738 = input.unsigned();
            var _t1739 = input.loc();
            _v1735.append((_t1737, _t1738, _t1739));
        }
        _f1728 = _v1735;
    }
    var _f1753 = Array<TypeAliasDef>();
    var _mode1756 = input.unsigned();
    if (_mode1756 == 2) {
        ulong _bi1757 = 0;
        var _n1754 = input.count();
        for (var _ in 0.._n1754) {
            var _at1758 = input.unsigned();
            while (_f1753.count < _at1758) {
                _f1753.append(base.constrained_aliases[_bi1757]);
                _bi1757 += 1;
            }
            _f1753.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1757 < base.constrained_aliases.count) {
            _f1753.append(base.constrained_aliases[_bi1757]);
            _bi1757 += 1;
        }
    } else {
        var _n1754 = input.count();
        for (var _ in 0.._n1754) {
            var _tag1755 = input.unsigned();
            if (_tag1755 & 1 == 1) {
                _f1753.append(base.constrained_aliases[_tag1755 >> 1]);
            } else {
                _f1753.append(_m_TypeAliasDef_read(input));
            }
        }
    }
    var _f1768 = Array<TraitType>();
    var _mode1771 = input.unsigned();
    if (_mode1771 == 2) {
        ulong _bi1772 = 0;
        var _n1769 = input.count();
        for (var _ in 0.._n1769) {
            var _at1773 = input.unsigned();
            while (_f1768.count < _at1773) {
                _f1768.append(base.trait_types[_bi1772]);
                _bi1772 += 1;
            }
            _f1768.append(_m_TraitType_read(input));
        }
        while (_bi1772 < base.trait_types.count) {
            _f1768.append(base.trait_types[_bi1772]);
            _bi1772 += 1;
        }
    } else {
        var _n1769 = input.count();
        for (var _ in 0.._n1769) {
            var _tag1770 = input.unsigned();
            if (_tag1770 & 1 == 1) {
                _f1768.append(base.trait_types[_tag1770 >> 1]);
            } else {
                _f1768.append(_m_TraitType_read(input));
            }
        }
    }
    var _f1783 = Array<Conversion>();
    var _mode1786 = input.unsigned();
    if (_mode1786 == 2) {
        ulong _bi1787 = 0;
        var _n1784 = input.count();
        for (var _ in 0.._n1784) {
            var _at1788 = input.unsigned();
            while (_f1783.count < _at1788) {
                _f1783.append(base.conversions[_bi1787]);
                _bi1787 += 1;
            }
            _f1783.append(_m_Conversion_read(input));
        }
        while (_bi1787 < base.conversions.count) {
            _f1783.append(base.conversions[_bi1787]);
            _bi1787 += 1;
        }
    } else {
        var _n1784 = input.count();
        for (var _ in 0.._n1784) {
            var _tag1785 = input.unsigned();
            if (_tag1785 & 1 == 1) {
                _f1783.append(base.conversions[_tag1785 >> 1]);
            } else {
                _f1783.append(_m_Conversion_read(input));
            }
        }
    }
    var _f1810 = Map<String, Array<String>>();
    var _tag1811 = input.unsigned();
    if (_tag1811 == 1) {
        for (var (_bk1812, _bv) in base.overload_sets) {
            _f1810[_bk1812] = _bv;
        }
        var _v1813 = Map<String, Array<String>>();
        var _n1814 = input.count();
        for (var _ in 0.._n1814) {
            var _k1815 = input.text();
            var _v1816 = Array<String>();
            var _n1817 = input.count();
            for (var _ in 0.._n1817) {
                _v1816.append(input.text());
            }
            _v1813[_k1815] = _v1816;
        }
        for (var (_bk1812, _av) in _v1813) {
            _f1810[_bk1812] = _av;
        }
    } else {
        var _v1818 = Map<String, Array<String>>();
        var _n1819 = input.count();
        for (var _ in 0.._n1819) {
            var _k1820 = input.text();
            var _v1821 = Array<String>();
            var _n1822 = input.count();
            for (var _ in 0.._n1822) {
                _v1821.append(input.text());
            }
            _v1818[_k1820] = _v1821;
        }
        _f1810 = _v1818;
    }
    var _f1849 = Map<String, Array<Array<String>>>();
    var _tag1850 = input.unsigned();
    if (_tag1850 == 1) {
        for (var (_bk1851, _bv) in base.overload_unions) {
            _f1849[_bk1851] = _bv;
        }
        var _v1852 = Map<String, Array<Array<String>>>();
        var _n1853 = input.count();
        for (var _ in 0.._n1853) {
            var _k1854 = input.text();
            var _v1855 = Array<Array<String>>();
            var _n1856 = input.count();
            for (var _ in 0.._n1856) {
                var _v1857 = Array<String>();
                var _n1858 = input.count();
                for (var _ in 0.._n1858) {
                    _v1857.append(input.text());
                }
                _v1855.append(_v1857);
            }
            _v1852[_k1854] = _v1855;
        }
        for (var (_bk1851, _av) in _v1852) {
            _f1849[_bk1851] = _av;
        }
    } else {
        var _v1859 = Map<String, Array<Array<String>>>();
        var _n1860 = input.count();
        for (var _ in 0.._n1860) {
            var _k1861 = input.text();
            var _v1862 = Array<Array<String>>();
            var _n1863 = input.count();
            for (var _ in 0.._n1863) {
                var _v1864 = Array<String>();
                var _n1865 = input.count();
                for (var _ in 0.._n1865) {
                    _v1864.append(input.text());
                }
                _v1862.append(_v1864);
            }
            _v1859[_k1861] = _v1862;
        }
        _f1849 = _v1859;
    }
    var _f1918 = Map<String, Map<String, Array<String>>>();
    var _tag1919 = input.unsigned();
    if (_tag1919 == 1) {
        for (var (_bk1920, _bv) in base.method_overload_sets) {
            _f1918[_bk1920] = _bv;
        }
        var _v1921 = Map<String, Map<String, Array<String>>>();
        var _n1922 = input.count();
        for (var _ in 0.._n1922) {
            var _k1923 = input.text();
            var _v1924 = Map<String, Array<String>>();
            var _n1925 = input.count();
            for (var _ in 0.._n1925) {
                var _k1926 = input.text();
                var _v1927 = Array<String>();
                var _n1928 = input.count();
                for (var _ in 0.._n1928) {
                    _v1927.append(input.text());
                }
                _v1924[_k1926] = _v1927;
            }
            _v1921[_k1923] = _v1924;
        }
        for (var (_bk1920, _av) in _v1921) {
            _f1918[_bk1920] = _av;
        }
    } else {
        var _v1929 = Map<String, Map<String, Array<String>>>();
        var _n1930 = input.count();
        for (var _ in 0.._n1930) {
            var _k1931 = input.text();
            var _v1932 = Map<String, Array<String>>();
            var _n1933 = input.count();
            for (var _ in 0.._n1933) {
                var _k1934 = input.text();
                var _v1935 = Array<String>();
                var _n1936 = input.count();
                for (var _ in 0.._n1936) {
                    _v1935.append(input.text());
                }
                _v1932[_k1934] = _v1935;
            }
            _v1929[_k1931] = _v1932;
        }
        _f1918 = _v1929;
    }
    var _f1944 = _m_ExtensionScopes_read(input);
    var _f1960 = HashSet<Loc>();
    var _tag1961 = input.unsigned();
    if (_tag1961 == 1) {
        for (var _bk1962 in base.private_functions) {
            _f1960.insert(_bk1962);
        }
        var _v1963 = HashSet<Loc>();
        var _n1964 = input.count();
        for (var _ in 0.._n1964) {
            _v1963.insert(input.loc());
        }
        for (var _bk1962 in _v1963) {
            _f1960.insert(_bk1962);
        }
    } else {
        var _v1965 = HashSet<Loc>();
        var _n1966 = input.count();
        for (var _ in 0.._n1966) {
            _v1965.insert(input.loc());
        }
        _f1960 = _v1965;
    }
    var _f1982 = HashSet<Loc>();
    var _tag1983 = input.unsigned();
    if (_tag1983 == 1) {
        for (var _bk1984 in base.file_private_functions) {
            _f1982.insert(_bk1984);
        }
        var _v1985 = HashSet<Loc>();
        var _n1986 = input.count();
        for (var _ in 0.._n1986) {
            _v1985.insert(input.loc());
        }
        for (var _bk1984 in _v1985) {
            _f1982.insert(_bk1984);
        }
    } else {
        var _v1987 = HashSet<Loc>();
        var _n1988 = input.count();
        for (var _ in 0.._n1988) {
            _v1987.insert(input.loc());
        }
        _f1982 = _v1987;
    }
    var _f2000 = Array<(Loc, String)>();
    var _tag2001 = input.unsigned();
    if (_tag2001 == 1) {
        input.unsigned();
        for (var _i1992 in 0..base.call_targets.count) {
            _f2000.append(base.call_targets[_i1992]);
        }
        var _more2003 = input.count();
        for (var _ in 0.._more2003) {
            var _t2004 = input.loc();
            var _t2005 = input.text();
            _f2000.append((_t2004, _t2005));
        }
    } else {
        var _v2006 = Array<(Loc, String)>();
        var _n2007 = input.count();
        for (var _ in 0.._n2007) {
            var _t2008 = input.loc();
            var _t2009 = input.text();
            _v2006.append((_t2008, _t2009));
        }
        _f2000 = _v2006;
    }
    var _f2026 = Array<(Loc, String)>();
    var _tag2027 = input.unsigned();
    if (_tag2027 == 1) {
        var _v2028 = Array<(Loc, String)>();
        var _n2029 = input.count();
        for (var _ in 0.._n2029) {
            var _t2030 = input.loc();
            var _t2031 = input.text();
            _v2028.append((_t2030, _t2031));
        }
        _f2026 = merge_by_place(base.argument_names, _v2028);
    } else {
        var _v2032 = Array<(Loc, String)>();
        var _n2033 = input.count();
        for (var _ in 0.._n2033) {
            var _t2034 = input.loc();
            var _t2035 = input.text();
            _v2032.append((_t2034, _t2035));
        }
        _f2026 = _v2032;
    }
    var _f2043 = Array<String>();
    var _tag2044 = input.unsigned();
    if (_tag2044 == 1) {
        input.unsigned();
        for (var _i2041 in 0..base.namespaces.count) {
            _f2043.append(base.namespaces[_i2041]);
        }
        var _more2046 = input.count();
        for (var _ in 0.._more2046) {
            _f2043.append(input.text());
        }
    } else {
        var _v2047 = Array<String>();
        var _n2048 = input.count();
        for (var _ in 0.._n2048) {
            _v2047.append(input.text());
        }
        _f2043 = _v2047;
    }
    var _f2056 = Array<bool>();
    var _tag2057 = input.unsigned();
    if (_tag2057 == 1) {
        input.unsigned();
        for (var _i2054 in 0..base.cached_files.count) {
            _f2056.append(base.cached_files[_i2054]);
        }
        var _more2059 = input.count();
        for (var _ in 0.._more2059) {
            _f2056.append(input.flag());
        }
    } else {
        var _v2060 = Array<bool>();
        var _n2061 = input.count();
        for (var _ in 0.._n2061) {
            _v2060.append(input.flag());
        }
        _f2056 = _v2060;
    }
    var _f2079 = HashMap<Loc, String>();
    var _tag2080 = input.unsigned();
    if (_tag2080 == 1) {
        for (var (_bk2081, _bv) in base.recorded_summaries) {
            _f2079[_bk2081] = _bv;
        }
        var _v2082 = HashMap<Loc, String>();
        var _n2083 = input.count();
        for (var _ in 0.._n2083) {
            var _k2084 = input.loc();
            _v2082[_k2084] = input.text();
        }
        for (var (_bk2081, _av) in _v2082) {
            _f2079[_bk2081] = _av;
        }
    } else {
        var _v2085 = HashMap<Loc, String>();
        var _n2086 = input.count();
        for (var _ in 0.._n2086) {
            var _k2087 = input.loc();
            _v2085[_k2087] = input.text();
        }
        _f2079 = _v2085;
    }
    var _f2103 = HashSet<Loc>();
    var _tag2104 = input.unsigned();
    if (_tag2104 == 1) {
        for (var _bk2105 in base.stripped) {
            _f2103.insert(_bk2105);
        }
        var _v2106 = HashSet<Loc>();
        var _n2107 = input.count();
        for (var _ in 0.._n2107) {
            _v2106.insert(input.loc());
        }
        for (var _bk2105 in _v2106) {
            _f2103.insert(_bk2105);
        }
    } else {
        var _v2108 = HashSet<Loc>();
        var _n2109 = input.count();
        for (var _ in 0.._n2109) {
            _v2108.insert(input.loc());
        }
        _f2103 = _v2108;
    }
    var _frozen = input.flag();
    var _f2119 = Array<StructDef>();
    var _mode2122 = input.unsigned();
    if (_mode2122 == 2) {
        var _patched2125 = HashMap<ulong, StructDef>();
        var _n2120 = input.count();
        for (var _ in 0.._n2120) {
            input.text();
            var _slot = input.unsigned();
            _patched2125[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2123 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2124 = input.unsigned();
            while (_f2119.count < _at2124) {
                var _p = _patched2125.try_get(_bi2123);
                _f2119.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2123]);
                _bi2123 += 1;
            }
            _f2119.append(_m_StructDef_read(input));
        }
        while (_bi2123 < base.templates.structs.count) {
            var _p = _patched2125.try_get(_bi2123);
            _f2119.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2123]);
            _bi2123 += 1;
        }
    } else {
        var _n2120 = input.count();
        for (var _ in 0.._n2120) {
            var _tag2121 = input.unsigned();
            if (_tag2121 & 1 == 1) {
                _f2119.append(base.templates.structs[_tag2121 >> 1]);
            } else if (_tag2121 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2119.append(_patch_t_read(input, _was));
            } else {
                _f2119.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2135 = Array<FunctionDef>();
    var _mode2138 = input.unsigned();
    if (_mode2138 == 2) {
        ulong _bi2139 = 0;
        var _n2136 = input.count();
        for (var _ in 0.._n2136) {
            var _at2140 = input.unsigned();
            while (_f2135.count < _at2140) {
                _f2135.append(base.templates.functions[_bi2139]);
                _bi2139 += 1;
            }
            _f2135.append(_m_FunctionDef_read(input));
        }
        while (_bi2139 < base.templates.functions.count) {
            _f2135.append(base.templates.functions[_bi2139]);
            _bi2139 += 1;
        }
    } else {
        var _n2136 = input.count();
        for (var _ in 0.._n2136) {
            var _tag2137 = input.unsigned();
            if (_tag2137 & 1 == 1) {
                _f2135.append(base.templates.functions[_tag2137 >> 1]);
            } else {
                _f2135.append(_m_FunctionDef_read(input));
            }
        }
    }
    var _f2142 = Templates(_frozen, _f2119, _f2135);
    var _f2143 = DeltaBase.read_checked(input, base.checked);
    var _f2159 = HashMap<String, SpecRequest>();
    var _tag2160 = input.unsigned();
    if (_tag2160 == 1) {
        for (var (_bk2161, _bv) in base.spec_requests) {
            _f2159[_bk2161] = _bv;
        }
        var _v2162 = HashMap<String, SpecRequest>();
        var _n2163 = input.count();
        for (var _ in 0.._n2163) {
            var _k2164 = input.text();
            _v2162[_k2164] = _m_SpecRequest_read(input);
        }
        for (var (_bk2161, _av) in _v2162) {
            _f2159[_bk2161] = _av;
        }
    } else {
        var _v2165 = HashMap<String, SpecRequest>();
        var _n2166 = input.count();
        for (var _ in 0.._n2166) {
            var _k2167 = input.text();
            _v2165[_k2167] = _m_SpecRequest_read(input);
        }
        _f2159 = _v2165;
    }
    var _f2168 = input.flag();
    var _f2180 = Array<(Loc, String)>();
    var _tag2181 = input.unsigned();
    if (_tag2181 == 1) {
        input.unsigned();
        for (var _i2172 in 0..base.summaries_to_record.count) {
            _f2180.append(base.summaries_to_record[_i2172]);
        }
        var _more2183 = input.count();
        for (var _ in 0.._more2183) {
            var _t2184 = input.loc();
            var _t2185 = input.text();
            _f2180.append((_t2184, _t2185));
        }
    } else {
        var _v2186 = Array<(Loc, String)>();
        var _n2187 = input.count();
        for (var _ in 0.._n2187) {
            var _t2188 = input.loc();
            var _t2189 = input.text();
            _v2186.append((_t2188, _t2189));
        }
        _f2180 = _v2186;
    }
    var _f2214 = HashMap<String, Array<bool>>();
    var _tag2215 = input.unsigned();
    if (_tag2215 == 1) {
        for (var (_bk2216, _bv) in base.caller_copies) {
            _f2214[_bk2216] = _bv;
        }
        var _v2217 = HashMap<String, Array<bool>>();
        var _n2218 = input.count();
        for (var _ in 0.._n2218) {
            var _k2219 = input.text();
            var _v2220 = Array<bool>();
            var _n2221 = input.count();
            for (var _ in 0.._n2221) {
                _v2220.append(input.flag());
            }
            _v2217[_k2219] = _v2220;
        }
        for (var (_bk2216, _av) in _v2217) {
            _f2214[_bk2216] = _av;
        }
    } else {
        var _v2222 = HashMap<String, Array<bool>>();
        var _n2223 = input.count();
        for (var _ in 0.._n2223) {
            var _k2224 = input.text();
            var _v2225 = Array<bool>();
            var _n2226 = input.count();
            for (var _ in 0.._n2226) {
                _v2225.append(input.flag());
            }
            _v2222[_k2224] = _v2225;
        }
        _f2214 = _v2222;
    }
    var _f2228 = input.flag();
    return Module(
        _f1488,
        _f1504,
        _f1520,
        _f1535,
        _f1550,
        _f1565,
        _f1580,
        _f1595,
        _f1610,
        _f1625,
        _f1640,
        _f1650,
        _f1662,
        _f1677,
        _f1692,
        _f1707,
        _f1728,
        _f1753,
        _f1768,
        _f1783,
        _f1810,
        _f1849,
        _f1918,
        _f1944,
        _f1960,
        _f1982,
        _f2000,
        _f2026,
        _f2043,
        _f2056,
        _f2079,
        _f2103,
        _f2142,
        _f2143,
        _f2159,
        _f2168,
        _f2180,
        _f2214,
        _f2228
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1494 = 0;
    for (var _item1480 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1480);
        base.add("imports", scratch, _j1494);
        _j1494 += 1;
    }
    ulong _j1511 = 0;
    for (var _item1495 in value.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1495);
        base.add("s", scratch, _j1511);
        base.name("s", _item1495.name, _j1511);
        _patch_s_index(_item1495, base, _j1511);
        _j1511 += 1;
    }
    ulong _j1526 = 0;
    for (var _item1512 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1512);
        base.add("traits", scratch, _j1526);
        _j1526 += 1;
    }
    ulong _j1541 = 0;
    for (var _item1527 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1527);
        base.add("extensions", scratch, _j1541);
        _j1541 += 1;
    }
    ulong _j1556 = 0;
    for (var _item1542 in value.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1542);
        base.add("functions", scratch, _j1556);
        _j1556 += 1;
    }
    ulong _j1571 = 0;
    for (var _item1557 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1557);
        base.add("externs", scratch, _j1571);
        _j1571 += 1;
    }
    ulong _j1586 = 0;
    for (var _item1572 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1572);
        base.add("globals", scratch, _j1586);
        _j1586 += 1;
    }
    ulong _j1601 = 0;
    for (var _item1587 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1587);
        base.add("static_blocks", scratch, _j1601);
        _j1601 += 1;
    }
    ulong _j1616 = 0;
    for (var _item1602 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1602);
        base.add("enums", scratch, _j1616);
        _j1616 += 1;
    }
    ulong _j1631 = 0;
    for (var _item1617 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1617);
        base.add("struct_specs", scratch, _j1631);
        _j1631 += 1;
    }
    ulong _j1646 = 0;
    for (var _item1632 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1632);
        base.add("func_specs", scratch, _j1646);
        _j1646 += 1;
    }
    ulong _j1653 = 0;
    for (var _item1647 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1647);
        base.add("type_aliases", scratch, _j1653);
        _j1653 += 1;
    }
    ulong _j1668 = 0;
    for (var _item1654 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1654);
        base.add("withheld", scratch, _j1668);
        _j1668 += 1;
    }
    ulong _j1683 = 0;
    for (var _item1669 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1669);
        base.add("properties", scratch, _j1683);
        _j1683 += 1;
    }
    ulong _j1698 = 0;
    for (var _item1684 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1684);
        base.add("type_uses", scratch, _j1698);
        _j1698 += 1;
    }
    ulong _j1713 = 0;
    for (var _item1699 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1699);
        base.add("use_contexts", scratch, _j1713);
        _j1713 += 1;
    }
    var _xscratch1740 = base.scratch();
    for (var _xitem1741 in value.literal_args) {
        var (_t1742, _t1743, _t1744) = _xitem1741;
        _xscratch1740.loc(_t1742);
        _xscratch1740.unsigned(_t1743);
        _xscratch1740.loc(_t1744);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1740);
    ulong _j1759 = 0;
    for (var _item1745 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1745);
        base.add("constrained_aliases", scratch, _j1759);
        _j1759 += 1;
    }
    ulong _j1774 = 0;
    for (var _item1760 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1760);
        base.add("trait_types", scratch, _j1774);
        _j1774 += 1;
    }
    ulong _j1789 = 0;
    for (var _item1775 in value.conversions) {
        var scratch = base.scratch();
        _m_Conversion_write(scratch, _item1775);
        base.add("conversions", scratch, _j1789);
        _j1789 += 1;
    }
    for (var (_key1790, _) in value.overload_sets) {
        var _kscratch1791 = base.scratch();
        _kscratch1791.text(_key1790);
        var _vscratch1792 = base.scratch();
        _vscratch1792.unsigned(value.overload_sets[_key1790].count);
        for (var _item1823 in value.overload_sets[_key1790]) {
            _vscratch1792.text(_item1823);
        }
        base.keep_entry("overload_sets", _kscratch1791, _vscratch1792);
    }
    for (var (_key1824, _) in value.overload_unions) {
        var _kscratch1825 = base.scratch();
        _kscratch1825.text(_key1824);
        var _vscratch1826 = base.scratch();
        _vscratch1826.unsigned(value.overload_unions[_key1824].count);
        for (var _item1866 in value.overload_unions[_key1824]) {
            _vscratch1826.unsigned(_item1866.count);
            for (var _item1867 in _item1866) {
                _vscratch1826.text(_item1867);
            }
        }
        base.keep_entry("overload_unions", _kscratch1825, _vscratch1826);
    }
    for (var (_key1868, _) in value.method_overload_sets) {
        var _kscratch1869 = base.scratch();
        _kscratch1869.text(_key1868);
        var _vscratch1870 = base.scratch();
        var _keys1938 = Array<(u8[], u8[], String)>();
        for (var (_key1937, _) in value.method_overload_sets[_key1868]) {
            var _scratch1939 = _vscratch1870.scratch();
            _scratch1939.text(_key1937);
            var _vscratch1941 = _vscratch1870.scratch();
            _vscratch1941.unsigned(value.method_overload_sets[_key1868][_key1937].count);
            for (var _item1942 in value.method_overload_sets[_key1868][_key1937]) {
                _vscratch1941.text(_item1942);
            }
            _keys1938.append((_scratch1939.finish(), _vscratch1941.finish(), _key1937));
        }
        _keys1938.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1870.unsigned(_keys1938.count);
        for (var (_bytes1940, _, _key1937) in _keys1938) {
            _vscratch1870.text(_key1937);
            _vscratch1870.unsigned(value.method_overload_sets[_key1868][_key1937].count);
            for (var _item1943 in value.method_overload_sets[_key1868][_key1937]) {
                _vscratch1870.text(_item1943);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1869, _vscratch1870);
    }
    for (var _key1945 in value.private_functions) {
        var _kscratch1946 = base.scratch();
        _kscratch1946.loc(_key1945);
        var _vscratch1947 = base.scratch();
        base.keep_entry("private_functions", _kscratch1946, _vscratch1947);
    }
    for (var _key1967 in value.file_private_functions) {
        var _kscratch1968 = base.scratch();
        _kscratch1968.loc(_key1967);
        var _vscratch1969 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch1968, _vscratch1969);
    }
    var _xscratch2010 = base.scratch();
    for (var _xitem2011 in value.call_targets) {
        var (_t2012, _t2013) = _xitem2011;
        _xscratch2010.loc(_t2012);
        _xscratch2010.text(_t2013);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2010);
    for (var _item2014 in value.argument_names) {
        var _escratch2015 = base.scratch();
        var (_t2036, _t2037) = _item2014;
        _escratch2015.loc(_t2036);
        _escratch2015.text(_t2037);
        base.keep_entry("argument_names", _escratch2015, base.scratch());
    }
    var _xscratch2049 = base.scratch();
    for (var _xitem2050 in value.namespaces) {
        _xscratch2049.text(_xitem2050);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2049);
    var _xscratch2062 = base.scratch();
    for (var _xitem2063 in value.cached_files) {
        _xscratch2062.flag(_xitem2063);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2062);
    for (var (_key2064, _) in value.recorded_summaries) {
        var _kscratch2065 = base.scratch();
        _kscratch2065.loc(_key2064);
        var _vscratch2066 = base.scratch();
        _vscratch2066.text(value.recorded_summaries[_key2064]);
        base.keep_entry("recorded_summaries", _kscratch2065, _vscratch2066);
    }
    for (var _key2088 in value.stripped) {
        var _kscratch2089 = base.scratch();
        _kscratch2089.loc(_key2088);
        var _vscratch2090 = base.scratch();
        base.keep_entry("stripped", _kscratch2089, _vscratch2090);
    }
    ulong _j2126 = 0;
    for (var _item2110 in value.templates.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item2110);
        base.add("t", scratch, _j2126);
        base.name("t", _item2110.name, _j2126);
        _patch_t_index(_item2110, base, _j2126);
        _j2126 += 1;
    }
    ulong _j2141 = 0;
    for (var _item2127 in value.templates.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2127);
        base.add("tf", scratch, _j2141);
        _j2141 += 1;
    }
    base.keep_checked(value.checked);
    for (var (_key2144, _) in value.spec_requests) {
        var _kscratch2145 = base.scratch();
        _kscratch2145.text(_key2144);
        var _vscratch2146 = base.scratch();
        _m_SpecRequest_write(_vscratch2146, value.spec_requests[_key2144]);
        base.keep_entry("spec_requests", _kscratch2145, _vscratch2146);
    }
    var _xscratch2190 = base.scratch();
    for (var _xitem2191 in value.summaries_to_record) {
        var (_t2192, _t2193) = _xitem2191;
        _xscratch2190.loc(_t2192);
        _xscratch2190.text(_t2193);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2190);
    for (var (_key2194, _) in value.caller_copies) {
        var _kscratch2195 = base.scratch();
        _kscratch2195.text(_key2194);
        var _vscratch2196 = base.scratch();
        _vscratch2196.unsigned(value.caller_copies[_key2194].count);
        for (var _item2227 in value.caller_copies[_key2194]) {
            _vscratch2196.flag(_item2227);
        }
        base.keep_entry("caller_copies", _kscratch2195, _vscratch2196);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1653 = 0;
    for (var _item1647 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1647);
        base.add("type_aliases", scratch, _j1653);
        _j1653 += 1;
    }
    for (var (_key2064, _) in value.recorded_summaries) {
        var _kscratch2065 = base.scratch();
        _kscratch2065.loc(_key2064);
        var _vscratch2066 = base.scratch();
        _vscratch2066.text(value.recorded_summaries[_key2064]);
        base.keep_entry("recorded_summaries", _kscratch2065, _vscratch2066);
    }
    var _xscratch2190 = base.scratch();
    for (var _xitem2191 in value.summaries_to_record) {
        var (_t2192, _t2193) = _xitem2191;
        _xscratch2190.loc(_t2192);
        _xscratch2190.text(_t2193);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2190);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _hits2232 = HashSet<long>();
    ulong _nj2233 = 0;
    out.unsigned(value.generic_params.count);
    for (var _item2231 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2231);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.generic_params", hash);
        if (at >= 0) {
            _hits2232.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_GenericParam_write(out, _item2231);
        }
    }
    base.missed("s.*.generic_params", $"s.{slot}.generic_params", _hits2232.count);
    var _hits2239 = HashSet<long>();
    ulong _nj2240 = 0;
    out.unsigned(value.field_members.count);
    for (var _item2238 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2238);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.field_members", hash);
        if (at >= 0) {
            _hits2239.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_VariableDef_write(out, _item2238);
        }
    }
    base.missed("s.*.field_members", $"s.{slot}.field_members", _hits2239.count);
    var _hits2246 = HashSet<long>();
    ulong _nj2247 = 0;
    out.unsigned(value.method_members.count);
    for (var _item2245 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2245);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.method_members", hash);
        if (at >= 0) {
            _hits2246.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2245);
        }
    }
    base.missed("s.*.method_members", $"s.{slot}.method_members", _hits2246.count);
    var _hits2253 = HashSet<long>();
    ulong _nj2254 = 0;
    out.unsigned(value.generic_methods.count);
    for (var _item2252 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2252);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.generic_methods", hash);
        if (at >= 0) {
            _hits2253.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2252);
        }
    }
    base.missed("s.*.generic_methods", $"s.{slot}.generic_methods", _hits2253.count);
    var _hits2260 = HashSet<long>();
    ulong _nj2261 = 0;
    out.unsigned(value.constructors.count);
    for (var _item2259 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2259);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.constructors", hash);
        if (at >= 0) {
            _hits2260.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2259);
        }
    }
    base.missed("s.*.constructors", $"s.{slot}.constructors", _hits2260.count);
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _hits2270 = HashSet<long>();
    ulong _nj2271 = 0;
    out.unsigned(value.traits.count);
    for (var _item2269 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2269);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.traits", hash);
        if (at >= 0) {
            _hits2270.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeName_write(out, _item2269);
        }
    }
    base.missed("s.*.traits", $"s.{slot}.traits", _hits2270.count);
    var _hits2277 = HashSet<long>();
    ulong _nj2278 = 0;
    out.unsigned(value.attributes.count);
    for (var _item2276 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2276);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.attributes", hash);
        if (at >= 0) {
            _hits2277.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _a_Attribute_write(out, _item2276);
        }
    }
    base.missed("s.*.attributes", $"s.{slot}.attributes", _hits2277.count);
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2284 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2284);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2229 = input.text();
    var _f2230 = _m_TypeName_read(input);
    var _f2234 = Array<GenericParam>();
    var _n2235 = input.count();
    for (var _ in 0.._n2235) {
        var _tag2236 = input.unsigned();
        if (_tag2236 & 1 == 1) {
            _f2234.append(was.generic_params[_tag2236 >> 1]);
        } else {
            _f2234.append(_m_GenericParam_read(input));
        }
    }
    var _f2241 = Array<VariableDef>();
    var _n2242 = input.count();
    for (var _ in 0.._n2242) {
        var _tag2243 = input.unsigned();
        if (_tag2243 & 1 == 1) {
            _f2241.append(was.field_members[_tag2243 >> 1]);
        } else {
            _f2241.append(_m_VariableDef_read(input));
        }
    }
    var _f2248 = Array<FunctionDef>();
    var _n2249 = input.count();
    for (var _ in 0.._n2249) {
        var _tag2250 = input.unsigned();
        if (_tag2250 & 1 == 1) {
            _f2248.append(was.method_members[_tag2250 >> 1]);
        } else {
            _f2248.append(_m_FunctionDef_read(input));
        }
    }
    var _f2255 = Array<FunctionDef>();
    var _n2256 = input.count();
    for (var _ in 0.._n2256) {
        var _tag2257 = input.unsigned();
        if (_tag2257 & 1 == 1) {
            _f2255.append(was.generic_methods[_tag2257 >> 1]);
        } else {
            _f2255.append(_m_FunctionDef_read(input));
        }
    }
    var _f2262 = Array<FunctionDef>();
    var _n2263 = input.count();
    for (var _ in 0.._n2263) {
        var _tag2264 = input.unsigned();
        if (_tag2264 & 1 == 1) {
            _f2262.append(was.constructors[_tag2264 >> 1]);
        } else {
            _f2262.append(_m_FunctionDef_read(input));
        }
    }
    var _f2266 = _m_FunctionDef_read(input);
    var _f2267 = _m_FunctionDef_read(input);
    var _f2268 = _m_FunctionDef_read(input);
    var _f2272 = Array<TypeName>();
    var _n2273 = input.count();
    for (var _ in 0.._n2273) {
        var _tag2274 = input.unsigned();
        if (_tag2274 & 1 == 1) {
            _f2272.append(was.traits[_tag2274 >> 1]);
        } else {
            _f2272.append(_m_TypeName_read(input));
        }
    }
    var _f2279 = Array<ast.Attribute>();
    var _n2280 = input.count();
    for (var _ in 0.._n2280) {
        var _tag2281 = input.unsigned();
        if (_tag2281 & 1 == 1) {
            _f2279.append(was.attributes[_tag2281 >> 1]);
        } else {
            _f2279.append(_a_Attribute_read(input));
        }
    }
    var _f2283 = input.loc();
    var _o2285 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2286 = Array<EnumCaseDef>();
        var _n2287 = input.count();
        for (var _ in 0.._n2287) {
            _v2286.append(_m_EnumCaseDef_read(input));
        }
        _o2285 = Optional<Array<EnumCaseDef>>.Value(_v2286);
    }
    var _f2288 = _o2285;
    return StructDef(
        _f2229, _f2230, _f2234, _f2241, _f2248, _f2255, _f2262, _f2266, _f2267, _f2268, _f2272, _f2279, _f2283, _f2288
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    ulong _j2237 = 0;
    for (var _item2231 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2231);
        base.add($"s.{slot}.generic_params", scratch, _j2237);
        _j2237 += 1;
    }
    ulong _j2244 = 0;
    for (var _item2238 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2238);
        base.add($"s.{slot}.field_members", scratch, _j2244);
        _j2244 += 1;
    }
    ulong _j2251 = 0;
    for (var _item2245 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2245);
        base.add($"s.{slot}.method_members", scratch, _j2251);
        _j2251 += 1;
    }
    ulong _j2258 = 0;
    for (var _item2252 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2252);
        base.add($"s.{slot}.generic_methods", scratch, _j2258);
        _j2258 += 1;
    }
    ulong _j2265 = 0;
    for (var _item2259 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2259);
        base.add($"s.{slot}.constructors", scratch, _j2265);
        _j2265 += 1;
    }
    ulong _j2275 = 0;
    for (var _item2269 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2269);
        base.add($"s.{slot}.traits", scratch, _j2275);
        _j2275 += 1;
    }
    ulong _j2282 = 0;
    for (var _item2276 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2276);
        base.add($"s.{slot}.attributes", scratch, _j2282);
        _j2282 += 1;
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _hits2292 = HashSet<long>();
    ulong _nj2293 = 0;
    out.unsigned(value.generic_params.count);
    for (var _item2291 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2291);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.generic_params", hash);
        if (at >= 0) {
            _hits2292.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_GenericParam_write(out, _item2291);
        }
    }
    base.missed("t.*.generic_params", $"t.{slot}.generic_params", _hits2292.count);
    var _hits2299 = HashSet<long>();
    ulong _nj2300 = 0;
    out.unsigned(value.field_members.count);
    for (var _item2298 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2298);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.field_members", hash);
        if (at >= 0) {
            _hits2299.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_VariableDef_write(out, _item2298);
        }
    }
    base.missed("t.*.field_members", $"t.{slot}.field_members", _hits2299.count);
    var _hits2306 = HashSet<long>();
    ulong _nj2307 = 0;
    out.unsigned(value.method_members.count);
    for (var _item2305 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2305);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.method_members", hash);
        if (at >= 0) {
            _hits2306.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2305);
        }
    }
    base.missed("t.*.method_members", $"t.{slot}.method_members", _hits2306.count);
    var _hits2313 = HashSet<long>();
    ulong _nj2314 = 0;
    out.unsigned(value.generic_methods.count);
    for (var _item2312 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2312);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.generic_methods", hash);
        if (at >= 0) {
            _hits2313.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2312);
        }
    }
    base.missed("t.*.generic_methods", $"t.{slot}.generic_methods", _hits2313.count);
    var _hits2320 = HashSet<long>();
    ulong _nj2321 = 0;
    out.unsigned(value.constructors.count);
    for (var _item2319 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2319);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.constructors", hash);
        if (at >= 0) {
            _hits2320.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2319);
        }
    }
    base.missed("t.*.constructors", $"t.{slot}.constructors", _hits2320.count);
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _hits2330 = HashSet<long>();
    ulong _nj2331 = 0;
    out.unsigned(value.traits.count);
    for (var _item2329 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2329);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.traits", hash);
        if (at >= 0) {
            _hits2330.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeName_write(out, _item2329);
        }
    }
    base.missed("t.*.traits", $"t.{slot}.traits", _hits2330.count);
    var _hits2337 = HashSet<long>();
    ulong _nj2338 = 0;
    out.unsigned(value.attributes.count);
    for (var _item2336 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2336);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.attributes", hash);
        if (at >= 0) {
            _hits2337.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _a_Attribute_write(out, _item2336);
        }
    }
    base.missed("t.*.attributes", $"t.{slot}.attributes", _hits2337.count);
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2344 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2344);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2289 = input.text();
    var _f2290 = _m_TypeName_read(input);
    var _f2294 = Array<GenericParam>();
    var _n2295 = input.count();
    for (var _ in 0.._n2295) {
        var _tag2296 = input.unsigned();
        if (_tag2296 & 1 == 1) {
            _f2294.append(was.generic_params[_tag2296 >> 1]);
        } else {
            _f2294.append(_m_GenericParam_read(input));
        }
    }
    var _f2301 = Array<VariableDef>();
    var _n2302 = input.count();
    for (var _ in 0.._n2302) {
        var _tag2303 = input.unsigned();
        if (_tag2303 & 1 == 1) {
            _f2301.append(was.field_members[_tag2303 >> 1]);
        } else {
            _f2301.append(_m_VariableDef_read(input));
        }
    }
    var _f2308 = Array<FunctionDef>();
    var _n2309 = input.count();
    for (var _ in 0.._n2309) {
        var _tag2310 = input.unsigned();
        if (_tag2310 & 1 == 1) {
            _f2308.append(was.method_members[_tag2310 >> 1]);
        } else {
            _f2308.append(_m_FunctionDef_read(input));
        }
    }
    var _f2315 = Array<FunctionDef>();
    var _n2316 = input.count();
    for (var _ in 0.._n2316) {
        var _tag2317 = input.unsigned();
        if (_tag2317 & 1 == 1) {
            _f2315.append(was.generic_methods[_tag2317 >> 1]);
        } else {
            _f2315.append(_m_FunctionDef_read(input));
        }
    }
    var _f2322 = Array<FunctionDef>();
    var _n2323 = input.count();
    for (var _ in 0.._n2323) {
        var _tag2324 = input.unsigned();
        if (_tag2324 & 1 == 1) {
            _f2322.append(was.constructors[_tag2324 >> 1]);
        } else {
            _f2322.append(_m_FunctionDef_read(input));
        }
    }
    var _f2326 = _m_FunctionDef_read(input);
    var _f2327 = _m_FunctionDef_read(input);
    var _f2328 = _m_FunctionDef_read(input);
    var _f2332 = Array<TypeName>();
    var _n2333 = input.count();
    for (var _ in 0.._n2333) {
        var _tag2334 = input.unsigned();
        if (_tag2334 & 1 == 1) {
            _f2332.append(was.traits[_tag2334 >> 1]);
        } else {
            _f2332.append(_m_TypeName_read(input));
        }
    }
    var _f2339 = Array<ast.Attribute>();
    var _n2340 = input.count();
    for (var _ in 0.._n2340) {
        var _tag2341 = input.unsigned();
        if (_tag2341 & 1 == 1) {
            _f2339.append(was.attributes[_tag2341 >> 1]);
        } else {
            _f2339.append(_a_Attribute_read(input));
        }
    }
    var _f2343 = input.loc();
    var _o2345 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2346 = Array<EnumCaseDef>();
        var _n2347 = input.count();
        for (var _ in 0.._n2347) {
            _v2346.append(_m_EnumCaseDef_read(input));
        }
        _o2345 = Optional<Array<EnumCaseDef>>.Value(_v2346);
    }
    var _f2348 = _o2345;
    return StructDef(
        _f2289, _f2290, _f2294, _f2301, _f2308, _f2315, _f2322, _f2326, _f2327, _f2328, _f2332, _f2339, _f2343, _f2348
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    ulong _j2297 = 0;
    for (var _item2291 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2291);
        base.add($"t.{slot}.generic_params", scratch, _j2297);
        _j2297 += 1;
    }
    ulong _j2304 = 0;
    for (var _item2298 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2298);
        base.add($"t.{slot}.field_members", scratch, _j2304);
        _j2304 += 1;
    }
    ulong _j2311 = 0;
    for (var _item2305 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2305);
        base.add($"t.{slot}.method_members", scratch, _j2311);
        _j2311 += 1;
    }
    ulong _j2318 = 0;
    for (var _item2312 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2312);
        base.add($"t.{slot}.generic_methods", scratch, _j2318);
        _j2318 += 1;
    }
    ulong _j2325 = 0;
    for (var _item2319 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2319);
        base.add($"t.{slot}.constructors", scratch, _j2325);
        _j2325 += 1;
    }
    ulong _j2335 = 0;
    for (var _item2329 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2329);
        base.add($"t.{slot}.traits", scratch, _j2335);
        _j2335 += 1;
    }
    ulong _j2342 = 0;
    for (var _item2336 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2336);
        base.add($"t.{slot}.attributes", scratch, _j2342);
        _j2342 += 1;
    }
}

_m_Module_interface_fields(value: Module, interface: bool): Array<(String, String)> {
    var found = Array<(String, String)>();
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.imports.count);
        for (var _item2349 in value.imports) {
            _a_Import_write(out, _item2349);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2350 in value.structs) {
            _m_StructDef_write(out, _item2350);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.traits.count);
        for (var _item2351 in value.traits) {
            _m_TraitDef_write(out, _item2351);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2352 in value.extensions) {
            _m_ExtensionDef_write(out, _item2352);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2353 in value.functions) {
            _m_FunctionDef_write(out, _item2353);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2354 in value.externs) {
            _m_ExternDef_write(out, _item2354);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2355 in value.globals) {
            _m_VariableDef_write(out, _item2355);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2356 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2356);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2357 in value.enums) {
            _m_EnumDef_write(out, _item2357);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2358 in value.struct_specs) {
            _m_TypeName_write(out, _item2358);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2359 in value.func_specs) {
            _m_TypeName_write(out, _item2359);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2360 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2360);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2361 in value.withheld) {
            _m_Withheld_write(out, _item2361);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2362 in value.properties) {
            _m_PropertyDef_write(out, _item2362);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2363 in value.type_uses) {
            _m_TypeUse_write(out, _item2363);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2364 in value.use_contexts) {
            _m_UseContext_write(out, _item2364);
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
            for (var _item2365 in value.literal_args) {
                var (_t2366, _t2367, _t2368) = _item2365;
                out.loc(_t2366);
                out.unsigned(_t2367);
                out.loc(_t2368);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2369 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2369);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2370 in value.trait_types) {
            _m_TraitType_write(out, _item2370);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2371 in value.conversions) {
            _m_Conversion_write(out, _item2371);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2373 = Array<(u8[], u8[], String)>();
        for (var (_key2372, _) in value.overload_sets) {
            var _scratch2374 = out.scratch();
            _scratch2374.text(_key2372);
            var _vscratch2376 = out.scratch();
            _vscratch2376.unsigned(value.overload_sets[_key2372].count);
            for (var _item2377 in value.overload_sets[_key2372]) {
                _vscratch2376.text(_item2377);
            }
            _keys2373.append((_scratch2374.finish(), _vscratch2376.finish(), _key2372));
        }
        _keys2373.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2373.count);
        for (var (_bytes2375, _, _key2372) in _keys2373) {
            out.text(_key2372);
            out.unsigned(value.overload_sets[_key2372].count);
            for (var _item2378 in value.overload_sets[_key2372]) {
                out.text(_item2378);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2380 = Array<(u8[], u8[], String)>();
        for (var (_key2379, _) in value.overload_unions) {
            var _scratch2381 = out.scratch();
            _scratch2381.text(_key2379);
            var _vscratch2383 = out.scratch();
            _vscratch2383.unsigned(value.overload_unions[_key2379].count);
            for (var _item2384 in value.overload_unions[_key2379]) {
                _vscratch2383.unsigned(_item2384.count);
                for (var _item2385 in _item2384) {
                    _vscratch2383.text(_item2385);
                }
            }
            _keys2380.append((_scratch2381.finish(), _vscratch2383.finish(), _key2379));
        }
        _keys2380.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2380.count);
        for (var (_bytes2382, _, _key2379) in _keys2380) {
            out.text(_key2379);
            out.unsigned(value.overload_unions[_key2379].count);
            for (var _item2386 in value.overload_unions[_key2379]) {
                out.unsigned(_item2386.count);
                for (var _item2387 in _item2386) {
                    out.text(_item2387);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2389 = Array<(u8[], u8[], String)>();
        for (var (_key2388, _) in value.method_overload_sets) {
            var _scratch2390 = out.scratch();
            _scratch2390.text(_key2388);
            var _vscratch2392 = out.scratch();
            var _keys2394 = Array<(u8[], u8[], String)>();
            for (var (_key2393, _) in value.method_overload_sets[_key2388]) {
                var _scratch2395 = _vscratch2392.scratch();
                _scratch2395.text(_key2393);
                var _vscratch2397 = _vscratch2392.scratch();
                _vscratch2397.unsigned(value.method_overload_sets[_key2388][_key2393].count);
                for (var _item2398 in value.method_overload_sets[_key2388][_key2393]) {
                    _vscratch2397.text(_item2398);
                }
                _keys2394.append((_scratch2395.finish(), _vscratch2397.finish(), _key2393));
            }
            _keys2394.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2392.unsigned(_keys2394.count);
            for (var (_bytes2396, _, _key2393) in _keys2394) {
                _vscratch2392.text(_key2393);
                _vscratch2392.unsigned(value.method_overload_sets[_key2388][_key2393].count);
                for (var _item2399 in value.method_overload_sets[_key2388][_key2393]) {
                    _vscratch2392.text(_item2399);
                }
            }
            _keys2389.append((_scratch2390.finish(), _vscratch2392.finish(), _key2388));
        }
        _keys2389.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2389.count);
        for (var (_bytes2391, _, _key2388) in _keys2389) {
            out.text(_key2388);
            var _keys2401 = Array<(u8[], u8[], String)>();
            for (var (_key2400, _) in value.method_overload_sets[_key2388]) {
                var _scratch2402 = out.scratch();
                _scratch2402.text(_key2400);
                var _vscratch2404 = out.scratch();
                _vscratch2404.unsigned(value.method_overload_sets[_key2388][_key2400].count);
                for (var _item2405 in value.method_overload_sets[_key2388][_key2400]) {
                    _vscratch2404.text(_item2405);
                }
                _keys2401.append((_scratch2402.finish(), _vscratch2404.finish(), _key2400));
            }
            _keys2401.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2401.count);
            for (var (_bytes2403, _, _key2400) in _keys2401) {
                out.text(_key2400);
                out.unsigned(value.method_overload_sets[_key2388][_key2400].count);
                for (var _item2406 in value.method_overload_sets[_key2388][_key2400]) {
                    out.text(_item2406);
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
        var _keys2408 = Array<(u8[], u8[], Loc)>();
        for (var _key2407 in value.private_functions) {
            var _scratch2409 = out.scratch();
            _scratch2409.loc(_key2407);
            var _vscratch2411 = out.scratch();
            _keys2408.append((_scratch2409.finish(), _vscratch2411.finish(), _key2407));
        }
        _keys2408.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2408.count);
        for (var (_bytes2410, _, _key2407) in _keys2408) {
            out.loc(_key2407);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2413 = Array<(u8[], u8[], Loc)>();
        for (var _key2412 in value.file_private_functions) {
            var _scratch2414 = out.scratch();
            _scratch2414.loc(_key2412);
            var _vscratch2416 = out.scratch();
            _keys2413.append((_scratch2414.finish(), _vscratch2416.finish(), _key2412));
        }
        _keys2413.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2413.count);
        for (var (_bytes2415, _, _key2412) in _keys2413) {
            out.loc(_key2412);
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
            for (var _item2417 in value.call_targets) {
                var (_t2418, _t2419) = _item2417;
                out.loc(_t2418);
                out.text(_t2419);
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
            for (var _item2420 in value.argument_names) {
                var (_t2421, _t2422) = _item2420;
                out.loc(_t2421);
                out.text(_t2422);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2423 in value.namespaces) {
            out.text(_item2423);
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
            for (var _item2424 in value.cached_files) {
                out.flag(_item2424);
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
            var _keys2426 = Array<(u8[], u8[], Loc)>();
            for (var (_key2425, _) in value.recorded_summaries) {
                var _scratch2427 = out.scratch();
                _scratch2427.loc(_key2425);
                var _vscratch2429 = out.scratch();
                _vscratch2429.text(value.recorded_summaries[_key2425]);
                _keys2426.append((_scratch2427.finish(), _vscratch2429.finish(), _key2425));
            }
            _keys2426.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2426.count);
            for (var (_bytes2428, _, _key2425) in _keys2426) {
                out.loc(_key2425);
                out.text(value.recorded_summaries[_key2425]);
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
            var _keys2431 = Array<(u8[], u8[], Loc)>();
            for (var _key2430 in value.stripped) {
                var _scratch2432 = out.scratch();
                _scratch2432.loc(_key2430);
                var _vscratch2434 = out.scratch();
                _keys2431.append((_scratch2432.finish(), _vscratch2434.finish(), _key2430));
            }
            _keys2431.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2431.count);
            for (var (_bytes2433, _, _key2430) in _keys2431) {
                out.loc(_key2430);
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
        var _keys2436 = Array<(u8[], u8[], String)>();
        for (var (_key2435, _) in value.spec_requests) {
            var _scratch2437 = out.scratch();
            _scratch2437.text(_key2435);
            var _vscratch2439 = out.scratch();
            _m_SpecRequest_write(_vscratch2439, value.spec_requests[_key2435]);
            _keys2436.append((_scratch2437.finish(), _vscratch2439.finish(), _key2435));
        }
        _keys2436.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2436.count);
        for (var (_bytes2438, _, _key2435) in _keys2436) {
            out.text(_key2435);
            _m_SpecRequest_write(out, value.spec_requests[_key2435]);
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
            for (var _item2440 in value.summaries_to_record) {
                var (_t2441, _t2442) = _item2440;
                out.loc(_t2441);
                out.text(_t2442);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2444 = Array<(u8[], u8[], String)>();
        for (var (_key2443, _) in value.caller_copies) {
            var _scratch2445 = out.scratch();
            _scratch2445.text(_key2443);
            var _vscratch2447 = out.scratch();
            _vscratch2447.unsigned(value.caller_copies[_key2443].count);
            for (var _item2448 in value.caller_copies[_key2443]) {
                _vscratch2447.flag(_item2448);
            }
            _keys2444.append((_scratch2445.finish(), _vscratch2447.finish(), _key2443));
        }
        _keys2444.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2444.count);
        for (var (_bytes2446, _, _key2443) in _keys2444) {
            out.text(_key2443);
            out.unsigned(value.caller_copies[_key2443].count);
            for (var _item2449 in value.caller_copies[_key2443]) {
                out.flag(_item2449);
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
    for (var _item2450 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2450);
        found.append(("structs " + _item2450.name, interface_text(out)));
    }
    for (var _item2451 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2451);
        found.append(("functions " + _item2451.name, interface_text(out)));
    }
    return found;
}

_m_Module_interface_elements(value: Module): Array<(String, String)> {
    var found = Array<(String, String)>();
    for (var _item2452 in value.imports) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _a_Import_write(out, _item2452);
        found.append(("imports", interface_text(out)));
    }
    for (var _item2453 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_StructDef_write(out, _item2453);
        found.append(("structs", interface_text(out)));
    }
    for (var _item2454 in value.traits) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_TraitDef_write(out, _item2454);
        found.append(("traits", interface_text(out)));
    }
    for (var _item2455 in value.extensions) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_ExtensionDef_write(out, _item2455);
        found.append(("extensions", interface_text(out)));
    }
    for (var _item2456 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_FunctionDef_write(out, _item2456);
        found.append(("functions", interface_text(out)));
    }
    for (var _item2457 in value.externs) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_ExternDef_write(out, _item2457);
        found.append(("externs", interface_text(out)));
    }
    for (var _item2458 in value.globals) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_VariableDef_write(out, _item2458);
        found.append(("globals", interface_text(out)));
    }
    for (var _item2459 in value.static_blocks) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_ModuleStaticBlock_write(out, _item2459);
        found.append(("static_blocks", interface_text(out)));
    }
    for (var _item2460 in value.enums) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_EnumDef_write(out, _item2460);
        found.append(("enums", interface_text(out)));
    }
    for (var _item2461 in value.struct_specs) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_TypeName_write(out, _item2461);
        found.append(("struct_specs", interface_text(out)));
    }
    for (var _item2462 in value.func_specs) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_TypeName_write(out, _item2462);
        found.append(("func_specs", interface_text(out)));
    }
    for (var _item2463 in value.type_aliases) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_TypeAliasDef_write(out, _item2463);
        found.append(("type_aliases", interface_text(out)));
    }
    for (var _item2464 in value.withheld) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_Withheld_write(out, _item2464);
        found.append(("withheld", interface_text(out)));
    }
    for (var _item2465 in value.properties) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_PropertyDef_write(out, _item2465);
        found.append(("properties", interface_text(out)));
    }
    for (var _item2466 in value.type_uses) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_TypeUse_write(out, _item2466);
        found.append(("type_uses", interface_text(out)));
    }
    for (var _item2467 in value.use_contexts) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_UseContext_write(out, _item2467);
        found.append(("use_contexts", interface_text(out)));
    }
    for (var _item2468 in value.constrained_aliases) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_TypeAliasDef_write(out, _item2468);
        found.append(("constrained_aliases", interface_text(out)));
    }
    for (var _item2469 in value.trait_types) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_TraitType_write(out, _item2469);
        found.append(("trait_types", interface_text(out)));
    }
    for (var _item2470 in value.conversions) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_Conversion_write(out, _item2470);
        found.append(("conversions", interface_text(out)));
    }
    for (var (_key2471, _) in value.overload_sets) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.text(_key2471);
        out.unsigned(value.overload_sets[_key2471].count);
        for (var _item2472 in value.overload_sets[_key2471]) {
            out.text(_item2472);
        }
        found.append(("overload_sets", interface_text(out)));
    }
    for (var (_key2473, _) in value.overload_unions) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.text(_key2473);
        out.unsigned(value.overload_unions[_key2473].count);
        for (var _item2474 in value.overload_unions[_key2473]) {
            out.unsigned(_item2474.count);
            for (var _item2475 in _item2474) {
                out.text(_item2475);
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    for (var (_key2476, _) in value.method_overload_sets) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.text(_key2476);
        var _keys2478 = Array<(u8[], u8[], String)>();
        for (var (_key2477, _) in value.method_overload_sets[_key2476]) {
            var _scratch2479 = out.scratch();
            _scratch2479.text(_key2477);
            var _vscratch2481 = out.scratch();
            _vscratch2481.unsigned(value.method_overload_sets[_key2476][_key2477].count);
            for (var _item2482 in value.method_overload_sets[_key2476][_key2477]) {
                _vscratch2481.text(_item2482);
            }
            _keys2478.append((_scratch2479.finish(), _vscratch2481.finish(), _key2477));
        }
        _keys2478.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2478.count);
        for (var (_bytes2480, _, _key2477) in _keys2478) {
            out.text(_key2477);
            out.unsigned(value.method_overload_sets[_key2476][_key2477].count);
            for (var _item2483 in value.method_overload_sets[_key2476][_key2477]) {
                out.text(_item2483);
            }
        }
        found.append(("method_overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        _m_ExtensionScopes_write(out, value.extension_scopes);
        found.append(("extension_scopes", interface_text(out)));
    }
    for (var _item2484 in value.private_functions) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.loc(_item2484);
        found.append(("private_functions", interface_text(out)));
    }
    for (var _item2485 in value.file_private_functions) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.loc(_item2485);
        found.append(("file_private_functions", interface_text(out)));
    }
    for (var _item2486 in value.namespaces) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.text(_item2486);
        found.append(("namespaces", interface_text(out)));
    }
    for (var (_, _text2487) in value.recorded_summaries) {
        var out = RecordOut();
        out.text(summary_without_place(_text2487));
        found.append(("recorded_summaries", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.flag(value.templates.frozen);
        found.append(("templates frozen", interface_text(out)));
    }
    for (var _item2488 in value.templates.structs) {
        var out = RecordOut();
        out.blank_bodies = false;
        out.blank_locs = true;
        _m_StructDef_write(out, _item2488);
        found.append(("templates structs", interface_text(out)));
    }
    for (var _item2489 in value.templates.functions) {
        var out = RecordOut();
        out.blank_bodies = false;
        out.blank_locs = true;
        _m_FunctionDef_write(out, _item2489);
        found.append(("templates functions", interface_text(out)));
    }
    for (var _name2490 in value.checked.structs) {
        var out = RecordOut();
        out.text(_name2490);
        found.append(("checked structs", interface_text(out)));
    }
    for (var _name2491 in value.checked.functions) {
        var out = RecordOut();
        out.text(_name2491);
        found.append(("checked functions", interface_text(out)));
    }
    for (var _name2492 in value.checked.globals) {
        var out = RecordOut();
        out.text(_name2492);
        found.append(("checked globals", interface_text(out)));
    }
    for (var (_key2493, (_, _text2494)) in value.checked.summaries) {
        var out = RecordOut();
        out.text(_key2493);
        out.text(summary_without_place(_text2494));
        found.append(("checked summaries", interface_text(out)));
    }
    for (var (_key2495, _) in value.spec_requests) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.text(_key2495);
        _m_SpecRequest_write(out, value.spec_requests[_key2495]);
        found.append(("spec_requests", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.flag(value.record_summaries);
        found.append(("record_summaries", interface_text(out)));
    }
    for (var (_key2496, _) in value.caller_copies) {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.text(_key2496);
        out.unsigned(value.caller_copies[_key2496].count);
        for (var _item2497 in value.caller_copies[_key2496]) {
            out.flag(_item2497);
        }
        found.append(("caller_copies", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = true;
        out.blank_locs = true;
        out.flag(value.linked);
        found.append(("linked", interface_text(out)));
    }
    return found;
}
