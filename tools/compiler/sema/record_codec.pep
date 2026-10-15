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

_m_Module_write_delta(out: RecordOut, value: Module, base: DeltaBase) {
    ulong _mark = out.values.count;
    var _hs1486 = Array<String>();
    for (var _item1481 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1481);
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
    var _seq1502 = base.ref_structs;
    ulong _bj1503 = 0;
    var _news1505 = Array<ulong>();
    var _patches1506 = Array<(ulong, ulong)>();
    for (var _i1507 in 0..value.structs.count) {
        if (_bj1503 < _seq1502.count
            and value.structs[_i1507] === _seq1502[_bj1503]
            and !value.extended_checked.contains(value.structs[_i1507].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1507]);
                base.verify_same("s", _bj1503, scratch, value.structs[_i1507].name);
            }
            _bj1503 += 1;
        } else if (_bj1503 < _seq1502.count
            and !(value.structs[_i1507] === _seq1502[_bj1503])
            and _same_m_StructDef(value.structs[_i1507], _seq1502[_bj1503], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1507]);
                base.verify_same("s", _bj1503, scratch, value.structs[_i1507].name);
            }
            _bj1503 += 1;
        } else if (_bj1503 < _seq1502.count and value.structs[_i1507].name == _seq1502[_bj1503].name) {
            _patches1506.append((_i1507, _bj1503));
            _bj1503 += 1;
        } else {
            _news1505.append(_i1507);
        }
    }
    if (_bj1503 == _seq1502.count) {
        out.unsigned(2);
        out.unsigned(_patches1506.count);
        for (var (_i1507, _b) in _patches1506) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1507].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1507], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1508 = RecordOut();
                _own1508.blank_bodies = true;
                _own1508.blank_locs = true;
                _own1508.pending_as_bytes = true;
                var _s1509 = value.structs[_i1507];
                var _methods1510 = _s1509.method_members;
                _s1509.method_members = Array<FunctionDef>();
                var _fields1511 = _s1509.field_members;
                var split__fields1511 = splits_fields(_s1509);
                if (split__fields1511) {
                    _s1509.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1508, _s1509);
                _s1509.method_members = _methods1510;
                _s1509.field_members = _fields1511;
                base.own_named("structs", _s1509.name, interface_text(_own1508));
                for (var _m1512 in _methods1510) {
                    var _own1513 = RecordOut();
                    _own1513.blank_bodies = true;
                    _own1513.blank_locs = true;
                    _own1513.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1513, _m1512);
                    base.own_method("structs", _s1509.name, _m1512.name, interface_text(_own1513));
                }
                if (split__fields1511) {
                    var _order1515 = StringBuilder();
                    for (var _f1514 in _fields1511) {
                        var _own1516 = RecordOut();
                        _own1516.blank_locs = true;
                        _m_VariableDef_write(_own1516, _f1514);
                        base.own_method("structs", _s1509.name, "." + _f1514.name, interface_text(_own1516));
                        _order1515.append(_f1514.name);
                        _order1515.append(",");
                    }
                    base.own_method("structs", _s1509.name, ".#order", _order1515.to_string());
                }
            }
        }
        out.unsigned(_news1505.count);
        for (var _i1507 in _news1505) {
            ulong _before = out.values.count;
            out.unsigned(_i1507);
            _m_StructDef_write(out, value.structs[_i1507]);
            base.count("s new", out.values.count - _before);
            {
                var _own1517 = RecordOut();
                _own1517.blank_bodies = true;
                _own1517.blank_locs = true;
                _own1517.pending_as_bytes = true;
                var _s1518 = value.structs[_i1507];
                var _methods1519 = _s1518.method_members;
                _s1518.method_members = Array<FunctionDef>();
                var _fields1520 = _s1518.field_members;
                var split__fields1520 = splits_fields(_s1518);
                if (split__fields1520) {
                    _s1518.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1517, _s1518);
                _s1518.method_members = _methods1519;
                _s1518.field_members = _fields1520;
                base.own_named("structs", _s1518.name, interface_text(_own1517));
                for (var _m1521 in _methods1519) {
                    var _own1522 = RecordOut();
                    _own1522.blank_bodies = true;
                    _own1522.blank_locs = true;
                    _own1522.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1522, _m1521);
                    base.own_method("structs", _s1518.name, _m1521.name, interface_text(_own1522));
                }
                if (split__fields1520) {
                    var _order1524 = StringBuilder();
                    for (var _f1523 in _fields1520) {
                        var _own1525 = RecordOut();
                        _own1525.blank_locs = true;
                        _m_VariableDef_write(_own1525, _f1523);
                        base.own_method("structs", _s1518.name, "." + _f1523.name, interface_text(_own1525));
                        _order1524.append(_f1523.name);
                        _order1524.append(",");
                    }
                    base.own_method("structs", _s1518.name, ".#order", _order1524.to_string());
                }
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1501 = HashSet<long>();
        var _slots1504 = HashMap<String, long>();
        for (var _i1507 in 0.._seq1502.count) {
            if (!_slots1504.contains(_seq1502[_i1507].name)) {
                _slots1504[_seq1502[_i1507].name] = _i1507 as long;
            }
        }
        out.unsigned(value.structs.count);
        for (var _i1507 in 0..value.structs.count) {
            var _item1500 = value.structs[_i1507];
            var _slot = _slots1504.try_get(_item1500.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq1502[named as ulong] === _item1500
                and !value.extended_checked.contains(_item1500.name)) {
                at = named;
            }
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
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1539 = Array<String>();
    for (var _item1534 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1534);
        _hs1539.append(base.hash_of(scratch));
    }
    var _seq1540 = base.sequence("traits");
    ulong _bj1541 = 0;
    var _news1542 = Array<ulong>();
    for (var _i1543 in 0.._hs1539.count) {
        if (_bj1541 < _seq1540.count and _hs1539[_i1543] == _seq1540[_bj1541]) {
            _bj1541 += 1;
        } else {
            _news1542.append(_i1543);
        }
    }
    if (_bj1541 == _seq1540.count) {
        out.unsigned(2);
        out.unsigned(_news1542.count);
        for (var _i1543 in _news1542) {
            out.unsigned(_i1543);
            _m_TraitDef_write(out, value.traits[_i1543]);
            {
                var _own1544 = RecordOut();
                _own1544.blank_bodies = true;
                _own1544.blank_locs = true;
                _own1544.pending_as_bytes = true;
                _m_TraitDef_write(_own1544, value.traits[_i1543]);
                base.own("traits", interface_text(_own1544));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1543 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1543]);
            {
                var _own1545 = RecordOut();
                _own1545.blank_bodies = true;
                _own1545.blank_locs = true;
                _own1545.pending_as_bytes = true;
                _m_TraitDef_write(_own1545, value.traits[_i1543]);
                base.own("traits", interface_text(_own1545));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1558 = Array<String>();
    for (var _item1553 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1553);
        _hs1558.append(base.hash_of(scratch));
    }
    var _seq1559 = base.sequence("extensions");
    ulong _bj1560 = 0;
    var _news1561 = Array<ulong>();
    for (var _i1562 in 0.._hs1558.count) {
        if (_bj1560 < _seq1559.count and _hs1558[_i1562] == _seq1559[_bj1560]) {
            _bj1560 += 1;
        } else {
            _news1561.append(_i1562);
        }
    }
    if (_bj1560 == _seq1559.count) {
        out.unsigned(2);
        out.unsigned(_news1561.count);
        for (var _i1562 in _news1561) {
            out.unsigned(_i1562);
            _m_ExtensionDef_write(out, value.extensions[_i1562]);
            {
                var _own1563 = RecordOut();
                _own1563.blank_bodies = true;
                _own1563.blank_locs = true;
                _own1563.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1563, value.extensions[_i1562]);
                base.own("extensions", interface_text(_own1563));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1562 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1562]);
            {
                var _own1564 = RecordOut();
                _own1564.blank_bodies = true;
                _own1564.blank_locs = true;
                _own1564.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1564, value.extensions[_i1562]);
                base.own("extensions", interface_text(_own1564));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1577 = base.ref_functions;
    ulong _bj1578 = 0;
    var _news1579 = Array<ulong>();
    var _changed1573 = Array<(ulong, ulong)>();
    for (var _i1580 in 0..value.functions.count) {
        if (_bj1578 < _seq1577.count and value.functions[_i1580] === _seq1577[_bj1578]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1580]);
                base.verify_same("functions", _bj1578, scratch);
            }
            _bj1578 += 1;
        } else if (_bj1578 < _seq1577.count and _same_m_FunctionDef(value.functions[_i1580], _seq1577[_bj1578], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1580]);
                base.verify_same("functions", _bj1578, scratch);
            }
            _bj1578 += 1;
        } else if (_bj1578 < _seq1577.count and value.functions[_i1580].name == _seq1577[_bj1578].name) {
            _changed1573.append((_i1580, _bj1578));
            _bj1578 += 1;
        } else {
            _news1579.append(_i1580);
        }
    }
    if (_bj1578 == _seq1577.count) {
        out.unsigned(2);
        out.unsigned(_changed1573.count);
        for (var (_i1580, _b) in _changed1573) {
            out.text(value.functions[_i1580].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1580]);
            {
                var _own1581 = RecordOut();
                _own1581.blank_bodies = true;
                _own1581.blank_locs = true;
                _own1581.pending_as_bytes = true;
                _m_FunctionDef_write(_own1581, value.functions[_i1580]);
                base.own_function("functions", value.functions[_i1580], interface_text(_own1581));
            }
        }
        base.count("functions" + " changed", _changed1573.count);
        out.unsigned(_news1579.count);
        for (var _i1580 in _news1579) {
            out.unsigned(_i1580);
            _m_FunctionDef_write(out, value.functions[_i1580]);
            {
                var _own1582 = RecordOut();
                _own1582.blank_bodies = true;
                _own1582.blank_locs = true;
                _own1582.pending_as_bytes = true;
                _m_FunctionDef_write(_own1582, value.functions[_i1580]);
                base.own_function("functions", value.functions[_i1580], interface_text(_own1582));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1580 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1580]);
            {
                var _own1583 = RecordOut();
                _own1583.blank_bodies = true;
                _own1583.blank_locs = true;
                _own1583.pending_as_bytes = true;
                _m_FunctionDef_write(_own1583, value.functions[_i1580]);
                base.own_function("functions", value.functions[_i1580], interface_text(_own1583));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1596 = Array<String>();
    for (var _item1591 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1591);
        _hs1596.append(base.hash_of(scratch));
    }
    var _seq1597 = base.sequence("externs");
    ulong _bj1598 = 0;
    var _news1599 = Array<ulong>();
    for (var _i1600 in 0.._hs1596.count) {
        if (_bj1598 < _seq1597.count and _hs1596[_i1600] == _seq1597[_bj1598]) {
            _bj1598 += 1;
        } else {
            _news1599.append(_i1600);
        }
    }
    if (_bj1598 == _seq1597.count) {
        out.unsigned(2);
        out.unsigned(_news1599.count);
        for (var _i1600 in _news1599) {
            out.unsigned(_i1600);
            _m_ExternDef_write(out, value.externs[_i1600]);
            {
                var _own1601 = RecordOut();
                _own1601.blank_bodies = true;
                _own1601.blank_locs = true;
                _own1601.pending_as_bytes = true;
                _m_ExternDef_write(_own1601, value.externs[_i1600]);
                base.own("externs", interface_text(_own1601));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1600 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1600]);
            {
                var _own1602 = RecordOut();
                _own1602.blank_bodies = true;
                _own1602.blank_locs = true;
                _own1602.pending_as_bytes = true;
                _m_ExternDef_write(_own1602, value.externs[_i1600]);
                base.own("externs", interface_text(_own1602));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1615 = Array<String>();
    for (var _item1610 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1610);
        _hs1615.append(base.hash_of(scratch));
    }
    var _seq1616 = base.sequence("globals");
    ulong _bj1617 = 0;
    var _news1618 = Array<ulong>();
    for (var _i1619 in 0.._hs1615.count) {
        if (_bj1617 < _seq1616.count and _hs1615[_i1619] == _seq1616[_bj1617]) {
            _bj1617 += 1;
        } else {
            _news1618.append(_i1619);
        }
    }
    if (_bj1617 == _seq1616.count) {
        out.unsigned(2);
        out.unsigned(_news1618.count);
        for (var _i1619 in _news1618) {
            out.unsigned(_i1619);
            _m_VariableDef_write(out, value.globals[_i1619]);
            {
                var _own1620 = RecordOut();
                _own1620.blank_bodies = true;
                _own1620.blank_locs = true;
                _own1620.pending_as_bytes = true;
                _m_VariableDef_write(_own1620, value.globals[_i1619]);
                base.own("globals", interface_text(_own1620));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1619 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1619]);
            {
                var _own1621 = RecordOut();
                _own1621.blank_bodies = true;
                _own1621.blank_locs = true;
                _own1621.pending_as_bytes = true;
                _m_VariableDef_write(_own1621, value.globals[_i1619]);
                base.own("globals", interface_text(_own1621));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1634 = Array<String>();
    for (var _item1629 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1629);
        _hs1634.append(base.hash_of(scratch));
    }
    var _seq1635 = base.sequence("static_blocks");
    ulong _bj1636 = 0;
    var _news1637 = Array<ulong>();
    for (var _i1638 in 0.._hs1634.count) {
        if (_bj1636 < _seq1635.count and _hs1634[_i1638] == _seq1635[_bj1636]) {
            _bj1636 += 1;
        } else {
            _news1637.append(_i1638);
        }
    }
    if (_bj1636 == _seq1635.count) {
        out.unsigned(2);
        out.unsigned(_news1637.count);
        for (var _i1638 in _news1637) {
            out.unsigned(_i1638);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1638]);
            {
                var _own1639 = RecordOut();
                _own1639.blank_bodies = true;
                _own1639.blank_locs = true;
                _own1639.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1639, value.static_blocks[_i1638]);
                base.own("static_blocks", interface_text(_own1639));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1638 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1638]);
            {
                var _own1640 = RecordOut();
                _own1640.blank_bodies = true;
                _own1640.blank_locs = true;
                _own1640.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1640, value.static_blocks[_i1638]);
                base.own("static_blocks", interface_text(_own1640));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1653 = Array<String>();
    for (var _item1648 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1648);
        _hs1653.append(base.hash_of(scratch));
    }
    var _seq1654 = base.sequence("enums");
    ulong _bj1655 = 0;
    var _news1656 = Array<ulong>();
    for (var _i1657 in 0.._hs1653.count) {
        if (_bj1655 < _seq1654.count and _hs1653[_i1657] == _seq1654[_bj1655]) {
            _bj1655 += 1;
        } else {
            _news1656.append(_i1657);
        }
    }
    if (_bj1655 == _seq1654.count) {
        out.unsigned(2);
        out.unsigned(_news1656.count);
        for (var _i1657 in _news1656) {
            out.unsigned(_i1657);
            _m_EnumDef_write(out, value.enums[_i1657]);
            {
                var _own1658 = RecordOut();
                _own1658.blank_bodies = true;
                _own1658.blank_locs = true;
                _own1658.pending_as_bytes = true;
                _m_EnumDef_write(_own1658, value.enums[_i1657]);
                base.own_named("enums", value.enums[_i1657].name, interface_text(_own1658));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1657 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1657]);
            {
                var _own1659 = RecordOut();
                _own1659.blank_bodies = true;
                _own1659.blank_locs = true;
                _own1659.pending_as_bytes = true;
                _m_EnumDef_write(_own1659, value.enums[_i1657]);
                base.own_named("enums", value.enums[_i1657].name, interface_text(_own1659));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1672 = Array<String>();
    for (var _item1667 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1667);
        _hs1672.append(base.hash_of(scratch));
    }
    var _seq1673 = base.sequence("struct_specs");
    ulong _bj1674 = 0;
    var _news1675 = Array<ulong>();
    for (var _i1676 in 0.._hs1672.count) {
        if (_bj1674 < _seq1673.count and _hs1672[_i1676] == _seq1673[_bj1674]) {
            _bj1674 += 1;
        } else {
            _news1675.append(_i1676);
        }
    }
    if (_bj1674 == _seq1673.count) {
        out.unsigned(2);
        out.unsigned(_news1675.count);
        for (var _i1676 in _news1675) {
            out.unsigned(_i1676);
            _m_TypeName_write(out, value.struct_specs[_i1676]);
            {
                var _own1677 = RecordOut();
                _own1677.blank_bodies = true;
                _own1677.blank_locs = true;
                _own1677.pending_as_bytes = true;
                _m_TypeName_write(_own1677, value.struct_specs[_i1676]);
                base.own("struct_specs", interface_text(_own1677));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1676 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1676]);
            {
                var _own1678 = RecordOut();
                _own1678.blank_bodies = true;
                _own1678.blank_locs = true;
                _own1678.pending_as_bytes = true;
                _m_TypeName_write(_own1678, value.struct_specs[_i1676]);
                base.own("struct_specs", interface_text(_own1678));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1691 = Array<String>();
    for (var _item1686 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1686);
        _hs1691.append(base.hash_of(scratch));
    }
    var _seq1692 = base.sequence("func_specs");
    ulong _bj1693 = 0;
    var _news1694 = Array<ulong>();
    for (var _i1695 in 0.._hs1691.count) {
        if (_bj1693 < _seq1692.count and _hs1691[_i1695] == _seq1692[_bj1693]) {
            _bj1693 += 1;
        } else {
            _news1694.append(_i1695);
        }
    }
    if (_bj1693 == _seq1692.count) {
        out.unsigned(2);
        out.unsigned(_news1694.count);
        for (var _i1695 in _news1694) {
            out.unsigned(_i1695);
            _m_TypeName_write(out, value.func_specs[_i1695]);
            {
                var _own1696 = RecordOut();
                _own1696.blank_bodies = true;
                _own1696.blank_locs = true;
                _own1696.pending_as_bytes = true;
                _m_TypeName_write(_own1696, value.func_specs[_i1695]);
                base.own("func_specs", interface_text(_own1696));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1695 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1695]);
            {
                var _own1697 = RecordOut();
                _own1697.blank_bodies = true;
                _own1697.blank_locs = true;
                _own1697.pending_as_bytes = true;
                _m_TypeName_write(_own1697, value.func_specs[_i1695]);
                base.own("func_specs", interface_text(_own1697));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1709 = HashSet<long>();
    out.unsigned(value.type_aliases.count);
    for (var _item1705 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1705);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1709.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1705);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1709.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1719 = Array<String>();
    for (var _item1714 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1714);
        _hs1719.append(base.hash_of(scratch));
    }
    var _seq1720 = base.sequence("withheld");
    ulong _bj1721 = 0;
    var _news1722 = Array<ulong>();
    for (var _i1723 in 0.._hs1719.count) {
        if (_bj1721 < _seq1720.count and _hs1719[_i1723] == _seq1720[_bj1721]) {
            _bj1721 += 1;
        } else {
            _news1722.append(_i1723);
        }
    }
    if (_bj1721 == _seq1720.count) {
        out.unsigned(2);
        out.unsigned(_news1722.count);
        for (var _i1723 in _news1722) {
            out.unsigned(_i1723);
            _m_Withheld_write(out, value.withheld[_i1723]);
            {
                var _own1724 = RecordOut();
                _own1724.blank_bodies = true;
                _own1724.blank_locs = true;
                _own1724.pending_as_bytes = true;
                _m_Withheld_write(_own1724, value.withheld[_i1723]);
                base.own("withheld", interface_text(_own1724));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1723 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1723]);
            {
                var _own1725 = RecordOut();
                _own1725.blank_bodies = true;
                _own1725.blank_locs = true;
                _own1725.pending_as_bytes = true;
                _m_Withheld_write(_own1725, value.withheld[_i1723]);
                base.own("withheld", interface_text(_own1725));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1738 = Array<String>();
    for (var _item1733 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1733);
        _hs1738.append(base.hash_of(scratch));
    }
    var _seq1739 = base.sequence("properties");
    ulong _bj1740 = 0;
    var _news1741 = Array<ulong>();
    for (var _i1742 in 0.._hs1738.count) {
        if (_bj1740 < _seq1739.count and _hs1738[_i1742] == _seq1739[_bj1740]) {
            _bj1740 += 1;
        } else {
            _news1741.append(_i1742);
        }
    }
    if (_bj1740 == _seq1739.count) {
        out.unsigned(2);
        out.unsigned(_news1741.count);
        for (var _i1742 in _news1741) {
            out.unsigned(_i1742);
            _m_PropertyDef_write(out, value.properties[_i1742]);
            {
                var _own1743 = RecordOut();
                _own1743.blank_bodies = true;
                _own1743.blank_locs = true;
                _own1743.pending_as_bytes = true;
                _m_PropertyDef_write(_own1743, value.properties[_i1742]);
                base.own("properties", interface_text(_own1743));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1742 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1742]);
            {
                var _own1744 = RecordOut();
                _own1744.blank_bodies = true;
                _own1744.blank_locs = true;
                _own1744.pending_as_bytes = true;
                _m_PropertyDef_write(_own1744, value.properties[_i1742]);
                base.own("properties", interface_text(_own1744));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1757 = Array<String>();
    for (var _item1752 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1752);
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
    var _hs1776 = Array<String>();
    for (var _item1771 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1771);
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
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1826 = Array<String>();
    for (var _item1821 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1821);
        _hs1826.append(base.hash_of(scratch));
    }
    var _seq1827 = base.sequence("constrained_aliases");
    ulong _bj1828 = 0;
    var _news1829 = Array<ulong>();
    for (var _i1830 in 0.._hs1826.count) {
        if (_bj1828 < _seq1827.count and _hs1826[_i1830] == _seq1827[_bj1828]) {
            _bj1828 += 1;
        } else {
            _news1829.append(_i1830);
        }
    }
    if (_bj1828 == _seq1827.count) {
        out.unsigned(2);
        out.unsigned(_news1829.count);
        for (var _i1830 in _news1829) {
            out.unsigned(_i1830);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1830]);
            {
                var _own1831 = RecordOut();
                _own1831.blank_bodies = true;
                _own1831.blank_locs = true;
                _own1831.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1831, value.constrained_aliases[_i1830]);
                base.own("constrained_aliases", interface_text(_own1831));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1830 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1830]);
            {
                var _own1832 = RecordOut();
                _own1832.blank_bodies = true;
                _own1832.blank_locs = true;
                _own1832.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1832, value.constrained_aliases[_i1830]);
                base.own("constrained_aliases", interface_text(_own1832));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1845 = Array<String>();
    for (var _item1840 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1840);
        _hs1845.append(base.hash_of(scratch));
    }
    var _seq1846 = base.sequence("trait_types");
    ulong _bj1847 = 0;
    var _news1848 = Array<ulong>();
    for (var _i1849 in 0.._hs1845.count) {
        if (_bj1847 < _seq1846.count and _hs1845[_i1849] == _seq1846[_bj1847]) {
            _bj1847 += 1;
        } else {
            _news1848.append(_i1849);
        }
    }
    if (_bj1847 == _seq1846.count) {
        out.unsigned(2);
        out.unsigned(_news1848.count);
        for (var _i1849 in _news1848) {
            out.unsigned(_i1849);
            _m_TraitType_write(out, value.trait_types[_i1849]);
            {
                var _own1850 = RecordOut();
                _own1850.blank_bodies = true;
                _own1850.blank_locs = true;
                _own1850.pending_as_bytes = true;
                _m_TraitType_write(_own1850, value.trait_types[_i1849]);
                base.own("trait_types", interface_text(_own1850));
            }
        }
        base.count("trait_types" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("trait_types" + " whole", 0);
        out.unsigned(value.trait_types.count);
        for (var _i1849 in 0..value.trait_types.count) {
            _m_TraitType_write(out, value.trait_types[_i1849]);
            {
                var _own1851 = RecordOut();
                _own1851.blank_bodies = true;
                _own1851.blank_locs = true;
                _own1851.pending_as_bytes = true;
                _m_TraitType_write(_own1851, value.trait_types[_i1849]);
                base.own("trait_types", interface_text(_own1851));
            }
        }
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    out.unsigned(value.conversions.count);
    for (var _item1859 in value.conversions) {
        _m_Conversion_write(out, _item1859);
    }
    for (var _conv1860 in value.conversions) {
        var _own1861 = RecordOut();
        _own1861.blank_locs = true;
        _m_Conversion_write(_own1861, _conv1860);
        var _h = interface_text(_own1861);
        if (base.find_hashed("conversions", _h) < 0) {
            base.own("conversions", _h);
        }
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1869 = 0;
    var _news1870 = Map<String, Array<String>>();
    for (var (_key1866, _) in value.overload_sets) {
        var _kscratch1867 = base.scratch();
        _kscratch1867.text(_key1866);
        var _vscratch1868 = base.scratch();
        _vscratch1868.unsigned(value.overload_sets[_key1866].count);
        for (var _item1871 in value.overload_sets[_key1866]) {
            _vscratch1868.text(_item1871);
        }
        var _had = base.entry("overload_sets", _kscratch1867, _vscratch1868);
        if (_had >= 0) {
            _kept1869 += 1;
        }
        if (_had != 1) {
            _news1870[_key1866] = value.overload_sets[_key1866];
        }
    }
    if (_kept1869 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1873 = Array<(u8[], u8[], String)>();
        for (var (_key1872, _) in _news1870) {
            var _scratch1874 = out.scratch();
            _scratch1874.text(_key1872);
            var _vscratch1876 = out.scratch();
            _vscratch1876.unsigned(_news1870[_key1872].count);
            for (var _item1877 in _news1870[_key1872]) {
                _vscratch1876.text(_item1877);
            }
            _keys1873.append((_scratch1874.finish(), _vscratch1876.finish(), _key1872));
        }
        _keys1873.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1873.count);
        for (var (_bytes1875, _, _key1872) in _keys1873) {
            out.text(_key1872);
            out.unsigned(_news1870[_key1872].count);
            for (var _item1878 in _news1870[_key1872]) {
                out.text(_item1878);
            }
        }
        for (var (_okey1879, _) in _news1870) {
            var _own1880 = RecordOut();
            _own1880.blank_bodies = true;
            _own1880.blank_locs = true;
            _own1880.pending_as_bytes = true;
            _own1880.text(_okey1879);
            _own1880.unsigned(_news1870[_okey1879].count);
            for (var _item1881 in _news1870[_okey1879]) {
                _own1880.text(_item1881);
            }
            base.own("overload_sets", interface_text(_own1880));
        }
    } else {
        out.unsigned(0);
        var _keys1883 = Array<(u8[], u8[], String)>();
        for (var (_key1882, _) in value.overload_sets) {
            var _scratch1884 = out.scratch();
            _scratch1884.text(_key1882);
            var _vscratch1886 = out.scratch();
            _vscratch1886.unsigned(value.overload_sets[_key1882].count);
            for (var _item1887 in value.overload_sets[_key1882]) {
                _vscratch1886.text(_item1887);
            }
            _keys1883.append((_scratch1884.finish(), _vscratch1886.finish(), _key1882));
        }
        _keys1883.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1883.count);
        for (var (_bytes1885, _, _key1882) in _keys1883) {
            out.text(_key1882);
            out.unsigned(value.overload_sets[_key1882].count);
            for (var _item1888 in value.overload_sets[_key1882]) {
                out.text(_item1888);
            }
        }
        for (var (_okey1889, _) in value.overload_sets) {
            var _own1890 = RecordOut();
            _own1890.blank_bodies = true;
            _own1890.blank_locs = true;
            _own1890.pending_as_bytes = true;
            _own1890.text(_okey1889);
            _own1890.unsigned(value.overload_sets[_okey1889].count);
            for (var _item1891 in value.overload_sets[_okey1889]) {
                _own1890.text(_item1891);
            }
            base.own("overload_sets", interface_text(_own1890));
        }
        base.count("overload_sets whole", 0);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1909 = 0;
    var _news1910 = Map<String, Array<Array<String>>>();
    for (var (_key1906, _) in value.overload_unions) {
        var _kscratch1907 = base.scratch();
        _kscratch1907.text(_key1906);
        var _vscratch1908 = base.scratch();
        _vscratch1908.unsigned(value.overload_unions[_key1906].count);
        for (var _item1911 in value.overload_unions[_key1906]) {
            _vscratch1908.unsigned(_item1911.count);
            for (var _item1912 in _item1911) {
                _vscratch1908.text(_item1912);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1907, _vscratch1908);
        if (_had >= 0) {
            _kept1909 += 1;
        }
        if (_had != 1) {
            _news1910[_key1906] = value.overload_unions[_key1906];
        }
    }
    if (_kept1909 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1914 = Array<(u8[], u8[], String)>();
        for (var (_key1913, _) in _news1910) {
            var _scratch1915 = out.scratch();
            _scratch1915.text(_key1913);
            var _vscratch1917 = out.scratch();
            _vscratch1917.unsigned(_news1910[_key1913].count);
            for (var _item1918 in _news1910[_key1913]) {
                _vscratch1917.unsigned(_item1918.count);
                for (var _item1919 in _item1918) {
                    _vscratch1917.text(_item1919);
                }
            }
            _keys1914.append((_scratch1915.finish(), _vscratch1917.finish(), _key1913));
        }
        _keys1914.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1914.count);
        for (var (_bytes1916, _, _key1913) in _keys1914) {
            out.text(_key1913);
            out.unsigned(_news1910[_key1913].count);
            for (var _item1920 in _news1910[_key1913]) {
                out.unsigned(_item1920.count);
                for (var _item1921 in _item1920) {
                    out.text(_item1921);
                }
            }
        }
        for (var (_okey1922, _) in _news1910) {
            var _own1923 = RecordOut();
            _own1923.blank_bodies = true;
            _own1923.blank_locs = true;
            _own1923.pending_as_bytes = true;
            _own1923.text(_okey1922);
            _own1923.unsigned(_news1910[_okey1922].count);
            for (var _item1924 in _news1910[_okey1922]) {
                _own1923.unsigned(_item1924.count);
                for (var _item1925 in _item1924) {
                    _own1923.text(_item1925);
                }
            }
            base.own("overload_unions", interface_text(_own1923));
        }
    } else {
        out.unsigned(0);
        var _keys1927 = Array<(u8[], u8[], String)>();
        for (var (_key1926, _) in value.overload_unions) {
            var _scratch1928 = out.scratch();
            _scratch1928.text(_key1926);
            var _vscratch1930 = out.scratch();
            _vscratch1930.unsigned(value.overload_unions[_key1926].count);
            for (var _item1931 in value.overload_unions[_key1926]) {
                _vscratch1930.unsigned(_item1931.count);
                for (var _item1932 in _item1931) {
                    _vscratch1930.text(_item1932);
                }
            }
            _keys1927.append((_scratch1928.finish(), _vscratch1930.finish(), _key1926));
        }
        _keys1927.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1927.count);
        for (var (_bytes1929, _, _key1926) in _keys1927) {
            out.text(_key1926);
            out.unsigned(value.overload_unions[_key1926].count);
            for (var _item1933 in value.overload_unions[_key1926]) {
                out.unsigned(_item1933.count);
                for (var _item1934 in _item1933) {
                    out.text(_item1934);
                }
            }
        }
        for (var (_okey1935, _) in value.overload_unions) {
            var _own1936 = RecordOut();
            _own1936.blank_bodies = true;
            _own1936.blank_locs = true;
            _own1936.pending_as_bytes = true;
            _own1936.text(_okey1935);
            _own1936.unsigned(value.overload_unions[_okey1935].count);
            for (var _item1937 in value.overload_unions[_okey1935]) {
                _own1936.unsigned(_item1937.count);
                for (var _item1938 in _item1937) {
                    _own1936.text(_item1938);
                }
            }
            base.own("overload_unions", interface_text(_own1936));
        }
        base.count("overload_unions whole", 0);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1961 = 0;
    var _news1962 = Map<String, Map<String, Array<String>>>();
    for (var (_key1958, _) in value.method_overload_sets) {
        var _kscratch1959 = base.scratch();
        _kscratch1959.text(_key1958);
        var _vscratch1960 = base.scratch();
        var _keys1964 = Array<(u8[], u8[], String)>();
        for (var (_key1963, _) in value.method_overload_sets[_key1958]) {
            var _scratch1965 = _vscratch1960.scratch();
            _scratch1965.text(_key1963);
            var _vscratch1967 = _vscratch1960.scratch();
            _vscratch1967.unsigned(value.method_overload_sets[_key1958][_key1963].count);
            for (var _item1968 in value.method_overload_sets[_key1958][_key1963]) {
                _vscratch1967.text(_item1968);
            }
            _keys1964.append((_scratch1965.finish(), _vscratch1967.finish(), _key1963));
        }
        _keys1964.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1960.unsigned(_keys1964.count);
        for (var (_bytes1966, _, _key1963) in _keys1964) {
            _vscratch1960.text(_key1963);
            _vscratch1960.unsigned(value.method_overload_sets[_key1958][_key1963].count);
            for (var _item1969 in value.method_overload_sets[_key1958][_key1963]) {
                _vscratch1960.text(_item1969);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1959, _vscratch1960);
        if (_had >= 0) {
            _kept1961 += 1;
        }
        if (_had != 1) {
            _news1962[_key1958] = value.method_overload_sets[_key1958];
        }
    }
    if (_kept1961 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1971 = Array<(u8[], u8[], String)>();
        for (var (_key1970, _) in _news1962) {
            var _scratch1972 = out.scratch();
            _scratch1972.text(_key1970);
            var _vscratch1974 = out.scratch();
            var _keys1976 = Array<(u8[], u8[], String)>();
            for (var (_key1975, _) in _news1962[_key1970]) {
                var _scratch1977 = _vscratch1974.scratch();
                _scratch1977.text(_key1975);
                var _vscratch1979 = _vscratch1974.scratch();
                _vscratch1979.unsigned(_news1962[_key1970][_key1975].count);
                for (var _item1980 in _news1962[_key1970][_key1975]) {
                    _vscratch1979.text(_item1980);
                }
                _keys1976.append((_scratch1977.finish(), _vscratch1979.finish(), _key1975));
            }
            _keys1976.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1974.unsigned(_keys1976.count);
            for (var (_bytes1978, _, _key1975) in _keys1976) {
                _vscratch1974.text(_key1975);
                _vscratch1974.unsigned(_news1962[_key1970][_key1975].count);
                for (var _item1981 in _news1962[_key1970][_key1975]) {
                    _vscratch1974.text(_item1981);
                }
            }
            _keys1971.append((_scratch1972.finish(), _vscratch1974.finish(), _key1970));
        }
        _keys1971.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1971.count);
        for (var (_bytes1973, _, _key1970) in _keys1971) {
            out.text(_key1970);
            var _keys1983 = Array<(u8[], u8[], String)>();
            for (var (_key1982, _) in _news1962[_key1970]) {
                var _scratch1984 = out.scratch();
                _scratch1984.text(_key1982);
                var _vscratch1986 = out.scratch();
                _vscratch1986.unsigned(_news1962[_key1970][_key1982].count);
                for (var _item1987 in _news1962[_key1970][_key1982]) {
                    _vscratch1986.text(_item1987);
                }
                _keys1983.append((_scratch1984.finish(), _vscratch1986.finish(), _key1982));
            }
            _keys1983.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1983.count);
            for (var (_bytes1985, _, _key1982) in _keys1983) {
                out.text(_key1982);
                out.unsigned(_news1962[_key1970][_key1982].count);
                for (var _item1988 in _news1962[_key1970][_key1982]) {
                    out.text(_item1988);
                }
            }
        }
        for (var (_okey1989, _) in _news1962) {
            var _own1990 = RecordOut();
            _own1990.blank_bodies = true;
            _own1990.blank_locs = true;
            _own1990.pending_as_bytes = true;
            _own1990.text(_okey1989);
            var _keys1992 = Array<(u8[], u8[], String)>();
            for (var (_key1991, _) in _news1962[_okey1989]) {
                var _scratch1993 = _own1990.scratch();
                _scratch1993.text(_key1991);
                var _vscratch1995 = _own1990.scratch();
                _vscratch1995.unsigned(_news1962[_okey1989][_key1991].count);
                for (var _item1996 in _news1962[_okey1989][_key1991]) {
                    _vscratch1995.text(_item1996);
                }
                _keys1992.append((_scratch1993.finish(), _vscratch1995.finish(), _key1991));
            }
            _keys1992.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own1990.unsigned(_keys1992.count);
            for (var (_bytes1994, _, _key1991) in _keys1992) {
                _own1990.text(_key1991);
                _own1990.unsigned(_news1962[_okey1989][_key1991].count);
                for (var _item1997 in _news1962[_okey1989][_key1991]) {
                    _own1990.text(_item1997);
                }
            }
            base.own("method_overload_sets", interface_text(_own1990));
        }
    } else {
        out.unsigned(0);
        var _keys1999 = Array<(u8[], u8[], String)>();
        for (var (_key1998, _) in value.method_overload_sets) {
            var _scratch2000 = out.scratch();
            _scratch2000.text(_key1998);
            var _vscratch2002 = out.scratch();
            var _keys2004 = Array<(u8[], u8[], String)>();
            for (var (_key2003, _) in value.method_overload_sets[_key1998]) {
                var _scratch2005 = _vscratch2002.scratch();
                _scratch2005.text(_key2003);
                var _vscratch2007 = _vscratch2002.scratch();
                _vscratch2007.unsigned(value.method_overload_sets[_key1998][_key2003].count);
                for (var _item2008 in value.method_overload_sets[_key1998][_key2003]) {
                    _vscratch2007.text(_item2008);
                }
                _keys2004.append((_scratch2005.finish(), _vscratch2007.finish(), _key2003));
            }
            _keys2004.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2002.unsigned(_keys2004.count);
            for (var (_bytes2006, _, _key2003) in _keys2004) {
                _vscratch2002.text(_key2003);
                _vscratch2002.unsigned(value.method_overload_sets[_key1998][_key2003].count);
                for (var _item2009 in value.method_overload_sets[_key1998][_key2003]) {
                    _vscratch2002.text(_item2009);
                }
            }
            _keys1999.append((_scratch2000.finish(), _vscratch2002.finish(), _key1998));
        }
        _keys1999.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1999.count);
        for (var (_bytes2001, _, _key1998) in _keys1999) {
            out.text(_key1998);
            var _keys2011 = Array<(u8[], u8[], String)>();
            for (var (_key2010, _) in value.method_overload_sets[_key1998]) {
                var _scratch2012 = out.scratch();
                _scratch2012.text(_key2010);
                var _vscratch2014 = out.scratch();
                _vscratch2014.unsigned(value.method_overload_sets[_key1998][_key2010].count);
                for (var _item2015 in value.method_overload_sets[_key1998][_key2010]) {
                    _vscratch2014.text(_item2015);
                }
                _keys2011.append((_scratch2012.finish(), _vscratch2014.finish(), _key2010));
            }
            _keys2011.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2011.count);
            for (var (_bytes2013, _, _key2010) in _keys2011) {
                out.text(_key2010);
                out.unsigned(value.method_overload_sets[_key1998][_key2010].count);
                for (var _item2016 in value.method_overload_sets[_key1998][_key2010]) {
                    out.text(_item2016);
                }
            }
        }
        for (var (_okey2017, _) in value.method_overload_sets) {
            var _own2018 = RecordOut();
            _own2018.blank_bodies = true;
            _own2018.blank_locs = true;
            _own2018.pending_as_bytes = true;
            _own2018.text(_okey2017);
            var _keys2020 = Array<(u8[], u8[], String)>();
            for (var (_key2019, _) in value.method_overload_sets[_okey2017]) {
                var _scratch2021 = _own2018.scratch();
                _scratch2021.text(_key2019);
                var _vscratch2023 = _own2018.scratch();
                _vscratch2023.unsigned(value.method_overload_sets[_okey2017][_key2019].count);
                for (var _item2024 in value.method_overload_sets[_okey2017][_key2019]) {
                    _vscratch2023.text(_item2024);
                }
                _keys2020.append((_scratch2021.finish(), _vscratch2023.finish(), _key2019));
            }
            _keys2020.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own2018.unsigned(_keys2020.count);
            for (var (_bytes2022, _, _key2019) in _keys2020) {
                _own2018.text(_key2019);
                _own2018.unsigned(value.method_overload_sets[_okey2017][_key2019].count);
                for (var _item2025 in value.method_overload_sets[_okey2017][_key2019]) {
                    _own2018.text(_item2025);
                }
            }
            base.own("method_overload_sets", interface_text(_own2018));
        }
        base.count("method_overload_sets whole", 0);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2056 = 0;
    var _news2057 = HashSet<Loc>();
    for (var _key2053 in value.private_functions) {
        var _kscratch2054 = base.scratch();
        _kscratch2054.loc(_key2053);
        var _vscratch2055 = base.scratch();
        var _had = base.entry("private_functions", _kscratch2054, _vscratch2055);
        if (_had >= 0) {
            _kept2056 += 1;
        }
        if (_had != 1) {
            _news2057.insert(_key2053);
        }
    }
    if (_kept2056 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys2059 = Array<(u8[], u8[], Loc)>();
        for (var _key2058 in _news2057) {
            var _scratch2060 = out.scratch();
            _scratch2060.loc(_key2058);
            var _vscratch2062 = out.scratch();
            _keys2059.append((_scratch2060.finish(), _vscratch2062.finish(), _key2058));
        }
        _keys2059.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2059.count);
        for (var (_bytes2061, _, _key2058) in _keys2059) {
            out.loc(_key2058);
        }
        for (var _okey2063 in _news2057) {
            var _own2064 = RecordOut();
            _own2064.blank_bodies = true;
            _own2064.blank_locs = true;
            _own2064.pending_as_bytes = true;
            _own2064.loc(_okey2063);
            base.own_at("private_functions", _okey2063, interface_text(_own2064));
        }
    } else {
        out.unsigned(0);
        var _keys2066 = Array<(u8[], u8[], Loc)>();
        for (var _key2065 in value.private_functions) {
            var _scratch2067 = out.scratch();
            _scratch2067.loc(_key2065);
            var _vscratch2069 = out.scratch();
            _keys2066.append((_scratch2067.finish(), _vscratch2069.finish(), _key2065));
        }
        _keys2066.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2066.count);
        for (var (_bytes2068, _, _key2065) in _keys2066) {
            out.loc(_key2065);
        }
        for (var _okey2070 in value.private_functions) {
            var _own2071 = RecordOut();
            _own2071.blank_bodies = true;
            _own2071.blank_locs = true;
            _own2071.pending_as_bytes = true;
            _own2071.loc(_okey2070);
            base.own_at("private_functions", _okey2070, interface_text(_own2071));
        }
        base.count("private_functions whole", 0);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2082 = 0;
    var _news2083 = HashSet<Loc>();
    for (var _key2079 in value.file_private_functions) {
        var _kscratch2080 = base.scratch();
        _kscratch2080.loc(_key2079);
        var _vscratch2081 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch2080, _vscratch2081);
        if (_had >= 0) {
            _kept2082 += 1;
        }
        if (_had != 1) {
            _news2083.insert(_key2079);
        }
    }
    if (_kept2082 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys2085 = Array<(u8[], u8[], Loc)>();
        for (var _key2084 in _news2083) {
            var _scratch2086 = out.scratch();
            _scratch2086.loc(_key2084);
            var _vscratch2088 = out.scratch();
            _keys2085.append((_scratch2086.finish(), _vscratch2088.finish(), _key2084));
        }
        _keys2085.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2085.count);
        for (var (_bytes2087, _, _key2084) in _keys2085) {
            out.loc(_key2084);
        }
        for (var _okey2089 in _news2083) {
            var _own2090 = RecordOut();
            _own2090.blank_bodies = true;
            _own2090.blank_locs = true;
            _own2090.pending_as_bytes = true;
            _own2090.loc(_okey2089);
            base.own_at("file_private_functions", _okey2089, interface_text(_own2090));
        }
    } else {
        out.unsigned(0);
        var _keys2092 = Array<(u8[], u8[], Loc)>();
        for (var _key2091 in value.file_private_functions) {
            var _scratch2093 = out.scratch();
            _scratch2093.loc(_key2091);
            var _vscratch2095 = out.scratch();
            _keys2092.append((_scratch2093.finish(), _vscratch2095.finish(), _key2091));
        }
        _keys2092.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2092.count);
        for (var (_bytes2094, _, _key2091) in _keys2092) {
            out.loc(_key2091);
        }
        for (var _okey2096 in value.file_private_functions) {
            var _own2097 = RecordOut();
            _own2097.blank_bodies = true;
            _own2097.blank_locs = true;
            _own2097.pending_as_bytes = true;
            _own2097.loc(_okey2096);
            base.own_at("file_private_functions", _okey2096, interface_text(_own2097));
        }
        base.count("file_private_functions whole", 0);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n2107 = base.size("call_targets");
    var _scratch2106 = base.scratch();
    if (value.call_targets.count >= _n2107) {
        for (var _i2108 in 0.._n2107) {
            var (_t2109, _t2110) = value.call_targets[_i2108];
            _scratch2106.loc(_t2109);
            _scratch2106.text(_t2110);
        }
    }
    if (value.call_targets.count >= _n2107 and base.same_list("call_targets", _scratch2106)) {
        out.unsigned(1);
        out.unsigned(_n2107);
        out.unsigned(value.call_targets.count - _n2107);
        for (var _i2108 in _n2107..value.call_targets.count) {
            var (_t2111, _t2112) = value.call_targets[_i2108];
            out.loc(_t2111);
            out.text(_t2112);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item2113 in value.call_targets) {
            var (_t2114, _t2115) = _item2113;
            out.loc(_t2114);
            out.text(_t2115);
        }
        base.count("call_targets whole", 0);
    }
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2132 = 0;
    var _news2133 = Array<(Loc, String)>();
    for (var _item2130 in value.argument_names) {
        var _escratch2131 = base.scratch();
        var (_t2134, _t2135) = _item2130;
        _escratch2131.loc(_t2134);
        _escratch2131.text(_t2135);
        if (base.entry("argument_names", _escratch2131, base.scratch()) >= 0) {
            _kept2132 += 1;
        } else {
            _news2133.append(_item2130);
        }
    }
    if (_kept2132 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2133.count);
        for (var _item2136 in _news2133) {
            var (_t2137, _t2138) = _item2136;
            out.loc(_t2137);
            out.text(_t2138);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2139 in value.argument_names) {
            var (_t2140, _t2141) = _item2139;
            out.loc(_t2140);
            out.text(_t2141);
        }
        base.count("argument_names whole", 0);
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2156 = base.size("namespaces");
    var _scratch2155 = base.scratch();
    if (value.namespaces.count >= _n2156) {
        for (var _i2157 in 0.._n2156) {
            _scratch2155.text(value.namespaces[_i2157]);
        }
    }
    if (value.namespaces.count >= _n2156 and base.same_list("namespaces", _scratch2155)) {
        out.unsigned(1);
        out.unsigned(_n2156);
        out.unsigned(value.namespaces.count - _n2156);
        for (var _i2157 in _n2156..value.namespaces.count) {
            out.text(value.namespaces[_i2157]);
            {
                var _own2158 = RecordOut();
                _own2158.blank_bodies = true;
                _own2158.blank_locs = true;
                _own2158.pending_as_bytes = true;
                _own2158.text(value.namespaces[_i2157]);
                base.own("namespaces", interface_text(_own2158));
            }
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2159 in value.namespaces) {
            out.text(_item2159);
        }
        for (var _i2157 in 0..value.namespaces.count) {
            {
                var _own2160 = RecordOut();
                _own2160.blank_bodies = true;
                _own2160.blank_locs = true;
                _own2160.pending_as_bytes = true;
                _own2160.text(value.namespaces[_i2157]);
                base.own("namespaces", interface_text(_own2160));
            }
        }
        base.count("namespaces whole", 0);
    }
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2171 = base.size("cached_files");
    var _scratch2170 = base.scratch();
    if (value.cached_files.count >= _n2171) {
        for (var _i2172 in 0.._n2171) {
            _scratch2170.flag(value.cached_files[_i2172]);
        }
    }
    if (value.cached_files.count >= _n2171 and base.same_list("cached_files", _scratch2170)) {
        out.unsigned(1);
        out.unsigned(_n2171);
        out.unsigned(value.cached_files.count - _n2171);
        for (var _i2172 in _n2171..value.cached_files.count) {
            out.flag(value.cached_files[_i2172]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2173 in value.cached_files) {
            out.flag(_item2173);
        }
        base.count("cached_files whole", 0);
    }
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2185 = 0;
    var _news2186 = HashMap<Loc, String>();
    for (var (_key2182, _) in value.recorded_summaries) {
        var _kscratch2183 = base.scratch();
        _kscratch2183.loc(_key2182);
        var _vscratch2184 = base.scratch();
        _vscratch2184.text(value.recorded_summaries[_key2182]);
        var _had = base.entry("recorded_summaries", _kscratch2183, _vscratch2184);
        if (_had >= 0) {
            _kept2185 += 1;
        }
        if (_had != 1) {
            _news2186[_key2182] = value.recorded_summaries[_key2182];
        }
    }
    if (_kept2185 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2188 = Array<(u8[], u8[], Loc)>();
        for (var (_key2187, _) in _news2186) {
            var _scratch2189 = out.scratch();
            _scratch2189.loc(_key2187);
            var _vscratch2191 = out.scratch();
            _vscratch2191.text(_news2186[_key2187]);
            _keys2188.append((_scratch2189.finish(), _vscratch2191.finish(), _key2187));
        }
        _keys2188.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2188.count);
        for (var (_bytes2190, _, _key2187) in _keys2188) {
            out.loc(_key2187);
            out.text(_news2186[_key2187]);
        }
    } else {
        out.unsigned(0);
        var _keys2193 = Array<(u8[], u8[], Loc)>();
        for (var (_key2192, _) in value.recorded_summaries) {
            var _scratch2194 = out.scratch();
            _scratch2194.loc(_key2192);
            var _vscratch2196 = out.scratch();
            _vscratch2196.text(value.recorded_summaries[_key2192]);
            _keys2193.append((_scratch2194.finish(), _vscratch2196.finish(), _key2192));
        }
        _keys2193.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2193.count);
        for (var (_bytes2195, _, _key2192) in _keys2193) {
            out.loc(_key2192);
            out.text(value.recorded_summaries[_key2192]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2209 = 0;
    var _news2210 = HashSet<Loc>();
    for (var _key2206 in value.stripped) {
        var _kscratch2207 = base.scratch();
        _kscratch2207.loc(_key2206);
        var _vscratch2208 = base.scratch();
        var _had = base.entry("stripped", _kscratch2207, _vscratch2208);
        if (_had >= 0) {
            _kept2209 += 1;
        }
        if (_had != 1) {
            _news2210.insert(_key2206);
        }
    }
    if (_kept2209 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2212 = Array<(u8[], u8[], Loc)>();
        for (var _key2211 in _news2210) {
            var _scratch2213 = out.scratch();
            _scratch2213.loc(_key2211);
            var _vscratch2215 = out.scratch();
            _keys2212.append((_scratch2213.finish(), _vscratch2215.finish(), _key2211));
        }
        _keys2212.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2212.count);
        for (var (_bytes2214, _, _key2211) in _keys2212) {
            out.loc(_key2211);
        }
    } else {
        out.unsigned(0);
        var _keys2217 = Array<(u8[], u8[], Loc)>();
        for (var _key2216 in value.stripped) {
            var _scratch2218 = out.scratch();
            _scratch2218.loc(_key2216);
            var _vscratch2220 = out.scratch();
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
            out.loc(_key2216);
        }
        base.count("stripped whole", 0);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _seq2230 = base.ref_templates;
    ulong _bj2231 = 0;
    var _news2233 = Array<ulong>();
    var _patches2234 = Array<(ulong, ulong)>();
    for (var _i2235 in 0..value.templates.structs.count) {
        if (_bj2231 < _seq2230.count
            and value.templates.structs[_i2235] === _seq2230[_bj2231]
            and !value.extended_checked.contains(value.templates.structs[_i2235].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2235]);
                base.verify_same("t", _bj2231, scratch, value.templates.structs[_i2235].name);
            }
            _bj2231 += 1;
        } else if (_bj2231 < _seq2230.count
            and !(value.templates.structs[_i2235] === _seq2230[_bj2231])
            and _same_m_StructDef(value.templates.structs[_i2235], _seq2230[_bj2231], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2235]);
                base.verify_same("t", _bj2231, scratch, value.templates.structs[_i2235].name);
            }
            _bj2231 += 1;
        } else if (_bj2231 < _seq2230.count and value.templates.structs[_i2235].name == _seq2230[_bj2231].name) {
            _patches2234.append((_i2235, _bj2231));
            _bj2231 += 1;
        } else {
            _news2233.append(_i2235);
        }
    }
    if (_bj2231 == _seq2230.count) {
        out.unsigned(2);
        out.unsigned(_patches2234.count);
        for (var (_i2235, _b) in _patches2234) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2235].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2235], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2236 = RecordOut();
                _own2236.blank_bodies = false;
                _own2236.blank_locs = true;
                _own2236.pending_as_bytes = true;
                _m_StructDef_write(_own2236, value.templates.structs[_i2235]);
                base.own("templates structs", interface_text(_own2236));
            }
        }
        out.unsigned(_news2233.count);
        for (var _i2235 in _news2233) {
            ulong _before = out.values.count;
            out.unsigned(_i2235);
            _m_StructDef_write(out, value.templates.structs[_i2235]);
            base.count("t new", out.values.count - _before);
            {
                var _own2237 = RecordOut();
                _own2237.blank_bodies = false;
                _own2237.blank_locs = true;
                _own2237.pending_as_bytes = true;
                _m_StructDef_write(_own2237, value.templates.structs[_i2235]);
                base.own("templates structs", interface_text(_own2237));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2229 = HashSet<long>();
        var _slots2232 = HashMap<String, long>();
        for (var _i2235 in 0.._seq2230.count) {
            if (!_slots2232.contains(_seq2230[_i2235].name)) {
                _slots2232[_seq2230[_i2235].name] = _i2235 as long;
            }
        }
        out.unsigned(value.templates.structs.count);
        for (var _i2235 in 0..value.templates.structs.count) {
            var _item2228 = value.templates.structs[_i2235];
            var _slot = _slots2232.try_get(_item2228.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq2230[named as ulong] === _item2228
                and !value.extended_checked.contains(_item2228.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2229.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2229.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2228, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2228);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2229.count);
    }
    var _seq2251 = base.ref_template_functions;
    ulong _bj2252 = 0;
    var _news2253 = Array<ulong>();
    var _changed2247 = Array<(ulong, ulong)>();
    for (var _i2254 in 0..value.templates.functions.count) {
        if (_bj2252 < _seq2251.count and value.templates.functions[_i2254] === _seq2251[_bj2252]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2254]);
                base.verify_same("tf", _bj2252, scratch);
            }
            _bj2252 += 1;
        } else if (_bj2252 < _seq2251.count
            and _same_m_FunctionDef(value.templates.functions[_i2254], _seq2251[_bj2252], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2254]);
                base.verify_same("tf", _bj2252, scratch);
            }
            _bj2252 += 1;
        } else if (_bj2252 < _seq2251.count and value.templates.functions[_i2254].name == _seq2251[_bj2252].name) {
            _changed2247.append((_i2254, _bj2252));
            _bj2252 += 1;
        } else {
            _news2253.append(_i2254);
        }
    }
    if (_bj2252 == _seq2251.count) {
        out.unsigned(2);
        out.unsigned(_changed2247.count);
        for (var (_i2254, _b) in _changed2247) {
            out.text(value.templates.functions[_i2254].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2254]);
            {
                var _own2255 = RecordOut();
                _own2255.blank_bodies = false;
                _own2255.blank_locs = true;
                _own2255.pending_as_bytes = true;
                _m_FunctionDef_write(_own2255, value.templates.functions[_i2254]);
                base.own("templates functions", interface_text(_own2255));
            }
        }
        base.count("tf" + " changed", _changed2247.count);
        out.unsigned(_news2253.count);
        for (var _i2254 in _news2253) {
            out.unsigned(_i2254);
            _m_FunctionDef_write(out, value.templates.functions[_i2254]);
            {
                var _own2256 = RecordOut();
                _own2256.blank_bodies = false;
                _own2256.blank_locs = true;
                _own2256.pending_as_bytes = true;
                _m_FunctionDef_write(_own2256, value.templates.functions[_i2254]);
                base.own("templates functions", interface_text(_own2256));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2254 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2254]);
            {
                var _own2257 = RecordOut();
                _own2257.blank_bodies = false;
                _own2257.blank_locs = true;
                _own2257.pending_as_bytes = true;
                _m_FunctionDef_write(_own2257, value.templates.functions[_i2254]);
                base.own("templates functions", interface_text(_own2257));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2270 = 0;
    var _news2271 = HashMap<String, SpecRequest>();
    for (var (_key2267, _) in value.spec_requests) {
        var _kscratch2268 = base.scratch();
        _kscratch2268.text(_key2267);
        var _vscratch2269 = base.scratch();
        _m_SpecRequest_write(_vscratch2269, value.spec_requests[_key2267]);
        var _had = base.entry("spec_requests", _kscratch2268, _vscratch2269);
        if (_had >= 0) {
            _kept2270 += 1;
        }
        if (_had != 1) {
            _news2271[_key2267] = value.spec_requests[_key2267];
        }
    }
    if (_kept2270 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2273 = Array<(u8[], u8[], String)>();
        for (var (_key2272, _) in _news2271) {
            var _scratch2274 = out.scratch();
            _scratch2274.text(_key2272);
            var _vscratch2276 = out.scratch();
            _m_SpecRequest_write(_vscratch2276, _news2271[_key2272]);
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
            _m_SpecRequest_write(out, _news2271[_key2272]);
        }
        for (var (_okey2277, _) in _news2271) {
            var _own2278 = RecordOut();
            _own2278.blank_bodies = true;
            _own2278.blank_locs = true;
            _own2278.pending_as_bytes = true;
            _own2278.text(_okey2277);
            _m_SpecRequest_write(_own2278, _news2271[_okey2277]);
            base.own("spec_requests", interface_text(_own2278));
        }
    } else {
        out.unsigned(0);
        var _keys2280 = Array<(u8[], u8[], String)>();
        for (var (_key2279, _) in value.spec_requests) {
            var _scratch2281 = out.scratch();
            _scratch2281.text(_key2279);
            var _vscratch2283 = out.scratch();
            _m_SpecRequest_write(_vscratch2283, value.spec_requests[_key2279]);
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
            _m_SpecRequest_write(out, value.spec_requests[_key2279]);
        }
        for (var (_okey2284, _) in value.spec_requests) {
            var _own2285 = RecordOut();
            _own2285.blank_bodies = true;
            _own2285.blank_locs = true;
            _own2285.pending_as_bytes = true;
            _own2285.text(_okey2284);
            _m_SpecRequest_write(_own2285, value.spec_requests[_okey2284]);
            base.own("spec_requests", interface_text(_own2285));
        }
        base.count("spec_requests whole", 0);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2298 = base.size("summaries_to_record");
    var _scratch2297 = base.scratch();
    if (value.summaries_to_record.count >= _n2298) {
        for (var _i2299 in 0.._n2298) {
            var (_t2300, _t2301) = value.summaries_to_record[_i2299];
            _scratch2297.loc(_t2300);
            _scratch2297.text(_t2301);
        }
    }
    if (value.summaries_to_record.count >= _n2298 and base.same_list("summaries_to_record", _scratch2297)) {
        out.unsigned(1);
        out.unsigned(_n2298);
        out.unsigned(value.summaries_to_record.count - _n2298);
        for (var _i2299 in _n2298..value.summaries_to_record.count) {
            var (_t2302, _t2303) = value.summaries_to_record[_i2299];
            out.loc(_t2302);
            out.text(_t2303);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2304 in value.summaries_to_record) {
            var (_t2305, _t2306) = _item2304;
            out.loc(_t2305);
            out.text(_t2306);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2324 = 0;
    var _news2325 = HashMap<String, Array<bool>>();
    for (var (_key2321, _) in value.caller_copies) {
        var _kscratch2322 = base.scratch();
        _kscratch2322.text(_key2321);
        var _vscratch2323 = base.scratch();
        _vscratch2323.unsigned(value.caller_copies[_key2321].count);
        for (var _item2326 in value.caller_copies[_key2321]) {
            _vscratch2323.flag(_item2326);
        }
        var _had = base.entry("caller_copies", _kscratch2322, _vscratch2323);
        if (_had >= 0) {
            _kept2324 += 1;
        }
        if (_had != 1) {
            _news2325[_key2321] = value.caller_copies[_key2321];
        }
    }
    if (_kept2324 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2328 = Array<(u8[], u8[], String)>();
        for (var (_key2327, _) in _news2325) {
            var _scratch2329 = out.scratch();
            _scratch2329.text(_key2327);
            var _vscratch2331 = out.scratch();
            _vscratch2331.unsigned(_news2325[_key2327].count);
            for (var _item2332 in _news2325[_key2327]) {
                _vscratch2331.flag(_item2332);
            }
            _keys2328.append((_scratch2329.finish(), _vscratch2331.finish(), _key2327));
        }
        _keys2328.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2328.count);
        for (var (_bytes2330, _, _key2327) in _keys2328) {
            out.text(_key2327);
            out.unsigned(_news2325[_key2327].count);
            for (var _item2333 in _news2325[_key2327]) {
                out.flag(_item2333);
            }
        }
        for (var (_okey2334, _) in _news2325) {
            var _own2335 = RecordOut();
            _own2335.blank_bodies = true;
            _own2335.blank_locs = true;
            _own2335.pending_as_bytes = true;
            _own2335.text(_okey2334);
            _own2335.unsigned(_news2325[_okey2334].count);
            for (var _item2336 in _news2325[_okey2334]) {
                _own2335.flag(_item2336);
            }
            base.own("caller_copies", interface_text(_own2335));
        }
    } else {
        out.unsigned(0);
        var _keys2338 = Array<(u8[], u8[], String)>();
        for (var (_key2337, _) in value.caller_copies) {
            var _scratch2339 = out.scratch();
            _scratch2339.text(_key2337);
            var _vscratch2341 = out.scratch();
            _vscratch2341.unsigned(value.caller_copies[_key2337].count);
            for (var _item2342 in value.caller_copies[_key2337]) {
                _vscratch2341.flag(_item2342);
            }
            _keys2338.append((_scratch2339.finish(), _vscratch2341.finish(), _key2337));
        }
        _keys2338.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2338.count);
        for (var (_bytes2340, _, _key2337) in _keys2338) {
            out.text(_key2337);
            out.unsigned(value.caller_copies[_key2337].count);
            for (var _item2343 in value.caller_copies[_key2337]) {
                out.flag(_item2343);
            }
        }
        for (var (_okey2344, _) in value.caller_copies) {
            var _own2345 = RecordOut();
            _own2345.blank_bodies = true;
            _own2345.blank_locs = true;
            _own2345.pending_as_bytes = true;
            _own2345.text(_okey2344);
            _own2345.unsigned(value.caller_copies[_okey2344].count);
            for (var _item2346 in value.caller_copies[_okey2344]) {
                _own2345.flag(_item2346);
            }
            base.own("caller_copies", interface_text(_own2345));
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
    var _f1493 = Array<ast.Import>();
    var _mode1496 = input.unsigned();
    if (_mode1496 == 2) {
        var _changed1482 = HashMap<ulong, ast.Import>();
        ulong _bi1497 = 0;
        var _n1494 = input.count();
        for (var _ in 0.._n1494) {
            var _at1498 = input.unsigned();
            while (_f1493.count < _at1498 or (input.merging and _bi1497 < base.imports.count)) {
                var _c = _changed1482.try_get(_bi1497);
                _f1493.append(_c.is_value() ? _c.value() : base.imports[_bi1497]);
                _bi1497 += 1;
            }
            _f1493.append(_a_Import_read(input));
        }
        while (_bi1497 < base.imports.count) {
            var _c = _changed1482.try_get(_bi1497);
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
    var _f1526 = Array<StructDef>();
    var _mode1529 = input.unsigned();
    if (_mode1529 == 2) {
        var _patched1532 = HashMap<ulong, StructDef>();
        var _n1527 = input.count();
        for (var _ in 0.._n1527) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1532[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1530 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1531 = input.unsigned();
            while (_f1526.count < _at1531 or (input.merging and _bi1530 < base.structs.count)) {
                var _p = _patched1532.try_get(_bi1530);
                _f1526.append(_p.is_value() ? _p.value() : base.structs[_bi1530]);
                _bi1530 += 1;
            }
            _f1526.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1530 < base.structs.count) {
            var _p = _patched1532.try_get(_bi1530);
            _f1526.append(_p.is_value() ? _p.value() : base.structs[_bi1530]);
            _bi1530 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1527 = input.count();
        for (var _ in 0.._n1527) {
            var _tag1528 = input.unsigned();
            if (_tag1528 & 1 == 1) {
                _f1526.append(base.structs[(_tag1528 >> 1) < base.structs.count ? _tag1528 >> 1 : 0]);
            } else if (_tag1528 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1526.append(_patch_s_read(input, _was));
            } else {
                _f1526.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1546 = Array<TraitDef>();
    var _mode1549 = input.unsigned();
    if (_mode1549 == 2) {
        var _changed1535 = HashMap<ulong, TraitDef>();
        ulong _bi1550 = 0;
        var _n1547 = input.count();
        for (var _ in 0.._n1547) {
            var _at1551 = input.unsigned();
            while (_f1546.count < _at1551 or (input.merging and _bi1550 < base.traits.count)) {
                var _c = _changed1535.try_get(_bi1550);
                _f1546.append(_c.is_value() ? _c.value() : base.traits[_bi1550]);
                _bi1550 += 1;
            }
            _f1546.append(_m_TraitDef_read(input));
        }
        while (_bi1550 < base.traits.count) {
            var _c = _changed1535.try_get(_bi1550);
            _f1546.append(_c.is_value() ? _c.value() : base.traits[_bi1550]);
            _bi1550 += 1;
        }
    } else if (_mode1549 == 3) {
        var _n1547 = input.count();
        for (var _ in 0.._n1547) {
            _f1546.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1547 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1547) {
            var _tag1548 = input.unsigned();
            if (_tag1548 & 1 == 1) {
                if (!input.merging) {
                    _f1546.append(base.traits[_tag1548 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1546.append(_read);
                }
            }
        }
    }
    var _f1565 = Array<ExtensionDef>();
    var _mode1568 = input.unsigned();
    if (_mode1568 == 2) {
        var _changed1554 = HashMap<ulong, ExtensionDef>();
        ulong _bi1569 = 0;
        var _n1566 = input.count();
        for (var _ in 0.._n1566) {
            var _at1570 = input.unsigned();
            while (_f1565.count < _at1570 or (input.merging and _bi1569 < base.extensions.count)) {
                var _c = _changed1554.try_get(_bi1569);
                _f1565.append(_c.is_value() ? _c.value() : base.extensions[_bi1569]);
                _bi1569 += 1;
            }
            _f1565.append(_m_ExtensionDef_read(input));
        }
        while (_bi1569 < base.extensions.count) {
            var _c = _changed1554.try_get(_bi1569);
            _f1565.append(_c.is_value() ? _c.value() : base.extensions[_bi1569]);
            _bi1569 += 1;
        }
    } else if (_mode1568 == 3) {
        var _n1566 = input.count();
        for (var _ in 0.._n1566) {
            _f1565.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1566 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1566) {
            var _tag1567 = input.unsigned();
            if (_tag1567 & 1 == 1) {
                if (!input.merging) {
                    _f1565.append(base.extensions[_tag1567 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1565.append(_read);
                }
            }
        }
    }
    var _f1584 = Array<FunctionDef>();
    var _mode1587 = input.unsigned();
    if (_mode1587 == 2) {
        var _changed1573 = HashMap<ulong, FunctionDef>();
        var _nc1575 = input.count();
        for (var _ in 0.._nc1575) {
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
                _changed1573[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1588 = 0;
        var _n1585 = input.count();
        for (var _ in 0.._n1585) {
            var _at1589 = input.unsigned();
            while (_f1584.count < _at1589 or (input.merging and _bi1588 < base.functions.count)) {
                var _c = _changed1573.try_get(_bi1588);
                _f1584.append(_c.is_value() ? _c.value() : base.functions[_bi1588]);
                _bi1588 += 1;
            }
            _f1584.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1588 < base.functions.count) {
            var _c = _changed1573.try_get(_bi1588);
            _f1584.append(_c.is_value() ? _c.value() : base.functions[_bi1588]);
            _bi1588 += 1;
        }
    } else if (_mode1587 == 3) {
        var _n1585 = input.count();
        for (var _ in 0.._n1585) {
            _f1584.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1585 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1585) {
            var _tag1586 = input.unsigned();
            if (_tag1586 & 1 == 1) {
                if (!input.merging) {
                    _f1584.append(base.functions[_tag1586 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1584.append(_read);
                }
            }
        }
    }
    var _f1603 = Array<ExternDef>();
    var _mode1606 = input.unsigned();
    if (_mode1606 == 2) {
        var _changed1592 = HashMap<ulong, ExternDef>();
        ulong _bi1607 = 0;
        var _n1604 = input.count();
        for (var _ in 0.._n1604) {
            var _at1608 = input.unsigned();
            while (_f1603.count < _at1608 or (input.merging and _bi1607 < base.externs.count)) {
                var _c = _changed1592.try_get(_bi1607);
                _f1603.append(_c.is_value() ? _c.value() : base.externs[_bi1607]);
                _bi1607 += 1;
            }
            _f1603.append(_m_ExternDef_read(input));
        }
        while (_bi1607 < base.externs.count) {
            var _c = _changed1592.try_get(_bi1607);
            _f1603.append(_c.is_value() ? _c.value() : base.externs[_bi1607]);
            _bi1607 += 1;
        }
    } else if (_mode1606 == 3) {
        var _n1604 = input.count();
        for (var _ in 0.._n1604) {
            _f1603.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1604 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1604) {
            var _tag1605 = input.unsigned();
            if (_tag1605 & 1 == 1) {
                if (!input.merging) {
                    _f1603.append(base.externs[_tag1605 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1603.append(_read);
                }
            }
        }
    }
    var _f1622 = Array<VariableDef>();
    var _mode1625 = input.unsigned();
    if (_mode1625 == 2) {
        var _changed1611 = HashMap<ulong, VariableDef>();
        ulong _bi1626 = 0;
        var _n1623 = input.count();
        for (var _ in 0.._n1623) {
            var _at1627 = input.unsigned();
            while (_f1622.count < _at1627 or (input.merging and _bi1626 < base.globals.count)) {
                var _c = _changed1611.try_get(_bi1626);
                _f1622.append(_c.is_value() ? _c.value() : base.globals[_bi1626]);
                _bi1626 += 1;
            }
            _f1622.append(_m_VariableDef_read(input));
        }
        while (_bi1626 < base.globals.count) {
            var _c = _changed1611.try_get(_bi1626);
            _f1622.append(_c.is_value() ? _c.value() : base.globals[_bi1626]);
            _bi1626 += 1;
        }
    } else if (_mode1625 == 3) {
        var _n1623 = input.count();
        for (var _ in 0.._n1623) {
            _f1622.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1623 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1623) {
            var _tag1624 = input.unsigned();
            if (_tag1624 & 1 == 1) {
                if (!input.merging) {
                    _f1622.append(base.globals[_tag1624 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1622.append(_read);
                }
            }
        }
    }
    var _f1641 = Array<ModuleStaticBlock>();
    var _mode1644 = input.unsigned();
    if (_mode1644 == 2) {
        var _changed1630 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1645 = 0;
        var _n1642 = input.count();
        for (var _ in 0.._n1642) {
            var _at1646 = input.unsigned();
            while (_f1641.count < _at1646 or (input.merging and _bi1645 < base.static_blocks.count)) {
                var _c = _changed1630.try_get(_bi1645);
                _f1641.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1645]);
                _bi1645 += 1;
            }
            _f1641.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1645 < base.static_blocks.count) {
            var _c = _changed1630.try_get(_bi1645);
            _f1641.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1645]);
            _bi1645 += 1;
        }
    } else if (_mode1644 == 3) {
        var _n1642 = input.count();
        for (var _ in 0.._n1642) {
            _f1641.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1642 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1642) {
            var _tag1643 = input.unsigned();
            if (_tag1643 & 1 == 1) {
                if (!input.merging) {
                    _f1641.append(base.static_blocks[_tag1643 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1641.append(_read);
                }
            }
        }
    }
    var _f1660 = Array<EnumDef>();
    var _mode1663 = input.unsigned();
    if (_mode1663 == 2) {
        var _changed1649 = HashMap<ulong, EnumDef>();
        ulong _bi1664 = 0;
        var _n1661 = input.count();
        for (var _ in 0.._n1661) {
            var _at1665 = input.unsigned();
            while (_f1660.count < _at1665 or (input.merging and _bi1664 < base.enums.count)) {
                var _c = _changed1649.try_get(_bi1664);
                _f1660.append(_c.is_value() ? _c.value() : base.enums[_bi1664]);
                _bi1664 += 1;
            }
            _f1660.append(_m_EnumDef_read(input));
        }
        while (_bi1664 < base.enums.count) {
            var _c = _changed1649.try_get(_bi1664);
            _f1660.append(_c.is_value() ? _c.value() : base.enums[_bi1664]);
            _bi1664 += 1;
        }
    } else if (_mode1663 == 3) {
        var _n1661 = input.count();
        for (var _ in 0.._n1661) {
            _f1660.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1661 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1661) {
            var _tag1662 = input.unsigned();
            if (_tag1662 & 1 == 1) {
                if (!input.merging) {
                    _f1660.append(base.enums[_tag1662 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1660.append(_read);
                }
            }
        }
    }
    var _f1679 = Array<TypeName>();
    var _mode1682 = input.unsigned();
    if (_mode1682 == 2) {
        var _changed1668 = HashMap<ulong, TypeName>();
        ulong _bi1683 = 0;
        var _n1680 = input.count();
        for (var _ in 0.._n1680) {
            var _at1684 = input.unsigned();
            while (_f1679.count < _at1684 or (input.merging and _bi1683 < base.struct_specs.count)) {
                var _c = _changed1668.try_get(_bi1683);
                _f1679.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1683]);
                _bi1683 += 1;
            }
            _f1679.append(_m_TypeName_read(input));
        }
        while (_bi1683 < base.struct_specs.count) {
            var _c = _changed1668.try_get(_bi1683);
            _f1679.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1683]);
            _bi1683 += 1;
        }
    } else if (_mode1682 == 3) {
        var _n1680 = input.count();
        for (var _ in 0.._n1680) {
            _f1679.append(_m_TypeName_read(input));
        }
    } else {
        var _n1680 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1680) {
            var _tag1681 = input.unsigned();
            if (_tag1681 & 1 == 1) {
                if (!input.merging) {
                    _f1679.append(base.struct_specs[_tag1681 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1679.append(_read);
                }
            }
        }
    }
    var _f1698 = Array<TypeName>();
    var _mode1701 = input.unsigned();
    if (_mode1701 == 2) {
        var _changed1687 = HashMap<ulong, TypeName>();
        ulong _bi1702 = 0;
        var _n1699 = input.count();
        for (var _ in 0.._n1699) {
            var _at1703 = input.unsigned();
            while (_f1698.count < _at1703 or (input.merging and _bi1702 < base.func_specs.count)) {
                var _c = _changed1687.try_get(_bi1702);
                _f1698.append(_c.is_value() ? _c.value() : base.func_specs[_bi1702]);
                _bi1702 += 1;
            }
            _f1698.append(_m_TypeName_read(input));
        }
        while (_bi1702 < base.func_specs.count) {
            var _c = _changed1687.try_get(_bi1702);
            _f1698.append(_c.is_value() ? _c.value() : base.func_specs[_bi1702]);
            _bi1702 += 1;
        }
    } else if (_mode1701 == 3) {
        var _n1699 = input.count();
        for (var _ in 0.._n1699) {
            _f1698.append(_m_TypeName_read(input));
        }
    } else {
        var _n1699 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1699) {
            var _tag1700 = input.unsigned();
            if (_tag1700 & 1 == 1) {
                if (!input.merging) {
                    _f1698.append(base.func_specs[_tag1700 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1698.append(_read);
                }
            }
        }
    }
    var _f1710 = Array<TypeAliasDef>();
    var _n1711 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1710.append(_b);
        }
    }
    for (var _ in 0.._n1711) {
        var _tag1712 = input.unsigned();
        if (_tag1712 & 1 == 1) {
            if (!input.merging) {
                _f1710.append(base.type_aliases[_tag1712 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1710.append(_read);
            }
        }
    }
    var _f1726 = Array<Withheld>();
    var _mode1729 = input.unsigned();
    if (_mode1729 == 2) {
        var _changed1715 = HashMap<ulong, Withheld>();
        ulong _bi1730 = 0;
        var _n1727 = input.count();
        for (var _ in 0.._n1727) {
            var _at1731 = input.unsigned();
            while (_f1726.count < _at1731 or (input.merging and _bi1730 < base.withheld.count)) {
                var _c = _changed1715.try_get(_bi1730);
                _f1726.append(_c.is_value() ? _c.value() : base.withheld[_bi1730]);
                _bi1730 += 1;
            }
            _f1726.append(_m_Withheld_read(input));
        }
        while (_bi1730 < base.withheld.count) {
            var _c = _changed1715.try_get(_bi1730);
            _f1726.append(_c.is_value() ? _c.value() : base.withheld[_bi1730]);
            _bi1730 += 1;
        }
    } else if (_mode1729 == 3) {
        var _n1727 = input.count();
        for (var _ in 0.._n1727) {
            _f1726.append(_m_Withheld_read(input));
        }
    } else {
        var _n1727 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1727) {
            var _tag1728 = input.unsigned();
            if (_tag1728 & 1 == 1) {
                if (!input.merging) {
                    _f1726.append(base.withheld[_tag1728 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1726.append(_read);
                }
            }
        }
    }
    var _f1745 = Array<PropertyDef>();
    var _mode1748 = input.unsigned();
    if (_mode1748 == 2) {
        var _changed1734 = HashMap<ulong, PropertyDef>();
        ulong _bi1749 = 0;
        var _n1746 = input.count();
        for (var _ in 0.._n1746) {
            var _at1750 = input.unsigned();
            while (_f1745.count < _at1750 or (input.merging and _bi1749 < base.properties.count)) {
                var _c = _changed1734.try_get(_bi1749);
                _f1745.append(_c.is_value() ? _c.value() : base.properties[_bi1749]);
                _bi1749 += 1;
            }
            _f1745.append(_m_PropertyDef_read(input));
        }
        while (_bi1749 < base.properties.count) {
            var _c = _changed1734.try_get(_bi1749);
            _f1745.append(_c.is_value() ? _c.value() : base.properties[_bi1749]);
            _bi1749 += 1;
        }
    } else if (_mode1748 == 3) {
        var _n1746 = input.count();
        for (var _ in 0.._n1746) {
            _f1745.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1746 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1746) {
            var _tag1747 = input.unsigned();
            if (_tag1747 & 1 == 1) {
                if (!input.merging) {
                    _f1745.append(base.properties[_tag1747 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1745.append(_read);
                }
            }
        }
    }
    var _f1764 = Array<TypeUse>();
    var _mode1767 = input.unsigned();
    if (_mode1767 == 2) {
        var _changed1753 = HashMap<ulong, TypeUse>();
        ulong _bi1768 = 0;
        var _n1765 = input.count();
        for (var _ in 0.._n1765) {
            var _at1769 = input.unsigned();
            while (_f1764.count < _at1769 or (input.merging and _bi1768 < base.type_uses.count)) {
                var _c = _changed1753.try_get(_bi1768);
                _f1764.append(_c.is_value() ? _c.value() : base.type_uses[_bi1768]);
                _bi1768 += 1;
            }
            _f1764.append(_m_TypeUse_read(input));
        }
        while (_bi1768 < base.type_uses.count) {
            var _c = _changed1753.try_get(_bi1768);
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
    var _f1783 = Array<UseContext>();
    var _mode1786 = input.unsigned();
    if (_mode1786 == 2) {
        var _changed1772 = HashMap<ulong, UseContext>();
        ulong _bi1787 = 0;
        var _n1784 = input.count();
        for (var _ in 0.._n1784) {
            var _at1788 = input.unsigned();
            while (_f1783.count < _at1788 or (input.merging and _bi1787 < base.use_contexts.count)) {
                var _c = _changed1772.try_get(_bi1787);
                _f1783.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1787]);
                _bi1787 += 1;
            }
            _f1783.append(_m_UseContext_read(input));
        }
        while (_bi1787 < base.use_contexts.count) {
            var _c = _changed1772.try_get(_bi1787);
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
    var _f1833 = Array<TypeAliasDef>();
    var _mode1836 = input.unsigned();
    if (_mode1836 == 2) {
        var _changed1822 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1837 = 0;
        var _n1834 = input.count();
        for (var _ in 0.._n1834) {
            var _at1838 = input.unsigned();
            while (_f1833.count < _at1838 or (input.merging and _bi1837 < base.constrained_aliases.count)) {
                var _c = _changed1822.try_get(_bi1837);
                _f1833.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1837]);
                _bi1837 += 1;
            }
            _f1833.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1837 < base.constrained_aliases.count) {
            var _c = _changed1822.try_get(_bi1837);
            _f1833.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1837]);
            _bi1837 += 1;
        }
    } else if (_mode1836 == 3) {
        var _n1834 = input.count();
        for (var _ in 0.._n1834) {
            _f1833.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1834 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1834) {
            var _tag1835 = input.unsigned();
            if (_tag1835 & 1 == 1) {
                if (!input.merging) {
                    _f1833.append(base.constrained_aliases[_tag1835 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1833.append(_read);
                }
            }
        }
    }
    var _f1852 = Array<TraitType>();
    var _mode1855 = input.unsigned();
    if (_mode1855 == 2) {
        var _changed1841 = HashMap<ulong, TraitType>();
        ulong _bi1856 = 0;
        var _n1853 = input.count();
        for (var _ in 0.._n1853) {
            var _at1857 = input.unsigned();
            while (_f1852.count < _at1857 or (input.merging and _bi1856 < base.trait_types.count)) {
                var _c = _changed1841.try_get(_bi1856);
                _f1852.append(_c.is_value() ? _c.value() : base.trait_types[_bi1856]);
                _bi1856 += 1;
            }
            _f1852.append(_m_TraitType_read(input));
        }
        while (_bi1856 < base.trait_types.count) {
            var _c = _changed1841.try_get(_bi1856);
            _f1852.append(_c.is_value() ? _c.value() : base.trait_types[_bi1856]);
            _bi1856 += 1;
        }
    } else if (_mode1855 == 3) {
        var _n1853 = input.count();
        for (var _ in 0.._n1853) {
            _f1852.append(_m_TraitType_read(input));
        }
    } else {
        var _n1853 = input.count();
        if (input.merging) {
            input.error = "trait_types" + " written by place";
        }
        for (var _ in 0.._n1853) {
            var _tag1854 = input.unsigned();
            if (_tag1854 & 1 == 1) {
                if (!input.merging) {
                    _f1852.append(base.trait_types[_tag1854 >> 1]);
                }
            } else {
                var _read = _m_TraitType_read(input);
                if (!input.merging or true) {
                    _f1852.append(_read);
                }
            }
        }
    }
    var _v1863 = Array<Conversion>();
    var _n1864 = input.count();
    for (var _ in 0.._n1864) {
        _v1863.append(_m_Conversion_read(input));
    }
    var _f1865 = _v1863;
    var _f1892 = Map<String, Array<String>>();
    var _tag1893 = input.unsigned();
    if (_tag1893 == 1) {
        for (var (_bk1894, _bv) in base.overload_sets) {
            _f1892[_bk1894] = _bv;
        }
        var _v1895 = Map<String, Array<String>>();
        var _n1896 = input.count();
        for (var _ in 0.._n1896) {
            var _k1897 = input.text();
            var _v1898 = Array<String>();
            var _n1899 = input.count();
            for (var _ in 0.._n1899) {
                _v1898.append(input.text());
            }
            _v1895[_k1897] = _v1898;
        }
        for (var (_bk1894, _av) in _v1895) {
            _f1892[_bk1894] = _av;
        }
    } else {
        var _v1900 = Map<String, Array<String>>();
        var _n1901 = input.count();
        for (var _ in 0.._n1901) {
            var _k1902 = input.text();
            var _v1903 = Array<String>();
            var _n1904 = input.count();
            for (var _ in 0.._n1904) {
                _v1903.append(input.text());
            }
            _v1900[_k1902] = _v1903;
        }
        _f1892 = _v1900;
    }
    var _f1939 = Map<String, Array<Array<String>>>();
    var _tag1940 = input.unsigned();
    if (_tag1940 == 1) {
        for (var (_bk1941, _bv) in base.overload_unions) {
            _f1939[_bk1941] = _bv;
        }
        var _v1942 = Map<String, Array<Array<String>>>();
        var _n1943 = input.count();
        for (var _ in 0.._n1943) {
            var _k1944 = input.text();
            var _v1945 = Array<Array<String>>();
            var _n1946 = input.count();
            for (var _ in 0.._n1946) {
                var _v1947 = Array<String>();
                var _n1948 = input.count();
                for (var _ in 0.._n1948) {
                    _v1947.append(input.text());
                }
                _v1945.append(_v1947);
            }
            _v1942[_k1944] = _v1945;
        }
        for (var (_bk1941, _av) in _v1942) {
            _f1939[_bk1941] = _av;
        }
    } else {
        var _v1949 = Map<String, Array<Array<String>>>();
        var _n1950 = input.count();
        for (var _ in 0.._n1950) {
            var _k1951 = input.text();
            var _v1952 = Array<Array<String>>();
            var _n1953 = input.count();
            for (var _ in 0.._n1953) {
                var _v1954 = Array<String>();
                var _n1955 = input.count();
                for (var _ in 0.._n1955) {
                    _v1954.append(input.text());
                }
                _v1952.append(_v1954);
            }
            _v1949[_k1951] = _v1952;
        }
        _f1939 = _v1949;
    }
    var _f2026 = Map<String, Map<String, Array<String>>>();
    var _tag2027 = input.unsigned();
    if (_tag2027 == 1) {
        for (var (_bk2028, _bv) in base.method_overload_sets) {
            _f2026[_bk2028] = _bv;
        }
        var _v2029 = Map<String, Map<String, Array<String>>>();
        var _n2030 = input.count();
        for (var _ in 0.._n2030) {
            var _k2031 = input.text();
            var _v2032 = Map<String, Array<String>>();
            var _n2033 = input.count();
            for (var _ in 0.._n2033) {
                var _k2034 = input.text();
                var _v2035 = Array<String>();
                var _n2036 = input.count();
                for (var _ in 0.._n2036) {
                    _v2035.append(input.text());
                }
                _v2032[_k2034] = _v2035;
            }
            _v2029[_k2031] = _v2032;
        }
        for (var (_bk2028, _av) in _v2029) {
            _f2026[_bk2028] = _av;
        }
    } else {
        var _v2037 = Map<String, Map<String, Array<String>>>();
        var _n2038 = input.count();
        for (var _ in 0.._n2038) {
            var _k2039 = input.text();
            var _v2040 = Map<String, Array<String>>();
            var _n2041 = input.count();
            for (var _ in 0.._n2041) {
                var _k2042 = input.text();
                var _v2043 = Array<String>();
                var _n2044 = input.count();
                for (var _ in 0.._n2044) {
                    _v2043.append(input.text());
                }
                _v2040[_k2042] = _v2043;
            }
            _v2037[_k2039] = _v2040;
        }
        _f2026 = _v2037;
    }
    var _f2052 = _m_ExtensionScopes_read(input);
    var _f2072 = HashSet<Loc>();
    var _tag2073 = input.unsigned();
    if (_tag2073 == 1) {
        for (var _bk2074 in base.private_functions) {
            _f2072.insert(_bk2074);
        }
        var _v2075 = HashSet<Loc>();
        var _n2076 = input.count();
        for (var _ in 0.._n2076) {
            _v2075.insert(input.loc());
        }
        for (var _bk2074 in _v2075) {
            _f2072.insert(_bk2074);
        }
    } else {
        var _v2077 = HashSet<Loc>();
        var _n2078 = input.count();
        for (var _ in 0.._n2078) {
            _v2077.insert(input.loc());
        }
        _f2072 = _v2077;
    }
    var _f2098 = HashSet<Loc>();
    var _tag2099 = input.unsigned();
    if (_tag2099 == 1) {
        for (var _bk2100 in base.file_private_functions) {
            _f2098.insert(_bk2100);
        }
        var _v2101 = HashSet<Loc>();
        var _n2102 = input.count();
        for (var _ in 0.._n2102) {
            _v2101.insert(input.loc());
        }
        for (var _bk2100 in _v2101) {
            _f2098.insert(_bk2100);
        }
    } else {
        var _v2103 = HashSet<Loc>();
        var _n2104 = input.count();
        for (var _ in 0.._n2104) {
            _v2103.insert(input.loc());
        }
        _f2098 = _v2103;
    }
    var _f2116 = Array<(Loc, String)>();
    var _tag2117 = input.unsigned();
    if (_tag2117 == 1) {
        input.unsigned();
        for (var _i2108 in 0..base.call_targets.count) {
            _f2116.append(base.call_targets[_i2108]);
        }
        var _more2119 = input.count();
        for (var _ in 0.._more2119) {
            var _t2120 = input.loc();
            var _t2121 = input.text();
            _f2116.append((_t2120, _t2121));
        }
    } else {
        var _v2122 = Array<(Loc, String)>();
        var _n2123 = input.count();
        for (var _ in 0.._n2123) {
            var _t2124 = input.loc();
            var _t2125 = input.text();
            _v2122.append((_t2124, _t2125));
        }
        _f2116 = _v2122;
    }
    var _f2142 = Array<(Loc, String)>();
    var _tag2143 = input.unsigned();
    if (_tag2143 == 1) {
        var _v2144 = Array<(Loc, String)>();
        var _n2145 = input.count();
        for (var _ in 0.._n2145) {
            var _t2146 = input.loc();
            var _t2147 = input.text();
            _v2144.append((_t2146, _t2147));
        }
        _f2142 = merge_by_place(base.argument_names, _v2144);
    } else {
        var _v2148 = Array<(Loc, String)>();
        var _n2149 = input.count();
        for (var _ in 0.._n2149) {
            var _t2150 = input.loc();
            var _t2151 = input.text();
            _v2148.append((_t2150, _t2151));
        }
        _f2142 = _v2148;
    }
    var _f2161 = Array<String>();
    var _tag2162 = input.unsigned();
    if (_tag2162 == 1) {
        input.unsigned();
        for (var _i2157 in 0..base.namespaces.count) {
            _f2161.append(base.namespaces[_i2157]);
        }
        var _more2164 = input.count();
        for (var _ in 0.._more2164) {
            _f2161.append(input.text());
        }
    } else {
        var _v2165 = Array<String>();
        var _n2166 = input.count();
        for (var _ in 0.._n2166) {
            _v2165.append(input.text());
        }
        _f2161 = _v2165;
    }
    var _f2174 = Array<bool>();
    var _tag2175 = input.unsigned();
    if (_tag2175 == 1) {
        input.unsigned();
        for (var _i2172 in 0..base.cached_files.count) {
            _f2174.append(base.cached_files[_i2172]);
        }
        var _more2177 = input.count();
        for (var _ in 0.._more2177) {
            _f2174.append(input.flag());
        }
    } else {
        var _v2178 = Array<bool>();
        var _n2179 = input.count();
        for (var _ in 0.._n2179) {
            _v2178.append(input.flag());
        }
        _f2174 = _v2178;
    }
    var _f2197 = HashMap<Loc, String>();
    var _tag2198 = input.unsigned();
    if (_tag2198 == 1) {
        for (var (_bk2199, _bv) in base.recorded_summaries) {
            _f2197[_bk2199] = _bv;
        }
        var _v2200 = HashMap<Loc, String>();
        var _n2201 = input.count();
        for (var _ in 0.._n2201) {
            var _k2202 = input.loc();
            _v2200[_k2202] = input.text();
        }
        for (var (_bk2199, _av) in _v2200) {
            _f2197[_bk2199] = _av;
        }
    } else {
        var _v2203 = HashMap<Loc, String>();
        var _n2204 = input.count();
        for (var _ in 0.._n2204) {
            var _k2205 = input.loc();
            _v2203[_k2205] = input.text();
        }
        _f2197 = _v2203;
    }
    var _f2221 = HashSet<Loc>();
    var _tag2222 = input.unsigned();
    if (_tag2222 == 1) {
        for (var _bk2223 in base.stripped) {
            _f2221.insert(_bk2223);
        }
        var _v2224 = HashSet<Loc>();
        var _n2225 = input.count();
        for (var _ in 0.._n2225) {
            _v2224.insert(input.loc());
        }
        for (var _bk2223 in _v2224) {
            _f2221.insert(_bk2223);
        }
    } else {
        var _v2226 = HashSet<Loc>();
        var _n2227 = input.count();
        for (var _ in 0.._n2227) {
            _v2226.insert(input.loc());
        }
        _f2221 = _v2226;
    }
    var _frozen = input.flag();
    var _f2238 = Array<StructDef>();
    var _mode2241 = input.unsigned();
    if (_mode2241 == 2) {
        var _patched2244 = HashMap<ulong, StructDef>();
        var _n2239 = input.count();
        for (var _ in 0.._n2239) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2244[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2242 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2243 = input.unsigned();
            while (_f2238.count < _at2243 or (input.merging and _bi2242 < base.templates.structs.count)) {
                var _p = _patched2244.try_get(_bi2242);
                _f2238.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2242]);
                _bi2242 += 1;
            }
            _f2238.append(_m_StructDef_read(input));
        }
        while (_bi2242 < base.templates.structs.count) {
            var _p = _patched2244.try_get(_bi2242);
            _f2238.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2242]);
            _bi2242 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2239 = input.count();
        for (var _ in 0.._n2239) {
            var _tag2240 = input.unsigned();
            if (_tag2240 & 1 == 1) {
                _f2238.append(
                    base.templates.structs[(_tag2240 >> 1) < base.templates.structs.count ? _tag2240 >> 1 : 0]
                );
            } else if (_tag2240 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2238.append(_patch_t_read(input, _was));
            } else {
                _f2238.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2258 = Array<FunctionDef>();
    var _mode2261 = input.unsigned();
    if (_mode2261 == 2) {
        var _changed2247 = HashMap<ulong, FunctionDef>();
        var _nc2249 = input.count();
        for (var _ in 0.._nc2249) {
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
                _changed2247[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2262 = 0;
        var _n2259 = input.count();
        for (var _ in 0.._n2259) {
            var _at2263 = input.unsigned();
            while (_f2258.count < _at2263 or (input.merging and _bi2262 < base.templates.functions.count)) {
                var _c = _changed2247.try_get(_bi2262);
                _f2258.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2262]);
                _bi2262 += 1;
            }
            _f2258.append(_m_FunctionDef_read(input));
        }
        while (_bi2262 < base.templates.functions.count) {
            var _c = _changed2247.try_get(_bi2262);
            _f2258.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2262]);
            _bi2262 += 1;
        }
    } else if (_mode2261 == 3) {
        var _n2259 = input.count();
        for (var _ in 0.._n2259) {
            _f2258.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2259 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2259) {
            var _tag2260 = input.unsigned();
            if (_tag2260 & 1 == 1) {
                if (!input.merging) {
                    _f2258.append(base.templates.functions[_tag2260 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2258.append(_read);
                }
            }
        }
    }
    var _f2265 = Templates(_frozen, _f2238, _f2258);
    var _f2266 = DeltaBase.read_checked(input, base.checked);
    var _f2286 = HashMap<String, SpecRequest>();
    var _tag2287 = input.unsigned();
    if (_tag2287 == 1) {
        for (var (_bk2288, _bv) in base.spec_requests) {
            _f2286[_bk2288] = _bv;
        }
        var _v2289 = HashMap<String, SpecRequest>();
        var _n2290 = input.count();
        for (var _ in 0.._n2290) {
            var _k2291 = input.text();
            _v2289[_k2291] = _m_SpecRequest_read(input);
        }
        for (var (_bk2288, _av) in _v2289) {
            _f2286[_bk2288] = _av;
        }
    } else {
        var _v2292 = HashMap<String, SpecRequest>();
        var _n2293 = input.count();
        for (var _ in 0.._n2293) {
            var _k2294 = input.text();
            _v2292[_k2294] = _m_SpecRequest_read(input);
        }
        _f2286 = _v2292;
    }
    var _f2295 = input.flag();
    var _f2307 = Array<(Loc, String)>();
    var _tag2308 = input.unsigned();
    if (_tag2308 == 1) {
        input.unsigned();
        for (var _i2299 in 0..base.summaries_to_record.count) {
            _f2307.append(base.summaries_to_record[_i2299]);
        }
        var _more2310 = input.count();
        for (var _ in 0.._more2310) {
            var _t2311 = input.loc();
            var _t2312 = input.text();
            _f2307.append((_t2311, _t2312));
        }
    } else {
        var _v2313 = Array<(Loc, String)>();
        var _n2314 = input.count();
        for (var _ in 0.._n2314) {
            var _t2315 = input.loc();
            var _t2316 = input.text();
            _v2313.append((_t2315, _t2316));
        }
        _f2307 = _v2313;
    }
    var _f2347 = HashMap<String, Array<bool>>();
    var _tag2348 = input.unsigned();
    if (_tag2348 == 1) {
        for (var (_bk2349, _bv) in base.caller_copies) {
            _f2347[_bk2349] = _bv;
        }
        var _v2350 = HashMap<String, Array<bool>>();
        var _n2351 = input.count();
        for (var _ in 0.._n2351) {
            var _k2352 = input.text();
            var _v2353 = Array<bool>();
            var _n2354 = input.count();
            for (var _ in 0.._n2354) {
                _v2353.append(input.flag());
            }
            _v2350[_k2352] = _v2353;
        }
        for (var (_bk2349, _av) in _v2350) {
            _f2347[_bk2349] = _av;
        }
    } else {
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
        _f2347 = _v2355;
    }
    var _f2361 = input.flag();
    return Module(
        _f1493,
        _f1526,
        _f1546,
        _f1565,
        _f1584,
        _f1603,
        _f1622,
        _f1641,
        _f1660,
        _f1679,
        _f1698,
        _f1710,
        _f1726,
        _f1745,
        _f1764,
        _f1783,
        _f1804,
        _f1833,
        _f1852,
        _f1865,
        _f1892,
        _f1939,
        _f2026,
        _f2052,
        _f2072,
        _f2098,
        _f2116,
        _f2142,
        _f2161,
        _f2174,
        _f2197,
        _f2221,
        _f2265,
        _f2266,
        _f2286,
        _f2295,
        _f2307,
        _f2347,
        _f2361
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1499 = 0;
    for (var _item1481 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1481);
        base.add("imports", scratch, _j1499);
        _j1499 += 1;
    }
    if (base.verifying) {
        ulong _j1533 = 0;
        for (var _item1500 in value.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item1500);
            base.add("s", scratch, _j1533);
            base.name("s", _item1500.name, _j1533);
            _patch_s_index(_item1500, base, _j1533);
            _j1533 += 1;
        }
    }
    base.ref_structs = value.structs.clone();
    base.ref_struct_parts = Array<StructDef>();
    for (var _item1500 in value.structs) {
        base.ref_struct_parts.append(_m_StructDef_shallow(_item1500));
    }
    ulong _j1552 = 0;
    for (var _item1534 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1534);
        base.add("traits", scratch, _j1552);
        _j1552 += 1;
    }
    ulong _j1571 = 0;
    for (var _item1553 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1553);
        base.add("extensions", scratch, _j1571);
        _j1571 += 1;
    }
    if (base.verifying) {
        ulong _j1590 = 0;
        for (var _item1572 in value.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item1572);
            base.add("functions", scratch, _j1590);
            base.name("functions", _item1572.name, _j1590);
            _j1590 += 1;
        }
    }
    base.ref_functions = value.functions.clone();
    ulong _j1609 = 0;
    for (var _item1591 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1591);
        base.add("externs", scratch, _j1609);
        _j1609 += 1;
    }
    ulong _j1628 = 0;
    for (var _item1610 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1610);
        base.add("globals", scratch, _j1628);
        _j1628 += 1;
    }
    ulong _j1647 = 0;
    for (var _item1629 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1629);
        base.add("static_blocks", scratch, _j1647);
        _j1647 += 1;
    }
    ulong _j1666 = 0;
    for (var _item1648 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1648);
        base.add("enums", scratch, _j1666);
        _j1666 += 1;
    }
    ulong _j1685 = 0;
    for (var _item1667 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1667);
        base.add("struct_specs", scratch, _j1685);
        _j1685 += 1;
    }
    ulong _j1704 = 0;
    for (var _item1686 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1686);
        base.add("func_specs", scratch, _j1704);
        _j1704 += 1;
    }
    ulong _j1713 = 0;
    for (var _item1705 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1705);
        base.add("type_aliases", scratch, _j1713);
        _j1713 += 1;
    }
    ulong _j1732 = 0;
    for (var _item1714 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1714);
        base.add("withheld", scratch, _j1732);
        _j1732 += 1;
    }
    ulong _j1751 = 0;
    for (var _item1733 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1733);
        base.add("properties", scratch, _j1751);
        _j1751 += 1;
    }
    ulong _j1770 = 0;
    for (var _item1752 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1752);
        base.add("type_uses", scratch, _j1770);
        _j1770 += 1;
    }
    ulong _j1789 = 0;
    for (var _item1771 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1771);
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
    ulong _j1839 = 0;
    for (var _item1821 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1821);
        base.add("constrained_aliases", scratch, _j1839);
        _j1839 += 1;
    }
    ulong _j1858 = 0;
    for (var _item1840 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1840);
        base.add("trait_types", scratch, _j1858);
        _j1858 += 1;
    }
    ulong _cj1862 = 0;
    for (var _conv1860 in value.conversions) {
        var _own1861 = RecordOut();
        _own1861.blank_locs = true;
        _m_Conversion_write(_own1861, _conv1860);
        base.add_hashed("conversions", interface_text(_own1861), _cj1862);
        _cj1862 += 1;
    }
    for (var (_key1866, _) in value.overload_sets) {
        var _kscratch1867 = base.scratch();
        _kscratch1867.text(_key1866);
        var _vscratch1868 = base.scratch();
        _vscratch1868.unsigned(value.overload_sets[_key1866].count);
        for (var _item1905 in value.overload_sets[_key1866]) {
            _vscratch1868.text(_item1905);
        }
        base.keep_entry("overload_sets", _kscratch1867, _vscratch1868);
    }
    for (var (_key1906, _) in value.overload_unions) {
        var _kscratch1907 = base.scratch();
        _kscratch1907.text(_key1906);
        var _vscratch1908 = base.scratch();
        _vscratch1908.unsigned(value.overload_unions[_key1906].count);
        for (var _item1956 in value.overload_unions[_key1906]) {
            _vscratch1908.unsigned(_item1956.count);
            for (var _item1957 in _item1956) {
                _vscratch1908.text(_item1957);
            }
        }
        base.keep_entry("overload_unions", _kscratch1907, _vscratch1908);
    }
    for (var (_key1958, _) in value.method_overload_sets) {
        var _kscratch1959 = base.scratch();
        _kscratch1959.text(_key1958);
        var _vscratch1960 = base.scratch();
        var _keys2046 = Array<(u8[], u8[], String)>();
        for (var (_key2045, _) in value.method_overload_sets[_key1958]) {
            var _scratch2047 = _vscratch1960.scratch();
            _scratch2047.text(_key2045);
            var _vscratch2049 = _vscratch1960.scratch();
            _vscratch2049.unsigned(value.method_overload_sets[_key1958][_key2045].count);
            for (var _item2050 in value.method_overload_sets[_key1958][_key2045]) {
                _vscratch2049.text(_item2050);
            }
            _keys2046.append((_scratch2047.finish(), _vscratch2049.finish(), _key2045));
        }
        _keys2046.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1960.unsigned(_keys2046.count);
        for (var (_bytes2048, _, _key2045) in _keys2046) {
            _vscratch1960.text(_key2045);
            _vscratch1960.unsigned(value.method_overload_sets[_key1958][_key2045].count);
            for (var _item2051 in value.method_overload_sets[_key1958][_key2045]) {
                _vscratch1960.text(_item2051);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1959, _vscratch1960);
    }
    for (var _key2053 in value.private_functions) {
        var _kscratch2054 = base.scratch();
        _kscratch2054.loc(_key2053);
        var _vscratch2055 = base.scratch();
        base.keep_entry("private_functions", _kscratch2054, _vscratch2055);
    }
    for (var _key2079 in value.file_private_functions) {
        var _kscratch2080 = base.scratch();
        _kscratch2080.loc(_key2079);
        var _vscratch2081 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch2080, _vscratch2081);
    }
    var _xscratch2126 = base.scratch();
    for (var _xitem2127 in value.call_targets) {
        var (_t2128, _t2129) = _xitem2127;
        _xscratch2126.loc(_t2128);
        _xscratch2126.text(_t2129);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2126);
    for (var _item2130 in value.argument_names) {
        var _escratch2131 = base.scratch();
        var (_t2152, _t2153) = _item2130;
        _escratch2131.loc(_t2152);
        _escratch2131.text(_t2153);
        base.keep_entry("argument_names", _escratch2131, base.scratch());
    }
    var _xscratch2167 = base.scratch();
    for (var _xitem2168 in value.namespaces) {
        _xscratch2167.text(_xitem2168);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2167);
    var _xscratch2180 = base.scratch();
    for (var _xitem2181 in value.cached_files) {
        _xscratch2180.flag(_xitem2181);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2180);
    for (var (_key2182, _) in value.recorded_summaries) {
        var _kscratch2183 = base.scratch();
        _kscratch2183.loc(_key2182);
        var _vscratch2184 = base.scratch();
        _vscratch2184.text(value.recorded_summaries[_key2182]);
        base.keep_entry("recorded_summaries", _kscratch2183, _vscratch2184);
    }
    for (var _key2206 in value.stripped) {
        var _kscratch2207 = base.scratch();
        _kscratch2207.loc(_key2206);
        var _vscratch2208 = base.scratch();
        base.keep_entry("stripped", _kscratch2207, _vscratch2208);
    }
    if (base.verifying) {
        ulong _j2245 = 0;
        for (var _item2228 in value.templates.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item2228);
            base.add("t", scratch, _j2245);
            base.name("t", _item2228.name, _j2245);
            _patch_t_index(_item2228, base, _j2245);
            _j2245 += 1;
        }
    }
    base.ref_templates = value.templates.structs.clone();
    base.ref_template_parts = Array<StructDef>();
    for (var _item2228 in value.templates.structs) {
        base.ref_template_parts.append(_m_StructDef_shallow(_item2228));
    }
    if (base.verifying) {
        ulong _j2264 = 0;
        for (var _item2246 in value.templates.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2246);
            base.add("tf", scratch, _j2264);
            base.name("tf", _item2246.name, _j2264);
            _j2264 += 1;
        }
    }
    base.ref_template_functions = value.templates.functions.clone();
    base.keep_checked(value.checked);
    for (var (_key2267, _) in value.spec_requests) {
        var _kscratch2268 = base.scratch();
        _kscratch2268.text(_key2267);
        var _vscratch2269 = base.scratch();
        _m_SpecRequest_write(_vscratch2269, value.spec_requests[_key2267]);
        base.keep_entry("spec_requests", _kscratch2268, _vscratch2269);
    }
    var _xscratch2317 = base.scratch();
    for (var _xitem2318 in value.summaries_to_record) {
        var (_t2319, _t2320) = _xitem2318;
        _xscratch2317.loc(_t2319);
        _xscratch2317.text(_t2320);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2317);
    for (var (_key2321, _) in value.caller_copies) {
        var _kscratch2322 = base.scratch();
        _kscratch2322.text(_key2321);
        var _vscratch2323 = base.scratch();
        _vscratch2323.unsigned(value.caller_copies[_key2321].count);
        for (var _item2360 in value.caller_copies[_key2321]) {
            _vscratch2323.flag(_item2360);
        }
        base.keep_entry("caller_copies", _kscratch2322, _vscratch2323);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1713 = 0;
    for (var _item1705 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1705);
        base.add("type_aliases", scratch, _j1713);
        _j1713 += 1;
    }
    for (var (_key2182, _) in value.recorded_summaries) {
        var _kscratch2183 = base.scratch();
        _kscratch2183.loc(_key2182);
        var _vscratch2184 = base.scratch();
        _vscratch2184.text(value.recorded_summaries[_key2182]);
        base.keep_entry("recorded_summaries", _kscratch2183, _vscratch2184);
    }
    var _xscratch2317 = base.scratch();
    for (var _xitem2318 in value.summaries_to_record) {
        var (_t2319, _t2320) = _xitem2318;
        _xscratch2317.loc(_t2319);
        _xscratch2317.text(_t2320);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2317);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2369 = base.ref_struct_parts[slot].generic_params;
    ulong _bj2370 = 0;
    var _news2371 = Array<ulong>();
    for (var _i2372 in 0..value.generic_params.count) {
        if (_bj2370 < _seq2369.count and value.generic_params[_i2372] === _seq2369[_bj2370]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2372]);
                base.verify_same($"s.{slot}.generic_params", _bj2370, scratch);
            }
            _bj2370 += 1;
        } else if (_bj2370 < _seq2369.count
            and _same_m_GenericParam(value.generic_params[_i2372], _seq2369[_bj2370], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2372]);
                base.verify_same($"s.{slot}.generic_params", _bj2370, scratch);
            }
            _bj2370 += 1;
        } else {
            _news2371.append(_i2372);
        }
    }
    if (_bj2370 == _seq2369.count) {
        out.unsigned(2);
        out.unsigned(_news2371.count);
        for (var _i2372 in _news2371) {
            out.unsigned(_i2372);
            _m_GenericParam_write(out, value.generic_params[_i2372]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2372 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2372]);
        }
    }
    var _seq2385 = base.ref_struct_parts[slot].field_members;
    ulong _bj2386 = 0;
    var _news2387 = Array<ulong>();
    for (var _i2388 in 0..value.field_members.count) {
        if (_bj2386 < _seq2385.count and value.field_members[_i2388] === _seq2385[_bj2386]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2388]);
                base.verify_same($"s.{slot}.field_members", _bj2386, scratch);
            }
            _bj2386 += 1;
        } else if (_bj2386 < _seq2385.count
            and _same_m_VariableDef(value.field_members[_i2388], _seq2385[_bj2386], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2388]);
                base.verify_same($"s.{slot}.field_members", _bj2386, scratch);
            }
            _bj2386 += 1;
        } else {
            _news2387.append(_i2388);
        }
    }
    if (_bj2386 == _seq2385.count) {
        out.unsigned(2);
        out.unsigned(_news2387.count);
        for (var _i2388 in _news2387) {
            out.unsigned(_i2388);
            _m_VariableDef_write(out, value.field_members[_i2388]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2388 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2388]);
        }
    }
    var _seq2401 = base.ref_struct_parts[slot].method_members;
    ulong _bj2402 = 0;
    var _news2403 = Array<ulong>();
    for (var _i2404 in 0..value.method_members.count) {
        if (_bj2402 < _seq2401.count and value.method_members[_i2404] === _seq2401[_bj2402]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2404]);
                base.verify_same($"s.{slot}.method_members", _bj2402, scratch);
            }
            _bj2402 += 1;
        } else if (_bj2402 < _seq2401.count
            and _same_m_FunctionDef(value.method_members[_i2404], _seq2401[_bj2402], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2404]);
                base.verify_same($"s.{slot}.method_members", _bj2402, scratch);
            }
            _bj2402 += 1;
        } else {
            _news2403.append(_i2404);
        }
    }
    if (_bj2402 == _seq2401.count) {
        out.unsigned(2);
        out.unsigned(_news2403.count);
        for (var _i2404 in _news2403) {
            out.unsigned(_i2404);
            _m_FunctionDef_write(out, value.method_members[_i2404]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2404 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2404]);
        }
    }
    var _seq2417 = base.ref_struct_parts[slot].generic_methods;
    ulong _bj2418 = 0;
    var _news2419 = Array<ulong>();
    for (var _i2420 in 0..value.generic_methods.count) {
        if (_bj2418 < _seq2417.count and value.generic_methods[_i2420] === _seq2417[_bj2418]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2420]);
                base.verify_same($"s.{slot}.generic_methods", _bj2418, scratch);
            }
            _bj2418 += 1;
        } else if (_bj2418 < _seq2417.count
            and _same_m_FunctionDef(value.generic_methods[_i2420], _seq2417[_bj2418], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2420]);
                base.verify_same($"s.{slot}.generic_methods", _bj2418, scratch);
            }
            _bj2418 += 1;
        } else {
            _news2419.append(_i2420);
        }
    }
    if (_bj2418 == _seq2417.count) {
        out.unsigned(2);
        out.unsigned(_news2419.count);
        for (var _i2420 in _news2419) {
            out.unsigned(_i2420);
            _m_FunctionDef_write(out, value.generic_methods[_i2420]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2420 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2420]);
        }
    }
    var _seq2433 = base.ref_struct_parts[slot].constructors;
    ulong _bj2434 = 0;
    var _news2435 = Array<ulong>();
    for (var _i2436 in 0..value.constructors.count) {
        if (_bj2434 < _seq2433.count and value.constructors[_i2436] === _seq2433[_bj2434]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2436]);
                base.verify_same($"s.{slot}.constructors", _bj2434, scratch);
            }
            _bj2434 += 1;
        } else if (_bj2434 < _seq2433.count
            and _same_m_FunctionDef(value.constructors[_i2436], _seq2433[_bj2434], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2436]);
                base.verify_same($"s.{slot}.constructors", _bj2434, scratch);
            }
            _bj2434 += 1;
        } else {
            _news2435.append(_i2436);
        }
    }
    if (_bj2434 == _seq2433.count) {
        out.unsigned(2);
        out.unsigned(_news2435.count);
        for (var _i2436 in _news2435) {
            out.unsigned(_i2436);
            _m_FunctionDef_write(out, value.constructors[_i2436]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2436 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2436]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2452 = base.ref_struct_parts[slot].traits;
    ulong _bj2453 = 0;
    var _news2454 = Array<ulong>();
    for (var _i2455 in 0..value.traits.count) {
        if (_bj2453 < _seq2452.count and value.traits[_i2455] === _seq2452[_bj2453]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2455]);
                base.verify_same($"s.{slot}.traits", _bj2453, scratch);
            }
            _bj2453 += 1;
        } else if (_bj2453 < _seq2452.count and _same_m_TypeName(value.traits[_i2455], _seq2452[_bj2453], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2455]);
                base.verify_same($"s.{slot}.traits", _bj2453, scratch);
            }
            _bj2453 += 1;
        } else {
            _news2454.append(_i2455);
        }
    }
    if (_bj2453 == _seq2452.count) {
        out.unsigned(2);
        out.unsigned(_news2454.count);
        for (var _i2455 in _news2454) {
            out.unsigned(_i2455);
            _m_TypeName_write(out, value.traits[_i2455]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2455 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2455]);
        }
    }
    var _seq2468 = base.ref_struct_parts[slot].attributes;
    ulong _bj2469 = 0;
    var _news2470 = Array<ulong>();
    for (var _i2471 in 0..value.attributes.count) {
        if (_bj2469 < _seq2468.count and value.attributes[_i2471] === _seq2468[_bj2469]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2471]);
                base.verify_same($"s.{slot}.attributes", _bj2469, scratch);
            }
            _bj2469 += 1;
        } else if (_bj2469 < _seq2468.count and _same_a_Attribute(value.attributes[_i2471], _seq2468[_bj2469], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2471]);
                base.verify_same($"s.{slot}.attributes", _bj2469, scratch);
            }
            _bj2469 += 1;
        } else {
            _news2470.append(_i2471);
        }
    }
    if (_bj2469 == _seq2468.count) {
        out.unsigned(2);
        out.unsigned(_news2470.count);
        for (var _i2471 in _news2470) {
            out.unsigned(_i2471);
            _a_Attribute_write(out, value.attributes[_i2471]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2471 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2471]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2480 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2480);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2362 = input.text();
    var _f2363 = _m_TypeName_read(input);
    var _f2373 = Array<GenericParam>();
    var _mode2376 = input.unsigned();
    if (_mode2376 == 2) {
        var _changed2365 = HashMap<ulong, GenericParam>();
        ulong _bi2377 = 0;
        var _n2374 = input.count();
        for (var _ in 0.._n2374) {
            var _at2378 = input.unsigned();
            while (_f2373.count < _at2378 or (input.merging and _bi2377 < was.generic_params.count)) {
                var _c = _changed2365.try_get(_bi2377);
                _f2373.append(_c.is_value() ? _c.value() : was.generic_params[_bi2377]);
                _bi2377 += 1;
            }
            _f2373.append(_m_GenericParam_read(input));
        }
        while (_bi2377 < was.generic_params.count) {
            var _c = _changed2365.try_get(_bi2377);
            _f2373.append(_c.is_value() ? _c.value() : was.generic_params[_bi2377]);
            _bi2377 += 1;
        }
    } else if (_mode2376 == 3) {
        var _n2374 = input.count();
        for (var _ in 0.._n2374) {
            _f2373.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2374 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2374) {
            var _tag2375 = input.unsigned();
            if (_tag2375 & 1 == 1) {
                if (!input.merging) {
                    _f2373.append(was.generic_params[_tag2375 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2373.append(_read);
                }
            }
        }
    }
    var _f2389 = Array<VariableDef>();
    var _mode2392 = input.unsigned();
    if (_mode2392 == 2) {
        var _changed2381 = HashMap<ulong, VariableDef>();
        ulong _bi2393 = 0;
        var _n2390 = input.count();
        for (var _ in 0.._n2390) {
            var _at2394 = input.unsigned();
            while (_f2389.count < _at2394 or (input.merging and _bi2393 < was.field_members.count)) {
                var _c = _changed2381.try_get(_bi2393);
                _f2389.append(_c.is_value() ? _c.value() : was.field_members[_bi2393]);
                _bi2393 += 1;
            }
            _f2389.append(_m_VariableDef_read(input));
        }
        while (_bi2393 < was.field_members.count) {
            var _c = _changed2381.try_get(_bi2393);
            _f2389.append(_c.is_value() ? _c.value() : was.field_members[_bi2393]);
            _bi2393 += 1;
        }
    } else if (_mode2392 == 3) {
        var _n2390 = input.count();
        for (var _ in 0.._n2390) {
            _f2389.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2390 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2390) {
            var _tag2391 = input.unsigned();
            if (_tag2391 & 1 == 1) {
                if (!input.merging) {
                    _f2389.append(was.field_members[_tag2391 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2389.append(_read);
                }
            }
        }
    }
    var _f2405 = Array<FunctionDef>();
    var _mode2408 = input.unsigned();
    if (_mode2408 == 2) {
        var _changed2397 = HashMap<ulong, FunctionDef>();
        ulong _bi2409 = 0;
        var _n2406 = input.count();
        for (var _ in 0.._n2406) {
            var _at2410 = input.unsigned();
            while (_f2405.count < _at2410 or (input.merging and _bi2409 < was.method_members.count)) {
                var _c = _changed2397.try_get(_bi2409);
                _f2405.append(_c.is_value() ? _c.value() : was.method_members[_bi2409]);
                _bi2409 += 1;
            }
            _f2405.append(_m_FunctionDef_read(input));
        }
        while (_bi2409 < was.method_members.count) {
            var _c = _changed2397.try_get(_bi2409);
            _f2405.append(_c.is_value() ? _c.value() : was.method_members[_bi2409]);
            _bi2409 += 1;
        }
    } else if (_mode2408 == 3) {
        var _n2406 = input.count();
        for (var _ in 0.._n2406) {
            _f2405.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2406 = input.count();
        if (input.merging) {
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2406) {
            var _tag2407 = input.unsigned();
            if (_tag2407 & 1 == 1) {
                if (!input.merging) {
                    _f2405.append(was.method_members[_tag2407 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2405.append(_read);
                }
            }
        }
    }
    var _f2421 = Array<FunctionDef>();
    var _mode2424 = input.unsigned();
    if (_mode2424 == 2) {
        var _changed2413 = HashMap<ulong, FunctionDef>();
        ulong _bi2425 = 0;
        var _n2422 = input.count();
        for (var _ in 0.._n2422) {
            var _at2426 = input.unsigned();
            while (_f2421.count < _at2426 or (input.merging and _bi2425 < was.generic_methods.count)) {
                var _c = _changed2413.try_get(_bi2425);
                _f2421.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2425]);
                _bi2425 += 1;
            }
            _f2421.append(_m_FunctionDef_read(input));
        }
        while (_bi2425 < was.generic_methods.count) {
            var _c = _changed2413.try_get(_bi2425);
            _f2421.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2425]);
            _bi2425 += 1;
        }
    } else if (_mode2424 == 3) {
        var _n2422 = input.count();
        for (var _ in 0.._n2422) {
            _f2421.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2422 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2422) {
            var _tag2423 = input.unsigned();
            if (_tag2423 & 1 == 1) {
                if (!input.merging) {
                    _f2421.append(was.generic_methods[_tag2423 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2421.append(_read);
                }
            }
        }
    }
    var _f2437 = Array<FunctionDef>();
    var _mode2440 = input.unsigned();
    if (_mode2440 == 2) {
        var _changed2429 = HashMap<ulong, FunctionDef>();
        ulong _bi2441 = 0;
        var _n2438 = input.count();
        for (var _ in 0.._n2438) {
            var _at2442 = input.unsigned();
            while (_f2437.count < _at2442 or (input.merging and _bi2441 < was.constructors.count)) {
                var _c = _changed2429.try_get(_bi2441);
                _f2437.append(_c.is_value() ? _c.value() : was.constructors[_bi2441]);
                _bi2441 += 1;
            }
            _f2437.append(_m_FunctionDef_read(input));
        }
        while (_bi2441 < was.constructors.count) {
            var _c = _changed2429.try_get(_bi2441);
            _f2437.append(_c.is_value() ? _c.value() : was.constructors[_bi2441]);
            _bi2441 += 1;
        }
    } else if (_mode2440 == 3) {
        var _n2438 = input.count();
        for (var _ in 0.._n2438) {
            _f2437.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2438 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2438) {
            var _tag2439 = input.unsigned();
            if (_tag2439 & 1 == 1) {
                if (!input.merging) {
                    _f2437.append(was.constructors[_tag2439 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2437.append(_read);
                }
            }
        }
    }
    var _f2444 = _m_FunctionDef_read(input);
    var _f2445 = _m_FunctionDef_read(input);
    var _f2446 = _m_FunctionDef_read(input);
    var _f2456 = Array<TypeName>();
    var _mode2459 = input.unsigned();
    if (_mode2459 == 2) {
        var _changed2448 = HashMap<ulong, TypeName>();
        ulong _bi2460 = 0;
        var _n2457 = input.count();
        for (var _ in 0.._n2457) {
            var _at2461 = input.unsigned();
            while (_f2456.count < _at2461 or (input.merging and _bi2460 < was.traits.count)) {
                var _c = _changed2448.try_get(_bi2460);
                _f2456.append(_c.is_value() ? _c.value() : was.traits[_bi2460]);
                _bi2460 += 1;
            }
            _f2456.append(_m_TypeName_read(input));
        }
        while (_bi2460 < was.traits.count) {
            var _c = _changed2448.try_get(_bi2460);
            _f2456.append(_c.is_value() ? _c.value() : was.traits[_bi2460]);
            _bi2460 += 1;
        }
    } else if (_mode2459 == 3) {
        var _n2457 = input.count();
        for (var _ in 0.._n2457) {
            _f2456.append(_m_TypeName_read(input));
        }
    } else {
        var _n2457 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2457) {
            var _tag2458 = input.unsigned();
            if (_tag2458 & 1 == 1) {
                if (!input.merging) {
                    _f2456.append(was.traits[_tag2458 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2456.append(_read);
                }
            }
        }
    }
    var _f2472 = Array<ast.Attribute>();
    var _mode2475 = input.unsigned();
    if (_mode2475 == 2) {
        var _changed2464 = HashMap<ulong, ast.Attribute>();
        ulong _bi2476 = 0;
        var _n2473 = input.count();
        for (var _ in 0.._n2473) {
            var _at2477 = input.unsigned();
            while (_f2472.count < _at2477 or (input.merging and _bi2476 < was.attributes.count)) {
                var _c = _changed2464.try_get(_bi2476);
                _f2472.append(_c.is_value() ? _c.value() : was.attributes[_bi2476]);
                _bi2476 += 1;
            }
            _f2472.append(_a_Attribute_read(input));
        }
        while (_bi2476 < was.attributes.count) {
            var _c = _changed2464.try_get(_bi2476);
            _f2472.append(_c.is_value() ? _c.value() : was.attributes[_bi2476]);
            _bi2476 += 1;
        }
    } else if (_mode2475 == 3) {
        var _n2473 = input.count();
        for (var _ in 0.._n2473) {
            _f2472.append(_a_Attribute_read(input));
        }
    } else {
        var _n2473 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2473) {
            var _tag2474 = input.unsigned();
            if (_tag2474 & 1 == 1) {
                if (!input.merging) {
                    _f2472.append(was.attributes[_tag2474 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2472.append(_read);
                }
            }
        }
    }
    var _f2479 = input.loc();
    var _o2481 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2482 = Array<EnumCaseDef>();
        var _n2483 = input.count();
        for (var _ in 0.._n2483) {
            _v2482.append(_m_EnumCaseDef_read(input));
        }
        _o2481 = Optional<Array<EnumCaseDef>>.Value(_v2482);
    }
    var _f2484 = _o2481;
    return StructDef(
        _f2362, _f2363, _f2373, _f2389, _f2405, _f2421, _f2437, _f2444, _f2445, _f2446, _f2456, _f2472, _f2479, _f2484
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2379 = 0;
        for (var _item2364 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2364);
            base.add($"s.{slot}.generic_params", scratch, _j2379);
            _j2379 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2395 = 0;
        for (var _item2380 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2380);
            base.add($"s.{slot}.field_members", scratch, _j2395);
            _j2395 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2411 = 0;
        for (var _item2396 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2396);
            base.add($"s.{slot}.method_members", scratch, _j2411);
            _j2411 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2427 = 0;
        for (var _item2412 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2412);
            base.add($"s.{slot}.generic_methods", scratch, _j2427);
            _j2427 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2443 = 0;
        for (var _item2428 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2428);
            base.add($"s.{slot}.constructors", scratch, _j2443);
            _j2443 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2462 = 0;
        for (var _item2447 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2447);
            base.add($"s.{slot}.traits", scratch, _j2462);
            _j2462 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2478 = 0;
        for (var _item2463 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2463);
            base.add($"s.{slot}.attributes", scratch, _j2478);
            _j2478 += 1;
        }
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2492 = base.ref_template_parts[slot].generic_params;
    ulong _bj2493 = 0;
    var _news2494 = Array<ulong>();
    for (var _i2495 in 0..value.generic_params.count) {
        if (_bj2493 < _seq2492.count and value.generic_params[_i2495] === _seq2492[_bj2493]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2495]);
                base.verify_same($"t.{slot}.generic_params", _bj2493, scratch);
            }
            _bj2493 += 1;
        } else if (_bj2493 < _seq2492.count
            and _same_m_GenericParam(value.generic_params[_i2495], _seq2492[_bj2493], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2495]);
                base.verify_same($"t.{slot}.generic_params", _bj2493, scratch);
            }
            _bj2493 += 1;
        } else {
            _news2494.append(_i2495);
        }
    }
    if (_bj2493 == _seq2492.count) {
        out.unsigned(2);
        out.unsigned(_news2494.count);
        for (var _i2495 in _news2494) {
            out.unsigned(_i2495);
            _m_GenericParam_write(out, value.generic_params[_i2495]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2495 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2495]);
        }
    }
    var _seq2508 = base.ref_template_parts[slot].field_members;
    ulong _bj2509 = 0;
    var _news2510 = Array<ulong>();
    for (var _i2511 in 0..value.field_members.count) {
        if (_bj2509 < _seq2508.count and value.field_members[_i2511] === _seq2508[_bj2509]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2511]);
                base.verify_same($"t.{slot}.field_members", _bj2509, scratch);
            }
            _bj2509 += 1;
        } else if (_bj2509 < _seq2508.count
            and _same_m_VariableDef(value.field_members[_i2511], _seq2508[_bj2509], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2511]);
                base.verify_same($"t.{slot}.field_members", _bj2509, scratch);
            }
            _bj2509 += 1;
        } else {
            _news2510.append(_i2511);
        }
    }
    if (_bj2509 == _seq2508.count) {
        out.unsigned(2);
        out.unsigned(_news2510.count);
        for (var _i2511 in _news2510) {
            out.unsigned(_i2511);
            _m_VariableDef_write(out, value.field_members[_i2511]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2511 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2511]);
        }
    }
    var _seq2524 = base.ref_template_parts[slot].method_members;
    ulong _bj2525 = 0;
    var _news2526 = Array<ulong>();
    for (var _i2527 in 0..value.method_members.count) {
        if (_bj2525 < _seq2524.count and value.method_members[_i2527] === _seq2524[_bj2525]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2527]);
                base.verify_same($"t.{slot}.method_members", _bj2525, scratch);
            }
            _bj2525 += 1;
        } else if (_bj2525 < _seq2524.count
            and _same_m_FunctionDef(value.method_members[_i2527], _seq2524[_bj2525], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2527]);
                base.verify_same($"t.{slot}.method_members", _bj2525, scratch);
            }
            _bj2525 += 1;
        } else {
            _news2526.append(_i2527);
        }
    }
    if (_bj2525 == _seq2524.count) {
        out.unsigned(2);
        out.unsigned(_news2526.count);
        for (var _i2527 in _news2526) {
            out.unsigned(_i2527);
            _m_FunctionDef_write(out, value.method_members[_i2527]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2527 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2527]);
        }
    }
    var _seq2540 = base.ref_template_parts[slot].generic_methods;
    ulong _bj2541 = 0;
    var _news2542 = Array<ulong>();
    for (var _i2543 in 0..value.generic_methods.count) {
        if (_bj2541 < _seq2540.count and value.generic_methods[_i2543] === _seq2540[_bj2541]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2543]);
                base.verify_same($"t.{slot}.generic_methods", _bj2541, scratch);
            }
            _bj2541 += 1;
        } else if (_bj2541 < _seq2540.count
            and _same_m_FunctionDef(value.generic_methods[_i2543], _seq2540[_bj2541], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2543]);
                base.verify_same($"t.{slot}.generic_methods", _bj2541, scratch);
            }
            _bj2541 += 1;
        } else {
            _news2542.append(_i2543);
        }
    }
    if (_bj2541 == _seq2540.count) {
        out.unsigned(2);
        out.unsigned(_news2542.count);
        for (var _i2543 in _news2542) {
            out.unsigned(_i2543);
            _m_FunctionDef_write(out, value.generic_methods[_i2543]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2543 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2543]);
        }
    }
    var _seq2556 = base.ref_template_parts[slot].constructors;
    ulong _bj2557 = 0;
    var _news2558 = Array<ulong>();
    for (var _i2559 in 0..value.constructors.count) {
        if (_bj2557 < _seq2556.count and value.constructors[_i2559] === _seq2556[_bj2557]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2559]);
                base.verify_same($"t.{slot}.constructors", _bj2557, scratch);
            }
            _bj2557 += 1;
        } else if (_bj2557 < _seq2556.count
            and _same_m_FunctionDef(value.constructors[_i2559], _seq2556[_bj2557], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2559]);
                base.verify_same($"t.{slot}.constructors", _bj2557, scratch);
            }
            _bj2557 += 1;
        } else {
            _news2558.append(_i2559);
        }
    }
    if (_bj2557 == _seq2556.count) {
        out.unsigned(2);
        out.unsigned(_news2558.count);
        for (var _i2559 in _news2558) {
            out.unsigned(_i2559);
            _m_FunctionDef_write(out, value.constructors[_i2559]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2559 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2559]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2575 = base.ref_template_parts[slot].traits;
    ulong _bj2576 = 0;
    var _news2577 = Array<ulong>();
    for (var _i2578 in 0..value.traits.count) {
        if (_bj2576 < _seq2575.count and value.traits[_i2578] === _seq2575[_bj2576]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2578]);
                base.verify_same($"t.{slot}.traits", _bj2576, scratch);
            }
            _bj2576 += 1;
        } else if (_bj2576 < _seq2575.count and _same_m_TypeName(value.traits[_i2578], _seq2575[_bj2576], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2578]);
                base.verify_same($"t.{slot}.traits", _bj2576, scratch);
            }
            _bj2576 += 1;
        } else {
            _news2577.append(_i2578);
        }
    }
    if (_bj2576 == _seq2575.count) {
        out.unsigned(2);
        out.unsigned(_news2577.count);
        for (var _i2578 in _news2577) {
            out.unsigned(_i2578);
            _m_TypeName_write(out, value.traits[_i2578]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2578 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2578]);
        }
    }
    var _seq2591 = base.ref_template_parts[slot].attributes;
    ulong _bj2592 = 0;
    var _news2593 = Array<ulong>();
    for (var _i2594 in 0..value.attributes.count) {
        if (_bj2592 < _seq2591.count and value.attributes[_i2594] === _seq2591[_bj2592]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2594]);
                base.verify_same($"t.{slot}.attributes", _bj2592, scratch);
            }
            _bj2592 += 1;
        } else if (_bj2592 < _seq2591.count and _same_a_Attribute(value.attributes[_i2594], _seq2591[_bj2592], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2594]);
                base.verify_same($"t.{slot}.attributes", _bj2592, scratch);
            }
            _bj2592 += 1;
        } else {
            _news2593.append(_i2594);
        }
    }
    if (_bj2592 == _seq2591.count) {
        out.unsigned(2);
        out.unsigned(_news2593.count);
        for (var _i2594 in _news2593) {
            out.unsigned(_i2594);
            _a_Attribute_write(out, value.attributes[_i2594]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2594 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2594]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2603 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2603);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2485 = input.text();
    var _f2486 = _m_TypeName_read(input);
    var _f2496 = Array<GenericParam>();
    var _mode2499 = input.unsigned();
    if (_mode2499 == 2) {
        var _changed2488 = HashMap<ulong, GenericParam>();
        ulong _bi2500 = 0;
        var _n2497 = input.count();
        for (var _ in 0.._n2497) {
            var _at2501 = input.unsigned();
            while (_f2496.count < _at2501 or (input.merging and _bi2500 < was.generic_params.count)) {
                var _c = _changed2488.try_get(_bi2500);
                _f2496.append(_c.is_value() ? _c.value() : was.generic_params[_bi2500]);
                _bi2500 += 1;
            }
            _f2496.append(_m_GenericParam_read(input));
        }
        while (_bi2500 < was.generic_params.count) {
            var _c = _changed2488.try_get(_bi2500);
            _f2496.append(_c.is_value() ? _c.value() : was.generic_params[_bi2500]);
            _bi2500 += 1;
        }
    } else if (_mode2499 == 3) {
        var _n2497 = input.count();
        for (var _ in 0.._n2497) {
            _f2496.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2497 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2497) {
            var _tag2498 = input.unsigned();
            if (_tag2498 & 1 == 1) {
                if (!input.merging) {
                    _f2496.append(was.generic_params[_tag2498 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2496.append(_read);
                }
            }
        }
    }
    var _f2512 = Array<VariableDef>();
    var _mode2515 = input.unsigned();
    if (_mode2515 == 2) {
        var _changed2504 = HashMap<ulong, VariableDef>();
        ulong _bi2516 = 0;
        var _n2513 = input.count();
        for (var _ in 0.._n2513) {
            var _at2517 = input.unsigned();
            while (_f2512.count < _at2517 or (input.merging and _bi2516 < was.field_members.count)) {
                var _c = _changed2504.try_get(_bi2516);
                _f2512.append(_c.is_value() ? _c.value() : was.field_members[_bi2516]);
                _bi2516 += 1;
            }
            _f2512.append(_m_VariableDef_read(input));
        }
        while (_bi2516 < was.field_members.count) {
            var _c = _changed2504.try_get(_bi2516);
            _f2512.append(_c.is_value() ? _c.value() : was.field_members[_bi2516]);
            _bi2516 += 1;
        }
    } else if (_mode2515 == 3) {
        var _n2513 = input.count();
        for (var _ in 0.._n2513) {
            _f2512.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2513 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2513) {
            var _tag2514 = input.unsigned();
            if (_tag2514 & 1 == 1) {
                if (!input.merging) {
                    _f2512.append(was.field_members[_tag2514 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2512.append(_read);
                }
            }
        }
    }
    var _f2528 = Array<FunctionDef>();
    var _mode2531 = input.unsigned();
    if (_mode2531 == 2) {
        var _changed2520 = HashMap<ulong, FunctionDef>();
        ulong _bi2532 = 0;
        var _n2529 = input.count();
        for (var _ in 0.._n2529) {
            var _at2533 = input.unsigned();
            while (_f2528.count < _at2533 or (input.merging and _bi2532 < was.method_members.count)) {
                var _c = _changed2520.try_get(_bi2532);
                _f2528.append(_c.is_value() ? _c.value() : was.method_members[_bi2532]);
                _bi2532 += 1;
            }
            _f2528.append(_m_FunctionDef_read(input));
        }
        while (_bi2532 < was.method_members.count) {
            var _c = _changed2520.try_get(_bi2532);
            _f2528.append(_c.is_value() ? _c.value() : was.method_members[_bi2532]);
            _bi2532 += 1;
        }
    } else if (_mode2531 == 3) {
        var _n2529 = input.count();
        for (var _ in 0.._n2529) {
            _f2528.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2529 = input.count();
        if (input.merging) {
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2529) {
            var _tag2530 = input.unsigned();
            if (_tag2530 & 1 == 1) {
                if (!input.merging) {
                    _f2528.append(was.method_members[_tag2530 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2528.append(_read);
                }
            }
        }
    }
    var _f2544 = Array<FunctionDef>();
    var _mode2547 = input.unsigned();
    if (_mode2547 == 2) {
        var _changed2536 = HashMap<ulong, FunctionDef>();
        ulong _bi2548 = 0;
        var _n2545 = input.count();
        for (var _ in 0.._n2545) {
            var _at2549 = input.unsigned();
            while (_f2544.count < _at2549 or (input.merging and _bi2548 < was.generic_methods.count)) {
                var _c = _changed2536.try_get(_bi2548);
                _f2544.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2548]);
                _bi2548 += 1;
            }
            _f2544.append(_m_FunctionDef_read(input));
        }
        while (_bi2548 < was.generic_methods.count) {
            var _c = _changed2536.try_get(_bi2548);
            _f2544.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2548]);
            _bi2548 += 1;
        }
    } else if (_mode2547 == 3) {
        var _n2545 = input.count();
        for (var _ in 0.._n2545) {
            _f2544.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2545 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2545) {
            var _tag2546 = input.unsigned();
            if (_tag2546 & 1 == 1) {
                if (!input.merging) {
                    _f2544.append(was.generic_methods[_tag2546 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2544.append(_read);
                }
            }
        }
    }
    var _f2560 = Array<FunctionDef>();
    var _mode2563 = input.unsigned();
    if (_mode2563 == 2) {
        var _changed2552 = HashMap<ulong, FunctionDef>();
        ulong _bi2564 = 0;
        var _n2561 = input.count();
        for (var _ in 0.._n2561) {
            var _at2565 = input.unsigned();
            while (_f2560.count < _at2565 or (input.merging and _bi2564 < was.constructors.count)) {
                var _c = _changed2552.try_get(_bi2564);
                _f2560.append(_c.is_value() ? _c.value() : was.constructors[_bi2564]);
                _bi2564 += 1;
            }
            _f2560.append(_m_FunctionDef_read(input));
        }
        while (_bi2564 < was.constructors.count) {
            var _c = _changed2552.try_get(_bi2564);
            _f2560.append(_c.is_value() ? _c.value() : was.constructors[_bi2564]);
            _bi2564 += 1;
        }
    } else if (_mode2563 == 3) {
        var _n2561 = input.count();
        for (var _ in 0.._n2561) {
            _f2560.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2561 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2561) {
            var _tag2562 = input.unsigned();
            if (_tag2562 & 1 == 1) {
                if (!input.merging) {
                    _f2560.append(was.constructors[_tag2562 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2560.append(_read);
                }
            }
        }
    }
    var _f2567 = _m_FunctionDef_read(input);
    var _f2568 = _m_FunctionDef_read(input);
    var _f2569 = _m_FunctionDef_read(input);
    var _f2579 = Array<TypeName>();
    var _mode2582 = input.unsigned();
    if (_mode2582 == 2) {
        var _changed2571 = HashMap<ulong, TypeName>();
        ulong _bi2583 = 0;
        var _n2580 = input.count();
        for (var _ in 0.._n2580) {
            var _at2584 = input.unsigned();
            while (_f2579.count < _at2584 or (input.merging and _bi2583 < was.traits.count)) {
                var _c = _changed2571.try_get(_bi2583);
                _f2579.append(_c.is_value() ? _c.value() : was.traits[_bi2583]);
                _bi2583 += 1;
            }
            _f2579.append(_m_TypeName_read(input));
        }
        while (_bi2583 < was.traits.count) {
            var _c = _changed2571.try_get(_bi2583);
            _f2579.append(_c.is_value() ? _c.value() : was.traits[_bi2583]);
            _bi2583 += 1;
        }
    } else if (_mode2582 == 3) {
        var _n2580 = input.count();
        for (var _ in 0.._n2580) {
            _f2579.append(_m_TypeName_read(input));
        }
    } else {
        var _n2580 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2580) {
            var _tag2581 = input.unsigned();
            if (_tag2581 & 1 == 1) {
                if (!input.merging) {
                    _f2579.append(was.traits[_tag2581 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2579.append(_read);
                }
            }
        }
    }
    var _f2595 = Array<ast.Attribute>();
    var _mode2598 = input.unsigned();
    if (_mode2598 == 2) {
        var _changed2587 = HashMap<ulong, ast.Attribute>();
        ulong _bi2599 = 0;
        var _n2596 = input.count();
        for (var _ in 0.._n2596) {
            var _at2600 = input.unsigned();
            while (_f2595.count < _at2600 or (input.merging and _bi2599 < was.attributes.count)) {
                var _c = _changed2587.try_get(_bi2599);
                _f2595.append(_c.is_value() ? _c.value() : was.attributes[_bi2599]);
                _bi2599 += 1;
            }
            _f2595.append(_a_Attribute_read(input));
        }
        while (_bi2599 < was.attributes.count) {
            var _c = _changed2587.try_get(_bi2599);
            _f2595.append(_c.is_value() ? _c.value() : was.attributes[_bi2599]);
            _bi2599 += 1;
        }
    } else if (_mode2598 == 3) {
        var _n2596 = input.count();
        for (var _ in 0.._n2596) {
            _f2595.append(_a_Attribute_read(input));
        }
    } else {
        var _n2596 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2596) {
            var _tag2597 = input.unsigned();
            if (_tag2597 & 1 == 1) {
                if (!input.merging) {
                    _f2595.append(was.attributes[_tag2597 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2595.append(_read);
                }
            }
        }
    }
    var _f2602 = input.loc();
    var _o2604 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2605 = Array<EnumCaseDef>();
        var _n2606 = input.count();
        for (var _ in 0.._n2606) {
            _v2605.append(_m_EnumCaseDef_read(input));
        }
        _o2604 = Optional<Array<EnumCaseDef>>.Value(_v2605);
    }
    var _f2607 = _o2604;
    return StructDef(
        _f2485, _f2486, _f2496, _f2512, _f2528, _f2544, _f2560, _f2567, _f2568, _f2569, _f2579, _f2595, _f2602, _f2607
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2502 = 0;
        for (var _item2487 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2487);
            base.add($"t.{slot}.generic_params", scratch, _j2502);
            _j2502 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2518 = 0;
        for (var _item2503 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2503);
            base.add($"t.{slot}.field_members", scratch, _j2518);
            _j2518 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2534 = 0;
        for (var _item2519 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2519);
            base.add($"t.{slot}.method_members", scratch, _j2534);
            _j2534 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2550 = 0;
        for (var _item2535 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2535);
            base.add($"t.{slot}.generic_methods", scratch, _j2550);
            _j2550 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2566 = 0;
        for (var _item2551 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2551);
            base.add($"t.{slot}.constructors", scratch, _j2566);
            _j2566 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2585 = 0;
        for (var _item2570 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2570);
            base.add($"t.{slot}.traits", scratch, _j2585);
            _j2585 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2601 = 0;
        for (var _item2586 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2586);
            base.add($"t.{slot}.attributes", scratch, _j2601);
            _j2601 += 1;
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
        for (var _item2608 in value.imports) {
            _a_Import_write(out, _item2608);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2609 in value.structs) {
            _m_StructDef_write(out, _item2609);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.traits.count);
        for (var _item2610 in value.traits) {
            _m_TraitDef_write(out, _item2610);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2611 in value.extensions) {
            _m_ExtensionDef_write(out, _item2611);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2612 in value.functions) {
            _m_FunctionDef_write(out, _item2612);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2613 in value.externs) {
            _m_ExternDef_write(out, _item2613);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2614 in value.globals) {
            _m_VariableDef_write(out, _item2614);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2615 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2615);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2616 in value.enums) {
            _m_EnumDef_write(out, _item2616);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2617 in value.struct_specs) {
            _m_TypeName_write(out, _item2617);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2618 in value.func_specs) {
            _m_TypeName_write(out, _item2618);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2619 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2619);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2620 in value.withheld) {
            _m_Withheld_write(out, _item2620);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2621 in value.properties) {
            _m_PropertyDef_write(out, _item2621);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2622 in value.type_uses) {
            _m_TypeUse_write(out, _item2622);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2623 in value.use_contexts) {
            _m_UseContext_write(out, _item2623);
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
            for (var _item2624 in value.literal_args) {
                var (_t2625, _t2626, _t2627) = _item2624;
                out.loc(_t2625);
                out.unsigned(_t2626);
                out.loc(_t2627);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2628 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2628);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2629 in value.trait_types) {
            _m_TraitType_write(out, _item2629);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2630 in value.conversions) {
            _m_Conversion_write(out, _item2630);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2632 = Array<(u8[], u8[], String)>();
        for (var (_key2631, _) in value.overload_sets) {
            var _scratch2633 = out.scratch();
            _scratch2633.text(_key2631);
            var _vscratch2635 = out.scratch();
            _vscratch2635.unsigned(value.overload_sets[_key2631].count);
            for (var _item2636 in value.overload_sets[_key2631]) {
                _vscratch2635.text(_item2636);
            }
            _keys2632.append((_scratch2633.finish(), _vscratch2635.finish(), _key2631));
        }
        _keys2632.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2632.count);
        for (var (_bytes2634, _, _key2631) in _keys2632) {
            out.text(_key2631);
            out.unsigned(value.overload_sets[_key2631].count);
            for (var _item2637 in value.overload_sets[_key2631]) {
                out.text(_item2637);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2639 = Array<(u8[], u8[], String)>();
        for (var (_key2638, _) in value.overload_unions) {
            var _scratch2640 = out.scratch();
            _scratch2640.text(_key2638);
            var _vscratch2642 = out.scratch();
            _vscratch2642.unsigned(value.overload_unions[_key2638].count);
            for (var _item2643 in value.overload_unions[_key2638]) {
                _vscratch2642.unsigned(_item2643.count);
                for (var _item2644 in _item2643) {
                    _vscratch2642.text(_item2644);
                }
            }
            _keys2639.append((_scratch2640.finish(), _vscratch2642.finish(), _key2638));
        }
        _keys2639.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2639.count);
        for (var (_bytes2641, _, _key2638) in _keys2639) {
            out.text(_key2638);
            out.unsigned(value.overload_unions[_key2638].count);
            for (var _item2645 in value.overload_unions[_key2638]) {
                out.unsigned(_item2645.count);
                for (var _item2646 in _item2645) {
                    out.text(_item2646);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2648 = Array<(u8[], u8[], String)>();
        for (var (_key2647, _) in value.method_overload_sets) {
            var _scratch2649 = out.scratch();
            _scratch2649.text(_key2647);
            var _vscratch2651 = out.scratch();
            var _keys2653 = Array<(u8[], u8[], String)>();
            for (var (_key2652, _) in value.method_overload_sets[_key2647]) {
                var _scratch2654 = _vscratch2651.scratch();
                _scratch2654.text(_key2652);
                var _vscratch2656 = _vscratch2651.scratch();
                _vscratch2656.unsigned(value.method_overload_sets[_key2647][_key2652].count);
                for (var _item2657 in value.method_overload_sets[_key2647][_key2652]) {
                    _vscratch2656.text(_item2657);
                }
                _keys2653.append((_scratch2654.finish(), _vscratch2656.finish(), _key2652));
            }
            _keys2653.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2651.unsigned(_keys2653.count);
            for (var (_bytes2655, _, _key2652) in _keys2653) {
                _vscratch2651.text(_key2652);
                _vscratch2651.unsigned(value.method_overload_sets[_key2647][_key2652].count);
                for (var _item2658 in value.method_overload_sets[_key2647][_key2652]) {
                    _vscratch2651.text(_item2658);
                }
            }
            _keys2648.append((_scratch2649.finish(), _vscratch2651.finish(), _key2647));
        }
        _keys2648.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2648.count);
        for (var (_bytes2650, _, _key2647) in _keys2648) {
            out.text(_key2647);
            var _keys2660 = Array<(u8[], u8[], String)>();
            for (var (_key2659, _) in value.method_overload_sets[_key2647]) {
                var _scratch2661 = out.scratch();
                _scratch2661.text(_key2659);
                var _vscratch2663 = out.scratch();
                _vscratch2663.unsigned(value.method_overload_sets[_key2647][_key2659].count);
                for (var _item2664 in value.method_overload_sets[_key2647][_key2659]) {
                    _vscratch2663.text(_item2664);
                }
                _keys2660.append((_scratch2661.finish(), _vscratch2663.finish(), _key2659));
            }
            _keys2660.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2660.count);
            for (var (_bytes2662, _, _key2659) in _keys2660) {
                out.text(_key2659);
                out.unsigned(value.method_overload_sets[_key2647][_key2659].count);
                for (var _item2665 in value.method_overload_sets[_key2647][_key2659]) {
                    out.text(_item2665);
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
        var _keys2667 = Array<(u8[], u8[], Loc)>();
        for (var _key2666 in value.private_functions) {
            var _scratch2668 = out.scratch();
            _scratch2668.loc(_key2666);
            var _vscratch2670 = out.scratch();
            _keys2667.append((_scratch2668.finish(), _vscratch2670.finish(), _key2666));
        }
        _keys2667.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2667.count);
        for (var (_bytes2669, _, _key2666) in _keys2667) {
            out.loc(_key2666);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2672 = Array<(u8[], u8[], Loc)>();
        for (var _key2671 in value.file_private_functions) {
            var _scratch2673 = out.scratch();
            _scratch2673.loc(_key2671);
            var _vscratch2675 = out.scratch();
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
            out.loc(_key2671);
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
            for (var _item2676 in value.call_targets) {
                var (_t2677, _t2678) = _item2676;
                out.loc(_t2677);
                out.text(_t2678);
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
            for (var _item2679 in value.argument_names) {
                var (_t2680, _t2681) = _item2679;
                out.loc(_t2680);
                out.text(_t2681);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2682 in value.namespaces) {
            out.text(_item2682);
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
            for (var _item2683 in value.cached_files) {
                out.flag(_item2683);
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
            var _keys2685 = Array<(u8[], u8[], Loc)>();
            for (var (_key2684, _) in value.recorded_summaries) {
                var _scratch2686 = out.scratch();
                _scratch2686.loc(_key2684);
                var _vscratch2688 = out.scratch();
                _vscratch2688.text(value.recorded_summaries[_key2684]);
                _keys2685.append((_scratch2686.finish(), _vscratch2688.finish(), _key2684));
            }
            _keys2685.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2685.count);
            for (var (_bytes2687, _, _key2684) in _keys2685) {
                out.loc(_key2684);
                out.text(value.recorded_summaries[_key2684]);
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
            var _keys2690 = Array<(u8[], u8[], Loc)>();
            for (var _key2689 in value.stripped) {
                var _scratch2691 = out.scratch();
                _scratch2691.loc(_key2689);
                var _vscratch2693 = out.scratch();
                _keys2690.append((_scratch2691.finish(), _vscratch2693.finish(), _key2689));
            }
            _keys2690.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2690.count);
            for (var (_bytes2692, _, _key2689) in _keys2690) {
                out.loc(_key2689);
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
        var _keys2695 = Array<(u8[], u8[], String)>();
        for (var (_key2694, _) in value.spec_requests) {
            var _scratch2696 = out.scratch();
            _scratch2696.text(_key2694);
            var _vscratch2698 = out.scratch();
            _m_SpecRequest_write(_vscratch2698, value.spec_requests[_key2694]);
            _keys2695.append((_scratch2696.finish(), _vscratch2698.finish(), _key2694));
        }
        _keys2695.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2695.count);
        for (var (_bytes2697, _, _key2694) in _keys2695) {
            out.text(_key2694);
            _m_SpecRequest_write(out, value.spec_requests[_key2694]);
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
            for (var _item2699 in value.summaries_to_record) {
                var (_t2700, _t2701) = _item2699;
                out.loc(_t2700);
                out.text(_t2701);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2703 = Array<(u8[], u8[], String)>();
        for (var (_key2702, _) in value.caller_copies) {
            var _scratch2704 = out.scratch();
            _scratch2704.text(_key2702);
            var _vscratch2706 = out.scratch();
            _vscratch2706.unsigned(value.caller_copies[_key2702].count);
            for (var _item2707 in value.caller_copies[_key2702]) {
                _vscratch2706.flag(_item2707);
            }
            _keys2703.append((_scratch2704.finish(), _vscratch2706.finish(), _key2702));
        }
        _keys2703.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2703.count);
        for (var (_bytes2705, _, _key2702) in _keys2703) {
            out.text(_key2702);
            out.unsigned(value.caller_copies[_key2702].count);
            for (var _item2708 in value.caller_copies[_key2702]) {
                out.flag(_item2708);
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
    for (var _item2709 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2709);
        found.append(("structs " + _item2709.name, interface_text(out)));
    }
    for (var _item2710 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2710);
        found.append(("functions " + _item2710.name, interface_text(out)));
    }
    return found;
}
