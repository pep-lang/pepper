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
    var _hits1481 = HashSet<long>();
    ulong _nj1482 = 0;
    out.unsigned(value.imports.count);
    for (var _item1480 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1480);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("imports", hash);
        next.add_hashed("imports", hash, _nj1482);
        _nj1482 += 1;
        if (at >= 0) {
            _hits1481.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _a_Import_write(out, _item1480);
        }
    }
    base.missed("imports", "imports", _hits1481.count);
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _struct_hits1488 = HashSet<long>();
    ulong _nj1489 = 0;
    out.unsigned(value.structs.count);
    for (var _item1487 in value.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1487);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("s", hash);
        var named = base.named("s", _item1487.name);
        next.add_hashed("s", hash, _nj1489);
        next.name("s", _item1487.name, _nj1489);
        _patch_s_index(_item1487, next, _nj1489);
        _nj1489 += 1;
        ulong _before = out.values.count;
        if (at >= 0) {
            _struct_hits1488.insert(at);
        } else if (named >= 0) {
            _struct_hits1488.insert(named);
        }
        if (at >= 0) {
            out.unsigned((at as ulong) * 2 + 1);
        } else if (named >= 0) {
            out.unsigned(2);
            out.unsigned(named as ulong);
            _patch_s_write(out, _item1487, base, named as ulong);
            base.count("s patched", out.values.count - _before);
        } else {
            out.unsigned(0);
            _m_StructDef_write(out, _item1487);
            base.count("s new", out.values.count - _before);
        }
    }
    base.missed("s", "s", _struct_hits1488.count);
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1495 = HashSet<long>();
    ulong _nj1496 = 0;
    out.unsigned(value.traits.count);
    for (var _item1494 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1494);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("traits", hash);
        next.add_hashed("traits", hash, _nj1496);
        _nj1496 += 1;
        if (at >= 0) {
            _hits1495.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TraitDef_write(out, _item1494);
        }
    }
    base.missed("traits", "traits", _hits1495.count);
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1502 = HashSet<long>();
    ulong _nj1503 = 0;
    out.unsigned(value.extensions.count);
    for (var _item1501 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1501);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("extensions", hash);
        next.add_hashed("extensions", hash, _nj1503);
        _nj1503 += 1;
        if (at >= 0) {
            _hits1502.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_ExtensionDef_write(out, _item1501);
        }
    }
    base.missed("extensions", "extensions", _hits1502.count);
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1509 = HashSet<long>();
    ulong _nj1510 = 0;
    out.unsigned(value.functions.count);
    for (var _item1508 in value.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1508);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("functions", hash);
        next.add_hashed("functions", hash, _nj1510);
        _nj1510 += 1;
        if (at >= 0) {
            _hits1509.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item1508);
        }
    }
    base.missed("functions", "functions", _hits1509.count);
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1516 = HashSet<long>();
    ulong _nj1517 = 0;
    out.unsigned(value.externs.count);
    for (var _item1515 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1515);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("externs", hash);
        next.add_hashed("externs", hash, _nj1517);
        _nj1517 += 1;
        if (at >= 0) {
            _hits1516.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_ExternDef_write(out, _item1515);
        }
    }
    base.missed("externs", "externs", _hits1516.count);
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1523 = HashSet<long>();
    ulong _nj1524 = 0;
    out.unsigned(value.globals.count);
    for (var _item1522 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1522);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("globals", hash);
        next.add_hashed("globals", hash, _nj1524);
        _nj1524 += 1;
        if (at >= 0) {
            _hits1523.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_VariableDef_write(out, _item1522);
        }
    }
    base.missed("globals", "globals", _hits1523.count);
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1530 = HashSet<long>();
    ulong _nj1531 = 0;
    out.unsigned(value.static_blocks.count);
    for (var _item1529 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1529);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("static_blocks", hash);
        next.add_hashed("static_blocks", hash, _nj1531);
        _nj1531 += 1;
        if (at >= 0) {
            _hits1530.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_ModuleStaticBlock_write(out, _item1529);
        }
    }
    base.missed("static_blocks", "static_blocks", _hits1530.count);
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1537 = HashSet<long>();
    ulong _nj1538 = 0;
    out.unsigned(value.enums.count);
    for (var _item1536 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1536);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("enums", hash);
        next.add_hashed("enums", hash, _nj1538);
        _nj1538 += 1;
        if (at >= 0) {
            _hits1537.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_EnumDef_write(out, _item1536);
        }
    }
    base.missed("enums", "enums", _hits1537.count);
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1544 = HashSet<long>();
    ulong _nj1545 = 0;
    out.unsigned(value.struct_specs.count);
    for (var _item1543 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1543);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("struct_specs", hash);
        next.add_hashed("struct_specs", hash, _nj1545);
        _nj1545 += 1;
        if (at >= 0) {
            _hits1544.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeName_write(out, _item1543);
        }
    }
    base.missed("struct_specs", "struct_specs", _hits1544.count);
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1551 = HashSet<long>();
    ulong _nj1552 = 0;
    out.unsigned(value.func_specs.count);
    for (var _item1550 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1550);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("func_specs", hash);
        next.add_hashed("func_specs", hash, _nj1552);
        _nj1552 += 1;
        if (at >= 0) {
            _hits1551.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeName_write(out, _item1550);
        }
    }
    base.missed("func_specs", "func_specs", _hits1551.count);
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1558 = HashSet<long>();
    ulong _nj1559 = 0;
    out.unsigned(value.type_aliases.count);
    for (var _item1557 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1557);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1558.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1557);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1558.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1565 = HashSet<long>();
    ulong _nj1566 = 0;
    out.unsigned(value.withheld.count);
    for (var _item1564 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1564);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("withheld", hash);
        next.add_hashed("withheld", hash, _nj1566);
        _nj1566 += 1;
        if (at >= 0) {
            _hits1565.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_Withheld_write(out, _item1564);
        }
    }
    base.missed("withheld", "withheld", _hits1565.count);
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1572 = HashSet<long>();
    ulong _nj1573 = 0;
    out.unsigned(value.properties.count);
    for (var _item1571 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1571);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("properties", hash);
        next.add_hashed("properties", hash, _nj1573);
        _nj1573 += 1;
        if (at >= 0) {
            _hits1572.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_PropertyDef_write(out, _item1571);
        }
    }
    base.missed("properties", "properties", _hits1572.count);
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1579 = HashSet<long>();
    ulong _nj1580 = 0;
    out.unsigned(value.type_uses.count);
    for (var _item1578 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1578);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_uses", hash);
        next.add_hashed("type_uses", hash, _nj1580);
        _nj1580 += 1;
        if (at >= 0) {
            _hits1579.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeUse_write(out, _item1578);
        }
    }
    base.missed("type_uses", "type_uses", _hits1579.count);
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1586 = HashSet<long>();
    ulong _nj1587 = 0;
    out.unsigned(value.use_contexts.count);
    for (var _item1585 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1585);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("use_contexts", hash);
        next.add_hashed("use_contexts", hash, _nj1587);
        _nj1587 += 1;
        if (at >= 0) {
            _hits1586.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_UseContext_write(out, _item1585);
        }
    }
    base.missed("use_contexts", "use_contexts", _hits1586.count);
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1594 = base.size("literal_args");
    var _scratch1593 = base.scratch();
    if (value.literal_args.count >= _n1594) {
        for (var _i1595 in 0.._n1594) {
            var (_t1596, _t1597, _t1598) = value.literal_args[_i1595];
            _scratch1593.loc(_t1596);
            _scratch1593.unsigned(_t1597);
            _scratch1593.loc(_t1598);
        }
    }
    if (value.literal_args.count >= _n1594 and base.same_list("literal_args", _scratch1593)) {
        out.unsigned(1);
        out.unsigned(_n1594);
        out.unsigned(value.literal_args.count - _n1594);
        for (var _i1595 in _n1594..value.literal_args.count) {
            var (_t1599, _t1600, _t1601) = value.literal_args[_i1595];
            out.loc(_t1599);
            out.unsigned(_t1600);
            out.loc(_t1601);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1602 in value.literal_args) {
            var (_t1603, _t1604, _t1605) = _item1602;
            out.loc(_t1603);
            out.unsigned(_t1604);
            out.loc(_t1605);
        }
        base.count("literal_args whole", 0);
    }
    var _xscratch1618 = next.scratch();
    for (var _xitem1619 in value.literal_args) {
        var (_t1620, _t1621, _t1622) = _xitem1619;
        _xscratch1618.loc(_t1620);
        _xscratch1618.unsigned(_t1621);
        _xscratch1618.loc(_t1622);
    }
    next.keep_list("literal_args", value.literal_args.count, _xscratch1618);
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1624 = HashSet<long>();
    ulong _nj1625 = 0;
    out.unsigned(value.constrained_aliases.count);
    for (var _item1623 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1623);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("constrained_aliases", hash);
        next.add_hashed("constrained_aliases", hash, _nj1625);
        _nj1625 += 1;
        if (at >= 0) {
            _hits1624.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1623);
        }
    }
    base.missed("constrained_aliases", "constrained_aliases", _hits1624.count);
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1631 = HashSet<long>();
    ulong _nj1632 = 0;
    out.unsigned(value.trait_types.count);
    for (var _item1630 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1630);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("trait_types", hash);
        next.add_hashed("trait_types", hash, _nj1632);
        _nj1632 += 1;
        if (at >= 0) {
            _hits1631.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TraitType_write(out, _item1630);
        }
    }
    base.missed("trait_types", "trait_types", _hits1631.count);
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1638 = HashSet<long>();
    ulong _nj1639 = 0;
    out.unsigned(value.conversions.count);
    for (var _item1637 in value.conversions) {
        var scratch = base.scratch();
        _m_Conversion_write(scratch, _item1637);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("conversions", hash);
        next.add_hashed("conversions", hash, _nj1639);
        _nj1639 += 1;
        if (at >= 0) {
            _hits1638.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_Conversion_write(out, _item1637);
        }
    }
    base.missed("conversions", "conversions", _hits1638.count);
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1647 = 0;
    var _news1648 = Map<String, Array<String>>();
    for (var (_key1644, _) in value.overload_sets) {
        var _kscratch1645 = base.scratch();
        _kscratch1645.text(_key1644);
        var _vscratch1646 = base.scratch();
        _vscratch1646.unsigned(value.overload_sets[_key1644].count);
        for (var _item1649 in value.overload_sets[_key1644]) {
            _vscratch1646.text(_item1649);
        }
        var _had = base.entry("overload_sets", _kscratch1645, _vscratch1646);
        if (_had >= 0) {
            _kept1647 += 1;
        }
        if (_had != 1) {
            _news1648[_key1644] = value.overload_sets[_key1644];
        }
    }
    if (_kept1647 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1651 = Array<(u8[], u8[], String)>();
        for (var (_key1650, _) in _news1648) {
            var _scratch1652 = out.scratch();
            _scratch1652.text(_key1650);
            var _vscratch1654 = out.scratch();
            _vscratch1654.unsigned(_news1648[_key1650].count);
            for (var _item1655 in _news1648[_key1650]) {
                _vscratch1654.text(_item1655);
            }
            _keys1651.append((_scratch1652.finish(), _vscratch1654.finish(), _key1650));
        }
        _keys1651.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1651.count);
        for (var (_bytes1653, _, _key1650) in _keys1651) {
            out.text(_key1650);
            out.unsigned(_news1648[_key1650].count);
            for (var _item1656 in _news1648[_key1650]) {
                out.text(_item1656);
            }
        }
    } else {
        out.unsigned(0);
        var _keys1658 = Array<(u8[], u8[], String)>();
        for (var (_key1657, _) in value.overload_sets) {
            var _scratch1659 = out.scratch();
            _scratch1659.text(_key1657);
            var _vscratch1661 = out.scratch();
            _vscratch1661.unsigned(value.overload_sets[_key1657].count);
            for (var _item1662 in value.overload_sets[_key1657]) {
                _vscratch1661.text(_item1662);
            }
            _keys1658.append((_scratch1659.finish(), _vscratch1661.finish(), _key1657));
        }
        _keys1658.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1658.count);
        for (var (_bytes1660, _, _key1657) in _keys1658) {
            out.text(_key1657);
            out.unsigned(value.overload_sets[_key1657].count);
            for (var _item1663 in value.overload_sets[_key1657]) {
                out.text(_item1663);
            }
        }
        base.count("overload_sets whole", 0);
    }
    for (var (_key1644, _) in value.overload_sets) {
        var _kscratch1645 = next.scratch();
        _kscratch1645.text(_key1644);
        var _vscratch1646 = next.scratch();
        _vscratch1646.unsigned(value.overload_sets[_key1644].count);
        for (var _item1677 in value.overload_sets[_key1644]) {
            _vscratch1646.text(_item1677);
        }
        next.keep_entry("overload_sets", _kscratch1645, _vscratch1646);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1681 = 0;
    var _news1682 = Map<String, Array<Array<String>>>();
    for (var (_key1678, _) in value.overload_unions) {
        var _kscratch1679 = base.scratch();
        _kscratch1679.text(_key1678);
        var _vscratch1680 = base.scratch();
        _vscratch1680.unsigned(value.overload_unions[_key1678].count);
        for (var _item1683 in value.overload_unions[_key1678]) {
            _vscratch1680.unsigned(_item1683.count);
            for (var _item1684 in _item1683) {
                _vscratch1680.text(_item1684);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1679, _vscratch1680);
        if (_had >= 0) {
            _kept1681 += 1;
        }
        if (_had != 1) {
            _news1682[_key1678] = value.overload_unions[_key1678];
        }
    }
    if (_kept1681 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1686 = Array<(u8[], u8[], String)>();
        for (var (_key1685, _) in _news1682) {
            var _scratch1687 = out.scratch();
            _scratch1687.text(_key1685);
            var _vscratch1689 = out.scratch();
            _vscratch1689.unsigned(_news1682[_key1685].count);
            for (var _item1690 in _news1682[_key1685]) {
                _vscratch1689.unsigned(_item1690.count);
                for (var _item1691 in _item1690) {
                    _vscratch1689.text(_item1691);
                }
            }
            _keys1686.append((_scratch1687.finish(), _vscratch1689.finish(), _key1685));
        }
        _keys1686.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1686.count);
        for (var (_bytes1688, _, _key1685) in _keys1686) {
            out.text(_key1685);
            out.unsigned(_news1682[_key1685].count);
            for (var _item1692 in _news1682[_key1685]) {
                out.unsigned(_item1692.count);
                for (var _item1693 in _item1692) {
                    out.text(_item1693);
                }
            }
        }
    } else {
        out.unsigned(0);
        var _keys1695 = Array<(u8[], u8[], String)>();
        for (var (_key1694, _) in value.overload_unions) {
            var _scratch1696 = out.scratch();
            _scratch1696.text(_key1694);
            var _vscratch1698 = out.scratch();
            _vscratch1698.unsigned(value.overload_unions[_key1694].count);
            for (var _item1699 in value.overload_unions[_key1694]) {
                _vscratch1698.unsigned(_item1699.count);
                for (var _item1700 in _item1699) {
                    _vscratch1698.text(_item1700);
                }
            }
            _keys1695.append((_scratch1696.finish(), _vscratch1698.finish(), _key1694));
        }
        _keys1695.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1695.count);
        for (var (_bytes1697, _, _key1694) in _keys1695) {
            out.text(_key1694);
            out.unsigned(value.overload_unions[_key1694].count);
            for (var _item1701 in value.overload_unions[_key1694]) {
                out.unsigned(_item1701.count);
                for (var _item1702 in _item1701) {
                    out.text(_item1702);
                }
            }
        }
        base.count("overload_unions whole", 0);
    }
    for (var (_key1678, _) in value.overload_unions) {
        var _kscratch1679 = next.scratch();
        _kscratch1679.text(_key1678);
        var _vscratch1680 = next.scratch();
        _vscratch1680.unsigned(value.overload_unions[_key1678].count);
        for (var _item1720 in value.overload_unions[_key1678]) {
            _vscratch1680.unsigned(_item1720.count);
            for (var _item1721 in _item1720) {
                _vscratch1680.text(_item1721);
            }
        }
        next.keep_entry("overload_unions", _kscratch1679, _vscratch1680);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1725 = 0;
    var _news1726 = Map<String, Map<String, Array<String>>>();
    for (var (_key1722, _) in value.method_overload_sets) {
        var _kscratch1723 = base.scratch();
        _kscratch1723.text(_key1722);
        var _vscratch1724 = base.scratch();
        var _keys1728 = Array<(u8[], u8[], String)>();
        for (var (_key1727, _) in value.method_overload_sets[_key1722]) {
            var _scratch1729 = _vscratch1724.scratch();
            _scratch1729.text(_key1727);
            var _vscratch1731 = _vscratch1724.scratch();
            _vscratch1731.unsigned(value.method_overload_sets[_key1722][_key1727].count);
            for (var _item1732 in value.method_overload_sets[_key1722][_key1727]) {
                _vscratch1731.text(_item1732);
            }
            _keys1728.append((_scratch1729.finish(), _vscratch1731.finish(), _key1727));
        }
        _keys1728.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1724.unsigned(_keys1728.count);
        for (var (_bytes1730, _, _key1727) in _keys1728) {
            _vscratch1724.text(_key1727);
            _vscratch1724.unsigned(value.method_overload_sets[_key1722][_key1727].count);
            for (var _item1733 in value.method_overload_sets[_key1722][_key1727]) {
                _vscratch1724.text(_item1733);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1723, _vscratch1724);
        if (_had >= 0) {
            _kept1725 += 1;
        }
        if (_had != 1) {
            _news1726[_key1722] = value.method_overload_sets[_key1722];
        }
    }
    if (_kept1725 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1735 = Array<(u8[], u8[], String)>();
        for (var (_key1734, _) in _news1726) {
            var _scratch1736 = out.scratch();
            _scratch1736.text(_key1734);
            var _vscratch1738 = out.scratch();
            var _keys1740 = Array<(u8[], u8[], String)>();
            for (var (_key1739, _) in _news1726[_key1734]) {
                var _scratch1741 = _vscratch1738.scratch();
                _scratch1741.text(_key1739);
                var _vscratch1743 = _vscratch1738.scratch();
                _vscratch1743.unsigned(_news1726[_key1734][_key1739].count);
                for (var _item1744 in _news1726[_key1734][_key1739]) {
                    _vscratch1743.text(_item1744);
                }
                _keys1740.append((_scratch1741.finish(), _vscratch1743.finish(), _key1739));
            }
            _keys1740.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1738.unsigned(_keys1740.count);
            for (var (_bytes1742, _, _key1739) in _keys1740) {
                _vscratch1738.text(_key1739);
                _vscratch1738.unsigned(_news1726[_key1734][_key1739].count);
                for (var _item1745 in _news1726[_key1734][_key1739]) {
                    _vscratch1738.text(_item1745);
                }
            }
            _keys1735.append((_scratch1736.finish(), _vscratch1738.finish(), _key1734));
        }
        _keys1735.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1735.count);
        for (var (_bytes1737, _, _key1734) in _keys1735) {
            out.text(_key1734);
            var _keys1747 = Array<(u8[], u8[], String)>();
            for (var (_key1746, _) in _news1726[_key1734]) {
                var _scratch1748 = out.scratch();
                _scratch1748.text(_key1746);
                var _vscratch1750 = out.scratch();
                _vscratch1750.unsigned(_news1726[_key1734][_key1746].count);
                for (var _item1751 in _news1726[_key1734][_key1746]) {
                    _vscratch1750.text(_item1751);
                }
                _keys1747.append((_scratch1748.finish(), _vscratch1750.finish(), _key1746));
            }
            _keys1747.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1747.count);
            for (var (_bytes1749, _, _key1746) in _keys1747) {
                out.text(_key1746);
                out.unsigned(_news1726[_key1734][_key1746].count);
                for (var _item1752 in _news1726[_key1734][_key1746]) {
                    out.text(_item1752);
                }
            }
        }
    } else {
        out.unsigned(0);
        var _keys1754 = Array<(u8[], u8[], String)>();
        for (var (_key1753, _) in value.method_overload_sets) {
            var _scratch1755 = out.scratch();
            _scratch1755.text(_key1753);
            var _vscratch1757 = out.scratch();
            var _keys1759 = Array<(u8[], u8[], String)>();
            for (var (_key1758, _) in value.method_overload_sets[_key1753]) {
                var _scratch1760 = _vscratch1757.scratch();
                _scratch1760.text(_key1758);
                var _vscratch1762 = _vscratch1757.scratch();
                _vscratch1762.unsigned(value.method_overload_sets[_key1753][_key1758].count);
                for (var _item1763 in value.method_overload_sets[_key1753][_key1758]) {
                    _vscratch1762.text(_item1763);
                }
                _keys1759.append((_scratch1760.finish(), _vscratch1762.finish(), _key1758));
            }
            _keys1759.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1757.unsigned(_keys1759.count);
            for (var (_bytes1761, _, _key1758) in _keys1759) {
                _vscratch1757.text(_key1758);
                _vscratch1757.unsigned(value.method_overload_sets[_key1753][_key1758].count);
                for (var _item1764 in value.method_overload_sets[_key1753][_key1758]) {
                    _vscratch1757.text(_item1764);
                }
            }
            _keys1754.append((_scratch1755.finish(), _vscratch1757.finish(), _key1753));
        }
        _keys1754.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1754.count);
        for (var (_bytes1756, _, _key1753) in _keys1754) {
            out.text(_key1753);
            var _keys1766 = Array<(u8[], u8[], String)>();
            for (var (_key1765, _) in value.method_overload_sets[_key1753]) {
                var _scratch1767 = out.scratch();
                _scratch1767.text(_key1765);
                var _vscratch1769 = out.scratch();
                _vscratch1769.unsigned(value.method_overload_sets[_key1753][_key1765].count);
                for (var _item1770 in value.method_overload_sets[_key1753][_key1765]) {
                    _vscratch1769.text(_item1770);
                }
                _keys1766.append((_scratch1767.finish(), _vscratch1769.finish(), _key1765));
            }
            _keys1766.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1766.count);
            for (var (_bytes1768, _, _key1765) in _keys1766) {
                out.text(_key1765);
                out.unsigned(value.method_overload_sets[_key1753][_key1765].count);
                for (var _item1771 in value.method_overload_sets[_key1753][_key1765]) {
                    out.text(_item1771);
                }
            }
        }
        base.count("method_overload_sets whole", 0);
    }
    for (var (_key1722, _) in value.method_overload_sets) {
        var _kscratch1723 = next.scratch();
        _kscratch1723.text(_key1722);
        var _vscratch1724 = next.scratch();
        var _keys1792 = Array<(u8[], u8[], String)>();
        for (var (_key1791, _) in value.method_overload_sets[_key1722]) {
            var _scratch1793 = _vscratch1724.scratch();
            _scratch1793.text(_key1791);
            var _vscratch1795 = _vscratch1724.scratch();
            _vscratch1795.unsigned(value.method_overload_sets[_key1722][_key1791].count);
            for (var _item1796 in value.method_overload_sets[_key1722][_key1791]) {
                _vscratch1795.text(_item1796);
            }
            _keys1792.append((_scratch1793.finish(), _vscratch1795.finish(), _key1791));
        }
        _keys1792.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1724.unsigned(_keys1792.count);
        for (var (_bytes1794, _, _key1791) in _keys1792) {
            _vscratch1724.text(_key1791);
            _vscratch1724.unsigned(value.method_overload_sets[_key1722][_key1791].count);
            for (var _item1797 in value.method_overload_sets[_key1722][_key1791]) {
                _vscratch1724.text(_item1797);
            }
        }
        next.keep_entry("method_overload_sets", _kscratch1723, _vscratch1724);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1802 = 0;
    var _news1803 = HashSet<Loc>();
    for (var _key1799 in value.private_functions) {
        var _kscratch1800 = base.scratch();
        _kscratch1800.loc(_key1799);
        var _vscratch1801 = base.scratch();
        var _had = base.entry("private_functions", _kscratch1800, _vscratch1801);
        if (_had >= 0) {
            _kept1802 += 1;
        }
        if (_had != 1) {
            _news1803.insert(_key1799);
        }
    }
    if (_kept1802 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys1805 = Array<(u8[], u8[], Loc)>();
        for (var _key1804 in _news1803) {
            var _scratch1806 = out.scratch();
            _scratch1806.loc(_key1804);
            var _vscratch1808 = out.scratch();
            _keys1805.append((_scratch1806.finish(), _vscratch1808.finish(), _key1804));
        }
        _keys1805.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1805.count);
        for (var (_bytes1807, _, _key1804) in _keys1805) {
            out.loc(_key1804);
        }
    } else {
        out.unsigned(0);
        var _keys1810 = Array<(u8[], u8[], Loc)>();
        for (var _key1809 in value.private_functions) {
            var _scratch1811 = out.scratch();
            _scratch1811.loc(_key1809);
            var _vscratch1813 = out.scratch();
            _keys1810.append((_scratch1811.finish(), _vscratch1813.finish(), _key1809));
        }
        _keys1810.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1810.count);
        for (var (_bytes1812, _, _key1809) in _keys1810) {
            out.loc(_key1809);
        }
        base.count("private_functions whole", 0);
    }
    for (var _key1799 in value.private_functions) {
        var _kscratch1800 = next.scratch();
        _kscratch1800.loc(_key1799);
        var _vscratch1801 = next.scratch();
        next.keep_entry("private_functions", _kscratch1800, _vscratch1801);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1824 = 0;
    var _news1825 = HashSet<Loc>();
    for (var _key1821 in value.file_private_functions) {
        var _kscratch1822 = base.scratch();
        _kscratch1822.loc(_key1821);
        var _vscratch1823 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch1822, _vscratch1823);
        if (_had >= 0) {
            _kept1824 += 1;
        }
        if (_had != 1) {
            _news1825.insert(_key1821);
        }
    }
    if (_kept1824 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys1827 = Array<(u8[], u8[], Loc)>();
        for (var _key1826 in _news1825) {
            var _scratch1828 = out.scratch();
            _scratch1828.loc(_key1826);
            var _vscratch1830 = out.scratch();
            _keys1827.append((_scratch1828.finish(), _vscratch1830.finish(), _key1826));
        }
        _keys1827.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1827.count);
        for (var (_bytes1829, _, _key1826) in _keys1827) {
            out.loc(_key1826);
        }
    } else {
        out.unsigned(0);
        var _keys1832 = Array<(u8[], u8[], Loc)>();
        for (var _key1831 in value.file_private_functions) {
            var _scratch1833 = out.scratch();
            _scratch1833.loc(_key1831);
            var _vscratch1835 = out.scratch();
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
            out.loc(_key1831);
        }
        base.count("file_private_functions whole", 0);
    }
    for (var _key1821 in value.file_private_functions) {
        var _kscratch1822 = next.scratch();
        _kscratch1822.loc(_key1821);
        var _vscratch1823 = next.scratch();
        next.keep_entry("file_private_functions", _kscratch1822, _vscratch1823);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n1845 = base.size("call_targets");
    var _scratch1844 = base.scratch();
    if (value.call_targets.count >= _n1845) {
        for (var _i1846 in 0.._n1845) {
            var (_t1847, _t1848) = value.call_targets[_i1846];
            _scratch1844.loc(_t1847);
            _scratch1844.text(_t1848);
        }
    }
    if (value.call_targets.count >= _n1845 and base.same_list("call_targets", _scratch1844)) {
        out.unsigned(1);
        out.unsigned(_n1845);
        out.unsigned(value.call_targets.count - _n1845);
        for (var _i1846 in _n1845..value.call_targets.count) {
            var (_t1849, _t1850) = value.call_targets[_i1846];
            out.loc(_t1849);
            out.text(_t1850);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item1851 in value.call_targets) {
            var (_t1852, _t1853) = _item1851;
            out.loc(_t1852);
            out.text(_t1853);
        }
        base.count("call_targets whole", 0);
    }
    var _xscratch1864 = next.scratch();
    for (var _xitem1865 in value.call_targets) {
        var (_t1866, _t1867) = _xitem1865;
        _xscratch1864.loc(_t1866);
        _xscratch1864.text(_t1867);
    }
    next.keep_list("call_targets", value.call_targets.count, _xscratch1864);
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1870 = 0;
    var _news1871 = Array<(Loc, String)>();
    for (var _item1868 in value.argument_names) {
        var _escratch1869 = base.scratch();
        var (_t1872, _t1873) = _item1868;
        _escratch1869.loc(_t1872);
        _escratch1869.text(_t1873);
        if (base.entry("argument_names", _escratch1869, base.scratch()) >= 0) {
            _kept1870 += 1;
        } else {
            _news1871.append(_item1868);
        }
    }
    if (_kept1870 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news1871.count);
        for (var _item1874 in _news1871) {
            var (_t1875, _t1876) = _item1874;
            out.loc(_t1875);
            out.text(_t1876);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item1877 in value.argument_names) {
            var (_t1878, _t1879) = _item1877;
            out.loc(_t1878);
            out.text(_t1879);
        }
        base.count("argument_names whole", 0);
    }
    for (var _item1868 in value.argument_names) {
        var _escratch1869 = next.scratch();
        var (_t1890, _t1891) = _item1868;
        _escratch1869.loc(_t1890);
        _escratch1869.text(_t1891);
        next.keep_entry("argument_names", _escratch1869, next.scratch());
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n1894 = base.size("namespaces");
    var _scratch1893 = base.scratch();
    if (value.namespaces.count >= _n1894) {
        for (var _i1895 in 0.._n1894) {
            _scratch1893.text(value.namespaces[_i1895]);
        }
    }
    if (value.namespaces.count >= _n1894 and base.same_list("namespaces", _scratch1893)) {
        out.unsigned(1);
        out.unsigned(_n1894);
        out.unsigned(value.namespaces.count - _n1894);
        for (var _i1895 in _n1894..value.namespaces.count) {
            out.text(value.namespaces[_i1895]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item1896 in value.namespaces) {
            out.text(_item1896);
        }
        base.count("namespaces whole", 0);
    }
    var _xscratch1903 = next.scratch();
    for (var _xitem1904 in value.namespaces) {
        _xscratch1903.text(_xitem1904);
    }
    next.keep_list("namespaces", value.namespaces.count, _xscratch1903);
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n1907 = base.size("cached_files");
    var _scratch1906 = base.scratch();
    if (value.cached_files.count >= _n1907) {
        for (var _i1908 in 0.._n1907) {
            _scratch1906.flag(value.cached_files[_i1908]);
        }
    }
    if (value.cached_files.count >= _n1907 and base.same_list("cached_files", _scratch1906)) {
        out.unsigned(1);
        out.unsigned(_n1907);
        out.unsigned(value.cached_files.count - _n1907);
        for (var _i1908 in _n1907..value.cached_files.count) {
            out.flag(value.cached_files[_i1908]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item1909 in value.cached_files) {
            out.flag(_item1909);
        }
        base.count("cached_files whole", 0);
    }
    var _xscratch1916 = next.scratch();
    for (var _xitem1917 in value.cached_files) {
        _xscratch1916.flag(_xitem1917);
    }
    next.keep_list("cached_files", value.cached_files.count, _xscratch1916);
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1921 = 0;
    var _news1922 = HashMap<Loc, String>();
    for (var (_key1918, _) in value.recorded_summaries) {
        var _kscratch1919 = base.scratch();
        _kscratch1919.loc(_key1918);
        var _vscratch1920 = base.scratch();
        _vscratch1920.text(value.recorded_summaries[_key1918]);
        var _had = base.entry("recorded_summaries", _kscratch1919, _vscratch1920);
        if (_had >= 0) {
            _kept1921 += 1;
        }
        if (_had != 1) {
            _news1922[_key1918] = value.recorded_summaries[_key1918];
        }
    }
    if (_kept1921 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys1924 = Array<(u8[], u8[], Loc)>();
        for (var (_key1923, _) in _news1922) {
            var _scratch1925 = out.scratch();
            _scratch1925.loc(_key1923);
            var _vscratch1927 = out.scratch();
            _vscratch1927.text(_news1922[_key1923]);
            _keys1924.append((_scratch1925.finish(), _vscratch1927.finish(), _key1923));
        }
        _keys1924.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1924.count);
        for (var (_bytes1926, _, _key1923) in _keys1924) {
            out.loc(_key1923);
            out.text(_news1922[_key1923]);
        }
    } else {
        out.unsigned(0);
        var _keys1929 = Array<(u8[], u8[], Loc)>();
        for (var (_key1928, _) in value.recorded_summaries) {
            var _scratch1930 = out.scratch();
            _scratch1930.loc(_key1928);
            var _vscratch1932 = out.scratch();
            _vscratch1932.text(value.recorded_summaries[_key1928]);
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
            out.loc(_key1928);
            out.text(value.recorded_summaries[_key1928]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1945 = 0;
    var _news1946 = HashSet<Loc>();
    for (var _key1942 in value.stripped) {
        var _kscratch1943 = base.scratch();
        _kscratch1943.loc(_key1942);
        var _vscratch1944 = base.scratch();
        var _had = base.entry("stripped", _kscratch1943, _vscratch1944);
        if (_had >= 0) {
            _kept1945 += 1;
        }
        if (_had != 1) {
            _news1946.insert(_key1942);
        }
    }
    if (_kept1945 == base.size("stripped")) {
        out.unsigned(1);
        var _keys1948 = Array<(u8[], u8[], Loc)>();
        for (var _key1947 in _news1946) {
            var _scratch1949 = out.scratch();
            _scratch1949.loc(_key1947);
            var _vscratch1951 = out.scratch();
            _keys1948.append((_scratch1949.finish(), _vscratch1951.finish(), _key1947));
        }
        _keys1948.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1948.count);
        for (var (_bytes1950, _, _key1947) in _keys1948) {
            out.loc(_key1947);
        }
    } else {
        out.unsigned(0);
        var _keys1953 = Array<(u8[], u8[], Loc)>();
        for (var _key1952 in value.stripped) {
            var _scratch1954 = out.scratch();
            _scratch1954.loc(_key1952);
            var _vscratch1956 = out.scratch();
            _keys1953.append((_scratch1954.finish(), _vscratch1956.finish(), _key1952));
        }
        _keys1953.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1953.count);
        for (var (_bytes1955, _, _key1952) in _keys1953) {
            out.loc(_key1952);
        }
        base.count("stripped whole", 0);
    }
    for (var _key1942 in value.stripped) {
        var _kscratch1943 = next.scratch();
        _kscratch1943.loc(_key1942);
        var _vscratch1944 = next.scratch();
        next.keep_entry("stripped", _kscratch1943, _vscratch1944);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _struct_hits1965 = HashSet<long>();
    ulong _nj1966 = 0;
    out.unsigned(value.templates.structs.count);
    for (var _item1964 in value.templates.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1964);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("t", hash);
        var named = base.named("t", _item1964.name);
        next.add_hashed("t", hash, _nj1966);
        next.name("t", _item1964.name, _nj1966);
        _patch_t_index(_item1964, next, _nj1966);
        _nj1966 += 1;
        ulong _before = out.values.count;
        if (at >= 0) {
            _struct_hits1965.insert(at);
        } else if (named >= 0) {
            _struct_hits1965.insert(named);
        }
        if (at >= 0) {
            out.unsigned((at as ulong) * 2 + 1);
        } else if (named >= 0) {
            out.unsigned(2);
            out.unsigned(named as ulong);
            _patch_t_write(out, _item1964, base, named as ulong);
            base.count("t patched", out.values.count - _before);
        } else {
            out.unsigned(0);
            _m_StructDef_write(out, _item1964);
            base.count("t new", out.values.count - _before);
        }
    }
    base.missed("t", "t", _struct_hits1965.count);
    var _hits1972 = HashSet<long>();
    ulong _nj1973 = 0;
    out.unsigned(value.templates.functions.count);
    for (var _item1971 in value.templates.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1971);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("tf", hash);
        next.add_hashed("tf", hash, _nj1973);
        _nj1973 += 1;
        if (at >= 0) {
            _hits1972.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item1971);
        }
    }
    base.missed("tf", "tf", _hits1972.count);
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    next.keep_checked(value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1983 = 0;
    var _news1984 = HashMap<String, SpecRequest>();
    for (var (_key1980, _) in value.spec_requests) {
        var _kscratch1981 = base.scratch();
        _kscratch1981.text(_key1980);
        var _vscratch1982 = base.scratch();
        _m_SpecRequest_write(_vscratch1982, value.spec_requests[_key1980]);
        var _had = base.entry("spec_requests", _kscratch1981, _vscratch1982);
        if (_had >= 0) {
            _kept1983 += 1;
        }
        if (_had != 1) {
            _news1984[_key1980] = value.spec_requests[_key1980];
        }
    }
    if (_kept1983 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys1986 = Array<(u8[], u8[], String)>();
        for (var (_key1985, _) in _news1984) {
            var _scratch1987 = out.scratch();
            _scratch1987.text(_key1985);
            var _vscratch1989 = out.scratch();
            _m_SpecRequest_write(_vscratch1989, _news1984[_key1985]);
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
            _m_SpecRequest_write(out, _news1984[_key1985]);
        }
    } else {
        out.unsigned(0);
        var _keys1991 = Array<(u8[], u8[], String)>();
        for (var (_key1990, _) in value.spec_requests) {
            var _scratch1992 = out.scratch();
            _scratch1992.text(_key1990);
            var _vscratch1994 = out.scratch();
            _m_SpecRequest_write(_vscratch1994, value.spec_requests[_key1990]);
            _keys1991.append((_scratch1992.finish(), _vscratch1994.finish(), _key1990));
        }
        _keys1991.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1991.count);
        for (var (_bytes1993, _, _key1990) in _keys1991) {
            out.text(_key1990);
            _m_SpecRequest_write(out, value.spec_requests[_key1990]);
        }
        base.count("spec_requests whole", 0);
    }
    for (var (_key1980, _) in value.spec_requests) {
        var _kscratch1981 = next.scratch();
        _kscratch1981.text(_key1980);
        var _vscratch1982 = next.scratch();
        _m_SpecRequest_write(_vscratch1982, value.spec_requests[_key1980]);
        next.keep_entry("spec_requests", _kscratch1981, _vscratch1982);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2007 = base.size("summaries_to_record");
    var _scratch2006 = base.scratch();
    if (value.summaries_to_record.count >= _n2007) {
        for (var _i2008 in 0.._n2007) {
            var (_t2009, _t2010) = value.summaries_to_record[_i2008];
            _scratch2006.loc(_t2009);
            _scratch2006.text(_t2010);
        }
    }
    if (value.summaries_to_record.count >= _n2007 and base.same_list("summaries_to_record", _scratch2006)) {
        out.unsigned(1);
        out.unsigned(_n2007);
        out.unsigned(value.summaries_to_record.count - _n2007);
        for (var _i2008 in _n2007..value.summaries_to_record.count) {
            var (_t2011, _t2012) = value.summaries_to_record[_i2008];
            out.loc(_t2011);
            out.text(_t2012);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2013 in value.summaries_to_record) {
            var (_t2014, _t2015) = _item2013;
            out.loc(_t2014);
            out.text(_t2015);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2033 = 0;
    var _news2034 = HashMap<String, Array<bool>>();
    for (var (_key2030, _) in value.caller_copies) {
        var _kscratch2031 = base.scratch();
        _kscratch2031.text(_key2030);
        var _vscratch2032 = base.scratch();
        _vscratch2032.unsigned(value.caller_copies[_key2030].count);
        for (var _item2035 in value.caller_copies[_key2030]) {
            _vscratch2032.flag(_item2035);
        }
        var _had = base.entry("caller_copies", _kscratch2031, _vscratch2032);
        if (_had >= 0) {
            _kept2033 += 1;
        }
        if (_had != 1) {
            _news2034[_key2030] = value.caller_copies[_key2030];
        }
    }
    if (_kept2033 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2037 = Array<(u8[], u8[], String)>();
        for (var (_key2036, _) in _news2034) {
            var _scratch2038 = out.scratch();
            _scratch2038.text(_key2036);
            var _vscratch2040 = out.scratch();
            _vscratch2040.unsigned(_news2034[_key2036].count);
            for (var _item2041 in _news2034[_key2036]) {
                _vscratch2040.flag(_item2041);
            }
            _keys2037.append((_scratch2038.finish(), _vscratch2040.finish(), _key2036));
        }
        _keys2037.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2037.count);
        for (var (_bytes2039, _, _key2036) in _keys2037) {
            out.text(_key2036);
            out.unsigned(_news2034[_key2036].count);
            for (var _item2042 in _news2034[_key2036]) {
                out.flag(_item2042);
            }
        }
    } else {
        out.unsigned(0);
        var _keys2044 = Array<(u8[], u8[], String)>();
        for (var (_key2043, _) in value.caller_copies) {
            var _scratch2045 = out.scratch();
            _scratch2045.text(_key2043);
            var _vscratch2047 = out.scratch();
            _vscratch2047.unsigned(value.caller_copies[_key2043].count);
            for (var _item2048 in value.caller_copies[_key2043]) {
                _vscratch2047.flag(_item2048);
            }
            _keys2044.append((_scratch2045.finish(), _vscratch2047.finish(), _key2043));
        }
        _keys2044.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2044.count);
        for (var (_bytes2046, _, _key2043) in _keys2044) {
            out.text(_key2043);
            out.unsigned(value.caller_copies[_key2043].count);
            for (var _item2049 in value.caller_copies[_key2043]) {
                out.flag(_item2049);
            }
        }
        base.count("caller_copies whole", 0);
    }
    for (var (_key2030, _) in value.caller_copies) {
        var _kscratch2031 = next.scratch();
        _kscratch2031.text(_key2030);
        var _vscratch2032 = next.scratch();
        _vscratch2032.unsigned(value.caller_copies[_key2030].count);
        for (var _item2063 in value.caller_copies[_key2030]) {
            _vscratch2032.flag(_item2063);
        }
        next.keep_entry("caller_copies", _kscratch2031, _vscratch2032);
    }
    base.stat("caller_copies", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.linked);
    base.stat("linked", out.values.count - _mark);
    _mark = out.values.count;
}

_m_Module_read_delta(input: RecordIn, base: Module): Module {
    var _f1483 = Array<ast.Import>();
    var _n1484 = input.count();
    for (var _ in 0.._n1484) {
        var _tag1485 = input.unsigned();
        if (_tag1485 & 1 == 1) {
            _f1483.append(base.imports[_tag1485 >> 1]);
        } else {
            _f1483.append(_a_Import_read(input));
        }
    }
    var _f1490 = Array<StructDef>();
    var _n1491 = input.count();
    for (var _ in 0.._n1491) {
        var _tag1492 = input.unsigned();
        if (_tag1492 & 1 == 1) {
            _f1490.append(base.structs[_tag1492 >> 1]);
        } else if (_tag1492 == 2) {
            var _was = base.structs[input.unsigned()];
            _f1490.append(_patch_s_read(input, _was));
        } else {
            _f1490.append(_m_StructDef_read_lazy(input));
        }
    }
    var _f1497 = Array<TraitDef>();
    var _n1498 = input.count();
    for (var _ in 0.._n1498) {
        var _tag1499 = input.unsigned();
        if (_tag1499 & 1 == 1) {
            _f1497.append(base.traits[_tag1499 >> 1]);
        } else {
            _f1497.append(_m_TraitDef_read(input));
        }
    }
    var _f1504 = Array<ExtensionDef>();
    var _n1505 = input.count();
    for (var _ in 0.._n1505) {
        var _tag1506 = input.unsigned();
        if (_tag1506 & 1 == 1) {
            _f1504.append(base.extensions[_tag1506 >> 1]);
        } else {
            _f1504.append(_m_ExtensionDef_read(input));
        }
    }
    var _f1511 = Array<FunctionDef>();
    var _n1512 = input.count();
    for (var _ in 0.._n1512) {
        var _tag1513 = input.unsigned();
        if (_tag1513 & 1 == 1) {
            _f1511.append(base.functions[_tag1513 >> 1]);
        } else {
            _f1511.append(_m_FunctionDef_read_lazy(input));
        }
    }
    var _f1518 = Array<ExternDef>();
    var _n1519 = input.count();
    for (var _ in 0.._n1519) {
        var _tag1520 = input.unsigned();
        if (_tag1520 & 1 == 1) {
            _f1518.append(base.externs[_tag1520 >> 1]);
        } else {
            _f1518.append(_m_ExternDef_read(input));
        }
    }
    var _f1525 = Array<VariableDef>();
    var _n1526 = input.count();
    for (var _ in 0.._n1526) {
        var _tag1527 = input.unsigned();
        if (_tag1527 & 1 == 1) {
            _f1525.append(base.globals[_tag1527 >> 1]);
        } else {
            _f1525.append(_m_VariableDef_read(input));
        }
    }
    var _f1532 = Array<ModuleStaticBlock>();
    var _n1533 = input.count();
    for (var _ in 0.._n1533) {
        var _tag1534 = input.unsigned();
        if (_tag1534 & 1 == 1) {
            _f1532.append(base.static_blocks[_tag1534 >> 1]);
        } else {
            _f1532.append(_m_ModuleStaticBlock_read(input));
        }
    }
    var _f1539 = Array<EnumDef>();
    var _n1540 = input.count();
    for (var _ in 0.._n1540) {
        var _tag1541 = input.unsigned();
        if (_tag1541 & 1 == 1) {
            _f1539.append(base.enums[_tag1541 >> 1]);
        } else {
            _f1539.append(_m_EnumDef_read(input));
        }
    }
    var _f1546 = Array<TypeName>();
    var _n1547 = input.count();
    for (var _ in 0.._n1547) {
        var _tag1548 = input.unsigned();
        if (_tag1548 & 1 == 1) {
            _f1546.append(base.struct_specs[_tag1548 >> 1]);
        } else {
            _f1546.append(_m_TypeName_read(input));
        }
    }
    var _f1553 = Array<TypeName>();
    var _n1554 = input.count();
    for (var _ in 0.._n1554) {
        var _tag1555 = input.unsigned();
        if (_tag1555 & 1 == 1) {
            _f1553.append(base.func_specs[_tag1555 >> 1]);
        } else {
            _f1553.append(_m_TypeName_read(input));
        }
    }
    var _f1560 = Array<TypeAliasDef>();
    var _n1561 = input.count();
    for (var _ in 0.._n1561) {
        var _tag1562 = input.unsigned();
        if (_tag1562 & 1 == 1) {
            _f1560.append(base.type_aliases[_tag1562 >> 1]);
        } else {
            _f1560.append(_m_TypeAliasDef_read(input));
        }
    }
    var _f1567 = Array<Withheld>();
    var _n1568 = input.count();
    for (var _ in 0.._n1568) {
        var _tag1569 = input.unsigned();
        if (_tag1569 & 1 == 1) {
            _f1567.append(base.withheld[_tag1569 >> 1]);
        } else {
            _f1567.append(_m_Withheld_read(input));
        }
    }
    var _f1574 = Array<PropertyDef>();
    var _n1575 = input.count();
    for (var _ in 0.._n1575) {
        var _tag1576 = input.unsigned();
        if (_tag1576 & 1 == 1) {
            _f1574.append(base.properties[_tag1576 >> 1]);
        } else {
            _f1574.append(_m_PropertyDef_read(input));
        }
    }
    var _f1581 = Array<TypeUse>();
    var _n1582 = input.count();
    for (var _ in 0.._n1582) {
        var _tag1583 = input.unsigned();
        if (_tag1583 & 1 == 1) {
            _f1581.append(base.type_uses[_tag1583 >> 1]);
        } else {
            _f1581.append(_m_TypeUse_read(input));
        }
    }
    var _f1588 = Array<UseContext>();
    var _n1589 = input.count();
    for (var _ in 0.._n1589) {
        var _tag1590 = input.unsigned();
        if (_tag1590 & 1 == 1) {
            _f1588.append(base.use_contexts[_tag1590 >> 1]);
        } else {
            _f1588.append(_m_UseContext_read(input));
        }
    }
    var _f1606 = Array<(Loc, ulong, Loc)>();
    var _tag1607 = input.unsigned();
    if (_tag1607 == 1) {
        input.unsigned();
        for (var _i1595 in 0..base.literal_args.count) {
            _f1606.append(base.literal_args[_i1595]);
        }
        var _more1609 = input.count();
        for (var _ in 0.._more1609) {
            var _t1610 = input.loc();
            var _t1611 = input.unsigned();
            var _t1612 = input.loc();
            _f1606.append((_t1610, _t1611, _t1612));
        }
    } else {
        var _v1613 = Array<(Loc, ulong, Loc)>();
        var _n1614 = input.count();
        for (var _ in 0.._n1614) {
            var _t1615 = input.loc();
            var _t1616 = input.unsigned();
            var _t1617 = input.loc();
            _v1613.append((_t1615, _t1616, _t1617));
        }
        _f1606 = _v1613;
    }
    var _f1626 = Array<TypeAliasDef>();
    var _n1627 = input.count();
    for (var _ in 0.._n1627) {
        var _tag1628 = input.unsigned();
        if (_tag1628 & 1 == 1) {
            _f1626.append(base.constrained_aliases[_tag1628 >> 1]);
        } else {
            _f1626.append(_m_TypeAliasDef_read(input));
        }
    }
    var _f1633 = Array<TraitType>();
    var _n1634 = input.count();
    for (var _ in 0.._n1634) {
        var _tag1635 = input.unsigned();
        if (_tag1635 & 1 == 1) {
            _f1633.append(base.trait_types[_tag1635 >> 1]);
        } else {
            _f1633.append(_m_TraitType_read(input));
        }
    }
    var _f1640 = Array<Conversion>();
    var _n1641 = input.count();
    for (var _ in 0.._n1641) {
        var _tag1642 = input.unsigned();
        if (_tag1642 & 1 == 1) {
            _f1640.append(base.conversions[_tag1642 >> 1]);
        } else {
            _f1640.append(_m_Conversion_read(input));
        }
    }
    var _f1664 = Map<String, Array<String>>();
    var _tag1665 = input.unsigned();
    if (_tag1665 == 1) {
        for (var (_bk1666, _bv) in base.overload_sets) {
            _f1664[_bk1666] = _bv;
        }
        var _v1667 = Map<String, Array<String>>();
        var _n1668 = input.count();
        for (var _ in 0.._n1668) {
            var _k1669 = input.text();
            var _v1670 = Array<String>();
            var _n1671 = input.count();
            for (var _ in 0.._n1671) {
                _v1670.append(input.text());
            }
            _v1667[_k1669] = _v1670;
        }
        for (var (_bk1666, _av) in _v1667) {
            _f1664[_bk1666] = _av;
        }
    } else {
        var _v1672 = Map<String, Array<String>>();
        var _n1673 = input.count();
        for (var _ in 0.._n1673) {
            var _k1674 = input.text();
            var _v1675 = Array<String>();
            var _n1676 = input.count();
            for (var _ in 0.._n1676) {
                _v1675.append(input.text());
            }
            _v1672[_k1674] = _v1675;
        }
        _f1664 = _v1672;
    }
    var _f1703 = Map<String, Array<Array<String>>>();
    var _tag1704 = input.unsigned();
    if (_tag1704 == 1) {
        for (var (_bk1705, _bv) in base.overload_unions) {
            _f1703[_bk1705] = _bv;
        }
        var _v1706 = Map<String, Array<Array<String>>>();
        var _n1707 = input.count();
        for (var _ in 0.._n1707) {
            var _k1708 = input.text();
            var _v1709 = Array<Array<String>>();
            var _n1710 = input.count();
            for (var _ in 0.._n1710) {
                var _v1711 = Array<String>();
                var _n1712 = input.count();
                for (var _ in 0.._n1712) {
                    _v1711.append(input.text());
                }
                _v1709.append(_v1711);
            }
            _v1706[_k1708] = _v1709;
        }
        for (var (_bk1705, _av) in _v1706) {
            _f1703[_bk1705] = _av;
        }
    } else {
        var _v1713 = Map<String, Array<Array<String>>>();
        var _n1714 = input.count();
        for (var _ in 0.._n1714) {
            var _k1715 = input.text();
            var _v1716 = Array<Array<String>>();
            var _n1717 = input.count();
            for (var _ in 0.._n1717) {
                var _v1718 = Array<String>();
                var _n1719 = input.count();
                for (var _ in 0.._n1719) {
                    _v1718.append(input.text());
                }
                _v1716.append(_v1718);
            }
            _v1713[_k1715] = _v1716;
        }
        _f1703 = _v1713;
    }
    var _f1772 = Map<String, Map<String, Array<String>>>();
    var _tag1773 = input.unsigned();
    if (_tag1773 == 1) {
        for (var (_bk1774, _bv) in base.method_overload_sets) {
            _f1772[_bk1774] = _bv;
        }
        var _v1775 = Map<String, Map<String, Array<String>>>();
        var _n1776 = input.count();
        for (var _ in 0.._n1776) {
            var _k1777 = input.text();
            var _v1778 = Map<String, Array<String>>();
            var _n1779 = input.count();
            for (var _ in 0.._n1779) {
                var _k1780 = input.text();
                var _v1781 = Array<String>();
                var _n1782 = input.count();
                for (var _ in 0.._n1782) {
                    _v1781.append(input.text());
                }
                _v1778[_k1780] = _v1781;
            }
            _v1775[_k1777] = _v1778;
        }
        for (var (_bk1774, _av) in _v1775) {
            _f1772[_bk1774] = _av;
        }
    } else {
        var _v1783 = Map<String, Map<String, Array<String>>>();
        var _n1784 = input.count();
        for (var _ in 0.._n1784) {
            var _k1785 = input.text();
            var _v1786 = Map<String, Array<String>>();
            var _n1787 = input.count();
            for (var _ in 0.._n1787) {
                var _k1788 = input.text();
                var _v1789 = Array<String>();
                var _n1790 = input.count();
                for (var _ in 0.._n1790) {
                    _v1789.append(input.text());
                }
                _v1786[_k1788] = _v1789;
            }
            _v1783[_k1785] = _v1786;
        }
        _f1772 = _v1783;
    }
    var _f1798 = _m_ExtensionScopes_read(input);
    var _f1814 = HashSet<Loc>();
    var _tag1815 = input.unsigned();
    if (_tag1815 == 1) {
        for (var _bk1816 in base.private_functions) {
            _f1814.insert(_bk1816);
        }
        var _v1817 = HashSet<Loc>();
        var _n1818 = input.count();
        for (var _ in 0.._n1818) {
            _v1817.insert(input.loc());
        }
        for (var _bk1816 in _v1817) {
            _f1814.insert(_bk1816);
        }
    } else {
        var _v1819 = HashSet<Loc>();
        var _n1820 = input.count();
        for (var _ in 0.._n1820) {
            _v1819.insert(input.loc());
        }
        _f1814 = _v1819;
    }
    var _f1836 = HashSet<Loc>();
    var _tag1837 = input.unsigned();
    if (_tag1837 == 1) {
        for (var _bk1838 in base.file_private_functions) {
            _f1836.insert(_bk1838);
        }
        var _v1839 = HashSet<Loc>();
        var _n1840 = input.count();
        for (var _ in 0.._n1840) {
            _v1839.insert(input.loc());
        }
        for (var _bk1838 in _v1839) {
            _f1836.insert(_bk1838);
        }
    } else {
        var _v1841 = HashSet<Loc>();
        var _n1842 = input.count();
        for (var _ in 0.._n1842) {
            _v1841.insert(input.loc());
        }
        _f1836 = _v1841;
    }
    var _f1854 = Array<(Loc, String)>();
    var _tag1855 = input.unsigned();
    if (_tag1855 == 1) {
        input.unsigned();
        for (var _i1846 in 0..base.call_targets.count) {
            _f1854.append(base.call_targets[_i1846]);
        }
        var _more1857 = input.count();
        for (var _ in 0.._more1857) {
            var _t1858 = input.loc();
            var _t1859 = input.text();
            _f1854.append((_t1858, _t1859));
        }
    } else {
        var _v1860 = Array<(Loc, String)>();
        var _n1861 = input.count();
        for (var _ in 0.._n1861) {
            var _t1862 = input.loc();
            var _t1863 = input.text();
            _v1860.append((_t1862, _t1863));
        }
        _f1854 = _v1860;
    }
    var _f1880 = Array<(Loc, String)>();
    var _tag1881 = input.unsigned();
    if (_tag1881 == 1) {
        var _v1882 = Array<(Loc, String)>();
        var _n1883 = input.count();
        for (var _ in 0.._n1883) {
            var _t1884 = input.loc();
            var _t1885 = input.text();
            _v1882.append((_t1884, _t1885));
        }
        _f1880 = merge_by_place(base.argument_names, _v1882);
    } else {
        var _v1886 = Array<(Loc, String)>();
        var _n1887 = input.count();
        for (var _ in 0.._n1887) {
            var _t1888 = input.loc();
            var _t1889 = input.text();
            _v1886.append((_t1888, _t1889));
        }
        _f1880 = _v1886;
    }
    var _f1897 = Array<String>();
    var _tag1898 = input.unsigned();
    if (_tag1898 == 1) {
        input.unsigned();
        for (var _i1895 in 0..base.namespaces.count) {
            _f1897.append(base.namespaces[_i1895]);
        }
        var _more1900 = input.count();
        for (var _ in 0.._more1900) {
            _f1897.append(input.text());
        }
    } else {
        var _v1901 = Array<String>();
        var _n1902 = input.count();
        for (var _ in 0.._n1902) {
            _v1901.append(input.text());
        }
        _f1897 = _v1901;
    }
    var _f1910 = Array<bool>();
    var _tag1911 = input.unsigned();
    if (_tag1911 == 1) {
        input.unsigned();
        for (var _i1908 in 0..base.cached_files.count) {
            _f1910.append(base.cached_files[_i1908]);
        }
        var _more1913 = input.count();
        for (var _ in 0.._more1913) {
            _f1910.append(input.flag());
        }
    } else {
        var _v1914 = Array<bool>();
        var _n1915 = input.count();
        for (var _ in 0.._n1915) {
            _v1914.append(input.flag());
        }
        _f1910 = _v1914;
    }
    var _f1933 = HashMap<Loc, String>();
    var _tag1934 = input.unsigned();
    if (_tag1934 == 1) {
        for (var (_bk1935, _bv) in base.recorded_summaries) {
            _f1933[_bk1935] = _bv;
        }
        var _v1936 = HashMap<Loc, String>();
        var _n1937 = input.count();
        for (var _ in 0.._n1937) {
            var _k1938 = input.loc();
            _v1936[_k1938] = input.text();
        }
        for (var (_bk1935, _av) in _v1936) {
            _f1933[_bk1935] = _av;
        }
    } else {
        var _v1939 = HashMap<Loc, String>();
        var _n1940 = input.count();
        for (var _ in 0.._n1940) {
            var _k1941 = input.loc();
            _v1939[_k1941] = input.text();
        }
        _f1933 = _v1939;
    }
    var _f1957 = HashSet<Loc>();
    var _tag1958 = input.unsigned();
    if (_tag1958 == 1) {
        for (var _bk1959 in base.stripped) {
            _f1957.insert(_bk1959);
        }
        var _v1960 = HashSet<Loc>();
        var _n1961 = input.count();
        for (var _ in 0.._n1961) {
            _v1960.insert(input.loc());
        }
        for (var _bk1959 in _v1960) {
            _f1957.insert(_bk1959);
        }
    } else {
        var _v1962 = HashSet<Loc>();
        var _n1963 = input.count();
        for (var _ in 0.._n1963) {
            _v1962.insert(input.loc());
        }
        _f1957 = _v1962;
    }
    var _frozen = input.flag();
    var _f1967 = Array<StructDef>();
    var _n1968 = input.count();
    for (var _ in 0.._n1968) {
        var _tag1969 = input.unsigned();
        if (_tag1969 & 1 == 1) {
            _f1967.append(base.templates.structs[_tag1969 >> 1]);
        } else if (_tag1969 == 2) {
            var _was = base.templates.structs[input.unsigned()];
            _f1967.append(_patch_t_read(input, _was));
        } else {
            _f1967.append(_m_StructDef_read(input));
        }
    }
    var _f1974 = Array<FunctionDef>();
    var _n1975 = input.count();
    for (var _ in 0.._n1975) {
        var _tag1976 = input.unsigned();
        if (_tag1976 & 1 == 1) {
            _f1974.append(base.templates.functions[_tag1976 >> 1]);
        } else {
            _f1974.append(_m_FunctionDef_read(input));
        }
    }
    var _f1978 = Templates(_frozen, _f1967, _f1974);
    var _f1979 = DeltaBase.read_checked(input, base.checked);
    var _f1995 = HashMap<String, SpecRequest>();
    var _tag1996 = input.unsigned();
    if (_tag1996 == 1) {
        for (var (_bk1997, _bv) in base.spec_requests) {
            _f1995[_bk1997] = _bv;
        }
        var _v1998 = HashMap<String, SpecRequest>();
        var _n1999 = input.count();
        for (var _ in 0.._n1999) {
            var _k2000 = input.text();
            _v1998[_k2000] = _m_SpecRequest_read(input);
        }
        for (var (_bk1997, _av) in _v1998) {
            _f1995[_bk1997] = _av;
        }
    } else {
        var _v2001 = HashMap<String, SpecRequest>();
        var _n2002 = input.count();
        for (var _ in 0.._n2002) {
            var _k2003 = input.text();
            _v2001[_k2003] = _m_SpecRequest_read(input);
        }
        _f1995 = _v2001;
    }
    var _f2004 = input.flag();
    var _f2016 = Array<(Loc, String)>();
    var _tag2017 = input.unsigned();
    if (_tag2017 == 1) {
        input.unsigned();
        for (var _i2008 in 0..base.summaries_to_record.count) {
            _f2016.append(base.summaries_to_record[_i2008]);
        }
        var _more2019 = input.count();
        for (var _ in 0.._more2019) {
            var _t2020 = input.loc();
            var _t2021 = input.text();
            _f2016.append((_t2020, _t2021));
        }
    } else {
        var _v2022 = Array<(Loc, String)>();
        var _n2023 = input.count();
        for (var _ in 0.._n2023) {
            var _t2024 = input.loc();
            var _t2025 = input.text();
            _v2022.append((_t2024, _t2025));
        }
        _f2016 = _v2022;
    }
    var _f2050 = HashMap<String, Array<bool>>();
    var _tag2051 = input.unsigned();
    if (_tag2051 == 1) {
        for (var (_bk2052, _bv) in base.caller_copies) {
            _f2050[_bk2052] = _bv;
        }
        var _v2053 = HashMap<String, Array<bool>>();
        var _n2054 = input.count();
        for (var _ in 0.._n2054) {
            var _k2055 = input.text();
            var _v2056 = Array<bool>();
            var _n2057 = input.count();
            for (var _ in 0.._n2057) {
                _v2056.append(input.flag());
            }
            _v2053[_k2055] = _v2056;
        }
        for (var (_bk2052, _av) in _v2053) {
            _f2050[_bk2052] = _av;
        }
    } else {
        var _v2058 = HashMap<String, Array<bool>>();
        var _n2059 = input.count();
        for (var _ in 0.._n2059) {
            var _k2060 = input.text();
            var _v2061 = Array<bool>();
            var _n2062 = input.count();
            for (var _ in 0.._n2062) {
                _v2061.append(input.flag());
            }
            _v2058[_k2060] = _v2061;
        }
        _f2050 = _v2058;
    }
    var _f2064 = input.flag();
    return Module(
        _f1483,
        _f1490,
        _f1497,
        _f1504,
        _f1511,
        _f1518,
        _f1525,
        _f1532,
        _f1539,
        _f1546,
        _f1553,
        _f1560,
        _f1567,
        _f1574,
        _f1581,
        _f1588,
        _f1606,
        _f1626,
        _f1633,
        _f1640,
        _f1664,
        _f1703,
        _f1772,
        _f1798,
        _f1814,
        _f1836,
        _f1854,
        _f1880,
        _f1897,
        _f1910,
        _f1933,
        _f1957,
        _f1978,
        _f1979,
        _f1995,
        _f2004,
        _f2016,
        _f2050,
        _f2064
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1486 = 0;
    for (var _item1480 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1480);
        base.add("imports", scratch, _j1486);
        _j1486 += 1;
    }
    ulong _j1493 = 0;
    for (var _item1487 in value.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1487);
        base.add("s", scratch, _j1493);
        base.name("s", _item1487.name, _j1493);
        _patch_s_index(_item1487, base, _j1493);
        _j1493 += 1;
    }
    ulong _j1500 = 0;
    for (var _item1494 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1494);
        base.add("traits", scratch, _j1500);
        _j1500 += 1;
    }
    ulong _j1507 = 0;
    for (var _item1501 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1501);
        base.add("extensions", scratch, _j1507);
        _j1507 += 1;
    }
    ulong _j1514 = 0;
    for (var _item1508 in value.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1508);
        base.add("functions", scratch, _j1514);
        _j1514 += 1;
    }
    ulong _j1521 = 0;
    for (var _item1515 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1515);
        base.add("externs", scratch, _j1521);
        _j1521 += 1;
    }
    ulong _j1528 = 0;
    for (var _item1522 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1522);
        base.add("globals", scratch, _j1528);
        _j1528 += 1;
    }
    ulong _j1535 = 0;
    for (var _item1529 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1529);
        base.add("static_blocks", scratch, _j1535);
        _j1535 += 1;
    }
    ulong _j1542 = 0;
    for (var _item1536 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1536);
        base.add("enums", scratch, _j1542);
        _j1542 += 1;
    }
    ulong _j1549 = 0;
    for (var _item1543 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1543);
        base.add("struct_specs", scratch, _j1549);
        _j1549 += 1;
    }
    ulong _j1556 = 0;
    for (var _item1550 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1550);
        base.add("func_specs", scratch, _j1556);
        _j1556 += 1;
    }
    ulong _j1563 = 0;
    for (var _item1557 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1557);
        base.add("type_aliases", scratch, _j1563);
        _j1563 += 1;
    }
    ulong _j1570 = 0;
    for (var _item1564 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1564);
        base.add("withheld", scratch, _j1570);
        _j1570 += 1;
    }
    ulong _j1577 = 0;
    for (var _item1571 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1571);
        base.add("properties", scratch, _j1577);
        _j1577 += 1;
    }
    ulong _j1584 = 0;
    for (var _item1578 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1578);
        base.add("type_uses", scratch, _j1584);
        _j1584 += 1;
    }
    ulong _j1591 = 0;
    for (var _item1585 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1585);
        base.add("use_contexts", scratch, _j1591);
        _j1591 += 1;
    }
    var _xscratch1618 = base.scratch();
    for (var _xitem1619 in value.literal_args) {
        var (_t1620, _t1621, _t1622) = _xitem1619;
        _xscratch1618.loc(_t1620);
        _xscratch1618.unsigned(_t1621);
        _xscratch1618.loc(_t1622);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1618);
    ulong _j1629 = 0;
    for (var _item1623 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1623);
        base.add("constrained_aliases", scratch, _j1629);
        _j1629 += 1;
    }
    ulong _j1636 = 0;
    for (var _item1630 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1630);
        base.add("trait_types", scratch, _j1636);
        _j1636 += 1;
    }
    ulong _j1643 = 0;
    for (var _item1637 in value.conversions) {
        var scratch = base.scratch();
        _m_Conversion_write(scratch, _item1637);
        base.add("conversions", scratch, _j1643);
        _j1643 += 1;
    }
    for (var (_key1644, _) in value.overload_sets) {
        var _kscratch1645 = base.scratch();
        _kscratch1645.text(_key1644);
        var _vscratch1646 = base.scratch();
        _vscratch1646.unsigned(value.overload_sets[_key1644].count);
        for (var _item1677 in value.overload_sets[_key1644]) {
            _vscratch1646.text(_item1677);
        }
        base.keep_entry("overload_sets", _kscratch1645, _vscratch1646);
    }
    for (var (_key1678, _) in value.overload_unions) {
        var _kscratch1679 = base.scratch();
        _kscratch1679.text(_key1678);
        var _vscratch1680 = base.scratch();
        _vscratch1680.unsigned(value.overload_unions[_key1678].count);
        for (var _item1720 in value.overload_unions[_key1678]) {
            _vscratch1680.unsigned(_item1720.count);
            for (var _item1721 in _item1720) {
                _vscratch1680.text(_item1721);
            }
        }
        base.keep_entry("overload_unions", _kscratch1679, _vscratch1680);
    }
    for (var (_key1722, _) in value.method_overload_sets) {
        var _kscratch1723 = base.scratch();
        _kscratch1723.text(_key1722);
        var _vscratch1724 = base.scratch();
        var _keys1792 = Array<(u8[], u8[], String)>();
        for (var (_key1791, _) in value.method_overload_sets[_key1722]) {
            var _scratch1793 = _vscratch1724.scratch();
            _scratch1793.text(_key1791);
            var _vscratch1795 = _vscratch1724.scratch();
            _vscratch1795.unsigned(value.method_overload_sets[_key1722][_key1791].count);
            for (var _item1796 in value.method_overload_sets[_key1722][_key1791]) {
                _vscratch1795.text(_item1796);
            }
            _keys1792.append((_scratch1793.finish(), _vscratch1795.finish(), _key1791));
        }
        _keys1792.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1724.unsigned(_keys1792.count);
        for (var (_bytes1794, _, _key1791) in _keys1792) {
            _vscratch1724.text(_key1791);
            _vscratch1724.unsigned(value.method_overload_sets[_key1722][_key1791].count);
            for (var _item1797 in value.method_overload_sets[_key1722][_key1791]) {
                _vscratch1724.text(_item1797);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1723, _vscratch1724);
    }
    for (var _key1799 in value.private_functions) {
        var _kscratch1800 = base.scratch();
        _kscratch1800.loc(_key1799);
        var _vscratch1801 = base.scratch();
        base.keep_entry("private_functions", _kscratch1800, _vscratch1801);
    }
    for (var _key1821 in value.file_private_functions) {
        var _kscratch1822 = base.scratch();
        _kscratch1822.loc(_key1821);
        var _vscratch1823 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch1822, _vscratch1823);
    }
    var _xscratch1864 = base.scratch();
    for (var _xitem1865 in value.call_targets) {
        var (_t1866, _t1867) = _xitem1865;
        _xscratch1864.loc(_t1866);
        _xscratch1864.text(_t1867);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch1864);
    for (var _item1868 in value.argument_names) {
        var _escratch1869 = base.scratch();
        var (_t1890, _t1891) = _item1868;
        _escratch1869.loc(_t1890);
        _escratch1869.text(_t1891);
        base.keep_entry("argument_names", _escratch1869, base.scratch());
    }
    var _xscratch1903 = base.scratch();
    for (var _xitem1904 in value.namespaces) {
        _xscratch1903.text(_xitem1904);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch1903);
    var _xscratch1916 = base.scratch();
    for (var _xitem1917 in value.cached_files) {
        _xscratch1916.flag(_xitem1917);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch1916);
    for (var (_key1918, _) in value.recorded_summaries) {
        var _kscratch1919 = base.scratch();
        _kscratch1919.loc(_key1918);
        var _vscratch1920 = base.scratch();
        _vscratch1920.text(value.recorded_summaries[_key1918]);
        base.keep_entry("recorded_summaries", _kscratch1919, _vscratch1920);
    }
    for (var _key1942 in value.stripped) {
        var _kscratch1943 = base.scratch();
        _kscratch1943.loc(_key1942);
        var _vscratch1944 = base.scratch();
        base.keep_entry("stripped", _kscratch1943, _vscratch1944);
    }
    ulong _j1970 = 0;
    for (var _item1964 in value.templates.structs) {
        var scratch = base.scratch();
        _m_StructDef_write(scratch, _item1964);
        base.add("t", scratch, _j1970);
        base.name("t", _item1964.name, _j1970);
        _patch_t_index(_item1964, base, _j1970);
        _j1970 += 1;
    }
    ulong _j1977 = 0;
    for (var _item1971 in value.templates.functions) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item1971);
        base.add("tf", scratch, _j1977);
        _j1977 += 1;
    }
    base.keep_checked(value.checked);
    for (var (_key1980, _) in value.spec_requests) {
        var _kscratch1981 = base.scratch();
        _kscratch1981.text(_key1980);
        var _vscratch1982 = base.scratch();
        _m_SpecRequest_write(_vscratch1982, value.spec_requests[_key1980]);
        base.keep_entry("spec_requests", _kscratch1981, _vscratch1982);
    }
    var _xscratch2026 = base.scratch();
    for (var _xitem2027 in value.summaries_to_record) {
        var (_t2028, _t2029) = _xitem2027;
        _xscratch2026.loc(_t2028);
        _xscratch2026.text(_t2029);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2026);
    for (var (_key2030, _) in value.caller_copies) {
        var _kscratch2031 = base.scratch();
        _kscratch2031.text(_key2030);
        var _vscratch2032 = base.scratch();
        _vscratch2032.unsigned(value.caller_copies[_key2030].count);
        for (var _item2063 in value.caller_copies[_key2030]) {
            _vscratch2032.flag(_item2063);
        }
        base.keep_entry("caller_copies", _kscratch2031, _vscratch2032);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1563 = 0;
    for (var _item1557 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1557);
        base.add("type_aliases", scratch, _j1563);
        _j1563 += 1;
    }
    for (var (_key1918, _) in value.recorded_summaries) {
        var _kscratch1919 = base.scratch();
        _kscratch1919.loc(_key1918);
        var _vscratch1920 = base.scratch();
        _vscratch1920.text(value.recorded_summaries[_key1918]);
        base.keep_entry("recorded_summaries", _kscratch1919, _vscratch1920);
    }
    var _xscratch2026 = base.scratch();
    for (var _xitem2027 in value.summaries_to_record) {
        var (_t2028, _t2029) = _xitem2027;
        _xscratch2026.loc(_t2028);
        _xscratch2026.text(_t2029);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2026);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _hits2068 = HashSet<long>();
    ulong _nj2069 = 0;
    out.unsigned(value.generic_params.count);
    for (var _item2067 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2067);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.generic_params", hash);
        if (at >= 0) {
            _hits2068.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_GenericParam_write(out, _item2067);
        }
    }
    base.missed("s.*.generic_params", $"s.{slot}.generic_params", _hits2068.count);
    var _hits2075 = HashSet<long>();
    ulong _nj2076 = 0;
    out.unsigned(value.field_members.count);
    for (var _item2074 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2074);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.field_members", hash);
        if (at >= 0) {
            _hits2075.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_VariableDef_write(out, _item2074);
        }
    }
    base.missed("s.*.field_members", $"s.{slot}.field_members", _hits2075.count);
    var _hits2082 = HashSet<long>();
    ulong _nj2083 = 0;
    out.unsigned(value.method_members.count);
    for (var _item2081 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2081);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.method_members", hash);
        if (at >= 0) {
            _hits2082.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2081);
        }
    }
    base.missed("s.*.method_members", $"s.{slot}.method_members", _hits2082.count);
    var _hits2089 = HashSet<long>();
    ulong _nj2090 = 0;
    out.unsigned(value.generic_methods.count);
    for (var _item2088 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2088);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.generic_methods", hash);
        if (at >= 0) {
            _hits2089.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2088);
        }
    }
    base.missed("s.*.generic_methods", $"s.{slot}.generic_methods", _hits2089.count);
    var _hits2096 = HashSet<long>();
    ulong _nj2097 = 0;
    out.unsigned(value.constructors.count);
    for (var _item2095 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2095);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.constructors", hash);
        if (at >= 0) {
            _hits2096.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2095);
        }
    }
    base.missed("s.*.constructors", $"s.{slot}.constructors", _hits2096.count);
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _hits2106 = HashSet<long>();
    ulong _nj2107 = 0;
    out.unsigned(value.traits.count);
    for (var _item2105 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2105);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.traits", hash);
        if (at >= 0) {
            _hits2106.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeName_write(out, _item2105);
        }
    }
    base.missed("s.*.traits", $"s.{slot}.traits", _hits2106.count);
    var _hits2113 = HashSet<long>();
    ulong _nj2114 = 0;
    out.unsigned(value.attributes.count);
    for (var _item2112 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2112);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"s.{slot}.attributes", hash);
        if (at >= 0) {
            _hits2113.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _a_Attribute_write(out, _item2112);
        }
    }
    base.missed("s.*.attributes", $"s.{slot}.attributes", _hits2113.count);
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2120 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2120);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2065 = input.text();
    var _f2066 = _m_TypeName_read(input);
    var _f2070 = Array<GenericParam>();
    var _n2071 = input.count();
    for (var _ in 0.._n2071) {
        var _tag2072 = input.unsigned();
        if (_tag2072 & 1 == 1) {
            _f2070.append(was.generic_params[_tag2072 >> 1]);
        } else {
            _f2070.append(_m_GenericParam_read(input));
        }
    }
    var _f2077 = Array<VariableDef>();
    var _n2078 = input.count();
    for (var _ in 0.._n2078) {
        var _tag2079 = input.unsigned();
        if (_tag2079 & 1 == 1) {
            _f2077.append(was.field_members[_tag2079 >> 1]);
        } else {
            _f2077.append(_m_VariableDef_read(input));
        }
    }
    var _f2084 = Array<FunctionDef>();
    var _n2085 = input.count();
    for (var _ in 0.._n2085) {
        var _tag2086 = input.unsigned();
        if (_tag2086 & 1 == 1) {
            _f2084.append(was.method_members[_tag2086 >> 1]);
        } else {
            _f2084.append(_m_FunctionDef_read(input));
        }
    }
    var _f2091 = Array<FunctionDef>();
    var _n2092 = input.count();
    for (var _ in 0.._n2092) {
        var _tag2093 = input.unsigned();
        if (_tag2093 & 1 == 1) {
            _f2091.append(was.generic_methods[_tag2093 >> 1]);
        } else {
            _f2091.append(_m_FunctionDef_read(input));
        }
    }
    var _f2098 = Array<FunctionDef>();
    var _n2099 = input.count();
    for (var _ in 0.._n2099) {
        var _tag2100 = input.unsigned();
        if (_tag2100 & 1 == 1) {
            _f2098.append(was.constructors[_tag2100 >> 1]);
        } else {
            _f2098.append(_m_FunctionDef_read(input));
        }
    }
    var _f2102 = _m_FunctionDef_read(input);
    var _f2103 = _m_FunctionDef_read(input);
    var _f2104 = _m_FunctionDef_read(input);
    var _f2108 = Array<TypeName>();
    var _n2109 = input.count();
    for (var _ in 0.._n2109) {
        var _tag2110 = input.unsigned();
        if (_tag2110 & 1 == 1) {
            _f2108.append(was.traits[_tag2110 >> 1]);
        } else {
            _f2108.append(_m_TypeName_read(input));
        }
    }
    var _f2115 = Array<ast.Attribute>();
    var _n2116 = input.count();
    for (var _ in 0.._n2116) {
        var _tag2117 = input.unsigned();
        if (_tag2117 & 1 == 1) {
            _f2115.append(was.attributes[_tag2117 >> 1]);
        } else {
            _f2115.append(_a_Attribute_read(input));
        }
    }
    var _f2119 = input.loc();
    var _o2121 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2122 = Array<EnumCaseDef>();
        var _n2123 = input.count();
        for (var _ in 0.._n2123) {
            _v2122.append(_m_EnumCaseDef_read(input));
        }
        _o2121 = Optional<Array<EnumCaseDef>>.Value(_v2122);
    }
    var _f2124 = _o2121;
    return StructDef(
        _f2065, _f2066, _f2070, _f2077, _f2084, _f2091, _f2098, _f2102, _f2103, _f2104, _f2108, _f2115, _f2119, _f2124
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    ulong _j2073 = 0;
    for (var _item2067 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2067);
        base.add($"s.{slot}.generic_params", scratch, _j2073);
        _j2073 += 1;
    }
    ulong _j2080 = 0;
    for (var _item2074 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2074);
        base.add($"s.{slot}.field_members", scratch, _j2080);
        _j2080 += 1;
    }
    ulong _j2087 = 0;
    for (var _item2081 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2081);
        base.add($"s.{slot}.method_members", scratch, _j2087);
        _j2087 += 1;
    }
    ulong _j2094 = 0;
    for (var _item2088 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2088);
        base.add($"s.{slot}.generic_methods", scratch, _j2094);
        _j2094 += 1;
    }
    ulong _j2101 = 0;
    for (var _item2095 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2095);
        base.add($"s.{slot}.constructors", scratch, _j2101);
        _j2101 += 1;
    }
    ulong _j2111 = 0;
    for (var _item2105 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2105);
        base.add($"s.{slot}.traits", scratch, _j2111);
        _j2111 += 1;
    }
    ulong _j2118 = 0;
    for (var _item2112 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2112);
        base.add($"s.{slot}.attributes", scratch, _j2118);
        _j2118 += 1;
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _hits2128 = HashSet<long>();
    ulong _nj2129 = 0;
    out.unsigned(value.generic_params.count);
    for (var _item2127 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2127);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.generic_params", hash);
        if (at >= 0) {
            _hits2128.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_GenericParam_write(out, _item2127);
        }
    }
    base.missed("t.*.generic_params", $"t.{slot}.generic_params", _hits2128.count);
    var _hits2135 = HashSet<long>();
    ulong _nj2136 = 0;
    out.unsigned(value.field_members.count);
    for (var _item2134 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2134);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.field_members", hash);
        if (at >= 0) {
            _hits2135.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_VariableDef_write(out, _item2134);
        }
    }
    base.missed("t.*.field_members", $"t.{slot}.field_members", _hits2135.count);
    var _hits2142 = HashSet<long>();
    ulong _nj2143 = 0;
    out.unsigned(value.method_members.count);
    for (var _item2141 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2141);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.method_members", hash);
        if (at >= 0) {
            _hits2142.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2141);
        }
    }
    base.missed("t.*.method_members", $"t.{slot}.method_members", _hits2142.count);
    var _hits2149 = HashSet<long>();
    ulong _nj2150 = 0;
    out.unsigned(value.generic_methods.count);
    for (var _item2148 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2148);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.generic_methods", hash);
        if (at >= 0) {
            _hits2149.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2148);
        }
    }
    base.missed("t.*.generic_methods", $"t.{slot}.generic_methods", _hits2149.count);
    var _hits2156 = HashSet<long>();
    ulong _nj2157 = 0;
    out.unsigned(value.constructors.count);
    for (var _item2155 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2155);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.constructors", hash);
        if (at >= 0) {
            _hits2156.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_FunctionDef_write(out, _item2155);
        }
    }
    base.missed("t.*.constructors", $"t.{slot}.constructors", _hits2156.count);
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _hits2166 = HashSet<long>();
    ulong _nj2167 = 0;
    out.unsigned(value.traits.count);
    for (var _item2165 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2165);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.traits", hash);
        if (at >= 0) {
            _hits2166.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeName_write(out, _item2165);
        }
    }
    base.missed("t.*.traits", $"t.{slot}.traits", _hits2166.count);
    var _hits2173 = HashSet<long>();
    ulong _nj2174 = 0;
    out.unsigned(value.attributes.count);
    for (var _item2172 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2172);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed($"t.{slot}.attributes", hash);
        if (at >= 0) {
            _hits2173.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _a_Attribute_write(out, _item2172);
        }
    }
    base.missed("t.*.attributes", $"t.{slot}.attributes", _hits2173.count);
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2180 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2180);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2125 = input.text();
    var _f2126 = _m_TypeName_read(input);
    var _f2130 = Array<GenericParam>();
    var _n2131 = input.count();
    for (var _ in 0.._n2131) {
        var _tag2132 = input.unsigned();
        if (_tag2132 & 1 == 1) {
            _f2130.append(was.generic_params[_tag2132 >> 1]);
        } else {
            _f2130.append(_m_GenericParam_read(input));
        }
    }
    var _f2137 = Array<VariableDef>();
    var _n2138 = input.count();
    for (var _ in 0.._n2138) {
        var _tag2139 = input.unsigned();
        if (_tag2139 & 1 == 1) {
            _f2137.append(was.field_members[_tag2139 >> 1]);
        } else {
            _f2137.append(_m_VariableDef_read(input));
        }
    }
    var _f2144 = Array<FunctionDef>();
    var _n2145 = input.count();
    for (var _ in 0.._n2145) {
        var _tag2146 = input.unsigned();
        if (_tag2146 & 1 == 1) {
            _f2144.append(was.method_members[_tag2146 >> 1]);
        } else {
            _f2144.append(_m_FunctionDef_read(input));
        }
    }
    var _f2151 = Array<FunctionDef>();
    var _n2152 = input.count();
    for (var _ in 0.._n2152) {
        var _tag2153 = input.unsigned();
        if (_tag2153 & 1 == 1) {
            _f2151.append(was.generic_methods[_tag2153 >> 1]);
        } else {
            _f2151.append(_m_FunctionDef_read(input));
        }
    }
    var _f2158 = Array<FunctionDef>();
    var _n2159 = input.count();
    for (var _ in 0.._n2159) {
        var _tag2160 = input.unsigned();
        if (_tag2160 & 1 == 1) {
            _f2158.append(was.constructors[_tag2160 >> 1]);
        } else {
            _f2158.append(_m_FunctionDef_read(input));
        }
    }
    var _f2162 = _m_FunctionDef_read(input);
    var _f2163 = _m_FunctionDef_read(input);
    var _f2164 = _m_FunctionDef_read(input);
    var _f2168 = Array<TypeName>();
    var _n2169 = input.count();
    for (var _ in 0.._n2169) {
        var _tag2170 = input.unsigned();
        if (_tag2170 & 1 == 1) {
            _f2168.append(was.traits[_tag2170 >> 1]);
        } else {
            _f2168.append(_m_TypeName_read(input));
        }
    }
    var _f2175 = Array<ast.Attribute>();
    var _n2176 = input.count();
    for (var _ in 0.._n2176) {
        var _tag2177 = input.unsigned();
        if (_tag2177 & 1 == 1) {
            _f2175.append(was.attributes[_tag2177 >> 1]);
        } else {
            _f2175.append(_a_Attribute_read(input));
        }
    }
    var _f2179 = input.loc();
    var _o2181 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2182 = Array<EnumCaseDef>();
        var _n2183 = input.count();
        for (var _ in 0.._n2183) {
            _v2182.append(_m_EnumCaseDef_read(input));
        }
        _o2181 = Optional<Array<EnumCaseDef>>.Value(_v2182);
    }
    var _f2184 = _o2181;
    return StructDef(
        _f2125, _f2126, _f2130, _f2137, _f2144, _f2151, _f2158, _f2162, _f2163, _f2164, _f2168, _f2175, _f2179, _f2184
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    ulong _j2133 = 0;
    for (var _item2127 in value.generic_params) {
        var scratch = base.scratch();
        _m_GenericParam_write(scratch, _item2127);
        base.add($"t.{slot}.generic_params", scratch, _j2133);
        _j2133 += 1;
    }
    ulong _j2140 = 0;
    for (var _item2134 in value.field_members) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item2134);
        base.add($"t.{slot}.field_members", scratch, _j2140);
        _j2140 += 1;
    }
    ulong _j2147 = 0;
    for (var _item2141 in value.method_members) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2141);
        base.add($"t.{slot}.method_members", scratch, _j2147);
        _j2147 += 1;
    }
    ulong _j2154 = 0;
    for (var _item2148 in value.generic_methods) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2148);
        base.add($"t.{slot}.generic_methods", scratch, _j2154);
        _j2154 += 1;
    }
    ulong _j2161 = 0;
    for (var _item2155 in value.constructors) {
        var scratch = base.scratch();
        _m_FunctionDef_write(scratch, _item2155);
        base.add($"t.{slot}.constructors", scratch, _j2161);
        _j2161 += 1;
    }
    ulong _j2171 = 0;
    for (var _item2165 in value.traits) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item2165);
        base.add($"t.{slot}.traits", scratch, _j2171);
        _j2171 += 1;
    }
    ulong _j2178 = 0;
    for (var _item2172 in value.attributes) {
        var scratch = base.scratch();
        _a_Attribute_write(scratch, _item2172);
        base.add($"t.{slot}.attributes", scratch, _j2178);
        _j2178 += 1;
    }
}

_m_Module_interface_fields(value: Module, interface: bool): Array<(String, String)> {
    var found = Array<(String, String)>();
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.imports.count);
        for (var _item2185 in value.imports) {
            _a_Import_write(out, _item2185);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2186 in value.structs) {
            _m_StructDef_write(out, _item2186);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.traits.count);
        for (var _item2187 in value.traits) {
            _m_TraitDef_write(out, _item2187);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2188 in value.extensions) {
            _m_ExtensionDef_write(out, _item2188);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2189 in value.functions) {
            _m_FunctionDef_write(out, _item2189);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2190 in value.externs) {
            _m_ExternDef_write(out, _item2190);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2191 in value.globals) {
            _m_VariableDef_write(out, _item2191);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2192 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2192);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2193 in value.enums) {
            _m_EnumDef_write(out, _item2193);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2194 in value.struct_specs) {
            _m_TypeName_write(out, _item2194);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2195 in value.func_specs) {
            _m_TypeName_write(out, _item2195);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2196 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2196);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2197 in value.withheld) {
            _m_Withheld_write(out, _item2197);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2198 in value.properties) {
            _m_PropertyDef_write(out, _item2198);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2199 in value.type_uses) {
            _m_TypeUse_write(out, _item2199);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2200 in value.use_contexts) {
            _m_UseContext_write(out, _item2200);
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
            for (var _item2201 in value.literal_args) {
                var (_t2202, _t2203, _t2204) = _item2201;
                out.loc(_t2202);
                out.unsigned(_t2203);
                out.loc(_t2204);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2205 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2205);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2206 in value.trait_types) {
            _m_TraitType_write(out, _item2206);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2207 in value.conversions) {
            _m_Conversion_write(out, _item2207);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2209 = Array<(u8[], u8[], String)>();
        for (var (_key2208, _) in value.overload_sets) {
            var _scratch2210 = out.scratch();
            _scratch2210.text(_key2208);
            var _vscratch2212 = out.scratch();
            _vscratch2212.unsigned(value.overload_sets[_key2208].count);
            for (var _item2213 in value.overload_sets[_key2208]) {
                _vscratch2212.text(_item2213);
            }
            _keys2209.append((_scratch2210.finish(), _vscratch2212.finish(), _key2208));
        }
        _keys2209.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2209.count);
        for (var (_bytes2211, _, _key2208) in _keys2209) {
            out.text(_key2208);
            out.unsigned(value.overload_sets[_key2208].count);
            for (var _item2214 in value.overload_sets[_key2208]) {
                out.text(_item2214);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2216 = Array<(u8[], u8[], String)>();
        for (var (_key2215, _) in value.overload_unions) {
            var _scratch2217 = out.scratch();
            _scratch2217.text(_key2215);
            var _vscratch2219 = out.scratch();
            _vscratch2219.unsigned(value.overload_unions[_key2215].count);
            for (var _item2220 in value.overload_unions[_key2215]) {
                _vscratch2219.unsigned(_item2220.count);
                for (var _item2221 in _item2220) {
                    _vscratch2219.text(_item2221);
                }
            }
            _keys2216.append((_scratch2217.finish(), _vscratch2219.finish(), _key2215));
        }
        _keys2216.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2216.count);
        for (var (_bytes2218, _, _key2215) in _keys2216) {
            out.text(_key2215);
            out.unsigned(value.overload_unions[_key2215].count);
            for (var _item2222 in value.overload_unions[_key2215]) {
                out.unsigned(_item2222.count);
                for (var _item2223 in _item2222) {
                    out.text(_item2223);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2225 = Array<(u8[], u8[], String)>();
        for (var (_key2224, _) in value.method_overload_sets) {
            var _scratch2226 = out.scratch();
            _scratch2226.text(_key2224);
            var _vscratch2228 = out.scratch();
            var _keys2230 = Array<(u8[], u8[], String)>();
            for (var (_key2229, _) in value.method_overload_sets[_key2224]) {
                var _scratch2231 = _vscratch2228.scratch();
                _scratch2231.text(_key2229);
                var _vscratch2233 = _vscratch2228.scratch();
                _vscratch2233.unsigned(value.method_overload_sets[_key2224][_key2229].count);
                for (var _item2234 in value.method_overload_sets[_key2224][_key2229]) {
                    _vscratch2233.text(_item2234);
                }
                _keys2230.append((_scratch2231.finish(), _vscratch2233.finish(), _key2229));
            }
            _keys2230.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2228.unsigned(_keys2230.count);
            for (var (_bytes2232, _, _key2229) in _keys2230) {
                _vscratch2228.text(_key2229);
                _vscratch2228.unsigned(value.method_overload_sets[_key2224][_key2229].count);
                for (var _item2235 in value.method_overload_sets[_key2224][_key2229]) {
                    _vscratch2228.text(_item2235);
                }
            }
            _keys2225.append((_scratch2226.finish(), _vscratch2228.finish(), _key2224));
        }
        _keys2225.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2225.count);
        for (var (_bytes2227, _, _key2224) in _keys2225) {
            out.text(_key2224);
            var _keys2237 = Array<(u8[], u8[], String)>();
            for (var (_key2236, _) in value.method_overload_sets[_key2224]) {
                var _scratch2238 = out.scratch();
                _scratch2238.text(_key2236);
                var _vscratch2240 = out.scratch();
                _vscratch2240.unsigned(value.method_overload_sets[_key2224][_key2236].count);
                for (var _item2241 in value.method_overload_sets[_key2224][_key2236]) {
                    _vscratch2240.text(_item2241);
                }
                _keys2237.append((_scratch2238.finish(), _vscratch2240.finish(), _key2236));
            }
            _keys2237.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2237.count);
            for (var (_bytes2239, _, _key2236) in _keys2237) {
                out.text(_key2236);
                out.unsigned(value.method_overload_sets[_key2224][_key2236].count);
                for (var _item2242 in value.method_overload_sets[_key2224][_key2236]) {
                    out.text(_item2242);
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
        var _keys2244 = Array<(u8[], u8[], Loc)>();
        for (var _key2243 in value.private_functions) {
            var _scratch2245 = out.scratch();
            _scratch2245.loc(_key2243);
            var _vscratch2247 = out.scratch();
            _keys2244.append((_scratch2245.finish(), _vscratch2247.finish(), _key2243));
        }
        _keys2244.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2244.count);
        for (var (_bytes2246, _, _key2243) in _keys2244) {
            out.loc(_key2243);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2249 = Array<(u8[], u8[], Loc)>();
        for (var _key2248 in value.file_private_functions) {
            var _scratch2250 = out.scratch();
            _scratch2250.loc(_key2248);
            var _vscratch2252 = out.scratch();
            _keys2249.append((_scratch2250.finish(), _vscratch2252.finish(), _key2248));
        }
        _keys2249.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2249.count);
        for (var (_bytes2251, _, _key2248) in _keys2249) {
            out.loc(_key2248);
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
            for (var _item2253 in value.call_targets) {
                var (_t2254, _t2255) = _item2253;
                out.loc(_t2254);
                out.text(_t2255);
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
            for (var _item2256 in value.argument_names) {
                var (_t2257, _t2258) = _item2256;
                out.loc(_t2257);
                out.text(_t2258);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2259 in value.namespaces) {
            out.text(_item2259);
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
            for (var _item2260 in value.cached_files) {
                out.flag(_item2260);
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
            var _keys2262 = Array<(u8[], u8[], Loc)>();
            for (var (_key2261, _) in value.recorded_summaries) {
                var _scratch2263 = out.scratch();
                _scratch2263.loc(_key2261);
                var _vscratch2265 = out.scratch();
                _vscratch2265.text(value.recorded_summaries[_key2261]);
                _keys2262.append((_scratch2263.finish(), _vscratch2265.finish(), _key2261));
            }
            _keys2262.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2262.count);
            for (var (_bytes2264, _, _key2261) in _keys2262) {
                out.loc(_key2261);
                out.text(value.recorded_summaries[_key2261]);
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
            var _keys2267 = Array<(u8[], u8[], Loc)>();
            for (var _key2266 in value.stripped) {
                var _scratch2268 = out.scratch();
                _scratch2268.loc(_key2266);
                var _vscratch2270 = out.scratch();
                _keys2267.append((_scratch2268.finish(), _vscratch2270.finish(), _key2266));
            }
            _keys2267.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2267.count);
            for (var (_bytes2269, _, _key2266) in _keys2267) {
                out.loc(_key2266);
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
        var _keys2272 = Array<(u8[], u8[], String)>();
        for (var (_key2271, _) in value.spec_requests) {
            var _scratch2273 = out.scratch();
            _scratch2273.text(_key2271);
            var _vscratch2275 = out.scratch();
            _m_SpecRequest_write(_vscratch2275, value.spec_requests[_key2271]);
            _keys2272.append((_scratch2273.finish(), _vscratch2275.finish(), _key2271));
        }
        _keys2272.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2272.count);
        for (var (_bytes2274, _, _key2271) in _keys2272) {
            out.text(_key2271);
            _m_SpecRequest_write(out, value.spec_requests[_key2271]);
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
            for (var _item2276 in value.summaries_to_record) {
                var (_t2277, _t2278) = _item2276;
                out.loc(_t2277);
                out.text(_t2278);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2280 = Array<(u8[], u8[], String)>();
        for (var (_key2279, _) in value.caller_copies) {
            var _scratch2281 = out.scratch();
            _scratch2281.text(_key2279);
            var _vscratch2283 = out.scratch();
            _vscratch2283.unsigned(value.caller_copies[_key2279].count);
            for (var _item2284 in value.caller_copies[_key2279]) {
                _vscratch2283.flag(_item2284);
            }
            _keys2280.append((_scratch2281.finish(), _vscratch2283.finish(), _key2279));
        }
        _keys2280.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2280.count);
        for (var (_bytes2282, _, _key2279) in _keys2280) {
            out.text(_key2279);
            out.unsigned(value.caller_copies[_key2279].count);
            for (var _item2285 in value.caller_copies[_key2279]) {
                out.flag(_item2285);
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
    for (var _item2286 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2286);
        found.append(("structs " + _item2286.name, interface_text(out)));
    }
    for (var _item2287 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2287);
        found.append(("functions " + _item2287.name, interface_text(out)));
    }
    return found;
}
