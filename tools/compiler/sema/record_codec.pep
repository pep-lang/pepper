## Saving and loading a checked module: a binary writer and reader for
## every type `Module` reaches, the AST nodes it holds included. Generated
## by `scripts/gen-sema-record.py`; do not edit.

import compiler.ast;
import [Loc] from "loc";
import "model";
import "pending";
import [
    anchors_of,
    compare_bytes,
    DeltaBase,
    interface_text,
    merge_by_place,
    RecordIn,
    RecordOut,
    splits_fields,
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
export write_module_delta(out: RecordOut, module: Module, base: DeltaBase) {
    _m_Module_write_delta(out, module, base);
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
    base.anchors = anchors_of(module);
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
        Unsigned(p0) => {
            out.unsigned(2);
            out.unsigned(p0);
        }
        Float(p0) => {
            out.unsigned(3);
            out.number(p0);
        }
        Bool(p0) => {
            out.unsigned(4);
            out.flag(p0);
        }
        Char(p0) => {
            out.unsigned(5);
            out.unsigned(p0 as ulong);
        }
        Null => {
            out.unsigned(6);
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
        var _f840 = input.unsigned();
        return ast.Literal.Unsigned(_f840);
    }
    if (tag == 3) {
        var _f841 = input.number();
        return ast.Literal.Float(_f841);
    }
    if (tag == 4) {
        var _f842 = input.flag();
        return ast.Literal.Bool(_f842);
    }
    if (tag == 5) {
        var _f843 = input.unsigned() as u8;
        return ast.Literal.Char(_f843);
    }
    if (tag == 6) {
        return ast.Literal.Null;
    }
    input.fail("Literal", tag);
    return _a_Literal_read(input);
}

_m_Block_write(out: RecordOut, value: Block) {
    out.text(value.name);
    out.unsigned(value.items.count);
    for (var _item844 in value.items) {
        _m_Statement_write(out, _item844);
    }
    out.unsigned(value.attributes.count);
    for (var _item845 in value.attributes) {
        _a_Attribute_write(out, _item845);
    }
}

_m_Block_read(input: RecordIn): Block {
    var _f846 = input.text();
    var _v847 = Array<Statement>();
    var _n848 = input.count();
    for (var _ in 0.._n848) {
        _v847.append(_m_Statement_read(input));
    }
    var _f849 = _v847;
    var _v850 = Array<ast.Attribute>();
    var _n851 = input.count();
    for (var _ in 0.._n851) {
        _v850.append(_a_Attribute_read(input));
    }
    var _f852 = _v850;
    return Block(_f846, _f849, _f852);
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
        var _f1265 = _m_Expression_read(input);
        return Statement.Expression(_f1265);
    }
    if (tag == 1) {
        var _f1266 = _m_Block_read(input);
        return Statement.Block(_f1266);
    }
    if (tag == 2) {
        var _f1267 = _m_Declaration_read(input);
        return Statement.Declaration(_f1267);
    }
    if (tag == 3) {
        var _f1268 = _m_Branch_read(input);
        return Statement.Branch(_f1268);
    }
    if (tag == 4) {
        var _f1269 = _m_While_read(input);
        return Statement.While(_f1269);
    }
    if (tag == 5) {
        var _f1270 = _m_ReturnStatement_read(input);
        return Statement.Return(_f1270);
    }
    if (tag == 6) {
        var _f1271 = _m_LoopBreak_read(input);
        return Statement.LoopBreak(_f1271);
    }
    if (tag == 7) {
        var _f1272 = _m_StaticBlock_read(input);
        return Statement.Static(_f1272);
    }
    if (tag == 8) {
        var _f1273 = _m_StaticPass_read(input);
        return Statement.StaticPass(_f1273);
    }
    input.fail("Statement", tag);
    return _m_Statement_read(input);
}

_m_StaticPass_write(out: RecordOut, value: StaticPass) {
    out.loc(value.loc);
    out.flag(value.stop);
    out.unsigned(value.values.count);
    for (var _item853 in value.values) {
        var (_t854, _t855) = _item853;
        out.text(_t854);
        _m_StaticConstant_write(out, _t855);
    }
    if (value.header.is_value()) {
        out.unsigned(1);
        out.unsigned(value.header.value() as ulong);
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.lines.count);
    for (var _item856 in value.lines) {
        var (_t857, _t858) = _item856;
        out.loc(_t857);
        out.unsigned(_t858 as ulong);
    }
}

_m_StaticPass_read(input: RecordIn): StaticPass {
    var _f859 = input.loc();
    var _f860 = input.flag();
    var _v861 = Array<(String, StaticConstant)>();
    var _n862 = input.count();
    for (var _ in 0.._n862) {
        var _t863 = input.text();
        var _t864 = _m_StaticConstant_read(input);
        _v861.append((_t863, _t864));
    }
    var _f865 = _v861;
    var _o866 = Optional<uint>.Empty;
    if (input.unsigned() == 1) {
        _o866 = Optional<uint>.Value(input.unsigned() as uint);
    }
    var _f867 = _o866;
    var _v868 = Array<(Loc, uint)>();
    var _n869 = input.count();
    for (var _ in 0.._n869) {
        var _t870 = input.loc();
        var _t871 = input.unsigned() as uint;
        _v868.append((_t870, _t871));
    }
    var _f872 = _v868;
    return StaticPass(_f859, _f860, _f865, _f867, _f872);
}

_m_RecordStaticConstant_write(out: RecordOut, value: RecordStaticConstant) {
    out.text(value.name);
    out.unsigned(value.fields.count);
    for (var _item1278 in value.fields) {
        var (_t1279, _t1280) = _item1278;
        out.text(_t1279);
        _m_StaticConstant_write(out, _t1280);
    }
}

_m_RecordStaticConstant_read(input: RecordIn): RecordStaticConstant {
    var _f1281 = input.text();
    var _v1282 = Array<(String, StaticConstant)>();
    var _n1283 = input.count();
    for (var _ in 0.._n1283) {
        var _t1284 = input.text();
        var _t1285 = _m_StaticConstant_read(input);
        _v1282.append((_t1284, _t1285));
    }
    var _f1286 = _v1282;
    return RecordStaticConstant(_f1281, _f1286);
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
        var _f1274 = input.signed();
        return StaticConstant.Int(_f1274);
    }
    if (tag == 1) {
        var _f1275 = input.number();
        return StaticConstant.Float(_f1275);
    }
    if (tag == 2) {
        var _f1276 = input.flag();
        return StaticConstant.Bool(_f1276);
    }
    if (tag == 3) {
        var _f1277 = input.text();
        return StaticConstant.String(_f1277);
    }
    if (tag == 4) {
        return StaticConstant.Record(_m_RecordStaticConstant_read(input));
    }
    input.fail("StaticConstant", tag);
    return _m_StaticConstant_read(input);
}

_m_StaticBlock_write(out: RecordOut, value: StaticBlock) {
    out.unsigned(value.captures.count);
    for (var _item873 in value.captures) {
        out.text(_item873);
    }
    out.unsigned(value.items.count);
    for (var _item874 in value.items) {
        _m_StaticItem_write(out, _item874);
    }
    out.unsigned(value.type_map.count);
    for (var _item875 in value.type_map) {
        var (_t876, _t877) = _item875;
        out.text(_t876);
        _m_TypeName_write(out, _t877);
    }
    out.loc(value.loc);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_StaticBlock_read(input: RecordIn): StaticBlock {
    var _v878 = Array<String>();
    var _n879 = input.count();
    for (var _ in 0.._n879) {
        _v878.append(input.text());
    }
    var _f880 = _v878;
    var _v881 = Array<StaticItem>();
    var _n882 = input.count();
    for (var _ in 0.._n882) {
        _v881.append(_m_StaticItem_read(input));
    }
    var _f883 = _v881;
    var _v884 = Array<(String, TypeName)>();
    var _n885 = input.count();
    for (var _ in 0.._n885) {
        var _t886 = input.text();
        var _t887 = _m_TypeName_read(input);
        _v884.append((_t886, _t887));
    }
    var _f888 = _v884;
    var _f889 = input.loc();
    var _s890 = input.unsigned();
    var _f891 = ast.Span(_s890, input.unsigned());
    return StaticBlock(_f880, _f883, _f888, _f889, _f891);
}

_m_TypeName_write(out: RecordOut, value: TypeName) {
    out.text(value.name);
    out.unsigned(value.sub_types.count);
    for (var _item892 in value.sub_types) {
        _m_TypeName_write(out, _item892);
    }
    _m_TypeFlags_write(out, value.flags);
    out.unsigned(value.labels.count);
    for (var _item893 in value.labels) {
        out.text(_item893);
    }
}

_m_TypeName_read(input: RecordIn): TypeName {
    var _f894 = input.text();
    var _v895 = Array<TypeName>();
    var _n896 = input.count();
    for (var _ in 0.._n896) {
        _v895.append(_m_TypeName_read(input));
    }
    var _f897 = _v895;
    var _f898 = _m_TypeFlags_read(input);
    var _v899 = Array<String>();
    var _n900 = input.count();
    for (var _ in 0.._n900) {
        _v899.append(input.text());
    }
    var _f901 = _v899;
    return TypeName(_f894, _f897, _f898, _f901);
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
    for (var _item1287 in value.body) {
        _m_StaticItem_write(out, _item1287);
    }
    out.loc(value.loc);
}

_m_ForStaticItem_read(input: RecordIn): ForStaticItem {
    var _f1288 = input.text();
    var _f1289 = _a_Expression_read(input);
    var _v1290 = Array<StaticItem>();
    var _n1291 = input.count();
    for (var _ in 0.._n1291) {
        _v1290.append(_m_StaticItem_read(input));
    }
    var _f1292 = _v1290;
    var _f1293 = input.loc();
    return ForStaticItem(_f1289, _f1288, _f1292, _f1293);
}

_m_WhileStaticItem_write(out: RecordOut, value: WhileStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.body.count);
    for (var _item1294 in value.body) {
        _m_StaticItem_write(out, _item1294);
    }
    out.loc(value.loc);
}

_m_WhileStaticItem_read(input: RecordIn): WhileStaticItem {
    var _f1295 = _a_Expression_read(input);
    var _v1296 = Array<StaticItem>();
    var _n1297 = input.count();
    for (var _ in 0.._n1297) {
        _v1296.append(_m_StaticItem_read(input));
    }
    var _f1298 = _v1296;
    var _f1299 = input.loc();
    return WhileStaticItem(_f1295, _f1298, _f1299);
}

_m_JumpStaticItem_write(out: RecordOut, value: JumpStaticItem) {
    _m_LoopBreakKind_write(out, value.kind);
    out.loc(value.loc);
}

_m_JumpStaticItem_read(input: RecordIn): JumpStaticItem {
    var _f1300 = _m_LoopBreakKind_read(input);
    var _f1301 = input.loc();
    return JumpStaticItem(_f1300, _f1301);
}

_m_IfStaticItem_write(out: RecordOut, value: IfStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1302 in value.then_items) {
        _m_StaticItem_write(out, _item1302);
    }
    out.unsigned(value.else_items.count);
    for (var _item1303 in value.else_items) {
        _m_StaticItem_write(out, _item1303);
    }
    out.loc(value.loc);
}

_m_IfStaticItem_read(input: RecordIn): IfStaticItem {
    var _f1304 = _a_Expression_read(input);
    var _v1305 = Array<StaticItem>();
    var _n1306 = input.count();
    for (var _ in 0.._n1306) {
        _v1305.append(_m_StaticItem_read(input));
    }
    var _f1307 = _v1305;
    var _v1308 = Array<StaticItem>();
    var _n1309 = input.count();
    for (var _ in 0.._n1309) {
        _v1308.append(_m_StaticItem_read(input));
    }
    var _f1310 = _v1308;
    var _f1311 = input.loc();
    return IfStaticItem(_f1304, _f1307, _f1310, _f1311);
}

_m_EmitIfStaticItem_write(out: RecordOut, value: EmitIfStaticItem) {
    _m_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1312 in value.then_items) {
        _m_StaticItem_write(out, _item1312);
    }
    out.unsigned(value.else_items.count);
    for (var _item1313 in value.else_items) {
        _m_StaticItem_write(out, _item1313);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_EmitIfStaticItem_read(input: RecordIn): EmitIfStaticItem {
    var _f1314 = _m_Expression_read(input);
    var _v1315 = Array<StaticItem>();
    var _n1316 = input.count();
    for (var _ in 0.._n1316) {
        _v1315.append(_m_StaticItem_read(input));
    }
    var _f1317 = _v1315;
    var _v1318 = Array<StaticItem>();
    var _n1319 = input.count();
    for (var _ in 0.._n1319) {
        _v1318.append(_m_StaticItem_read(input));
    }
    var _f1320 = _v1318;
    var _s1321 = input.unsigned();
    var _f1322 = ast.Span(_s1321, input.unsigned());
    return EmitIfStaticItem(_f1314, _f1317, _f1320, _f1322);
}

_m_VarStaticItem_write(out: RecordOut, value: VarStaticItem) {
    out.text(value.name);
    _a_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_VarStaticItem_read(input: RecordIn): VarStaticItem {
    var _f1327 = input.text();
    var _f1328 = _a_Expression_read(input);
    var _f1329 = input.loc();
    return VarStaticItem(_f1328, _f1327, _f1329);
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
            for (var _item1323 in v) {
                _m_StaticItem_write(out, _item1323);
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
        var _v1324 = Array<StaticItem>();
        var _n1325 = input.count();
        for (var _ in 0.._n1325) {
            _v1324.append(_m_StaticItem_read(input));
        }
        var _f1326 = _v1324;
        return StaticItem.Block(_f1326);
    }
    if (tag == 6) {
        return StaticItem.Var(_m_VarStaticItem_read(input));
    }
    if (tag == 7) {
        var _f1330 = _a_Expression_read(input);
        return StaticItem.Evaluate(_f1330);
    }
    if (tag == 8) {
        var _f1331 = _m_Statement_read(input);
        var _s1332 = input.unsigned();
        var _f1333 = ast.Span(_s1332, input.unsigned());
        return StaticItem.Emit(_f1331, _f1333);
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
    var _f1334 = input.text();
    var _f1335 = _m_TypeName_read(input);
    var _f1336 = input.loc();
    return SymbolRefExpression(_f1334, _f1335, _f1336);
}

_m_MemberRefExpression_write(out: RecordOut, value: MemberRefExpression) {
    _m_Expression_write(out, value.lhs);
    out.text(value.name);
    out.loc(value.loc);
}

_m_MemberRefExpression_read(input: RecordIn): MemberRefExpression {
    var _f1337 = _m_Expression_read(input);
    var _f1338 = input.text();
    var _f1339 = input.loc();
    return MemberRefExpression(_f1337, _f1338, _f1339);
}

_m_StringLiteralExpression_write(out: RecordOut, value: StringLiteralExpression) {
    out.text(value.value);
    out.flag(value.is_raw);
    out.loc(value.loc);
}

_m_StringLiteralExpression_read(input: RecordIn): StringLiteralExpression {
    var _f1343 = input.text();
    var _f1344 = input.flag();
    var _f1345 = input.loc();
    return StringLiteralExpression(_f1343, _f1344, _f1345);
}

_m_BinaryExpression_write(out: RecordOut, value: BinaryExpression) {
    _m_BinaryOp_write(out, value.op);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_BinaryExpression_read(input: RecordIn): BinaryExpression {
    var _f1346 = _m_BinaryOp_read(input);
    var _f1347 = _m_Expression_read(input);
    var _f1348 = _m_Expression_read(input);
    var _f1349 = input.loc();
    return BinaryExpression(_f1347, _f1348, _f1346, _f1349);
}

_m_UnaryExpression_write(out: RecordOut, value: UnaryExpression) {
    _m_UnaryOp_write(out, value.op);
    _m_Expression_write(out, value.operand);
    out.loc(value.loc);
}

_m_UnaryExpression_read(input: RecordIn): UnaryExpression {
    var _f1350 = _m_UnaryOp_read(input);
    var _f1351 = _m_Expression_read(input);
    var _f1352 = input.loc();
    return UnaryExpression(_f1351, _f1350, _f1352);
}

_m_CastExpression_write(out: RecordOut, value: CastExpression) {
    _m_Expression_write(out, value.expr);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
    _m_CastKind_write(out, value.kind);
}

_m_CastExpression_read(input: RecordIn): CastExpression {
    var _f1353 = _m_Expression_read(input);
    var _f1354 = _m_TypeName_read(input);
    var _f1355 = input.loc();
    var _f1356 = _m_CastKind_read(input);
    return CastExpression(_f1353, _f1354, _f1355, _f1356);
}

_m_TernaryExpression_write(out: RecordOut, value: TernaryExpression) {
    _m_Expression_write(out, value.condition);
    _m_Expression_write(out, value.true_expr);
    _m_Expression_write(out, value.false_expr);
}

_m_TernaryExpression_read(input: RecordIn): TernaryExpression {
    var _f1357 = _m_Expression_read(input);
    var _f1358 = _m_Expression_read(input);
    var _f1359 = _m_Expression_read(input);
    return TernaryExpression(_f1357, _f1358, _f1359);
}

_m_IndexExpression_write(out: RecordOut, value: IndexExpression) {
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_IndexExpression_read(input: RecordIn): IndexExpression {
    var _f1360 = _m_Expression_read(input);
    var _f1361 = _m_Expression_read(input);
    var _f1362 = input.loc();
    return IndexExpression(_f1360, _f1361, _f1362);
}

_m_ArrayIndexExpression_write(out: RecordOut, value: ArrayIndexExpression) {
    _m_TypeName_write(out, value.ty);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_ArrayIndexExpression_read(input: RecordIn): ArrayIndexExpression {
    var _f1363 = _m_TypeName_read(input);
    var _f1364 = _m_Expression_read(input);
    var _f1365 = _m_Expression_read(input);
    var _f1366 = input.loc();
    return ArrayIndexExpression(_f1364, _f1365, _f1363, _f1366);
}

_m_SimdExpression_write(out: RecordOut, value: SimdExpression) {
    _m_SimdOp_write(out, value.op);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1390 in value.args) {
        _m_Expression_write(out, _item1390);
    }
    out.loc(value.loc);
}

_m_SimdExpression_read(input: RecordIn): SimdExpression {
    var _f1391 = _m_SimdOp_read(input);
    var _f1392 = _m_TypeName_read(input);
    var _v1393 = Array<Expression>();
    var _n1394 = input.count();
    for (var _ in 0.._n1394) {
        _v1393.append(_m_Expression_read(input));
    }
    var _f1395 = _v1393;
    var _f1396 = input.loc();
    return SimdExpression(_f1391, _f1392, _f1395, _f1396);
}

_m_CountStepExpression_write(out: RecordOut, value: CountStepExpression) {
    _m_CountField_write(out, value.field);
    out.flag(value.increment);
    out.flag(value.atomic);
}

_m_CountStepExpression_read(input: RecordIn): CountStepExpression {
    var _f1400 = _m_CountField_read(input);
    var _f1401 = input.flag();
    var _f1402 = input.flag();
    return CountStepExpression(_f1400, _f1401, _f1402);
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
    var _o1403 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1403 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1404 = _o1403;
    var _f1405 = input.text();
    var _f1406 = input.loc();
    return FunctionPointerExpression(_f1404, _f1405, _f1406);
}

_m_FunctionCallExpression_write(out: RecordOut, value: FunctionCallExpression) {
    out.text(value.function);
    out.unsigned(value.args.count);
    for (var _item1407 in value.args) {
        _m_Expression_write(out, _item1407);
    }
    out.loc(value.loc);
    if (value.labeled.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.labeled.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.bare);
}

_m_FunctionCallExpression_read(input: RecordIn): FunctionCallExpression {
    var _f1408 = input.text();
    var _v1409 = Array<Expression>();
    var _n1410 = input.count();
    for (var _ in 0.._n1410) {
        _v1409.append(_m_Expression_read(input));
    }
    var _f1411 = _v1409;
    var _f1412 = input.loc();
    var _o1413 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1413 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1414 = _o1413;
    var _f1415 = input.flag();
    return FunctionCallExpression(_f1408, _f1411, _f1412, _f1414, _f1415);
}

_m_NamedArgumentExpression_write(out: RecordOut, value: NamedArgumentExpression) {
    out.text(value.name);
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_NamedArgumentExpression_read(input: RecordIn): NamedArgumentExpression {
    var _f1416 = input.text();
    var _f1417 = _m_Expression_read(input);
    var _f1418 = input.loc();
    return NamedArgumentExpression(_f1417, _f1416, _f1418);
}

_m_DefaultArgumentExpression_write(out: RecordOut, value: DefaultArgumentExpression) {
    _m_TypeName_write(out, value.ty);
}

_m_DefaultArgumentExpression_read(input: RecordIn): DefaultArgumentExpression {
    var _f1419 = _m_TypeName_read(input);
    return DefaultArgumentExpression(_f1419);
}

_m_MethodCallExpression_write(out: RecordOut, value: MethodCallExpression) {
    _m_Expression_write(out, value.this_value);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item1420 in value.args) {
        _m_Expression_write(out, _item1420);
    }
    out.loc(value.loc);
    if (value.labeled.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.labeled.value());
    } else {
        out.unsigned(0);
    }
}

_m_MethodCallExpression_read(input: RecordIn): MethodCallExpression {
    var _f1421 = _m_Expression_read(input);
    var _f1422 = input.text();
    var _v1423 = Array<Expression>();
    var _n1424 = input.count();
    for (var _ in 0.._n1424) {
        _v1423.append(_m_Expression_read(input));
    }
    var _f1425 = _v1423;
    var _f1426 = input.loc();
    var _o1427 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1427 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1428 = _o1427;
    return MethodCallExpression(_f1421, _f1422, _f1425, _f1426, _f1428);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1429 = input.text();
    var _f1430 = _m_TypeName_read(input);
    var _f1431 = input.loc();
    return FunctionRefExpression(_f1429, _f1430, _f1431);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1432 in value.args) {
        _m_Expression_write(out, _item1432);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1433 = _m_Expression_read(input);
    var _v1434 = Array<Expression>();
    var _n1435 = input.count();
    for (var _ in 0.._n1435) {
        _v1434.append(_m_Expression_read(input));
    }
    var _f1436 = _v1434;
    return InvokeExpression(_f1433, _f1436);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1438 = _m_Expression_read(input);
    var _f1439 = input.text();
    var _f1440 = _m_TypeName_read(input);
    var _f1441 = input.loc();
    return MakeClosureExpression(_f1438, _f1439, _f1440, _f1441);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1443 in value.args) {
        _m_Expression_write(out, _item1443);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1444 = _m_Expression_read(input);
    var _v1445 = Array<Expression>();
    var _n1446 = input.count();
    for (var _ in 0.._n1446) {
        _v1445.append(_m_Expression_read(input));
    }
    var _f1447 = _v1445;
    return CallPointerExpression(_f1444, _f1447);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1450 = _m_Expression_read(input);
    var _f1451 = input.loc();
    return MoveExpression(_f1450, _f1451);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1452 = _m_Expression_read(input);
    var _f1453 = input.unsigned();
    var _f1454 = input.loc();
    return DestructureExpression(_f1452, _f1453, _f1454);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1457 = _m_TypeName_read(input);
    var _f1458 = input.signed();
    return StaticCaseExpression(_f1457, _f1458);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1459 = input.text();
    var _f1460 = input.loc();
    return StaticStringExpression(_f1459, _f1460);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1462 = input.unsigned();
    var _f1463 = _m_TypeName_read(input);
    var _f1464 = input.loc();
    return SubjectExpression(_f1462, _f1463, _f1464);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1465 = _m_Expression_read(input);
    var _f1466 = _m_TypeName_read(input);
    var _f1467 = _m_TypeName_read(input);
    var _f1468 = input.loc();
    return ToTraitExpression(_f1465, _f1466, _f1467, _f1468);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1469 in value.candidates) {
        _m_TypeName_write(out, _item1469);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1470 = _m_Expression_read(input);
    var _f1471 = _m_TypeName_read(input);
    var _f1472 = _m_TypeName_read(input);
    var _v1473 = Array<TypeName>();
    var _n1474 = input.count();
    for (var _ in 0.._n1474) {
        _v1473.append(_m_TypeName_read(input));
    }
    var _f1475 = _v1473;
    var _f1476 = input.flag();
    var _f1477 = input.loc();
    return FromTraitExpression(_f1470, _f1471, _f1472, _f1475, _f1476, _f1477);
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
        var _f1340 = input.flag();
        return Expression.BoolLiteral(_f1340);
    }
    if (tag == 4) {
        var _f1341 = input.signed();
        return Expression.IntLiteral(_f1341);
    }
    if (tag == 5) {
        var _f1342 = input.number();
        return Expression.FloatLiteral(_f1342);
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
        var _f1367 = _m_TypeName_read(input);
        return Expression.SizeOf(_f1367);
    }
    if (tag == 15) {
        var _f1368 = _m_TypeName_read(input);
        return Expression.IsPod(_f1368);
    }
    if (tag == 16) {
        var _f1369 = _m_TypeName_read(input);
        return Expression.Default(_f1369);
    }
    if (tag == 17) {
        var _f1370 = _m_TypeName_read(input);
        return Expression.Allocate(_f1370);
    }
    if (tag == 18) {
        var _f1371 = _m_TypeName_read(input);
        var _f1372 = _m_Expression_read(input);
        return Expression.RefCount(_f1371, _f1372);
    }
    if (tag == 19) {
        var _f1373 = _m_TypeName_read(input);
        var _f1374 = _m_Expression_read(input);
        return Expression.Address(_f1373, _f1374);
    }
    if (tag == 20) {
        var _f1375 = _m_TypeName_read(input);
        var _f1376 = _m_Expression_read(input);
        return Expression.AtomicLoad(_f1375, _f1376);
    }
    if (tag == 21) {
        var _f1377 = _m_TypeName_read(input);
        var _f1378 = _m_Expression_read(input);
        var _f1379 = _m_Expression_read(input);
        return Expression.AtomicStore(_f1377, _f1378, _f1379);
    }
    if (tag == 22) {
        var _f1380 = _m_Expression_read(input);
        var _f1381 = _m_Expression_read(input);
        return Expression.ConstructAt(_f1380, _f1381);
    }
    if (tag == 23) {
        var _f1382 = _m_TypeName_read(input);
        var _f1383 = _m_Expression_read(input);
        var _f1384 = _m_Expression_read(input);
        var _f1385 = _m_Expression_read(input);
        return Expression.AtomicCmpXchg(_f1382, _f1383, _f1384, _f1385);
    }
    if (tag == 24) {
        var _f1386 = _m_AtomicFetchOp_read(input);
        var _f1387 = _m_TypeName_read(input);
        var _f1388 = _m_Expression_read(input);
        var _f1389 = _m_Expression_read(input);
        return Expression.AtomicFetch(_f1386, _f1387, _f1388, _f1389);
    }
    if (tag == 25) {
        return Expression.Simd(_m_SimdExpression_read(input));
    }
    if (tag == 26) {
        var _f1397 = _m_WeakOp_read(input);
        var _f1398 = _m_TypeName_read(input);
        var _f1399 = _m_Expression_read(input);
        return Expression.Weak(_f1397, _f1398, _f1399);
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
        var _f1437 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1437);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1442 = input.text();
        return Expression.MethodAddress(_f1442);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1448 = _m_Expression_read(input);
        return Expression.ForIterator(_f1448);
    }
    if (tag == 40) {
        var _f1449 = _m_Expression_read(input);
        return Expression.WithEntered(_f1449);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1455 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1455);
    }
    if (tag == 44) {
        var _f1456 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1456);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1461 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1461);
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
        var _f1478 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1478);
    }
    if (tag == 53) {
        var _f1479 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1479);
    }
    input.fail("Expression", tag);
    return _m_Expression_read(input);
}

_m_StaticMember_write(out: RecordOut, value: StaticMember) {
    _a_Expression_write(out, value.member);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item902 in value.args) {
        _m_Expression_write(out, _item902);
    }
    out.loc(value.loc);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.argument_spans.count);
    for (var _item903 in value.argument_spans) {
        out.unsigned(out.blank_locs ? 0 : _item903.start);
        out.unsigned(out.blank_locs ? 0 : _item903.end);
    }
}

_m_StaticMember_read(input: RecordIn): StaticMember {
    var _f904 = _a_Expression_read(input);
    var _f905 = input.text();
    var _v906 = Array<Expression>();
    var _n907 = input.count();
    for (var _ in 0.._n907) {
        _v906.append(_m_Expression_read(input));
    }
    var _f908 = _v906;
    var _f909 = input.loc();
    var _s910 = input.unsigned();
    var _f911 = ast.Span(_s910, input.unsigned());
    var _v912 = Array<ast.Span>();
    var _n913 = input.count();
    for (var _ in 0.._n913) {
        var _s914 = input.unsigned();
        _v912.append(ast.Span(_s914, input.unsigned()));
    }
    var _f915 = _v912;
    return StaticMember(_f904, _f905, _f908, _f909, _f911, _f915);
}

_m_StaticValue_write(out: RecordOut, value: StaticValue) {
    _a_Expression_write(out, value.expr);
    out.loc(value.loc);
}

_m_StaticValue_read(input: RecordIn): StaticValue {
    var _f916 = _a_Expression_read(input);
    var _f917 = input.loc();
    return StaticValue(_f916, _f917);
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
    var _f918 = input.unsigned();
    var _f919 = _m_Expression_read(input);
    var _f920 = _m_Expression_read(input);
    var _o921 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o921 = Optional<String>.Value(input.text());
    }
    var _f922 = _o921;
    var _f923 = input.loc();
    return WithSubject(_f919, _f920, _f918, _f922, _f923);
}

_m_CaseValue_write(out: RecordOut, value: CaseValue) {
    _m_Expression_write(out, value.subject);
    out.text(value.name);
    out.unsigned(value.choices.count);
    for (var _item924 in value.choices) {
        _m_CaseChoice_write(out, _item924);
    }
    out.loc(value.loc);
}

_m_CaseValue_read(input: RecordIn): CaseValue {
    var _f925 = _m_Expression_read(input);
    var _f926 = input.text();
    var _v927 = Array<CaseChoice>();
    var _n928 = input.count();
    for (var _ in 0.._n928) {
        _v927.append(_m_CaseChoice_read(input));
    }
    var _f929 = _v927;
    var _f930 = input.loc();
    return CaseValue(_f925, _f926, _f929, _f930);
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
    for (var _item931 in value.bindings) {
        out.loc(_item931);
    }
    out.loc(value.loc);
}

_m_CaseChoice_read(input: RecordIn): CaseChoice {
    var _f932 = input.text();
    var _f933 = input.loc();
    var _o934 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o934 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f935 = _o934;
    var _f936 = input.unsigned();
    var _v937 = Array<Loc>();
    var _n938 = input.count();
    for (var _ in 0.._n938) {
        _v937.append(input.loc());
    }
    var _f939 = _v937;
    var _f940 = input.loc();
    return CaseChoice(_f932, _f933, _f935, _f936, _f939, _f940);
}

_m_MatchArmTest_write(out: RecordOut, value: MatchArmTest) {
    _m_Expression_write(out, value.subject);
    out.unsigned(value.patterns.count);
    for (var _item941 in value.patterns) {
        _m_CasePattern_write(out, _item941);
    }
    _m_MatchSite_write(out, value.site);
    out.unsigned(value.element_names.count);
    for (var _item942 in value.element_names) {
        _m_ElementName_write(out, _item942);
    }
    out.flag(value.guarded);
}

_m_MatchArmTest_read(input: RecordIn): MatchArmTest {
    var _f943 = _m_Expression_read(input);
    var _v944 = Array<CasePattern>();
    var _n945 = input.count();
    for (var _ in 0.._n945) {
        _v944.append(_m_CasePattern_read(input));
    }
    var _f946 = _v944;
    var _f947 = _m_MatchSite_read(input);
    var _v948 = Array<ElementName>();
    var _n949 = input.count();
    for (var _ in 0.._n949) {
        _v948.append(_m_ElementName_read(input));
    }
    var _f950 = _v948;
    var _f951 = input.flag();
    return MatchArmTest(_f943, _f946, _f947, _f950, _f951);
}

_m_ElementName_write(out: RecordOut, value: ElementName) {
    out.text(value.name);
    out.loc(value.loc);
    out.flag(value.declared);
    if (value.missing.is_value()) {
        out.unsigned(1);
        var (_t952, _t953) = value.missing.value();
        out.text(_t952);
        out.loc(_t953);
    } else {
        out.unsigned(0);
    }
}

_m_ElementName_read(input: RecordIn): ElementName {
    var _f954 = input.text();
    var _f955 = input.loc();
    var _f956 = input.flag();
    var _o957 = Optional<(String, Loc)>.Empty;
    if (input.unsigned() == 1) {
        var _t958 = input.text();
        var _t959 = input.loc();
        _o957 = Optional<(String, Loc)>.Value((_t958, _t959));
    }
    var _f960 = _o957;
    return ElementName(_f954, _f955, _f956, _f960);
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
    var _f961 = input.unsigned();
    var _f962 = input.loc();
    var _o963 = Optional<Loc>.Empty;
    if (input.unsigned() == 1) {
        _o963 = Optional<Loc>.Value(input.loc());
    }
    var _f964 = _o963;
    var _f965 = input.flag();
    var _f966 = input.flag();
    return MatchSite(_f961, _f962, _f964, _f965, _f966);
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
        for (var _item967 in value.bindings.value()) {
            _m_CasePattern_write(out, _item967);
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
        for (var _item968 in value.elements.value()) {
            _m_CasePattern_write(out, _item968);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.range);
    out.flag(value.constant);
    if (value.values.is_value()) {
        out.unsigned(1);
        var (_t969, _t970) = value.values.value();
        out.signed(_t969 as long);
        out.signed(_t970 as long);
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
    var _o971 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o971 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f972 = _o971;
    var _f973 = input.text();
    var _f974 = input.loc();
    var _o975 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v976 = Array<CasePattern>();
        var _n977 = input.count();
        for (var _ in 0.._n977) {
            _v976.append(_m_CasePattern_read(input));
        }
        _o975 = Optional<Array<CasePattern>>.Value(_v976);
    }
    var _f978 = _o975;
    var _o979 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o979 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f980 = _o979;
    var _o981 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v982 = Array<CasePattern>();
        var _n983 = input.count();
        for (var _ in 0.._n983) {
            _v982.append(_m_CasePattern_read(input));
        }
        _o981 = Optional<Array<CasePattern>>.Value(_v982);
    }
    var _f984 = _o981;
    var _f985 = input.flag();
    var _f986 = input.flag();
    var _o987 = Optional<(long, long)>.Empty;
    if (input.unsigned() == 1) {
        var _t988 = input.signed();
        var _t989 = input.signed();
        _o987 = Optional<(long, long)>.Value((_t988, _t989));
    }
    var _f990 = _o987;
    var _o991 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o991 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f992 = _o991;
    return CasePattern(_f972, _f973, _f974, _f978, _f980, _f984, _f985, _f986, _f990, _f992);
}

_m_ClosureLiteral_write(out: RecordOut, value: ClosureLiteral) {
    out.unsigned(value.parameters.count);
    for (var _item993 in value.parameters) {
        _m_VariableDef_write(out, _item993);
    }
    _m_TypeName_write(out, value.ty);
    _m_Block_write(out, value.body);
    out.flag(value.expression_body);
    out.loc(value.loc);
}

_m_ClosureLiteral_read(input: RecordIn): ClosureLiteral {
    var _v994 = Array<VariableDef>();
    var _n995 = input.count();
    for (var _ in 0.._n995) {
        _v994.append(_m_VariableDef_read(input));
    }
    var _f996 = _v994;
    var _f997 = _m_TypeName_read(input);
    var _f998 = _m_Block_read(input);
    var _f999 = input.flag();
    var _f1000 = input.loc();
    return ClosureLiteral(_f996, _f997, _f998, _f999, _f1000);
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
    for (var _item1001 in value.attributes) {
        _a_Attribute_write(out, _item1001);
    }
    out.loc(value.loc);
    out.loc(value.type_loc);
    out.flag(value.is_const);
}

_m_VariableDef_read(input: RecordIn): VariableDef {
    var _f1002 = input.text();
    var _f1003 = _m_TypeName_read(input);
    var _o1004 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o1004 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f1005 = _o1004;
    var _f1006 = input.flag();
    var _f1007 = _m_Kind_read(input);
    var _v1008 = Array<ast.Attribute>();
    var _n1009 = input.count();
    for (var _ in 0.._n1009) {
        _v1008.append(_a_Attribute_read(input));
    }
    var _f1010 = _v1008;
    var _f1011 = input.loc();
    var _f1012 = input.loc();
    var _f1013 = input.flag();
    return VariableDef(_f1002, _f1003, _f1005, _f1006, _f1007, _f1010, _f1011, _f1012, _f1013);
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
    var _f1014 = _m_LoopBreakKind_read(input);
    return LoopBreak(_f1014);
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
    var _o1015 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o1015 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f1016 = _o1015;
    var _f1017 = input.loc();
    return ReturnStatement(_f1016, _f1017);
}

_m_While_write(out: RecordOut, value: While) {
    _m_Expression_write(out, value.condition);
    _m_Block_write(out, value.block);
}

_m_While_read(input: RecordIn): While {
    var _f1018 = _m_Expression_read(input);
    var _f1019 = _m_Block_read(input);
    return While(_f1018, _f1019);
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
    var _f1020 = _m_Expression_read(input);
    var _f1021 = _m_Block_read(input);
    var _o1022 = Optional<Block>.Empty;
    if (input.unsigned() == 1) {
        _o1022 = Optional<Block>.Value(_m_Block_read(input));
    }
    var _f1023 = _o1022;
    return Branch(_f1020, _f1021, _f1023);
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
        var _f1480 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1480);
    }
    if (tag == 1) {
        var _f1481 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1481);
    }
    if (tag == 2) {
        var _f1482 = _m_StructDef_read(input);
        return Declaration.Struct(_f1482);
    }
    if (tag == 3) {
        var _f1483 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1483);
    }
    if (tag == 4) {
        var _f1484 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1484);
    }
    if (tag == 5) {
        var _f1485 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1485);
    }
    if (tag == 6) {
        var _f1486 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1486);
    }
    input.fail("Declaration", tag);
    return _m_Declaration_read(input);
}

_m_TypeAliasDef_write(out: RecordOut, value: TypeAliasDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1024 in value.generic_params) {
        _m_GenericParam_write(out, _item1024);
    }
    _m_TypeName_write(out, value.target);
    out.unsigned(value.attributes.count);
    for (var _item1025 in value.attributes) {
        _a_Attribute_write(out, _item1025);
    }
    out.loc(value.loc);
}

_m_TypeAliasDef_read(input: RecordIn): TypeAliasDef {
    var _f1026 = input.text();
    var _v1027 = Array<GenericParam>();
    var _n1028 = input.count();
    for (var _ in 0.._n1028) {
        _v1027.append(_m_GenericParam_read(input));
    }
    var _f1029 = _v1027;
    var _f1030 = _m_TypeName_read(input);
    var _v1031 = Array<ast.Attribute>();
    var _n1032 = input.count();
    for (var _ in 0.._n1032) {
        _v1031.append(_a_Attribute_read(input));
    }
    var _f1033 = _v1031;
    var _f1034 = input.loc();
    return TypeAliasDef(_f1026, _f1029, _f1030, _f1033, _f1034);
}

_m_GenericParam_write(out: RecordOut, value: GenericParam) {
    out.text(value.name);
    out.loc(value.loc);
    out.unsigned(value.bounds.count);
    for (var _item1035 in value.bounds) {
        _m_Bound_write(out, _item1035);
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
    var _f1036 = input.text();
    var _f1037 = input.loc();
    var _v1038 = Array<Bound>();
    var _n1039 = input.count();
    for (var _ in 0.._n1039) {
        _v1038.append(_m_Bound_read(input));
    }
    var _f1040 = _v1038;
    var _o1041 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1041 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1042 = _o1041;
    var _f1043 = input.loc();
    var _f1044 = input.flag();
    return GenericParam(_f1036, _f1037, _f1040, _f1042, _f1043, _f1044);
}

_m_Bound_write(out: RecordOut, value: Bound) {
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_Bound_read(input: RecordIn): Bound {
    var _f1045 = _m_TypeName_read(input);
    var _f1046 = input.loc();
    return Bound(_f1045, _f1046);
}

_m_ExternDef_write(out: RecordOut, value: ExternDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.parameters.count);
    for (var _item1047 in value.parameters) {
        _m_VariableDef_write(out, _item1047);
    }
    out.flag(value.is_variadic);
    out.unsigned(value.attributes.count);
    for (var _item1048 in value.attributes) {
        _a_Attribute_write(out, _item1048);
    }
    out.loc(value.loc);
}

_m_ExternDef_read(input: RecordIn): ExternDef {
    var _f1049 = input.text();
    var _f1050 = _m_TypeName_read(input);
    var _v1051 = Array<VariableDef>();
    var _n1052 = input.count();
    for (var _ in 0.._n1052) {
        _v1051.append(_m_VariableDef_read(input));
    }
    var _f1053 = _v1051;
    var _f1054 = input.flag();
    var _v1055 = Array<ast.Attribute>();
    var _n1056 = input.count();
    for (var _ in 0.._n1056) {
        _v1055.append(_a_Attribute_read(input));
    }
    var _f1057 = _v1055;
    var _f1058 = input.loc();
    return ExternDef(_f1049, _f1050, _f1053, _f1054, _f1057, _f1058);
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
    for (var _item1059 in value.traits) {
        _m_TypeName_write(out, _item1059);
    }
    out.unsigned(value.restated.count);
    for (var _item1060 in value.restated) {
        var (_t1061, _t1062) = _item1060;
        out.unsigned(_t1061);
        _m_Bound_write(out, _t1062);
    }
    out.unsigned(value.methods.count);
    for (var _item1063 in value.methods) {
        _m_FunctionDef_write(out, _item1063);
    }
    out.unsigned(value.attributes.count);
    for (var _item1064 in value.attributes) {
        _a_Attribute_write(out, _item1064);
    }
    out.loc(value.loc);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_m_ExtensionDef_read(input: RecordIn): ExtensionDef {
    var _f1065 = _m_TypeName_read(input);
    var _o1066 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1066 = Optional<String>.Value(input.text());
    }
    var _f1067 = _o1066;
    var _v1068 = Array<TypeName>();
    var _n1069 = input.count();
    for (var _ in 0.._n1069) {
        _v1068.append(_m_TypeName_read(input));
    }
    var _f1070 = _v1068;
    var _v1071 = Array<(ulong, Bound)>();
    var _n1072 = input.count();
    for (var _ in 0.._n1072) {
        var _t1073 = input.unsigned();
        var _t1074 = _m_Bound_read(input);
        _v1071.append((_t1073, _t1074));
    }
    var _f1075 = _v1071;
    var _v1076 = Array<FunctionDef>();
    var _n1077 = input.count();
    for (var _ in 0.._n1077) {
        _v1076.append(_m_FunctionDef_read(input));
    }
    var _f1078 = _v1076;
    var _v1079 = Array<ast.Attribute>();
    var _n1080 = input.count();
    for (var _ in 0.._n1080) {
        _v1079.append(_a_Attribute_read(input));
    }
    var _f1081 = _v1079;
    var _f1082 = input.loc();
    var _f1083 = input.flag();
    var _f1084 = input.flag();
    return ExtensionDef(_f1065, _f1067, _f1070, _f1075, _f1078, _f1081, _f1082, _f1083, _f1084);
}

_m_TraitDef_write(out: RecordOut, value: TraitDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1085 in value.generic_params) {
        _m_GenericParam_write(out, _item1085);
    }
    out.unsigned(value.methods.count);
    for (var _item1086 in value.methods) {
        _m_FunctionDef_write(out, _item1086);
    }
    out.unsigned(value.attributes.count);
    for (var _item1087 in value.attributes) {
        _a_Attribute_write(out, _item1087);
    }
    out.loc(value.loc);
}

_m_TraitDef_read(input: RecordIn): TraitDef {
    var _f1088 = input.text();
    var _v1089 = Array<GenericParam>();
    var _n1090 = input.count();
    for (var _ in 0.._n1090) {
        _v1089.append(_m_GenericParam_read(input));
    }
    var _f1091 = _v1089;
    var _v1092 = Array<FunctionDef>();
    var _n1093 = input.count();
    for (var _ in 0.._n1093) {
        _v1092.append(_m_FunctionDef_read(input));
    }
    var _f1094 = _v1092;
    var _v1095 = Array<ast.Attribute>();
    var _n1096 = input.count();
    for (var _ in 0.._n1096) {
        _v1095.append(_a_Attribute_read(input));
    }
    var _f1097 = _v1095;
    var _f1098 = input.loc();
    return TraitDef(_f1088, _f1091, _f1094, _f1097, _f1098);
}

_m_StructDef_write(out: RecordOut, value: StructDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.generic_params.count);
    for (var _item1099 in value.generic_params) {
        _m_GenericParam_write(out, _item1099);
    }
    out.unsigned(value.field_members.count);
    for (var _item1100 in value.field_members) {
        _m_VariableDef_write(out, _item1100);
    }
    out.unsigned(value.method_members.count);
    for (var _item1101 in value.method_members) {
        _m_FunctionDef_write(out, _item1101);
    }
    out.unsigned(value.generic_methods.count);
    for (var _item1102 in value.generic_methods) {
        _m_FunctionDef_write(out, _item1102);
    }
    out.unsigned(value.constructors.count);
    for (var _item1103 in value.constructors) {
        _m_FunctionDef_write(out, _item1103);
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    out.unsigned(value.traits.count);
    for (var _item1104 in value.traits) {
        _m_TypeName_write(out, _item1104);
    }
    out.unsigned(value.attributes.count);
    for (var _item1105 in value.attributes) {
        _a_Attribute_write(out, _item1105);
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item1106 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item1106);
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
    var _f1107 = input.text();
    var _f1108 = _m_TypeName_read(input);
    var _v1109 = Array<GenericParam>();
    var _n1110 = input.count();
    for (var _ in 0.._n1110) {
        _v1109.append(_m_GenericParam_read(input));
    }
    var _f1111 = _v1109;
    var _v1112 = Array<VariableDef>();
    var _n1113 = input.count();
    for (var _ in 0.._n1113) {
        _v1112.append(_m_VariableDef_read(input));
    }
    var _f1114 = _v1112;
    var _v1115 = Array<FunctionDef>();
    var _n1116 = input.count();
    for (var _ in 0.._n1116) {
        _v1115.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1117 = _v1115;
    var _v1118 = Array<FunctionDef>();
    var _n1119 = input.count();
    for (var _ in 0.._n1119) {
        _v1118.append(_m_FunctionDef_read(input));
    }
    var _f1120 = _v1118;
    var _v1121 = Array<FunctionDef>();
    var _n1122 = input.count();
    for (var _ in 0.._n1122) {
        _v1121.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1123 = _v1121;
    var _f1124 = _m_FunctionDef_read_with(input, lazy);
    var _f1125 = _m_FunctionDef_read_with(input, lazy);
    var _f1126 = _m_FunctionDef_read_with(input, lazy);
    var _v1127 = Array<TypeName>();
    var _n1128 = input.count();
    for (var _ in 0.._n1128) {
        _v1127.append(_m_TypeName_read(input));
    }
    var _f1129 = _v1127;
    var _v1130 = Array<ast.Attribute>();
    var _n1131 = input.count();
    for (var _ in 0.._n1131) {
        _v1130.append(_a_Attribute_read(input));
    }
    var _f1132 = _v1130;
    var _f1133 = input.loc();
    var _o1134 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v1135 = Array<EnumCaseDef>();
        var _n1136 = input.count();
        for (var _ in 0.._n1136) {
            _v1135.append(_m_EnumCaseDef_read(input));
        }
        _o1134 = Optional<Array<EnumCaseDef>>.Value(_v1135);
    }
    var _f1137 = _o1134;
    return StructDef(
        _f1107, _f1108, _f1111, _f1114, _f1117, _f1120, _f1123, _f1124, _f1125, _f1126, _f1129, _f1132, _f1133, _f1137
    );
}

_m_EnumCaseDef_write(out: RecordOut, value: EnumCaseDef) {
    out.text(value.name);
    out.signed(value.value as long);
    out.unsigned(value.payload.count);
    for (var _item1138 in value.payload) {
        var (_t1139, _t1140) = _item1138;
        out.text(_t1139);
        out.loc(_t1140);
    }
    out.unsigned(value.attributes.count);
    for (var _item1141 in value.attributes) {
        _a_Attribute_write(out, _item1141);
    }
    out.loc(value.loc);
}

_m_EnumCaseDef_read(input: RecordIn): EnumCaseDef {
    var _f1142 = input.text();
    var _f1143 = input.signed();
    var _v1144 = Array<(String, Loc)>();
    var _n1145 = input.count();
    for (var _ in 0.._n1145) {
        var _t1146 = input.text();
        var _t1147 = input.loc();
        _v1144.append((_t1146, _t1147));
    }
    var _f1148 = _v1144;
    var _v1149 = Array<ast.Attribute>();
    var _n1150 = input.count();
    for (var _ in 0.._n1150) {
        _v1149.append(_a_Attribute_read(input));
    }
    var _f1151 = _v1149;
    var _f1152 = input.loc();
    return EnumCaseDef(_f1142, _f1143, _f1148, _f1151, _f1152);
}

_m_ExtensionScopes_write(out: RecordOut, value: ExtensionScopes) {
    var _keys1154 = Array<(u8[], u8[], uint)>();
    for (var _key1153 in value.prelude) {
        var _scratch1155 = out.scratch();
        _scratch1155.unsigned(_key1153 as ulong);
        var _vscratch1157 = out.scratch();
        _keys1154.append((_scratch1155.finish(), _vscratch1157.finish(), _key1153));
    }
    _keys1154.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys1154.count);
    for (var (_bytes1156, _, _key1153) in _keys1154) {
        out.unsigned(_key1153 as ulong);
    }
    out.unsigned(value.visible.count);
    for (var _item1158 in value.visible) {
        var _keys1160 = Array<(u8[], u8[], uint)>();
        for (var _key1159 in _item1158) {
            var _scratch1161 = out.scratch();
            _scratch1161.unsigned(_key1159 as ulong);
            var _vscratch1163 = out.scratch();
            _keys1160.append((_scratch1161.finish(), _vscratch1163.finish(), _key1159));
        }
        _keys1160.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1160.count);
        for (var (_bytes1162, _, _key1159) in _keys1160) {
            out.unsigned(_key1159 as ulong);
        }
    }
    out.unsigned(value.module.count);
    for (var _item1164 in value.module) {
        if (_item1164.is_value()) {
            out.unsigned(1);
            out.unsigned(_item1164.value() as ulong);
        } else {
            out.unsigned(0);
        }
    }
}

_m_ExtensionScopes_read(input: RecordIn): ExtensionScopes {
    var _v1165 = HashSet<uint>();
    var _n1166 = input.count();
    for (var _ in 0.._n1166) {
        _v1165.insert(input.unsigned() as uint);
    }
    var _f1167 = _v1165;
    var _v1168 = Array<HashSet<uint>>();
    var _n1169 = input.count();
    for (var _ in 0.._n1169) {
        var _v1170 = HashSet<uint>();
        var _n1171 = input.count();
        for (var _ in 0.._n1171) {
            _v1170.insert(input.unsigned() as uint);
        }
        _v1168.append(_v1170);
    }
    var _f1172 = _v1168;
    var _v1173 = Array<Optional<uint>>();
    var _n1174 = input.count();
    for (var _ in 0.._n1174) {
        var _o1175 = Optional<uint>.Empty;
        if (input.unsigned() == 1) {
            _o1175 = Optional<uint>.Value(input.unsigned() as uint);
        }
        _v1173.append(_o1175);
    }
    var _f1176 = _v1173;
    return ExtensionScopes(_f1167, _f1172, _f1176);
}

_m_Conversion_write(out: RecordOut, value: Conversion) {
    out.loc(value.at);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.constructor);
}

_m_Conversion_read(input: RecordIn): Conversion {
    var _f1177 = input.loc();
    var _f1178 = _m_TypeName_read(input);
    var _f1179 = _m_TypeName_read(input);
    var _f1180 = input.loc();
    return Conversion(_f1177, _f1178, _f1179, _f1180);
}

_m_TraitType_write(out: RecordOut, value: TraitType) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.methods.count);
    for (var _item1181 in value.methods) {
        _m_FunctionDef_write(out, _item1181);
    }
}

_m_TraitType_read(input: RecordIn): TraitType {
    var _f1182 = _m_TypeName_read(input);
    var _v1183 = Array<FunctionDef>();
    var _n1184 = input.count();
    for (var _ in 0.._n1184) {
        _v1183.append(_m_FunctionDef_read(input));
    }
    var _f1185 = _v1183;
    return TraitType(_f1182, _f1185);
}

_m_UseContext_write(out: RecordOut, value: UseContext) {
    out.unsigned(value.scope.count);
    for (var _item1186 in value.scope) {
        _m_GenericParam_write(out, _item1186);
    }
    if (value.extension.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.extension.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.conditions.count);
    for (var _item1187 in value.conditions) {
        _a_Attribute_write(out, _item1187);
    }
}

_m_UseContext_read(input: RecordIn): UseContext {
    var _v1188 = Array<GenericParam>();
    var _n1189 = input.count();
    for (var _ in 0.._n1189) {
        _v1188.append(_m_GenericParam_read(input));
    }
    var _f1190 = _v1188;
    var _o1191 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1191 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1192 = _o1191;
    var _v1193 = Array<ast.Attribute>();
    var _n1194 = input.count();
    for (var _ in 0.._n1194) {
        _v1193.append(_a_Attribute_read(input));
    }
    var _f1195 = _v1193;
    return UseContext(_f1190, _f1192, _f1195);
}

_m_TypeUse_write(out: RecordOut, value: TypeUse) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1196 in value.args) {
        out.loc(_item1196);
    }
    out.unsigned(value.context);
}

_m_TypeUse_read(input: RecordIn): TypeUse {
    var _f1197 = _m_TypeName_read(input);
    var _v1198 = Array<Loc>();
    var _n1199 = input.count();
    for (var _ in 0.._n1199) {
        _v1198.append(input.loc());
    }
    var _f1200 = _v1198;
    var _f1201 = input.unsigned();
    return TypeUse(_f1197, _f1200, _f1201);
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
    var _f1202 = input.text();
    var _f1203 = input.text();
    var _f1204 = input.flag();
    var _f1205 = input.loc();
    var _f1206 = _m_AccessorKind_read(input);
    var _o1207 = Optional<AccessorKind>.Empty;
    if (input.unsigned() == 1) {
        _o1207 = Optional<AccessorKind>.Value(_m_AccessorKind_read(input));
    }
    var _f1208 = _o1207;
    var _f1209 = input.loc();
    var _o1210 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1210 = Optional<String>.Value(input.text());
    }
    var _f1211 = _o1210;
    var _f1212 = input.flag();
    return PropertyDef(_f1202, _f1203, _f1204, _f1205, _f1206, _f1208, _f1209, _f1211, _f1212);
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
    var _f1213 = input.text();
    var _f1214 = input.text();
    var _f1215 = input.text();
    var _f1216 = input.unsigned();
    var _f1217 = _m_TypeName_read(input);
    var _f1218 = _m_TypeName_read(input);
    var _f1219 = input.loc();
    return Withheld(_f1213, _f1214, _f1215, _f1216, _f1217, _f1218, _f1219);
}

_m_EnumDef_write(out: RecordOut, value: EnumDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.representation);
    out.unsigned(value.cases.count);
    for (var _item1220 in value.cases) {
        _m_EnumCaseDef_write(out, _item1220);
    }
    out.unsigned(value.attributes.count);
    for (var _item1221 in value.attributes) {
        _a_Attribute_write(out, _item1221);
    }
    out.loc(value.loc);
}

_m_EnumDef_read(input: RecordIn): EnumDef {
    var _f1222 = input.text();
    var _f1223 = _m_TypeName_read(input);
    var _v1224 = Array<EnumCaseDef>();
    var _n1225 = input.count();
    for (var _ in 0.._n1225) {
        _v1224.append(_m_EnumCaseDef_read(input));
    }
    var _f1226 = _v1224;
    var _v1227 = Array<ast.Attribute>();
    var _n1228 = input.count();
    for (var _ in 0.._n1228) {
        _v1227.append(_a_Attribute_read(input));
    }
    var _f1229 = _v1227;
    var _f1230 = input.loc();
    return EnumDef(_f1222, _f1223, _f1226, _f1229, _f1230);
}

_m_ModuleStaticBlock_write(out: RecordOut, value: ModuleStaticBlock) {
    _m_StaticBlock_write(out, value.block);
    out.unsigned(value.constants.count);
    for (var _item1231 in value.constants) {
        var (_t1232, _t1233) = _item1231;
        out.text(_t1232);
        out.loc(_t1233);
    }
}

_m_ModuleStaticBlock_read(input: RecordIn): ModuleStaticBlock {
    var _f1234 = _m_StaticBlock_read(input);
    var _v1235 = Array<(String, Loc)>();
    var _n1236 = input.count();
    for (var _ in 0.._n1236) {
        var _t1237 = input.text();
        var _t1238 = input.loc();
        _v1235.append((_t1237, _t1238));
    }
    var _f1239 = _v1235;
    return ModuleStaticBlock(_f1234, _f1239);
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
        for (var _item1240 in value.symbols.value()) {
            _a_ImportedSymbol_write(out, _item1240);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.reexport);
    out.unsigned(value.attributes.count);
    for (var _item1241 in value.attributes) {
        _a_Attribute_write(out, _item1241);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Import_read(input: RecordIn): ast.Import {
    var _f1242 = input.text();
    var _s1243 = input.unsigned();
    var _f1244 = ast.Span(_s1243, input.unsigned());
    var _o1245 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1245 = Optional<String>.Value(input.text());
    }
    var _f1246 = _o1245;
    var _f1247 = input.flag();
    var _o1248 = Optional<Array<ast.ImportedSymbol>>.Empty;
    if (input.unsigned() == 1) {
        var _v1249 = Array<ast.ImportedSymbol>();
        var _n1250 = input.count();
        for (var _ in 0.._n1250) {
            _v1249.append(_a_ImportedSymbol_read(input));
        }
        _o1248 = Optional<Array<ast.ImportedSymbol>>.Value(_v1249);
    }
    var _f1251 = _o1248;
    var _f1252 = input.flag();
    var _v1253 = Array<ast.Attribute>();
    var _n1254 = input.count();
    for (var _ in 0.._n1254) {
        _v1253.append(_a_Attribute_read(input));
    }
    var _f1255 = _v1253;
    var _s1256 = input.unsigned();
    var _f1257 = ast.Span(_s1256, input.unsigned());
    var value = ast.Import();
    value.name = _f1242;
    value.name_span = _f1244;
    value.alias = _f1246;
    value.is_local = _f1247;
    value.symbols = _f1251;
    value.reexport = _f1252;
    value.attributes = _f1255;
    value.span = _f1257;
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
    var _f1258 = input.text();
    var _s1259 = input.unsigned();
    var _f1260 = ast.Span(_s1259, input.unsigned());
    var _o1261 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1261 = Optional<String>.Value(input.text());
    }
    var _f1262 = _o1261;
    var _s1263 = input.unsigned();
    var _f1264 = ast.Span(_s1263, input.unsigned());
    var value = ast.ImportedSymbol();
    value.name = _f1258;
    value.name_span = _f1260;
    value.alias = _f1262;
    value.span = _f1264;
    return value;
}

_m_Module_write_delta(out: RecordOut, value: Module, base: DeltaBase) {
    ulong _mark = out.values.count;
    var _hs1492 = Array<String>();
    for (var _item1487 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1487);
        _hs1492.append(base.hash_of(scratch));
    }
    var _seq1493 = base.sequence("imports");
    ulong _bj1494 = 0;
    var _news1495 = Array<ulong>();
    for (var _i1496 in 0.._hs1492.count) {
        if (_bj1494 < _seq1493.count and _hs1492[_i1496] == _seq1493[_bj1494]) {
            _bj1494 += 1;
        } else {
            _news1495.append(_i1496);
        }
    }
    if (_bj1494 == _seq1493.count) {
        out.unsigned(2);
        out.unsigned(_news1495.count);
        for (var _i1496 in _news1495) {
            out.unsigned(_i1496);
            _a_Import_write(out, value.imports[_i1496]);
            {
                var _own1497 = RecordOut();
                _own1497.blank_bodies = true;
                _own1497.blank_locs = true;
                _own1497.pending_as_bytes = true;
                _a_Import_write(_own1497, value.imports[_i1496]);
                base.own("imports", interface_text(_own1497));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1496 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1496]);
            {
                var _own1498 = RecordOut();
                _own1498.blank_bodies = true;
                _own1498.blank_locs = true;
                _own1498.pending_as_bytes = true;
                _a_Import_write(_own1498, value.imports[_i1496]);
                base.own("imports", interface_text(_own1498));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1508 = base.ref_structs;
    ulong _bj1509 = 0;
    var _news1511 = Array<ulong>();
    var _patches1512 = Array<(ulong, ulong)>();
    for (var _i1513 in 0..value.structs.count) {
        if (_bj1509 < _seq1508.count
            and value.structs[_i1513] === _seq1508[_bj1509]
            and !value.extended_checked.contains(value.structs[_i1513].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1513]);
                base.verify_same("s", _bj1509, scratch, value.structs[_i1513].name);
            }
            _bj1509 += 1;
        } else if (_bj1509 < _seq1508.count
            and !(value.structs[_i1513] === _seq1508[_bj1509])
            and _same_m_StructDef(value.structs[_i1513], _seq1508[_bj1509], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1513]);
                base.verify_same("s", _bj1509, scratch, value.structs[_i1513].name);
            }
            _bj1509 += 1;
        } else if (_bj1509 < _seq1508.count and value.structs[_i1513].name == _seq1508[_bj1509].name) {
            _patches1512.append((_i1513, _bj1509));
            _bj1509 += 1;
        } else {
            _news1511.append(_i1513);
        }
    }
    if (_bj1509 == _seq1508.count) {
        out.unsigned(2);
        out.unsigned(_patches1512.count);
        for (var (_i1513, _b) in _patches1512) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1513].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1513], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1514 = RecordOut();
                _own1514.blank_bodies = true;
                _own1514.blank_locs = true;
                _own1514.pending_as_bytes = true;
                var _s1515 = value.structs[_i1513];
                var _methods1516 = _s1515.method_members;
                _s1515.method_members = Array<FunctionDef>();
                var _fields1517 = _s1515.field_members;
                var split__fields1517 = splits_fields(_s1515);
                if (split__fields1517) {
                    _s1515.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1514, _s1515);
                _s1515.method_members = _methods1516;
                _s1515.field_members = _fields1517;
                base.own_named("structs", _s1515.name, interface_text(_own1514));
                for (var _m1518 in _methods1516) {
                    var _own1519 = RecordOut();
                    _own1519.blank_bodies = true;
                    _own1519.blank_locs = true;
                    _own1519.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1519, _m1518);
                    base.own_method("structs", _s1515.name, _m1518.name, interface_text(_own1519));
                }
                if (_s1515.is_value()) {
                    for (var _m1518 in _s1515.constructors) {
                        var _own1519 = RecordOut();
                        _own1519.blank_locs = true;
                        _own1519.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1519, _m1518);
                        base.own_method("structs", _s1515.name, "__ctor", interface_text(_own1519));
                    }
                }
                if (split__fields1517) {
                    var _order1521 = StringBuilder();
                    for (var _f1520 in _fields1517) {
                        var _own1522 = RecordOut();
                        _own1522.blank_locs = true;
                        _m_VariableDef_write(_own1522, _f1520);
                        base.own_method("structs", _s1515.name, "." + _f1520.name, interface_text(_own1522));
                        _order1521.append(_f1520.name);
                        _order1521.append(",");
                    }
                    base.own_method("structs", _s1515.name, ".#order", _order1521.to_string());
                }
            }
        }
        out.unsigned(_news1511.count);
        for (var _i1513 in _news1511) {
            ulong _before = out.values.count;
            out.unsigned(_i1513);
            _m_StructDef_write(out, value.structs[_i1513]);
            base.count("s new", out.values.count - _before);
            {
                var _own1523 = RecordOut();
                _own1523.blank_bodies = true;
                _own1523.blank_locs = true;
                _own1523.pending_as_bytes = true;
                var _s1524 = value.structs[_i1513];
                var _methods1525 = _s1524.method_members;
                _s1524.method_members = Array<FunctionDef>();
                var _fields1526 = _s1524.field_members;
                var split__fields1526 = splits_fields(_s1524);
                if (split__fields1526) {
                    _s1524.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1523, _s1524);
                _s1524.method_members = _methods1525;
                _s1524.field_members = _fields1526;
                base.own_named("structs", _s1524.name, interface_text(_own1523));
                for (var _m1527 in _methods1525) {
                    var _own1528 = RecordOut();
                    _own1528.blank_bodies = true;
                    _own1528.blank_locs = true;
                    _own1528.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1528, _m1527);
                    base.own_method("structs", _s1524.name, _m1527.name, interface_text(_own1528));
                }
                if (_s1524.is_value()) {
                    for (var _m1527 in _s1524.constructors) {
                        var _own1528 = RecordOut();
                        _own1528.blank_locs = true;
                        _own1528.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1528, _m1527);
                        base.own_method("structs", _s1524.name, "__ctor", interface_text(_own1528));
                    }
                }
                if (split__fields1526) {
                    var _order1530 = StringBuilder();
                    for (var _f1529 in _fields1526) {
                        var _own1531 = RecordOut();
                        _own1531.blank_locs = true;
                        _m_VariableDef_write(_own1531, _f1529);
                        base.own_method("structs", _s1524.name, "." + _f1529.name, interface_text(_own1531));
                        _order1530.append(_f1529.name);
                        _order1530.append(",");
                    }
                    base.own_method("structs", _s1524.name, ".#order", _order1530.to_string());
                }
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1507 = HashSet<long>();
        var _slots1510 = HashMap<String, long>();
        for (var _i1513 in 0.._seq1508.count) {
            if (!_slots1510.contains(_seq1508[_i1513].name)) {
                _slots1510[_seq1508[_i1513].name] = _i1513 as long;
            }
        }
        out.unsigned(value.structs.count);
        for (var _i1513 in 0..value.structs.count) {
            var _item1506 = value.structs[_i1513];
            var _slot = _slots1510.try_get(_item1506.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq1508[named as ulong] === _item1506
                and !value.extended_checked.contains(_item1506.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1507.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1507.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1506, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1506);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1507.count);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1545 = Array<String>();
    for (var _item1540 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1540);
        _hs1545.append(base.hash_of(scratch));
    }
    var _seq1546 = base.sequence("traits");
    ulong _bj1547 = 0;
    var _news1548 = Array<ulong>();
    for (var _i1549 in 0.._hs1545.count) {
        if (_bj1547 < _seq1546.count and _hs1545[_i1549] == _seq1546[_bj1547]) {
            _bj1547 += 1;
        } else {
            _news1548.append(_i1549);
        }
    }
    if (_bj1547 == _seq1546.count) {
        out.unsigned(2);
        out.unsigned(_news1548.count);
        for (var _i1549 in _news1548) {
            out.unsigned(_i1549);
            _m_TraitDef_write(out, value.traits[_i1549]);
            {
                var _own1550 = RecordOut();
                _own1550.blank_bodies = false;
                _own1550.blank_locs = true;
                _own1550.pending_as_bytes = true;
                _m_TraitDef_write(_own1550, value.traits[_i1549]);
                base.own("traits", interface_text(_own1550));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1549 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1549]);
            {
                var _own1551 = RecordOut();
                _own1551.blank_bodies = false;
                _own1551.blank_locs = true;
                _own1551.pending_as_bytes = true;
                _m_TraitDef_write(_own1551, value.traits[_i1549]);
                base.own("traits", interface_text(_own1551));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1564 = Array<String>();
    for (var _item1559 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1559);
        _hs1564.append(base.hash_of(scratch));
    }
    var _seq1565 = base.sequence("extensions");
    ulong _bj1566 = 0;
    var _news1567 = Array<ulong>();
    for (var _i1568 in 0.._hs1564.count) {
        if (_bj1566 < _seq1565.count and _hs1564[_i1568] == _seq1565[_bj1566]) {
            _bj1566 += 1;
        } else {
            _news1567.append(_i1568);
        }
    }
    if (_bj1566 == _seq1565.count) {
        out.unsigned(2);
        out.unsigned(_news1567.count);
        for (var _i1568 in _news1567) {
            out.unsigned(_i1568);
            _m_ExtensionDef_write(out, value.extensions[_i1568]);
            {
                var _own1569 = RecordOut();
                _own1569.blank_bodies = true;
                _own1569.blank_locs = true;
                _own1569.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1569, value.extensions[_i1568]);
                base.own("extensions", interface_text(_own1569));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1568 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1568]);
            {
                var _own1570 = RecordOut();
                _own1570.blank_bodies = true;
                _own1570.blank_locs = true;
                _own1570.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1570, value.extensions[_i1568]);
                base.own("extensions", interface_text(_own1570));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1583 = base.ref_functions;
    ulong _bj1584 = 0;
    var _news1585 = Array<ulong>();
    var _changed1579 = Array<(ulong, ulong)>();
    for (var _i1586 in 0..value.functions.count) {
        if (_bj1584 < _seq1583.count and value.functions[_i1586] === _seq1583[_bj1584]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1586]);
                base.verify_same("functions", _bj1584, scratch);
            }
            _bj1584 += 1;
        } else if (_bj1584 < _seq1583.count and _same_m_FunctionDef(value.functions[_i1586], _seq1583[_bj1584], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1586]);
                base.verify_same("functions", _bj1584, scratch);
            }
            _bj1584 += 1;
        } else if (_bj1584 < _seq1583.count and value.functions[_i1586].name == _seq1583[_bj1584].name) {
            _changed1579.append((_i1586, _bj1584));
            _bj1584 += 1;
        } else {
            _news1585.append(_i1586);
        }
    }
    if (_bj1584 == _seq1583.count) {
        out.unsigned(2);
        out.unsigned(_changed1579.count);
        for (var (_i1586, _b) in _changed1579) {
            out.text(value.functions[_i1586].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1586]);
            {
                var _own1587 = RecordOut();
                _own1587.blank_bodies = true;
                _own1587.blank_locs = true;
                _own1587.pending_as_bytes = true;
                _m_FunctionDef_write(_own1587, value.functions[_i1586]);
                base.own_function("functions", value.functions[_i1586], interface_text(_own1587));
            }
        }
        base.count("functions" + " changed", _changed1579.count);
        out.unsigned(_news1585.count);
        for (var _i1586 in _news1585) {
            out.unsigned(_i1586);
            _m_FunctionDef_write(out, value.functions[_i1586]);
            {
                var _own1588 = RecordOut();
                _own1588.blank_bodies = true;
                _own1588.blank_locs = true;
                _own1588.pending_as_bytes = true;
                _m_FunctionDef_write(_own1588, value.functions[_i1586]);
                base.own_function("functions", value.functions[_i1586], interface_text(_own1588));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1586 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1586]);
            {
                var _own1589 = RecordOut();
                _own1589.blank_bodies = true;
                _own1589.blank_locs = true;
                _own1589.pending_as_bytes = true;
                _m_FunctionDef_write(_own1589, value.functions[_i1586]);
                base.own_function("functions", value.functions[_i1586], interface_text(_own1589));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1602 = Array<String>();
    for (var _item1597 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1597);
        _hs1602.append(base.hash_of(scratch));
    }
    var _seq1603 = base.sequence("externs");
    ulong _bj1604 = 0;
    var _news1605 = Array<ulong>();
    for (var _i1606 in 0.._hs1602.count) {
        if (_bj1604 < _seq1603.count and _hs1602[_i1606] == _seq1603[_bj1604]) {
            _bj1604 += 1;
        } else {
            _news1605.append(_i1606);
        }
    }
    if (_bj1604 == _seq1603.count) {
        out.unsigned(2);
        out.unsigned(_news1605.count);
        for (var _i1606 in _news1605) {
            out.unsigned(_i1606);
            _m_ExternDef_write(out, value.externs[_i1606]);
            {
                var _own1607 = RecordOut();
                _own1607.blank_bodies = true;
                _own1607.blank_locs = true;
                _own1607.pending_as_bytes = true;
                _m_ExternDef_write(_own1607, value.externs[_i1606]);
                base.own("externs", interface_text(_own1607));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1606 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1606]);
            {
                var _own1608 = RecordOut();
                _own1608.blank_bodies = true;
                _own1608.blank_locs = true;
                _own1608.pending_as_bytes = true;
                _m_ExternDef_write(_own1608, value.externs[_i1606]);
                base.own("externs", interface_text(_own1608));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1621 = Array<String>();
    for (var _item1616 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1616);
        _hs1621.append(base.hash_of(scratch));
    }
    var _seq1622 = base.sequence("globals");
    ulong _bj1623 = 0;
    var _news1624 = Array<ulong>();
    for (var _i1625 in 0.._hs1621.count) {
        if (_bj1623 < _seq1622.count and _hs1621[_i1625] == _seq1622[_bj1623]) {
            _bj1623 += 1;
        } else {
            _news1624.append(_i1625);
        }
    }
    if (_bj1623 == _seq1622.count) {
        out.unsigned(2);
        out.unsigned(_news1624.count);
        for (var _i1625 in _news1624) {
            out.unsigned(_i1625);
            _m_VariableDef_write(out, value.globals[_i1625]);
            {
                var _own1626 = RecordOut();
                _own1626.blank_bodies = true;
                _own1626.blank_locs = true;
                _own1626.pending_as_bytes = true;
                _m_VariableDef_write(_own1626, value.globals[_i1625]);
                base.own("globals", interface_text(_own1626));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1625 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1625]);
            {
                var _own1627 = RecordOut();
                _own1627.blank_bodies = true;
                _own1627.blank_locs = true;
                _own1627.pending_as_bytes = true;
                _m_VariableDef_write(_own1627, value.globals[_i1625]);
                base.own("globals", interface_text(_own1627));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1640 = Array<String>();
    for (var _item1635 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1635);
        _hs1640.append(base.hash_of(scratch));
    }
    var _seq1641 = base.sequence("static_blocks");
    ulong _bj1642 = 0;
    var _news1643 = Array<ulong>();
    for (var _i1644 in 0.._hs1640.count) {
        if (_bj1642 < _seq1641.count and _hs1640[_i1644] == _seq1641[_bj1642]) {
            _bj1642 += 1;
        } else {
            _news1643.append(_i1644);
        }
    }
    if (_bj1642 == _seq1641.count) {
        out.unsigned(2);
        out.unsigned(_news1643.count);
        for (var _i1644 in _news1643) {
            out.unsigned(_i1644);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1644]);
            {
                var _own1645 = RecordOut();
                _own1645.blank_bodies = true;
                _own1645.blank_locs = true;
                _own1645.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1645, value.static_blocks[_i1644]);
                base.own("static_blocks", interface_text(_own1645));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1644 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1644]);
            {
                var _own1646 = RecordOut();
                _own1646.blank_bodies = true;
                _own1646.blank_locs = true;
                _own1646.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1646, value.static_blocks[_i1644]);
                base.own("static_blocks", interface_text(_own1646));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1659 = Array<String>();
    for (var _item1654 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1654);
        _hs1659.append(base.hash_of(scratch));
    }
    var _seq1660 = base.sequence("enums");
    ulong _bj1661 = 0;
    var _news1662 = Array<ulong>();
    for (var _i1663 in 0.._hs1659.count) {
        if (_bj1661 < _seq1660.count and _hs1659[_i1663] == _seq1660[_bj1661]) {
            _bj1661 += 1;
        } else {
            _news1662.append(_i1663);
        }
    }
    if (_bj1661 == _seq1660.count) {
        out.unsigned(2);
        out.unsigned(_news1662.count);
        for (var _i1663 in _news1662) {
            out.unsigned(_i1663);
            _m_EnumDef_write(out, value.enums[_i1663]);
            {
                var _own1664 = RecordOut();
                _own1664.blank_bodies = true;
                _own1664.blank_locs = true;
                _own1664.pending_as_bytes = true;
                _m_EnumDef_write(_own1664, value.enums[_i1663]);
                base.own_named("enums", value.enums[_i1663].name, interface_text(_own1664));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1663 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1663]);
            {
                var _own1665 = RecordOut();
                _own1665.blank_bodies = true;
                _own1665.blank_locs = true;
                _own1665.pending_as_bytes = true;
                _m_EnumDef_write(_own1665, value.enums[_i1663]);
                base.own_named("enums", value.enums[_i1663].name, interface_text(_own1665));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1678 = Array<String>();
    for (var _item1673 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1673);
        _hs1678.append(base.hash_of(scratch));
    }
    var _seq1679 = base.sequence("struct_specs");
    ulong _bj1680 = 0;
    var _news1681 = Array<ulong>();
    for (var _i1682 in 0.._hs1678.count) {
        if (_bj1680 < _seq1679.count and _hs1678[_i1682] == _seq1679[_bj1680]) {
            _bj1680 += 1;
        } else {
            _news1681.append(_i1682);
        }
    }
    if (_bj1680 == _seq1679.count) {
        out.unsigned(2);
        out.unsigned(_news1681.count);
        for (var _i1682 in _news1681) {
            out.unsigned(_i1682);
            _m_TypeName_write(out, value.struct_specs[_i1682]);
            {
                var _own1683 = RecordOut();
                _own1683.blank_bodies = true;
                _own1683.blank_locs = true;
                _own1683.pending_as_bytes = true;
                _m_TypeName_write(_own1683, value.struct_specs[_i1682]);
                base.own("struct_specs", interface_text(_own1683));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1682 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1682]);
            {
                var _own1684 = RecordOut();
                _own1684.blank_bodies = true;
                _own1684.blank_locs = true;
                _own1684.pending_as_bytes = true;
                _m_TypeName_write(_own1684, value.struct_specs[_i1682]);
                base.own("struct_specs", interface_text(_own1684));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1697 = Array<String>();
    for (var _item1692 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1692);
        _hs1697.append(base.hash_of(scratch));
    }
    var _seq1698 = base.sequence("func_specs");
    ulong _bj1699 = 0;
    var _news1700 = Array<ulong>();
    for (var _i1701 in 0.._hs1697.count) {
        if (_bj1699 < _seq1698.count and _hs1697[_i1701] == _seq1698[_bj1699]) {
            _bj1699 += 1;
        } else {
            _news1700.append(_i1701);
        }
    }
    if (_bj1699 == _seq1698.count) {
        out.unsigned(2);
        out.unsigned(_news1700.count);
        for (var _i1701 in _news1700) {
            out.unsigned(_i1701);
            _m_TypeName_write(out, value.func_specs[_i1701]);
            {
                var _own1702 = RecordOut();
                _own1702.blank_bodies = true;
                _own1702.blank_locs = true;
                _own1702.pending_as_bytes = true;
                _m_TypeName_write(_own1702, value.func_specs[_i1701]);
                base.own("func_specs", interface_text(_own1702));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1701 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1701]);
            {
                var _own1703 = RecordOut();
                _own1703.blank_bodies = true;
                _own1703.blank_locs = true;
                _own1703.pending_as_bytes = true;
                _m_TypeName_write(_own1703, value.func_specs[_i1701]);
                base.own("func_specs", interface_text(_own1703));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1715 = HashSet<long>();
    out.unsigned(value.type_aliases.count);
    for (var _item1711 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1711);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1715.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1711);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1715.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1725 = Array<String>();
    for (var _item1720 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1720);
        _hs1725.append(base.hash_of(scratch));
    }
    var _seq1726 = base.sequence("withheld");
    ulong _bj1727 = 0;
    var _news1728 = Array<ulong>();
    for (var _i1729 in 0.._hs1725.count) {
        if (_bj1727 < _seq1726.count and _hs1725[_i1729] == _seq1726[_bj1727]) {
            _bj1727 += 1;
        } else {
            _news1728.append(_i1729);
        }
    }
    if (_bj1727 == _seq1726.count) {
        out.unsigned(2);
        out.unsigned(_news1728.count);
        for (var _i1729 in _news1728) {
            out.unsigned(_i1729);
            _m_Withheld_write(out, value.withheld[_i1729]);
            {
                var _own1730 = RecordOut();
                _own1730.blank_bodies = true;
                _own1730.blank_locs = true;
                _own1730.pending_as_bytes = true;
                _m_Withheld_write(_own1730, value.withheld[_i1729]);
                base.own("withheld", interface_text(_own1730));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1729 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1729]);
            {
                var _own1731 = RecordOut();
                _own1731.blank_bodies = true;
                _own1731.blank_locs = true;
                _own1731.pending_as_bytes = true;
                _m_Withheld_write(_own1731, value.withheld[_i1729]);
                base.own("withheld", interface_text(_own1731));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1744 = Array<String>();
    for (var _item1739 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1739);
        _hs1744.append(base.hash_of(scratch));
    }
    var _seq1745 = base.sequence("properties");
    ulong _bj1746 = 0;
    var _news1747 = Array<ulong>();
    for (var _i1748 in 0.._hs1744.count) {
        if (_bj1746 < _seq1745.count and _hs1744[_i1748] == _seq1745[_bj1746]) {
            _bj1746 += 1;
        } else {
            _news1747.append(_i1748);
        }
    }
    if (_bj1746 == _seq1745.count) {
        out.unsigned(2);
        out.unsigned(_news1747.count);
        for (var _i1748 in _news1747) {
            out.unsigned(_i1748);
            _m_PropertyDef_write(out, value.properties[_i1748]);
            {
                var _own1749 = RecordOut();
                _own1749.blank_bodies = true;
                _own1749.blank_locs = true;
                _own1749.pending_as_bytes = true;
                _m_PropertyDef_write(_own1749, value.properties[_i1748]);
                base.own("properties", interface_text(_own1749));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1748 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1748]);
            {
                var _own1750 = RecordOut();
                _own1750.blank_bodies = true;
                _own1750.blank_locs = true;
                _own1750.pending_as_bytes = true;
                _m_PropertyDef_write(_own1750, value.properties[_i1748]);
                base.own("properties", interface_text(_own1750));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1763 = Array<String>();
    for (var _item1758 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1758);
        _hs1763.append(base.hash_of(scratch));
    }
    var _seq1764 = base.sequence("type_uses");
    ulong _bj1765 = 0;
    var _news1766 = Array<ulong>();
    for (var _i1767 in 0.._hs1763.count) {
        if (_bj1765 < _seq1764.count and _hs1763[_i1767] == _seq1764[_bj1765]) {
            _bj1765 += 1;
        } else {
            _news1766.append(_i1767);
        }
    }
    if (_bj1765 == _seq1764.count) {
        out.unsigned(2);
        out.unsigned(_news1766.count);
        for (var _i1767 in _news1766) {
            out.unsigned(_i1767);
            _m_TypeUse_write(out, value.type_uses[_i1767]);
            {
                var _own1768 = RecordOut();
                _own1768.blank_bodies = true;
                _own1768.blank_locs = true;
                _own1768.pending_as_bytes = true;
                _m_TypeUse_write(_own1768, value.type_uses[_i1767]);
                base.own("type_uses", interface_text(_own1768));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1767 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1767]);
            {
                var _own1769 = RecordOut();
                _own1769.blank_bodies = true;
                _own1769.blank_locs = true;
                _own1769.pending_as_bytes = true;
                _m_TypeUse_write(_own1769, value.type_uses[_i1767]);
                base.own("type_uses", interface_text(_own1769));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1782 = Array<String>();
    for (var _item1777 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1777);
        _hs1782.append(base.hash_of(scratch));
    }
    var _seq1783 = base.sequence("use_contexts");
    ulong _bj1784 = 0;
    var _news1785 = Array<ulong>();
    for (var _i1786 in 0.._hs1782.count) {
        if (_bj1784 < _seq1783.count and _hs1782[_i1786] == _seq1783[_bj1784]) {
            _bj1784 += 1;
        } else {
            _news1785.append(_i1786);
        }
    }
    if (_bj1784 == _seq1783.count) {
        out.unsigned(2);
        out.unsigned(_news1785.count);
        for (var _i1786 in _news1785) {
            out.unsigned(_i1786);
            _m_UseContext_write(out, value.use_contexts[_i1786]);
            {
                var _own1787 = RecordOut();
                _own1787.blank_bodies = true;
                _own1787.blank_locs = true;
                _own1787.pending_as_bytes = true;
                _m_UseContext_write(_own1787, value.use_contexts[_i1786]);
                base.own("use_contexts", interface_text(_own1787));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1786 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1786]);
            {
                var _own1788 = RecordOut();
                _own1788.blank_bodies = true;
                _own1788.blank_locs = true;
                _own1788.pending_as_bytes = true;
                _m_UseContext_write(_own1788, value.use_contexts[_i1786]);
                base.own("use_contexts", interface_text(_own1788));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1798 = base.size("literal_args");
    var _scratch1797 = base.scratch();
    if (value.literal_args.count >= _n1798) {
        for (var _i1799 in 0.._n1798) {
            var (_t1800, _t1801, _t1802) = value.literal_args[_i1799];
            _scratch1797.loc(_t1800);
            _scratch1797.unsigned(_t1801);
            _scratch1797.loc(_t1802);
        }
    }
    if (value.literal_args.count >= _n1798 and base.same_list("literal_args", _scratch1797)) {
        out.unsigned(1);
        out.unsigned(_n1798);
        out.unsigned(value.literal_args.count - _n1798);
        for (var _i1799 in _n1798..value.literal_args.count) {
            var (_t1803, _t1804, _t1805) = value.literal_args[_i1799];
            out.loc(_t1803);
            out.unsigned(_t1804);
            out.loc(_t1805);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1806 in value.literal_args) {
            var (_t1807, _t1808, _t1809) = _item1806;
            out.loc(_t1807);
            out.unsigned(_t1808);
            out.loc(_t1809);
        }
        base.count("literal_args whole", 0);
    }
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1832 = Array<String>();
    for (var _item1827 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1827);
        _hs1832.append(base.hash_of(scratch));
    }
    var _seq1833 = base.sequence("constrained_aliases");
    ulong _bj1834 = 0;
    var _news1835 = Array<ulong>();
    for (var _i1836 in 0.._hs1832.count) {
        if (_bj1834 < _seq1833.count and _hs1832[_i1836] == _seq1833[_bj1834]) {
            _bj1834 += 1;
        } else {
            _news1835.append(_i1836);
        }
    }
    if (_bj1834 == _seq1833.count) {
        out.unsigned(2);
        out.unsigned(_news1835.count);
        for (var _i1836 in _news1835) {
            out.unsigned(_i1836);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1836]);
            {
                var _own1837 = RecordOut();
                _own1837.blank_bodies = true;
                _own1837.blank_locs = true;
                _own1837.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1837, value.constrained_aliases[_i1836]);
                base.own("constrained_aliases", interface_text(_own1837));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1836 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1836]);
            {
                var _own1838 = RecordOut();
                _own1838.blank_bodies = true;
                _own1838.blank_locs = true;
                _own1838.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1838, value.constrained_aliases[_i1836]);
                base.own("constrained_aliases", interface_text(_own1838));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1851 = Array<String>();
    for (var _item1846 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1846);
        _hs1851.append(base.hash_of(scratch));
    }
    var _seq1852 = base.sequence("trait_types");
    ulong _bj1853 = 0;
    var _news1854 = Array<ulong>();
    for (var _i1855 in 0.._hs1851.count) {
        if (_bj1853 < _seq1852.count and _hs1851[_i1855] == _seq1852[_bj1853]) {
            _bj1853 += 1;
        } else {
            _news1854.append(_i1855);
        }
    }
    if (_bj1853 == _seq1852.count) {
        out.unsigned(2);
        out.unsigned(_news1854.count);
        for (var _i1855 in _news1854) {
            out.unsigned(_i1855);
            _m_TraitType_write(out, value.trait_types[_i1855]);
            {
                var _own1856 = RecordOut();
                _own1856.blank_bodies = true;
                _own1856.blank_locs = true;
                _own1856.pending_as_bytes = true;
                _m_TraitType_write(_own1856, value.trait_types[_i1855]);
                base.own("trait_types", interface_text(_own1856));
            }
        }
        base.count("trait_types" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("trait_types" + " whole", 0);
        out.unsigned(value.trait_types.count);
        for (var _i1855 in 0..value.trait_types.count) {
            _m_TraitType_write(out, value.trait_types[_i1855]);
            {
                var _own1857 = RecordOut();
                _own1857.blank_bodies = true;
                _own1857.blank_locs = true;
                _own1857.pending_as_bytes = true;
                _m_TraitType_write(_own1857, value.trait_types[_i1855]);
                base.own("trait_types", interface_text(_own1857));
            }
        }
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    out.unsigned(value.conversions.count);
    for (var _item1865 in value.conversions) {
        _m_Conversion_write(out, _item1865);
    }
    for (var _conv1866 in value.conversions) {
        var _own1867 = RecordOut();
        _own1867.blank_locs = true;
        _m_Conversion_write(_own1867, _conv1866);
        var _h = interface_text(_own1867);
        if (base.find_hashed("conversions", _h) < 0) {
            base.own("conversions", _h);
        }
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1875 = 0;
    var _news1876 = Map<String, Array<String>>();
    for (var (_key1872, _) in value.overload_sets) {
        var _kscratch1873 = base.scratch();
        _kscratch1873.text(_key1872);
        var _vscratch1874 = base.scratch();
        _vscratch1874.unsigned(value.overload_sets[_key1872].count);
        for (var _item1877 in value.overload_sets[_key1872]) {
            _vscratch1874.text(_item1877);
        }
        var _had = base.entry("overload_sets", _kscratch1873, _vscratch1874);
        if (_had >= 0) {
            _kept1875 += 1;
        }
        if (_had != 1) {
            _news1876[_key1872] = value.overload_sets[_key1872];
        }
    }
    if (_kept1875 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1879 = Array<(u8[], u8[], String)>();
        for (var (_key1878, _) in _news1876) {
            var _scratch1880 = out.scratch();
            _scratch1880.text(_key1878);
            var _vscratch1882 = out.scratch();
            _vscratch1882.unsigned(_news1876[_key1878].count);
            for (var _item1883 in _news1876[_key1878]) {
                _vscratch1882.text(_item1883);
            }
            _keys1879.append((_scratch1880.finish(), _vscratch1882.finish(), _key1878));
        }
        _keys1879.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1879.count);
        for (var (_bytes1881, _, _key1878) in _keys1879) {
            out.text(_key1878);
            out.unsigned(_news1876[_key1878].count);
            for (var _item1884 in _news1876[_key1878]) {
                out.text(_item1884);
            }
        }
        for (var (_okey1885, _) in _news1876) {
            var _own1886 = RecordOut();
            _own1886.blank_bodies = true;
            _own1886.blank_locs = true;
            _own1886.pending_as_bytes = true;
            _own1886.text(_okey1885);
            _own1886.unsigned(_news1876[_okey1885].count);
            for (var _item1887 in _news1876[_okey1885]) {
                _own1886.text(_item1887);
            }
            base.own("overload_sets", interface_text(_own1886));
        }
    } else {
        out.unsigned(0);
        var _keys1889 = Array<(u8[], u8[], String)>();
        for (var (_key1888, _) in value.overload_sets) {
            var _scratch1890 = out.scratch();
            _scratch1890.text(_key1888);
            var _vscratch1892 = out.scratch();
            _vscratch1892.unsigned(value.overload_sets[_key1888].count);
            for (var _item1893 in value.overload_sets[_key1888]) {
                _vscratch1892.text(_item1893);
            }
            _keys1889.append((_scratch1890.finish(), _vscratch1892.finish(), _key1888));
        }
        _keys1889.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1889.count);
        for (var (_bytes1891, _, _key1888) in _keys1889) {
            out.text(_key1888);
            out.unsigned(value.overload_sets[_key1888].count);
            for (var _item1894 in value.overload_sets[_key1888]) {
                out.text(_item1894);
            }
        }
        for (var (_okey1895, _) in value.overload_sets) {
            var _own1896 = RecordOut();
            _own1896.blank_bodies = true;
            _own1896.blank_locs = true;
            _own1896.pending_as_bytes = true;
            _own1896.text(_okey1895);
            _own1896.unsigned(value.overload_sets[_okey1895].count);
            for (var _item1897 in value.overload_sets[_okey1895]) {
                _own1896.text(_item1897);
            }
            base.own("overload_sets", interface_text(_own1896));
        }
        base.count("overload_sets whole", 0);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1915 = 0;
    var _news1916 = Map<String, Array<Array<String>>>();
    for (var (_key1912, _) in value.overload_unions) {
        var _kscratch1913 = base.scratch();
        _kscratch1913.text(_key1912);
        var _vscratch1914 = base.scratch();
        _vscratch1914.unsigned(value.overload_unions[_key1912].count);
        for (var _item1917 in value.overload_unions[_key1912]) {
            _vscratch1914.unsigned(_item1917.count);
            for (var _item1918 in _item1917) {
                _vscratch1914.text(_item1918);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1913, _vscratch1914);
        if (_had >= 0) {
            _kept1915 += 1;
        }
        if (_had != 1) {
            _news1916[_key1912] = value.overload_unions[_key1912];
        }
    }
    if (_kept1915 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1920 = Array<(u8[], u8[], String)>();
        for (var (_key1919, _) in _news1916) {
            var _scratch1921 = out.scratch();
            _scratch1921.text(_key1919);
            var _vscratch1923 = out.scratch();
            _vscratch1923.unsigned(_news1916[_key1919].count);
            for (var _item1924 in _news1916[_key1919]) {
                _vscratch1923.unsigned(_item1924.count);
                for (var _item1925 in _item1924) {
                    _vscratch1923.text(_item1925);
                }
            }
            _keys1920.append((_scratch1921.finish(), _vscratch1923.finish(), _key1919));
        }
        _keys1920.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1920.count);
        for (var (_bytes1922, _, _key1919) in _keys1920) {
            out.text(_key1919);
            out.unsigned(_news1916[_key1919].count);
            for (var _item1926 in _news1916[_key1919]) {
                out.unsigned(_item1926.count);
                for (var _item1927 in _item1926) {
                    out.text(_item1927);
                }
            }
        }
        for (var (_okey1928, _) in _news1916) {
            var _own1929 = RecordOut();
            _own1929.blank_bodies = true;
            _own1929.blank_locs = true;
            _own1929.pending_as_bytes = true;
            _own1929.text(_okey1928);
            _own1929.unsigned(_news1916[_okey1928].count);
            for (var _item1930 in _news1916[_okey1928]) {
                _own1929.unsigned(_item1930.count);
                for (var _item1931 in _item1930) {
                    _own1929.text(_item1931);
                }
            }
            base.own("overload_unions", interface_text(_own1929));
        }
    } else {
        out.unsigned(0);
        var _keys1933 = Array<(u8[], u8[], String)>();
        for (var (_key1932, _) in value.overload_unions) {
            var _scratch1934 = out.scratch();
            _scratch1934.text(_key1932);
            var _vscratch1936 = out.scratch();
            _vscratch1936.unsigned(value.overload_unions[_key1932].count);
            for (var _item1937 in value.overload_unions[_key1932]) {
                _vscratch1936.unsigned(_item1937.count);
                for (var _item1938 in _item1937) {
                    _vscratch1936.text(_item1938);
                }
            }
            _keys1933.append((_scratch1934.finish(), _vscratch1936.finish(), _key1932));
        }
        _keys1933.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1933.count);
        for (var (_bytes1935, _, _key1932) in _keys1933) {
            out.text(_key1932);
            out.unsigned(value.overload_unions[_key1932].count);
            for (var _item1939 in value.overload_unions[_key1932]) {
                out.unsigned(_item1939.count);
                for (var _item1940 in _item1939) {
                    out.text(_item1940);
                }
            }
        }
        for (var (_okey1941, _) in value.overload_unions) {
            var _own1942 = RecordOut();
            _own1942.blank_bodies = true;
            _own1942.blank_locs = true;
            _own1942.pending_as_bytes = true;
            _own1942.text(_okey1941);
            _own1942.unsigned(value.overload_unions[_okey1941].count);
            for (var _item1943 in value.overload_unions[_okey1941]) {
                _own1942.unsigned(_item1943.count);
                for (var _item1944 in _item1943) {
                    _own1942.text(_item1944);
                }
            }
            base.own("overload_unions", interface_text(_own1942));
        }
        base.count("overload_unions whole", 0);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1967 = 0;
    var _news1968 = Map<String, Map<String, Array<String>>>();
    for (var (_key1964, _) in value.method_overload_sets) {
        var _kscratch1965 = base.scratch();
        _kscratch1965.text(_key1964);
        var _vscratch1966 = base.scratch();
        var _keys1970 = Array<(u8[], u8[], String)>();
        for (var (_key1969, _) in value.method_overload_sets[_key1964]) {
            var _scratch1971 = _vscratch1966.scratch();
            _scratch1971.text(_key1969);
            var _vscratch1973 = _vscratch1966.scratch();
            _vscratch1973.unsigned(value.method_overload_sets[_key1964][_key1969].count);
            for (var _item1974 in value.method_overload_sets[_key1964][_key1969]) {
                _vscratch1973.text(_item1974);
            }
            _keys1970.append((_scratch1971.finish(), _vscratch1973.finish(), _key1969));
        }
        _keys1970.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1966.unsigned(_keys1970.count);
        for (var (_bytes1972, _, _key1969) in _keys1970) {
            _vscratch1966.text(_key1969);
            _vscratch1966.unsigned(value.method_overload_sets[_key1964][_key1969].count);
            for (var _item1975 in value.method_overload_sets[_key1964][_key1969]) {
                _vscratch1966.text(_item1975);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1965, _vscratch1966);
        if (_had >= 0) {
            _kept1967 += 1;
        }
        if (_had != 1) {
            _news1968[_key1964] = value.method_overload_sets[_key1964];
        }
    }
    if (_kept1967 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1977 = Array<(u8[], u8[], String)>();
        for (var (_key1976, _) in _news1968) {
            var _scratch1978 = out.scratch();
            _scratch1978.text(_key1976);
            var _vscratch1980 = out.scratch();
            var _keys1982 = Array<(u8[], u8[], String)>();
            for (var (_key1981, _) in _news1968[_key1976]) {
                var _scratch1983 = _vscratch1980.scratch();
                _scratch1983.text(_key1981);
                var _vscratch1985 = _vscratch1980.scratch();
                _vscratch1985.unsigned(_news1968[_key1976][_key1981].count);
                for (var _item1986 in _news1968[_key1976][_key1981]) {
                    _vscratch1985.text(_item1986);
                }
                _keys1982.append((_scratch1983.finish(), _vscratch1985.finish(), _key1981));
            }
            _keys1982.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1980.unsigned(_keys1982.count);
            for (var (_bytes1984, _, _key1981) in _keys1982) {
                _vscratch1980.text(_key1981);
                _vscratch1980.unsigned(_news1968[_key1976][_key1981].count);
                for (var _item1987 in _news1968[_key1976][_key1981]) {
                    _vscratch1980.text(_item1987);
                }
            }
            _keys1977.append((_scratch1978.finish(), _vscratch1980.finish(), _key1976));
        }
        _keys1977.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1977.count);
        for (var (_bytes1979, _, _key1976) in _keys1977) {
            out.text(_key1976);
            var _keys1989 = Array<(u8[], u8[], String)>();
            for (var (_key1988, _) in _news1968[_key1976]) {
                var _scratch1990 = out.scratch();
                _scratch1990.text(_key1988);
                var _vscratch1992 = out.scratch();
                _vscratch1992.unsigned(_news1968[_key1976][_key1988].count);
                for (var _item1993 in _news1968[_key1976][_key1988]) {
                    _vscratch1992.text(_item1993);
                }
                _keys1989.append((_scratch1990.finish(), _vscratch1992.finish(), _key1988));
            }
            _keys1989.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1989.count);
            for (var (_bytes1991, _, _key1988) in _keys1989) {
                out.text(_key1988);
                out.unsigned(_news1968[_key1976][_key1988].count);
                for (var _item1994 in _news1968[_key1976][_key1988]) {
                    out.text(_item1994);
                }
            }
        }
        for (var (_okey1995, _) in _news1968) {
            var _own1996 = RecordOut();
            _own1996.blank_bodies = true;
            _own1996.blank_locs = true;
            _own1996.pending_as_bytes = true;
            _own1996.text(_okey1995);
            var _keys1998 = Array<(u8[], u8[], String)>();
            for (var (_key1997, _) in _news1968[_okey1995]) {
                var _scratch1999 = _own1996.scratch();
                _scratch1999.text(_key1997);
                var _vscratch2001 = _own1996.scratch();
                _vscratch2001.unsigned(_news1968[_okey1995][_key1997].count);
                for (var _item2002 in _news1968[_okey1995][_key1997]) {
                    _vscratch2001.text(_item2002);
                }
                _keys1998.append((_scratch1999.finish(), _vscratch2001.finish(), _key1997));
            }
            _keys1998.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own1996.unsigned(_keys1998.count);
            for (var (_bytes2000, _, _key1997) in _keys1998) {
                _own1996.text(_key1997);
                _own1996.unsigned(_news1968[_okey1995][_key1997].count);
                for (var _item2003 in _news1968[_okey1995][_key1997]) {
                    _own1996.text(_item2003);
                }
            }
            base.own("method_overload_sets", interface_text(_own1996));
        }
    } else {
        out.unsigned(0);
        var _keys2005 = Array<(u8[], u8[], String)>();
        for (var (_key2004, _) in value.method_overload_sets) {
            var _scratch2006 = out.scratch();
            _scratch2006.text(_key2004);
            var _vscratch2008 = out.scratch();
            var _keys2010 = Array<(u8[], u8[], String)>();
            for (var (_key2009, _) in value.method_overload_sets[_key2004]) {
                var _scratch2011 = _vscratch2008.scratch();
                _scratch2011.text(_key2009);
                var _vscratch2013 = _vscratch2008.scratch();
                _vscratch2013.unsigned(value.method_overload_sets[_key2004][_key2009].count);
                for (var _item2014 in value.method_overload_sets[_key2004][_key2009]) {
                    _vscratch2013.text(_item2014);
                }
                _keys2010.append((_scratch2011.finish(), _vscratch2013.finish(), _key2009));
            }
            _keys2010.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2008.unsigned(_keys2010.count);
            for (var (_bytes2012, _, _key2009) in _keys2010) {
                _vscratch2008.text(_key2009);
                _vscratch2008.unsigned(value.method_overload_sets[_key2004][_key2009].count);
                for (var _item2015 in value.method_overload_sets[_key2004][_key2009]) {
                    _vscratch2008.text(_item2015);
                }
            }
            _keys2005.append((_scratch2006.finish(), _vscratch2008.finish(), _key2004));
        }
        _keys2005.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2005.count);
        for (var (_bytes2007, _, _key2004) in _keys2005) {
            out.text(_key2004);
            var _keys2017 = Array<(u8[], u8[], String)>();
            for (var (_key2016, _) in value.method_overload_sets[_key2004]) {
                var _scratch2018 = out.scratch();
                _scratch2018.text(_key2016);
                var _vscratch2020 = out.scratch();
                _vscratch2020.unsigned(value.method_overload_sets[_key2004][_key2016].count);
                for (var _item2021 in value.method_overload_sets[_key2004][_key2016]) {
                    _vscratch2020.text(_item2021);
                }
                _keys2017.append((_scratch2018.finish(), _vscratch2020.finish(), _key2016));
            }
            _keys2017.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2017.count);
            for (var (_bytes2019, _, _key2016) in _keys2017) {
                out.text(_key2016);
                out.unsigned(value.method_overload_sets[_key2004][_key2016].count);
                for (var _item2022 in value.method_overload_sets[_key2004][_key2016]) {
                    out.text(_item2022);
                }
            }
        }
        for (var (_okey2023, _) in value.method_overload_sets) {
            var _own2024 = RecordOut();
            _own2024.blank_bodies = true;
            _own2024.blank_locs = true;
            _own2024.pending_as_bytes = true;
            _own2024.text(_okey2023);
            var _keys2026 = Array<(u8[], u8[], String)>();
            for (var (_key2025, _) in value.method_overload_sets[_okey2023]) {
                var _scratch2027 = _own2024.scratch();
                _scratch2027.text(_key2025);
                var _vscratch2029 = _own2024.scratch();
                _vscratch2029.unsigned(value.method_overload_sets[_okey2023][_key2025].count);
                for (var _item2030 in value.method_overload_sets[_okey2023][_key2025]) {
                    _vscratch2029.text(_item2030);
                }
                _keys2026.append((_scratch2027.finish(), _vscratch2029.finish(), _key2025));
            }
            _keys2026.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own2024.unsigned(_keys2026.count);
            for (var (_bytes2028, _, _key2025) in _keys2026) {
                _own2024.text(_key2025);
                _own2024.unsigned(value.method_overload_sets[_okey2023][_key2025].count);
                for (var _item2031 in value.method_overload_sets[_okey2023][_key2025]) {
                    _own2024.text(_item2031);
                }
            }
            base.own("method_overload_sets", interface_text(_own2024));
        }
        base.count("method_overload_sets whole", 0);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2062 = 0;
    var _news2063 = HashSet<Loc>();
    for (var _key2059 in value.private_functions) {
        var _kscratch2060 = base.scratch();
        _kscratch2060.loc(_key2059);
        var _vscratch2061 = base.scratch();
        var _had = base.entry("private_functions", _kscratch2060, _vscratch2061);
        if (_had >= 0) {
            _kept2062 += 1;
        }
        if (_had != 1) {
            _news2063.insert(_key2059);
        }
    }
    if (_kept2062 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys2065 = Array<(u8[], u8[], Loc)>();
        for (var _key2064 in _news2063) {
            var _scratch2066 = out.scratch();
            _scratch2066.loc(_key2064);
            var _vscratch2068 = out.scratch();
            _keys2065.append((_scratch2066.finish(), _vscratch2068.finish(), _key2064));
        }
        _keys2065.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2065.count);
        for (var (_bytes2067, _, _key2064) in _keys2065) {
            out.loc(_key2064);
        }
        for (var _okey2069 in _news2063) {
            var _own2070 = RecordOut();
            _own2070.blank_bodies = true;
            _own2070.blank_locs = true;
            _own2070.pending_as_bytes = true;
            _own2070.loc(_okey2069);
            base.own_at("private_functions", _okey2069, interface_text(_own2070));
        }
    } else {
        out.unsigned(0);
        var _keys2072 = Array<(u8[], u8[], Loc)>();
        for (var _key2071 in value.private_functions) {
            var _scratch2073 = out.scratch();
            _scratch2073.loc(_key2071);
            var _vscratch2075 = out.scratch();
            _keys2072.append((_scratch2073.finish(), _vscratch2075.finish(), _key2071));
        }
        _keys2072.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2072.count);
        for (var (_bytes2074, _, _key2071) in _keys2072) {
            out.loc(_key2071);
        }
        for (var _okey2076 in value.private_functions) {
            var _own2077 = RecordOut();
            _own2077.blank_bodies = true;
            _own2077.blank_locs = true;
            _own2077.pending_as_bytes = true;
            _own2077.loc(_okey2076);
            base.own_at("private_functions", _okey2076, interface_text(_own2077));
        }
        base.count("private_functions whole", 0);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2088 = 0;
    var _news2089 = HashSet<Loc>();
    for (var _key2085 in value.file_private_functions) {
        var _kscratch2086 = base.scratch();
        _kscratch2086.loc(_key2085);
        var _vscratch2087 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch2086, _vscratch2087);
        if (_had >= 0) {
            _kept2088 += 1;
        }
        if (_had != 1) {
            _news2089.insert(_key2085);
        }
    }
    if (_kept2088 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys2091 = Array<(u8[], u8[], Loc)>();
        for (var _key2090 in _news2089) {
            var _scratch2092 = out.scratch();
            _scratch2092.loc(_key2090);
            var _vscratch2094 = out.scratch();
            _keys2091.append((_scratch2092.finish(), _vscratch2094.finish(), _key2090));
        }
        _keys2091.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2091.count);
        for (var (_bytes2093, _, _key2090) in _keys2091) {
            out.loc(_key2090);
        }
        for (var _okey2095 in _news2089) {
            var _own2096 = RecordOut();
            _own2096.blank_bodies = true;
            _own2096.blank_locs = true;
            _own2096.pending_as_bytes = true;
            _own2096.loc(_okey2095);
            base.own_at("file_private_functions", _okey2095, interface_text(_own2096));
        }
    } else {
        out.unsigned(0);
        var _keys2098 = Array<(u8[], u8[], Loc)>();
        for (var _key2097 in value.file_private_functions) {
            var _scratch2099 = out.scratch();
            _scratch2099.loc(_key2097);
            var _vscratch2101 = out.scratch();
            _keys2098.append((_scratch2099.finish(), _vscratch2101.finish(), _key2097));
        }
        _keys2098.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2098.count);
        for (var (_bytes2100, _, _key2097) in _keys2098) {
            out.loc(_key2097);
        }
        for (var _okey2102 in value.file_private_functions) {
            var _own2103 = RecordOut();
            _own2103.blank_bodies = true;
            _own2103.blank_locs = true;
            _own2103.pending_as_bytes = true;
            _own2103.loc(_okey2102);
            base.own_at("file_private_functions", _okey2102, interface_text(_own2103));
        }
        base.count("file_private_functions whole", 0);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n2113 = base.size("call_targets");
    var _scratch2112 = base.scratch();
    if (value.call_targets.count >= _n2113) {
        for (var _i2114 in 0.._n2113) {
            var (_t2115, _t2116) = value.call_targets[_i2114];
            _scratch2112.loc(_t2115);
            _scratch2112.text(_t2116);
        }
    }
    if (value.call_targets.count >= _n2113 and base.same_list("call_targets", _scratch2112)) {
        out.unsigned(1);
        out.unsigned(_n2113);
        out.unsigned(value.call_targets.count - _n2113);
        for (var _i2114 in _n2113..value.call_targets.count) {
            var (_t2117, _t2118) = value.call_targets[_i2114];
            out.loc(_t2117);
            out.text(_t2118);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item2119 in value.call_targets) {
            var (_t2120, _t2121) = _item2119;
            out.loc(_t2120);
            out.text(_t2121);
        }
        base.count("call_targets whole", 0);
    }
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2138 = 0;
    var _news2139 = Array<(Loc, String)>();
    for (var _item2136 in value.argument_names) {
        var _escratch2137 = base.scratch();
        var (_t2140, _t2141) = _item2136;
        _escratch2137.loc(_t2140);
        _escratch2137.text(_t2141);
        if (base.entry("argument_names", _escratch2137, base.scratch()) >= 0) {
            _kept2138 += 1;
        } else {
            _news2139.append(_item2136);
        }
    }
    if (_kept2138 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2139.count);
        for (var _item2142 in _news2139) {
            var (_t2143, _t2144) = _item2142;
            out.loc(_t2143);
            out.text(_t2144);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2145 in value.argument_names) {
            var (_t2146, _t2147) = _item2145;
            out.loc(_t2146);
            out.text(_t2147);
        }
        base.count("argument_names whole", 0);
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2162 = base.size("namespaces");
    var _scratch2161 = base.scratch();
    if (value.namespaces.count >= _n2162) {
        for (var _i2163 in 0.._n2162) {
            _scratch2161.text(value.namespaces[_i2163]);
        }
    }
    if (value.namespaces.count >= _n2162 and base.same_list("namespaces", _scratch2161)) {
        out.unsigned(1);
        out.unsigned(_n2162);
        out.unsigned(value.namespaces.count - _n2162);
        for (var _i2163 in _n2162..value.namespaces.count) {
            out.text(value.namespaces[_i2163]);
            {
                var _own2164 = RecordOut();
                _own2164.blank_bodies = true;
                _own2164.blank_locs = true;
                _own2164.pending_as_bytes = true;
                _own2164.text(value.namespaces[_i2163]);
                base.own("namespaces", interface_text(_own2164));
            }
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2165 in value.namespaces) {
            out.text(_item2165);
        }
        for (var _i2163 in 0..value.namespaces.count) {
            {
                var _own2166 = RecordOut();
                _own2166.blank_bodies = true;
                _own2166.blank_locs = true;
                _own2166.pending_as_bytes = true;
                _own2166.text(value.namespaces[_i2163]);
                base.own("namespaces", interface_text(_own2166));
            }
        }
        base.count("namespaces whole", 0);
    }
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2177 = base.size("cached_files");
    var _scratch2176 = base.scratch();
    if (value.cached_files.count >= _n2177) {
        for (var _i2178 in 0.._n2177) {
            _scratch2176.flag(value.cached_files[_i2178]);
        }
    }
    if (value.cached_files.count >= _n2177 and base.same_list("cached_files", _scratch2176)) {
        out.unsigned(1);
        out.unsigned(_n2177);
        out.unsigned(value.cached_files.count - _n2177);
        for (var _i2178 in _n2177..value.cached_files.count) {
            out.flag(value.cached_files[_i2178]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2179 in value.cached_files) {
            out.flag(_item2179);
        }
        base.count("cached_files whole", 0);
    }
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2191 = 0;
    var _news2192 = HashMap<Loc, String>();
    for (var (_key2188, _) in value.recorded_summaries) {
        var _kscratch2189 = base.scratch();
        _kscratch2189.loc(_key2188);
        var _vscratch2190 = base.scratch();
        _vscratch2190.text(value.recorded_summaries[_key2188]);
        var _had = base.entry("recorded_summaries", _kscratch2189, _vscratch2190);
        if (_had >= 0) {
            _kept2191 += 1;
        }
        if (_had != 1) {
            _news2192[_key2188] = value.recorded_summaries[_key2188];
        }
    }
    if (_kept2191 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2194 = Array<(u8[], u8[], Loc)>();
        for (var (_key2193, _) in _news2192) {
            var _scratch2195 = out.scratch();
            _scratch2195.loc(_key2193);
            var _vscratch2197 = out.scratch();
            _vscratch2197.text(_news2192[_key2193]);
            _keys2194.append((_scratch2195.finish(), _vscratch2197.finish(), _key2193));
        }
        _keys2194.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2194.count);
        for (var (_bytes2196, _, _key2193) in _keys2194) {
            out.loc(_key2193);
            out.text(_news2192[_key2193]);
        }
    } else {
        out.unsigned(0);
        var _keys2199 = Array<(u8[], u8[], Loc)>();
        for (var (_key2198, _) in value.recorded_summaries) {
            var _scratch2200 = out.scratch();
            _scratch2200.loc(_key2198);
            var _vscratch2202 = out.scratch();
            _vscratch2202.text(value.recorded_summaries[_key2198]);
            _keys2199.append((_scratch2200.finish(), _vscratch2202.finish(), _key2198));
        }
        _keys2199.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2199.count);
        for (var (_bytes2201, _, _key2198) in _keys2199) {
            out.loc(_key2198);
            out.text(value.recorded_summaries[_key2198]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2215 = 0;
    var _news2216 = HashSet<Loc>();
    for (var _key2212 in value.stripped) {
        var _kscratch2213 = base.scratch();
        _kscratch2213.loc(_key2212);
        var _vscratch2214 = base.scratch();
        var _had = base.entry("stripped", _kscratch2213, _vscratch2214);
        if (_had >= 0) {
            _kept2215 += 1;
        }
        if (_had != 1) {
            _news2216.insert(_key2212);
        }
    }
    if (_kept2215 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2218 = Array<(u8[], u8[], Loc)>();
        for (var _key2217 in _news2216) {
            var _scratch2219 = out.scratch();
            _scratch2219.loc(_key2217);
            var _vscratch2221 = out.scratch();
            _keys2218.append((_scratch2219.finish(), _vscratch2221.finish(), _key2217));
        }
        _keys2218.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2218.count);
        for (var (_bytes2220, _, _key2217) in _keys2218) {
            out.loc(_key2217);
        }
    } else {
        out.unsigned(0);
        var _keys2223 = Array<(u8[], u8[], Loc)>();
        for (var _key2222 in value.stripped) {
            var _scratch2224 = out.scratch();
            _scratch2224.loc(_key2222);
            var _vscratch2226 = out.scratch();
            _keys2223.append((_scratch2224.finish(), _vscratch2226.finish(), _key2222));
        }
        _keys2223.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2223.count);
        for (var (_bytes2225, _, _key2222) in _keys2223) {
            out.loc(_key2222);
        }
        base.count("stripped whole", 0);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _seq2236 = base.ref_templates;
    ulong _bj2237 = 0;
    var _news2239 = Array<ulong>();
    var _patches2240 = Array<(ulong, ulong)>();
    for (var _i2241 in 0..value.templates.structs.count) {
        if (_bj2237 < _seq2236.count
            and value.templates.structs[_i2241] === _seq2236[_bj2237]
            and !value.extended_checked.contains(value.templates.structs[_i2241].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2241]);
                base.verify_same("t", _bj2237, scratch, value.templates.structs[_i2241].name);
            }
            _bj2237 += 1;
        } else if (_bj2237 < _seq2236.count
            and !(value.templates.structs[_i2241] === _seq2236[_bj2237])
            and _same_m_StructDef(value.templates.structs[_i2241], _seq2236[_bj2237], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2241]);
                base.verify_same("t", _bj2237, scratch, value.templates.structs[_i2241].name);
            }
            _bj2237 += 1;
        } else if (_bj2237 < _seq2236.count and value.templates.structs[_i2241].name == _seq2236[_bj2237].name) {
            _patches2240.append((_i2241, _bj2237));
            _bj2237 += 1;
        } else {
            _news2239.append(_i2241);
        }
    }
    if (_bj2237 == _seq2236.count) {
        out.unsigned(2);
        out.unsigned(_patches2240.count);
        for (var (_i2241, _b) in _patches2240) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2241].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2241], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2242 = RecordOut();
                _own2242.blank_bodies = false;
                _own2242.blank_locs = true;
                _own2242.pending_as_bytes = true;
                _m_StructDef_write(_own2242, value.templates.structs[_i2241]);
                base.own("templates structs", interface_text(_own2242));
            }
        }
        out.unsigned(_news2239.count);
        for (var _i2241 in _news2239) {
            ulong _before = out.values.count;
            out.unsigned(_i2241);
            _m_StructDef_write(out, value.templates.structs[_i2241]);
            base.count("t new", out.values.count - _before);
            {
                var _own2243 = RecordOut();
                _own2243.blank_bodies = false;
                _own2243.blank_locs = true;
                _own2243.pending_as_bytes = true;
                _m_StructDef_write(_own2243, value.templates.structs[_i2241]);
                base.own("templates structs", interface_text(_own2243));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2235 = HashSet<long>();
        var _slots2238 = HashMap<String, long>();
        for (var _i2241 in 0.._seq2236.count) {
            if (!_slots2238.contains(_seq2236[_i2241].name)) {
                _slots2238[_seq2236[_i2241].name] = _i2241 as long;
            }
        }
        out.unsigned(value.templates.structs.count);
        for (var _i2241 in 0..value.templates.structs.count) {
            var _item2234 = value.templates.structs[_i2241];
            var _slot = _slots2238.try_get(_item2234.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq2236[named as ulong] === _item2234
                and !value.extended_checked.contains(_item2234.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2235.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2235.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2234, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2234);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2235.count);
    }
    var _seq2257 = base.ref_template_functions;
    ulong _bj2258 = 0;
    var _news2259 = Array<ulong>();
    var _changed2253 = Array<(ulong, ulong)>();
    for (var _i2260 in 0..value.templates.functions.count) {
        if (_bj2258 < _seq2257.count and value.templates.functions[_i2260] === _seq2257[_bj2258]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2260]);
                base.verify_same("tf", _bj2258, scratch);
            }
            _bj2258 += 1;
        } else if (_bj2258 < _seq2257.count
            and _same_m_FunctionDef(value.templates.functions[_i2260], _seq2257[_bj2258], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2260]);
                base.verify_same("tf", _bj2258, scratch);
            }
            _bj2258 += 1;
        } else if (_bj2258 < _seq2257.count and value.templates.functions[_i2260].name == _seq2257[_bj2258].name) {
            _changed2253.append((_i2260, _bj2258));
            _bj2258 += 1;
        } else {
            _news2259.append(_i2260);
        }
    }
    if (_bj2258 == _seq2257.count) {
        out.unsigned(2);
        out.unsigned(_changed2253.count);
        for (var (_i2260, _b) in _changed2253) {
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
        base.count("tf" + " changed", _changed2253.count);
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
    base.stat("caller_copies", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.linked);
    base.stat("linked", out.values.count - _mark);
    _mark = out.values.count;
}

_m_Module_read_delta(input: RecordIn, base: Module): Module {
    var _f1499 = Array<ast.Import>();
    var _mode1502 = input.unsigned();
    if (_mode1502 == 2) {
        var _changed1488 = HashMap<ulong, ast.Import>();
        ulong _bi1503 = 0;
        var _n1500 = input.count();
        for (var _ in 0.._n1500) {
            var _at1504 = input.unsigned();
            while (_f1499.count < _at1504 or (input.merging and _bi1503 < base.imports.count)) {
                var _c = _changed1488.try_get(_bi1503);
                _f1499.append(_c.is_value() ? _c.value() : base.imports[_bi1503]);
                _bi1503 += 1;
            }
            _f1499.append(_a_Import_read(input));
        }
        while (_bi1503 < base.imports.count) {
            var _c = _changed1488.try_get(_bi1503);
            _f1499.append(_c.is_value() ? _c.value() : base.imports[_bi1503]);
            _bi1503 += 1;
        }
    } else if (_mode1502 == 3) {
        var _n1500 = input.count();
        for (var _ in 0.._n1500) {
            _f1499.append(_a_Import_read(input));
        }
    } else {
        var _n1500 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1500) {
            var _tag1501 = input.unsigned();
            if (_tag1501 & 1 == 1) {
                if (!input.merging) {
                    _f1499.append(base.imports[_tag1501 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1499.append(_read);
                }
            }
        }
    }
    var _f1532 = Array<StructDef>();
    var _mode1535 = input.unsigned();
    if (_mode1535 == 2) {
        var _patched1538 = HashMap<ulong, StructDef>();
        var _n1533 = input.count();
        for (var _ in 0.._n1533) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1538[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1536 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1537 = input.unsigned();
            while (_f1532.count < _at1537 or (input.merging and _bi1536 < base.structs.count)) {
                var _p = _patched1538.try_get(_bi1536);
                _f1532.append(_p.is_value() ? _p.value() : base.structs[_bi1536]);
                _bi1536 += 1;
            }
            _f1532.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1536 < base.structs.count) {
            var _p = _patched1538.try_get(_bi1536);
            _f1532.append(_p.is_value() ? _p.value() : base.structs[_bi1536]);
            _bi1536 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1533 = input.count();
        for (var _ in 0.._n1533) {
            var _tag1534 = input.unsigned();
            if (_tag1534 & 1 == 1) {
                _f1532.append(base.structs[(_tag1534 >> 1) < base.structs.count ? _tag1534 >> 1 : 0]);
            } else if (_tag1534 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1532.append(_patch_s_read(input, _was));
            } else {
                _f1532.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1552 = Array<TraitDef>();
    var _mode1555 = input.unsigned();
    if (_mode1555 == 2) {
        var _changed1541 = HashMap<ulong, TraitDef>();
        ulong _bi1556 = 0;
        var _n1553 = input.count();
        for (var _ in 0.._n1553) {
            var _at1557 = input.unsigned();
            while (_f1552.count < _at1557 or (input.merging and _bi1556 < base.traits.count)) {
                var _c = _changed1541.try_get(_bi1556);
                _f1552.append(_c.is_value() ? _c.value() : base.traits[_bi1556]);
                _bi1556 += 1;
            }
            _f1552.append(_m_TraitDef_read(input));
        }
        while (_bi1556 < base.traits.count) {
            var _c = _changed1541.try_get(_bi1556);
            _f1552.append(_c.is_value() ? _c.value() : base.traits[_bi1556]);
            _bi1556 += 1;
        }
    } else if (_mode1555 == 3) {
        var _n1553 = input.count();
        for (var _ in 0.._n1553) {
            _f1552.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1553 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1553) {
            var _tag1554 = input.unsigned();
            if (_tag1554 & 1 == 1) {
                if (!input.merging) {
                    _f1552.append(base.traits[_tag1554 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1552.append(_read);
                }
            }
        }
    }
    var _f1571 = Array<ExtensionDef>();
    var _mode1574 = input.unsigned();
    if (_mode1574 == 2) {
        var _changed1560 = HashMap<ulong, ExtensionDef>();
        ulong _bi1575 = 0;
        var _n1572 = input.count();
        for (var _ in 0.._n1572) {
            var _at1576 = input.unsigned();
            while (_f1571.count < _at1576 or (input.merging and _bi1575 < base.extensions.count)) {
                var _c = _changed1560.try_get(_bi1575);
                _f1571.append(_c.is_value() ? _c.value() : base.extensions[_bi1575]);
                _bi1575 += 1;
            }
            _f1571.append(_m_ExtensionDef_read(input));
        }
        while (_bi1575 < base.extensions.count) {
            var _c = _changed1560.try_get(_bi1575);
            _f1571.append(_c.is_value() ? _c.value() : base.extensions[_bi1575]);
            _bi1575 += 1;
        }
    } else if (_mode1574 == 3) {
        var _n1572 = input.count();
        for (var _ in 0.._n1572) {
            _f1571.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1572 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1572) {
            var _tag1573 = input.unsigned();
            if (_tag1573 & 1 == 1) {
                if (!input.merging) {
                    _f1571.append(base.extensions[_tag1573 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1571.append(_read);
                }
            }
        }
    }
    var _f1590 = Array<FunctionDef>();
    var _mode1593 = input.unsigned();
    if (_mode1593 == 2) {
        var _changed1579 = HashMap<ulong, FunctionDef>();
        var _nc1581 = input.count();
        for (var _ in 0.._nc1581) {
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
                _changed1579[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1594 = 0;
        var _n1591 = input.count();
        for (var _ in 0.._n1591) {
            var _at1595 = input.unsigned();
            while (_f1590.count < _at1595 or (input.merging and _bi1594 < base.functions.count)) {
                var _c = _changed1579.try_get(_bi1594);
                _f1590.append(_c.is_value() ? _c.value() : base.functions[_bi1594]);
                _bi1594 += 1;
            }
            _f1590.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1594 < base.functions.count) {
            var _c = _changed1579.try_get(_bi1594);
            _f1590.append(_c.is_value() ? _c.value() : base.functions[_bi1594]);
            _bi1594 += 1;
        }
    } else if (_mode1593 == 3) {
        var _n1591 = input.count();
        for (var _ in 0.._n1591) {
            _f1590.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1591 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1591) {
            var _tag1592 = input.unsigned();
            if (_tag1592 & 1 == 1) {
                if (!input.merging) {
                    _f1590.append(base.functions[_tag1592 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1590.append(_read);
                }
            }
        }
    }
    var _f1609 = Array<ExternDef>();
    var _mode1612 = input.unsigned();
    if (_mode1612 == 2) {
        var _changed1598 = HashMap<ulong, ExternDef>();
        ulong _bi1613 = 0;
        var _n1610 = input.count();
        for (var _ in 0.._n1610) {
            var _at1614 = input.unsigned();
            while (_f1609.count < _at1614 or (input.merging and _bi1613 < base.externs.count)) {
                var _c = _changed1598.try_get(_bi1613);
                _f1609.append(_c.is_value() ? _c.value() : base.externs[_bi1613]);
                _bi1613 += 1;
            }
            _f1609.append(_m_ExternDef_read(input));
        }
        while (_bi1613 < base.externs.count) {
            var _c = _changed1598.try_get(_bi1613);
            _f1609.append(_c.is_value() ? _c.value() : base.externs[_bi1613]);
            _bi1613 += 1;
        }
    } else if (_mode1612 == 3) {
        var _n1610 = input.count();
        for (var _ in 0.._n1610) {
            _f1609.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1610 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1610) {
            var _tag1611 = input.unsigned();
            if (_tag1611 & 1 == 1) {
                if (!input.merging) {
                    _f1609.append(base.externs[_tag1611 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1609.append(_read);
                }
            }
        }
    }
    var _f1628 = Array<VariableDef>();
    var _mode1631 = input.unsigned();
    if (_mode1631 == 2) {
        var _changed1617 = HashMap<ulong, VariableDef>();
        ulong _bi1632 = 0;
        var _n1629 = input.count();
        for (var _ in 0.._n1629) {
            var _at1633 = input.unsigned();
            while (_f1628.count < _at1633 or (input.merging and _bi1632 < base.globals.count)) {
                var _c = _changed1617.try_get(_bi1632);
                _f1628.append(_c.is_value() ? _c.value() : base.globals[_bi1632]);
                _bi1632 += 1;
            }
            _f1628.append(_m_VariableDef_read(input));
        }
        while (_bi1632 < base.globals.count) {
            var _c = _changed1617.try_get(_bi1632);
            _f1628.append(_c.is_value() ? _c.value() : base.globals[_bi1632]);
            _bi1632 += 1;
        }
    } else if (_mode1631 == 3) {
        var _n1629 = input.count();
        for (var _ in 0.._n1629) {
            _f1628.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1629 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1629) {
            var _tag1630 = input.unsigned();
            if (_tag1630 & 1 == 1) {
                if (!input.merging) {
                    _f1628.append(base.globals[_tag1630 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1628.append(_read);
                }
            }
        }
    }
    var _f1647 = Array<ModuleStaticBlock>();
    var _mode1650 = input.unsigned();
    if (_mode1650 == 2) {
        var _changed1636 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1651 = 0;
        var _n1648 = input.count();
        for (var _ in 0.._n1648) {
            var _at1652 = input.unsigned();
            while (_f1647.count < _at1652 or (input.merging and _bi1651 < base.static_blocks.count)) {
                var _c = _changed1636.try_get(_bi1651);
                _f1647.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1651]);
                _bi1651 += 1;
            }
            _f1647.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1651 < base.static_blocks.count) {
            var _c = _changed1636.try_get(_bi1651);
            _f1647.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1651]);
            _bi1651 += 1;
        }
    } else if (_mode1650 == 3) {
        var _n1648 = input.count();
        for (var _ in 0.._n1648) {
            _f1647.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1648 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1648) {
            var _tag1649 = input.unsigned();
            if (_tag1649 & 1 == 1) {
                if (!input.merging) {
                    _f1647.append(base.static_blocks[_tag1649 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1647.append(_read);
                }
            }
        }
    }
    var _f1666 = Array<EnumDef>();
    var _mode1669 = input.unsigned();
    if (_mode1669 == 2) {
        var _changed1655 = HashMap<ulong, EnumDef>();
        ulong _bi1670 = 0;
        var _n1667 = input.count();
        for (var _ in 0.._n1667) {
            var _at1671 = input.unsigned();
            while (_f1666.count < _at1671 or (input.merging and _bi1670 < base.enums.count)) {
                var _c = _changed1655.try_get(_bi1670);
                _f1666.append(_c.is_value() ? _c.value() : base.enums[_bi1670]);
                _bi1670 += 1;
            }
            _f1666.append(_m_EnumDef_read(input));
        }
        while (_bi1670 < base.enums.count) {
            var _c = _changed1655.try_get(_bi1670);
            _f1666.append(_c.is_value() ? _c.value() : base.enums[_bi1670]);
            _bi1670 += 1;
        }
    } else if (_mode1669 == 3) {
        var _n1667 = input.count();
        for (var _ in 0.._n1667) {
            _f1666.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1667 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1667) {
            var _tag1668 = input.unsigned();
            if (_tag1668 & 1 == 1) {
                if (!input.merging) {
                    _f1666.append(base.enums[_tag1668 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1666.append(_read);
                }
            }
        }
    }
    var _f1685 = Array<TypeName>();
    var _mode1688 = input.unsigned();
    if (_mode1688 == 2) {
        var _changed1674 = HashMap<ulong, TypeName>();
        ulong _bi1689 = 0;
        var _n1686 = input.count();
        for (var _ in 0.._n1686) {
            var _at1690 = input.unsigned();
            while (_f1685.count < _at1690 or (input.merging and _bi1689 < base.struct_specs.count)) {
                var _c = _changed1674.try_get(_bi1689);
                _f1685.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1689]);
                _bi1689 += 1;
            }
            _f1685.append(_m_TypeName_read(input));
        }
        while (_bi1689 < base.struct_specs.count) {
            var _c = _changed1674.try_get(_bi1689);
            _f1685.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1689]);
            _bi1689 += 1;
        }
    } else if (_mode1688 == 3) {
        var _n1686 = input.count();
        for (var _ in 0.._n1686) {
            _f1685.append(_m_TypeName_read(input));
        }
    } else {
        var _n1686 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1686) {
            var _tag1687 = input.unsigned();
            if (_tag1687 & 1 == 1) {
                if (!input.merging) {
                    _f1685.append(base.struct_specs[_tag1687 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1685.append(_read);
                }
            }
        }
    }
    var _f1704 = Array<TypeName>();
    var _mode1707 = input.unsigned();
    if (_mode1707 == 2) {
        var _changed1693 = HashMap<ulong, TypeName>();
        ulong _bi1708 = 0;
        var _n1705 = input.count();
        for (var _ in 0.._n1705) {
            var _at1709 = input.unsigned();
            while (_f1704.count < _at1709 or (input.merging and _bi1708 < base.func_specs.count)) {
                var _c = _changed1693.try_get(_bi1708);
                _f1704.append(_c.is_value() ? _c.value() : base.func_specs[_bi1708]);
                _bi1708 += 1;
            }
            _f1704.append(_m_TypeName_read(input));
        }
        while (_bi1708 < base.func_specs.count) {
            var _c = _changed1693.try_get(_bi1708);
            _f1704.append(_c.is_value() ? _c.value() : base.func_specs[_bi1708]);
            _bi1708 += 1;
        }
    } else if (_mode1707 == 3) {
        var _n1705 = input.count();
        for (var _ in 0.._n1705) {
            _f1704.append(_m_TypeName_read(input));
        }
    } else {
        var _n1705 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1705) {
            var _tag1706 = input.unsigned();
            if (_tag1706 & 1 == 1) {
                if (!input.merging) {
                    _f1704.append(base.func_specs[_tag1706 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1704.append(_read);
                }
            }
        }
    }
    var _f1716 = Array<TypeAliasDef>();
    var _n1717 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1716.append(_b);
        }
    }
    for (var _ in 0.._n1717) {
        var _tag1718 = input.unsigned();
        if (_tag1718 & 1 == 1) {
            if (!input.merging) {
                _f1716.append(base.type_aliases[_tag1718 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1716.append(_read);
            }
        }
    }
    var _f1732 = Array<Withheld>();
    var _mode1735 = input.unsigned();
    if (_mode1735 == 2) {
        var _changed1721 = HashMap<ulong, Withheld>();
        ulong _bi1736 = 0;
        var _n1733 = input.count();
        for (var _ in 0.._n1733) {
            var _at1737 = input.unsigned();
            while (_f1732.count < _at1737 or (input.merging and _bi1736 < base.withheld.count)) {
                var _c = _changed1721.try_get(_bi1736);
                _f1732.append(_c.is_value() ? _c.value() : base.withheld[_bi1736]);
                _bi1736 += 1;
            }
            _f1732.append(_m_Withheld_read(input));
        }
        while (_bi1736 < base.withheld.count) {
            var _c = _changed1721.try_get(_bi1736);
            _f1732.append(_c.is_value() ? _c.value() : base.withheld[_bi1736]);
            _bi1736 += 1;
        }
    } else if (_mode1735 == 3) {
        var _n1733 = input.count();
        for (var _ in 0.._n1733) {
            _f1732.append(_m_Withheld_read(input));
        }
    } else {
        var _n1733 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1733) {
            var _tag1734 = input.unsigned();
            if (_tag1734 & 1 == 1) {
                if (!input.merging) {
                    _f1732.append(base.withheld[_tag1734 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1732.append(_read);
                }
            }
        }
    }
    var _f1751 = Array<PropertyDef>();
    var _mode1754 = input.unsigned();
    if (_mode1754 == 2) {
        var _changed1740 = HashMap<ulong, PropertyDef>();
        ulong _bi1755 = 0;
        var _n1752 = input.count();
        for (var _ in 0.._n1752) {
            var _at1756 = input.unsigned();
            while (_f1751.count < _at1756 or (input.merging and _bi1755 < base.properties.count)) {
                var _c = _changed1740.try_get(_bi1755);
                _f1751.append(_c.is_value() ? _c.value() : base.properties[_bi1755]);
                _bi1755 += 1;
            }
            _f1751.append(_m_PropertyDef_read(input));
        }
        while (_bi1755 < base.properties.count) {
            var _c = _changed1740.try_get(_bi1755);
            _f1751.append(_c.is_value() ? _c.value() : base.properties[_bi1755]);
            _bi1755 += 1;
        }
    } else if (_mode1754 == 3) {
        var _n1752 = input.count();
        for (var _ in 0.._n1752) {
            _f1751.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1752 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1752) {
            var _tag1753 = input.unsigned();
            if (_tag1753 & 1 == 1) {
                if (!input.merging) {
                    _f1751.append(base.properties[_tag1753 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1751.append(_read);
                }
            }
        }
    }
    var _f1770 = Array<TypeUse>();
    var _mode1773 = input.unsigned();
    if (_mode1773 == 2) {
        var _changed1759 = HashMap<ulong, TypeUse>();
        ulong _bi1774 = 0;
        var _n1771 = input.count();
        for (var _ in 0.._n1771) {
            var _at1775 = input.unsigned();
            while (_f1770.count < _at1775 or (input.merging and _bi1774 < base.type_uses.count)) {
                var _c = _changed1759.try_get(_bi1774);
                _f1770.append(_c.is_value() ? _c.value() : base.type_uses[_bi1774]);
                _bi1774 += 1;
            }
            _f1770.append(_m_TypeUse_read(input));
        }
        while (_bi1774 < base.type_uses.count) {
            var _c = _changed1759.try_get(_bi1774);
            _f1770.append(_c.is_value() ? _c.value() : base.type_uses[_bi1774]);
            _bi1774 += 1;
        }
    } else if (_mode1773 == 3) {
        var _n1771 = input.count();
        for (var _ in 0.._n1771) {
            _f1770.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1771 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1771) {
            var _tag1772 = input.unsigned();
            if (_tag1772 & 1 == 1) {
                if (!input.merging) {
                    _f1770.append(base.type_uses[_tag1772 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1770.append(_read);
                }
            }
        }
    }
    var _f1789 = Array<UseContext>();
    var _mode1792 = input.unsigned();
    if (_mode1792 == 2) {
        var _changed1778 = HashMap<ulong, UseContext>();
        ulong _bi1793 = 0;
        var _n1790 = input.count();
        for (var _ in 0.._n1790) {
            var _at1794 = input.unsigned();
            while (_f1789.count < _at1794 or (input.merging and _bi1793 < base.use_contexts.count)) {
                var _c = _changed1778.try_get(_bi1793);
                _f1789.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1793]);
                _bi1793 += 1;
            }
            _f1789.append(_m_UseContext_read(input));
        }
        while (_bi1793 < base.use_contexts.count) {
            var _c = _changed1778.try_get(_bi1793);
            _f1789.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1793]);
            _bi1793 += 1;
        }
    } else if (_mode1792 == 3) {
        var _n1790 = input.count();
        for (var _ in 0.._n1790) {
            _f1789.append(_m_UseContext_read(input));
        }
    } else {
        var _n1790 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1790) {
            var _tag1791 = input.unsigned();
            if (_tag1791 & 1 == 1) {
                if (!input.merging) {
                    _f1789.append(base.use_contexts[_tag1791 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1789.append(_read);
                }
            }
        }
    }
    var _f1810 = Array<(Loc, ulong, Loc)>();
    var _tag1811 = input.unsigned();
    if (_tag1811 == 1) {
        input.unsigned();
        for (var _i1799 in 0..base.literal_args.count) {
            _f1810.append(base.literal_args[_i1799]);
        }
        var _more1813 = input.count();
        for (var _ in 0.._more1813) {
            var _t1814 = input.loc();
            var _t1815 = input.unsigned();
            var _t1816 = input.loc();
            _f1810.append((_t1814, _t1815, _t1816));
        }
    } else {
        var _v1817 = Array<(Loc, ulong, Loc)>();
        var _n1818 = input.count();
        for (var _ in 0.._n1818) {
            var _t1819 = input.loc();
            var _t1820 = input.unsigned();
            var _t1821 = input.loc();
            _v1817.append((_t1819, _t1820, _t1821));
        }
        _f1810 = _v1817;
    }
    var _f1839 = Array<TypeAliasDef>();
    var _mode1842 = input.unsigned();
    if (_mode1842 == 2) {
        var _changed1828 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1843 = 0;
        var _n1840 = input.count();
        for (var _ in 0.._n1840) {
            var _at1844 = input.unsigned();
            while (_f1839.count < _at1844 or (input.merging and _bi1843 < base.constrained_aliases.count)) {
                var _c = _changed1828.try_get(_bi1843);
                _f1839.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1843]);
                _bi1843 += 1;
            }
            _f1839.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1843 < base.constrained_aliases.count) {
            var _c = _changed1828.try_get(_bi1843);
            _f1839.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1843]);
            _bi1843 += 1;
        }
    } else if (_mode1842 == 3) {
        var _n1840 = input.count();
        for (var _ in 0.._n1840) {
            _f1839.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1840 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1840) {
            var _tag1841 = input.unsigned();
            if (_tag1841 & 1 == 1) {
                if (!input.merging) {
                    _f1839.append(base.constrained_aliases[_tag1841 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1839.append(_read);
                }
            }
        }
    }
    var _f1858 = Array<TraitType>();
    var _mode1861 = input.unsigned();
    if (_mode1861 == 2) {
        var _changed1847 = HashMap<ulong, TraitType>();
        ulong _bi1862 = 0;
        var _n1859 = input.count();
        for (var _ in 0.._n1859) {
            var _at1863 = input.unsigned();
            while (_f1858.count < _at1863 or (input.merging and _bi1862 < base.trait_types.count)) {
                var _c = _changed1847.try_get(_bi1862);
                _f1858.append(_c.is_value() ? _c.value() : base.trait_types[_bi1862]);
                _bi1862 += 1;
            }
            _f1858.append(_m_TraitType_read(input));
        }
        while (_bi1862 < base.trait_types.count) {
            var _c = _changed1847.try_get(_bi1862);
            _f1858.append(_c.is_value() ? _c.value() : base.trait_types[_bi1862]);
            _bi1862 += 1;
        }
    } else if (_mode1861 == 3) {
        var _n1859 = input.count();
        for (var _ in 0.._n1859) {
            _f1858.append(_m_TraitType_read(input));
        }
    } else {
        var _n1859 = input.count();
        if (input.merging) {
            input.error = "trait_types" + " written by place";
        }
        for (var _ in 0.._n1859) {
            var _tag1860 = input.unsigned();
            if (_tag1860 & 1 == 1) {
                if (!input.merging) {
                    _f1858.append(base.trait_types[_tag1860 >> 1]);
                }
            } else {
                var _read = _m_TraitType_read(input);
                if (!input.merging or true) {
                    _f1858.append(_read);
                }
            }
        }
    }
    var _v1869 = Array<Conversion>();
    var _n1870 = input.count();
    for (var _ in 0.._n1870) {
        _v1869.append(_m_Conversion_read(input));
    }
    var _f1871 = _v1869;
    var _f1898 = Map<String, Array<String>>();
    var _tag1899 = input.unsigned();
    if (_tag1899 == 1) {
        for (var (_bk1900, _bv) in base.overload_sets) {
            _f1898[_bk1900] = _bv;
        }
        var _v1901 = Map<String, Array<String>>();
        var _n1902 = input.count();
        for (var _ in 0.._n1902) {
            var _k1903 = input.text();
            var _v1904 = Array<String>();
            var _n1905 = input.count();
            for (var _ in 0.._n1905) {
                _v1904.append(input.text());
            }
            _v1901[_k1903] = _v1904;
        }
        for (var (_bk1900, _av) in _v1901) {
            _f1898[_bk1900] = _av;
        }
    } else {
        var _v1906 = Map<String, Array<String>>();
        var _n1907 = input.count();
        for (var _ in 0.._n1907) {
            var _k1908 = input.text();
            var _v1909 = Array<String>();
            var _n1910 = input.count();
            for (var _ in 0.._n1910) {
                _v1909.append(input.text());
            }
            _v1906[_k1908] = _v1909;
        }
        _f1898 = _v1906;
    }
    var _f1945 = Map<String, Array<Array<String>>>();
    var _tag1946 = input.unsigned();
    if (_tag1946 == 1) {
        for (var (_bk1947, _bv) in base.overload_unions) {
            _f1945[_bk1947] = _bv;
        }
        var _v1948 = Map<String, Array<Array<String>>>();
        var _n1949 = input.count();
        for (var _ in 0.._n1949) {
            var _k1950 = input.text();
            var _v1951 = Array<Array<String>>();
            var _n1952 = input.count();
            for (var _ in 0.._n1952) {
                var _v1953 = Array<String>();
                var _n1954 = input.count();
                for (var _ in 0.._n1954) {
                    _v1953.append(input.text());
                }
                _v1951.append(_v1953);
            }
            _v1948[_k1950] = _v1951;
        }
        for (var (_bk1947, _av) in _v1948) {
            _f1945[_bk1947] = _av;
        }
    } else {
        var _v1955 = Map<String, Array<Array<String>>>();
        var _n1956 = input.count();
        for (var _ in 0.._n1956) {
            var _k1957 = input.text();
            var _v1958 = Array<Array<String>>();
            var _n1959 = input.count();
            for (var _ in 0.._n1959) {
                var _v1960 = Array<String>();
                var _n1961 = input.count();
                for (var _ in 0.._n1961) {
                    _v1960.append(input.text());
                }
                _v1958.append(_v1960);
            }
            _v1955[_k1957] = _v1958;
        }
        _f1945 = _v1955;
    }
    var _f2032 = Map<String, Map<String, Array<String>>>();
    var _tag2033 = input.unsigned();
    if (_tag2033 == 1) {
        for (var (_bk2034, _bv) in base.method_overload_sets) {
            _f2032[_bk2034] = _bv;
        }
        var _v2035 = Map<String, Map<String, Array<String>>>();
        var _n2036 = input.count();
        for (var _ in 0.._n2036) {
            var _k2037 = input.text();
            var _v2038 = Map<String, Array<String>>();
            var _n2039 = input.count();
            for (var _ in 0.._n2039) {
                var _k2040 = input.text();
                var _v2041 = Array<String>();
                var _n2042 = input.count();
                for (var _ in 0.._n2042) {
                    _v2041.append(input.text());
                }
                _v2038[_k2040] = _v2041;
            }
            _v2035[_k2037] = _v2038;
        }
        for (var (_bk2034, _av) in _v2035) {
            _f2032[_bk2034] = _av;
        }
    } else {
        var _v2043 = Map<String, Map<String, Array<String>>>();
        var _n2044 = input.count();
        for (var _ in 0.._n2044) {
            var _k2045 = input.text();
            var _v2046 = Map<String, Array<String>>();
            var _n2047 = input.count();
            for (var _ in 0.._n2047) {
                var _k2048 = input.text();
                var _v2049 = Array<String>();
                var _n2050 = input.count();
                for (var _ in 0.._n2050) {
                    _v2049.append(input.text());
                }
                _v2046[_k2048] = _v2049;
            }
            _v2043[_k2045] = _v2046;
        }
        _f2032 = _v2043;
    }
    var _f2058 = _m_ExtensionScopes_read(input);
    var _f2078 = HashSet<Loc>();
    var _tag2079 = input.unsigned();
    if (_tag2079 == 1) {
        for (var _bk2080 in base.private_functions) {
            _f2078.insert(_bk2080);
        }
        var _v2081 = HashSet<Loc>();
        var _n2082 = input.count();
        for (var _ in 0.._n2082) {
            _v2081.insert(input.loc());
        }
        for (var _bk2080 in _v2081) {
            _f2078.insert(_bk2080);
        }
    } else {
        var _v2083 = HashSet<Loc>();
        var _n2084 = input.count();
        for (var _ in 0.._n2084) {
            _v2083.insert(input.loc());
        }
        _f2078 = _v2083;
    }
    var _f2104 = HashSet<Loc>();
    var _tag2105 = input.unsigned();
    if (_tag2105 == 1) {
        for (var _bk2106 in base.file_private_functions) {
            _f2104.insert(_bk2106);
        }
        var _v2107 = HashSet<Loc>();
        var _n2108 = input.count();
        for (var _ in 0.._n2108) {
            _v2107.insert(input.loc());
        }
        for (var _bk2106 in _v2107) {
            _f2104.insert(_bk2106);
        }
    } else {
        var _v2109 = HashSet<Loc>();
        var _n2110 = input.count();
        for (var _ in 0.._n2110) {
            _v2109.insert(input.loc());
        }
        _f2104 = _v2109;
    }
    var _f2122 = Array<(Loc, String)>();
    var _tag2123 = input.unsigned();
    if (_tag2123 == 1) {
        input.unsigned();
        for (var _i2114 in 0..base.call_targets.count) {
            _f2122.append(base.call_targets[_i2114]);
        }
        var _more2125 = input.count();
        for (var _ in 0.._more2125) {
            var _t2126 = input.loc();
            var _t2127 = input.text();
            _f2122.append((_t2126, _t2127));
        }
    } else {
        var _v2128 = Array<(Loc, String)>();
        var _n2129 = input.count();
        for (var _ in 0.._n2129) {
            var _t2130 = input.loc();
            var _t2131 = input.text();
            _v2128.append((_t2130, _t2131));
        }
        _f2122 = _v2128;
    }
    var _f2148 = Array<(Loc, String)>();
    var _tag2149 = input.unsigned();
    if (_tag2149 == 1) {
        var _v2150 = Array<(Loc, String)>();
        var _n2151 = input.count();
        for (var _ in 0.._n2151) {
            var _t2152 = input.loc();
            var _t2153 = input.text();
            _v2150.append((_t2152, _t2153));
        }
        _f2148 = merge_by_place(base.argument_names, _v2150);
    } else {
        var _v2154 = Array<(Loc, String)>();
        var _n2155 = input.count();
        for (var _ in 0.._n2155) {
            var _t2156 = input.loc();
            var _t2157 = input.text();
            _v2154.append((_t2156, _t2157));
        }
        _f2148 = _v2154;
    }
    var _f2167 = Array<String>();
    var _tag2168 = input.unsigned();
    if (_tag2168 == 1) {
        input.unsigned();
        for (var _i2163 in 0..base.namespaces.count) {
            _f2167.append(base.namespaces[_i2163]);
        }
        var _more2170 = input.count();
        for (var _ in 0.._more2170) {
            _f2167.append(input.text());
        }
    } else {
        var _v2171 = Array<String>();
        var _n2172 = input.count();
        for (var _ in 0.._n2172) {
            _v2171.append(input.text());
        }
        _f2167 = _v2171;
    }
    var _f2180 = Array<bool>();
    var _tag2181 = input.unsigned();
    if (_tag2181 == 1) {
        input.unsigned();
        for (var _i2178 in 0..base.cached_files.count) {
            _f2180.append(base.cached_files[_i2178]);
        }
        var _more2183 = input.count();
        for (var _ in 0.._more2183) {
            _f2180.append(input.flag());
        }
    } else {
        var _v2184 = Array<bool>();
        var _n2185 = input.count();
        for (var _ in 0.._n2185) {
            _v2184.append(input.flag());
        }
        _f2180 = _v2184;
    }
    var _f2203 = HashMap<Loc, String>();
    var _tag2204 = input.unsigned();
    if (_tag2204 == 1) {
        for (var (_bk2205, _bv) in base.recorded_summaries) {
            _f2203[_bk2205] = _bv;
        }
        var _v2206 = HashMap<Loc, String>();
        var _n2207 = input.count();
        for (var _ in 0.._n2207) {
            var _k2208 = input.loc();
            _v2206[_k2208] = input.text();
        }
        for (var (_bk2205, _av) in _v2206) {
            _f2203[_bk2205] = _av;
        }
    } else {
        var _v2209 = HashMap<Loc, String>();
        var _n2210 = input.count();
        for (var _ in 0.._n2210) {
            var _k2211 = input.loc();
            _v2209[_k2211] = input.text();
        }
        _f2203 = _v2209;
    }
    var _f2227 = HashSet<Loc>();
    var _tag2228 = input.unsigned();
    if (_tag2228 == 1) {
        for (var _bk2229 in base.stripped) {
            _f2227.insert(_bk2229);
        }
        var _v2230 = HashSet<Loc>();
        var _n2231 = input.count();
        for (var _ in 0.._n2231) {
            _v2230.insert(input.loc());
        }
        for (var _bk2229 in _v2230) {
            _f2227.insert(_bk2229);
        }
    } else {
        var _v2232 = HashSet<Loc>();
        var _n2233 = input.count();
        for (var _ in 0.._n2233) {
            _v2232.insert(input.loc());
        }
        _f2227 = _v2232;
    }
    var _frozen = input.flag();
    var _f2244 = Array<StructDef>();
    var _mode2247 = input.unsigned();
    if (_mode2247 == 2) {
        var _patched2250 = HashMap<ulong, StructDef>();
        var _n2245 = input.count();
        for (var _ in 0.._n2245) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2250[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2248 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2249 = input.unsigned();
            while (_f2244.count < _at2249 or (input.merging and _bi2248 < base.templates.structs.count)) {
                var _p = _patched2250.try_get(_bi2248);
                _f2244.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2248]);
                _bi2248 += 1;
            }
            _f2244.append(_m_StructDef_read(input));
        }
        while (_bi2248 < base.templates.structs.count) {
            var _p = _patched2250.try_get(_bi2248);
            _f2244.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2248]);
            _bi2248 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2245 = input.count();
        for (var _ in 0.._n2245) {
            var _tag2246 = input.unsigned();
            if (_tag2246 & 1 == 1) {
                _f2244.append(
                    base.templates.structs[(_tag2246 >> 1) < base.templates.structs.count ? _tag2246 >> 1 : 0]
                );
            } else if (_tag2246 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2244.append(_patch_t_read(input, _was));
            } else {
                _f2244.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2264 = Array<FunctionDef>();
    var _mode2267 = input.unsigned();
    if (_mode2267 == 2) {
        var _changed2253 = HashMap<ulong, FunctionDef>();
        var _nc2255 = input.count();
        for (var _ in 0.._nc2255) {
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
                _changed2253[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2268 = 0;
        var _n2265 = input.count();
        for (var _ in 0.._n2265) {
            var _at2269 = input.unsigned();
            while (_f2264.count < _at2269 or (input.merging and _bi2268 < base.templates.functions.count)) {
                var _c = _changed2253.try_get(_bi2268);
                _f2264.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2268]);
                _bi2268 += 1;
            }
            _f2264.append(_m_FunctionDef_read(input));
        }
        while (_bi2268 < base.templates.functions.count) {
            var _c = _changed2253.try_get(_bi2268);
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
    var _f2271 = Templates(_frozen, _f2244, _f2264);
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
        _f1499,
        _f1532,
        _f1552,
        _f1571,
        _f1590,
        _f1609,
        _f1628,
        _f1647,
        _f1666,
        _f1685,
        _f1704,
        _f1716,
        _f1732,
        _f1751,
        _f1770,
        _f1789,
        _f1810,
        _f1839,
        _f1858,
        _f1871,
        _f1898,
        _f1945,
        _f2032,
        _f2058,
        _f2078,
        _f2104,
        _f2122,
        _f2148,
        _f2167,
        _f2180,
        _f2203,
        _f2227,
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
    ulong _j1505 = 0;
    for (var _item1487 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1487);
        base.add("imports", scratch, _j1505);
        _j1505 += 1;
    }
    if (base.verifying) {
        ulong _j1539 = 0;
        for (var _item1506 in value.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item1506);
            base.add("s", scratch, _j1539);
            base.name("s", _item1506.name, _j1539);
            _patch_s_index(_item1506, base, _j1539);
            _j1539 += 1;
        }
    }
    base.ref_structs = value.structs.clone();
    base.ref_struct_parts = Array<StructDef>();
    for (var _item1506 in value.structs) {
        base.ref_struct_parts.append(_m_StructDef_shallow(_item1506));
    }
    ulong _j1558 = 0;
    for (var _item1540 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1540);
        base.add("traits", scratch, _j1558);
        _j1558 += 1;
    }
    ulong _j1577 = 0;
    for (var _item1559 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1559);
        base.add("extensions", scratch, _j1577);
        _j1577 += 1;
    }
    if (base.verifying) {
        ulong _j1596 = 0;
        for (var _item1578 in value.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item1578);
            base.add("functions", scratch, _j1596);
            base.name("functions", _item1578.name, _j1596);
            _j1596 += 1;
        }
    }
    base.ref_functions = value.functions.clone();
    ulong _j1615 = 0;
    for (var _item1597 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1597);
        base.add("externs", scratch, _j1615);
        _j1615 += 1;
    }
    ulong _j1634 = 0;
    for (var _item1616 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1616);
        base.add("globals", scratch, _j1634);
        _j1634 += 1;
    }
    ulong _j1653 = 0;
    for (var _item1635 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1635);
        base.add("static_blocks", scratch, _j1653);
        _j1653 += 1;
    }
    ulong _j1672 = 0;
    for (var _item1654 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1654);
        base.add("enums", scratch, _j1672);
        _j1672 += 1;
    }
    ulong _j1691 = 0;
    for (var _item1673 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1673);
        base.add("struct_specs", scratch, _j1691);
        _j1691 += 1;
    }
    ulong _j1710 = 0;
    for (var _item1692 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1692);
        base.add("func_specs", scratch, _j1710);
        _j1710 += 1;
    }
    ulong _j1719 = 0;
    for (var _item1711 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1711);
        base.add("type_aliases", scratch, _j1719);
        _j1719 += 1;
    }
    ulong _j1738 = 0;
    for (var _item1720 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1720);
        base.add("withheld", scratch, _j1738);
        _j1738 += 1;
    }
    ulong _j1757 = 0;
    for (var _item1739 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1739);
        base.add("properties", scratch, _j1757);
        _j1757 += 1;
    }
    ulong _j1776 = 0;
    for (var _item1758 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1758);
        base.add("type_uses", scratch, _j1776);
        _j1776 += 1;
    }
    ulong _j1795 = 0;
    for (var _item1777 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1777);
        base.add("use_contexts", scratch, _j1795);
        _j1795 += 1;
    }
    var _xscratch1822 = base.scratch();
    for (var _xitem1823 in value.literal_args) {
        var (_t1824, _t1825, _t1826) = _xitem1823;
        _xscratch1822.loc(_t1824);
        _xscratch1822.unsigned(_t1825);
        _xscratch1822.loc(_t1826);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1822);
    ulong _j1845 = 0;
    for (var _item1827 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1827);
        base.add("constrained_aliases", scratch, _j1845);
        _j1845 += 1;
    }
    ulong _j1864 = 0;
    for (var _item1846 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1846);
        base.add("trait_types", scratch, _j1864);
        _j1864 += 1;
    }
    ulong _cj1868 = 0;
    for (var _conv1866 in value.conversions) {
        var _own1867 = RecordOut();
        _own1867.blank_locs = true;
        _m_Conversion_write(_own1867, _conv1866);
        base.add_hashed("conversions", interface_text(_own1867), _cj1868);
        _cj1868 += 1;
    }
    for (var (_key1872, _) in value.overload_sets) {
        var _kscratch1873 = base.scratch();
        _kscratch1873.text(_key1872);
        var _vscratch1874 = base.scratch();
        _vscratch1874.unsigned(value.overload_sets[_key1872].count);
        for (var _item1911 in value.overload_sets[_key1872]) {
            _vscratch1874.text(_item1911);
        }
        base.keep_entry("overload_sets", _kscratch1873, _vscratch1874);
    }
    for (var (_key1912, _) in value.overload_unions) {
        var _kscratch1913 = base.scratch();
        _kscratch1913.text(_key1912);
        var _vscratch1914 = base.scratch();
        _vscratch1914.unsigned(value.overload_unions[_key1912].count);
        for (var _item1962 in value.overload_unions[_key1912]) {
            _vscratch1914.unsigned(_item1962.count);
            for (var _item1963 in _item1962) {
                _vscratch1914.text(_item1963);
            }
        }
        base.keep_entry("overload_unions", _kscratch1913, _vscratch1914);
    }
    for (var (_key1964, _) in value.method_overload_sets) {
        var _kscratch1965 = base.scratch();
        _kscratch1965.text(_key1964);
        var _vscratch1966 = base.scratch();
        var _keys2052 = Array<(u8[], u8[], String)>();
        for (var (_key2051, _) in value.method_overload_sets[_key1964]) {
            var _scratch2053 = _vscratch1966.scratch();
            _scratch2053.text(_key2051);
            var _vscratch2055 = _vscratch1966.scratch();
            _vscratch2055.unsigned(value.method_overload_sets[_key1964][_key2051].count);
            for (var _item2056 in value.method_overload_sets[_key1964][_key2051]) {
                _vscratch2055.text(_item2056);
            }
            _keys2052.append((_scratch2053.finish(), _vscratch2055.finish(), _key2051));
        }
        _keys2052.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1966.unsigned(_keys2052.count);
        for (var (_bytes2054, _, _key2051) in _keys2052) {
            _vscratch1966.text(_key2051);
            _vscratch1966.unsigned(value.method_overload_sets[_key1964][_key2051].count);
            for (var _item2057 in value.method_overload_sets[_key1964][_key2051]) {
                _vscratch1966.text(_item2057);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1965, _vscratch1966);
    }
    for (var _key2059 in value.private_functions) {
        var _kscratch2060 = base.scratch();
        _kscratch2060.loc(_key2059);
        var _vscratch2061 = base.scratch();
        base.keep_entry("private_functions", _kscratch2060, _vscratch2061);
    }
    for (var _key2085 in value.file_private_functions) {
        var _kscratch2086 = base.scratch();
        _kscratch2086.loc(_key2085);
        var _vscratch2087 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch2086, _vscratch2087);
    }
    var _xscratch2132 = base.scratch();
    for (var _xitem2133 in value.call_targets) {
        var (_t2134, _t2135) = _xitem2133;
        _xscratch2132.loc(_t2134);
        _xscratch2132.text(_t2135);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2132);
    for (var _item2136 in value.argument_names) {
        var _escratch2137 = base.scratch();
        var (_t2158, _t2159) = _item2136;
        _escratch2137.loc(_t2158);
        _escratch2137.text(_t2159);
        base.keep_entry("argument_names", _escratch2137, base.scratch());
    }
    var _xscratch2173 = base.scratch();
    for (var _xitem2174 in value.namespaces) {
        _xscratch2173.text(_xitem2174);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2173);
    var _xscratch2186 = base.scratch();
    for (var _xitem2187 in value.cached_files) {
        _xscratch2186.flag(_xitem2187);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2186);
    for (var (_key2188, _) in value.recorded_summaries) {
        var _kscratch2189 = base.scratch();
        _kscratch2189.loc(_key2188);
        var _vscratch2190 = base.scratch();
        _vscratch2190.text(value.recorded_summaries[_key2188]);
        base.keep_entry("recorded_summaries", _kscratch2189, _vscratch2190);
    }
    for (var _key2212 in value.stripped) {
        var _kscratch2213 = base.scratch();
        _kscratch2213.loc(_key2212);
        var _vscratch2214 = base.scratch();
        base.keep_entry("stripped", _kscratch2213, _vscratch2214);
    }
    if (base.verifying) {
        ulong _j2251 = 0;
        for (var _item2234 in value.templates.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item2234);
            base.add("t", scratch, _j2251);
            base.name("t", _item2234.name, _j2251);
            _patch_t_index(_item2234, base, _j2251);
            _j2251 += 1;
        }
    }
    base.ref_templates = value.templates.structs.clone();
    base.ref_template_parts = Array<StructDef>();
    for (var _item2234 in value.templates.structs) {
        base.ref_template_parts.append(_m_StructDef_shallow(_item2234));
    }
    if (base.verifying) {
        ulong _j2270 = 0;
        for (var _item2252 in value.templates.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2252);
            base.add("tf", scratch, _j2270);
            base.name("tf", _item2252.name, _j2270);
            _j2270 += 1;
        }
    }
    base.ref_template_functions = value.templates.functions.clone();
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
    ulong _j1719 = 0;
    for (var _item1711 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1711);
        base.add("type_aliases", scratch, _j1719);
        _j1719 += 1;
    }
    for (var (_key2188, _) in value.recorded_summaries) {
        var _kscratch2189 = base.scratch();
        _kscratch2189.loc(_key2188);
        var _vscratch2190 = base.scratch();
        _vscratch2190.text(value.recorded_summaries[_key2188]);
        base.keep_entry("recorded_summaries", _kscratch2189, _vscratch2190);
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
    var _seq2375 = base.ref_struct_parts[slot].generic_params;
    ulong _bj2376 = 0;
    var _news2377 = Array<ulong>();
    for (var _i2378 in 0..value.generic_params.count) {
        if (_bj2376 < _seq2375.count and value.generic_params[_i2378] === _seq2375[_bj2376]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2378]);
                base.verify_same($"s.{slot}.generic_params", _bj2376, scratch);
            }
            _bj2376 += 1;
        } else if (_bj2376 < _seq2375.count
            and _same_m_GenericParam(value.generic_params[_i2378], _seq2375[_bj2376], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2378]);
                base.verify_same($"s.{slot}.generic_params", _bj2376, scratch);
            }
            _bj2376 += 1;
        } else {
            _news2377.append(_i2378);
        }
    }
    if (_bj2376 == _seq2375.count) {
        out.unsigned(2);
        out.unsigned(_news2377.count);
        for (var _i2378 in _news2377) {
            out.unsigned(_i2378);
            _m_GenericParam_write(out, value.generic_params[_i2378]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2378 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2378]);
        }
    }
    var _seq2391 = base.ref_struct_parts[slot].field_members;
    ulong _bj2392 = 0;
    var _news2393 = Array<ulong>();
    for (var _i2394 in 0..value.field_members.count) {
        if (_bj2392 < _seq2391.count and value.field_members[_i2394] === _seq2391[_bj2392]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2394]);
                base.verify_same($"s.{slot}.field_members", _bj2392, scratch);
            }
            _bj2392 += 1;
        } else if (_bj2392 < _seq2391.count
            and _same_m_VariableDef(value.field_members[_i2394], _seq2391[_bj2392], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2394]);
                base.verify_same($"s.{slot}.field_members", _bj2392, scratch);
            }
            _bj2392 += 1;
        } else {
            _news2393.append(_i2394);
        }
    }
    if (_bj2392 == _seq2391.count) {
        out.unsigned(2);
        out.unsigned(_news2393.count);
        for (var _i2394 in _news2393) {
            out.unsigned(_i2394);
            _m_VariableDef_write(out, value.field_members[_i2394]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2394 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2394]);
        }
    }
    var _seq2407 = base.ref_struct_parts[slot].method_members;
    ulong _bj2408 = 0;
    var _news2409 = Array<ulong>();
    for (var _i2410 in 0..value.method_members.count) {
        if (_bj2408 < _seq2407.count and value.method_members[_i2410] === _seq2407[_bj2408]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2410]);
                base.verify_same($"s.{slot}.method_members", _bj2408, scratch);
            }
            _bj2408 += 1;
        } else if (_bj2408 < _seq2407.count
            and _same_m_FunctionDef(value.method_members[_i2410], _seq2407[_bj2408], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2410]);
                base.verify_same($"s.{slot}.method_members", _bj2408, scratch);
            }
            _bj2408 += 1;
        } else {
            _news2409.append(_i2410);
        }
    }
    if (_bj2408 == _seq2407.count) {
        out.unsigned(2);
        out.unsigned(_news2409.count);
        for (var _i2410 in _news2409) {
            out.unsigned(_i2410);
            _m_FunctionDef_write(out, value.method_members[_i2410]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2410 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2410]);
        }
    }
    var _seq2423 = base.ref_struct_parts[slot].generic_methods;
    ulong _bj2424 = 0;
    var _news2425 = Array<ulong>();
    for (var _i2426 in 0..value.generic_methods.count) {
        if (_bj2424 < _seq2423.count and value.generic_methods[_i2426] === _seq2423[_bj2424]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2426]);
                base.verify_same($"s.{slot}.generic_methods", _bj2424, scratch);
            }
            _bj2424 += 1;
        } else if (_bj2424 < _seq2423.count
            and _same_m_FunctionDef(value.generic_methods[_i2426], _seq2423[_bj2424], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2426]);
                base.verify_same($"s.{slot}.generic_methods", _bj2424, scratch);
            }
            _bj2424 += 1;
        } else {
            _news2425.append(_i2426);
        }
    }
    if (_bj2424 == _seq2423.count) {
        out.unsigned(2);
        out.unsigned(_news2425.count);
        for (var _i2426 in _news2425) {
            out.unsigned(_i2426);
            _m_FunctionDef_write(out, value.generic_methods[_i2426]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2426 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2426]);
        }
    }
    var _seq2439 = base.ref_struct_parts[slot].constructors;
    ulong _bj2440 = 0;
    var _news2441 = Array<ulong>();
    for (var _i2442 in 0..value.constructors.count) {
        if (_bj2440 < _seq2439.count and value.constructors[_i2442] === _seq2439[_bj2440]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2442]);
                base.verify_same($"s.{slot}.constructors", _bj2440, scratch);
            }
            _bj2440 += 1;
        } else if (_bj2440 < _seq2439.count
            and _same_m_FunctionDef(value.constructors[_i2442], _seq2439[_bj2440], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2442]);
                base.verify_same($"s.{slot}.constructors", _bj2440, scratch);
            }
            _bj2440 += 1;
        } else {
            _news2441.append(_i2442);
        }
    }
    if (_bj2440 == _seq2439.count) {
        out.unsigned(2);
        out.unsigned(_news2441.count);
        for (var _i2442 in _news2441) {
            out.unsigned(_i2442);
            _m_FunctionDef_write(out, value.constructors[_i2442]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2442 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2442]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2458 = base.ref_struct_parts[slot].traits;
    ulong _bj2459 = 0;
    var _news2460 = Array<ulong>();
    for (var _i2461 in 0..value.traits.count) {
        if (_bj2459 < _seq2458.count and value.traits[_i2461] === _seq2458[_bj2459]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2461]);
                base.verify_same($"s.{slot}.traits", _bj2459, scratch);
            }
            _bj2459 += 1;
        } else if (_bj2459 < _seq2458.count and _same_m_TypeName(value.traits[_i2461], _seq2458[_bj2459], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2461]);
                base.verify_same($"s.{slot}.traits", _bj2459, scratch);
            }
            _bj2459 += 1;
        } else {
            _news2460.append(_i2461);
        }
    }
    if (_bj2459 == _seq2458.count) {
        out.unsigned(2);
        out.unsigned(_news2460.count);
        for (var _i2461 in _news2460) {
            out.unsigned(_i2461);
            _m_TypeName_write(out, value.traits[_i2461]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2461 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2461]);
        }
    }
    var _seq2474 = base.ref_struct_parts[slot].attributes;
    ulong _bj2475 = 0;
    var _news2476 = Array<ulong>();
    for (var _i2477 in 0..value.attributes.count) {
        if (_bj2475 < _seq2474.count and value.attributes[_i2477] === _seq2474[_bj2475]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2477]);
                base.verify_same($"s.{slot}.attributes", _bj2475, scratch);
            }
            _bj2475 += 1;
        } else if (_bj2475 < _seq2474.count and _same_a_Attribute(value.attributes[_i2477], _seq2474[_bj2475], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2477]);
                base.verify_same($"s.{slot}.attributes", _bj2475, scratch);
            }
            _bj2475 += 1;
        } else {
            _news2476.append(_i2477);
        }
    }
    if (_bj2475 == _seq2474.count) {
        out.unsigned(2);
        out.unsigned(_news2476.count);
        for (var _i2477 in _news2476) {
            out.unsigned(_i2477);
            _a_Attribute_write(out, value.attributes[_i2477]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2477 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2477]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2486 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2486);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2368 = input.text();
    var _f2369 = _m_TypeName_read(input);
    var _f2379 = Array<GenericParam>();
    var _mode2382 = input.unsigned();
    if (_mode2382 == 2) {
        var _changed2371 = HashMap<ulong, GenericParam>();
        ulong _bi2383 = 0;
        var _n2380 = input.count();
        for (var _ in 0.._n2380) {
            var _at2384 = input.unsigned();
            while (_f2379.count < _at2384 or (input.merging and _bi2383 < was.generic_params.count)) {
                var _c = _changed2371.try_get(_bi2383);
                _f2379.append(_c.is_value() ? _c.value() : was.generic_params[_bi2383]);
                _bi2383 += 1;
            }
            _f2379.append(_m_GenericParam_read(input));
        }
        while (_bi2383 < was.generic_params.count) {
            var _c = _changed2371.try_get(_bi2383);
            _f2379.append(_c.is_value() ? _c.value() : was.generic_params[_bi2383]);
            _bi2383 += 1;
        }
    } else if (_mode2382 == 3) {
        var _n2380 = input.count();
        for (var _ in 0.._n2380) {
            _f2379.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2380 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2380) {
            var _tag2381 = input.unsigned();
            if (_tag2381 & 1 == 1) {
                if (!input.merging) {
                    _f2379.append(was.generic_params[_tag2381 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2379.append(_read);
                }
            }
        }
    }
    var _f2395 = Array<VariableDef>();
    var _mode2398 = input.unsigned();
    if (_mode2398 == 2) {
        var _changed2387 = HashMap<ulong, VariableDef>();
        ulong _bi2399 = 0;
        var _n2396 = input.count();
        for (var _ in 0.._n2396) {
            var _at2400 = input.unsigned();
            while (_f2395.count < _at2400 or (input.merging and _bi2399 < was.field_members.count)) {
                var _c = _changed2387.try_get(_bi2399);
                _f2395.append(_c.is_value() ? _c.value() : was.field_members[_bi2399]);
                _bi2399 += 1;
            }
            _f2395.append(_m_VariableDef_read(input));
        }
        while (_bi2399 < was.field_members.count) {
            var _c = _changed2387.try_get(_bi2399);
            _f2395.append(_c.is_value() ? _c.value() : was.field_members[_bi2399]);
            _bi2399 += 1;
        }
    } else if (_mode2398 == 3) {
        var _n2396 = input.count();
        for (var _ in 0.._n2396) {
            _f2395.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2396 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2396) {
            var _tag2397 = input.unsigned();
            if (_tag2397 & 1 == 1) {
                if (!input.merging) {
                    _f2395.append(was.field_members[_tag2397 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2395.append(_read);
                }
            }
        }
    }
    var _f2411 = Array<FunctionDef>();
    var _mode2414 = input.unsigned();
    if (_mode2414 == 2) {
        var _changed2403 = HashMap<ulong, FunctionDef>();
        ulong _bi2415 = 0;
        var _n2412 = input.count();
        for (var _ in 0.._n2412) {
            var _at2416 = input.unsigned();
            while (_f2411.count < _at2416 or (input.merging and _bi2415 < was.method_members.count)) {
                var _c = _changed2403.try_get(_bi2415);
                _f2411.append(_c.is_value() ? _c.value() : was.method_members[_bi2415]);
                _bi2415 += 1;
            }
            _f2411.append(_m_FunctionDef_read(input));
        }
        while (_bi2415 < was.method_members.count) {
            var _c = _changed2403.try_get(_bi2415);
            _f2411.append(_c.is_value() ? _c.value() : was.method_members[_bi2415]);
            _bi2415 += 1;
        }
    } else if (_mode2414 == 3) {
        var _n2412 = input.count();
        for (var _ in 0.._n2412) {
            _f2411.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2412 = input.count();
        if (input.merging) {
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2412) {
            var _tag2413 = input.unsigned();
            if (_tag2413 & 1 == 1) {
                if (!input.merging) {
                    _f2411.append(was.method_members[_tag2413 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2411.append(_read);
                }
            }
        }
    }
    var _f2427 = Array<FunctionDef>();
    var _mode2430 = input.unsigned();
    if (_mode2430 == 2) {
        var _changed2419 = HashMap<ulong, FunctionDef>();
        ulong _bi2431 = 0;
        var _n2428 = input.count();
        for (var _ in 0.._n2428) {
            var _at2432 = input.unsigned();
            while (_f2427.count < _at2432 or (input.merging and _bi2431 < was.generic_methods.count)) {
                var _c = _changed2419.try_get(_bi2431);
                _f2427.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2431]);
                _bi2431 += 1;
            }
            _f2427.append(_m_FunctionDef_read(input));
        }
        while (_bi2431 < was.generic_methods.count) {
            var _c = _changed2419.try_get(_bi2431);
            _f2427.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2431]);
            _bi2431 += 1;
        }
    } else if (_mode2430 == 3) {
        var _n2428 = input.count();
        for (var _ in 0.._n2428) {
            _f2427.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2428 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2428) {
            var _tag2429 = input.unsigned();
            if (_tag2429 & 1 == 1) {
                if (!input.merging) {
                    _f2427.append(was.generic_methods[_tag2429 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2427.append(_read);
                }
            }
        }
    }
    var _f2443 = Array<FunctionDef>();
    var _mode2446 = input.unsigned();
    if (_mode2446 == 2) {
        var _changed2435 = HashMap<ulong, FunctionDef>();
        ulong _bi2447 = 0;
        var _n2444 = input.count();
        for (var _ in 0.._n2444) {
            var _at2448 = input.unsigned();
            while (_f2443.count < _at2448 or (input.merging and _bi2447 < was.constructors.count)) {
                var _c = _changed2435.try_get(_bi2447);
                _f2443.append(_c.is_value() ? _c.value() : was.constructors[_bi2447]);
                _bi2447 += 1;
            }
            _f2443.append(_m_FunctionDef_read(input));
        }
        while (_bi2447 < was.constructors.count) {
            var _c = _changed2435.try_get(_bi2447);
            _f2443.append(_c.is_value() ? _c.value() : was.constructors[_bi2447]);
            _bi2447 += 1;
        }
    } else if (_mode2446 == 3) {
        var _n2444 = input.count();
        for (var _ in 0.._n2444) {
            _f2443.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2444 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2444) {
            var _tag2445 = input.unsigned();
            if (_tag2445 & 1 == 1) {
                if (!input.merging) {
                    _f2443.append(was.constructors[_tag2445 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2443.append(_read);
                }
            }
        }
    }
    var _f2450 = _m_FunctionDef_read(input);
    var _f2451 = _m_FunctionDef_read(input);
    var _f2452 = _m_FunctionDef_read(input);
    var _f2462 = Array<TypeName>();
    var _mode2465 = input.unsigned();
    if (_mode2465 == 2) {
        var _changed2454 = HashMap<ulong, TypeName>();
        ulong _bi2466 = 0;
        var _n2463 = input.count();
        for (var _ in 0.._n2463) {
            var _at2467 = input.unsigned();
            while (_f2462.count < _at2467 or (input.merging and _bi2466 < was.traits.count)) {
                var _c = _changed2454.try_get(_bi2466);
                _f2462.append(_c.is_value() ? _c.value() : was.traits[_bi2466]);
                _bi2466 += 1;
            }
            _f2462.append(_m_TypeName_read(input));
        }
        while (_bi2466 < was.traits.count) {
            var _c = _changed2454.try_get(_bi2466);
            _f2462.append(_c.is_value() ? _c.value() : was.traits[_bi2466]);
            _bi2466 += 1;
        }
    } else if (_mode2465 == 3) {
        var _n2463 = input.count();
        for (var _ in 0.._n2463) {
            _f2462.append(_m_TypeName_read(input));
        }
    } else {
        var _n2463 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2463) {
            var _tag2464 = input.unsigned();
            if (_tag2464 & 1 == 1) {
                if (!input.merging) {
                    _f2462.append(was.traits[_tag2464 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2462.append(_read);
                }
            }
        }
    }
    var _f2478 = Array<ast.Attribute>();
    var _mode2481 = input.unsigned();
    if (_mode2481 == 2) {
        var _changed2470 = HashMap<ulong, ast.Attribute>();
        ulong _bi2482 = 0;
        var _n2479 = input.count();
        for (var _ in 0.._n2479) {
            var _at2483 = input.unsigned();
            while (_f2478.count < _at2483 or (input.merging and _bi2482 < was.attributes.count)) {
                var _c = _changed2470.try_get(_bi2482);
                _f2478.append(_c.is_value() ? _c.value() : was.attributes[_bi2482]);
                _bi2482 += 1;
            }
            _f2478.append(_a_Attribute_read(input));
        }
        while (_bi2482 < was.attributes.count) {
            var _c = _changed2470.try_get(_bi2482);
            _f2478.append(_c.is_value() ? _c.value() : was.attributes[_bi2482]);
            _bi2482 += 1;
        }
    } else if (_mode2481 == 3) {
        var _n2479 = input.count();
        for (var _ in 0.._n2479) {
            _f2478.append(_a_Attribute_read(input));
        }
    } else {
        var _n2479 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2479) {
            var _tag2480 = input.unsigned();
            if (_tag2480 & 1 == 1) {
                if (!input.merging) {
                    _f2478.append(was.attributes[_tag2480 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2478.append(_read);
                }
            }
        }
    }
    var _f2485 = input.loc();
    var _o2487 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2488 = Array<EnumCaseDef>();
        var _n2489 = input.count();
        for (var _ in 0.._n2489) {
            _v2488.append(_m_EnumCaseDef_read(input));
        }
        _o2487 = Optional<Array<EnumCaseDef>>.Value(_v2488);
    }
    var _f2490 = _o2487;
    return StructDef(
        _f2368, _f2369, _f2379, _f2395, _f2411, _f2427, _f2443, _f2450, _f2451, _f2452, _f2462, _f2478, _f2485, _f2490
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2385 = 0;
        for (var _item2370 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2370);
            base.add($"s.{slot}.generic_params", scratch, _j2385);
            _j2385 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2401 = 0;
        for (var _item2386 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2386);
            base.add($"s.{slot}.field_members", scratch, _j2401);
            _j2401 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2417 = 0;
        for (var _item2402 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2402);
            base.add($"s.{slot}.method_members", scratch, _j2417);
            _j2417 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2433 = 0;
        for (var _item2418 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2418);
            base.add($"s.{slot}.generic_methods", scratch, _j2433);
            _j2433 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2449 = 0;
        for (var _item2434 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2434);
            base.add($"s.{slot}.constructors", scratch, _j2449);
            _j2449 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2468 = 0;
        for (var _item2453 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2453);
            base.add($"s.{slot}.traits", scratch, _j2468);
            _j2468 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2484 = 0;
        for (var _item2469 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2469);
            base.add($"s.{slot}.attributes", scratch, _j2484);
            _j2484 += 1;
        }
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2498 = base.ref_template_parts[slot].generic_params;
    ulong _bj2499 = 0;
    var _news2500 = Array<ulong>();
    for (var _i2501 in 0..value.generic_params.count) {
        if (_bj2499 < _seq2498.count and value.generic_params[_i2501] === _seq2498[_bj2499]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2501]);
                base.verify_same($"t.{slot}.generic_params", _bj2499, scratch);
            }
            _bj2499 += 1;
        } else if (_bj2499 < _seq2498.count
            and _same_m_GenericParam(value.generic_params[_i2501], _seq2498[_bj2499], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2501]);
                base.verify_same($"t.{slot}.generic_params", _bj2499, scratch);
            }
            _bj2499 += 1;
        } else {
            _news2500.append(_i2501);
        }
    }
    if (_bj2499 == _seq2498.count) {
        out.unsigned(2);
        out.unsigned(_news2500.count);
        for (var _i2501 in _news2500) {
            out.unsigned(_i2501);
            _m_GenericParam_write(out, value.generic_params[_i2501]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2501 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2501]);
        }
    }
    var _seq2514 = base.ref_template_parts[slot].field_members;
    ulong _bj2515 = 0;
    var _news2516 = Array<ulong>();
    for (var _i2517 in 0..value.field_members.count) {
        if (_bj2515 < _seq2514.count and value.field_members[_i2517] === _seq2514[_bj2515]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2517]);
                base.verify_same($"t.{slot}.field_members", _bj2515, scratch);
            }
            _bj2515 += 1;
        } else if (_bj2515 < _seq2514.count
            and _same_m_VariableDef(value.field_members[_i2517], _seq2514[_bj2515], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2517]);
                base.verify_same($"t.{slot}.field_members", _bj2515, scratch);
            }
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
            _m_VariableDef_write(out, value.field_members[_i2517]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2517 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2517]);
        }
    }
    var _seq2530 = base.ref_template_parts[slot].method_members;
    ulong _bj2531 = 0;
    var _news2532 = Array<ulong>();
    for (var _i2533 in 0..value.method_members.count) {
        if (_bj2531 < _seq2530.count and value.method_members[_i2533] === _seq2530[_bj2531]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2533]);
                base.verify_same($"t.{slot}.method_members", _bj2531, scratch);
            }
            _bj2531 += 1;
        } else if (_bj2531 < _seq2530.count
            and _same_m_FunctionDef(value.method_members[_i2533], _seq2530[_bj2531], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2533]);
                base.verify_same($"t.{slot}.method_members", _bj2531, scratch);
            }
            _bj2531 += 1;
        } else {
            _news2532.append(_i2533);
        }
    }
    if (_bj2531 == _seq2530.count) {
        out.unsigned(2);
        out.unsigned(_news2532.count);
        for (var _i2533 in _news2532) {
            out.unsigned(_i2533);
            _m_FunctionDef_write(out, value.method_members[_i2533]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2533 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2533]);
        }
    }
    var _seq2546 = base.ref_template_parts[slot].generic_methods;
    ulong _bj2547 = 0;
    var _news2548 = Array<ulong>();
    for (var _i2549 in 0..value.generic_methods.count) {
        if (_bj2547 < _seq2546.count and value.generic_methods[_i2549] === _seq2546[_bj2547]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2549]);
                base.verify_same($"t.{slot}.generic_methods", _bj2547, scratch);
            }
            _bj2547 += 1;
        } else if (_bj2547 < _seq2546.count
            and _same_m_FunctionDef(value.generic_methods[_i2549], _seq2546[_bj2547], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2549]);
                base.verify_same($"t.{slot}.generic_methods", _bj2547, scratch);
            }
            _bj2547 += 1;
        } else {
            _news2548.append(_i2549);
        }
    }
    if (_bj2547 == _seq2546.count) {
        out.unsigned(2);
        out.unsigned(_news2548.count);
        for (var _i2549 in _news2548) {
            out.unsigned(_i2549);
            _m_FunctionDef_write(out, value.generic_methods[_i2549]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2549 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2549]);
        }
    }
    var _seq2562 = base.ref_template_parts[slot].constructors;
    ulong _bj2563 = 0;
    var _news2564 = Array<ulong>();
    for (var _i2565 in 0..value.constructors.count) {
        if (_bj2563 < _seq2562.count and value.constructors[_i2565] === _seq2562[_bj2563]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2565]);
                base.verify_same($"t.{slot}.constructors", _bj2563, scratch);
            }
            _bj2563 += 1;
        } else if (_bj2563 < _seq2562.count
            and _same_m_FunctionDef(value.constructors[_i2565], _seq2562[_bj2563], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2565]);
                base.verify_same($"t.{slot}.constructors", _bj2563, scratch);
            }
            _bj2563 += 1;
        } else {
            _news2564.append(_i2565);
        }
    }
    if (_bj2563 == _seq2562.count) {
        out.unsigned(2);
        out.unsigned(_news2564.count);
        for (var _i2565 in _news2564) {
            out.unsigned(_i2565);
            _m_FunctionDef_write(out, value.constructors[_i2565]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2565 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2565]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2581 = base.ref_template_parts[slot].traits;
    ulong _bj2582 = 0;
    var _news2583 = Array<ulong>();
    for (var _i2584 in 0..value.traits.count) {
        if (_bj2582 < _seq2581.count and value.traits[_i2584] === _seq2581[_bj2582]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2584]);
                base.verify_same($"t.{slot}.traits", _bj2582, scratch);
            }
            _bj2582 += 1;
        } else if (_bj2582 < _seq2581.count and _same_m_TypeName(value.traits[_i2584], _seq2581[_bj2582], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2584]);
                base.verify_same($"t.{slot}.traits", _bj2582, scratch);
            }
            _bj2582 += 1;
        } else {
            _news2583.append(_i2584);
        }
    }
    if (_bj2582 == _seq2581.count) {
        out.unsigned(2);
        out.unsigned(_news2583.count);
        for (var _i2584 in _news2583) {
            out.unsigned(_i2584);
            _m_TypeName_write(out, value.traits[_i2584]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2584 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2584]);
        }
    }
    var _seq2597 = base.ref_template_parts[slot].attributes;
    ulong _bj2598 = 0;
    var _news2599 = Array<ulong>();
    for (var _i2600 in 0..value.attributes.count) {
        if (_bj2598 < _seq2597.count and value.attributes[_i2600] === _seq2597[_bj2598]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2600]);
                base.verify_same($"t.{slot}.attributes", _bj2598, scratch);
            }
            _bj2598 += 1;
        } else if (_bj2598 < _seq2597.count and _same_a_Attribute(value.attributes[_i2600], _seq2597[_bj2598], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2600]);
                base.verify_same($"t.{slot}.attributes", _bj2598, scratch);
            }
            _bj2598 += 1;
        } else {
            _news2599.append(_i2600);
        }
    }
    if (_bj2598 == _seq2597.count) {
        out.unsigned(2);
        out.unsigned(_news2599.count);
        for (var _i2600 in _news2599) {
            out.unsigned(_i2600);
            _a_Attribute_write(out, value.attributes[_i2600]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2600 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2600]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2609 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2609);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2491 = input.text();
    var _f2492 = _m_TypeName_read(input);
    var _f2502 = Array<GenericParam>();
    var _mode2505 = input.unsigned();
    if (_mode2505 == 2) {
        var _changed2494 = HashMap<ulong, GenericParam>();
        ulong _bi2506 = 0;
        var _n2503 = input.count();
        for (var _ in 0.._n2503) {
            var _at2507 = input.unsigned();
            while (_f2502.count < _at2507 or (input.merging and _bi2506 < was.generic_params.count)) {
                var _c = _changed2494.try_get(_bi2506);
                _f2502.append(_c.is_value() ? _c.value() : was.generic_params[_bi2506]);
                _bi2506 += 1;
            }
            _f2502.append(_m_GenericParam_read(input));
        }
        while (_bi2506 < was.generic_params.count) {
            var _c = _changed2494.try_get(_bi2506);
            _f2502.append(_c.is_value() ? _c.value() : was.generic_params[_bi2506]);
            _bi2506 += 1;
        }
    } else if (_mode2505 == 3) {
        var _n2503 = input.count();
        for (var _ in 0.._n2503) {
            _f2502.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2503 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2503) {
            var _tag2504 = input.unsigned();
            if (_tag2504 & 1 == 1) {
                if (!input.merging) {
                    _f2502.append(was.generic_params[_tag2504 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2502.append(_read);
                }
            }
        }
    }
    var _f2518 = Array<VariableDef>();
    var _mode2521 = input.unsigned();
    if (_mode2521 == 2) {
        var _changed2510 = HashMap<ulong, VariableDef>();
        ulong _bi2522 = 0;
        var _n2519 = input.count();
        for (var _ in 0.._n2519) {
            var _at2523 = input.unsigned();
            while (_f2518.count < _at2523 or (input.merging and _bi2522 < was.field_members.count)) {
                var _c = _changed2510.try_get(_bi2522);
                _f2518.append(_c.is_value() ? _c.value() : was.field_members[_bi2522]);
                _bi2522 += 1;
            }
            _f2518.append(_m_VariableDef_read(input));
        }
        while (_bi2522 < was.field_members.count) {
            var _c = _changed2510.try_get(_bi2522);
            _f2518.append(_c.is_value() ? _c.value() : was.field_members[_bi2522]);
            _bi2522 += 1;
        }
    } else if (_mode2521 == 3) {
        var _n2519 = input.count();
        for (var _ in 0.._n2519) {
            _f2518.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2519 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2519) {
            var _tag2520 = input.unsigned();
            if (_tag2520 & 1 == 1) {
                if (!input.merging) {
                    _f2518.append(was.field_members[_tag2520 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2518.append(_read);
                }
            }
        }
    }
    var _f2534 = Array<FunctionDef>();
    var _mode2537 = input.unsigned();
    if (_mode2537 == 2) {
        var _changed2526 = HashMap<ulong, FunctionDef>();
        ulong _bi2538 = 0;
        var _n2535 = input.count();
        for (var _ in 0.._n2535) {
            var _at2539 = input.unsigned();
            while (_f2534.count < _at2539 or (input.merging and _bi2538 < was.method_members.count)) {
                var _c = _changed2526.try_get(_bi2538);
                _f2534.append(_c.is_value() ? _c.value() : was.method_members[_bi2538]);
                _bi2538 += 1;
            }
            _f2534.append(_m_FunctionDef_read(input));
        }
        while (_bi2538 < was.method_members.count) {
            var _c = _changed2526.try_get(_bi2538);
            _f2534.append(_c.is_value() ? _c.value() : was.method_members[_bi2538]);
            _bi2538 += 1;
        }
    } else if (_mode2537 == 3) {
        var _n2535 = input.count();
        for (var _ in 0.._n2535) {
            _f2534.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2535 = input.count();
        if (input.merging) {
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2535) {
            var _tag2536 = input.unsigned();
            if (_tag2536 & 1 == 1) {
                if (!input.merging) {
                    _f2534.append(was.method_members[_tag2536 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2534.append(_read);
                }
            }
        }
    }
    var _f2550 = Array<FunctionDef>();
    var _mode2553 = input.unsigned();
    if (_mode2553 == 2) {
        var _changed2542 = HashMap<ulong, FunctionDef>();
        ulong _bi2554 = 0;
        var _n2551 = input.count();
        for (var _ in 0.._n2551) {
            var _at2555 = input.unsigned();
            while (_f2550.count < _at2555 or (input.merging and _bi2554 < was.generic_methods.count)) {
                var _c = _changed2542.try_get(_bi2554);
                _f2550.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2554]);
                _bi2554 += 1;
            }
            _f2550.append(_m_FunctionDef_read(input));
        }
        while (_bi2554 < was.generic_methods.count) {
            var _c = _changed2542.try_get(_bi2554);
            _f2550.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2554]);
            _bi2554 += 1;
        }
    } else if (_mode2553 == 3) {
        var _n2551 = input.count();
        for (var _ in 0.._n2551) {
            _f2550.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2551 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2551) {
            var _tag2552 = input.unsigned();
            if (_tag2552 & 1 == 1) {
                if (!input.merging) {
                    _f2550.append(was.generic_methods[_tag2552 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2550.append(_read);
                }
            }
        }
    }
    var _f2566 = Array<FunctionDef>();
    var _mode2569 = input.unsigned();
    if (_mode2569 == 2) {
        var _changed2558 = HashMap<ulong, FunctionDef>();
        ulong _bi2570 = 0;
        var _n2567 = input.count();
        for (var _ in 0.._n2567) {
            var _at2571 = input.unsigned();
            while (_f2566.count < _at2571 or (input.merging and _bi2570 < was.constructors.count)) {
                var _c = _changed2558.try_get(_bi2570);
                _f2566.append(_c.is_value() ? _c.value() : was.constructors[_bi2570]);
                _bi2570 += 1;
            }
            _f2566.append(_m_FunctionDef_read(input));
        }
        while (_bi2570 < was.constructors.count) {
            var _c = _changed2558.try_get(_bi2570);
            _f2566.append(_c.is_value() ? _c.value() : was.constructors[_bi2570]);
            _bi2570 += 1;
        }
    } else if (_mode2569 == 3) {
        var _n2567 = input.count();
        for (var _ in 0.._n2567) {
            _f2566.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2567 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2567) {
            var _tag2568 = input.unsigned();
            if (_tag2568 & 1 == 1) {
                if (!input.merging) {
                    _f2566.append(was.constructors[_tag2568 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2566.append(_read);
                }
            }
        }
    }
    var _f2573 = _m_FunctionDef_read(input);
    var _f2574 = _m_FunctionDef_read(input);
    var _f2575 = _m_FunctionDef_read(input);
    var _f2585 = Array<TypeName>();
    var _mode2588 = input.unsigned();
    if (_mode2588 == 2) {
        var _changed2577 = HashMap<ulong, TypeName>();
        ulong _bi2589 = 0;
        var _n2586 = input.count();
        for (var _ in 0.._n2586) {
            var _at2590 = input.unsigned();
            while (_f2585.count < _at2590 or (input.merging and _bi2589 < was.traits.count)) {
                var _c = _changed2577.try_get(_bi2589);
                _f2585.append(_c.is_value() ? _c.value() : was.traits[_bi2589]);
                _bi2589 += 1;
            }
            _f2585.append(_m_TypeName_read(input));
        }
        while (_bi2589 < was.traits.count) {
            var _c = _changed2577.try_get(_bi2589);
            _f2585.append(_c.is_value() ? _c.value() : was.traits[_bi2589]);
            _bi2589 += 1;
        }
    } else if (_mode2588 == 3) {
        var _n2586 = input.count();
        for (var _ in 0.._n2586) {
            _f2585.append(_m_TypeName_read(input));
        }
    } else {
        var _n2586 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2586) {
            var _tag2587 = input.unsigned();
            if (_tag2587 & 1 == 1) {
                if (!input.merging) {
                    _f2585.append(was.traits[_tag2587 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2585.append(_read);
                }
            }
        }
    }
    var _f2601 = Array<ast.Attribute>();
    var _mode2604 = input.unsigned();
    if (_mode2604 == 2) {
        var _changed2593 = HashMap<ulong, ast.Attribute>();
        ulong _bi2605 = 0;
        var _n2602 = input.count();
        for (var _ in 0.._n2602) {
            var _at2606 = input.unsigned();
            while (_f2601.count < _at2606 or (input.merging and _bi2605 < was.attributes.count)) {
                var _c = _changed2593.try_get(_bi2605);
                _f2601.append(_c.is_value() ? _c.value() : was.attributes[_bi2605]);
                _bi2605 += 1;
            }
            _f2601.append(_a_Attribute_read(input));
        }
        while (_bi2605 < was.attributes.count) {
            var _c = _changed2593.try_get(_bi2605);
            _f2601.append(_c.is_value() ? _c.value() : was.attributes[_bi2605]);
            _bi2605 += 1;
        }
    } else if (_mode2604 == 3) {
        var _n2602 = input.count();
        for (var _ in 0.._n2602) {
            _f2601.append(_a_Attribute_read(input));
        }
    } else {
        var _n2602 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2602) {
            var _tag2603 = input.unsigned();
            if (_tag2603 & 1 == 1) {
                if (!input.merging) {
                    _f2601.append(was.attributes[_tag2603 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2601.append(_read);
                }
            }
        }
    }
    var _f2608 = input.loc();
    var _o2610 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2611 = Array<EnumCaseDef>();
        var _n2612 = input.count();
        for (var _ in 0.._n2612) {
            _v2611.append(_m_EnumCaseDef_read(input));
        }
        _o2610 = Optional<Array<EnumCaseDef>>.Value(_v2611);
    }
    var _f2613 = _o2610;
    return StructDef(
        _f2491, _f2492, _f2502, _f2518, _f2534, _f2550, _f2566, _f2573, _f2574, _f2575, _f2585, _f2601, _f2608, _f2613
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2508 = 0;
        for (var _item2493 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2493);
            base.add($"t.{slot}.generic_params", scratch, _j2508);
            _j2508 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2524 = 0;
        for (var _item2509 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2509);
            base.add($"t.{slot}.field_members", scratch, _j2524);
            _j2524 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2540 = 0;
        for (var _item2525 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2525);
            base.add($"t.{slot}.method_members", scratch, _j2540);
            _j2540 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2556 = 0;
        for (var _item2541 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2541);
            base.add($"t.{slot}.generic_methods", scratch, _j2556);
            _j2556 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2572 = 0;
        for (var _item2557 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2557);
            base.add($"t.{slot}.constructors", scratch, _j2572);
            _j2572 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2591 = 0;
        for (var _item2576 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2576);
            base.add($"t.{slot}.traits", scratch, _j2591);
            _j2591 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2607 = 0;
        for (var _item2592 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2592);
            base.add($"t.{slot}.attributes", scratch, _j2607);
            _j2607 += 1;
        }
    }
}

_m_StructDef_shallow(value: StructDef): StructDef {
    return StructDef(
        value.name,
        value.ty,
        value.generic_params.clone(),
        value.field_members.clone(),
        value.method_members.clone(),
        value.generic_methods.clone(),
        value.constructors.clone(),
        value.destructor,
        value.acquire,
        value.release,
        value.traits.clone(),
        value.attributes.clone(),
        value.loc,
        value.enum_cases
    );
}

# Whether `a`, not the base's element `b` itself, has the same record:
# a copy a pass made of it.
_same_a_Attribute(a: ast.Attribute, b: ast.Attribute, base: DeltaBase): bool {
    var x = base.scratch();
    _a_Attribute_write(x, a);
    var y = base.scratch();
    _a_Attribute_write(y, b);
    return base.hash_of(x) == base.hash_of(y);
}

# Whether `a`, not the base's element `b` itself, has the same record:
# a copy a pass made of it.
_same_m_FunctionDef(a: FunctionDef, b: FunctionDef, base: DeltaBase): bool {
    var x = base.scratch();
    _m_FunctionDef_write(x, a);
    var y = base.scratch();
    _m_FunctionDef_write(y, b);
    return base.hash_of(x) == base.hash_of(y);
}

# Whether `a`, not the base's element `b` itself, has the same record:
# a copy a pass made of it.
_same_m_GenericParam(a: GenericParam, b: GenericParam, base: DeltaBase): bool {
    var x = base.scratch();
    _m_GenericParam_write(x, a);
    var y = base.scratch();
    _m_GenericParam_write(y, b);
    return base.hash_of(x) == base.hash_of(y);
}

# Whether `a`, not the base's element `b` itself, has the same record:
# a copy a pass made of it.
_same_m_StructDef(a: StructDef, b: StructDef, base: DeltaBase): bool {
    var x = base.scratch();
    _m_StructDef_write(x, a);
    var y = base.scratch();
    _m_StructDef_write(y, b);
    return base.hash_of(x) == base.hash_of(y);
}

# Whether `a`, not the base's element `b` itself, has the same record:
# a copy a pass made of it.
_same_m_TypeName(a: TypeName, b: TypeName, base: DeltaBase): bool {
    var x = base.scratch();
    _m_TypeName_write(x, a);
    var y = base.scratch();
    _m_TypeName_write(y, b);
    return base.hash_of(x) == base.hash_of(y);
}

# Whether `a`, not the base's element `b` itself, has the same record:
# a copy a pass made of it.
_same_m_VariableDef(a: VariableDef, b: VariableDef, base: DeltaBase): bool {
    var x = base.scratch();
    _m_VariableDef_write(x, a);
    var y = base.scratch();
    _m_VariableDef_write(y, b);
    return base.hash_of(x) == base.hash_of(y);
}

_m_Module_interface_fields(value: Module, interface: bool): Array<(String, String)> {
    var found = Array<(String, String)>();
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.imports.count);
        for (var _item2614 in value.imports) {
            _a_Import_write(out, _item2614);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2615 in value.structs) {
            _m_StructDef_write(out, _item2615);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.blank_bodies = false;
        out.unsigned(value.traits.count);
        for (var _item2616 in value.traits) {
            _m_TraitDef_write(out, _item2616);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2617 in value.extensions) {
            _m_ExtensionDef_write(out, _item2617);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2618 in value.functions) {
            _m_FunctionDef_write(out, _item2618);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2619 in value.externs) {
            _m_ExternDef_write(out, _item2619);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2620 in value.globals) {
            _m_VariableDef_write(out, _item2620);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2621 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2621);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2622 in value.enums) {
            _m_EnumDef_write(out, _item2622);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2623 in value.struct_specs) {
            _m_TypeName_write(out, _item2623);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2624 in value.func_specs) {
            _m_TypeName_write(out, _item2624);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2625 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2625);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2626 in value.withheld) {
            _m_Withheld_write(out, _item2626);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2627 in value.properties) {
            _m_PropertyDef_write(out, _item2627);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2628 in value.type_uses) {
            _m_TypeUse_write(out, _item2628);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2629 in value.use_contexts) {
            _m_UseContext_write(out, _item2629);
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
            for (var _item2630 in value.literal_args) {
                var (_t2631, _t2632, _t2633) = _item2630;
                out.loc(_t2631);
                out.unsigned(_t2632);
                out.loc(_t2633);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2634 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2634);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2635 in value.trait_types) {
            _m_TraitType_write(out, _item2635);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2636 in value.conversions) {
            _m_Conversion_write(out, _item2636);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2638 = Array<(u8[], u8[], String)>();
        for (var (_key2637, _) in value.overload_sets) {
            var _scratch2639 = out.scratch();
            _scratch2639.text(_key2637);
            var _vscratch2641 = out.scratch();
            _vscratch2641.unsigned(value.overload_sets[_key2637].count);
            for (var _item2642 in value.overload_sets[_key2637]) {
                _vscratch2641.text(_item2642);
            }
            _keys2638.append((_scratch2639.finish(), _vscratch2641.finish(), _key2637));
        }
        _keys2638.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2638.count);
        for (var (_bytes2640, _, _key2637) in _keys2638) {
            out.text(_key2637);
            out.unsigned(value.overload_sets[_key2637].count);
            for (var _item2643 in value.overload_sets[_key2637]) {
                out.text(_item2643);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2645 = Array<(u8[], u8[], String)>();
        for (var (_key2644, _) in value.overload_unions) {
            var _scratch2646 = out.scratch();
            _scratch2646.text(_key2644);
            var _vscratch2648 = out.scratch();
            _vscratch2648.unsigned(value.overload_unions[_key2644].count);
            for (var _item2649 in value.overload_unions[_key2644]) {
                _vscratch2648.unsigned(_item2649.count);
                for (var _item2650 in _item2649) {
                    _vscratch2648.text(_item2650);
                }
            }
            _keys2645.append((_scratch2646.finish(), _vscratch2648.finish(), _key2644));
        }
        _keys2645.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2645.count);
        for (var (_bytes2647, _, _key2644) in _keys2645) {
            out.text(_key2644);
            out.unsigned(value.overload_unions[_key2644].count);
            for (var _item2651 in value.overload_unions[_key2644]) {
                out.unsigned(_item2651.count);
                for (var _item2652 in _item2651) {
                    out.text(_item2652);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2654 = Array<(u8[], u8[], String)>();
        for (var (_key2653, _) in value.method_overload_sets) {
            var _scratch2655 = out.scratch();
            _scratch2655.text(_key2653);
            var _vscratch2657 = out.scratch();
            var _keys2659 = Array<(u8[], u8[], String)>();
            for (var (_key2658, _) in value.method_overload_sets[_key2653]) {
                var _scratch2660 = _vscratch2657.scratch();
                _scratch2660.text(_key2658);
                var _vscratch2662 = _vscratch2657.scratch();
                _vscratch2662.unsigned(value.method_overload_sets[_key2653][_key2658].count);
                for (var _item2663 in value.method_overload_sets[_key2653][_key2658]) {
                    _vscratch2662.text(_item2663);
                }
                _keys2659.append((_scratch2660.finish(), _vscratch2662.finish(), _key2658));
            }
            _keys2659.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2657.unsigned(_keys2659.count);
            for (var (_bytes2661, _, _key2658) in _keys2659) {
                _vscratch2657.text(_key2658);
                _vscratch2657.unsigned(value.method_overload_sets[_key2653][_key2658].count);
                for (var _item2664 in value.method_overload_sets[_key2653][_key2658]) {
                    _vscratch2657.text(_item2664);
                }
            }
            _keys2654.append((_scratch2655.finish(), _vscratch2657.finish(), _key2653));
        }
        _keys2654.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2654.count);
        for (var (_bytes2656, _, _key2653) in _keys2654) {
            out.text(_key2653);
            var _keys2666 = Array<(u8[], u8[], String)>();
            for (var (_key2665, _) in value.method_overload_sets[_key2653]) {
                var _scratch2667 = out.scratch();
                _scratch2667.text(_key2665);
                var _vscratch2669 = out.scratch();
                _vscratch2669.unsigned(value.method_overload_sets[_key2653][_key2665].count);
                for (var _item2670 in value.method_overload_sets[_key2653][_key2665]) {
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
                out.unsigned(value.method_overload_sets[_key2653][_key2665].count);
                for (var _item2671 in value.method_overload_sets[_key2653][_key2665]) {
                    out.text(_item2671);
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
        var _keys2673 = Array<(u8[], u8[], Loc)>();
        for (var _key2672 in value.private_functions) {
            var _scratch2674 = out.scratch();
            _scratch2674.loc(_key2672);
            var _vscratch2676 = out.scratch();
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
            out.loc(_key2672);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2678 = Array<(u8[], u8[], Loc)>();
        for (var _key2677 in value.file_private_functions) {
            var _scratch2679 = out.scratch();
            _scratch2679.loc(_key2677);
            var _vscratch2681 = out.scratch();
            _keys2678.append((_scratch2679.finish(), _vscratch2681.finish(), _key2677));
        }
        _keys2678.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2678.count);
        for (var (_bytes2680, _, _key2677) in _keys2678) {
            out.loc(_key2677);
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
            for (var _item2682 in value.call_targets) {
                var (_t2683, _t2684) = _item2682;
                out.loc(_t2683);
                out.text(_t2684);
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
            for (var _item2685 in value.argument_names) {
                var (_t2686, _t2687) = _item2685;
                out.loc(_t2686);
                out.text(_t2687);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2688 in value.namespaces) {
            out.text(_item2688);
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
            for (var _item2689 in value.cached_files) {
                out.flag(_item2689);
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
            var _keys2691 = Array<(u8[], u8[], Loc)>();
            for (var (_key2690, _) in value.recorded_summaries) {
                var _scratch2692 = out.scratch();
                _scratch2692.loc(_key2690);
                var _vscratch2694 = out.scratch();
                _vscratch2694.text(value.recorded_summaries[_key2690]);
                _keys2691.append((_scratch2692.finish(), _vscratch2694.finish(), _key2690));
            }
            _keys2691.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2691.count);
            for (var (_bytes2693, _, _key2690) in _keys2691) {
                out.loc(_key2690);
                out.text(value.recorded_summaries[_key2690]);
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
            var _keys2696 = Array<(u8[], u8[], Loc)>();
            for (var _key2695 in value.stripped) {
                var _scratch2697 = out.scratch();
                _scratch2697.loc(_key2695);
                var _vscratch2699 = out.scratch();
                _keys2696.append((_scratch2697.finish(), _vscratch2699.finish(), _key2695));
            }
            _keys2696.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2696.count);
            for (var (_bytes2698, _, _key2695) in _keys2696) {
                out.loc(_key2695);
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
        var _keys2701 = Array<(u8[], u8[], String)>();
        for (var (_key2700, _) in value.spec_requests) {
            var _scratch2702 = out.scratch();
            _scratch2702.text(_key2700);
            var _vscratch2704 = out.scratch();
            _m_SpecRequest_write(_vscratch2704, value.spec_requests[_key2700]);
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
            out.text(_key2700);
            _m_SpecRequest_write(out, value.spec_requests[_key2700]);
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
            for (var _item2705 in value.summaries_to_record) {
                var (_t2706, _t2707) = _item2705;
                out.loc(_t2706);
                out.text(_t2707);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2709 = Array<(u8[], u8[], String)>();
        for (var (_key2708, _) in value.caller_copies) {
            var _scratch2710 = out.scratch();
            _scratch2710.text(_key2708);
            var _vscratch2712 = out.scratch();
            _vscratch2712.unsigned(value.caller_copies[_key2708].count);
            for (var _item2713 in value.caller_copies[_key2708]) {
                _vscratch2712.flag(_item2713);
            }
            _keys2709.append((_scratch2710.finish(), _vscratch2712.finish(), _key2708));
        }
        _keys2709.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2709.count);
        for (var (_bytes2711, _, _key2708) in _keys2709) {
            out.text(_key2708);
            out.unsigned(value.caller_copies[_key2708].count);
            for (var _item2714 in value.caller_copies[_key2708]) {
                out.flag(_item2714);
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
    for (var _item2715 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2715);
        found.append(("structs " + _item2715.name, interface_text(out)));
    }
    for (var _item2716 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2716);
        found.append(("functions " + _item2716.name, interface_text(out)));
    }
    return found;
}
