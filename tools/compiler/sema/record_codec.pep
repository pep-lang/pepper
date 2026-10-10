## Saving and loading a checked module: a binary writer and reader for
## every type `Module` reaches, the AST nodes it holds included. Generated
## by `scripts/gen-sema-record.py`; do not edit.

import compiler.ast;
import [Loc] from "loc";
import "model";
import "pending";
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
    out.flag(value.c_pointer);
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
    var _f491 = input.flag();
    var value = ast.TypeName();
    value.name = _f482;
    value.generic_types = _f485;
    value.span = _f487;
    value.labels = _f490;
    value.c_pointer = _f491;
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
    return _m_StructDef_read_with(input, false);
}

_m_StructDef_read_lazy(input: RecordIn): StructDef {
    return _m_StructDef_read_with(input, input.lazy_bodies);
}

_m_StructDef_read_with(input: RecordIn, lazy: bool): StructDef {
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
        _v1114.append(_m_FunctionDef_read_with(input, lazy));
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
        _v1120.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1122 = _v1120;
    var _f1123 = _m_FunctionDef_read_with(input, lazy);
    var _f1124 = _m_FunctionDef_read_with(input, lazy);
    var _f1125 = _m_FunctionDef_read_with(input, lazy);
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
    var _hs1487 = Array<String>();
    for (var _item1481 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1481);
        _hs1487.append(base.hash_of(scratch));
    }
    var _seq1488 = base.sequence("imports");
    ulong _bj1489 = 0;
    var _news1490 = Array<ulong>();
    for (var _i1491 in 0.._hs1487.count) {
        if (_bj1489 < _seq1488.count and _hs1487[_i1491] == _seq1488[_bj1489]) {
            _bj1489 += 1;
        } else {
            _news1490.append(_i1491);
        }
    }
    for (var _i1491 in 0.._hs1487.count) {
        next.add_hashed("imports", _hs1487[_i1491], _i1491);
    }
    if (_bj1489 == _seq1488.count) {
        out.unsigned(2);
        out.unsigned(_news1490.count);
        for (var _i1491 in _news1490) {
            out.unsigned(_i1491);
            _a_Import_write(out, value.imports[_i1491]);
            {
                var _own1492 = RecordOut();
                _own1492.blank_bodies = true;
                _own1492.blank_locs = true;
                _own1492.pending_as_bytes = true;
                _a_Import_write(_own1492, value.imports[_i1491]);
                base.own("imports", interface_text(_own1492));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1491 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1491]);
            {
                var _own1493 = RecordOut();
                _own1493.blank_bodies = true;
                _own1493.blank_locs = true;
                _own1493.pending_as_bytes = true;
                _a_Import_write(_own1493, value.imports[_i1491]);
                base.own("imports", interface_text(_own1493));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1503 = Array<String>();
    for (var _item1501 in value.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1501);
        _hs1503.append(base.hash_of(scratch));
    }
    var _seq1504 = base.sequence("s");
    var _seqn1505 = base.sequence("s#");
    ulong _bj1506 = 0;
    var _news1507 = Array<ulong>();
    var _patches1508 = Array<(ulong, ulong)>();
    for (var _i1509 in 0.._hs1503.count) {
        if (_bj1506 < _seq1504.count and _hs1503[_i1509] == _seq1504[_bj1506]) {
            _bj1506 += 1;
        } else if (_bj1506 < _seq1504.count
            and _bj1506 < _seqn1505.count
            and value.structs[_i1509].name == _seqn1505[_bj1506]) {
            _patches1508.append((_i1509, _bj1506));
            _bj1506 += 1;
        } else {
            _news1507.append(_i1509);
        }
    }
    if (_bj1506 == _seq1504.count) {
        out.unsigned(2);
        out.unsigned(_patches1508.count);
        for (var (_i1509, _b) in _patches1508) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1509].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1509], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1510 = RecordOut();
                _own1510.blank_bodies = true;
                _own1510.blank_locs = true;
                _own1510.pending_as_bytes = true;
                _m_StructDef_write(_own1510, value.structs[_i1509]);
                base.own("structs", interface_text(_own1510));
            }
        }
        out.unsigned(_news1507.count);
        for (var _i1509 in _news1507) {
            ulong _before = out.values.count;
            out.unsigned(_i1509);
            _m_StructDef_write(out, value.structs[_i1509]);
            base.count("s new", out.values.count - _before);
            {
                var _own1511 = RecordOut();
                _own1511.blank_bodies = true;
                _own1511.blank_locs = true;
                _own1511.pending_as_bytes = true;
                _m_StructDef_write(_own1511, value.structs[_i1509]);
                base.own("structs", interface_text(_own1511));
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1502 = HashSet<long>();
        out.unsigned(value.structs.count);
        for (var _i1509 in 0..value.structs.count) {
            var _item1501 = value.structs[_i1509];
            var at = base.find_hashed("s", _hs1503[_i1509]);
            var named = base.named("s", _item1501.name);
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1502.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1502.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1501, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1501);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1502.count);
    }
    for (var _i1509 in 0.._hs1503.count) {
        next.add_hashed("s", _hs1503[_i1509], _i1509);
        next.name("s", value.structs[_i1509].name, _i1509);
        _patch_s_index(value.structs[_i1509], next, _i1509);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1526 = Array<String>();
    for (var _item1520 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1520);
        _hs1526.append(base.hash_of(scratch));
    }
    var _seq1527 = base.sequence("traits");
    ulong _bj1528 = 0;
    var _news1529 = Array<ulong>();
    for (var _i1530 in 0.._hs1526.count) {
        if (_bj1528 < _seq1527.count and _hs1526[_i1530] == _seq1527[_bj1528]) {
            _bj1528 += 1;
        } else {
            _news1529.append(_i1530);
        }
    }
    for (var _i1530 in 0.._hs1526.count) {
        next.add_hashed("traits", _hs1526[_i1530], _i1530);
    }
    if (_bj1528 == _seq1527.count) {
        out.unsigned(2);
        out.unsigned(_news1529.count);
        for (var _i1530 in _news1529) {
            out.unsigned(_i1530);
            _m_TraitDef_write(out, value.traits[_i1530]);
            {
                var _own1531 = RecordOut();
                _own1531.blank_bodies = true;
                _own1531.blank_locs = true;
                _own1531.pending_as_bytes = true;
                _m_TraitDef_write(_own1531, value.traits[_i1530]);
                base.own("traits", interface_text(_own1531));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1530 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1530]);
            {
                var _own1532 = RecordOut();
                _own1532.blank_bodies = true;
                _own1532.blank_locs = true;
                _own1532.pending_as_bytes = true;
                _m_TraitDef_write(_own1532, value.traits[_i1530]);
                base.own("traits", interface_text(_own1532));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1546 = Array<String>();
    for (var _item1540 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1540);
        _hs1546.append(base.hash_of(scratch));
    }
    var _seq1547 = base.sequence("extensions");
    ulong _bj1548 = 0;
    var _news1549 = Array<ulong>();
    for (var _i1550 in 0.._hs1546.count) {
        if (_bj1548 < _seq1547.count and _hs1546[_i1550] == _seq1547[_bj1548]) {
            _bj1548 += 1;
        } else {
            _news1549.append(_i1550);
        }
    }
    for (var _i1550 in 0.._hs1546.count) {
        next.add_hashed("extensions", _hs1546[_i1550], _i1550);
    }
    if (_bj1548 == _seq1547.count) {
        out.unsigned(2);
        out.unsigned(_news1549.count);
        for (var _i1550 in _news1549) {
            out.unsigned(_i1550);
            _m_ExtensionDef_write(out, value.extensions[_i1550]);
            {
                var _own1551 = RecordOut();
                _own1551.blank_bodies = true;
                _own1551.blank_locs = true;
                _own1551.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1551, value.extensions[_i1550]);
                base.own("extensions", interface_text(_own1551));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1550 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1550]);
            {
                var _own1552 = RecordOut();
                _own1552.blank_bodies = true;
                _own1552.blank_locs = true;
                _own1552.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1552, value.extensions[_i1550]);
                base.own("extensions", interface_text(_own1552));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1566 = Array<String>();
    for (var _item1560 in value.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1560);
        _hs1566.append(base.hash_of(scratch));
    }
    var _seq1567 = base.sequence("functions");
    ulong _bj1568 = 0;
    var _news1569 = Array<ulong>();
    var _changed1561 = Array<(ulong, ulong)>();
    var _seqn1562 = base.sequence("functions" + "#");
    for (var _i1570 in 0.._hs1566.count) {
        if (_bj1568 < _seq1567.count and _hs1566[_i1570] == _seq1567[_bj1568]) {
            _bj1568 += 1;
        } else if (_bj1568 < _seqn1562.count and value.functions[_i1570].name == _seqn1562[_bj1568]) {
            _changed1561.append((_i1570, _bj1568));
            _bj1568 += 1;
        } else {
            _news1569.append(_i1570);
        }
    }
    for (var _i1570 in 0.._hs1566.count) {
        next.add_hashed("functions", _hs1566[_i1570], _i1570);
        next.name("functions", value.functions[_i1570].name, _i1570);
    }
    if (_bj1568 == _seq1567.count) {
        out.unsigned(2);
        out.unsigned(_changed1561.count);
        for (var (_i1570, _b) in _changed1561) {
            out.text(value.functions[_i1570].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1570]);
            {
                var _own1571 = RecordOut();
                _own1571.blank_bodies = true;
                _own1571.blank_locs = true;
                _own1571.pending_as_bytes = true;
                _m_FunctionDef_write(_own1571, value.functions[_i1570]);
                base.own("functions", interface_text(_own1571));
            }
        }
        base.count("functions" + " changed", _changed1561.count);
        out.unsigned(_news1569.count);
        for (var _i1570 in _news1569) {
            out.unsigned(_i1570);
            _m_FunctionDef_write(out, value.functions[_i1570]);
            {
                var _own1572 = RecordOut();
                _own1572.blank_bodies = true;
                _own1572.blank_locs = true;
                _own1572.pending_as_bytes = true;
                _m_FunctionDef_write(_own1572, value.functions[_i1570]);
                base.own("functions", interface_text(_own1572));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1570 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1570]);
            {
                var _own1573 = RecordOut();
                _own1573.blank_bodies = true;
                _own1573.blank_locs = true;
                _own1573.pending_as_bytes = true;
                _m_FunctionDef_write(_own1573, value.functions[_i1570]);
                base.own("functions", interface_text(_own1573));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1587 = Array<String>();
    for (var _item1581 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1581);
        _hs1587.append(base.hash_of(scratch));
    }
    var _seq1588 = base.sequence("externs");
    ulong _bj1589 = 0;
    var _news1590 = Array<ulong>();
    for (var _i1591 in 0.._hs1587.count) {
        if (_bj1589 < _seq1588.count and _hs1587[_i1591] == _seq1588[_bj1589]) {
            _bj1589 += 1;
        } else {
            _news1590.append(_i1591);
        }
    }
    for (var _i1591 in 0.._hs1587.count) {
        next.add_hashed("externs", _hs1587[_i1591], _i1591);
    }
    if (_bj1589 == _seq1588.count) {
        out.unsigned(2);
        out.unsigned(_news1590.count);
        for (var _i1591 in _news1590) {
            out.unsigned(_i1591);
            _m_ExternDef_write(out, value.externs[_i1591]);
            {
                var _own1592 = RecordOut();
                _own1592.blank_bodies = true;
                _own1592.blank_locs = true;
                _own1592.pending_as_bytes = true;
                _m_ExternDef_write(_own1592, value.externs[_i1591]);
                base.own("externs", interface_text(_own1592));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1591 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1591]);
            {
                var _own1593 = RecordOut();
                _own1593.blank_bodies = true;
                _own1593.blank_locs = true;
                _own1593.pending_as_bytes = true;
                _m_ExternDef_write(_own1593, value.externs[_i1591]);
                base.own("externs", interface_text(_own1593));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1607 = Array<String>();
    for (var _item1601 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1601);
        _hs1607.append(base.hash_of(scratch));
    }
    var _seq1608 = base.sequence("globals");
    ulong _bj1609 = 0;
    var _news1610 = Array<ulong>();
    for (var _i1611 in 0.._hs1607.count) {
        if (_bj1609 < _seq1608.count and _hs1607[_i1611] == _seq1608[_bj1609]) {
            _bj1609 += 1;
        } else {
            _news1610.append(_i1611);
        }
    }
    for (var _i1611 in 0.._hs1607.count) {
        next.add_hashed("globals", _hs1607[_i1611], _i1611);
    }
    if (_bj1609 == _seq1608.count) {
        out.unsigned(2);
        out.unsigned(_news1610.count);
        for (var _i1611 in _news1610) {
            out.unsigned(_i1611);
            _m_VariableDef_write(out, value.globals[_i1611]);
            {
                var _own1612 = RecordOut();
                _own1612.blank_bodies = true;
                _own1612.blank_locs = true;
                _own1612.pending_as_bytes = true;
                _m_VariableDef_write(_own1612, value.globals[_i1611]);
                base.own("globals", interface_text(_own1612));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1611 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1611]);
            {
                var _own1613 = RecordOut();
                _own1613.blank_bodies = true;
                _own1613.blank_locs = true;
                _own1613.pending_as_bytes = true;
                _m_VariableDef_write(_own1613, value.globals[_i1611]);
                base.own("globals", interface_text(_own1613));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1627 = Array<String>();
    for (var _item1621 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1621);
        _hs1627.append(base.hash_of(scratch));
    }
    var _seq1628 = base.sequence("static_blocks");
    ulong _bj1629 = 0;
    var _news1630 = Array<ulong>();
    for (var _i1631 in 0.._hs1627.count) {
        if (_bj1629 < _seq1628.count and _hs1627[_i1631] == _seq1628[_bj1629]) {
            _bj1629 += 1;
        } else {
            _news1630.append(_i1631);
        }
    }
    for (var _i1631 in 0.._hs1627.count) {
        next.add_hashed("static_blocks", _hs1627[_i1631], _i1631);
    }
    if (_bj1629 == _seq1628.count) {
        out.unsigned(2);
        out.unsigned(_news1630.count);
        for (var _i1631 in _news1630) {
            out.unsigned(_i1631);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1631]);
            {
                var _own1632 = RecordOut();
                _own1632.blank_bodies = true;
                _own1632.blank_locs = true;
                _own1632.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1632, value.static_blocks[_i1631]);
                base.own("static_blocks", interface_text(_own1632));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1631 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1631]);
            {
                var _own1633 = RecordOut();
                _own1633.blank_bodies = true;
                _own1633.blank_locs = true;
                _own1633.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1633, value.static_blocks[_i1631]);
                base.own("static_blocks", interface_text(_own1633));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1647 = Array<String>();
    for (var _item1641 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1641);
        _hs1647.append(base.hash_of(scratch));
    }
    var _seq1648 = base.sequence("enums");
    ulong _bj1649 = 0;
    var _news1650 = Array<ulong>();
    for (var _i1651 in 0.._hs1647.count) {
        if (_bj1649 < _seq1648.count and _hs1647[_i1651] == _seq1648[_bj1649]) {
            _bj1649 += 1;
        } else {
            _news1650.append(_i1651);
        }
    }
    for (var _i1651 in 0.._hs1647.count) {
        next.add_hashed("enums", _hs1647[_i1651], _i1651);
    }
    if (_bj1649 == _seq1648.count) {
        out.unsigned(2);
        out.unsigned(_news1650.count);
        for (var _i1651 in _news1650) {
            out.unsigned(_i1651);
            _m_EnumDef_write(out, value.enums[_i1651]);
            {
                var _own1652 = RecordOut();
                _own1652.blank_bodies = true;
                _own1652.blank_locs = true;
                _own1652.pending_as_bytes = true;
                _m_EnumDef_write(_own1652, value.enums[_i1651]);
                base.own("enums", interface_text(_own1652));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1651 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1651]);
            {
                var _own1653 = RecordOut();
                _own1653.blank_bodies = true;
                _own1653.blank_locs = true;
                _own1653.pending_as_bytes = true;
                _m_EnumDef_write(_own1653, value.enums[_i1651]);
                base.own("enums", interface_text(_own1653));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1667 = Array<String>();
    for (var _item1661 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1661);
        _hs1667.append(base.hash_of(scratch));
    }
    var _seq1668 = base.sequence("struct_specs");
    ulong _bj1669 = 0;
    var _news1670 = Array<ulong>();
    for (var _i1671 in 0.._hs1667.count) {
        if (_bj1669 < _seq1668.count and _hs1667[_i1671] == _seq1668[_bj1669]) {
            _bj1669 += 1;
        } else {
            _news1670.append(_i1671);
        }
    }
    for (var _i1671 in 0.._hs1667.count) {
        next.add_hashed("struct_specs", _hs1667[_i1671], _i1671);
    }
    if (_bj1669 == _seq1668.count) {
        out.unsigned(2);
        out.unsigned(_news1670.count);
        for (var _i1671 in _news1670) {
            out.unsigned(_i1671);
            _m_TypeName_write(out, value.struct_specs[_i1671]);
            {
                var _own1672 = RecordOut();
                _own1672.blank_bodies = true;
                _own1672.blank_locs = true;
                _own1672.pending_as_bytes = true;
                _m_TypeName_write(_own1672, value.struct_specs[_i1671]);
                base.own("struct_specs", interface_text(_own1672));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1671 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1671]);
            {
                var _own1673 = RecordOut();
                _own1673.blank_bodies = true;
                _own1673.blank_locs = true;
                _own1673.pending_as_bytes = true;
                _m_TypeName_write(_own1673, value.struct_specs[_i1671]);
                base.own("struct_specs", interface_text(_own1673));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1687 = Array<String>();
    for (var _item1681 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1681);
        _hs1687.append(base.hash_of(scratch));
    }
    var _seq1688 = base.sequence("func_specs");
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
        next.add_hashed("func_specs", _hs1687[_i1691], _i1691);
    }
    if (_bj1689 == _seq1688.count) {
        out.unsigned(2);
        out.unsigned(_news1690.count);
        for (var _i1691 in _news1690) {
            out.unsigned(_i1691);
            _m_TypeName_write(out, value.func_specs[_i1691]);
            {
                var _own1692 = RecordOut();
                _own1692.blank_bodies = true;
                _own1692.blank_locs = true;
                _own1692.pending_as_bytes = true;
                _m_TypeName_write(_own1692, value.func_specs[_i1691]);
                base.own("func_specs", interface_text(_own1692));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1691 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1691]);
            {
                var _own1693 = RecordOut();
                _own1693.blank_bodies = true;
                _own1693.blank_locs = true;
                _own1693.pending_as_bytes = true;
                _m_TypeName_write(_own1693, value.func_specs[_i1691]);
                base.own("func_specs", interface_text(_own1693));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1705 = HashSet<long>();
    ulong _nj1706 = 0;
    out.unsigned(value.type_aliases.count);
    for (var _item1701 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1701);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1705.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1701);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1705.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1717 = Array<String>();
    for (var _item1711 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1711);
        _hs1717.append(base.hash_of(scratch));
    }
    var _seq1718 = base.sequence("withheld");
    ulong _bj1719 = 0;
    var _news1720 = Array<ulong>();
    for (var _i1721 in 0.._hs1717.count) {
        if (_bj1719 < _seq1718.count and _hs1717[_i1721] == _seq1718[_bj1719]) {
            _bj1719 += 1;
        } else {
            _news1720.append(_i1721);
        }
    }
    for (var _i1721 in 0.._hs1717.count) {
        next.add_hashed("withheld", _hs1717[_i1721], _i1721);
    }
    if (_bj1719 == _seq1718.count) {
        out.unsigned(2);
        out.unsigned(_news1720.count);
        for (var _i1721 in _news1720) {
            out.unsigned(_i1721);
            _m_Withheld_write(out, value.withheld[_i1721]);
            {
                var _own1722 = RecordOut();
                _own1722.blank_bodies = true;
                _own1722.blank_locs = true;
                _own1722.pending_as_bytes = true;
                _m_Withheld_write(_own1722, value.withheld[_i1721]);
                base.own("withheld", interface_text(_own1722));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1721 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1721]);
            {
                var _own1723 = RecordOut();
                _own1723.blank_bodies = true;
                _own1723.blank_locs = true;
                _own1723.pending_as_bytes = true;
                _m_Withheld_write(_own1723, value.withheld[_i1721]);
                base.own("withheld", interface_text(_own1723));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1737 = Array<String>();
    for (var _item1731 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1731);
        _hs1737.append(base.hash_of(scratch));
    }
    var _seq1738 = base.sequence("properties");
    ulong _bj1739 = 0;
    var _news1740 = Array<ulong>();
    for (var _i1741 in 0.._hs1737.count) {
        if (_bj1739 < _seq1738.count and _hs1737[_i1741] == _seq1738[_bj1739]) {
            _bj1739 += 1;
        } else {
            _news1740.append(_i1741);
        }
    }
    for (var _i1741 in 0.._hs1737.count) {
        next.add_hashed("properties", _hs1737[_i1741], _i1741);
    }
    if (_bj1739 == _seq1738.count) {
        out.unsigned(2);
        out.unsigned(_news1740.count);
        for (var _i1741 in _news1740) {
            out.unsigned(_i1741);
            _m_PropertyDef_write(out, value.properties[_i1741]);
            {
                var _own1742 = RecordOut();
                _own1742.blank_bodies = true;
                _own1742.blank_locs = true;
                _own1742.pending_as_bytes = true;
                _m_PropertyDef_write(_own1742, value.properties[_i1741]);
                base.own("properties", interface_text(_own1742));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1741 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1741]);
            {
                var _own1743 = RecordOut();
                _own1743.blank_bodies = true;
                _own1743.blank_locs = true;
                _own1743.pending_as_bytes = true;
                _m_PropertyDef_write(_own1743, value.properties[_i1741]);
                base.own("properties", interface_text(_own1743));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1757 = Array<String>();
    for (var _item1751 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1751);
        _hs1757.append(base.hash_of(scratch));
    }
    var _seq1758 = base.sequence("type_uses");
    ulong _bj1759 = 0;
    var _news1760 = Array<ulong>();
    for (var _i1761 in 0.._hs1757.count) {
        if (_bj1759 < _seq1758.count and _hs1757[_i1761] == _seq1758[_bj1759]) {
            _bj1759 += 1;
        } else {
            _news1760.append(_i1761);
        }
    }
    for (var _i1761 in 0.._hs1757.count) {
        next.add_hashed("type_uses", _hs1757[_i1761], _i1761);
    }
    if (_bj1759 == _seq1758.count) {
        out.unsigned(2);
        out.unsigned(_news1760.count);
        for (var _i1761 in _news1760) {
            out.unsigned(_i1761);
            _m_TypeUse_write(out, value.type_uses[_i1761]);
            {
                var _own1762 = RecordOut();
                _own1762.blank_bodies = true;
                _own1762.blank_locs = true;
                _own1762.pending_as_bytes = true;
                _m_TypeUse_write(_own1762, value.type_uses[_i1761]);
                base.own("type_uses", interface_text(_own1762));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1761 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1761]);
            {
                var _own1763 = RecordOut();
                _own1763.blank_bodies = true;
                _own1763.blank_locs = true;
                _own1763.pending_as_bytes = true;
                _m_TypeUse_write(_own1763, value.type_uses[_i1761]);
                base.own("type_uses", interface_text(_own1763));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1777 = Array<String>();
    for (var _item1771 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1771);
        _hs1777.append(base.hash_of(scratch));
    }
    var _seq1778 = base.sequence("use_contexts");
    ulong _bj1779 = 0;
    var _news1780 = Array<ulong>();
    for (var _i1781 in 0.._hs1777.count) {
        if (_bj1779 < _seq1778.count and _hs1777[_i1781] == _seq1778[_bj1779]) {
            _bj1779 += 1;
        } else {
            _news1780.append(_i1781);
        }
    }
    for (var _i1781 in 0.._hs1777.count) {
        next.add_hashed("use_contexts", _hs1777[_i1781], _i1781);
    }
    if (_bj1779 == _seq1778.count) {
        out.unsigned(2);
        out.unsigned(_news1780.count);
        for (var _i1781 in _news1780) {
            out.unsigned(_i1781);
            _m_UseContext_write(out, value.use_contexts[_i1781]);
            {
                var _own1782 = RecordOut();
                _own1782.blank_bodies = true;
                _own1782.blank_locs = true;
                _own1782.pending_as_bytes = true;
                _m_UseContext_write(_own1782, value.use_contexts[_i1781]);
                base.own("use_contexts", interface_text(_own1782));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1781 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1781]);
            {
                var _own1783 = RecordOut();
                _own1783.blank_bodies = true;
                _own1783.blank_locs = true;
                _own1783.pending_as_bytes = true;
                _m_UseContext_write(_own1783, value.use_contexts[_i1781]);
                base.own("use_contexts", interface_text(_own1783));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1793 = base.size("literal_args");
    var _scratch1792 = base.scratch();
    if (value.literal_args.count >= _n1793) {
        for (var _i1794 in 0.._n1793) {
            var (_t1795, _t1796, _t1797) = value.literal_args[_i1794];
            _scratch1792.loc(_t1795);
            _scratch1792.unsigned(_t1796);
            _scratch1792.loc(_t1797);
        }
    }
    if (value.literal_args.count >= _n1793 and base.same_list("literal_args", _scratch1792)) {
        out.unsigned(1);
        out.unsigned(_n1793);
        out.unsigned(value.literal_args.count - _n1793);
        for (var _i1794 in _n1793..value.literal_args.count) {
            var (_t1798, _t1799, _t1800) = value.literal_args[_i1794];
            out.loc(_t1798);
            out.unsigned(_t1799);
            out.loc(_t1800);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1801 in value.literal_args) {
            var (_t1802, _t1803, _t1804) = _item1801;
            out.loc(_t1802);
            out.unsigned(_t1803);
            out.loc(_t1804);
        }
        base.count("literal_args whole", 0);
    }
    var _xscratch1817 = next.scratch();
    for (var _xitem1818 in value.literal_args) {
        var (_t1819, _t1820, _t1821) = _xitem1818;
        _xscratch1817.loc(_t1819);
        _xscratch1817.unsigned(_t1820);
        _xscratch1817.loc(_t1821);
    }
    next.keep_list("literal_args", value.literal_args.count, _xscratch1817);
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1828 = Array<String>();
    for (var _item1822 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1822);
        _hs1828.append(base.hash_of(scratch));
    }
    var _seq1829 = base.sequence("constrained_aliases");
    ulong _bj1830 = 0;
    var _news1831 = Array<ulong>();
    for (var _i1832 in 0.._hs1828.count) {
        if (_bj1830 < _seq1829.count and _hs1828[_i1832] == _seq1829[_bj1830]) {
            _bj1830 += 1;
        } else {
            _news1831.append(_i1832);
        }
    }
    for (var _i1832 in 0.._hs1828.count) {
        next.add_hashed("constrained_aliases", _hs1828[_i1832], _i1832);
    }
    if (_bj1830 == _seq1829.count) {
        out.unsigned(2);
        out.unsigned(_news1831.count);
        for (var _i1832 in _news1831) {
            out.unsigned(_i1832);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1832]);
            {
                var _own1833 = RecordOut();
                _own1833.blank_bodies = true;
                _own1833.blank_locs = true;
                _own1833.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1833, value.constrained_aliases[_i1832]);
                base.own("constrained_aliases", interface_text(_own1833));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1832 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1832]);
            {
                var _own1834 = RecordOut();
                _own1834.blank_bodies = true;
                _own1834.blank_locs = true;
                _own1834.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1834, value.constrained_aliases[_i1832]);
                base.own("constrained_aliases", interface_text(_own1834));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1848 = Array<String>();
    for (var _item1842 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1842);
        _hs1848.append(base.hash_of(scratch));
    }
    var _seq1849 = base.sequence("trait_types");
    ulong _bj1850 = 0;
    var _news1851 = Array<ulong>();
    for (var _i1852 in 0.._hs1848.count) {
        if (_bj1850 < _seq1849.count and _hs1848[_i1852] == _seq1849[_bj1850]) {
            _bj1850 += 1;
        } else {
            _news1851.append(_i1852);
        }
    }
    for (var _i1852 in 0.._hs1848.count) {
        next.add_hashed("trait_types", _hs1848[_i1852], _i1852);
    }
    if (_bj1850 == _seq1849.count) {
        out.unsigned(2);
        out.unsigned(_news1851.count);
        for (var _i1852 in _news1851) {
            out.unsigned(_i1852);
            _m_TraitType_write(out, value.trait_types[_i1852]);
            {
                var _own1853 = RecordOut();
                _own1853.blank_bodies = true;
                _own1853.blank_locs = true;
                _own1853.pending_as_bytes = true;
                _m_TraitType_write(_own1853, value.trait_types[_i1852]);
                base.own("trait_types", interface_text(_own1853));
            }
        }
        base.count("trait_types" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("trait_types" + " whole", 0);
        out.unsigned(value.trait_types.count);
        for (var _i1852 in 0..value.trait_types.count) {
            _m_TraitType_write(out, value.trait_types[_i1852]);
            {
                var _own1854 = RecordOut();
                _own1854.blank_bodies = true;
                _own1854.blank_locs = true;
                _own1854.pending_as_bytes = true;
                _m_TraitType_write(_own1854, value.trait_types[_i1852]);
                base.own("trait_types", interface_text(_own1854));
            }
        }
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    out.unsigned(value.conversions.count);
    for (var _item1862 in value.conversions) {
        _m_Conversion_write(out, _item1862);
    }
    for (var _conv1863 in value.conversions) {
        var _own1864 = RecordOut();
        _own1864.blank_locs = true;
        _m_Conversion_write(_own1864, _conv1863);
        var _h = interface_text(_own1864);
        if (base.find_hashed("conversions", _h) < 0) {
            base.own("conversions", _h);
        }
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1872 = 0;
    var _news1873 = Map<String, Array<String>>();
    for (var (_key1869, _) in value.overload_sets) {
        var _kscratch1870 = base.scratch();
        _kscratch1870.text(_key1869);
        var _vscratch1871 = base.scratch();
        _vscratch1871.unsigned(value.overload_sets[_key1869].count);
        for (var _item1874 in value.overload_sets[_key1869]) {
            _vscratch1871.text(_item1874);
        }
        var _had = base.entry("overload_sets", _kscratch1870, _vscratch1871);
        if (_had >= 0) {
            _kept1872 += 1;
        }
        if (_had != 1) {
            _news1873[_key1869] = value.overload_sets[_key1869];
        }
    }
    if (_kept1872 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1876 = Array<(u8[], u8[], String)>();
        for (var (_key1875, _) in _news1873) {
            var _scratch1877 = out.scratch();
            _scratch1877.text(_key1875);
            var _vscratch1879 = out.scratch();
            _vscratch1879.unsigned(_news1873[_key1875].count);
            for (var _item1880 in _news1873[_key1875]) {
                _vscratch1879.text(_item1880);
            }
            _keys1876.append((_scratch1877.finish(), _vscratch1879.finish(), _key1875));
        }
        _keys1876.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1876.count);
        for (var (_bytes1878, _, _key1875) in _keys1876) {
            out.text(_key1875);
            out.unsigned(_news1873[_key1875].count);
            for (var _item1881 in _news1873[_key1875]) {
                out.text(_item1881);
            }
        }
        for (var (_okey1882, _) in _news1873) {
            var _own1883 = RecordOut();
            _own1883.blank_bodies = true;
            _own1883.blank_locs = true;
            _own1883.pending_as_bytes = true;
            _own1883.text(_okey1882);
            _own1883.unsigned(_news1873[_okey1882].count);
            for (var _item1884 in _news1873[_okey1882]) {
                _own1883.text(_item1884);
            }
            base.own("overload_sets", interface_text(_own1883));
        }
    } else {
        out.unsigned(0);
        var _keys1886 = Array<(u8[], u8[], String)>();
        for (var (_key1885, _) in value.overload_sets) {
            var _scratch1887 = out.scratch();
            _scratch1887.text(_key1885);
            var _vscratch1889 = out.scratch();
            _vscratch1889.unsigned(value.overload_sets[_key1885].count);
            for (var _item1890 in value.overload_sets[_key1885]) {
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
        out.unsigned(_keys1886.count);
        for (var (_bytes1888, _, _key1885) in _keys1886) {
            out.text(_key1885);
            out.unsigned(value.overload_sets[_key1885].count);
            for (var _item1891 in value.overload_sets[_key1885]) {
                out.text(_item1891);
            }
        }
        for (var (_okey1892, _) in value.overload_sets) {
            var _own1893 = RecordOut();
            _own1893.blank_bodies = true;
            _own1893.blank_locs = true;
            _own1893.pending_as_bytes = true;
            _own1893.text(_okey1892);
            _own1893.unsigned(value.overload_sets[_okey1892].count);
            for (var _item1894 in value.overload_sets[_okey1892]) {
                _own1893.text(_item1894);
            }
            base.own("overload_sets", interface_text(_own1893));
        }
        base.count("overload_sets whole", 0);
    }
    for (var (_key1869, _) in value.overload_sets) {
        var _kscratch1870 = next.scratch();
        _kscratch1870.text(_key1869);
        var _vscratch1871 = next.scratch();
        _vscratch1871.unsigned(value.overload_sets[_key1869].count);
        for (var _item1908 in value.overload_sets[_key1869]) {
            _vscratch1871.text(_item1908);
        }
        next.keep_entry("overload_sets", _kscratch1870, _vscratch1871);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1912 = 0;
    var _news1913 = Map<String, Array<Array<String>>>();
    for (var (_key1909, _) in value.overload_unions) {
        var _kscratch1910 = base.scratch();
        _kscratch1910.text(_key1909);
        var _vscratch1911 = base.scratch();
        _vscratch1911.unsigned(value.overload_unions[_key1909].count);
        for (var _item1914 in value.overload_unions[_key1909]) {
            _vscratch1911.unsigned(_item1914.count);
            for (var _item1915 in _item1914) {
                _vscratch1911.text(_item1915);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1910, _vscratch1911);
        if (_had >= 0) {
            _kept1912 += 1;
        }
        if (_had != 1) {
            _news1913[_key1909] = value.overload_unions[_key1909];
        }
    }
    if (_kept1912 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1917 = Array<(u8[], u8[], String)>();
        for (var (_key1916, _) in _news1913) {
            var _scratch1918 = out.scratch();
            _scratch1918.text(_key1916);
            var _vscratch1920 = out.scratch();
            _vscratch1920.unsigned(_news1913[_key1916].count);
            for (var _item1921 in _news1913[_key1916]) {
                _vscratch1920.unsigned(_item1921.count);
                for (var _item1922 in _item1921) {
                    _vscratch1920.text(_item1922);
                }
            }
            _keys1917.append((_scratch1918.finish(), _vscratch1920.finish(), _key1916));
        }
        _keys1917.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1917.count);
        for (var (_bytes1919, _, _key1916) in _keys1917) {
            out.text(_key1916);
            out.unsigned(_news1913[_key1916].count);
            for (var _item1923 in _news1913[_key1916]) {
                out.unsigned(_item1923.count);
                for (var _item1924 in _item1923) {
                    out.text(_item1924);
                }
            }
        }
        for (var (_okey1925, _) in _news1913) {
            var _own1926 = RecordOut();
            _own1926.blank_bodies = true;
            _own1926.blank_locs = true;
            _own1926.pending_as_bytes = true;
            _own1926.text(_okey1925);
            _own1926.unsigned(_news1913[_okey1925].count);
            for (var _item1927 in _news1913[_okey1925]) {
                _own1926.unsigned(_item1927.count);
                for (var _item1928 in _item1927) {
                    _own1926.text(_item1928);
                }
            }
            base.own("overload_unions", interface_text(_own1926));
        }
    } else {
        out.unsigned(0);
        var _keys1930 = Array<(u8[], u8[], String)>();
        for (var (_key1929, _) in value.overload_unions) {
            var _scratch1931 = out.scratch();
            _scratch1931.text(_key1929);
            var _vscratch1933 = out.scratch();
            _vscratch1933.unsigned(value.overload_unions[_key1929].count);
            for (var _item1934 in value.overload_unions[_key1929]) {
                _vscratch1933.unsigned(_item1934.count);
                for (var _item1935 in _item1934) {
                    _vscratch1933.text(_item1935);
                }
            }
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
            out.text(_key1929);
            out.unsigned(value.overload_unions[_key1929].count);
            for (var _item1936 in value.overload_unions[_key1929]) {
                out.unsigned(_item1936.count);
                for (var _item1937 in _item1936) {
                    out.text(_item1937);
                }
            }
        }
        for (var (_okey1938, _) in value.overload_unions) {
            var _own1939 = RecordOut();
            _own1939.blank_bodies = true;
            _own1939.blank_locs = true;
            _own1939.pending_as_bytes = true;
            _own1939.text(_okey1938);
            _own1939.unsigned(value.overload_unions[_okey1938].count);
            for (var _item1940 in value.overload_unions[_okey1938]) {
                _own1939.unsigned(_item1940.count);
                for (var _item1941 in _item1940) {
                    _own1939.text(_item1941);
                }
            }
            base.own("overload_unions", interface_text(_own1939));
        }
        base.count("overload_unions whole", 0);
    }
    for (var (_key1909, _) in value.overload_unions) {
        var _kscratch1910 = next.scratch();
        _kscratch1910.text(_key1909);
        var _vscratch1911 = next.scratch();
        _vscratch1911.unsigned(value.overload_unions[_key1909].count);
        for (var _item1959 in value.overload_unions[_key1909]) {
            _vscratch1911.unsigned(_item1959.count);
            for (var _item1960 in _item1959) {
                _vscratch1911.text(_item1960);
            }
        }
        next.keep_entry("overload_unions", _kscratch1910, _vscratch1911);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1964 = 0;
    var _news1965 = Map<String, Map<String, Array<String>>>();
    for (var (_key1961, _) in value.method_overload_sets) {
        var _kscratch1962 = base.scratch();
        _kscratch1962.text(_key1961);
        var _vscratch1963 = base.scratch();
        var _keys1967 = Array<(u8[], u8[], String)>();
        for (var (_key1966, _) in value.method_overload_sets[_key1961]) {
            var _scratch1968 = _vscratch1963.scratch();
            _scratch1968.text(_key1966);
            var _vscratch1970 = _vscratch1963.scratch();
            _vscratch1970.unsigned(value.method_overload_sets[_key1961][_key1966].count);
            for (var _item1971 in value.method_overload_sets[_key1961][_key1966]) {
                _vscratch1970.text(_item1971);
            }
            _keys1967.append((_scratch1968.finish(), _vscratch1970.finish(), _key1966));
        }
        _keys1967.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1963.unsigned(_keys1967.count);
        for (var (_bytes1969, _, _key1966) in _keys1967) {
            _vscratch1963.text(_key1966);
            _vscratch1963.unsigned(value.method_overload_sets[_key1961][_key1966].count);
            for (var _item1972 in value.method_overload_sets[_key1961][_key1966]) {
                _vscratch1963.text(_item1972);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1962, _vscratch1963);
        if (_had >= 0) {
            _kept1964 += 1;
        }
        if (_had != 1) {
            _news1965[_key1961] = value.method_overload_sets[_key1961];
        }
    }
    if (_kept1964 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1974 = Array<(u8[], u8[], String)>();
        for (var (_key1973, _) in _news1965) {
            var _scratch1975 = out.scratch();
            _scratch1975.text(_key1973);
            var _vscratch1977 = out.scratch();
            var _keys1979 = Array<(u8[], u8[], String)>();
            for (var (_key1978, _) in _news1965[_key1973]) {
                var _scratch1980 = _vscratch1977.scratch();
                _scratch1980.text(_key1978);
                var _vscratch1982 = _vscratch1977.scratch();
                _vscratch1982.unsigned(_news1965[_key1973][_key1978].count);
                for (var _item1983 in _news1965[_key1973][_key1978]) {
                    _vscratch1982.text(_item1983);
                }
                _keys1979.append((_scratch1980.finish(), _vscratch1982.finish(), _key1978));
            }
            _keys1979.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1977.unsigned(_keys1979.count);
            for (var (_bytes1981, _, _key1978) in _keys1979) {
                _vscratch1977.text(_key1978);
                _vscratch1977.unsigned(_news1965[_key1973][_key1978].count);
                for (var _item1984 in _news1965[_key1973][_key1978]) {
                    _vscratch1977.text(_item1984);
                }
            }
            _keys1974.append((_scratch1975.finish(), _vscratch1977.finish(), _key1973));
        }
        _keys1974.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1974.count);
        for (var (_bytes1976, _, _key1973) in _keys1974) {
            out.text(_key1973);
            var _keys1986 = Array<(u8[], u8[], String)>();
            for (var (_key1985, _) in _news1965[_key1973]) {
                var _scratch1987 = out.scratch();
                _scratch1987.text(_key1985);
                var _vscratch1989 = out.scratch();
                _vscratch1989.unsigned(_news1965[_key1973][_key1985].count);
                for (var _item1990 in _news1965[_key1973][_key1985]) {
                    _vscratch1989.text(_item1990);
                }
                _keys1986.append((_scratch1987.finish(), _vscratch1989.finish(), _key1985));
            }
            _keys1986.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1986.count);
            for (var (_bytes1988, _, _key1985) in _keys1986) {
                out.text(_key1985);
                out.unsigned(_news1965[_key1973][_key1985].count);
                for (var _item1991 in _news1965[_key1973][_key1985]) {
                    out.text(_item1991);
                }
            }
        }
        for (var (_okey1992, _) in _news1965) {
            var _own1993 = RecordOut();
            _own1993.blank_bodies = true;
            _own1993.blank_locs = true;
            _own1993.pending_as_bytes = true;
            _own1993.text(_okey1992);
            var _keys1995 = Array<(u8[], u8[], String)>();
            for (var (_key1994, _) in _news1965[_okey1992]) {
                var _scratch1996 = _own1993.scratch();
                _scratch1996.text(_key1994);
                var _vscratch1998 = _own1993.scratch();
                _vscratch1998.unsigned(_news1965[_okey1992][_key1994].count);
                for (var _item1999 in _news1965[_okey1992][_key1994]) {
                    _vscratch1998.text(_item1999);
                }
                _keys1995.append((_scratch1996.finish(), _vscratch1998.finish(), _key1994));
            }
            _keys1995.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own1993.unsigned(_keys1995.count);
            for (var (_bytes1997, _, _key1994) in _keys1995) {
                _own1993.text(_key1994);
                _own1993.unsigned(_news1965[_okey1992][_key1994].count);
                for (var _item2000 in _news1965[_okey1992][_key1994]) {
                    _own1993.text(_item2000);
                }
            }
            base.own("method_overload_sets", interface_text(_own1993));
        }
    } else {
        out.unsigned(0);
        var _keys2002 = Array<(u8[], u8[], String)>();
        for (var (_key2001, _) in value.method_overload_sets) {
            var _scratch2003 = out.scratch();
            _scratch2003.text(_key2001);
            var _vscratch2005 = out.scratch();
            var _keys2007 = Array<(u8[], u8[], String)>();
            for (var (_key2006, _) in value.method_overload_sets[_key2001]) {
                var _scratch2008 = _vscratch2005.scratch();
                _scratch2008.text(_key2006);
                var _vscratch2010 = _vscratch2005.scratch();
                _vscratch2010.unsigned(value.method_overload_sets[_key2001][_key2006].count);
                for (var _item2011 in value.method_overload_sets[_key2001][_key2006]) {
                    _vscratch2010.text(_item2011);
                }
                _keys2007.append((_scratch2008.finish(), _vscratch2010.finish(), _key2006));
            }
            _keys2007.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2005.unsigned(_keys2007.count);
            for (var (_bytes2009, _, _key2006) in _keys2007) {
                _vscratch2005.text(_key2006);
                _vscratch2005.unsigned(value.method_overload_sets[_key2001][_key2006].count);
                for (var _item2012 in value.method_overload_sets[_key2001][_key2006]) {
                    _vscratch2005.text(_item2012);
                }
            }
            _keys2002.append((_scratch2003.finish(), _vscratch2005.finish(), _key2001));
        }
        _keys2002.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2002.count);
        for (var (_bytes2004, _, _key2001) in _keys2002) {
            out.text(_key2001);
            var _keys2014 = Array<(u8[], u8[], String)>();
            for (var (_key2013, _) in value.method_overload_sets[_key2001]) {
                var _scratch2015 = out.scratch();
                _scratch2015.text(_key2013);
                var _vscratch2017 = out.scratch();
                _vscratch2017.unsigned(value.method_overload_sets[_key2001][_key2013].count);
                for (var _item2018 in value.method_overload_sets[_key2001][_key2013]) {
                    _vscratch2017.text(_item2018);
                }
                _keys2014.append((_scratch2015.finish(), _vscratch2017.finish(), _key2013));
            }
            _keys2014.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2014.count);
            for (var (_bytes2016, _, _key2013) in _keys2014) {
                out.text(_key2013);
                out.unsigned(value.method_overload_sets[_key2001][_key2013].count);
                for (var _item2019 in value.method_overload_sets[_key2001][_key2013]) {
                    out.text(_item2019);
                }
            }
        }
        for (var (_okey2020, _) in value.method_overload_sets) {
            var _own2021 = RecordOut();
            _own2021.blank_bodies = true;
            _own2021.blank_locs = true;
            _own2021.pending_as_bytes = true;
            _own2021.text(_okey2020);
            var _keys2023 = Array<(u8[], u8[], String)>();
            for (var (_key2022, _) in value.method_overload_sets[_okey2020]) {
                var _scratch2024 = _own2021.scratch();
                _scratch2024.text(_key2022);
                var _vscratch2026 = _own2021.scratch();
                _vscratch2026.unsigned(value.method_overload_sets[_okey2020][_key2022].count);
                for (var _item2027 in value.method_overload_sets[_okey2020][_key2022]) {
                    _vscratch2026.text(_item2027);
                }
                _keys2023.append((_scratch2024.finish(), _vscratch2026.finish(), _key2022));
            }
            _keys2023.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own2021.unsigned(_keys2023.count);
            for (var (_bytes2025, _, _key2022) in _keys2023) {
                _own2021.text(_key2022);
                _own2021.unsigned(value.method_overload_sets[_okey2020][_key2022].count);
                for (var _item2028 in value.method_overload_sets[_okey2020][_key2022]) {
                    _own2021.text(_item2028);
                }
            }
            base.own("method_overload_sets", interface_text(_own2021));
        }
        base.count("method_overload_sets whole", 0);
    }
    for (var (_key1961, _) in value.method_overload_sets) {
        var _kscratch1962 = next.scratch();
        _kscratch1962.text(_key1961);
        var _vscratch1963 = next.scratch();
        var _keys2049 = Array<(u8[], u8[], String)>();
        for (var (_key2048, _) in value.method_overload_sets[_key1961]) {
            var _scratch2050 = _vscratch1963.scratch();
            _scratch2050.text(_key2048);
            var _vscratch2052 = _vscratch1963.scratch();
            _vscratch2052.unsigned(value.method_overload_sets[_key1961][_key2048].count);
            for (var _item2053 in value.method_overload_sets[_key1961][_key2048]) {
                _vscratch2052.text(_item2053);
            }
            _keys2049.append((_scratch2050.finish(), _vscratch2052.finish(), _key2048));
        }
        _keys2049.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1963.unsigned(_keys2049.count);
        for (var (_bytes2051, _, _key2048) in _keys2049) {
            _vscratch1963.text(_key2048);
            _vscratch1963.unsigned(value.method_overload_sets[_key1961][_key2048].count);
            for (var _item2054 in value.method_overload_sets[_key1961][_key2048]) {
                _vscratch1963.text(_item2054);
            }
        }
        next.keep_entry("method_overload_sets", _kscratch1962, _vscratch1963);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2059 = 0;
    var _news2060 = HashSet<Loc>();
    for (var _key2056 in value.private_functions) {
        var _kscratch2057 = base.scratch();
        _kscratch2057.loc(_key2056);
        var _vscratch2058 = base.scratch();
        var _had = base.entry("private_functions", _kscratch2057, _vscratch2058);
        if (_had >= 0) {
            _kept2059 += 1;
        }
        if (_had != 1) {
            _news2060.insert(_key2056);
        }
    }
    if (_kept2059 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys2062 = Array<(u8[], u8[], Loc)>();
        for (var _key2061 in _news2060) {
            var _scratch2063 = out.scratch();
            _scratch2063.loc(_key2061);
            var _vscratch2065 = out.scratch();
            _keys2062.append((_scratch2063.finish(), _vscratch2065.finish(), _key2061));
        }
        _keys2062.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2062.count);
        for (var (_bytes2064, _, _key2061) in _keys2062) {
            out.loc(_key2061);
        }
        for (var _okey2066 in _news2060) {
            var _own2067 = RecordOut();
            _own2067.blank_bodies = true;
            _own2067.blank_locs = true;
            _own2067.pending_as_bytes = true;
            _own2067.loc(_okey2066);
            base.own("private_functions", interface_text(_own2067));
        }
    } else {
        out.unsigned(0);
        var _keys2069 = Array<(u8[], u8[], Loc)>();
        for (var _key2068 in value.private_functions) {
            var _scratch2070 = out.scratch();
            _scratch2070.loc(_key2068);
            var _vscratch2072 = out.scratch();
            _keys2069.append((_scratch2070.finish(), _vscratch2072.finish(), _key2068));
        }
        _keys2069.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2069.count);
        for (var (_bytes2071, _, _key2068) in _keys2069) {
            out.loc(_key2068);
        }
        for (var _okey2073 in value.private_functions) {
            var _own2074 = RecordOut();
            _own2074.blank_bodies = true;
            _own2074.blank_locs = true;
            _own2074.pending_as_bytes = true;
            _own2074.loc(_okey2073);
            base.own("private_functions", interface_text(_own2074));
        }
        base.count("private_functions whole", 0);
    }
    for (var _key2056 in value.private_functions) {
        var _kscratch2057 = next.scratch();
        _kscratch2057.loc(_key2056);
        var _vscratch2058 = next.scratch();
        next.keep_entry("private_functions", _kscratch2057, _vscratch2058);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2085 = 0;
    var _news2086 = HashSet<Loc>();
    for (var _key2082 in value.file_private_functions) {
        var _kscratch2083 = base.scratch();
        _kscratch2083.loc(_key2082);
        var _vscratch2084 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch2083, _vscratch2084);
        if (_had >= 0) {
            _kept2085 += 1;
        }
        if (_had != 1) {
            _news2086.insert(_key2082);
        }
    }
    if (_kept2085 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys2088 = Array<(u8[], u8[], Loc)>();
        for (var _key2087 in _news2086) {
            var _scratch2089 = out.scratch();
            _scratch2089.loc(_key2087);
            var _vscratch2091 = out.scratch();
            _keys2088.append((_scratch2089.finish(), _vscratch2091.finish(), _key2087));
        }
        _keys2088.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2088.count);
        for (var (_bytes2090, _, _key2087) in _keys2088) {
            out.loc(_key2087);
        }
        for (var _okey2092 in _news2086) {
            var _own2093 = RecordOut();
            _own2093.blank_bodies = true;
            _own2093.blank_locs = true;
            _own2093.pending_as_bytes = true;
            _own2093.loc(_okey2092);
            base.own("file_private_functions", interface_text(_own2093));
        }
    } else {
        out.unsigned(0);
        var _keys2095 = Array<(u8[], u8[], Loc)>();
        for (var _key2094 in value.file_private_functions) {
            var _scratch2096 = out.scratch();
            _scratch2096.loc(_key2094);
            var _vscratch2098 = out.scratch();
            _keys2095.append((_scratch2096.finish(), _vscratch2098.finish(), _key2094));
        }
        _keys2095.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2095.count);
        for (var (_bytes2097, _, _key2094) in _keys2095) {
            out.loc(_key2094);
        }
        for (var _okey2099 in value.file_private_functions) {
            var _own2100 = RecordOut();
            _own2100.blank_bodies = true;
            _own2100.blank_locs = true;
            _own2100.pending_as_bytes = true;
            _own2100.loc(_okey2099);
            base.own("file_private_functions", interface_text(_own2100));
        }
        base.count("file_private_functions whole", 0);
    }
    for (var _key2082 in value.file_private_functions) {
        var _kscratch2083 = next.scratch();
        _kscratch2083.loc(_key2082);
        var _vscratch2084 = next.scratch();
        next.keep_entry("file_private_functions", _kscratch2083, _vscratch2084);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n2110 = base.size("call_targets");
    var _scratch2109 = base.scratch();
    if (value.call_targets.count >= _n2110) {
        for (var _i2111 in 0.._n2110) {
            var (_t2112, _t2113) = value.call_targets[_i2111];
            _scratch2109.loc(_t2112);
            _scratch2109.text(_t2113);
        }
    }
    if (value.call_targets.count >= _n2110 and base.same_list("call_targets", _scratch2109)) {
        out.unsigned(1);
        out.unsigned(_n2110);
        out.unsigned(value.call_targets.count - _n2110);
        for (var _i2111 in _n2110..value.call_targets.count) {
            var (_t2114, _t2115) = value.call_targets[_i2111];
            out.loc(_t2114);
            out.text(_t2115);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item2116 in value.call_targets) {
            var (_t2117, _t2118) = _item2116;
            out.loc(_t2117);
            out.text(_t2118);
        }
        base.count("call_targets whole", 0);
    }
    var _xscratch2129 = next.scratch();
    for (var _xitem2130 in value.call_targets) {
        var (_t2131, _t2132) = _xitem2130;
        _xscratch2129.loc(_t2131);
        _xscratch2129.text(_t2132);
    }
    next.keep_list("call_targets", value.call_targets.count, _xscratch2129);
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2135 = 0;
    var _news2136 = Array<(Loc, String)>();
    for (var _item2133 in value.argument_names) {
        var _escratch2134 = base.scratch();
        var (_t2137, _t2138) = _item2133;
        _escratch2134.loc(_t2137);
        _escratch2134.text(_t2138);
        if (base.entry("argument_names", _escratch2134, base.scratch()) >= 0) {
            _kept2135 += 1;
        } else {
            _news2136.append(_item2133);
        }
    }
    if (_kept2135 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2136.count);
        for (var _item2139 in _news2136) {
            var (_t2140, _t2141) = _item2139;
            out.loc(_t2140);
            out.text(_t2141);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2142 in value.argument_names) {
            var (_t2143, _t2144) = _item2142;
            out.loc(_t2143);
            out.text(_t2144);
        }
        base.count("argument_names whole", 0);
    }
    for (var _item2133 in value.argument_names) {
        var _escratch2134 = next.scratch();
        var (_t2155, _t2156) = _item2133;
        _escratch2134.loc(_t2155);
        _escratch2134.text(_t2156);
        next.keep_entry("argument_names", _escratch2134, next.scratch());
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2159 = base.size("namespaces");
    var _scratch2158 = base.scratch();
    if (value.namespaces.count >= _n2159) {
        for (var _i2160 in 0.._n2159) {
            _scratch2158.text(value.namespaces[_i2160]);
        }
    }
    if (value.namespaces.count >= _n2159 and base.same_list("namespaces", _scratch2158)) {
        out.unsigned(1);
        out.unsigned(_n2159);
        out.unsigned(value.namespaces.count - _n2159);
        for (var _i2160 in _n2159..value.namespaces.count) {
            out.text(value.namespaces[_i2160]);
            {
                var _own2161 = RecordOut();
                _own2161.blank_bodies = true;
                _own2161.blank_locs = true;
                _own2161.pending_as_bytes = true;
                _own2161.text(value.namespaces[_i2160]);
                base.own("namespaces", interface_text(_own2161));
            }
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2162 in value.namespaces) {
            out.text(_item2162);
        }
        for (var _i2160 in 0..value.namespaces.count) {
            {
                var _own2163 = RecordOut();
                _own2163.blank_bodies = true;
                _own2163.blank_locs = true;
                _own2163.pending_as_bytes = true;
                _own2163.text(value.namespaces[_i2160]);
                base.own("namespaces", interface_text(_own2163));
            }
        }
        base.count("namespaces whole", 0);
    }
    var _xscratch2170 = next.scratch();
    for (var _xitem2171 in value.namespaces) {
        _xscratch2170.text(_xitem2171);
    }
    next.keep_list("namespaces", value.namespaces.count, _xscratch2170);
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2174 = base.size("cached_files");
    var _scratch2173 = base.scratch();
    if (value.cached_files.count >= _n2174) {
        for (var _i2175 in 0.._n2174) {
            _scratch2173.flag(value.cached_files[_i2175]);
        }
    }
    if (value.cached_files.count >= _n2174 and base.same_list("cached_files", _scratch2173)) {
        out.unsigned(1);
        out.unsigned(_n2174);
        out.unsigned(value.cached_files.count - _n2174);
        for (var _i2175 in _n2174..value.cached_files.count) {
            out.flag(value.cached_files[_i2175]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2176 in value.cached_files) {
            out.flag(_item2176);
        }
        base.count("cached_files whole", 0);
    }
    var _xscratch2183 = next.scratch();
    for (var _xitem2184 in value.cached_files) {
        _xscratch2183.flag(_xitem2184);
    }
    next.keep_list("cached_files", value.cached_files.count, _xscratch2183);
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2188 = 0;
    var _news2189 = HashMap<Loc, String>();
    for (var (_key2185, _) in value.recorded_summaries) {
        var _kscratch2186 = base.scratch();
        _kscratch2186.loc(_key2185);
        var _vscratch2187 = base.scratch();
        _vscratch2187.text(value.recorded_summaries[_key2185]);
        var _had = base.entry("recorded_summaries", _kscratch2186, _vscratch2187);
        if (_had >= 0) {
            _kept2188 += 1;
        }
        if (_had != 1) {
            _news2189[_key2185] = value.recorded_summaries[_key2185];
        }
    }
    if (_kept2188 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2191 = Array<(u8[], u8[], Loc)>();
        for (var (_key2190, _) in _news2189) {
            var _scratch2192 = out.scratch();
            _scratch2192.loc(_key2190);
            var _vscratch2194 = out.scratch();
            _vscratch2194.text(_news2189[_key2190]);
            _keys2191.append((_scratch2192.finish(), _vscratch2194.finish(), _key2190));
        }
        _keys2191.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2191.count);
        for (var (_bytes2193, _, _key2190) in _keys2191) {
            out.loc(_key2190);
            out.text(_news2189[_key2190]);
        }
    } else {
        out.unsigned(0);
        var _keys2196 = Array<(u8[], u8[], Loc)>();
        for (var (_key2195, _) in value.recorded_summaries) {
            var _scratch2197 = out.scratch();
            _scratch2197.loc(_key2195);
            var _vscratch2199 = out.scratch();
            _vscratch2199.text(value.recorded_summaries[_key2195]);
            _keys2196.append((_scratch2197.finish(), _vscratch2199.finish(), _key2195));
        }
        _keys2196.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2196.count);
        for (var (_bytes2198, _, _key2195) in _keys2196) {
            out.loc(_key2195);
            out.text(value.recorded_summaries[_key2195]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2212 = 0;
    var _news2213 = HashSet<Loc>();
    for (var _key2209 in value.stripped) {
        var _kscratch2210 = base.scratch();
        _kscratch2210.loc(_key2209);
        var _vscratch2211 = base.scratch();
        var _had = base.entry("stripped", _kscratch2210, _vscratch2211);
        if (_had >= 0) {
            _kept2212 += 1;
        }
        if (_had != 1) {
            _news2213.insert(_key2209);
        }
    }
    if (_kept2212 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2215 = Array<(u8[], u8[], Loc)>();
        for (var _key2214 in _news2213) {
            var _scratch2216 = out.scratch();
            _scratch2216.loc(_key2214);
            var _vscratch2218 = out.scratch();
            _keys2215.append((_scratch2216.finish(), _vscratch2218.finish(), _key2214));
        }
        _keys2215.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2215.count);
        for (var (_bytes2217, _, _key2214) in _keys2215) {
            out.loc(_key2214);
        }
    } else {
        out.unsigned(0);
        var _keys2220 = Array<(u8[], u8[], Loc)>();
        for (var _key2219 in value.stripped) {
            var _scratch2221 = out.scratch();
            _scratch2221.loc(_key2219);
            var _vscratch2223 = out.scratch();
            _keys2220.append((_scratch2221.finish(), _vscratch2223.finish(), _key2219));
        }
        _keys2220.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2220.count);
        for (var (_bytes2222, _, _key2219) in _keys2220) {
            out.loc(_key2219);
        }
        base.count("stripped whole", 0);
    }
    for (var _key2209 in value.stripped) {
        var _kscratch2210 = next.scratch();
        _kscratch2210.loc(_key2209);
        var _vscratch2211 = next.scratch();
        next.keep_entry("stripped", _kscratch2210, _vscratch2211);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _hs2233 = Array<String>();
    for (var _item2231 in value.templates.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item2231);
        _hs2233.append(base.hash_of(scratch));
    }
    var _seq2234 = base.sequence("t");
    var _seqn2235 = base.sequence("t#");
    ulong _bj2236 = 0;
    var _news2237 = Array<ulong>();
    var _patches2238 = Array<(ulong, ulong)>();
    for (var _i2239 in 0.._hs2233.count) {
        if (_bj2236 < _seq2234.count and _hs2233[_i2239] == _seq2234[_bj2236]) {
            _bj2236 += 1;
        } else if (_bj2236 < _seq2234.count
            and _bj2236 < _seqn2235.count
            and value.templates.structs[_i2239].name == _seqn2235[_bj2236]) {
            _patches2238.append((_i2239, _bj2236));
            _bj2236 += 1;
        } else {
            _news2237.append(_i2239);
        }
    }
    if (_bj2236 == _seq2234.count) {
        out.unsigned(2);
        out.unsigned(_patches2238.count);
        for (var (_i2239, _b) in _patches2238) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2239].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2239], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2240 = RecordOut();
                _own2240.blank_bodies = false;
                _own2240.blank_locs = true;
                _own2240.pending_as_bytes = true;
                _m_StructDef_write(_own2240, value.templates.structs[_i2239]);
                base.own("templates structs", interface_text(_own2240));
            }
        }
        out.unsigned(_news2237.count);
        for (var _i2239 in _news2237) {
            ulong _before = out.values.count;
            out.unsigned(_i2239);
            _m_StructDef_write(out, value.templates.structs[_i2239]);
            base.count("t new", out.values.count - _before);
            {
                var _own2241 = RecordOut();
                _own2241.blank_bodies = false;
                _own2241.blank_locs = true;
                _own2241.pending_as_bytes = true;
                _m_StructDef_write(_own2241, value.templates.structs[_i2239]);
                base.own("templates structs", interface_text(_own2241));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2232 = HashSet<long>();
        out.unsigned(value.templates.structs.count);
        for (var _i2239 in 0..value.templates.structs.count) {
            var _item2231 = value.templates.structs[_i2239];
            var at = base.find_hashed("t", _hs2233[_i2239]);
            var named = base.named("t", _item2231.name);
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2232.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2232.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2231, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2231);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2232.count);
    }
    for (var _i2239 in 0.._hs2233.count) {
        next.add_hashed("t", _hs2233[_i2239], _i2239);
        next.name("t", value.templates.structs[_i2239].name, _i2239);
        _patch_t_index(value.templates.structs[_i2239], next, _i2239);
    }
    var _hs2256 = Array<String>();
    for (var _item2250 in value.templates.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2250);
        _hs2256.append(base.hash_of(scratch));
    }
    var _seq2257 = base.sequence("tf");
    ulong _bj2258 = 0;
    var _news2259 = Array<ulong>();
    var _changed2251 = Array<(ulong, ulong)>();
    var _seqn2252 = base.sequence("tf" + "#");
    for (var _i2260 in 0.._hs2256.count) {
        if (_bj2258 < _seq2257.count and _hs2256[_i2260] == _seq2257[_bj2258]) {
            _bj2258 += 1;
        } else if (_bj2258 < _seqn2252.count and value.templates.functions[_i2260].name == _seqn2252[_bj2258]) {
            _changed2251.append((_i2260, _bj2258));
            _bj2258 += 1;
        } else {
            _news2259.append(_i2260);
        }
    }
    for (var _i2260 in 0.._hs2256.count) {
        next.add_hashed("tf", _hs2256[_i2260], _i2260);
        next.name("tf", value.templates.functions[_i2260].name, _i2260);
    }
    if (_bj2258 == _seq2257.count) {
        out.unsigned(2);
        out.unsigned(_changed2251.count);
        for (var (_i2260, _b) in _changed2251) {
            out.text(value.templates.functions[_i2260].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2260]);
            {
                var _own2261 = RecordOut();
                _own2261.blank_bodies = false;
                _own2261.blank_locs = true;
                _own2261.pending_as_bytes = true;
                _m_FunctionDef_write(_own2261, value.templates.functions[_i2260]);
                base.own("templates functions", interface_text(_own2261));
            }
        }
        base.count("tf" + " changed", _changed2251.count);
        out.unsigned(_news2259.count);
        for (var _i2260 in _news2259) {
            out.unsigned(_i2260);
            _m_FunctionDef_write(out, value.templates.functions[_i2260]);
            {
                var _own2262 = RecordOut();
                _own2262.blank_bodies = false;
                _own2262.blank_locs = true;
                _own2262.pending_as_bytes = true;
                _m_FunctionDef_write(_own2262, value.templates.functions[_i2260]);
                base.own("templates functions", interface_text(_own2262));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2260 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2260]);
            {
                var _own2263 = RecordOut();
                _own2263.blank_bodies = false;
                _own2263.blank_locs = true;
                _own2263.pending_as_bytes = true;
                _m_FunctionDef_write(_own2263, value.templates.functions[_i2260]);
                base.own("templates functions", interface_text(_own2263));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    next.keep_checked(value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2276 = 0;
    var _news2277 = HashMap<String, SpecRequest>();
    for (var (_key2273, _) in value.spec_requests) {
        var _kscratch2274 = base.scratch();
        _kscratch2274.text(_key2273);
        var _vscratch2275 = base.scratch();
        _m_SpecRequest_write(_vscratch2275, value.spec_requests[_key2273]);
        var _had = base.entry("spec_requests", _kscratch2274, _vscratch2275);
        if (_had >= 0) {
            _kept2276 += 1;
        }
        if (_had != 1) {
            _news2277[_key2273] = value.spec_requests[_key2273];
        }
    }
    if (_kept2276 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2279 = Array<(u8[], u8[], String)>();
        for (var (_key2278, _) in _news2277) {
            var _scratch2280 = out.scratch();
            _scratch2280.text(_key2278);
            var _vscratch2282 = out.scratch();
            _m_SpecRequest_write(_vscratch2282, _news2277[_key2278]);
            _keys2279.append((_scratch2280.finish(), _vscratch2282.finish(), _key2278));
        }
        _keys2279.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2279.count);
        for (var (_bytes2281, _, _key2278) in _keys2279) {
            out.text(_key2278);
            _m_SpecRequest_write(out, _news2277[_key2278]);
        }
        for (var (_okey2283, _) in _news2277) {
            var _own2284 = RecordOut();
            _own2284.blank_bodies = true;
            _own2284.blank_locs = true;
            _own2284.pending_as_bytes = true;
            _own2284.text(_okey2283);
            _m_SpecRequest_write(_own2284, _news2277[_okey2283]);
            base.own("spec_requests", interface_text(_own2284));
        }
    } else {
        out.unsigned(0);
        var _keys2286 = Array<(u8[], u8[], String)>();
        for (var (_key2285, _) in value.spec_requests) {
            var _scratch2287 = out.scratch();
            _scratch2287.text(_key2285);
            var _vscratch2289 = out.scratch();
            _m_SpecRequest_write(_vscratch2289, value.spec_requests[_key2285]);
            _keys2286.append((_scratch2287.finish(), _vscratch2289.finish(), _key2285));
        }
        _keys2286.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2286.count);
        for (var (_bytes2288, _, _key2285) in _keys2286) {
            out.text(_key2285);
            _m_SpecRequest_write(out, value.spec_requests[_key2285]);
        }
        for (var (_okey2290, _) in value.spec_requests) {
            var _own2291 = RecordOut();
            _own2291.blank_bodies = true;
            _own2291.blank_locs = true;
            _own2291.pending_as_bytes = true;
            _own2291.text(_okey2290);
            _m_SpecRequest_write(_own2291, value.spec_requests[_okey2290]);
            base.own("spec_requests", interface_text(_own2291));
        }
        base.count("spec_requests whole", 0);
    }
    for (var (_key2273, _) in value.spec_requests) {
        var _kscratch2274 = next.scratch();
        _kscratch2274.text(_key2273);
        var _vscratch2275 = next.scratch();
        _m_SpecRequest_write(_vscratch2275, value.spec_requests[_key2273]);
        next.keep_entry("spec_requests", _kscratch2274, _vscratch2275);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2304 = base.size("summaries_to_record");
    var _scratch2303 = base.scratch();
    if (value.summaries_to_record.count >= _n2304) {
        for (var _i2305 in 0.._n2304) {
            var (_t2306, _t2307) = value.summaries_to_record[_i2305];
            _scratch2303.loc(_t2306);
            _scratch2303.text(_t2307);
        }
    }
    if (value.summaries_to_record.count >= _n2304 and base.same_list("summaries_to_record", _scratch2303)) {
        out.unsigned(1);
        out.unsigned(_n2304);
        out.unsigned(value.summaries_to_record.count - _n2304);
        for (var _i2305 in _n2304..value.summaries_to_record.count) {
            var (_t2308, _t2309) = value.summaries_to_record[_i2305];
            out.loc(_t2308);
            out.text(_t2309);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2310 in value.summaries_to_record) {
            var (_t2311, _t2312) = _item2310;
            out.loc(_t2311);
            out.text(_t2312);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2330 = 0;
    var _news2331 = HashMap<String, Array<bool>>();
    for (var (_key2327, _) in value.caller_copies) {
        var _kscratch2328 = base.scratch();
        _kscratch2328.text(_key2327);
        var _vscratch2329 = base.scratch();
        _vscratch2329.unsigned(value.caller_copies[_key2327].count);
        for (var _item2332 in value.caller_copies[_key2327]) {
            _vscratch2329.flag(_item2332);
        }
        var _had = base.entry("caller_copies", _kscratch2328, _vscratch2329);
        if (_had >= 0) {
            _kept2330 += 1;
        }
        if (_had != 1) {
            _news2331[_key2327] = value.caller_copies[_key2327];
        }
    }
    if (_kept2330 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2334 = Array<(u8[], u8[], String)>();
        for (var (_key2333, _) in _news2331) {
            var _scratch2335 = out.scratch();
            _scratch2335.text(_key2333);
            var _vscratch2337 = out.scratch();
            _vscratch2337.unsigned(_news2331[_key2333].count);
            for (var _item2338 in _news2331[_key2333]) {
                _vscratch2337.flag(_item2338);
            }
            _keys2334.append((_scratch2335.finish(), _vscratch2337.finish(), _key2333));
        }
        _keys2334.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2334.count);
        for (var (_bytes2336, _, _key2333) in _keys2334) {
            out.text(_key2333);
            out.unsigned(_news2331[_key2333].count);
            for (var _item2339 in _news2331[_key2333]) {
                out.flag(_item2339);
            }
        }
        for (var (_okey2340, _) in _news2331) {
            var _own2341 = RecordOut();
            _own2341.blank_bodies = true;
            _own2341.blank_locs = true;
            _own2341.pending_as_bytes = true;
            _own2341.text(_okey2340);
            _own2341.unsigned(_news2331[_okey2340].count);
            for (var _item2342 in _news2331[_okey2340]) {
                _own2341.flag(_item2342);
            }
            base.own("caller_copies", interface_text(_own2341));
        }
    } else {
        out.unsigned(0);
        var _keys2344 = Array<(u8[], u8[], String)>();
        for (var (_key2343, _) in value.caller_copies) {
            var _scratch2345 = out.scratch();
            _scratch2345.text(_key2343);
            var _vscratch2347 = out.scratch();
            _vscratch2347.unsigned(value.caller_copies[_key2343].count);
            for (var _item2348 in value.caller_copies[_key2343]) {
                _vscratch2347.flag(_item2348);
            }
            _keys2344.append((_scratch2345.finish(), _vscratch2347.finish(), _key2343));
        }
        _keys2344.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2344.count);
        for (var (_bytes2346, _, _key2343) in _keys2344) {
            out.text(_key2343);
            out.unsigned(value.caller_copies[_key2343].count);
            for (var _item2349 in value.caller_copies[_key2343]) {
                out.flag(_item2349);
            }
        }
        for (var (_okey2350, _) in value.caller_copies) {
            var _own2351 = RecordOut();
            _own2351.blank_bodies = true;
            _own2351.blank_locs = true;
            _own2351.pending_as_bytes = true;
            _own2351.text(_okey2350);
            _own2351.unsigned(value.caller_copies[_okey2350].count);
            for (var _item2352 in value.caller_copies[_okey2350]) {
                _own2351.flag(_item2352);
            }
            base.own("caller_copies", interface_text(_own2351));
        }
        base.count("caller_copies whole", 0);
    }
    for (var (_key2327, _) in value.caller_copies) {
        var _kscratch2328 = next.scratch();
        _kscratch2328.text(_key2327);
        var _vscratch2329 = next.scratch();
        _vscratch2329.unsigned(value.caller_copies[_key2327].count);
        for (var _item2366 in value.caller_copies[_key2327]) {
            _vscratch2329.flag(_item2366);
        }
        next.keep_entry("caller_copies", _kscratch2328, _vscratch2329);
    }
    base.stat("caller_copies", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.linked);
    base.stat("linked", out.values.count - _mark);
    _mark = out.values.count;
}

_m_Module_read_delta(input: RecordIn, base: Module): Module {
    var _f1494 = Array<ast.Import>();
    var _mode1497 = input.unsigned();
    if (_mode1497 == 2) {
        var _changed1482 = HashMap<ulong, ast.Import>();
        ulong _bi1498 = 0;
        var _n1495 = input.count();
        for (var _ in 0.._n1495) {
            var _at1499 = input.unsigned();
            while (_f1494.count < _at1499 or (input.merging and _bi1498 < base.imports.count)) {
                var _c = _changed1482.try_get(_bi1498);
                _f1494.append(_c.is_value() ? _c.value() : base.imports[_bi1498]);
                _bi1498 += 1;
            }
            _f1494.append(_a_Import_read(input));
        }
        while (_bi1498 < base.imports.count) {
            var _c = _changed1482.try_get(_bi1498);
            _f1494.append(_c.is_value() ? _c.value() : base.imports[_bi1498]);
            _bi1498 += 1;
        }
    } else if (_mode1497 == 3) {
        var _n1495 = input.count();
        for (var _ in 0.._n1495) {
            _f1494.append(_a_Import_read(input));
        }
    } else {
        var _n1495 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1495) {
            var _tag1496 = input.unsigned();
            if (_tag1496 & 1 == 1) {
                if (!input.merging) {
                    _f1494.append(base.imports[_tag1496 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1494.append(_read);
                }
            }
        }
    }
    var _f1512 = Array<StructDef>();
    var _mode1515 = input.unsigned();
    if (_mode1515 == 2) {
        var _patched1518 = HashMap<ulong, StructDef>();
        var _n1513 = input.count();
        for (var _ in 0.._n1513) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1518[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1516 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1517 = input.unsigned();
            while (_f1512.count < _at1517 or (input.merging and _bi1516 < base.structs.count)) {
                var _p = _patched1518.try_get(_bi1516);
                _f1512.append(_p.is_value() ? _p.value() : base.structs[_bi1516]);
                _bi1516 += 1;
            }
            _f1512.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1516 < base.structs.count) {
            var _p = _patched1518.try_get(_bi1516);
            _f1512.append(_p.is_value() ? _p.value() : base.structs[_bi1516]);
            _bi1516 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1513 = input.count();
        for (var _ in 0.._n1513) {
            var _tag1514 = input.unsigned();
            if (_tag1514 & 1 == 1) {
                _f1512.append(base.structs[(_tag1514 >> 1) < base.structs.count ? _tag1514 >> 1 : 0]);
            } else if (_tag1514 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1512.append(_patch_s_read(input, _was));
            } else {
                _f1512.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1533 = Array<TraitDef>();
    var _mode1536 = input.unsigned();
    if (_mode1536 == 2) {
        var _changed1521 = HashMap<ulong, TraitDef>();
        ulong _bi1537 = 0;
        var _n1534 = input.count();
        for (var _ in 0.._n1534) {
            var _at1538 = input.unsigned();
            while (_f1533.count < _at1538 or (input.merging and _bi1537 < base.traits.count)) {
                var _c = _changed1521.try_get(_bi1537);
                _f1533.append(_c.is_value() ? _c.value() : base.traits[_bi1537]);
                _bi1537 += 1;
            }
            _f1533.append(_m_TraitDef_read(input));
        }
        while (_bi1537 < base.traits.count) {
            var _c = _changed1521.try_get(_bi1537);
            _f1533.append(_c.is_value() ? _c.value() : base.traits[_bi1537]);
            _bi1537 += 1;
        }
    } else if (_mode1536 == 3) {
        var _n1534 = input.count();
        for (var _ in 0.._n1534) {
            _f1533.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1534 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1534) {
            var _tag1535 = input.unsigned();
            if (_tag1535 & 1 == 1) {
                if (!input.merging) {
                    _f1533.append(base.traits[_tag1535 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1533.append(_read);
                }
            }
        }
    }
    var _f1553 = Array<ExtensionDef>();
    var _mode1556 = input.unsigned();
    if (_mode1556 == 2) {
        var _changed1541 = HashMap<ulong, ExtensionDef>();
        ulong _bi1557 = 0;
        var _n1554 = input.count();
        for (var _ in 0.._n1554) {
            var _at1558 = input.unsigned();
            while (_f1553.count < _at1558 or (input.merging and _bi1557 < base.extensions.count)) {
                var _c = _changed1541.try_get(_bi1557);
                _f1553.append(_c.is_value() ? _c.value() : base.extensions[_bi1557]);
                _bi1557 += 1;
            }
            _f1553.append(_m_ExtensionDef_read(input));
        }
        while (_bi1557 < base.extensions.count) {
            var _c = _changed1541.try_get(_bi1557);
            _f1553.append(_c.is_value() ? _c.value() : base.extensions[_bi1557]);
            _bi1557 += 1;
        }
    } else if (_mode1556 == 3) {
        var _n1554 = input.count();
        for (var _ in 0.._n1554) {
            _f1553.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1554 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1554) {
            var _tag1555 = input.unsigned();
            if (_tag1555 & 1 == 1) {
                if (!input.merging) {
                    _f1553.append(base.extensions[_tag1555 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1553.append(_read);
                }
            }
        }
    }
    var _f1574 = Array<FunctionDef>();
    var _mode1577 = input.unsigned();
    if (_mode1577 == 2) {
        var _changed1561 = HashMap<ulong, FunctionDef>();
        var _nc1563 = input.count();
        for (var _ in 0.._nc1563) {
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
                _changed1561[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1578 = 0;
        var _n1575 = input.count();
        for (var _ in 0.._n1575) {
            var _at1579 = input.unsigned();
            while (_f1574.count < _at1579 or (input.merging and _bi1578 < base.functions.count)) {
                var _c = _changed1561.try_get(_bi1578);
                _f1574.append(_c.is_value() ? _c.value() : base.functions[_bi1578]);
                _bi1578 += 1;
            }
            _f1574.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1578 < base.functions.count) {
            var _c = _changed1561.try_get(_bi1578);
            _f1574.append(_c.is_value() ? _c.value() : base.functions[_bi1578]);
            _bi1578 += 1;
        }
    } else if (_mode1577 == 3) {
        var _n1575 = input.count();
        for (var _ in 0.._n1575) {
            _f1574.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1575 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1575) {
            var _tag1576 = input.unsigned();
            if (_tag1576 & 1 == 1) {
                if (!input.merging) {
                    _f1574.append(base.functions[_tag1576 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1574.append(_read);
                }
            }
        }
    }
    var _f1594 = Array<ExternDef>();
    var _mode1597 = input.unsigned();
    if (_mode1597 == 2) {
        var _changed1582 = HashMap<ulong, ExternDef>();
        ulong _bi1598 = 0;
        var _n1595 = input.count();
        for (var _ in 0.._n1595) {
            var _at1599 = input.unsigned();
            while (_f1594.count < _at1599 or (input.merging and _bi1598 < base.externs.count)) {
                var _c = _changed1582.try_get(_bi1598);
                _f1594.append(_c.is_value() ? _c.value() : base.externs[_bi1598]);
                _bi1598 += 1;
            }
            _f1594.append(_m_ExternDef_read(input));
        }
        while (_bi1598 < base.externs.count) {
            var _c = _changed1582.try_get(_bi1598);
            _f1594.append(_c.is_value() ? _c.value() : base.externs[_bi1598]);
            _bi1598 += 1;
        }
    } else if (_mode1597 == 3) {
        var _n1595 = input.count();
        for (var _ in 0.._n1595) {
            _f1594.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1595 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1595) {
            var _tag1596 = input.unsigned();
            if (_tag1596 & 1 == 1) {
                if (!input.merging) {
                    _f1594.append(base.externs[_tag1596 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1594.append(_read);
                }
            }
        }
    }
    var _f1614 = Array<VariableDef>();
    var _mode1617 = input.unsigned();
    if (_mode1617 == 2) {
        var _changed1602 = HashMap<ulong, VariableDef>();
        ulong _bi1618 = 0;
        var _n1615 = input.count();
        for (var _ in 0.._n1615) {
            var _at1619 = input.unsigned();
            while (_f1614.count < _at1619 or (input.merging and _bi1618 < base.globals.count)) {
                var _c = _changed1602.try_get(_bi1618);
                _f1614.append(_c.is_value() ? _c.value() : base.globals[_bi1618]);
                _bi1618 += 1;
            }
            _f1614.append(_m_VariableDef_read(input));
        }
        while (_bi1618 < base.globals.count) {
            var _c = _changed1602.try_get(_bi1618);
            _f1614.append(_c.is_value() ? _c.value() : base.globals[_bi1618]);
            _bi1618 += 1;
        }
    } else if (_mode1617 == 3) {
        var _n1615 = input.count();
        for (var _ in 0.._n1615) {
            _f1614.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1615 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1615) {
            var _tag1616 = input.unsigned();
            if (_tag1616 & 1 == 1) {
                if (!input.merging) {
                    _f1614.append(base.globals[_tag1616 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1614.append(_read);
                }
            }
        }
    }
    var _f1634 = Array<ModuleStaticBlock>();
    var _mode1637 = input.unsigned();
    if (_mode1637 == 2) {
        var _changed1622 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1638 = 0;
        var _n1635 = input.count();
        for (var _ in 0.._n1635) {
            var _at1639 = input.unsigned();
            while (_f1634.count < _at1639 or (input.merging and _bi1638 < base.static_blocks.count)) {
                var _c = _changed1622.try_get(_bi1638);
                _f1634.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1638]);
                _bi1638 += 1;
            }
            _f1634.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1638 < base.static_blocks.count) {
            var _c = _changed1622.try_get(_bi1638);
            _f1634.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1638]);
            _bi1638 += 1;
        }
    } else if (_mode1637 == 3) {
        var _n1635 = input.count();
        for (var _ in 0.._n1635) {
            _f1634.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1635 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1635) {
            var _tag1636 = input.unsigned();
            if (_tag1636 & 1 == 1) {
                if (!input.merging) {
                    _f1634.append(base.static_blocks[_tag1636 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1634.append(_read);
                }
            }
        }
    }
    var _f1654 = Array<EnumDef>();
    var _mode1657 = input.unsigned();
    if (_mode1657 == 2) {
        var _changed1642 = HashMap<ulong, EnumDef>();
        ulong _bi1658 = 0;
        var _n1655 = input.count();
        for (var _ in 0.._n1655) {
            var _at1659 = input.unsigned();
            while (_f1654.count < _at1659 or (input.merging and _bi1658 < base.enums.count)) {
                var _c = _changed1642.try_get(_bi1658);
                _f1654.append(_c.is_value() ? _c.value() : base.enums[_bi1658]);
                _bi1658 += 1;
            }
            _f1654.append(_m_EnumDef_read(input));
        }
        while (_bi1658 < base.enums.count) {
            var _c = _changed1642.try_get(_bi1658);
            _f1654.append(_c.is_value() ? _c.value() : base.enums[_bi1658]);
            _bi1658 += 1;
        }
    } else if (_mode1657 == 3) {
        var _n1655 = input.count();
        for (var _ in 0.._n1655) {
            _f1654.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1655 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1655) {
            var _tag1656 = input.unsigned();
            if (_tag1656 & 1 == 1) {
                if (!input.merging) {
                    _f1654.append(base.enums[_tag1656 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1654.append(_read);
                }
            }
        }
    }
    var _f1674 = Array<TypeName>();
    var _mode1677 = input.unsigned();
    if (_mode1677 == 2) {
        var _changed1662 = HashMap<ulong, TypeName>();
        ulong _bi1678 = 0;
        var _n1675 = input.count();
        for (var _ in 0.._n1675) {
            var _at1679 = input.unsigned();
            while (_f1674.count < _at1679 or (input.merging and _bi1678 < base.struct_specs.count)) {
                var _c = _changed1662.try_get(_bi1678);
                _f1674.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1678]);
                _bi1678 += 1;
            }
            _f1674.append(_m_TypeName_read(input));
        }
        while (_bi1678 < base.struct_specs.count) {
            var _c = _changed1662.try_get(_bi1678);
            _f1674.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1678]);
            _bi1678 += 1;
        }
    } else if (_mode1677 == 3) {
        var _n1675 = input.count();
        for (var _ in 0.._n1675) {
            _f1674.append(_m_TypeName_read(input));
        }
    } else {
        var _n1675 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1675) {
            var _tag1676 = input.unsigned();
            if (_tag1676 & 1 == 1) {
                if (!input.merging) {
                    _f1674.append(base.struct_specs[_tag1676 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1674.append(_read);
                }
            }
        }
    }
    var _f1694 = Array<TypeName>();
    var _mode1697 = input.unsigned();
    if (_mode1697 == 2) {
        var _changed1682 = HashMap<ulong, TypeName>();
        ulong _bi1698 = 0;
        var _n1695 = input.count();
        for (var _ in 0.._n1695) {
            var _at1699 = input.unsigned();
            while (_f1694.count < _at1699 or (input.merging and _bi1698 < base.func_specs.count)) {
                var _c = _changed1682.try_get(_bi1698);
                _f1694.append(_c.is_value() ? _c.value() : base.func_specs[_bi1698]);
                _bi1698 += 1;
            }
            _f1694.append(_m_TypeName_read(input));
        }
        while (_bi1698 < base.func_specs.count) {
            var _c = _changed1682.try_get(_bi1698);
            _f1694.append(_c.is_value() ? _c.value() : base.func_specs[_bi1698]);
            _bi1698 += 1;
        }
    } else if (_mode1697 == 3) {
        var _n1695 = input.count();
        for (var _ in 0.._n1695) {
            _f1694.append(_m_TypeName_read(input));
        }
    } else {
        var _n1695 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1695) {
            var _tag1696 = input.unsigned();
            if (_tag1696 & 1 == 1) {
                if (!input.merging) {
                    _f1694.append(base.func_specs[_tag1696 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1694.append(_read);
                }
            }
        }
    }
    var _f1707 = Array<TypeAliasDef>();
    var _n1708 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1707.append(_b);
        }
    }
    for (var _ in 0.._n1708) {
        var _tag1709 = input.unsigned();
        if (_tag1709 & 1 == 1) {
            if (!input.merging) {
                _f1707.append(base.type_aliases[_tag1709 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1707.append(_read);
            }
        }
    }
    var _f1724 = Array<Withheld>();
    var _mode1727 = input.unsigned();
    if (_mode1727 == 2) {
        var _changed1712 = HashMap<ulong, Withheld>();
        ulong _bi1728 = 0;
        var _n1725 = input.count();
        for (var _ in 0.._n1725) {
            var _at1729 = input.unsigned();
            while (_f1724.count < _at1729 or (input.merging and _bi1728 < base.withheld.count)) {
                var _c = _changed1712.try_get(_bi1728);
                _f1724.append(_c.is_value() ? _c.value() : base.withheld[_bi1728]);
                _bi1728 += 1;
            }
            _f1724.append(_m_Withheld_read(input));
        }
        while (_bi1728 < base.withheld.count) {
            var _c = _changed1712.try_get(_bi1728);
            _f1724.append(_c.is_value() ? _c.value() : base.withheld[_bi1728]);
            _bi1728 += 1;
        }
    } else if (_mode1727 == 3) {
        var _n1725 = input.count();
        for (var _ in 0.._n1725) {
            _f1724.append(_m_Withheld_read(input));
        }
    } else {
        var _n1725 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1725) {
            var _tag1726 = input.unsigned();
            if (_tag1726 & 1 == 1) {
                if (!input.merging) {
                    _f1724.append(base.withheld[_tag1726 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1724.append(_read);
                }
            }
        }
    }
    var _f1744 = Array<PropertyDef>();
    var _mode1747 = input.unsigned();
    if (_mode1747 == 2) {
        var _changed1732 = HashMap<ulong, PropertyDef>();
        ulong _bi1748 = 0;
        var _n1745 = input.count();
        for (var _ in 0.._n1745) {
            var _at1749 = input.unsigned();
            while (_f1744.count < _at1749 or (input.merging and _bi1748 < base.properties.count)) {
                var _c = _changed1732.try_get(_bi1748);
                _f1744.append(_c.is_value() ? _c.value() : base.properties[_bi1748]);
                _bi1748 += 1;
            }
            _f1744.append(_m_PropertyDef_read(input));
        }
        while (_bi1748 < base.properties.count) {
            var _c = _changed1732.try_get(_bi1748);
            _f1744.append(_c.is_value() ? _c.value() : base.properties[_bi1748]);
            _bi1748 += 1;
        }
    } else if (_mode1747 == 3) {
        var _n1745 = input.count();
        for (var _ in 0.._n1745) {
            _f1744.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1745 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1745) {
            var _tag1746 = input.unsigned();
            if (_tag1746 & 1 == 1) {
                if (!input.merging) {
                    _f1744.append(base.properties[_tag1746 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1744.append(_read);
                }
            }
        }
    }
    var _f1764 = Array<TypeUse>();
    var _mode1767 = input.unsigned();
    if (_mode1767 == 2) {
        var _changed1752 = HashMap<ulong, TypeUse>();
        ulong _bi1768 = 0;
        var _n1765 = input.count();
        for (var _ in 0.._n1765) {
            var _at1769 = input.unsigned();
            while (_f1764.count < _at1769 or (input.merging and _bi1768 < base.type_uses.count)) {
                var _c = _changed1752.try_get(_bi1768);
                _f1764.append(_c.is_value() ? _c.value() : base.type_uses[_bi1768]);
                _bi1768 += 1;
            }
            _f1764.append(_m_TypeUse_read(input));
        }
        while (_bi1768 < base.type_uses.count) {
            var _c = _changed1752.try_get(_bi1768);
            _f1764.append(_c.is_value() ? _c.value() : base.type_uses[_bi1768]);
            _bi1768 += 1;
        }
    } else if (_mode1767 == 3) {
        var _n1765 = input.count();
        for (var _ in 0.._n1765) {
            _f1764.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1765 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1765) {
            var _tag1766 = input.unsigned();
            if (_tag1766 & 1 == 1) {
                if (!input.merging) {
                    _f1764.append(base.type_uses[_tag1766 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1764.append(_read);
                }
            }
        }
    }
    var _f1784 = Array<UseContext>();
    var _mode1787 = input.unsigned();
    if (_mode1787 == 2) {
        var _changed1772 = HashMap<ulong, UseContext>();
        ulong _bi1788 = 0;
        var _n1785 = input.count();
        for (var _ in 0.._n1785) {
            var _at1789 = input.unsigned();
            while (_f1784.count < _at1789 or (input.merging and _bi1788 < base.use_contexts.count)) {
                var _c = _changed1772.try_get(_bi1788);
                _f1784.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1788]);
                _bi1788 += 1;
            }
            _f1784.append(_m_UseContext_read(input));
        }
        while (_bi1788 < base.use_contexts.count) {
            var _c = _changed1772.try_get(_bi1788);
            _f1784.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1788]);
            _bi1788 += 1;
        }
    } else if (_mode1787 == 3) {
        var _n1785 = input.count();
        for (var _ in 0.._n1785) {
            _f1784.append(_m_UseContext_read(input));
        }
    } else {
        var _n1785 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1785) {
            var _tag1786 = input.unsigned();
            if (_tag1786 & 1 == 1) {
                if (!input.merging) {
                    _f1784.append(base.use_contexts[_tag1786 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1784.append(_read);
                }
            }
        }
    }
    var _f1805 = Array<(Loc, ulong, Loc)>();
    var _tag1806 = input.unsigned();
    if (_tag1806 == 1) {
        input.unsigned();
        for (var _i1794 in 0..base.literal_args.count) {
            _f1805.append(base.literal_args[_i1794]);
        }
        var _more1808 = input.count();
        for (var _ in 0.._more1808) {
            var _t1809 = input.loc();
            var _t1810 = input.unsigned();
            var _t1811 = input.loc();
            _f1805.append((_t1809, _t1810, _t1811));
        }
    } else {
        var _v1812 = Array<(Loc, ulong, Loc)>();
        var _n1813 = input.count();
        for (var _ in 0.._n1813) {
            var _t1814 = input.loc();
            var _t1815 = input.unsigned();
            var _t1816 = input.loc();
            _v1812.append((_t1814, _t1815, _t1816));
        }
        _f1805 = _v1812;
    }
    var _f1835 = Array<TypeAliasDef>();
    var _mode1838 = input.unsigned();
    if (_mode1838 == 2) {
        var _changed1823 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1839 = 0;
        var _n1836 = input.count();
        for (var _ in 0.._n1836) {
            var _at1840 = input.unsigned();
            while (_f1835.count < _at1840 or (input.merging and _bi1839 < base.constrained_aliases.count)) {
                var _c = _changed1823.try_get(_bi1839);
                _f1835.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1839]);
                _bi1839 += 1;
            }
            _f1835.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1839 < base.constrained_aliases.count) {
            var _c = _changed1823.try_get(_bi1839);
            _f1835.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1839]);
            _bi1839 += 1;
        }
    } else if (_mode1838 == 3) {
        var _n1836 = input.count();
        for (var _ in 0.._n1836) {
            _f1835.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1836 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1836) {
            var _tag1837 = input.unsigned();
            if (_tag1837 & 1 == 1) {
                if (!input.merging) {
                    _f1835.append(base.constrained_aliases[_tag1837 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1835.append(_read);
                }
            }
        }
    }
    var _f1855 = Array<TraitType>();
    var _mode1858 = input.unsigned();
    if (_mode1858 == 2) {
        var _changed1843 = HashMap<ulong, TraitType>();
        ulong _bi1859 = 0;
        var _n1856 = input.count();
        for (var _ in 0.._n1856) {
            var _at1860 = input.unsigned();
            while (_f1855.count < _at1860 or (input.merging and _bi1859 < base.trait_types.count)) {
                var _c = _changed1843.try_get(_bi1859);
                _f1855.append(_c.is_value() ? _c.value() : base.trait_types[_bi1859]);
                _bi1859 += 1;
            }
            _f1855.append(_m_TraitType_read(input));
        }
        while (_bi1859 < base.trait_types.count) {
            var _c = _changed1843.try_get(_bi1859);
            _f1855.append(_c.is_value() ? _c.value() : base.trait_types[_bi1859]);
            _bi1859 += 1;
        }
    } else if (_mode1858 == 3) {
        var _n1856 = input.count();
        for (var _ in 0.._n1856) {
            _f1855.append(_m_TraitType_read(input));
        }
    } else {
        var _n1856 = input.count();
        if (input.merging) {
            input.error = "trait_types" + " written by place";
        }
        for (var _ in 0.._n1856) {
            var _tag1857 = input.unsigned();
            if (_tag1857 & 1 == 1) {
                if (!input.merging) {
                    _f1855.append(base.trait_types[_tag1857 >> 1]);
                }
            } else {
                var _read = _m_TraitType_read(input);
                if (!input.merging or true) {
                    _f1855.append(_read);
                }
            }
        }
    }
    var _v1866 = Array<Conversion>();
    var _n1867 = input.count();
    for (var _ in 0.._n1867) {
        _v1866.append(_m_Conversion_read(input));
    }
    var _f1868 = _v1866;
    var _f1895 = Map<String, Array<String>>();
    var _tag1896 = input.unsigned();
    if (_tag1896 == 1) {
        for (var (_bk1897, _bv) in base.overload_sets) {
            _f1895[_bk1897] = _bv;
        }
        var _v1898 = Map<String, Array<String>>();
        var _n1899 = input.count();
        for (var _ in 0.._n1899) {
            var _k1900 = input.text();
            var _v1901 = Array<String>();
            var _n1902 = input.count();
            for (var _ in 0.._n1902) {
                _v1901.append(input.text());
            }
            _v1898[_k1900] = _v1901;
        }
        for (var (_bk1897, _av) in _v1898) {
            _f1895[_bk1897] = _av;
        }
    } else {
        var _v1903 = Map<String, Array<String>>();
        var _n1904 = input.count();
        for (var _ in 0.._n1904) {
            var _k1905 = input.text();
            var _v1906 = Array<String>();
            var _n1907 = input.count();
            for (var _ in 0.._n1907) {
                _v1906.append(input.text());
            }
            _v1903[_k1905] = _v1906;
        }
        _f1895 = _v1903;
    }
    var _f1942 = Map<String, Array<Array<String>>>();
    var _tag1943 = input.unsigned();
    if (_tag1943 == 1) {
        for (var (_bk1944, _bv) in base.overload_unions) {
            _f1942[_bk1944] = _bv;
        }
        var _v1945 = Map<String, Array<Array<String>>>();
        var _n1946 = input.count();
        for (var _ in 0.._n1946) {
            var _k1947 = input.text();
            var _v1948 = Array<Array<String>>();
            var _n1949 = input.count();
            for (var _ in 0.._n1949) {
                var _v1950 = Array<String>();
                var _n1951 = input.count();
                for (var _ in 0.._n1951) {
                    _v1950.append(input.text());
                }
                _v1948.append(_v1950);
            }
            _v1945[_k1947] = _v1948;
        }
        for (var (_bk1944, _av) in _v1945) {
            _f1942[_bk1944] = _av;
        }
    } else {
        var _v1952 = Map<String, Array<Array<String>>>();
        var _n1953 = input.count();
        for (var _ in 0.._n1953) {
            var _k1954 = input.text();
            var _v1955 = Array<Array<String>>();
            var _n1956 = input.count();
            for (var _ in 0.._n1956) {
                var _v1957 = Array<String>();
                var _n1958 = input.count();
                for (var _ in 0.._n1958) {
                    _v1957.append(input.text());
                }
                _v1955.append(_v1957);
            }
            _v1952[_k1954] = _v1955;
        }
        _f1942 = _v1952;
    }
    var _f2029 = Map<String, Map<String, Array<String>>>();
    var _tag2030 = input.unsigned();
    if (_tag2030 == 1) {
        for (var (_bk2031, _bv) in base.method_overload_sets) {
            _f2029[_bk2031] = _bv;
        }
        var _v2032 = Map<String, Map<String, Array<String>>>();
        var _n2033 = input.count();
        for (var _ in 0.._n2033) {
            var _k2034 = input.text();
            var _v2035 = Map<String, Array<String>>();
            var _n2036 = input.count();
            for (var _ in 0.._n2036) {
                var _k2037 = input.text();
                var _v2038 = Array<String>();
                var _n2039 = input.count();
                for (var _ in 0.._n2039) {
                    _v2038.append(input.text());
                }
                _v2035[_k2037] = _v2038;
            }
            _v2032[_k2034] = _v2035;
        }
        for (var (_bk2031, _av) in _v2032) {
            _f2029[_bk2031] = _av;
        }
    } else {
        var _v2040 = Map<String, Map<String, Array<String>>>();
        var _n2041 = input.count();
        for (var _ in 0.._n2041) {
            var _k2042 = input.text();
            var _v2043 = Map<String, Array<String>>();
            var _n2044 = input.count();
            for (var _ in 0.._n2044) {
                var _k2045 = input.text();
                var _v2046 = Array<String>();
                var _n2047 = input.count();
                for (var _ in 0.._n2047) {
                    _v2046.append(input.text());
                }
                _v2043[_k2045] = _v2046;
            }
            _v2040[_k2042] = _v2043;
        }
        _f2029 = _v2040;
    }
    var _f2055 = _m_ExtensionScopes_read(input);
    var _f2075 = HashSet<Loc>();
    var _tag2076 = input.unsigned();
    if (_tag2076 == 1) {
        for (var _bk2077 in base.private_functions) {
            _f2075.insert(_bk2077);
        }
        var _v2078 = HashSet<Loc>();
        var _n2079 = input.count();
        for (var _ in 0.._n2079) {
            _v2078.insert(input.loc());
        }
        for (var _bk2077 in _v2078) {
            _f2075.insert(_bk2077);
        }
    } else {
        var _v2080 = HashSet<Loc>();
        var _n2081 = input.count();
        for (var _ in 0.._n2081) {
            _v2080.insert(input.loc());
        }
        _f2075 = _v2080;
    }
    var _f2101 = HashSet<Loc>();
    var _tag2102 = input.unsigned();
    if (_tag2102 == 1) {
        for (var _bk2103 in base.file_private_functions) {
            _f2101.insert(_bk2103);
        }
        var _v2104 = HashSet<Loc>();
        var _n2105 = input.count();
        for (var _ in 0.._n2105) {
            _v2104.insert(input.loc());
        }
        for (var _bk2103 in _v2104) {
            _f2101.insert(_bk2103);
        }
    } else {
        var _v2106 = HashSet<Loc>();
        var _n2107 = input.count();
        for (var _ in 0.._n2107) {
            _v2106.insert(input.loc());
        }
        _f2101 = _v2106;
    }
    var _f2119 = Array<(Loc, String)>();
    var _tag2120 = input.unsigned();
    if (_tag2120 == 1) {
        input.unsigned();
        for (var _i2111 in 0..base.call_targets.count) {
            _f2119.append(base.call_targets[_i2111]);
        }
        var _more2122 = input.count();
        for (var _ in 0.._more2122) {
            var _t2123 = input.loc();
            var _t2124 = input.text();
            _f2119.append((_t2123, _t2124));
        }
    } else {
        var _v2125 = Array<(Loc, String)>();
        var _n2126 = input.count();
        for (var _ in 0.._n2126) {
            var _t2127 = input.loc();
            var _t2128 = input.text();
            _v2125.append((_t2127, _t2128));
        }
        _f2119 = _v2125;
    }
    var _f2145 = Array<(Loc, String)>();
    var _tag2146 = input.unsigned();
    if (_tag2146 == 1) {
        var _v2147 = Array<(Loc, String)>();
        var _n2148 = input.count();
        for (var _ in 0.._n2148) {
            var _t2149 = input.loc();
            var _t2150 = input.text();
            _v2147.append((_t2149, _t2150));
        }
        _f2145 = merge_by_place(base.argument_names, _v2147);
    } else {
        var _v2151 = Array<(Loc, String)>();
        var _n2152 = input.count();
        for (var _ in 0.._n2152) {
            var _t2153 = input.loc();
            var _t2154 = input.text();
            _v2151.append((_t2153, _t2154));
        }
        _f2145 = _v2151;
    }
    var _f2164 = Array<String>();
    var _tag2165 = input.unsigned();
    if (_tag2165 == 1) {
        input.unsigned();
        for (var _i2160 in 0..base.namespaces.count) {
            _f2164.append(base.namespaces[_i2160]);
        }
        var _more2167 = input.count();
        for (var _ in 0.._more2167) {
            _f2164.append(input.text());
        }
    } else {
        var _v2168 = Array<String>();
        var _n2169 = input.count();
        for (var _ in 0.._n2169) {
            _v2168.append(input.text());
        }
        _f2164 = _v2168;
    }
    var _f2177 = Array<bool>();
    var _tag2178 = input.unsigned();
    if (_tag2178 == 1) {
        input.unsigned();
        for (var _i2175 in 0..base.cached_files.count) {
            _f2177.append(base.cached_files[_i2175]);
        }
        var _more2180 = input.count();
        for (var _ in 0.._more2180) {
            _f2177.append(input.flag());
        }
    } else {
        var _v2181 = Array<bool>();
        var _n2182 = input.count();
        for (var _ in 0.._n2182) {
            _v2181.append(input.flag());
        }
        _f2177 = _v2181;
    }
    var _f2200 = HashMap<Loc, String>();
    var _tag2201 = input.unsigned();
    if (_tag2201 == 1) {
        for (var (_bk2202, _bv) in base.recorded_summaries) {
            _f2200[_bk2202] = _bv;
        }
        var _v2203 = HashMap<Loc, String>();
        var _n2204 = input.count();
        for (var _ in 0.._n2204) {
            var _k2205 = input.loc();
            _v2203[_k2205] = input.text();
        }
        for (var (_bk2202, _av) in _v2203) {
            _f2200[_bk2202] = _av;
        }
    } else {
        var _v2206 = HashMap<Loc, String>();
        var _n2207 = input.count();
        for (var _ in 0.._n2207) {
            var _k2208 = input.loc();
            _v2206[_k2208] = input.text();
        }
        _f2200 = _v2206;
    }
    var _f2224 = HashSet<Loc>();
    var _tag2225 = input.unsigned();
    if (_tag2225 == 1) {
        for (var _bk2226 in base.stripped) {
            _f2224.insert(_bk2226);
        }
        var _v2227 = HashSet<Loc>();
        var _n2228 = input.count();
        for (var _ in 0.._n2228) {
            _v2227.insert(input.loc());
        }
        for (var _bk2226 in _v2227) {
            _f2224.insert(_bk2226);
        }
    } else {
        var _v2229 = HashSet<Loc>();
        var _n2230 = input.count();
        for (var _ in 0.._n2230) {
            _v2229.insert(input.loc());
        }
        _f2224 = _v2229;
    }
    var _frozen = input.flag();
    var _f2242 = Array<StructDef>();
    var _mode2245 = input.unsigned();
    if (_mode2245 == 2) {
        var _patched2248 = HashMap<ulong, StructDef>();
        var _n2243 = input.count();
        for (var _ in 0.._n2243) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2248[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2246 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2247 = input.unsigned();
            while (_f2242.count < _at2247 or (input.merging and _bi2246 < base.templates.structs.count)) {
                var _p = _patched2248.try_get(_bi2246);
                _f2242.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2246]);
                _bi2246 += 1;
            }
            _f2242.append(_m_StructDef_read(input));
        }
        while (_bi2246 < base.templates.structs.count) {
            var _p = _patched2248.try_get(_bi2246);
            _f2242.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2246]);
            _bi2246 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2243 = input.count();
        for (var _ in 0.._n2243) {
            var _tag2244 = input.unsigned();
            if (_tag2244 & 1 == 1) {
                _f2242.append(
                    base.templates.structs[(_tag2244 >> 1) < base.templates.structs.count ? _tag2244 >> 1 : 0]
                );
            } else if (_tag2244 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2242.append(_patch_t_read(input, _was));
            } else {
                _f2242.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2264 = Array<FunctionDef>();
    var _mode2267 = input.unsigned();
    if (_mode2267 == 2) {
        var _changed2251 = HashMap<ulong, FunctionDef>();
        var _nc2253 = input.count();
        for (var _ in 0.._nc2253) {
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
                _changed2251[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2268 = 0;
        var _n2265 = input.count();
        for (var _ in 0.._n2265) {
            var _at2269 = input.unsigned();
            while (_f2264.count < _at2269 or (input.merging and _bi2268 < base.templates.functions.count)) {
                var _c = _changed2251.try_get(_bi2268);
                _f2264.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2268]);
                _bi2268 += 1;
            }
            _f2264.append(_m_FunctionDef_read(input));
        }
        while (_bi2268 < base.templates.functions.count) {
            var _c = _changed2251.try_get(_bi2268);
            _f2264.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2268]);
            _bi2268 += 1;
        }
    } else if (_mode2267 == 3) {
        var _n2265 = input.count();
        for (var _ in 0.._n2265) {
            _f2264.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2265 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2265) {
            var _tag2266 = input.unsigned();
            if (_tag2266 & 1 == 1) {
                if (!input.merging) {
                    _f2264.append(base.templates.functions[_tag2266 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2264.append(_read);
                }
            }
        }
    }
    var _f2271 = Templates(_frozen, _f2242, _f2264);
    var _f2272 = DeltaBase.read_checked(input, base.checked);
    var _f2292 = HashMap<String, SpecRequest>();
    var _tag2293 = input.unsigned();
    if (_tag2293 == 1) {
        for (var (_bk2294, _bv) in base.spec_requests) {
            _f2292[_bk2294] = _bv;
        }
        var _v2295 = HashMap<String, SpecRequest>();
        var _n2296 = input.count();
        for (var _ in 0.._n2296) {
            var _k2297 = input.text();
            _v2295[_k2297] = _m_SpecRequest_read(input);
        }
        for (var (_bk2294, _av) in _v2295) {
            _f2292[_bk2294] = _av;
        }
    } else {
        var _v2298 = HashMap<String, SpecRequest>();
        var _n2299 = input.count();
        for (var _ in 0.._n2299) {
            var _k2300 = input.text();
            _v2298[_k2300] = _m_SpecRequest_read(input);
        }
        _f2292 = _v2298;
    }
    var _f2301 = input.flag();
    var _f2313 = Array<(Loc, String)>();
    var _tag2314 = input.unsigned();
    if (_tag2314 == 1) {
        input.unsigned();
        for (var _i2305 in 0..base.summaries_to_record.count) {
            _f2313.append(base.summaries_to_record[_i2305]);
        }
        var _more2316 = input.count();
        for (var _ in 0.._more2316) {
            var _t2317 = input.loc();
            var _t2318 = input.text();
            _f2313.append((_t2317, _t2318));
        }
    } else {
        var _v2319 = Array<(Loc, String)>();
        var _n2320 = input.count();
        for (var _ in 0.._n2320) {
            var _t2321 = input.loc();
            var _t2322 = input.text();
            _v2319.append((_t2321, _t2322));
        }
        _f2313 = _v2319;
    }
    var _f2353 = HashMap<String, Array<bool>>();
    var _tag2354 = input.unsigned();
    if (_tag2354 == 1) {
        for (var (_bk2355, _bv) in base.caller_copies) {
            _f2353[_bk2355] = _bv;
        }
        var _v2356 = HashMap<String, Array<bool>>();
        var _n2357 = input.count();
        for (var _ in 0.._n2357) {
            var _k2358 = input.text();
            var _v2359 = Array<bool>();
            var _n2360 = input.count();
            for (var _ in 0.._n2360) {
                _v2359.append(input.flag());
            }
            _v2356[_k2358] = _v2359;
        }
        for (var (_bk2355, _av) in _v2356) {
            _f2353[_bk2355] = _av;
        }
    } else {
        var _v2361 = HashMap<String, Array<bool>>();
        var _n2362 = input.count();
        for (var _ in 0.._n2362) {
            var _k2363 = input.text();
            var _v2364 = Array<bool>();
            var _n2365 = input.count();
            for (var _ in 0.._n2365) {
                _v2364.append(input.flag());
            }
            _v2361[_k2363] = _v2364;
        }
        _f2353 = _v2361;
    }
    var _f2367 = input.flag();
    return Module(
        _f1494,
        _f1512,
        _f1533,
        _f1553,
        _f1574,
        _f1594,
        _f1614,
        _f1634,
        _f1654,
        _f1674,
        _f1694,
        _f1707,
        _f1724,
        _f1744,
        _f1764,
        _f1784,
        _f1805,
        _f1835,
        _f1855,
        _f1868,
        _f1895,
        _f1942,
        _f2029,
        _f2055,
        _f2075,
        _f2101,
        _f2119,
        _f2145,
        _f2164,
        _f2177,
        _f2200,
        _f2224,
        _f2271,
        _f2272,
        _f2292,
        _f2301,
        _f2313,
        _f2353,
        _f2367
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1500 = 0;
    for (var _item1481 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1481);
        base.add("imports", scratch, _j1500);
        _j1500 += 1;
    }
    ulong _j1519 = 0;
    for (var _item1501 in value.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1501);
        base.add("s", scratch, _j1519);
        base.name("s", _item1501.name, _j1519);
        _patch_s_index(_item1501, base, _j1519);
        _j1519 += 1;
    }
    ulong _j1539 = 0;
    for (var _item1520 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1520);
        base.add("traits", scratch, _j1539);
        _j1539 += 1;
    }
    ulong _j1559 = 0;
    for (var _item1540 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1540);
        base.add("extensions", scratch, _j1559);
        _j1559 += 1;
    }
    ulong _j1580 = 0;
    for (var _item1560 in value.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1560);
        base.add("functions", scratch, _j1580);
        base.name("functions", _item1560.name, _j1580);
        _j1580 += 1;
    }
    ulong _j1600 = 0;
    for (var _item1581 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1581);
        base.add("externs", scratch, _j1600);
        _j1600 += 1;
    }
    ulong _j1620 = 0;
    for (var _item1601 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1601);
        base.add("globals", scratch, _j1620);
        _j1620 += 1;
    }
    ulong _j1640 = 0;
    for (var _item1621 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1621);
        base.add("static_blocks", scratch, _j1640);
        _j1640 += 1;
    }
    ulong _j1660 = 0;
    for (var _item1641 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1641);
        base.add("enums", scratch, _j1660);
        _j1660 += 1;
    }
    ulong _j1680 = 0;
    for (var _item1661 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1661);
        base.add("struct_specs", scratch, _j1680);
        _j1680 += 1;
    }
    ulong _j1700 = 0;
    for (var _item1681 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1681);
        base.add("func_specs", scratch, _j1700);
        _j1700 += 1;
    }
    ulong _j1710 = 0;
    for (var _item1701 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1701);
        base.add("type_aliases", scratch, _j1710);
        _j1710 += 1;
    }
    ulong _j1730 = 0;
    for (var _item1711 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1711);
        base.add("withheld", scratch, _j1730);
        _j1730 += 1;
    }
    ulong _j1750 = 0;
    for (var _item1731 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1731);
        base.add("properties", scratch, _j1750);
        _j1750 += 1;
    }
    ulong _j1770 = 0;
    for (var _item1751 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1751);
        base.add("type_uses", scratch, _j1770);
        _j1770 += 1;
    }
    ulong _j1790 = 0;
    for (var _item1771 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1771);
        base.add("use_contexts", scratch, _j1790);
        _j1790 += 1;
    }
    var _xscratch1817 = base.scratch();
    for (var _xitem1818 in value.literal_args) {
        var (_t1819, _t1820, _t1821) = _xitem1818;
        _xscratch1817.loc(_t1819);
        _xscratch1817.unsigned(_t1820);
        _xscratch1817.loc(_t1821);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1817);
    ulong _j1841 = 0;
    for (var _item1822 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1822);
        base.add("constrained_aliases", scratch, _j1841);
        _j1841 += 1;
    }
    ulong _j1861 = 0;
    for (var _item1842 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1842);
        base.add("trait_types", scratch, _j1861);
        _j1861 += 1;
    }
    ulong _cj1865 = 0;
    for (var _conv1863 in value.conversions) {
        var _own1864 = RecordOut();
        _own1864.blank_locs = true;
        _m_Conversion_write(_own1864, _conv1863);
        base.add_hashed("conversions", interface_text(_own1864), _cj1865);
        _cj1865 += 1;
    }
    for (var (_key1869, _) in value.overload_sets) {
        var _kscratch1870 = base.scratch();
        _kscratch1870.text(_key1869);
        var _vscratch1871 = base.scratch();
        _vscratch1871.unsigned(value.overload_sets[_key1869].count);
        for (var _item1908 in value.overload_sets[_key1869]) {
            _vscratch1871.text(_item1908);
        }
        base.keep_entry("overload_sets", _kscratch1870, _vscratch1871);
    }
    for (var (_key1909, _) in value.overload_unions) {
        var _kscratch1910 = base.scratch();
        _kscratch1910.text(_key1909);
        var _vscratch1911 = base.scratch();
        _vscratch1911.unsigned(value.overload_unions[_key1909].count);
        for (var _item1959 in value.overload_unions[_key1909]) {
            _vscratch1911.unsigned(_item1959.count);
            for (var _item1960 in _item1959) {
                _vscratch1911.text(_item1960);
            }
        }
        base.keep_entry("overload_unions", _kscratch1910, _vscratch1911);
    }
    for (var (_key1961, _) in value.method_overload_sets) {
        var _kscratch1962 = base.scratch();
        _kscratch1962.text(_key1961);
        var _vscratch1963 = base.scratch();
        var _keys2049 = Array<(u8[], u8[], String)>();
        for (var (_key2048, _) in value.method_overload_sets[_key1961]) {
            var _scratch2050 = _vscratch1963.scratch();
            _scratch2050.text(_key2048);
            var _vscratch2052 = _vscratch1963.scratch();
            _vscratch2052.unsigned(value.method_overload_sets[_key1961][_key2048].count);
            for (var _item2053 in value.method_overload_sets[_key1961][_key2048]) {
                _vscratch2052.text(_item2053);
            }
            _keys2049.append((_scratch2050.finish(), _vscratch2052.finish(), _key2048));
        }
        _keys2049.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1963.unsigned(_keys2049.count);
        for (var (_bytes2051, _, _key2048) in _keys2049) {
            _vscratch1963.text(_key2048);
            _vscratch1963.unsigned(value.method_overload_sets[_key1961][_key2048].count);
            for (var _item2054 in value.method_overload_sets[_key1961][_key2048]) {
                _vscratch1963.text(_item2054);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1962, _vscratch1963);
    }
    for (var _key2056 in value.private_functions) {
        var _kscratch2057 = base.scratch();
        _kscratch2057.loc(_key2056);
        var _vscratch2058 = base.scratch();
        base.keep_entry("private_functions", _kscratch2057, _vscratch2058);
    }
    for (var _key2082 in value.file_private_functions) {
        var _kscratch2083 = base.scratch();
        _kscratch2083.loc(_key2082);
        var _vscratch2084 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch2083, _vscratch2084);
    }
    var _xscratch2129 = base.scratch();
    for (var _xitem2130 in value.call_targets) {
        var (_t2131, _t2132) = _xitem2130;
        _xscratch2129.loc(_t2131);
        _xscratch2129.text(_t2132);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2129);
    for (var _item2133 in value.argument_names) {
        var _escratch2134 = base.scratch();
        var (_t2155, _t2156) = _item2133;
        _escratch2134.loc(_t2155);
        _escratch2134.text(_t2156);
        base.keep_entry("argument_names", _escratch2134, base.scratch());
    }
    var _xscratch2170 = base.scratch();
    for (var _xitem2171 in value.namespaces) {
        _xscratch2170.text(_xitem2171);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2170);
    var _xscratch2183 = base.scratch();
    for (var _xitem2184 in value.cached_files) {
        _xscratch2183.flag(_xitem2184);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2183);
    for (var (_key2185, _) in value.recorded_summaries) {
        var _kscratch2186 = base.scratch();
        _kscratch2186.loc(_key2185);
        var _vscratch2187 = base.scratch();
        _vscratch2187.text(value.recorded_summaries[_key2185]);
        base.keep_entry("recorded_summaries", _kscratch2186, _vscratch2187);
    }
    for (var _key2209 in value.stripped) {
        var _kscratch2210 = base.scratch();
        _kscratch2210.loc(_key2209);
        var _vscratch2211 = base.scratch();
        base.keep_entry("stripped", _kscratch2210, _vscratch2211);
    }
    ulong _j2249 = 0;
    for (var _item2231 in value.templates.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item2231);
        base.add("t", scratch, _j2249);
        base.name("t", _item2231.name, _j2249);
        _patch_t_index(_item2231, base, _j2249);
        _j2249 += 1;
    }
    ulong _j2270 = 0;
    for (var _item2250 in value.templates.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2250);
        base.add("tf", scratch, _j2270);
        base.name("tf", _item2250.name, _j2270);
        _j2270 += 1;
    }
    base.keep_checked(value.checked);
    for (var (_key2273, _) in value.spec_requests) {
        var _kscratch2274 = base.scratch();
        _kscratch2274.text(_key2273);
        var _vscratch2275 = base.scratch();
        _m_SpecRequest_write(_vscratch2275, value.spec_requests[_key2273]);
        base.keep_entry("spec_requests", _kscratch2274, _vscratch2275);
    }
    var _xscratch2323 = base.scratch();
    for (var _xitem2324 in value.summaries_to_record) {
        var (_t2325, _t2326) = _xitem2324;
        _xscratch2323.loc(_t2325);
        _xscratch2323.text(_t2326);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2323);
    for (var (_key2327, _) in value.caller_copies) {
        var _kscratch2328 = base.scratch();
        _kscratch2328.text(_key2327);
        var _vscratch2329 = base.scratch();
        _vscratch2329.unsigned(value.caller_copies[_key2327].count);
        for (var _item2366 in value.caller_copies[_key2327]) {
            _vscratch2329.flag(_item2366);
        }
        base.keep_entry("caller_copies", _kscratch2328, _vscratch2329);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1710 = 0;
    for (var _item1701 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1701);
        base.add("type_aliases", scratch, _j1710);
        _j1710 += 1;
    }
    for (var (_key2185, _) in value.recorded_summaries) {
        var _kscratch2186 = base.scratch();
        _kscratch2186.loc(_key2185);
        var _vscratch2187 = base.scratch();
        _vscratch2187.text(value.recorded_summaries[_key2185]);
        base.keep_entry("recorded_summaries", _kscratch2186, _vscratch2187);
    }
    var _xscratch2323 = base.scratch();
    for (var _xitem2324 in value.summaries_to_record) {
        var (_t2325, _t2326) = _xitem2324;
        _xscratch2323.loc(_t2325);
        _xscratch2323.text(_t2326);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2323);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _hs2376 = Array<String>();
    for (var _item2370 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2370);
        _hs2376.append(base.hash_of(scratch));
    }
    var _seq2377 = base.sequence($"s.{slot}.generic_params");
    ulong _bj2378 = 0;
    var _news2379 = Array<ulong>();
    for (var _i2380 in 0.._hs2376.count) {
        if (_bj2378 < _seq2377.count and _hs2376[_i2380] == _seq2377[_bj2378]) {
            _bj2378 += 1;
        } else {
            _news2379.append(_i2380);
        }
    }
    if (_bj2378 == _seq2377.count) {
        out.unsigned(2);
        out.unsigned(_news2379.count);
        for (var _i2380 in _news2379) {
            out.unsigned(_i2380);
            _m_GenericParam_write(out, value.generic_params[_i2380]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2380 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2380]);
        }
    }
    var _hs2394 = Array<String>();
    for (var _item2388 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2388);
        _hs2394.append(base.hash_of(scratch));
    }
    var _seq2395 = base.sequence($"s.{slot}.field_members");
    ulong _bj2396 = 0;
    var _news2397 = Array<ulong>();
    for (var _i2398 in 0.._hs2394.count) {
        if (_bj2396 < _seq2395.count and _hs2394[_i2398] == _seq2395[_bj2396]) {
            _bj2396 += 1;
        } else {
            _news2397.append(_i2398);
        }
    }
    if (_bj2396 == _seq2395.count) {
        out.unsigned(2);
        out.unsigned(_news2397.count);
        for (var _i2398 in _news2397) {
            out.unsigned(_i2398);
            _m_VariableDef_write(out, value.field_members[_i2398]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2398 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2398]);
        }
    }
    var _hs2412 = Array<String>();
    for (var _item2406 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2406);
        _hs2412.append(base.hash_of(scratch));
    }
    var _seq2413 = base.sequence($"s.{slot}.method_members");
    ulong _bj2414 = 0;
    var _news2415 = Array<ulong>();
    for (var _i2416 in 0.._hs2412.count) {
        if (_bj2414 < _seq2413.count and _hs2412[_i2416] == _seq2413[_bj2414]) {
            _bj2414 += 1;
        } else {
            _news2415.append(_i2416);
        }
    }
    if (_bj2414 == _seq2413.count) {
        out.unsigned(2);
        out.unsigned(_news2415.count);
        for (var _i2416 in _news2415) {
            out.unsigned(_i2416);
            _m_FunctionDef_write(out, value.method_members[_i2416]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2416 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2416]);
        }
    }
    var _hs2430 = Array<String>();
    for (var _item2424 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2424);
        _hs2430.append(base.hash_of(scratch));
    }
    var _seq2431 = base.sequence($"s.{slot}.generic_methods");
    ulong _bj2432 = 0;
    var _news2433 = Array<ulong>();
    for (var _i2434 in 0.._hs2430.count) {
        if (_bj2432 < _seq2431.count and _hs2430[_i2434] == _seq2431[_bj2432]) {
            _bj2432 += 1;
        } else {
            _news2433.append(_i2434);
        }
    }
    if (_bj2432 == _seq2431.count) {
        out.unsigned(2);
        out.unsigned(_news2433.count);
        for (var _i2434 in _news2433) {
            out.unsigned(_i2434);
            _m_FunctionDef_write(out, value.generic_methods[_i2434]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2434 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2434]);
        }
    }
    var _hs2448 = Array<String>();
    for (var _item2442 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2442);
        _hs2448.append(base.hash_of(scratch));
    }
    var _seq2449 = base.sequence($"s.{slot}.constructors");
    ulong _bj2450 = 0;
    var _news2451 = Array<ulong>();
    for (var _i2452 in 0.._hs2448.count) {
        if (_bj2450 < _seq2449.count and _hs2448[_i2452] == _seq2449[_bj2450]) {
            _bj2450 += 1;
        } else {
            _news2451.append(_i2452);
        }
    }
    if (_bj2450 == _seq2449.count) {
        out.unsigned(2);
        out.unsigned(_news2451.count);
        for (var _i2452 in _news2451) {
            out.unsigned(_i2452);
            _m_FunctionDef_write(out, value.constructors[_i2452]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2452 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2452]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _hs2469 = Array<String>();
    for (var _item2463 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2463);
        _hs2469.append(base.hash_of(scratch));
    }
    var _seq2470 = base.sequence($"s.{slot}.traits");
    ulong _bj2471 = 0;
    var _news2472 = Array<ulong>();
    for (var _i2473 in 0.._hs2469.count) {
        if (_bj2471 < _seq2470.count and _hs2469[_i2473] == _seq2470[_bj2471]) {
            _bj2471 += 1;
        } else {
            _news2472.append(_i2473);
        }
    }
    if (_bj2471 == _seq2470.count) {
        out.unsigned(2);
        out.unsigned(_news2472.count);
        for (var _i2473 in _news2472) {
            out.unsigned(_i2473);
            _m_TypeName_write(out, value.traits[_i2473]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2473 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2473]);
        }
    }
    var _hs2487 = Array<String>();
    for (var _item2481 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2481);
        _hs2487.append(base.hash_of(scratch));
    }
    var _seq2488 = base.sequence($"s.{slot}.attributes");
    ulong _bj2489 = 0;
    var _news2490 = Array<ulong>();
    for (var _i2491 in 0.._hs2487.count) {
        if (_bj2489 < _seq2488.count and _hs2487[_i2491] == _seq2488[_bj2489]) {
            _bj2489 += 1;
        } else {
            _news2490.append(_i2491);
        }
    }
    if (_bj2489 == _seq2488.count) {
        out.unsigned(2);
        out.unsigned(_news2490.count);
        for (var _i2491 in _news2490) {
            out.unsigned(_i2491);
            _a_Attribute_write(out, value.attributes[_i2491]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2491 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2491]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2500 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2500);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2368 = input.text();
    var _f2369 = _m_TypeName_read(input);
    var _f2381 = Array<GenericParam>();
    var _mode2384 = input.unsigned();
    if (_mode2384 == 2) {
        var _changed2371 = HashMap<ulong, GenericParam>();
        ulong _bi2385 = 0;
        var _n2382 = input.count();
        for (var _ in 0.._n2382) {
            var _at2386 = input.unsigned();
            while (_f2381.count < _at2386 or (input.merging and _bi2385 < was.generic_params.count)) {
                var _c = _changed2371.try_get(_bi2385);
                _f2381.append(_c.is_value() ? _c.value() : was.generic_params[_bi2385]);
                _bi2385 += 1;
            }
            _f2381.append(_m_GenericParam_read(input));
        }
        while (_bi2385 < was.generic_params.count) {
            var _c = _changed2371.try_get(_bi2385);
            _f2381.append(_c.is_value() ? _c.value() : was.generic_params[_bi2385]);
            _bi2385 += 1;
        }
    } else if (_mode2384 == 3) {
        var _n2382 = input.count();
        for (var _ in 0.._n2382) {
            _f2381.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2382 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2382) {
            var _tag2383 = input.unsigned();
            if (_tag2383 & 1 == 1) {
                if (!input.merging) {
                    _f2381.append(was.generic_params[_tag2383 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2381.append(_read);
                }
            }
        }
    }
    var _f2399 = Array<VariableDef>();
    var _mode2402 = input.unsigned();
    if (_mode2402 == 2) {
        var _changed2389 = HashMap<ulong, VariableDef>();
        ulong _bi2403 = 0;
        var _n2400 = input.count();
        for (var _ in 0.._n2400) {
            var _at2404 = input.unsigned();
            while (_f2399.count < _at2404 or (input.merging and _bi2403 < was.field_members.count)) {
                var _c = _changed2389.try_get(_bi2403);
                _f2399.append(_c.is_value() ? _c.value() : was.field_members[_bi2403]);
                _bi2403 += 1;
            }
            _f2399.append(_m_VariableDef_read(input));
        }
        while (_bi2403 < was.field_members.count) {
            var _c = _changed2389.try_get(_bi2403);
            _f2399.append(_c.is_value() ? _c.value() : was.field_members[_bi2403]);
            _bi2403 += 1;
        }
    } else if (_mode2402 == 3) {
        var _n2400 = input.count();
        for (var _ in 0.._n2400) {
            _f2399.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2400 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2400) {
            var _tag2401 = input.unsigned();
            if (_tag2401 & 1 == 1) {
                if (!input.merging) {
                    _f2399.append(was.field_members[_tag2401 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2399.append(_read);
                }
            }
        }
    }
    var _f2417 = Array<FunctionDef>();
    var _mode2420 = input.unsigned();
    if (_mode2420 == 2) {
        var _changed2407 = HashMap<ulong, FunctionDef>();
        ulong _bi2421 = 0;
        var _n2418 = input.count();
        for (var _ in 0.._n2418) {
            var _at2422 = input.unsigned();
            while (_f2417.count < _at2422 or (input.merging and _bi2421 < was.method_members.count)) {
                var _c = _changed2407.try_get(_bi2421);
                _f2417.append(_c.is_value() ? _c.value() : was.method_members[_bi2421]);
                _bi2421 += 1;
            }
            _f2417.append(_m_FunctionDef_read(input));
        }
        while (_bi2421 < was.method_members.count) {
            var _c = _changed2407.try_get(_bi2421);
            _f2417.append(_c.is_value() ? _c.value() : was.method_members[_bi2421]);
            _bi2421 += 1;
        }
    } else if (_mode2420 == 3) {
        var _n2418 = input.count();
        for (var _ in 0.._n2418) {
            _f2417.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2418 = input.count();
        if (input.merging) {
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2418) {
            var _tag2419 = input.unsigned();
            if (_tag2419 & 1 == 1) {
                if (!input.merging) {
                    _f2417.append(was.method_members[_tag2419 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2417.append(_read);
                }
            }
        }
    }
    var _f2435 = Array<FunctionDef>();
    var _mode2438 = input.unsigned();
    if (_mode2438 == 2) {
        var _changed2425 = HashMap<ulong, FunctionDef>();
        ulong _bi2439 = 0;
        var _n2436 = input.count();
        for (var _ in 0.._n2436) {
            var _at2440 = input.unsigned();
            while (_f2435.count < _at2440 or (input.merging and _bi2439 < was.generic_methods.count)) {
                var _c = _changed2425.try_get(_bi2439);
                _f2435.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2439]);
                _bi2439 += 1;
            }
            _f2435.append(_m_FunctionDef_read(input));
        }
        while (_bi2439 < was.generic_methods.count) {
            var _c = _changed2425.try_get(_bi2439);
            _f2435.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2439]);
            _bi2439 += 1;
        }
    } else if (_mode2438 == 3) {
        var _n2436 = input.count();
        for (var _ in 0.._n2436) {
            _f2435.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2436 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2436) {
            var _tag2437 = input.unsigned();
            if (_tag2437 & 1 == 1) {
                if (!input.merging) {
                    _f2435.append(was.generic_methods[_tag2437 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2435.append(_read);
                }
            }
        }
    }
    var _f2453 = Array<FunctionDef>();
    var _mode2456 = input.unsigned();
    if (_mode2456 == 2) {
        var _changed2443 = HashMap<ulong, FunctionDef>();
        ulong _bi2457 = 0;
        var _n2454 = input.count();
        for (var _ in 0.._n2454) {
            var _at2458 = input.unsigned();
            while (_f2453.count < _at2458 or (input.merging and _bi2457 < was.constructors.count)) {
                var _c = _changed2443.try_get(_bi2457);
                _f2453.append(_c.is_value() ? _c.value() : was.constructors[_bi2457]);
                _bi2457 += 1;
            }
            _f2453.append(_m_FunctionDef_read(input));
        }
        while (_bi2457 < was.constructors.count) {
            var _c = _changed2443.try_get(_bi2457);
            _f2453.append(_c.is_value() ? _c.value() : was.constructors[_bi2457]);
            _bi2457 += 1;
        }
    } else if (_mode2456 == 3) {
        var _n2454 = input.count();
        for (var _ in 0.._n2454) {
            _f2453.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2454 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2454) {
            var _tag2455 = input.unsigned();
            if (_tag2455 & 1 == 1) {
                if (!input.merging) {
                    _f2453.append(was.constructors[_tag2455 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2453.append(_read);
                }
            }
        }
    }
    var _f2460 = _m_FunctionDef_read(input);
    var _f2461 = _m_FunctionDef_read(input);
    var _f2462 = _m_FunctionDef_read(input);
    var _f2474 = Array<TypeName>();
    var _mode2477 = input.unsigned();
    if (_mode2477 == 2) {
        var _changed2464 = HashMap<ulong, TypeName>();
        ulong _bi2478 = 0;
        var _n2475 = input.count();
        for (var _ in 0.._n2475) {
            var _at2479 = input.unsigned();
            while (_f2474.count < _at2479 or (input.merging and _bi2478 < was.traits.count)) {
                var _c = _changed2464.try_get(_bi2478);
                _f2474.append(_c.is_value() ? _c.value() : was.traits[_bi2478]);
                _bi2478 += 1;
            }
            _f2474.append(_m_TypeName_read(input));
        }
        while (_bi2478 < was.traits.count) {
            var _c = _changed2464.try_get(_bi2478);
            _f2474.append(_c.is_value() ? _c.value() : was.traits[_bi2478]);
            _bi2478 += 1;
        }
    } else if (_mode2477 == 3) {
        var _n2475 = input.count();
        for (var _ in 0.._n2475) {
            _f2474.append(_m_TypeName_read(input));
        }
    } else {
        var _n2475 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2475) {
            var _tag2476 = input.unsigned();
            if (_tag2476 & 1 == 1) {
                if (!input.merging) {
                    _f2474.append(was.traits[_tag2476 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2474.append(_read);
                }
            }
        }
    }
    var _f2492 = Array<ast.Attribute>();
    var _mode2495 = input.unsigned();
    if (_mode2495 == 2) {
        var _changed2482 = HashMap<ulong, ast.Attribute>();
        ulong _bi2496 = 0;
        var _n2493 = input.count();
        for (var _ in 0.._n2493) {
            var _at2497 = input.unsigned();
            while (_f2492.count < _at2497 or (input.merging and _bi2496 < was.attributes.count)) {
                var _c = _changed2482.try_get(_bi2496);
                _f2492.append(_c.is_value() ? _c.value() : was.attributes[_bi2496]);
                _bi2496 += 1;
            }
            _f2492.append(_a_Attribute_read(input));
        }
        while (_bi2496 < was.attributes.count) {
            var _c = _changed2482.try_get(_bi2496);
            _f2492.append(_c.is_value() ? _c.value() : was.attributes[_bi2496]);
            _bi2496 += 1;
        }
    } else if (_mode2495 == 3) {
        var _n2493 = input.count();
        for (var _ in 0.._n2493) {
            _f2492.append(_a_Attribute_read(input));
        }
    } else {
        var _n2493 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2493) {
            var _tag2494 = input.unsigned();
            if (_tag2494 & 1 == 1) {
                if (!input.merging) {
                    _f2492.append(was.attributes[_tag2494 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2492.append(_read);
                }
            }
        }
    }
    var _f2499 = input.loc();
    var _o2501 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2502 = Array<EnumCaseDef>();
        var _n2503 = input.count();
        for (var _ in 0.._n2503) {
            _v2502.append(_m_EnumCaseDef_read(input));
        }
        _o2501 = Optional<Array<EnumCaseDef>>.Value(_v2502);
    }
    var _f2504 = _o2501;
    return StructDef(
        _f2368, _f2369, _f2381, _f2399, _f2417, _f2435, _f2453, _f2460, _f2461, _f2462, _f2474, _f2492, _f2499, _f2504
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    ulong _j2387 = 0;
    for (var _item2370 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2370);
        base.add($"s.{slot}.generic_params", scratch, _j2387);
        _j2387 += 1;
    }
    ulong _j2405 = 0;
    for (var _item2388 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2388);
        base.add($"s.{slot}.field_members", scratch, _j2405);
        _j2405 += 1;
    }
    ulong _j2423 = 0;
    for (var _item2406 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2406);
        base.add($"s.{slot}.method_members", scratch, _j2423);
        _j2423 += 1;
    }
    ulong _j2441 = 0;
    for (var _item2424 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2424);
        base.add($"s.{slot}.generic_methods", scratch, _j2441);
        _j2441 += 1;
    }
    ulong _j2459 = 0;
    for (var _item2442 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2442);
        base.add($"s.{slot}.constructors", scratch, _j2459);
        _j2459 += 1;
    }
    ulong _j2480 = 0;
    for (var _item2463 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2463);
        base.add($"s.{slot}.traits", scratch, _j2480);
        _j2480 += 1;
    }
    ulong _j2498 = 0;
    for (var _item2481 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2481);
        base.add($"s.{slot}.attributes", scratch, _j2498);
        _j2498 += 1;
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _hs2513 = Array<String>();
    for (var _item2507 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2507);
        _hs2513.append(base.hash_of(scratch));
    }
    var _seq2514 = base.sequence($"t.{slot}.generic_params");
    ulong _bj2515 = 0;
    var _news2516 = Array<ulong>();
    for (var _i2517 in 0.._hs2513.count) {
        if (_bj2515 < _seq2514.count and _hs2513[_i2517] == _seq2514[_bj2515]) {
            _bj2515 += 1;
        } else {
            _news2516.append(_i2517);
        }
    }
    if (_bj2515 == _seq2514.count) {
        out.unsigned(2);
        out.unsigned(_news2516.count);
        for (var _i2517 in _news2516) {
            out.unsigned(_i2517);
            _m_GenericParam_write(out, value.generic_params[_i2517]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2517 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2517]);
        }
    }
    var _hs2531 = Array<String>();
    for (var _item2525 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2525);
        _hs2531.append(base.hash_of(scratch));
    }
    var _seq2532 = base.sequence($"t.{slot}.field_members");
    ulong _bj2533 = 0;
    var _news2534 = Array<ulong>();
    for (var _i2535 in 0.._hs2531.count) {
        if (_bj2533 < _seq2532.count and _hs2531[_i2535] == _seq2532[_bj2533]) {
            _bj2533 += 1;
        } else {
            _news2534.append(_i2535);
        }
    }
    if (_bj2533 == _seq2532.count) {
        out.unsigned(2);
        out.unsigned(_news2534.count);
        for (var _i2535 in _news2534) {
            out.unsigned(_i2535);
            _m_VariableDef_write(out, value.field_members[_i2535]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2535 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2535]);
        }
    }
    var _hs2549 = Array<String>();
    for (var _item2543 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2543);
        _hs2549.append(base.hash_of(scratch));
    }
    var _seq2550 = base.sequence($"t.{slot}.method_members");
    ulong _bj2551 = 0;
    var _news2552 = Array<ulong>();
    for (var _i2553 in 0.._hs2549.count) {
        if (_bj2551 < _seq2550.count and _hs2549[_i2553] == _seq2550[_bj2551]) {
            _bj2551 += 1;
        } else {
            _news2552.append(_i2553);
        }
    }
    if (_bj2551 == _seq2550.count) {
        out.unsigned(2);
        out.unsigned(_news2552.count);
        for (var _i2553 in _news2552) {
            out.unsigned(_i2553);
            _m_FunctionDef_write(out, value.method_members[_i2553]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2553 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2553]);
        }
    }
    var _hs2567 = Array<String>();
    for (var _item2561 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2561);
        _hs2567.append(base.hash_of(scratch));
    }
    var _seq2568 = base.sequence($"t.{slot}.generic_methods");
    ulong _bj2569 = 0;
    var _news2570 = Array<ulong>();
    for (var _i2571 in 0.._hs2567.count) {
        if (_bj2569 < _seq2568.count and _hs2567[_i2571] == _seq2568[_bj2569]) {
            _bj2569 += 1;
        } else {
            _news2570.append(_i2571);
        }
    }
    if (_bj2569 == _seq2568.count) {
        out.unsigned(2);
        out.unsigned(_news2570.count);
        for (var _i2571 in _news2570) {
            out.unsigned(_i2571);
            _m_FunctionDef_write(out, value.generic_methods[_i2571]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2571 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2571]);
        }
    }
    var _hs2585 = Array<String>();
    for (var _item2579 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2579);
        _hs2585.append(base.hash_of(scratch));
    }
    var _seq2586 = base.sequence($"t.{slot}.constructors");
    ulong _bj2587 = 0;
    var _news2588 = Array<ulong>();
    for (var _i2589 in 0.._hs2585.count) {
        if (_bj2587 < _seq2586.count and _hs2585[_i2589] == _seq2586[_bj2587]) {
            _bj2587 += 1;
        } else {
            _news2588.append(_i2589);
        }
    }
    if (_bj2587 == _seq2586.count) {
        out.unsigned(2);
        out.unsigned(_news2588.count);
        for (var _i2589 in _news2588) {
            out.unsigned(_i2589);
            _m_FunctionDef_write(out, value.constructors[_i2589]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2589 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2589]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _hs2606 = Array<String>();
    for (var _item2600 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2600);
        _hs2606.append(base.hash_of(scratch));
    }
    var _seq2607 = base.sequence($"t.{slot}.traits");
    ulong _bj2608 = 0;
    var _news2609 = Array<ulong>();
    for (var _i2610 in 0.._hs2606.count) {
        if (_bj2608 < _seq2607.count and _hs2606[_i2610] == _seq2607[_bj2608]) {
            _bj2608 += 1;
        } else {
            _news2609.append(_i2610);
        }
    }
    if (_bj2608 == _seq2607.count) {
        out.unsigned(2);
        out.unsigned(_news2609.count);
        for (var _i2610 in _news2609) {
            out.unsigned(_i2610);
            _m_TypeName_write(out, value.traits[_i2610]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2610 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2610]);
        }
    }
    var _hs2624 = Array<String>();
    for (var _item2618 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2618);
        _hs2624.append(base.hash_of(scratch));
    }
    var _seq2625 = base.sequence($"t.{slot}.attributes");
    ulong _bj2626 = 0;
    var _news2627 = Array<ulong>();
    for (var _i2628 in 0.._hs2624.count) {
        if (_bj2626 < _seq2625.count and _hs2624[_i2628] == _seq2625[_bj2626]) {
            _bj2626 += 1;
        } else {
            _news2627.append(_i2628);
        }
    }
    if (_bj2626 == _seq2625.count) {
        out.unsigned(2);
        out.unsigned(_news2627.count);
        for (var _i2628 in _news2627) {
            out.unsigned(_i2628);
            _a_Attribute_write(out, value.attributes[_i2628]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2628 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2628]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2637 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2637);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2505 = input.text();
    var _f2506 = _m_TypeName_read(input);
    var _f2518 = Array<GenericParam>();
    var _mode2521 = input.unsigned();
    if (_mode2521 == 2) {
        var _changed2508 = HashMap<ulong, GenericParam>();
        ulong _bi2522 = 0;
        var _n2519 = input.count();
        for (var _ in 0.._n2519) {
            var _at2523 = input.unsigned();
            while (_f2518.count < _at2523 or (input.merging and _bi2522 < was.generic_params.count)) {
                var _c = _changed2508.try_get(_bi2522);
                _f2518.append(_c.is_value() ? _c.value() : was.generic_params[_bi2522]);
                _bi2522 += 1;
            }
            _f2518.append(_m_GenericParam_read(input));
        }
        while (_bi2522 < was.generic_params.count) {
            var _c = _changed2508.try_get(_bi2522);
            _f2518.append(_c.is_value() ? _c.value() : was.generic_params[_bi2522]);
            _bi2522 += 1;
        }
    } else if (_mode2521 == 3) {
        var _n2519 = input.count();
        for (var _ in 0.._n2519) {
            _f2518.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2519 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2519) {
            var _tag2520 = input.unsigned();
            if (_tag2520 & 1 == 1) {
                if (!input.merging) {
                    _f2518.append(was.generic_params[_tag2520 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2518.append(_read);
                }
            }
        }
    }
    var _f2536 = Array<VariableDef>();
    var _mode2539 = input.unsigned();
    if (_mode2539 == 2) {
        var _changed2526 = HashMap<ulong, VariableDef>();
        ulong _bi2540 = 0;
        var _n2537 = input.count();
        for (var _ in 0.._n2537) {
            var _at2541 = input.unsigned();
            while (_f2536.count < _at2541 or (input.merging and _bi2540 < was.field_members.count)) {
                var _c = _changed2526.try_get(_bi2540);
                _f2536.append(_c.is_value() ? _c.value() : was.field_members[_bi2540]);
                _bi2540 += 1;
            }
            _f2536.append(_m_VariableDef_read(input));
        }
        while (_bi2540 < was.field_members.count) {
            var _c = _changed2526.try_get(_bi2540);
            _f2536.append(_c.is_value() ? _c.value() : was.field_members[_bi2540]);
            _bi2540 += 1;
        }
    } else if (_mode2539 == 3) {
        var _n2537 = input.count();
        for (var _ in 0.._n2537) {
            _f2536.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2537 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2537) {
            var _tag2538 = input.unsigned();
            if (_tag2538 & 1 == 1) {
                if (!input.merging) {
                    _f2536.append(was.field_members[_tag2538 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2536.append(_read);
                }
            }
        }
    }
    var _f2554 = Array<FunctionDef>();
    var _mode2557 = input.unsigned();
    if (_mode2557 == 2) {
        var _changed2544 = HashMap<ulong, FunctionDef>();
        ulong _bi2558 = 0;
        var _n2555 = input.count();
        for (var _ in 0.._n2555) {
            var _at2559 = input.unsigned();
            while (_f2554.count < _at2559 or (input.merging and _bi2558 < was.method_members.count)) {
                var _c = _changed2544.try_get(_bi2558);
                _f2554.append(_c.is_value() ? _c.value() : was.method_members[_bi2558]);
                _bi2558 += 1;
            }
            _f2554.append(_m_FunctionDef_read(input));
        }
        while (_bi2558 < was.method_members.count) {
            var _c = _changed2544.try_get(_bi2558);
            _f2554.append(_c.is_value() ? _c.value() : was.method_members[_bi2558]);
            _bi2558 += 1;
        }
    } else if (_mode2557 == 3) {
        var _n2555 = input.count();
        for (var _ in 0.._n2555) {
            _f2554.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2555 = input.count();
        if (input.merging) {
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2555) {
            var _tag2556 = input.unsigned();
            if (_tag2556 & 1 == 1) {
                if (!input.merging) {
                    _f2554.append(was.method_members[_tag2556 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2554.append(_read);
                }
            }
        }
    }
    var _f2572 = Array<FunctionDef>();
    var _mode2575 = input.unsigned();
    if (_mode2575 == 2) {
        var _changed2562 = HashMap<ulong, FunctionDef>();
        ulong _bi2576 = 0;
        var _n2573 = input.count();
        for (var _ in 0.._n2573) {
            var _at2577 = input.unsigned();
            while (_f2572.count < _at2577 or (input.merging and _bi2576 < was.generic_methods.count)) {
                var _c = _changed2562.try_get(_bi2576);
                _f2572.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2576]);
                _bi2576 += 1;
            }
            _f2572.append(_m_FunctionDef_read(input));
        }
        while (_bi2576 < was.generic_methods.count) {
            var _c = _changed2562.try_get(_bi2576);
            _f2572.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2576]);
            _bi2576 += 1;
        }
    } else if (_mode2575 == 3) {
        var _n2573 = input.count();
        for (var _ in 0.._n2573) {
            _f2572.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2573 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2573) {
            var _tag2574 = input.unsigned();
            if (_tag2574 & 1 == 1) {
                if (!input.merging) {
                    _f2572.append(was.generic_methods[_tag2574 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2572.append(_read);
                }
            }
        }
    }
    var _f2590 = Array<FunctionDef>();
    var _mode2593 = input.unsigned();
    if (_mode2593 == 2) {
        var _changed2580 = HashMap<ulong, FunctionDef>();
        ulong _bi2594 = 0;
        var _n2591 = input.count();
        for (var _ in 0.._n2591) {
            var _at2595 = input.unsigned();
            while (_f2590.count < _at2595 or (input.merging and _bi2594 < was.constructors.count)) {
                var _c = _changed2580.try_get(_bi2594);
                _f2590.append(_c.is_value() ? _c.value() : was.constructors[_bi2594]);
                _bi2594 += 1;
            }
            _f2590.append(_m_FunctionDef_read(input));
        }
        while (_bi2594 < was.constructors.count) {
            var _c = _changed2580.try_get(_bi2594);
            _f2590.append(_c.is_value() ? _c.value() : was.constructors[_bi2594]);
            _bi2594 += 1;
        }
    } else if (_mode2593 == 3) {
        var _n2591 = input.count();
        for (var _ in 0.._n2591) {
            _f2590.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2591 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2591) {
            var _tag2592 = input.unsigned();
            if (_tag2592 & 1 == 1) {
                if (!input.merging) {
                    _f2590.append(was.constructors[_tag2592 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2590.append(_read);
                }
            }
        }
    }
    var _f2597 = _m_FunctionDef_read(input);
    var _f2598 = _m_FunctionDef_read(input);
    var _f2599 = _m_FunctionDef_read(input);
    var _f2611 = Array<TypeName>();
    var _mode2614 = input.unsigned();
    if (_mode2614 == 2) {
        var _changed2601 = HashMap<ulong, TypeName>();
        ulong _bi2615 = 0;
        var _n2612 = input.count();
        for (var _ in 0.._n2612) {
            var _at2616 = input.unsigned();
            while (_f2611.count < _at2616 or (input.merging and _bi2615 < was.traits.count)) {
                var _c = _changed2601.try_get(_bi2615);
                _f2611.append(_c.is_value() ? _c.value() : was.traits[_bi2615]);
                _bi2615 += 1;
            }
            _f2611.append(_m_TypeName_read(input));
        }
        while (_bi2615 < was.traits.count) {
            var _c = _changed2601.try_get(_bi2615);
            _f2611.append(_c.is_value() ? _c.value() : was.traits[_bi2615]);
            _bi2615 += 1;
        }
    } else if (_mode2614 == 3) {
        var _n2612 = input.count();
        for (var _ in 0.._n2612) {
            _f2611.append(_m_TypeName_read(input));
        }
    } else {
        var _n2612 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2612) {
            var _tag2613 = input.unsigned();
            if (_tag2613 & 1 == 1) {
                if (!input.merging) {
                    _f2611.append(was.traits[_tag2613 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2611.append(_read);
                }
            }
        }
    }
    var _f2629 = Array<ast.Attribute>();
    var _mode2632 = input.unsigned();
    if (_mode2632 == 2) {
        var _changed2619 = HashMap<ulong, ast.Attribute>();
        ulong _bi2633 = 0;
        var _n2630 = input.count();
        for (var _ in 0.._n2630) {
            var _at2634 = input.unsigned();
            while (_f2629.count < _at2634 or (input.merging and _bi2633 < was.attributes.count)) {
                var _c = _changed2619.try_get(_bi2633);
                _f2629.append(_c.is_value() ? _c.value() : was.attributes[_bi2633]);
                _bi2633 += 1;
            }
            _f2629.append(_a_Attribute_read(input));
        }
        while (_bi2633 < was.attributes.count) {
            var _c = _changed2619.try_get(_bi2633);
            _f2629.append(_c.is_value() ? _c.value() : was.attributes[_bi2633]);
            _bi2633 += 1;
        }
    } else if (_mode2632 == 3) {
        var _n2630 = input.count();
        for (var _ in 0.._n2630) {
            _f2629.append(_a_Attribute_read(input));
        }
    } else {
        var _n2630 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2630) {
            var _tag2631 = input.unsigned();
            if (_tag2631 & 1 == 1) {
                if (!input.merging) {
                    _f2629.append(was.attributes[_tag2631 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2629.append(_read);
                }
            }
        }
    }
    var _f2636 = input.loc();
    var _o2638 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2639 = Array<EnumCaseDef>();
        var _n2640 = input.count();
        for (var _ in 0.._n2640) {
            _v2639.append(_m_EnumCaseDef_read(input));
        }
        _o2638 = Optional<Array<EnumCaseDef>>.Value(_v2639);
    }
    var _f2641 = _o2638;
    return StructDef(
        _f2505, _f2506, _f2518, _f2536, _f2554, _f2572, _f2590, _f2597, _f2598, _f2599, _f2611, _f2629, _f2636, _f2641
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    ulong _j2524 = 0;
    for (var _item2507 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2507);
        base.add($"t.{slot}.generic_params", scratch, _j2524);
        _j2524 += 1;
    }
    ulong _j2542 = 0;
    for (var _item2525 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2525);
        base.add($"t.{slot}.field_members", scratch, _j2542);
        _j2542 += 1;
    }
    ulong _j2560 = 0;
    for (var _item2543 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2543);
        base.add($"t.{slot}.method_members", scratch, _j2560);
        _j2560 += 1;
    }
    ulong _j2578 = 0;
    for (var _item2561 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2561);
        base.add($"t.{slot}.generic_methods", scratch, _j2578);
        _j2578 += 1;
    }
    ulong _j2596 = 0;
    for (var _item2579 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2579);
        base.add($"t.{slot}.constructors", scratch, _j2596);
        _j2596 += 1;
    }
    ulong _j2617 = 0;
    for (var _item2600 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2600);
        base.add($"t.{slot}.traits", scratch, _j2617);
        _j2617 += 1;
    }
    ulong _j2635 = 0;
    for (var _item2618 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2618);
        base.add($"t.{slot}.attributes", scratch, _j2635);
        _j2635 += 1;
    }
}

_m_Module_interface_fields(value: Module, interface: bool): Array<(String, String)> {
    var found = Array<(String, String)>();
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.imports.count);
        for (var _item2642 in value.imports) {
            _a_Import_write(out, _item2642);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2643 in value.structs) {
            _m_StructDef_write(out, _item2643);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.traits.count);
        for (var _item2644 in value.traits) {
            _m_TraitDef_write(out, _item2644);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2645 in value.extensions) {
            _m_ExtensionDef_write(out, _item2645);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2646 in value.functions) {
            _m_FunctionDef_write(out, _item2646);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2647 in value.externs) {
            _m_ExternDef_write(out, _item2647);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2648 in value.globals) {
            _m_VariableDef_write(out, _item2648);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2649 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2649);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2650 in value.enums) {
            _m_EnumDef_write(out, _item2650);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2651 in value.struct_specs) {
            _m_TypeName_write(out, _item2651);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2652 in value.func_specs) {
            _m_TypeName_write(out, _item2652);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2653 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2653);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2654 in value.withheld) {
            _m_Withheld_write(out, _item2654);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2655 in value.properties) {
            _m_PropertyDef_write(out, _item2655);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2656 in value.type_uses) {
            _m_TypeUse_write(out, _item2656);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2657 in value.use_contexts) {
            _m_UseContext_write(out, _item2657);
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
            for (var _item2658 in value.literal_args) {
                var (_t2659, _t2660, _t2661) = _item2658;
                out.loc(_t2659);
                out.unsigned(_t2660);
                out.loc(_t2661);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2662 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2662);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2663 in value.trait_types) {
            _m_TraitType_write(out, _item2663);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2664 in value.conversions) {
            _m_Conversion_write(out, _item2664);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2666 = Array<(u8[], u8[], String)>();
        for (var (_key2665, _) in value.overload_sets) {
            var _scratch2667 = out.scratch();
            _scratch2667.text(_key2665);
            var _vscratch2669 = out.scratch();
            _vscratch2669.unsigned(value.overload_sets[_key2665].count);
            for (var _item2670 in value.overload_sets[_key2665]) {
                _vscratch2669.text(_item2670);
            }
            _keys2666.append((_scratch2667.finish(), _vscratch2669.finish(), _key2665));
        }
        _keys2666.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2666.count);
        for (var (_bytes2668, _, _key2665) in _keys2666) {
            out.text(_key2665);
            out.unsigned(value.overload_sets[_key2665].count);
            for (var _item2671 in value.overload_sets[_key2665]) {
                out.text(_item2671);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2673 = Array<(u8[], u8[], String)>();
        for (var (_key2672, _) in value.overload_unions) {
            var _scratch2674 = out.scratch();
            _scratch2674.text(_key2672);
            var _vscratch2676 = out.scratch();
            _vscratch2676.unsigned(value.overload_unions[_key2672].count);
            for (var _item2677 in value.overload_unions[_key2672]) {
                _vscratch2676.unsigned(_item2677.count);
                for (var _item2678 in _item2677) {
                    _vscratch2676.text(_item2678);
                }
            }
            _keys2673.append((_scratch2674.finish(), _vscratch2676.finish(), _key2672));
        }
        _keys2673.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2673.count);
        for (var (_bytes2675, _, _key2672) in _keys2673) {
            out.text(_key2672);
            out.unsigned(value.overload_unions[_key2672].count);
            for (var _item2679 in value.overload_unions[_key2672]) {
                out.unsigned(_item2679.count);
                for (var _item2680 in _item2679) {
                    out.text(_item2680);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2682 = Array<(u8[], u8[], String)>();
        for (var (_key2681, _) in value.method_overload_sets) {
            var _scratch2683 = out.scratch();
            _scratch2683.text(_key2681);
            var _vscratch2685 = out.scratch();
            var _keys2687 = Array<(u8[], u8[], String)>();
            for (var (_key2686, _) in value.method_overload_sets[_key2681]) {
                var _scratch2688 = _vscratch2685.scratch();
                _scratch2688.text(_key2686);
                var _vscratch2690 = _vscratch2685.scratch();
                _vscratch2690.unsigned(value.method_overload_sets[_key2681][_key2686].count);
                for (var _item2691 in value.method_overload_sets[_key2681][_key2686]) {
                    _vscratch2690.text(_item2691);
                }
                _keys2687.append((_scratch2688.finish(), _vscratch2690.finish(), _key2686));
            }
            _keys2687.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2685.unsigned(_keys2687.count);
            for (var (_bytes2689, _, _key2686) in _keys2687) {
                _vscratch2685.text(_key2686);
                _vscratch2685.unsigned(value.method_overload_sets[_key2681][_key2686].count);
                for (var _item2692 in value.method_overload_sets[_key2681][_key2686]) {
                    _vscratch2685.text(_item2692);
                }
            }
            _keys2682.append((_scratch2683.finish(), _vscratch2685.finish(), _key2681));
        }
        _keys2682.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2682.count);
        for (var (_bytes2684, _, _key2681) in _keys2682) {
            out.text(_key2681);
            var _keys2694 = Array<(u8[], u8[], String)>();
            for (var (_key2693, _) in value.method_overload_sets[_key2681]) {
                var _scratch2695 = out.scratch();
                _scratch2695.text(_key2693);
                var _vscratch2697 = out.scratch();
                _vscratch2697.unsigned(value.method_overload_sets[_key2681][_key2693].count);
                for (var _item2698 in value.method_overload_sets[_key2681][_key2693]) {
                    _vscratch2697.text(_item2698);
                }
                _keys2694.append((_scratch2695.finish(), _vscratch2697.finish(), _key2693));
            }
            _keys2694.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2694.count);
            for (var (_bytes2696, _, _key2693) in _keys2694) {
                out.text(_key2693);
                out.unsigned(value.method_overload_sets[_key2681][_key2693].count);
                for (var _item2699 in value.method_overload_sets[_key2681][_key2693]) {
                    out.text(_item2699);
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
        var _keys2701 = Array<(u8[], u8[], Loc)>();
        for (var _key2700 in value.private_functions) {
            var _scratch2702 = out.scratch();
            _scratch2702.loc(_key2700);
            var _vscratch2704 = out.scratch();
            _keys2701.append((_scratch2702.finish(), _vscratch2704.finish(), _key2700));
        }
        _keys2701.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2701.count);
        for (var (_bytes2703, _, _key2700) in _keys2701) {
            out.loc(_key2700);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2706 = Array<(u8[], u8[], Loc)>();
        for (var _key2705 in value.file_private_functions) {
            var _scratch2707 = out.scratch();
            _scratch2707.loc(_key2705);
            var _vscratch2709 = out.scratch();
            _keys2706.append((_scratch2707.finish(), _vscratch2709.finish(), _key2705));
        }
        _keys2706.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2706.count);
        for (var (_bytes2708, _, _key2705) in _keys2706) {
            out.loc(_key2705);
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
            for (var _item2710 in value.call_targets) {
                var (_t2711, _t2712) = _item2710;
                out.loc(_t2711);
                out.text(_t2712);
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
            for (var _item2713 in value.argument_names) {
                var (_t2714, _t2715) = _item2713;
                out.loc(_t2714);
                out.text(_t2715);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2716 in value.namespaces) {
            out.text(_item2716);
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
            for (var _item2717 in value.cached_files) {
                out.flag(_item2717);
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
            var _keys2719 = Array<(u8[], u8[], Loc)>();
            for (var (_key2718, _) in value.recorded_summaries) {
                var _scratch2720 = out.scratch();
                _scratch2720.loc(_key2718);
                var _vscratch2722 = out.scratch();
                _vscratch2722.text(value.recorded_summaries[_key2718]);
                _keys2719.append((_scratch2720.finish(), _vscratch2722.finish(), _key2718));
            }
            _keys2719.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2719.count);
            for (var (_bytes2721, _, _key2718) in _keys2719) {
                out.loc(_key2718);
                out.text(value.recorded_summaries[_key2718]);
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
            var _keys2724 = Array<(u8[], u8[], Loc)>();
            for (var _key2723 in value.stripped) {
                var _scratch2725 = out.scratch();
                _scratch2725.loc(_key2723);
                var _vscratch2727 = out.scratch();
                _keys2724.append((_scratch2725.finish(), _vscratch2727.finish(), _key2723));
            }
            _keys2724.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2724.count);
            for (var (_bytes2726, _, _key2723) in _keys2724) {
                out.loc(_key2723);
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
        var _keys2729 = Array<(u8[], u8[], String)>();
        for (var (_key2728, _) in value.spec_requests) {
            var _scratch2730 = out.scratch();
            _scratch2730.text(_key2728);
            var _vscratch2732 = out.scratch();
            _m_SpecRequest_write(_vscratch2732, value.spec_requests[_key2728]);
            _keys2729.append((_scratch2730.finish(), _vscratch2732.finish(), _key2728));
        }
        _keys2729.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2729.count);
        for (var (_bytes2731, _, _key2728) in _keys2729) {
            out.text(_key2728);
            _m_SpecRequest_write(out, value.spec_requests[_key2728]);
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
            for (var _item2733 in value.summaries_to_record) {
                var (_t2734, _t2735) = _item2733;
                out.loc(_t2734);
                out.text(_t2735);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2737 = Array<(u8[], u8[], String)>();
        for (var (_key2736, _) in value.caller_copies) {
            var _scratch2738 = out.scratch();
            _scratch2738.text(_key2736);
            var _vscratch2740 = out.scratch();
            _vscratch2740.unsigned(value.caller_copies[_key2736].count);
            for (var _item2741 in value.caller_copies[_key2736]) {
                _vscratch2740.flag(_item2741);
            }
            _keys2737.append((_scratch2738.finish(), _vscratch2740.finish(), _key2736));
        }
        _keys2737.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2737.count);
        for (var (_bytes2739, _, _key2736) in _keys2737) {
            out.text(_key2736);
            out.unsigned(value.caller_copies[_key2736].count);
            for (var _item2742 in value.caller_copies[_key2736]) {
                out.flag(_item2742);
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
    for (var _item2743 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2743);
        found.append(("structs " + _item2743.name, interface_text(out)));
    }
    for (var _item2744 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2744);
        found.append(("functions " + _item2744.name, interface_text(out)));
    }
    return found;
}
