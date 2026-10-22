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
    if (value.labeled.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.labeled.value());
    } else {
        out.unsigned(0);
    }
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
    var _o1412 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1412 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1413 = _o1412;
    return FunctionCallExpression(_f1407, _f1410, _f1411, _f1413);
}

_m_NamedArgumentExpression_write(out: RecordOut, value: NamedArgumentExpression) {
    out.text(value.name);
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_NamedArgumentExpression_read(input: RecordIn): NamedArgumentExpression {
    var _f1414 = input.text();
    var _f1415 = _m_Expression_read(input);
    var _f1416 = input.loc();
    return NamedArgumentExpression(_f1415, _f1414, _f1416);
}

_m_DefaultArgumentExpression_write(out: RecordOut, value: DefaultArgumentExpression) {
    _m_TypeName_write(out, value.ty);
}

_m_DefaultArgumentExpression_read(input: RecordIn): DefaultArgumentExpression {
    var _f1417 = _m_TypeName_read(input);
    return DefaultArgumentExpression(_f1417);
}

_m_MethodCallExpression_write(out: RecordOut, value: MethodCallExpression) {
    _m_Expression_write(out, value.this_value);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item1418 in value.args) {
        _m_Expression_write(out, _item1418);
    }
    out.loc(value.loc);
}

_m_MethodCallExpression_read(input: RecordIn): MethodCallExpression {
    var _f1419 = _m_Expression_read(input);
    var _f1420 = input.text();
    var _v1421 = Array<Expression>();
    var _n1422 = input.count();
    for (var _ in 0.._n1422) {
        _v1421.append(_m_Expression_read(input));
    }
    var _f1423 = _v1421;
    var _f1424 = input.loc();
    return MethodCallExpression(_f1419, _f1420, _f1423, _f1424);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1425 = input.text();
    var _f1426 = _m_TypeName_read(input);
    var _f1427 = input.loc();
    return FunctionRefExpression(_f1425, _f1426, _f1427);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1428 in value.args) {
        _m_Expression_write(out, _item1428);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1429 = _m_Expression_read(input);
    var _v1430 = Array<Expression>();
    var _n1431 = input.count();
    for (var _ in 0.._n1431) {
        _v1430.append(_m_Expression_read(input));
    }
    var _f1432 = _v1430;
    return InvokeExpression(_f1429, _f1432);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1434 = _m_Expression_read(input);
    var _f1435 = input.text();
    var _f1436 = _m_TypeName_read(input);
    var _f1437 = input.loc();
    return MakeClosureExpression(_f1434, _f1435, _f1436, _f1437);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1439 in value.args) {
        _m_Expression_write(out, _item1439);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1440 = _m_Expression_read(input);
    var _v1441 = Array<Expression>();
    var _n1442 = input.count();
    for (var _ in 0.._n1442) {
        _v1441.append(_m_Expression_read(input));
    }
    var _f1443 = _v1441;
    return CallPointerExpression(_f1440, _f1443);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1446 = _m_Expression_read(input);
    var _f1447 = input.loc();
    return MoveExpression(_f1446, _f1447);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1448 = _m_Expression_read(input);
    var _f1449 = input.unsigned();
    var _f1450 = input.loc();
    return DestructureExpression(_f1448, _f1449, _f1450);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1453 = _m_TypeName_read(input);
    var _f1454 = input.signed();
    return StaticCaseExpression(_f1453, _f1454);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1455 = input.text();
    var _f1456 = input.loc();
    return StaticStringExpression(_f1455, _f1456);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1458 = input.unsigned();
    var _f1459 = _m_TypeName_read(input);
    var _f1460 = input.loc();
    return SubjectExpression(_f1458, _f1459, _f1460);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1461 = _m_Expression_read(input);
    var _f1462 = _m_TypeName_read(input);
    var _f1463 = _m_TypeName_read(input);
    var _f1464 = input.loc();
    return ToTraitExpression(_f1461, _f1462, _f1463, _f1464);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1465 in value.candidates) {
        _m_TypeName_write(out, _item1465);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1466 = _m_Expression_read(input);
    var _f1467 = _m_TypeName_read(input);
    var _f1468 = _m_TypeName_read(input);
    var _v1469 = Array<TypeName>();
    var _n1470 = input.count();
    for (var _ in 0.._n1470) {
        _v1469.append(_m_TypeName_read(input));
    }
    var _f1471 = _v1469;
    var _f1472 = input.flag();
    var _f1473 = input.loc();
    return FromTraitExpression(_f1466, _f1467, _f1468, _f1471, _f1472, _f1473);
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
        var _f1433 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1433);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1438 = input.text();
        return Expression.MethodAddress(_f1438);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1444 = _m_Expression_read(input);
        return Expression.ForIterator(_f1444);
    }
    if (tag == 40) {
        var _f1445 = _m_Expression_read(input);
        return Expression.WithEntered(_f1445);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1451 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1451);
    }
    if (tag == 44) {
        var _f1452 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1452);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1457 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1457);
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
        var _f1474 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1474);
    }
    if (tag == 53) {
        var _f1475 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1475);
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
        var _f1476 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1476);
    }
    if (tag == 1) {
        var _f1477 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1477);
    }
    if (tag == 2) {
        var _f1478 = _m_StructDef_read(input);
        return Declaration.Struct(_f1478);
    }
    if (tag == 3) {
        var _f1479 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1479);
    }
    if (tag == 4) {
        var _f1480 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1480);
    }
    if (tag == 5) {
        var _f1481 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1481);
    }
    if (tag == 6) {
        var _f1482 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1482);
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
    var _hs1488 = Array<String>();
    for (var _item1483 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1483);
        _hs1488.append(base.hash_of(scratch));
    }
    var _seq1489 = base.sequence("imports");
    ulong _bj1490 = 0;
    var _news1491 = Array<ulong>();
    for (var _i1492 in 0.._hs1488.count) {
        if (_bj1490 < _seq1489.count and _hs1488[_i1492] == _seq1489[_bj1490]) {
            _bj1490 += 1;
        } else {
            _news1491.append(_i1492);
        }
    }
    if (_bj1490 == _seq1489.count) {
        out.unsigned(2);
        out.unsigned(_news1491.count);
        for (var _i1492 in _news1491) {
            out.unsigned(_i1492);
            _a_Import_write(out, value.imports[_i1492]);
            {
                var _own1493 = RecordOut();
                _own1493.blank_bodies = true;
                _own1493.blank_locs = true;
                _own1493.pending_as_bytes = true;
                _a_Import_write(_own1493, value.imports[_i1492]);
                base.own("imports", interface_text(_own1493));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1492 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1492]);
            {
                var _own1494 = RecordOut();
                _own1494.blank_bodies = true;
                _own1494.blank_locs = true;
                _own1494.pending_as_bytes = true;
                _a_Import_write(_own1494, value.imports[_i1492]);
                base.own("imports", interface_text(_own1494));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1504 = base.ref_structs;
    ulong _bj1505 = 0;
    var _news1507 = Array<ulong>();
    var _patches1508 = Array<(ulong, ulong)>();
    for (var _i1509 in 0..value.structs.count) {
        if (_bj1505 < _seq1504.count
            and value.structs[_i1509] === _seq1504[_bj1505]
            and !value.extended_checked.contains(value.structs[_i1509].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1509]);
                base.verify_same("s", _bj1505, scratch, value.structs[_i1509].name);
            }
            _bj1505 += 1;
        } else if (_bj1505 < _seq1504.count
            and !(value.structs[_i1509] === _seq1504[_bj1505])
            and _same_m_StructDef(value.structs[_i1509], _seq1504[_bj1505], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1509]);
                base.verify_same("s", _bj1505, scratch, value.structs[_i1509].name);
            }
            _bj1505 += 1;
        } else if (_bj1505 < _seq1504.count and value.structs[_i1509].name == _seq1504[_bj1505].name) {
            _patches1508.append((_i1509, _bj1505));
            _bj1505 += 1;
        } else {
            _news1507.append(_i1509);
        }
    }
    if (_bj1505 == _seq1504.count) {
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
                var _s1511 = value.structs[_i1509];
                var _methods1512 = _s1511.method_members;
                _s1511.method_members = Array<FunctionDef>();
                var _fields1513 = _s1511.field_members;
                var split__fields1513 = splits_fields(_s1511);
                if (split__fields1513) {
                    _s1511.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1510, _s1511);
                _s1511.method_members = _methods1512;
                _s1511.field_members = _fields1513;
                base.own_named("structs", _s1511.name, interface_text(_own1510));
                for (var _m1514 in _methods1512) {
                    var _own1515 = RecordOut();
                    _own1515.blank_bodies = true;
                    _own1515.blank_locs = true;
                    _own1515.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1515, _m1514);
                    base.own_method("structs", _s1511.name, _m1514.name, interface_text(_own1515));
                }
                if (split__fields1513) {
                    var _order1517 = StringBuilder();
                    for (var _f1516 in _fields1513) {
                        var _own1518 = RecordOut();
                        _own1518.blank_locs = true;
                        _m_VariableDef_write(_own1518, _f1516);
                        base.own_method("structs", _s1511.name, "." + _f1516.name, interface_text(_own1518));
                        _order1517.append(_f1516.name);
                        _order1517.append(",");
                    }
                    base.own_method("structs", _s1511.name, ".#order", _order1517.to_string());
                }
            }
        }
        out.unsigned(_news1507.count);
        for (var _i1509 in _news1507) {
            ulong _before = out.values.count;
            out.unsigned(_i1509);
            _m_StructDef_write(out, value.structs[_i1509]);
            base.count("s new", out.values.count - _before);
            {
                var _own1519 = RecordOut();
                _own1519.blank_bodies = true;
                _own1519.blank_locs = true;
                _own1519.pending_as_bytes = true;
                var _s1520 = value.structs[_i1509];
                var _methods1521 = _s1520.method_members;
                _s1520.method_members = Array<FunctionDef>();
                var _fields1522 = _s1520.field_members;
                var split__fields1522 = splits_fields(_s1520);
                if (split__fields1522) {
                    _s1520.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1519, _s1520);
                _s1520.method_members = _methods1521;
                _s1520.field_members = _fields1522;
                base.own_named("structs", _s1520.name, interface_text(_own1519));
                for (var _m1523 in _methods1521) {
                    var _own1524 = RecordOut();
                    _own1524.blank_bodies = true;
                    _own1524.blank_locs = true;
                    _own1524.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1524, _m1523);
                    base.own_method("structs", _s1520.name, _m1523.name, interface_text(_own1524));
                }
                if (split__fields1522) {
                    var _order1526 = StringBuilder();
                    for (var _f1525 in _fields1522) {
                        var _own1527 = RecordOut();
                        _own1527.blank_locs = true;
                        _m_VariableDef_write(_own1527, _f1525);
                        base.own_method("structs", _s1520.name, "." + _f1525.name, interface_text(_own1527));
                        _order1526.append(_f1525.name);
                        _order1526.append(",");
                    }
                    base.own_method("structs", _s1520.name, ".#order", _order1526.to_string());
                }
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1503 = HashSet<long>();
        var _slots1506 = HashMap<String, long>();
        for (var _i1509 in 0.._seq1504.count) {
            if (!_slots1506.contains(_seq1504[_i1509].name)) {
                _slots1506[_seq1504[_i1509].name] = _i1509 as long;
            }
        }
        out.unsigned(value.structs.count);
        for (var _i1509 in 0..value.structs.count) {
            var _item1502 = value.structs[_i1509];
            var _slot = _slots1506.try_get(_item1502.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq1504[named as ulong] === _item1502
                and !value.extended_checked.contains(_item1502.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1503.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1503.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1502, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1502);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1503.count);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1541 = Array<String>();
    for (var _item1536 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1536);
        _hs1541.append(base.hash_of(scratch));
    }
    var _seq1542 = base.sequence("traits");
    ulong _bj1543 = 0;
    var _news1544 = Array<ulong>();
    for (var _i1545 in 0.._hs1541.count) {
        if (_bj1543 < _seq1542.count and _hs1541[_i1545] == _seq1542[_bj1543]) {
            _bj1543 += 1;
        } else {
            _news1544.append(_i1545);
        }
    }
    if (_bj1543 == _seq1542.count) {
        out.unsigned(2);
        out.unsigned(_news1544.count);
        for (var _i1545 in _news1544) {
            out.unsigned(_i1545);
            _m_TraitDef_write(out, value.traits[_i1545]);
            {
                var _own1546 = RecordOut();
                _own1546.blank_bodies = false;
                _own1546.blank_locs = true;
                _own1546.pending_as_bytes = true;
                _m_TraitDef_write(_own1546, value.traits[_i1545]);
                base.own("traits", interface_text(_own1546));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1545 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1545]);
            {
                var _own1547 = RecordOut();
                _own1547.blank_bodies = false;
                _own1547.blank_locs = true;
                _own1547.pending_as_bytes = true;
                _m_TraitDef_write(_own1547, value.traits[_i1545]);
                base.own("traits", interface_text(_own1547));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1560 = Array<String>();
    for (var _item1555 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1555);
        _hs1560.append(base.hash_of(scratch));
    }
    var _seq1561 = base.sequence("extensions");
    ulong _bj1562 = 0;
    var _news1563 = Array<ulong>();
    for (var _i1564 in 0.._hs1560.count) {
        if (_bj1562 < _seq1561.count and _hs1560[_i1564] == _seq1561[_bj1562]) {
            _bj1562 += 1;
        } else {
            _news1563.append(_i1564);
        }
    }
    if (_bj1562 == _seq1561.count) {
        out.unsigned(2);
        out.unsigned(_news1563.count);
        for (var _i1564 in _news1563) {
            out.unsigned(_i1564);
            _m_ExtensionDef_write(out, value.extensions[_i1564]);
            {
                var _own1565 = RecordOut();
                _own1565.blank_bodies = true;
                _own1565.blank_locs = true;
                _own1565.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1565, value.extensions[_i1564]);
                base.own("extensions", interface_text(_own1565));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1564 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1564]);
            {
                var _own1566 = RecordOut();
                _own1566.blank_bodies = true;
                _own1566.blank_locs = true;
                _own1566.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1566, value.extensions[_i1564]);
                base.own("extensions", interface_text(_own1566));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1579 = base.ref_functions;
    ulong _bj1580 = 0;
    var _news1581 = Array<ulong>();
    var _changed1575 = Array<(ulong, ulong)>();
    for (var _i1582 in 0..value.functions.count) {
        if (_bj1580 < _seq1579.count and value.functions[_i1582] === _seq1579[_bj1580]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1582]);
                base.verify_same("functions", _bj1580, scratch);
            }
            _bj1580 += 1;
        } else if (_bj1580 < _seq1579.count and _same_m_FunctionDef(value.functions[_i1582], _seq1579[_bj1580], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1582]);
                base.verify_same("functions", _bj1580, scratch);
            }
            _bj1580 += 1;
        } else if (_bj1580 < _seq1579.count and value.functions[_i1582].name == _seq1579[_bj1580].name) {
            _changed1575.append((_i1582, _bj1580));
            _bj1580 += 1;
        } else {
            _news1581.append(_i1582);
        }
    }
    if (_bj1580 == _seq1579.count) {
        out.unsigned(2);
        out.unsigned(_changed1575.count);
        for (var (_i1582, _b) in _changed1575) {
            out.text(value.functions[_i1582].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1582]);
            {
                var _own1583 = RecordOut();
                _own1583.blank_bodies = true;
                _own1583.blank_locs = true;
                _own1583.pending_as_bytes = true;
                _m_FunctionDef_write(_own1583, value.functions[_i1582]);
                base.own_function("functions", value.functions[_i1582], interface_text(_own1583));
            }
        }
        base.count("functions" + " changed", _changed1575.count);
        out.unsigned(_news1581.count);
        for (var _i1582 in _news1581) {
            out.unsigned(_i1582);
            _m_FunctionDef_write(out, value.functions[_i1582]);
            {
                var _own1584 = RecordOut();
                _own1584.blank_bodies = true;
                _own1584.blank_locs = true;
                _own1584.pending_as_bytes = true;
                _m_FunctionDef_write(_own1584, value.functions[_i1582]);
                base.own_function("functions", value.functions[_i1582], interface_text(_own1584));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1582 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1582]);
            {
                var _own1585 = RecordOut();
                _own1585.blank_bodies = true;
                _own1585.blank_locs = true;
                _own1585.pending_as_bytes = true;
                _m_FunctionDef_write(_own1585, value.functions[_i1582]);
                base.own_function("functions", value.functions[_i1582], interface_text(_own1585));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1598 = Array<String>();
    for (var _item1593 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1593);
        _hs1598.append(base.hash_of(scratch));
    }
    var _seq1599 = base.sequence("externs");
    ulong _bj1600 = 0;
    var _news1601 = Array<ulong>();
    for (var _i1602 in 0.._hs1598.count) {
        if (_bj1600 < _seq1599.count and _hs1598[_i1602] == _seq1599[_bj1600]) {
            _bj1600 += 1;
        } else {
            _news1601.append(_i1602);
        }
    }
    if (_bj1600 == _seq1599.count) {
        out.unsigned(2);
        out.unsigned(_news1601.count);
        for (var _i1602 in _news1601) {
            out.unsigned(_i1602);
            _m_ExternDef_write(out, value.externs[_i1602]);
            {
                var _own1603 = RecordOut();
                _own1603.blank_bodies = true;
                _own1603.blank_locs = true;
                _own1603.pending_as_bytes = true;
                _m_ExternDef_write(_own1603, value.externs[_i1602]);
                base.own("externs", interface_text(_own1603));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1602 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1602]);
            {
                var _own1604 = RecordOut();
                _own1604.blank_bodies = true;
                _own1604.blank_locs = true;
                _own1604.pending_as_bytes = true;
                _m_ExternDef_write(_own1604, value.externs[_i1602]);
                base.own("externs", interface_text(_own1604));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1617 = Array<String>();
    for (var _item1612 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1612);
        _hs1617.append(base.hash_of(scratch));
    }
    var _seq1618 = base.sequence("globals");
    ulong _bj1619 = 0;
    var _news1620 = Array<ulong>();
    for (var _i1621 in 0.._hs1617.count) {
        if (_bj1619 < _seq1618.count and _hs1617[_i1621] == _seq1618[_bj1619]) {
            _bj1619 += 1;
        } else {
            _news1620.append(_i1621);
        }
    }
    if (_bj1619 == _seq1618.count) {
        out.unsigned(2);
        out.unsigned(_news1620.count);
        for (var _i1621 in _news1620) {
            out.unsigned(_i1621);
            _m_VariableDef_write(out, value.globals[_i1621]);
            {
                var _own1622 = RecordOut();
                _own1622.blank_bodies = true;
                _own1622.blank_locs = true;
                _own1622.pending_as_bytes = true;
                _m_VariableDef_write(_own1622, value.globals[_i1621]);
                base.own("globals", interface_text(_own1622));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1621 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1621]);
            {
                var _own1623 = RecordOut();
                _own1623.blank_bodies = true;
                _own1623.blank_locs = true;
                _own1623.pending_as_bytes = true;
                _m_VariableDef_write(_own1623, value.globals[_i1621]);
                base.own("globals", interface_text(_own1623));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1636 = Array<String>();
    for (var _item1631 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1631);
        _hs1636.append(base.hash_of(scratch));
    }
    var _seq1637 = base.sequence("static_blocks");
    ulong _bj1638 = 0;
    var _news1639 = Array<ulong>();
    for (var _i1640 in 0.._hs1636.count) {
        if (_bj1638 < _seq1637.count and _hs1636[_i1640] == _seq1637[_bj1638]) {
            _bj1638 += 1;
        } else {
            _news1639.append(_i1640);
        }
    }
    if (_bj1638 == _seq1637.count) {
        out.unsigned(2);
        out.unsigned(_news1639.count);
        for (var _i1640 in _news1639) {
            out.unsigned(_i1640);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1640]);
            {
                var _own1641 = RecordOut();
                _own1641.blank_bodies = true;
                _own1641.blank_locs = true;
                _own1641.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1641, value.static_blocks[_i1640]);
                base.own("static_blocks", interface_text(_own1641));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1640 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1640]);
            {
                var _own1642 = RecordOut();
                _own1642.blank_bodies = true;
                _own1642.blank_locs = true;
                _own1642.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1642, value.static_blocks[_i1640]);
                base.own("static_blocks", interface_text(_own1642));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1655 = Array<String>();
    for (var _item1650 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1650);
        _hs1655.append(base.hash_of(scratch));
    }
    var _seq1656 = base.sequence("enums");
    ulong _bj1657 = 0;
    var _news1658 = Array<ulong>();
    for (var _i1659 in 0.._hs1655.count) {
        if (_bj1657 < _seq1656.count and _hs1655[_i1659] == _seq1656[_bj1657]) {
            _bj1657 += 1;
        } else {
            _news1658.append(_i1659);
        }
    }
    if (_bj1657 == _seq1656.count) {
        out.unsigned(2);
        out.unsigned(_news1658.count);
        for (var _i1659 in _news1658) {
            out.unsigned(_i1659);
            _m_EnumDef_write(out, value.enums[_i1659]);
            {
                var _own1660 = RecordOut();
                _own1660.blank_bodies = true;
                _own1660.blank_locs = true;
                _own1660.pending_as_bytes = true;
                _m_EnumDef_write(_own1660, value.enums[_i1659]);
                base.own_named("enums", value.enums[_i1659].name, interface_text(_own1660));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1659 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1659]);
            {
                var _own1661 = RecordOut();
                _own1661.blank_bodies = true;
                _own1661.blank_locs = true;
                _own1661.pending_as_bytes = true;
                _m_EnumDef_write(_own1661, value.enums[_i1659]);
                base.own_named("enums", value.enums[_i1659].name, interface_text(_own1661));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1674 = Array<String>();
    for (var _item1669 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1669);
        _hs1674.append(base.hash_of(scratch));
    }
    var _seq1675 = base.sequence("struct_specs");
    ulong _bj1676 = 0;
    var _news1677 = Array<ulong>();
    for (var _i1678 in 0.._hs1674.count) {
        if (_bj1676 < _seq1675.count and _hs1674[_i1678] == _seq1675[_bj1676]) {
            _bj1676 += 1;
        } else {
            _news1677.append(_i1678);
        }
    }
    if (_bj1676 == _seq1675.count) {
        out.unsigned(2);
        out.unsigned(_news1677.count);
        for (var _i1678 in _news1677) {
            out.unsigned(_i1678);
            _m_TypeName_write(out, value.struct_specs[_i1678]);
            {
                var _own1679 = RecordOut();
                _own1679.blank_bodies = true;
                _own1679.blank_locs = true;
                _own1679.pending_as_bytes = true;
                _m_TypeName_write(_own1679, value.struct_specs[_i1678]);
                base.own("struct_specs", interface_text(_own1679));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1678 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1678]);
            {
                var _own1680 = RecordOut();
                _own1680.blank_bodies = true;
                _own1680.blank_locs = true;
                _own1680.pending_as_bytes = true;
                _m_TypeName_write(_own1680, value.struct_specs[_i1678]);
                base.own("struct_specs", interface_text(_own1680));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1693 = Array<String>();
    for (var _item1688 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1688);
        _hs1693.append(base.hash_of(scratch));
    }
    var _seq1694 = base.sequence("func_specs");
    ulong _bj1695 = 0;
    var _news1696 = Array<ulong>();
    for (var _i1697 in 0.._hs1693.count) {
        if (_bj1695 < _seq1694.count and _hs1693[_i1697] == _seq1694[_bj1695]) {
            _bj1695 += 1;
        } else {
            _news1696.append(_i1697);
        }
    }
    if (_bj1695 == _seq1694.count) {
        out.unsigned(2);
        out.unsigned(_news1696.count);
        for (var _i1697 in _news1696) {
            out.unsigned(_i1697);
            _m_TypeName_write(out, value.func_specs[_i1697]);
            {
                var _own1698 = RecordOut();
                _own1698.blank_bodies = true;
                _own1698.blank_locs = true;
                _own1698.pending_as_bytes = true;
                _m_TypeName_write(_own1698, value.func_specs[_i1697]);
                base.own("func_specs", interface_text(_own1698));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1697 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1697]);
            {
                var _own1699 = RecordOut();
                _own1699.blank_bodies = true;
                _own1699.blank_locs = true;
                _own1699.pending_as_bytes = true;
                _m_TypeName_write(_own1699, value.func_specs[_i1697]);
                base.own("func_specs", interface_text(_own1699));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1711 = HashSet<long>();
    out.unsigned(value.type_aliases.count);
    for (var _item1707 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1707);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1711.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1707);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1711.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1721 = Array<String>();
    for (var _item1716 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1716);
        _hs1721.append(base.hash_of(scratch));
    }
    var _seq1722 = base.sequence("withheld");
    ulong _bj1723 = 0;
    var _news1724 = Array<ulong>();
    for (var _i1725 in 0.._hs1721.count) {
        if (_bj1723 < _seq1722.count and _hs1721[_i1725] == _seq1722[_bj1723]) {
            _bj1723 += 1;
        } else {
            _news1724.append(_i1725);
        }
    }
    if (_bj1723 == _seq1722.count) {
        out.unsigned(2);
        out.unsigned(_news1724.count);
        for (var _i1725 in _news1724) {
            out.unsigned(_i1725);
            _m_Withheld_write(out, value.withheld[_i1725]);
            {
                var _own1726 = RecordOut();
                _own1726.blank_bodies = true;
                _own1726.blank_locs = true;
                _own1726.pending_as_bytes = true;
                _m_Withheld_write(_own1726, value.withheld[_i1725]);
                base.own("withheld", interface_text(_own1726));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1725 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1725]);
            {
                var _own1727 = RecordOut();
                _own1727.blank_bodies = true;
                _own1727.blank_locs = true;
                _own1727.pending_as_bytes = true;
                _m_Withheld_write(_own1727, value.withheld[_i1725]);
                base.own("withheld", interface_text(_own1727));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1740 = Array<String>();
    for (var _item1735 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1735);
        _hs1740.append(base.hash_of(scratch));
    }
    var _seq1741 = base.sequence("properties");
    ulong _bj1742 = 0;
    var _news1743 = Array<ulong>();
    for (var _i1744 in 0.._hs1740.count) {
        if (_bj1742 < _seq1741.count and _hs1740[_i1744] == _seq1741[_bj1742]) {
            _bj1742 += 1;
        } else {
            _news1743.append(_i1744);
        }
    }
    if (_bj1742 == _seq1741.count) {
        out.unsigned(2);
        out.unsigned(_news1743.count);
        for (var _i1744 in _news1743) {
            out.unsigned(_i1744);
            _m_PropertyDef_write(out, value.properties[_i1744]);
            {
                var _own1745 = RecordOut();
                _own1745.blank_bodies = true;
                _own1745.blank_locs = true;
                _own1745.pending_as_bytes = true;
                _m_PropertyDef_write(_own1745, value.properties[_i1744]);
                base.own("properties", interface_text(_own1745));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1744 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1744]);
            {
                var _own1746 = RecordOut();
                _own1746.blank_bodies = true;
                _own1746.blank_locs = true;
                _own1746.pending_as_bytes = true;
                _m_PropertyDef_write(_own1746, value.properties[_i1744]);
                base.own("properties", interface_text(_own1746));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1759 = Array<String>();
    for (var _item1754 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1754);
        _hs1759.append(base.hash_of(scratch));
    }
    var _seq1760 = base.sequence("type_uses");
    ulong _bj1761 = 0;
    var _news1762 = Array<ulong>();
    for (var _i1763 in 0.._hs1759.count) {
        if (_bj1761 < _seq1760.count and _hs1759[_i1763] == _seq1760[_bj1761]) {
            _bj1761 += 1;
        } else {
            _news1762.append(_i1763);
        }
    }
    if (_bj1761 == _seq1760.count) {
        out.unsigned(2);
        out.unsigned(_news1762.count);
        for (var _i1763 in _news1762) {
            out.unsigned(_i1763);
            _m_TypeUse_write(out, value.type_uses[_i1763]);
            {
                var _own1764 = RecordOut();
                _own1764.blank_bodies = true;
                _own1764.blank_locs = true;
                _own1764.pending_as_bytes = true;
                _m_TypeUse_write(_own1764, value.type_uses[_i1763]);
                base.own("type_uses", interface_text(_own1764));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1763 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1763]);
            {
                var _own1765 = RecordOut();
                _own1765.blank_bodies = true;
                _own1765.blank_locs = true;
                _own1765.pending_as_bytes = true;
                _m_TypeUse_write(_own1765, value.type_uses[_i1763]);
                base.own("type_uses", interface_text(_own1765));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1778 = Array<String>();
    for (var _item1773 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1773);
        _hs1778.append(base.hash_of(scratch));
    }
    var _seq1779 = base.sequence("use_contexts");
    ulong _bj1780 = 0;
    var _news1781 = Array<ulong>();
    for (var _i1782 in 0.._hs1778.count) {
        if (_bj1780 < _seq1779.count and _hs1778[_i1782] == _seq1779[_bj1780]) {
            _bj1780 += 1;
        } else {
            _news1781.append(_i1782);
        }
    }
    if (_bj1780 == _seq1779.count) {
        out.unsigned(2);
        out.unsigned(_news1781.count);
        for (var _i1782 in _news1781) {
            out.unsigned(_i1782);
            _m_UseContext_write(out, value.use_contexts[_i1782]);
            {
                var _own1783 = RecordOut();
                _own1783.blank_bodies = true;
                _own1783.blank_locs = true;
                _own1783.pending_as_bytes = true;
                _m_UseContext_write(_own1783, value.use_contexts[_i1782]);
                base.own("use_contexts", interface_text(_own1783));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1782 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1782]);
            {
                var _own1784 = RecordOut();
                _own1784.blank_bodies = true;
                _own1784.blank_locs = true;
                _own1784.pending_as_bytes = true;
                _m_UseContext_write(_own1784, value.use_contexts[_i1782]);
                base.own("use_contexts", interface_text(_own1784));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1794 = base.size("literal_args");
    var _scratch1793 = base.scratch();
    if (value.literal_args.count >= _n1794) {
        for (var _i1795 in 0.._n1794) {
            var (_t1796, _t1797, _t1798) = value.literal_args[_i1795];
            _scratch1793.loc(_t1796);
            _scratch1793.unsigned(_t1797);
            _scratch1793.loc(_t1798);
        }
    }
    if (value.literal_args.count >= _n1794 and base.same_list("literal_args", _scratch1793)) {
        out.unsigned(1);
        out.unsigned(_n1794);
        out.unsigned(value.literal_args.count - _n1794);
        for (var _i1795 in _n1794..value.literal_args.count) {
            var (_t1799, _t1800, _t1801) = value.literal_args[_i1795];
            out.loc(_t1799);
            out.unsigned(_t1800);
            out.loc(_t1801);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1802 in value.literal_args) {
            var (_t1803, _t1804, _t1805) = _item1802;
            out.loc(_t1803);
            out.unsigned(_t1804);
            out.loc(_t1805);
        }
        base.count("literal_args whole", 0);
    }
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1828 = Array<String>();
    for (var _item1823 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1823);
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
    var _hs1847 = Array<String>();
    for (var _item1842 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1842);
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
            base.own_at("private_functions", _okey2065, interface_text(_own2066));
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
            base.own_at("private_functions", _okey2072, interface_text(_own2073));
        }
        base.count("private_functions whole", 0);
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
            base.own_at("file_private_functions", _okey2091, interface_text(_own2092));
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
            base.own_at("file_private_functions", _okey2098, interface_text(_own2099));
        }
        base.count("file_private_functions whole", 0);
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
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _seq2232 = base.ref_templates;
    ulong _bj2233 = 0;
    var _news2235 = Array<ulong>();
    var _patches2236 = Array<(ulong, ulong)>();
    for (var _i2237 in 0..value.templates.structs.count) {
        if (_bj2233 < _seq2232.count
            and value.templates.structs[_i2237] === _seq2232[_bj2233]
            and !value.extended_checked.contains(value.templates.structs[_i2237].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2237]);
                base.verify_same("t", _bj2233, scratch, value.templates.structs[_i2237].name);
            }
            _bj2233 += 1;
        } else if (_bj2233 < _seq2232.count
            and !(value.templates.structs[_i2237] === _seq2232[_bj2233])
            and _same_m_StructDef(value.templates.structs[_i2237], _seq2232[_bj2233], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2237]);
                base.verify_same("t", _bj2233, scratch, value.templates.structs[_i2237].name);
            }
            _bj2233 += 1;
        } else if (_bj2233 < _seq2232.count and value.templates.structs[_i2237].name == _seq2232[_bj2233].name) {
            _patches2236.append((_i2237, _bj2233));
            _bj2233 += 1;
        } else {
            _news2235.append(_i2237);
        }
    }
    if (_bj2233 == _seq2232.count) {
        out.unsigned(2);
        out.unsigned(_patches2236.count);
        for (var (_i2237, _b) in _patches2236) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2237].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2237], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2238 = RecordOut();
                _own2238.blank_bodies = false;
                _own2238.blank_locs = true;
                _own2238.pending_as_bytes = true;
                _m_StructDef_write(_own2238, value.templates.structs[_i2237]);
                base.own("templates structs", interface_text(_own2238));
            }
        }
        out.unsigned(_news2235.count);
        for (var _i2237 in _news2235) {
            ulong _before = out.values.count;
            out.unsigned(_i2237);
            _m_StructDef_write(out, value.templates.structs[_i2237]);
            base.count("t new", out.values.count - _before);
            {
                var _own2239 = RecordOut();
                _own2239.blank_bodies = false;
                _own2239.blank_locs = true;
                _own2239.pending_as_bytes = true;
                _m_StructDef_write(_own2239, value.templates.structs[_i2237]);
                base.own("templates structs", interface_text(_own2239));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2231 = HashSet<long>();
        var _slots2234 = HashMap<String, long>();
        for (var _i2237 in 0.._seq2232.count) {
            if (!_slots2234.contains(_seq2232[_i2237].name)) {
                _slots2234[_seq2232[_i2237].name] = _i2237 as long;
            }
        }
        out.unsigned(value.templates.structs.count);
        for (var _i2237 in 0..value.templates.structs.count) {
            var _item2230 = value.templates.structs[_i2237];
            var _slot = _slots2234.try_get(_item2230.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq2232[named as ulong] === _item2230
                and !value.extended_checked.contains(_item2230.name)) {
                at = named;
            }
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
    var _seq2253 = base.ref_template_functions;
    ulong _bj2254 = 0;
    var _news2255 = Array<ulong>();
    var _changed2249 = Array<(ulong, ulong)>();
    for (var _i2256 in 0..value.templates.functions.count) {
        if (_bj2254 < _seq2253.count and value.templates.functions[_i2256] === _seq2253[_bj2254]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2256]);
                base.verify_same("tf", _bj2254, scratch);
            }
            _bj2254 += 1;
        } else if (_bj2254 < _seq2253.count
            and _same_m_FunctionDef(value.templates.functions[_i2256], _seq2253[_bj2254], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2256]);
                base.verify_same("tf", _bj2254, scratch);
            }
            _bj2254 += 1;
        } else if (_bj2254 < _seq2253.count and value.templates.functions[_i2256].name == _seq2253[_bj2254].name) {
            _changed2249.append((_i2256, _bj2254));
            _bj2254 += 1;
        } else {
            _news2255.append(_i2256);
        }
    }
    if (_bj2254 == _seq2253.count) {
        out.unsigned(2);
        out.unsigned(_changed2249.count);
        for (var (_i2256, _b) in _changed2249) {
            out.text(value.templates.functions[_i2256].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2256]);
            {
                var _own2257 = RecordOut();
                _own2257.blank_bodies = false;
                _own2257.blank_locs = true;
                _own2257.pending_as_bytes = true;
                _m_FunctionDef_write(_own2257, value.templates.functions[_i2256]);
                base.own("templates functions", interface_text(_own2257));
            }
        }
        base.count("tf" + " changed", _changed2249.count);
        out.unsigned(_news2255.count);
        for (var _i2256 in _news2255) {
            out.unsigned(_i2256);
            _m_FunctionDef_write(out, value.templates.functions[_i2256]);
            {
                var _own2258 = RecordOut();
                _own2258.blank_bodies = false;
                _own2258.blank_locs = true;
                _own2258.pending_as_bytes = true;
                _m_FunctionDef_write(_own2258, value.templates.functions[_i2256]);
                base.own("templates functions", interface_text(_own2258));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2256 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2256]);
            {
                var _own2259 = RecordOut();
                _own2259.blank_bodies = false;
                _own2259.blank_locs = true;
                _own2259.pending_as_bytes = true;
                _m_FunctionDef_write(_own2259, value.templates.functions[_i2256]);
                base.own("templates functions", interface_text(_own2259));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2272 = 0;
    var _news2273 = HashMap<String, SpecRequest>();
    for (var (_key2269, _) in value.spec_requests) {
        var _kscratch2270 = base.scratch();
        _kscratch2270.text(_key2269);
        var _vscratch2271 = base.scratch();
        _m_SpecRequest_write(_vscratch2271, value.spec_requests[_key2269]);
        var _had = base.entry("spec_requests", _kscratch2270, _vscratch2271);
        if (_had >= 0) {
            _kept2272 += 1;
        }
        if (_had != 1) {
            _news2273[_key2269] = value.spec_requests[_key2269];
        }
    }
    if (_kept2272 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2275 = Array<(u8[], u8[], String)>();
        for (var (_key2274, _) in _news2273) {
            var _scratch2276 = out.scratch();
            _scratch2276.text(_key2274);
            var _vscratch2278 = out.scratch();
            _m_SpecRequest_write(_vscratch2278, _news2273[_key2274]);
            _keys2275.append((_scratch2276.finish(), _vscratch2278.finish(), _key2274));
        }
        _keys2275.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2275.count);
        for (var (_bytes2277, _, _key2274) in _keys2275) {
            out.text(_key2274);
            _m_SpecRequest_write(out, _news2273[_key2274]);
        }
        for (var (_okey2279, _) in _news2273) {
            var _own2280 = RecordOut();
            _own2280.blank_bodies = true;
            _own2280.blank_locs = true;
            _own2280.pending_as_bytes = true;
            _own2280.text(_okey2279);
            _m_SpecRequest_write(_own2280, _news2273[_okey2279]);
            base.own("spec_requests", interface_text(_own2280));
        }
    } else {
        out.unsigned(0);
        var _keys2282 = Array<(u8[], u8[], String)>();
        for (var (_key2281, _) in value.spec_requests) {
            var _scratch2283 = out.scratch();
            _scratch2283.text(_key2281);
            var _vscratch2285 = out.scratch();
            _m_SpecRequest_write(_vscratch2285, value.spec_requests[_key2281]);
            _keys2282.append((_scratch2283.finish(), _vscratch2285.finish(), _key2281));
        }
        _keys2282.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2282.count);
        for (var (_bytes2284, _, _key2281) in _keys2282) {
            out.text(_key2281);
            _m_SpecRequest_write(out, value.spec_requests[_key2281]);
        }
        for (var (_okey2286, _) in value.spec_requests) {
            var _own2287 = RecordOut();
            _own2287.blank_bodies = true;
            _own2287.blank_locs = true;
            _own2287.pending_as_bytes = true;
            _own2287.text(_okey2286);
            _m_SpecRequest_write(_own2287, value.spec_requests[_okey2286]);
            base.own("spec_requests", interface_text(_own2287));
        }
        base.count("spec_requests whole", 0);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2300 = base.size("summaries_to_record");
    var _scratch2299 = base.scratch();
    if (value.summaries_to_record.count >= _n2300) {
        for (var _i2301 in 0.._n2300) {
            var (_t2302, _t2303) = value.summaries_to_record[_i2301];
            _scratch2299.loc(_t2302);
            _scratch2299.text(_t2303);
        }
    }
    if (value.summaries_to_record.count >= _n2300 and base.same_list("summaries_to_record", _scratch2299)) {
        out.unsigned(1);
        out.unsigned(_n2300);
        out.unsigned(value.summaries_to_record.count - _n2300);
        for (var _i2301 in _n2300..value.summaries_to_record.count) {
            var (_t2304, _t2305) = value.summaries_to_record[_i2301];
            out.loc(_t2304);
            out.text(_t2305);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2306 in value.summaries_to_record) {
            var (_t2307, _t2308) = _item2306;
            out.loc(_t2307);
            out.text(_t2308);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2326 = 0;
    var _news2327 = HashMap<String, Array<bool>>();
    for (var (_key2323, _) in value.caller_copies) {
        var _kscratch2324 = base.scratch();
        _kscratch2324.text(_key2323);
        var _vscratch2325 = base.scratch();
        _vscratch2325.unsigned(value.caller_copies[_key2323].count);
        for (var _item2328 in value.caller_copies[_key2323]) {
            _vscratch2325.flag(_item2328);
        }
        var _had = base.entry("caller_copies", _kscratch2324, _vscratch2325);
        if (_had >= 0) {
            _kept2326 += 1;
        }
        if (_had != 1) {
            _news2327[_key2323] = value.caller_copies[_key2323];
        }
    }
    if (_kept2326 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2330 = Array<(u8[], u8[], String)>();
        for (var (_key2329, _) in _news2327) {
            var _scratch2331 = out.scratch();
            _scratch2331.text(_key2329);
            var _vscratch2333 = out.scratch();
            _vscratch2333.unsigned(_news2327[_key2329].count);
            for (var _item2334 in _news2327[_key2329]) {
                _vscratch2333.flag(_item2334);
            }
            _keys2330.append((_scratch2331.finish(), _vscratch2333.finish(), _key2329));
        }
        _keys2330.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2330.count);
        for (var (_bytes2332, _, _key2329) in _keys2330) {
            out.text(_key2329);
            out.unsigned(_news2327[_key2329].count);
            for (var _item2335 in _news2327[_key2329]) {
                out.flag(_item2335);
            }
        }
        for (var (_okey2336, _) in _news2327) {
            var _own2337 = RecordOut();
            _own2337.blank_bodies = true;
            _own2337.blank_locs = true;
            _own2337.pending_as_bytes = true;
            _own2337.text(_okey2336);
            _own2337.unsigned(_news2327[_okey2336].count);
            for (var _item2338 in _news2327[_okey2336]) {
                _own2337.flag(_item2338);
            }
            base.own("caller_copies", interface_text(_own2337));
        }
    } else {
        out.unsigned(0);
        var _keys2340 = Array<(u8[], u8[], String)>();
        for (var (_key2339, _) in value.caller_copies) {
            var _scratch2341 = out.scratch();
            _scratch2341.text(_key2339);
            var _vscratch2343 = out.scratch();
            _vscratch2343.unsigned(value.caller_copies[_key2339].count);
            for (var _item2344 in value.caller_copies[_key2339]) {
                _vscratch2343.flag(_item2344);
            }
            _keys2340.append((_scratch2341.finish(), _vscratch2343.finish(), _key2339));
        }
        _keys2340.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2340.count);
        for (var (_bytes2342, _, _key2339) in _keys2340) {
            out.text(_key2339);
            out.unsigned(value.caller_copies[_key2339].count);
            for (var _item2345 in value.caller_copies[_key2339]) {
                out.flag(_item2345);
            }
        }
        for (var (_okey2346, _) in value.caller_copies) {
            var _own2347 = RecordOut();
            _own2347.blank_bodies = true;
            _own2347.blank_locs = true;
            _own2347.pending_as_bytes = true;
            _own2347.text(_okey2346);
            _own2347.unsigned(value.caller_copies[_okey2346].count);
            for (var _item2348 in value.caller_copies[_okey2346]) {
                _own2347.flag(_item2348);
            }
            base.own("caller_copies", interface_text(_own2347));
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
    var _f1495 = Array<ast.Import>();
    var _mode1498 = input.unsigned();
    if (_mode1498 == 2) {
        var _changed1484 = HashMap<ulong, ast.Import>();
        ulong _bi1499 = 0;
        var _n1496 = input.count();
        for (var _ in 0.._n1496) {
            var _at1500 = input.unsigned();
            while (_f1495.count < _at1500 or (input.merging and _bi1499 < base.imports.count)) {
                var _c = _changed1484.try_get(_bi1499);
                _f1495.append(_c.is_value() ? _c.value() : base.imports[_bi1499]);
                _bi1499 += 1;
            }
            _f1495.append(_a_Import_read(input));
        }
        while (_bi1499 < base.imports.count) {
            var _c = _changed1484.try_get(_bi1499);
            _f1495.append(_c.is_value() ? _c.value() : base.imports[_bi1499]);
            _bi1499 += 1;
        }
    } else if (_mode1498 == 3) {
        var _n1496 = input.count();
        for (var _ in 0.._n1496) {
            _f1495.append(_a_Import_read(input));
        }
    } else {
        var _n1496 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1496) {
            var _tag1497 = input.unsigned();
            if (_tag1497 & 1 == 1) {
                if (!input.merging) {
                    _f1495.append(base.imports[_tag1497 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1495.append(_read);
                }
            }
        }
    }
    var _f1528 = Array<StructDef>();
    var _mode1531 = input.unsigned();
    if (_mode1531 == 2) {
        var _patched1534 = HashMap<ulong, StructDef>();
        var _n1529 = input.count();
        for (var _ in 0.._n1529) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1534[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1532 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1533 = input.unsigned();
            while (_f1528.count < _at1533 or (input.merging and _bi1532 < base.structs.count)) {
                var _p = _patched1534.try_get(_bi1532);
                _f1528.append(_p.is_value() ? _p.value() : base.structs[_bi1532]);
                _bi1532 += 1;
            }
            _f1528.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1532 < base.structs.count) {
            var _p = _patched1534.try_get(_bi1532);
            _f1528.append(_p.is_value() ? _p.value() : base.structs[_bi1532]);
            _bi1532 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1529 = input.count();
        for (var _ in 0.._n1529) {
            var _tag1530 = input.unsigned();
            if (_tag1530 & 1 == 1) {
                _f1528.append(base.structs[(_tag1530 >> 1) < base.structs.count ? _tag1530 >> 1 : 0]);
            } else if (_tag1530 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1528.append(_patch_s_read(input, _was));
            } else {
                _f1528.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1548 = Array<TraitDef>();
    var _mode1551 = input.unsigned();
    if (_mode1551 == 2) {
        var _changed1537 = HashMap<ulong, TraitDef>();
        ulong _bi1552 = 0;
        var _n1549 = input.count();
        for (var _ in 0.._n1549) {
            var _at1553 = input.unsigned();
            while (_f1548.count < _at1553 or (input.merging and _bi1552 < base.traits.count)) {
                var _c = _changed1537.try_get(_bi1552);
                _f1548.append(_c.is_value() ? _c.value() : base.traits[_bi1552]);
                _bi1552 += 1;
            }
            _f1548.append(_m_TraitDef_read(input));
        }
        while (_bi1552 < base.traits.count) {
            var _c = _changed1537.try_get(_bi1552);
            _f1548.append(_c.is_value() ? _c.value() : base.traits[_bi1552]);
            _bi1552 += 1;
        }
    } else if (_mode1551 == 3) {
        var _n1549 = input.count();
        for (var _ in 0.._n1549) {
            _f1548.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1549 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1549) {
            var _tag1550 = input.unsigned();
            if (_tag1550 & 1 == 1) {
                if (!input.merging) {
                    _f1548.append(base.traits[_tag1550 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1548.append(_read);
                }
            }
        }
    }
    var _f1567 = Array<ExtensionDef>();
    var _mode1570 = input.unsigned();
    if (_mode1570 == 2) {
        var _changed1556 = HashMap<ulong, ExtensionDef>();
        ulong _bi1571 = 0;
        var _n1568 = input.count();
        for (var _ in 0.._n1568) {
            var _at1572 = input.unsigned();
            while (_f1567.count < _at1572 or (input.merging and _bi1571 < base.extensions.count)) {
                var _c = _changed1556.try_get(_bi1571);
                _f1567.append(_c.is_value() ? _c.value() : base.extensions[_bi1571]);
                _bi1571 += 1;
            }
            _f1567.append(_m_ExtensionDef_read(input));
        }
        while (_bi1571 < base.extensions.count) {
            var _c = _changed1556.try_get(_bi1571);
            _f1567.append(_c.is_value() ? _c.value() : base.extensions[_bi1571]);
            _bi1571 += 1;
        }
    } else if (_mode1570 == 3) {
        var _n1568 = input.count();
        for (var _ in 0.._n1568) {
            _f1567.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1568 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1568) {
            var _tag1569 = input.unsigned();
            if (_tag1569 & 1 == 1) {
                if (!input.merging) {
                    _f1567.append(base.extensions[_tag1569 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1567.append(_read);
                }
            }
        }
    }
    var _f1586 = Array<FunctionDef>();
    var _mode1589 = input.unsigned();
    if (_mode1589 == 2) {
        var _changed1575 = HashMap<ulong, FunctionDef>();
        var _nc1577 = input.count();
        for (var _ in 0.._nc1577) {
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
                _changed1575[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1590 = 0;
        var _n1587 = input.count();
        for (var _ in 0.._n1587) {
            var _at1591 = input.unsigned();
            while (_f1586.count < _at1591 or (input.merging and _bi1590 < base.functions.count)) {
                var _c = _changed1575.try_get(_bi1590);
                _f1586.append(_c.is_value() ? _c.value() : base.functions[_bi1590]);
                _bi1590 += 1;
            }
            _f1586.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1590 < base.functions.count) {
            var _c = _changed1575.try_get(_bi1590);
            _f1586.append(_c.is_value() ? _c.value() : base.functions[_bi1590]);
            _bi1590 += 1;
        }
    } else if (_mode1589 == 3) {
        var _n1587 = input.count();
        for (var _ in 0.._n1587) {
            _f1586.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1587 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1587) {
            var _tag1588 = input.unsigned();
            if (_tag1588 & 1 == 1) {
                if (!input.merging) {
                    _f1586.append(base.functions[_tag1588 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1586.append(_read);
                }
            }
        }
    }
    var _f1605 = Array<ExternDef>();
    var _mode1608 = input.unsigned();
    if (_mode1608 == 2) {
        var _changed1594 = HashMap<ulong, ExternDef>();
        ulong _bi1609 = 0;
        var _n1606 = input.count();
        for (var _ in 0.._n1606) {
            var _at1610 = input.unsigned();
            while (_f1605.count < _at1610 or (input.merging and _bi1609 < base.externs.count)) {
                var _c = _changed1594.try_get(_bi1609);
                _f1605.append(_c.is_value() ? _c.value() : base.externs[_bi1609]);
                _bi1609 += 1;
            }
            _f1605.append(_m_ExternDef_read(input));
        }
        while (_bi1609 < base.externs.count) {
            var _c = _changed1594.try_get(_bi1609);
            _f1605.append(_c.is_value() ? _c.value() : base.externs[_bi1609]);
            _bi1609 += 1;
        }
    } else if (_mode1608 == 3) {
        var _n1606 = input.count();
        for (var _ in 0.._n1606) {
            _f1605.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1606 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1606) {
            var _tag1607 = input.unsigned();
            if (_tag1607 & 1 == 1) {
                if (!input.merging) {
                    _f1605.append(base.externs[_tag1607 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1605.append(_read);
                }
            }
        }
    }
    var _f1624 = Array<VariableDef>();
    var _mode1627 = input.unsigned();
    if (_mode1627 == 2) {
        var _changed1613 = HashMap<ulong, VariableDef>();
        ulong _bi1628 = 0;
        var _n1625 = input.count();
        for (var _ in 0.._n1625) {
            var _at1629 = input.unsigned();
            while (_f1624.count < _at1629 or (input.merging and _bi1628 < base.globals.count)) {
                var _c = _changed1613.try_get(_bi1628);
                _f1624.append(_c.is_value() ? _c.value() : base.globals[_bi1628]);
                _bi1628 += 1;
            }
            _f1624.append(_m_VariableDef_read(input));
        }
        while (_bi1628 < base.globals.count) {
            var _c = _changed1613.try_get(_bi1628);
            _f1624.append(_c.is_value() ? _c.value() : base.globals[_bi1628]);
            _bi1628 += 1;
        }
    } else if (_mode1627 == 3) {
        var _n1625 = input.count();
        for (var _ in 0.._n1625) {
            _f1624.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1625 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1625) {
            var _tag1626 = input.unsigned();
            if (_tag1626 & 1 == 1) {
                if (!input.merging) {
                    _f1624.append(base.globals[_tag1626 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1624.append(_read);
                }
            }
        }
    }
    var _f1643 = Array<ModuleStaticBlock>();
    var _mode1646 = input.unsigned();
    if (_mode1646 == 2) {
        var _changed1632 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1647 = 0;
        var _n1644 = input.count();
        for (var _ in 0.._n1644) {
            var _at1648 = input.unsigned();
            while (_f1643.count < _at1648 or (input.merging and _bi1647 < base.static_blocks.count)) {
                var _c = _changed1632.try_get(_bi1647);
                _f1643.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1647]);
                _bi1647 += 1;
            }
            _f1643.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1647 < base.static_blocks.count) {
            var _c = _changed1632.try_get(_bi1647);
            _f1643.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1647]);
            _bi1647 += 1;
        }
    } else if (_mode1646 == 3) {
        var _n1644 = input.count();
        for (var _ in 0.._n1644) {
            _f1643.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1644 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1644) {
            var _tag1645 = input.unsigned();
            if (_tag1645 & 1 == 1) {
                if (!input.merging) {
                    _f1643.append(base.static_blocks[_tag1645 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1643.append(_read);
                }
            }
        }
    }
    var _f1662 = Array<EnumDef>();
    var _mode1665 = input.unsigned();
    if (_mode1665 == 2) {
        var _changed1651 = HashMap<ulong, EnumDef>();
        ulong _bi1666 = 0;
        var _n1663 = input.count();
        for (var _ in 0.._n1663) {
            var _at1667 = input.unsigned();
            while (_f1662.count < _at1667 or (input.merging and _bi1666 < base.enums.count)) {
                var _c = _changed1651.try_get(_bi1666);
                _f1662.append(_c.is_value() ? _c.value() : base.enums[_bi1666]);
                _bi1666 += 1;
            }
            _f1662.append(_m_EnumDef_read(input));
        }
        while (_bi1666 < base.enums.count) {
            var _c = _changed1651.try_get(_bi1666);
            _f1662.append(_c.is_value() ? _c.value() : base.enums[_bi1666]);
            _bi1666 += 1;
        }
    } else if (_mode1665 == 3) {
        var _n1663 = input.count();
        for (var _ in 0.._n1663) {
            _f1662.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1663 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1663) {
            var _tag1664 = input.unsigned();
            if (_tag1664 & 1 == 1) {
                if (!input.merging) {
                    _f1662.append(base.enums[_tag1664 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1662.append(_read);
                }
            }
        }
    }
    var _f1681 = Array<TypeName>();
    var _mode1684 = input.unsigned();
    if (_mode1684 == 2) {
        var _changed1670 = HashMap<ulong, TypeName>();
        ulong _bi1685 = 0;
        var _n1682 = input.count();
        for (var _ in 0.._n1682) {
            var _at1686 = input.unsigned();
            while (_f1681.count < _at1686 or (input.merging and _bi1685 < base.struct_specs.count)) {
                var _c = _changed1670.try_get(_bi1685);
                _f1681.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1685]);
                _bi1685 += 1;
            }
            _f1681.append(_m_TypeName_read(input));
        }
        while (_bi1685 < base.struct_specs.count) {
            var _c = _changed1670.try_get(_bi1685);
            _f1681.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1685]);
            _bi1685 += 1;
        }
    } else if (_mode1684 == 3) {
        var _n1682 = input.count();
        for (var _ in 0.._n1682) {
            _f1681.append(_m_TypeName_read(input));
        }
    } else {
        var _n1682 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1682) {
            var _tag1683 = input.unsigned();
            if (_tag1683 & 1 == 1) {
                if (!input.merging) {
                    _f1681.append(base.struct_specs[_tag1683 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1681.append(_read);
                }
            }
        }
    }
    var _f1700 = Array<TypeName>();
    var _mode1703 = input.unsigned();
    if (_mode1703 == 2) {
        var _changed1689 = HashMap<ulong, TypeName>();
        ulong _bi1704 = 0;
        var _n1701 = input.count();
        for (var _ in 0.._n1701) {
            var _at1705 = input.unsigned();
            while (_f1700.count < _at1705 or (input.merging and _bi1704 < base.func_specs.count)) {
                var _c = _changed1689.try_get(_bi1704);
                _f1700.append(_c.is_value() ? _c.value() : base.func_specs[_bi1704]);
                _bi1704 += 1;
            }
            _f1700.append(_m_TypeName_read(input));
        }
        while (_bi1704 < base.func_specs.count) {
            var _c = _changed1689.try_get(_bi1704);
            _f1700.append(_c.is_value() ? _c.value() : base.func_specs[_bi1704]);
            _bi1704 += 1;
        }
    } else if (_mode1703 == 3) {
        var _n1701 = input.count();
        for (var _ in 0.._n1701) {
            _f1700.append(_m_TypeName_read(input));
        }
    } else {
        var _n1701 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1701) {
            var _tag1702 = input.unsigned();
            if (_tag1702 & 1 == 1) {
                if (!input.merging) {
                    _f1700.append(base.func_specs[_tag1702 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1700.append(_read);
                }
            }
        }
    }
    var _f1712 = Array<TypeAliasDef>();
    var _n1713 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1712.append(_b);
        }
    }
    for (var _ in 0.._n1713) {
        var _tag1714 = input.unsigned();
        if (_tag1714 & 1 == 1) {
            if (!input.merging) {
                _f1712.append(base.type_aliases[_tag1714 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1712.append(_read);
            }
        }
    }
    var _f1728 = Array<Withheld>();
    var _mode1731 = input.unsigned();
    if (_mode1731 == 2) {
        var _changed1717 = HashMap<ulong, Withheld>();
        ulong _bi1732 = 0;
        var _n1729 = input.count();
        for (var _ in 0.._n1729) {
            var _at1733 = input.unsigned();
            while (_f1728.count < _at1733 or (input.merging and _bi1732 < base.withheld.count)) {
                var _c = _changed1717.try_get(_bi1732);
                _f1728.append(_c.is_value() ? _c.value() : base.withheld[_bi1732]);
                _bi1732 += 1;
            }
            _f1728.append(_m_Withheld_read(input));
        }
        while (_bi1732 < base.withheld.count) {
            var _c = _changed1717.try_get(_bi1732);
            _f1728.append(_c.is_value() ? _c.value() : base.withheld[_bi1732]);
            _bi1732 += 1;
        }
    } else if (_mode1731 == 3) {
        var _n1729 = input.count();
        for (var _ in 0.._n1729) {
            _f1728.append(_m_Withheld_read(input));
        }
    } else {
        var _n1729 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1729) {
            var _tag1730 = input.unsigned();
            if (_tag1730 & 1 == 1) {
                if (!input.merging) {
                    _f1728.append(base.withheld[_tag1730 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1728.append(_read);
                }
            }
        }
    }
    var _f1747 = Array<PropertyDef>();
    var _mode1750 = input.unsigned();
    if (_mode1750 == 2) {
        var _changed1736 = HashMap<ulong, PropertyDef>();
        ulong _bi1751 = 0;
        var _n1748 = input.count();
        for (var _ in 0.._n1748) {
            var _at1752 = input.unsigned();
            while (_f1747.count < _at1752 or (input.merging and _bi1751 < base.properties.count)) {
                var _c = _changed1736.try_get(_bi1751);
                _f1747.append(_c.is_value() ? _c.value() : base.properties[_bi1751]);
                _bi1751 += 1;
            }
            _f1747.append(_m_PropertyDef_read(input));
        }
        while (_bi1751 < base.properties.count) {
            var _c = _changed1736.try_get(_bi1751);
            _f1747.append(_c.is_value() ? _c.value() : base.properties[_bi1751]);
            _bi1751 += 1;
        }
    } else if (_mode1750 == 3) {
        var _n1748 = input.count();
        for (var _ in 0.._n1748) {
            _f1747.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1748 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1748) {
            var _tag1749 = input.unsigned();
            if (_tag1749 & 1 == 1) {
                if (!input.merging) {
                    _f1747.append(base.properties[_tag1749 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1747.append(_read);
                }
            }
        }
    }
    var _f1766 = Array<TypeUse>();
    var _mode1769 = input.unsigned();
    if (_mode1769 == 2) {
        var _changed1755 = HashMap<ulong, TypeUse>();
        ulong _bi1770 = 0;
        var _n1767 = input.count();
        for (var _ in 0.._n1767) {
            var _at1771 = input.unsigned();
            while (_f1766.count < _at1771 or (input.merging and _bi1770 < base.type_uses.count)) {
                var _c = _changed1755.try_get(_bi1770);
                _f1766.append(_c.is_value() ? _c.value() : base.type_uses[_bi1770]);
                _bi1770 += 1;
            }
            _f1766.append(_m_TypeUse_read(input));
        }
        while (_bi1770 < base.type_uses.count) {
            var _c = _changed1755.try_get(_bi1770);
            _f1766.append(_c.is_value() ? _c.value() : base.type_uses[_bi1770]);
            _bi1770 += 1;
        }
    } else if (_mode1769 == 3) {
        var _n1767 = input.count();
        for (var _ in 0.._n1767) {
            _f1766.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1767 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1767) {
            var _tag1768 = input.unsigned();
            if (_tag1768 & 1 == 1) {
                if (!input.merging) {
                    _f1766.append(base.type_uses[_tag1768 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1766.append(_read);
                }
            }
        }
    }
    var _f1785 = Array<UseContext>();
    var _mode1788 = input.unsigned();
    if (_mode1788 == 2) {
        var _changed1774 = HashMap<ulong, UseContext>();
        ulong _bi1789 = 0;
        var _n1786 = input.count();
        for (var _ in 0.._n1786) {
            var _at1790 = input.unsigned();
            while (_f1785.count < _at1790 or (input.merging and _bi1789 < base.use_contexts.count)) {
                var _c = _changed1774.try_get(_bi1789);
                _f1785.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1789]);
                _bi1789 += 1;
            }
            _f1785.append(_m_UseContext_read(input));
        }
        while (_bi1789 < base.use_contexts.count) {
            var _c = _changed1774.try_get(_bi1789);
            _f1785.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1789]);
            _bi1789 += 1;
        }
    } else if (_mode1788 == 3) {
        var _n1786 = input.count();
        for (var _ in 0.._n1786) {
            _f1785.append(_m_UseContext_read(input));
        }
    } else {
        var _n1786 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1786) {
            var _tag1787 = input.unsigned();
            if (_tag1787 & 1 == 1) {
                if (!input.merging) {
                    _f1785.append(base.use_contexts[_tag1787 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1785.append(_read);
                }
            }
        }
    }
    var _f1806 = Array<(Loc, ulong, Loc)>();
    var _tag1807 = input.unsigned();
    if (_tag1807 == 1) {
        input.unsigned();
        for (var _i1795 in 0..base.literal_args.count) {
            _f1806.append(base.literal_args[_i1795]);
        }
        var _more1809 = input.count();
        for (var _ in 0.._more1809) {
            var _t1810 = input.loc();
            var _t1811 = input.unsigned();
            var _t1812 = input.loc();
            _f1806.append((_t1810, _t1811, _t1812));
        }
    } else {
        var _v1813 = Array<(Loc, ulong, Loc)>();
        var _n1814 = input.count();
        for (var _ in 0.._n1814) {
            var _t1815 = input.loc();
            var _t1816 = input.unsigned();
            var _t1817 = input.loc();
            _v1813.append((_t1815, _t1816, _t1817));
        }
        _f1806 = _v1813;
    }
    var _f1835 = Array<TypeAliasDef>();
    var _mode1838 = input.unsigned();
    if (_mode1838 == 2) {
        var _changed1824 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1839 = 0;
        var _n1836 = input.count();
        for (var _ in 0.._n1836) {
            var _at1840 = input.unsigned();
            while (_f1835.count < _at1840 or (input.merging and _bi1839 < base.constrained_aliases.count)) {
                var _c = _changed1824.try_get(_bi1839);
                _f1835.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1839]);
                _bi1839 += 1;
            }
            _f1835.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1839 < base.constrained_aliases.count) {
            var _c = _changed1824.try_get(_bi1839);
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
    var _f1854 = Array<TraitType>();
    var _mode1857 = input.unsigned();
    if (_mode1857 == 2) {
        var _changed1843 = HashMap<ulong, TraitType>();
        ulong _bi1858 = 0;
        var _n1855 = input.count();
        for (var _ in 0.._n1855) {
            var _at1859 = input.unsigned();
            while (_f1854.count < _at1859 or (input.merging and _bi1858 < base.trait_types.count)) {
                var _c = _changed1843.try_get(_bi1858);
                _f1854.append(_c.is_value() ? _c.value() : base.trait_types[_bi1858]);
                _bi1858 += 1;
            }
            _f1854.append(_m_TraitType_read(input));
        }
        while (_bi1858 < base.trait_types.count) {
            var _c = _changed1843.try_get(_bi1858);
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
    var _f2240 = Array<StructDef>();
    var _mode2243 = input.unsigned();
    if (_mode2243 == 2) {
        var _patched2246 = HashMap<ulong, StructDef>();
        var _n2241 = input.count();
        for (var _ in 0.._n2241) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2246[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2244 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2245 = input.unsigned();
            while (_f2240.count < _at2245 or (input.merging and _bi2244 < base.templates.structs.count)) {
                var _p = _patched2246.try_get(_bi2244);
                _f2240.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2244]);
                _bi2244 += 1;
            }
            _f2240.append(_m_StructDef_read(input));
        }
        while (_bi2244 < base.templates.structs.count) {
            var _p = _patched2246.try_get(_bi2244);
            _f2240.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2244]);
            _bi2244 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2241 = input.count();
        for (var _ in 0.._n2241) {
            var _tag2242 = input.unsigned();
            if (_tag2242 & 1 == 1) {
                _f2240.append(
                    base.templates.structs[(_tag2242 >> 1) < base.templates.structs.count ? _tag2242 >> 1 : 0]
                );
            } else if (_tag2242 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2240.append(_patch_t_read(input, _was));
            } else {
                _f2240.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2260 = Array<FunctionDef>();
    var _mode2263 = input.unsigned();
    if (_mode2263 == 2) {
        var _changed2249 = HashMap<ulong, FunctionDef>();
        var _nc2251 = input.count();
        for (var _ in 0.._nc2251) {
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
                _changed2249[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2264 = 0;
        var _n2261 = input.count();
        for (var _ in 0.._n2261) {
            var _at2265 = input.unsigned();
            while (_f2260.count < _at2265 or (input.merging and _bi2264 < base.templates.functions.count)) {
                var _c = _changed2249.try_get(_bi2264);
                _f2260.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2264]);
                _bi2264 += 1;
            }
            _f2260.append(_m_FunctionDef_read(input));
        }
        while (_bi2264 < base.templates.functions.count) {
            var _c = _changed2249.try_get(_bi2264);
            _f2260.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2264]);
            _bi2264 += 1;
        }
    } else if (_mode2263 == 3) {
        var _n2261 = input.count();
        for (var _ in 0.._n2261) {
            _f2260.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2261 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2261) {
            var _tag2262 = input.unsigned();
            if (_tag2262 & 1 == 1) {
                if (!input.merging) {
                    _f2260.append(base.templates.functions[_tag2262 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2260.append(_read);
                }
            }
        }
    }
    var _f2267 = Templates(_frozen, _f2240, _f2260);
    var _f2268 = DeltaBase.read_checked(input, base.checked);
    var _f2288 = HashMap<String, SpecRequest>();
    var _tag2289 = input.unsigned();
    if (_tag2289 == 1) {
        for (var (_bk2290, _bv) in base.spec_requests) {
            _f2288[_bk2290] = _bv;
        }
        var _v2291 = HashMap<String, SpecRequest>();
        var _n2292 = input.count();
        for (var _ in 0.._n2292) {
            var _k2293 = input.text();
            _v2291[_k2293] = _m_SpecRequest_read(input);
        }
        for (var (_bk2290, _av) in _v2291) {
            _f2288[_bk2290] = _av;
        }
    } else {
        var _v2294 = HashMap<String, SpecRequest>();
        var _n2295 = input.count();
        for (var _ in 0.._n2295) {
            var _k2296 = input.text();
            _v2294[_k2296] = _m_SpecRequest_read(input);
        }
        _f2288 = _v2294;
    }
    var _f2297 = input.flag();
    var _f2309 = Array<(Loc, String)>();
    var _tag2310 = input.unsigned();
    if (_tag2310 == 1) {
        input.unsigned();
        for (var _i2301 in 0..base.summaries_to_record.count) {
            _f2309.append(base.summaries_to_record[_i2301]);
        }
        var _more2312 = input.count();
        for (var _ in 0.._more2312) {
            var _t2313 = input.loc();
            var _t2314 = input.text();
            _f2309.append((_t2313, _t2314));
        }
    } else {
        var _v2315 = Array<(Loc, String)>();
        var _n2316 = input.count();
        for (var _ in 0.._n2316) {
            var _t2317 = input.loc();
            var _t2318 = input.text();
            _v2315.append((_t2317, _t2318));
        }
        _f2309 = _v2315;
    }
    var _f2349 = HashMap<String, Array<bool>>();
    var _tag2350 = input.unsigned();
    if (_tag2350 == 1) {
        for (var (_bk2351, _bv) in base.caller_copies) {
            _f2349[_bk2351] = _bv;
        }
        var _v2352 = HashMap<String, Array<bool>>();
        var _n2353 = input.count();
        for (var _ in 0.._n2353) {
            var _k2354 = input.text();
            var _v2355 = Array<bool>();
            var _n2356 = input.count();
            for (var _ in 0.._n2356) {
                _v2355.append(input.flag());
            }
            _v2352[_k2354] = _v2355;
        }
        for (var (_bk2351, _av) in _v2352) {
            _f2349[_bk2351] = _av;
        }
    } else {
        var _v2357 = HashMap<String, Array<bool>>();
        var _n2358 = input.count();
        for (var _ in 0.._n2358) {
            var _k2359 = input.text();
            var _v2360 = Array<bool>();
            var _n2361 = input.count();
            for (var _ in 0.._n2361) {
                _v2360.append(input.flag());
            }
            _v2357[_k2359] = _v2360;
        }
        _f2349 = _v2357;
    }
    var _f2363 = input.flag();
    return Module(
        _f1495,
        _f1528,
        _f1548,
        _f1567,
        _f1586,
        _f1605,
        _f1624,
        _f1643,
        _f1662,
        _f1681,
        _f1700,
        _f1712,
        _f1728,
        _f1747,
        _f1766,
        _f1785,
        _f1806,
        _f1835,
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
        _f2267,
        _f2268,
        _f2288,
        _f2297,
        _f2309,
        _f2349,
        _f2363
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1501 = 0;
    for (var _item1483 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1483);
        base.add("imports", scratch, _j1501);
        _j1501 += 1;
    }
    if (base.verifying) {
        ulong _j1535 = 0;
        for (var _item1502 in value.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item1502);
            base.add("s", scratch, _j1535);
            base.name("s", _item1502.name, _j1535);
            _patch_s_index(_item1502, base, _j1535);
            _j1535 += 1;
        }
    }
    base.ref_structs = value.structs.clone();
    base.ref_struct_parts = Array<StructDef>();
    for (var _item1502 in value.structs) {
        base.ref_struct_parts.append(_m_StructDef_shallow(_item1502));
    }
    ulong _j1554 = 0;
    for (var _item1536 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1536);
        base.add("traits", scratch, _j1554);
        _j1554 += 1;
    }
    ulong _j1573 = 0;
    for (var _item1555 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1555);
        base.add("extensions", scratch, _j1573);
        _j1573 += 1;
    }
    if (base.verifying) {
        ulong _j1592 = 0;
        for (var _item1574 in value.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item1574);
            base.add("functions", scratch, _j1592);
            base.name("functions", _item1574.name, _j1592);
            _j1592 += 1;
        }
    }
    base.ref_functions = value.functions.clone();
    ulong _j1611 = 0;
    for (var _item1593 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1593);
        base.add("externs", scratch, _j1611);
        _j1611 += 1;
    }
    ulong _j1630 = 0;
    for (var _item1612 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1612);
        base.add("globals", scratch, _j1630);
        _j1630 += 1;
    }
    ulong _j1649 = 0;
    for (var _item1631 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1631);
        base.add("static_blocks", scratch, _j1649);
        _j1649 += 1;
    }
    ulong _j1668 = 0;
    for (var _item1650 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1650);
        base.add("enums", scratch, _j1668);
        _j1668 += 1;
    }
    ulong _j1687 = 0;
    for (var _item1669 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1669);
        base.add("struct_specs", scratch, _j1687);
        _j1687 += 1;
    }
    ulong _j1706 = 0;
    for (var _item1688 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1688);
        base.add("func_specs", scratch, _j1706);
        _j1706 += 1;
    }
    ulong _j1715 = 0;
    for (var _item1707 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1707);
        base.add("type_aliases", scratch, _j1715);
        _j1715 += 1;
    }
    ulong _j1734 = 0;
    for (var _item1716 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1716);
        base.add("withheld", scratch, _j1734);
        _j1734 += 1;
    }
    ulong _j1753 = 0;
    for (var _item1735 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1735);
        base.add("properties", scratch, _j1753);
        _j1753 += 1;
    }
    ulong _j1772 = 0;
    for (var _item1754 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1754);
        base.add("type_uses", scratch, _j1772);
        _j1772 += 1;
    }
    ulong _j1791 = 0;
    for (var _item1773 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1773);
        base.add("use_contexts", scratch, _j1791);
        _j1791 += 1;
    }
    var _xscratch1818 = base.scratch();
    for (var _xitem1819 in value.literal_args) {
        var (_t1820, _t1821, _t1822) = _xitem1819;
        _xscratch1818.loc(_t1820);
        _xscratch1818.unsigned(_t1821);
        _xscratch1818.loc(_t1822);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1818);
    ulong _j1841 = 0;
    for (var _item1823 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1823);
        base.add("constrained_aliases", scratch, _j1841);
        _j1841 += 1;
    }
    ulong _j1860 = 0;
    for (var _item1842 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1842);
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
    if (base.verifying) {
        ulong _j2247 = 0;
        for (var _item2230 in value.templates.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item2230);
            base.add("t", scratch, _j2247);
            base.name("t", _item2230.name, _j2247);
            _patch_t_index(_item2230, base, _j2247);
            _j2247 += 1;
        }
    }
    base.ref_templates = value.templates.structs.clone();
    base.ref_template_parts = Array<StructDef>();
    for (var _item2230 in value.templates.structs) {
        base.ref_template_parts.append(_m_StructDef_shallow(_item2230));
    }
    if (base.verifying) {
        ulong _j2266 = 0;
        for (var _item2248 in value.templates.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2248);
            base.add("tf", scratch, _j2266);
            base.name("tf", _item2248.name, _j2266);
            _j2266 += 1;
        }
    }
    base.ref_template_functions = value.templates.functions.clone();
    base.keep_checked(value.checked);
    for (var (_key2269, _) in value.spec_requests) {
        var _kscratch2270 = base.scratch();
        _kscratch2270.text(_key2269);
        var _vscratch2271 = base.scratch();
        _m_SpecRequest_write(_vscratch2271, value.spec_requests[_key2269]);
        base.keep_entry("spec_requests", _kscratch2270, _vscratch2271);
    }
    var _xscratch2319 = base.scratch();
    for (var _xitem2320 in value.summaries_to_record) {
        var (_t2321, _t2322) = _xitem2320;
        _xscratch2319.loc(_t2321);
        _xscratch2319.text(_t2322);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2319);
    for (var (_key2323, _) in value.caller_copies) {
        var _kscratch2324 = base.scratch();
        _kscratch2324.text(_key2323);
        var _vscratch2325 = base.scratch();
        _vscratch2325.unsigned(value.caller_copies[_key2323].count);
        for (var _item2362 in value.caller_copies[_key2323]) {
            _vscratch2325.flag(_item2362);
        }
        base.keep_entry("caller_copies", _kscratch2324, _vscratch2325);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1715 = 0;
    for (var _item1707 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1707);
        base.add("type_aliases", scratch, _j1715);
        _j1715 += 1;
    }
    for (var (_key2184, _) in value.recorded_summaries) {
        var _kscratch2185 = base.scratch();
        _kscratch2185.loc(_key2184);
        var _vscratch2186 = base.scratch();
        _vscratch2186.text(value.recorded_summaries[_key2184]);
        base.keep_entry("recorded_summaries", _kscratch2185, _vscratch2186);
    }
    var _xscratch2319 = base.scratch();
    for (var _xitem2320 in value.summaries_to_record) {
        var (_t2321, _t2322) = _xitem2320;
        _xscratch2319.loc(_t2321);
        _xscratch2319.text(_t2322);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2319);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2371 = base.ref_struct_parts[slot].generic_params;
    ulong _bj2372 = 0;
    var _news2373 = Array<ulong>();
    for (var _i2374 in 0..value.generic_params.count) {
        if (_bj2372 < _seq2371.count and value.generic_params[_i2374] === _seq2371[_bj2372]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2374]);
                base.verify_same($"s.{slot}.generic_params", _bj2372, scratch);
            }
            _bj2372 += 1;
        } else if (_bj2372 < _seq2371.count
            and _same_m_GenericParam(value.generic_params[_i2374], _seq2371[_bj2372], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2374]);
                base.verify_same($"s.{slot}.generic_params", _bj2372, scratch);
            }
            _bj2372 += 1;
        } else {
            _news2373.append(_i2374);
        }
    }
    if (_bj2372 == _seq2371.count) {
        out.unsigned(2);
        out.unsigned(_news2373.count);
        for (var _i2374 in _news2373) {
            out.unsigned(_i2374);
            _m_GenericParam_write(out, value.generic_params[_i2374]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2374 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2374]);
        }
    }
    var _seq2387 = base.ref_struct_parts[slot].field_members;
    ulong _bj2388 = 0;
    var _news2389 = Array<ulong>();
    for (var _i2390 in 0..value.field_members.count) {
        if (_bj2388 < _seq2387.count and value.field_members[_i2390] === _seq2387[_bj2388]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2390]);
                base.verify_same($"s.{slot}.field_members", _bj2388, scratch);
            }
            _bj2388 += 1;
        } else if (_bj2388 < _seq2387.count
            and _same_m_VariableDef(value.field_members[_i2390], _seq2387[_bj2388], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2390]);
                base.verify_same($"s.{slot}.field_members", _bj2388, scratch);
            }
            _bj2388 += 1;
        } else {
            _news2389.append(_i2390);
        }
    }
    if (_bj2388 == _seq2387.count) {
        out.unsigned(2);
        out.unsigned(_news2389.count);
        for (var _i2390 in _news2389) {
            out.unsigned(_i2390);
            _m_VariableDef_write(out, value.field_members[_i2390]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2390 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2390]);
        }
    }
    var _seq2403 = base.ref_struct_parts[slot].method_members;
    ulong _bj2404 = 0;
    var _news2405 = Array<ulong>();
    for (var _i2406 in 0..value.method_members.count) {
        if (_bj2404 < _seq2403.count and value.method_members[_i2406] === _seq2403[_bj2404]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2406]);
                base.verify_same($"s.{slot}.method_members", _bj2404, scratch);
            }
            _bj2404 += 1;
        } else if (_bj2404 < _seq2403.count
            and _same_m_FunctionDef(value.method_members[_i2406], _seq2403[_bj2404], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2406]);
                base.verify_same($"s.{slot}.method_members", _bj2404, scratch);
            }
            _bj2404 += 1;
        } else {
            _news2405.append(_i2406);
        }
    }
    if (_bj2404 == _seq2403.count) {
        out.unsigned(2);
        out.unsigned(_news2405.count);
        for (var _i2406 in _news2405) {
            out.unsigned(_i2406);
            _m_FunctionDef_write(out, value.method_members[_i2406]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2406 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2406]);
        }
    }
    var _seq2419 = base.ref_struct_parts[slot].generic_methods;
    ulong _bj2420 = 0;
    var _news2421 = Array<ulong>();
    for (var _i2422 in 0..value.generic_methods.count) {
        if (_bj2420 < _seq2419.count and value.generic_methods[_i2422] === _seq2419[_bj2420]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2422]);
                base.verify_same($"s.{slot}.generic_methods", _bj2420, scratch);
            }
            _bj2420 += 1;
        } else if (_bj2420 < _seq2419.count
            and _same_m_FunctionDef(value.generic_methods[_i2422], _seq2419[_bj2420], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2422]);
                base.verify_same($"s.{slot}.generic_methods", _bj2420, scratch);
            }
            _bj2420 += 1;
        } else {
            _news2421.append(_i2422);
        }
    }
    if (_bj2420 == _seq2419.count) {
        out.unsigned(2);
        out.unsigned(_news2421.count);
        for (var _i2422 in _news2421) {
            out.unsigned(_i2422);
            _m_FunctionDef_write(out, value.generic_methods[_i2422]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2422 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2422]);
        }
    }
    var _seq2435 = base.ref_struct_parts[slot].constructors;
    ulong _bj2436 = 0;
    var _news2437 = Array<ulong>();
    for (var _i2438 in 0..value.constructors.count) {
        if (_bj2436 < _seq2435.count and value.constructors[_i2438] === _seq2435[_bj2436]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2438]);
                base.verify_same($"s.{slot}.constructors", _bj2436, scratch);
            }
            _bj2436 += 1;
        } else if (_bj2436 < _seq2435.count
            and _same_m_FunctionDef(value.constructors[_i2438], _seq2435[_bj2436], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2438]);
                base.verify_same($"s.{slot}.constructors", _bj2436, scratch);
            }
            _bj2436 += 1;
        } else {
            _news2437.append(_i2438);
        }
    }
    if (_bj2436 == _seq2435.count) {
        out.unsigned(2);
        out.unsigned(_news2437.count);
        for (var _i2438 in _news2437) {
            out.unsigned(_i2438);
            _m_FunctionDef_write(out, value.constructors[_i2438]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2438 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2438]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2454 = base.ref_struct_parts[slot].traits;
    ulong _bj2455 = 0;
    var _news2456 = Array<ulong>();
    for (var _i2457 in 0..value.traits.count) {
        if (_bj2455 < _seq2454.count and value.traits[_i2457] === _seq2454[_bj2455]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2457]);
                base.verify_same($"s.{slot}.traits", _bj2455, scratch);
            }
            _bj2455 += 1;
        } else if (_bj2455 < _seq2454.count and _same_m_TypeName(value.traits[_i2457], _seq2454[_bj2455], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2457]);
                base.verify_same($"s.{slot}.traits", _bj2455, scratch);
            }
            _bj2455 += 1;
        } else {
            _news2456.append(_i2457);
        }
    }
    if (_bj2455 == _seq2454.count) {
        out.unsigned(2);
        out.unsigned(_news2456.count);
        for (var _i2457 in _news2456) {
            out.unsigned(_i2457);
            _m_TypeName_write(out, value.traits[_i2457]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2457 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2457]);
        }
    }
    var _seq2470 = base.ref_struct_parts[slot].attributes;
    ulong _bj2471 = 0;
    var _news2472 = Array<ulong>();
    for (var _i2473 in 0..value.attributes.count) {
        if (_bj2471 < _seq2470.count and value.attributes[_i2473] === _seq2470[_bj2471]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2473]);
                base.verify_same($"s.{slot}.attributes", _bj2471, scratch);
            }
            _bj2471 += 1;
        } else if (_bj2471 < _seq2470.count and _same_a_Attribute(value.attributes[_i2473], _seq2470[_bj2471], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2473]);
                base.verify_same($"s.{slot}.attributes", _bj2471, scratch);
            }
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
            _a_Attribute_write(out, value.attributes[_i2473]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2473 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2473]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2482 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2482);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2364 = input.text();
    var _f2365 = _m_TypeName_read(input);
    var _f2375 = Array<GenericParam>();
    var _mode2378 = input.unsigned();
    if (_mode2378 == 2) {
        var _changed2367 = HashMap<ulong, GenericParam>();
        ulong _bi2379 = 0;
        var _n2376 = input.count();
        for (var _ in 0.._n2376) {
            var _at2380 = input.unsigned();
            while (_f2375.count < _at2380 or (input.merging and _bi2379 < was.generic_params.count)) {
                var _c = _changed2367.try_get(_bi2379);
                _f2375.append(_c.is_value() ? _c.value() : was.generic_params[_bi2379]);
                _bi2379 += 1;
            }
            _f2375.append(_m_GenericParam_read(input));
        }
        while (_bi2379 < was.generic_params.count) {
            var _c = _changed2367.try_get(_bi2379);
            _f2375.append(_c.is_value() ? _c.value() : was.generic_params[_bi2379]);
            _bi2379 += 1;
        }
    } else if (_mode2378 == 3) {
        var _n2376 = input.count();
        for (var _ in 0.._n2376) {
            _f2375.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2376 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2376) {
            var _tag2377 = input.unsigned();
            if (_tag2377 & 1 == 1) {
                if (!input.merging) {
                    _f2375.append(was.generic_params[_tag2377 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2375.append(_read);
                }
            }
        }
    }
    var _f2391 = Array<VariableDef>();
    var _mode2394 = input.unsigned();
    if (_mode2394 == 2) {
        var _changed2383 = HashMap<ulong, VariableDef>();
        ulong _bi2395 = 0;
        var _n2392 = input.count();
        for (var _ in 0.._n2392) {
            var _at2396 = input.unsigned();
            while (_f2391.count < _at2396 or (input.merging and _bi2395 < was.field_members.count)) {
                var _c = _changed2383.try_get(_bi2395);
                _f2391.append(_c.is_value() ? _c.value() : was.field_members[_bi2395]);
                _bi2395 += 1;
            }
            _f2391.append(_m_VariableDef_read(input));
        }
        while (_bi2395 < was.field_members.count) {
            var _c = _changed2383.try_get(_bi2395);
            _f2391.append(_c.is_value() ? _c.value() : was.field_members[_bi2395]);
            _bi2395 += 1;
        }
    } else if (_mode2394 == 3) {
        var _n2392 = input.count();
        for (var _ in 0.._n2392) {
            _f2391.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2392 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2392) {
            var _tag2393 = input.unsigned();
            if (_tag2393 & 1 == 1) {
                if (!input.merging) {
                    _f2391.append(was.field_members[_tag2393 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2391.append(_read);
                }
            }
        }
    }
    var _f2407 = Array<FunctionDef>();
    var _mode2410 = input.unsigned();
    if (_mode2410 == 2) {
        var _changed2399 = HashMap<ulong, FunctionDef>();
        ulong _bi2411 = 0;
        var _n2408 = input.count();
        for (var _ in 0.._n2408) {
            var _at2412 = input.unsigned();
            while (_f2407.count < _at2412 or (input.merging and _bi2411 < was.method_members.count)) {
                var _c = _changed2399.try_get(_bi2411);
                _f2407.append(_c.is_value() ? _c.value() : was.method_members[_bi2411]);
                _bi2411 += 1;
            }
            _f2407.append(_m_FunctionDef_read(input));
        }
        while (_bi2411 < was.method_members.count) {
            var _c = _changed2399.try_get(_bi2411);
            _f2407.append(_c.is_value() ? _c.value() : was.method_members[_bi2411]);
            _bi2411 += 1;
        }
    } else if (_mode2410 == 3) {
        var _n2408 = input.count();
        for (var _ in 0.._n2408) {
            _f2407.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2408 = input.count();
        if (input.merging) {
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2408) {
            var _tag2409 = input.unsigned();
            if (_tag2409 & 1 == 1) {
                if (!input.merging) {
                    _f2407.append(was.method_members[_tag2409 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2407.append(_read);
                }
            }
        }
    }
    var _f2423 = Array<FunctionDef>();
    var _mode2426 = input.unsigned();
    if (_mode2426 == 2) {
        var _changed2415 = HashMap<ulong, FunctionDef>();
        ulong _bi2427 = 0;
        var _n2424 = input.count();
        for (var _ in 0.._n2424) {
            var _at2428 = input.unsigned();
            while (_f2423.count < _at2428 or (input.merging and _bi2427 < was.generic_methods.count)) {
                var _c = _changed2415.try_get(_bi2427);
                _f2423.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2427]);
                _bi2427 += 1;
            }
            _f2423.append(_m_FunctionDef_read(input));
        }
        while (_bi2427 < was.generic_methods.count) {
            var _c = _changed2415.try_get(_bi2427);
            _f2423.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2427]);
            _bi2427 += 1;
        }
    } else if (_mode2426 == 3) {
        var _n2424 = input.count();
        for (var _ in 0.._n2424) {
            _f2423.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2424 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2424) {
            var _tag2425 = input.unsigned();
            if (_tag2425 & 1 == 1) {
                if (!input.merging) {
                    _f2423.append(was.generic_methods[_tag2425 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2423.append(_read);
                }
            }
        }
    }
    var _f2439 = Array<FunctionDef>();
    var _mode2442 = input.unsigned();
    if (_mode2442 == 2) {
        var _changed2431 = HashMap<ulong, FunctionDef>();
        ulong _bi2443 = 0;
        var _n2440 = input.count();
        for (var _ in 0.._n2440) {
            var _at2444 = input.unsigned();
            while (_f2439.count < _at2444 or (input.merging and _bi2443 < was.constructors.count)) {
                var _c = _changed2431.try_get(_bi2443);
                _f2439.append(_c.is_value() ? _c.value() : was.constructors[_bi2443]);
                _bi2443 += 1;
            }
            _f2439.append(_m_FunctionDef_read(input));
        }
        while (_bi2443 < was.constructors.count) {
            var _c = _changed2431.try_get(_bi2443);
            _f2439.append(_c.is_value() ? _c.value() : was.constructors[_bi2443]);
            _bi2443 += 1;
        }
    } else if (_mode2442 == 3) {
        var _n2440 = input.count();
        for (var _ in 0.._n2440) {
            _f2439.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2440 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2440) {
            var _tag2441 = input.unsigned();
            if (_tag2441 & 1 == 1) {
                if (!input.merging) {
                    _f2439.append(was.constructors[_tag2441 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2439.append(_read);
                }
            }
        }
    }
    var _f2446 = _m_FunctionDef_read(input);
    var _f2447 = _m_FunctionDef_read(input);
    var _f2448 = _m_FunctionDef_read(input);
    var _f2458 = Array<TypeName>();
    var _mode2461 = input.unsigned();
    if (_mode2461 == 2) {
        var _changed2450 = HashMap<ulong, TypeName>();
        ulong _bi2462 = 0;
        var _n2459 = input.count();
        for (var _ in 0.._n2459) {
            var _at2463 = input.unsigned();
            while (_f2458.count < _at2463 or (input.merging and _bi2462 < was.traits.count)) {
                var _c = _changed2450.try_get(_bi2462);
                _f2458.append(_c.is_value() ? _c.value() : was.traits[_bi2462]);
                _bi2462 += 1;
            }
            _f2458.append(_m_TypeName_read(input));
        }
        while (_bi2462 < was.traits.count) {
            var _c = _changed2450.try_get(_bi2462);
            _f2458.append(_c.is_value() ? _c.value() : was.traits[_bi2462]);
            _bi2462 += 1;
        }
    } else if (_mode2461 == 3) {
        var _n2459 = input.count();
        for (var _ in 0.._n2459) {
            _f2458.append(_m_TypeName_read(input));
        }
    } else {
        var _n2459 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2459) {
            var _tag2460 = input.unsigned();
            if (_tag2460 & 1 == 1) {
                if (!input.merging) {
                    _f2458.append(was.traits[_tag2460 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2458.append(_read);
                }
            }
        }
    }
    var _f2474 = Array<ast.Attribute>();
    var _mode2477 = input.unsigned();
    if (_mode2477 == 2) {
        var _changed2466 = HashMap<ulong, ast.Attribute>();
        ulong _bi2478 = 0;
        var _n2475 = input.count();
        for (var _ in 0.._n2475) {
            var _at2479 = input.unsigned();
            while (_f2474.count < _at2479 or (input.merging and _bi2478 < was.attributes.count)) {
                var _c = _changed2466.try_get(_bi2478);
                _f2474.append(_c.is_value() ? _c.value() : was.attributes[_bi2478]);
                _bi2478 += 1;
            }
            _f2474.append(_a_Attribute_read(input));
        }
        while (_bi2478 < was.attributes.count) {
            var _c = _changed2466.try_get(_bi2478);
            _f2474.append(_c.is_value() ? _c.value() : was.attributes[_bi2478]);
            _bi2478 += 1;
        }
    } else if (_mode2477 == 3) {
        var _n2475 = input.count();
        for (var _ in 0.._n2475) {
            _f2474.append(_a_Attribute_read(input));
        }
    } else {
        var _n2475 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2475) {
            var _tag2476 = input.unsigned();
            if (_tag2476 & 1 == 1) {
                if (!input.merging) {
                    _f2474.append(was.attributes[_tag2476 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2474.append(_read);
                }
            }
        }
    }
    var _f2481 = input.loc();
    var _o2483 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2484 = Array<EnumCaseDef>();
        var _n2485 = input.count();
        for (var _ in 0.._n2485) {
            _v2484.append(_m_EnumCaseDef_read(input));
        }
        _o2483 = Optional<Array<EnumCaseDef>>.Value(_v2484);
    }
    var _f2486 = _o2483;
    return StructDef(
        _f2364, _f2365, _f2375, _f2391, _f2407, _f2423, _f2439, _f2446, _f2447, _f2448, _f2458, _f2474, _f2481, _f2486
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2381 = 0;
        for (var _item2366 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2366);
            base.add($"s.{slot}.generic_params", scratch, _j2381);
            _j2381 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2397 = 0;
        for (var _item2382 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2382);
            base.add($"s.{slot}.field_members", scratch, _j2397);
            _j2397 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2413 = 0;
        for (var _item2398 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2398);
            base.add($"s.{slot}.method_members", scratch, _j2413);
            _j2413 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2429 = 0;
        for (var _item2414 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2414);
            base.add($"s.{slot}.generic_methods", scratch, _j2429);
            _j2429 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2445 = 0;
        for (var _item2430 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2430);
            base.add($"s.{slot}.constructors", scratch, _j2445);
            _j2445 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2464 = 0;
        for (var _item2449 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2449);
            base.add($"s.{slot}.traits", scratch, _j2464);
            _j2464 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2480 = 0;
        for (var _item2465 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2465);
            base.add($"s.{slot}.attributes", scratch, _j2480);
            _j2480 += 1;
        }
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2494 = base.ref_template_parts[slot].generic_params;
    ulong _bj2495 = 0;
    var _news2496 = Array<ulong>();
    for (var _i2497 in 0..value.generic_params.count) {
        if (_bj2495 < _seq2494.count and value.generic_params[_i2497] === _seq2494[_bj2495]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2497]);
                base.verify_same($"t.{slot}.generic_params", _bj2495, scratch);
            }
            _bj2495 += 1;
        } else if (_bj2495 < _seq2494.count
            and _same_m_GenericParam(value.generic_params[_i2497], _seq2494[_bj2495], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2497]);
                base.verify_same($"t.{slot}.generic_params", _bj2495, scratch);
            }
            _bj2495 += 1;
        } else {
            _news2496.append(_i2497);
        }
    }
    if (_bj2495 == _seq2494.count) {
        out.unsigned(2);
        out.unsigned(_news2496.count);
        for (var _i2497 in _news2496) {
            out.unsigned(_i2497);
            _m_GenericParam_write(out, value.generic_params[_i2497]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2497 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2497]);
        }
    }
    var _seq2510 = base.ref_template_parts[slot].field_members;
    ulong _bj2511 = 0;
    var _news2512 = Array<ulong>();
    for (var _i2513 in 0..value.field_members.count) {
        if (_bj2511 < _seq2510.count and value.field_members[_i2513] === _seq2510[_bj2511]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2513]);
                base.verify_same($"t.{slot}.field_members", _bj2511, scratch);
            }
            _bj2511 += 1;
        } else if (_bj2511 < _seq2510.count
            and _same_m_VariableDef(value.field_members[_i2513], _seq2510[_bj2511], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2513]);
                base.verify_same($"t.{slot}.field_members", _bj2511, scratch);
            }
            _bj2511 += 1;
        } else {
            _news2512.append(_i2513);
        }
    }
    if (_bj2511 == _seq2510.count) {
        out.unsigned(2);
        out.unsigned(_news2512.count);
        for (var _i2513 in _news2512) {
            out.unsigned(_i2513);
            _m_VariableDef_write(out, value.field_members[_i2513]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2513 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2513]);
        }
    }
    var _seq2526 = base.ref_template_parts[slot].method_members;
    ulong _bj2527 = 0;
    var _news2528 = Array<ulong>();
    for (var _i2529 in 0..value.method_members.count) {
        if (_bj2527 < _seq2526.count and value.method_members[_i2529] === _seq2526[_bj2527]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2529]);
                base.verify_same($"t.{slot}.method_members", _bj2527, scratch);
            }
            _bj2527 += 1;
        } else if (_bj2527 < _seq2526.count
            and _same_m_FunctionDef(value.method_members[_i2529], _seq2526[_bj2527], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2529]);
                base.verify_same($"t.{slot}.method_members", _bj2527, scratch);
            }
            _bj2527 += 1;
        } else {
            _news2528.append(_i2529);
        }
    }
    if (_bj2527 == _seq2526.count) {
        out.unsigned(2);
        out.unsigned(_news2528.count);
        for (var _i2529 in _news2528) {
            out.unsigned(_i2529);
            _m_FunctionDef_write(out, value.method_members[_i2529]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2529 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2529]);
        }
    }
    var _seq2542 = base.ref_template_parts[slot].generic_methods;
    ulong _bj2543 = 0;
    var _news2544 = Array<ulong>();
    for (var _i2545 in 0..value.generic_methods.count) {
        if (_bj2543 < _seq2542.count and value.generic_methods[_i2545] === _seq2542[_bj2543]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2545]);
                base.verify_same($"t.{slot}.generic_methods", _bj2543, scratch);
            }
            _bj2543 += 1;
        } else if (_bj2543 < _seq2542.count
            and _same_m_FunctionDef(value.generic_methods[_i2545], _seq2542[_bj2543], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2545]);
                base.verify_same($"t.{slot}.generic_methods", _bj2543, scratch);
            }
            _bj2543 += 1;
        } else {
            _news2544.append(_i2545);
        }
    }
    if (_bj2543 == _seq2542.count) {
        out.unsigned(2);
        out.unsigned(_news2544.count);
        for (var _i2545 in _news2544) {
            out.unsigned(_i2545);
            _m_FunctionDef_write(out, value.generic_methods[_i2545]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2545 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2545]);
        }
    }
    var _seq2558 = base.ref_template_parts[slot].constructors;
    ulong _bj2559 = 0;
    var _news2560 = Array<ulong>();
    for (var _i2561 in 0..value.constructors.count) {
        if (_bj2559 < _seq2558.count and value.constructors[_i2561] === _seq2558[_bj2559]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2561]);
                base.verify_same($"t.{slot}.constructors", _bj2559, scratch);
            }
            _bj2559 += 1;
        } else if (_bj2559 < _seq2558.count
            and _same_m_FunctionDef(value.constructors[_i2561], _seq2558[_bj2559], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2561]);
                base.verify_same($"t.{slot}.constructors", _bj2559, scratch);
            }
            _bj2559 += 1;
        } else {
            _news2560.append(_i2561);
        }
    }
    if (_bj2559 == _seq2558.count) {
        out.unsigned(2);
        out.unsigned(_news2560.count);
        for (var _i2561 in _news2560) {
            out.unsigned(_i2561);
            _m_FunctionDef_write(out, value.constructors[_i2561]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2561 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2561]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2577 = base.ref_template_parts[slot].traits;
    ulong _bj2578 = 0;
    var _news2579 = Array<ulong>();
    for (var _i2580 in 0..value.traits.count) {
        if (_bj2578 < _seq2577.count and value.traits[_i2580] === _seq2577[_bj2578]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2580]);
                base.verify_same($"t.{slot}.traits", _bj2578, scratch);
            }
            _bj2578 += 1;
        } else if (_bj2578 < _seq2577.count and _same_m_TypeName(value.traits[_i2580], _seq2577[_bj2578], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2580]);
                base.verify_same($"t.{slot}.traits", _bj2578, scratch);
            }
            _bj2578 += 1;
        } else {
            _news2579.append(_i2580);
        }
    }
    if (_bj2578 == _seq2577.count) {
        out.unsigned(2);
        out.unsigned(_news2579.count);
        for (var _i2580 in _news2579) {
            out.unsigned(_i2580);
            _m_TypeName_write(out, value.traits[_i2580]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2580 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2580]);
        }
    }
    var _seq2593 = base.ref_template_parts[slot].attributes;
    ulong _bj2594 = 0;
    var _news2595 = Array<ulong>();
    for (var _i2596 in 0..value.attributes.count) {
        if (_bj2594 < _seq2593.count and value.attributes[_i2596] === _seq2593[_bj2594]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2596]);
                base.verify_same($"t.{slot}.attributes", _bj2594, scratch);
            }
            _bj2594 += 1;
        } else if (_bj2594 < _seq2593.count and _same_a_Attribute(value.attributes[_i2596], _seq2593[_bj2594], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2596]);
                base.verify_same($"t.{slot}.attributes", _bj2594, scratch);
            }
            _bj2594 += 1;
        } else {
            _news2595.append(_i2596);
        }
    }
    if (_bj2594 == _seq2593.count) {
        out.unsigned(2);
        out.unsigned(_news2595.count);
        for (var _i2596 in _news2595) {
            out.unsigned(_i2596);
            _a_Attribute_write(out, value.attributes[_i2596]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2596 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2596]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2605 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2605);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2487 = input.text();
    var _f2488 = _m_TypeName_read(input);
    var _f2498 = Array<GenericParam>();
    var _mode2501 = input.unsigned();
    if (_mode2501 == 2) {
        var _changed2490 = HashMap<ulong, GenericParam>();
        ulong _bi2502 = 0;
        var _n2499 = input.count();
        for (var _ in 0.._n2499) {
            var _at2503 = input.unsigned();
            while (_f2498.count < _at2503 or (input.merging and _bi2502 < was.generic_params.count)) {
                var _c = _changed2490.try_get(_bi2502);
                _f2498.append(_c.is_value() ? _c.value() : was.generic_params[_bi2502]);
                _bi2502 += 1;
            }
            _f2498.append(_m_GenericParam_read(input));
        }
        while (_bi2502 < was.generic_params.count) {
            var _c = _changed2490.try_get(_bi2502);
            _f2498.append(_c.is_value() ? _c.value() : was.generic_params[_bi2502]);
            _bi2502 += 1;
        }
    } else if (_mode2501 == 3) {
        var _n2499 = input.count();
        for (var _ in 0.._n2499) {
            _f2498.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2499 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2499) {
            var _tag2500 = input.unsigned();
            if (_tag2500 & 1 == 1) {
                if (!input.merging) {
                    _f2498.append(was.generic_params[_tag2500 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2498.append(_read);
                }
            }
        }
    }
    var _f2514 = Array<VariableDef>();
    var _mode2517 = input.unsigned();
    if (_mode2517 == 2) {
        var _changed2506 = HashMap<ulong, VariableDef>();
        ulong _bi2518 = 0;
        var _n2515 = input.count();
        for (var _ in 0.._n2515) {
            var _at2519 = input.unsigned();
            while (_f2514.count < _at2519 or (input.merging and _bi2518 < was.field_members.count)) {
                var _c = _changed2506.try_get(_bi2518);
                _f2514.append(_c.is_value() ? _c.value() : was.field_members[_bi2518]);
                _bi2518 += 1;
            }
            _f2514.append(_m_VariableDef_read(input));
        }
        while (_bi2518 < was.field_members.count) {
            var _c = _changed2506.try_get(_bi2518);
            _f2514.append(_c.is_value() ? _c.value() : was.field_members[_bi2518]);
            _bi2518 += 1;
        }
    } else if (_mode2517 == 3) {
        var _n2515 = input.count();
        for (var _ in 0.._n2515) {
            _f2514.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2515 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2515) {
            var _tag2516 = input.unsigned();
            if (_tag2516 & 1 == 1) {
                if (!input.merging) {
                    _f2514.append(was.field_members[_tag2516 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2514.append(_read);
                }
            }
        }
    }
    var _f2530 = Array<FunctionDef>();
    var _mode2533 = input.unsigned();
    if (_mode2533 == 2) {
        var _changed2522 = HashMap<ulong, FunctionDef>();
        ulong _bi2534 = 0;
        var _n2531 = input.count();
        for (var _ in 0.._n2531) {
            var _at2535 = input.unsigned();
            while (_f2530.count < _at2535 or (input.merging and _bi2534 < was.method_members.count)) {
                var _c = _changed2522.try_get(_bi2534);
                _f2530.append(_c.is_value() ? _c.value() : was.method_members[_bi2534]);
                _bi2534 += 1;
            }
            _f2530.append(_m_FunctionDef_read(input));
        }
        while (_bi2534 < was.method_members.count) {
            var _c = _changed2522.try_get(_bi2534);
            _f2530.append(_c.is_value() ? _c.value() : was.method_members[_bi2534]);
            _bi2534 += 1;
        }
    } else if (_mode2533 == 3) {
        var _n2531 = input.count();
        for (var _ in 0.._n2531) {
            _f2530.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2531 = input.count();
        if (input.merging) {
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2531) {
            var _tag2532 = input.unsigned();
            if (_tag2532 & 1 == 1) {
                if (!input.merging) {
                    _f2530.append(was.method_members[_tag2532 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2530.append(_read);
                }
            }
        }
    }
    var _f2546 = Array<FunctionDef>();
    var _mode2549 = input.unsigned();
    if (_mode2549 == 2) {
        var _changed2538 = HashMap<ulong, FunctionDef>();
        ulong _bi2550 = 0;
        var _n2547 = input.count();
        for (var _ in 0.._n2547) {
            var _at2551 = input.unsigned();
            while (_f2546.count < _at2551 or (input.merging and _bi2550 < was.generic_methods.count)) {
                var _c = _changed2538.try_get(_bi2550);
                _f2546.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2550]);
                _bi2550 += 1;
            }
            _f2546.append(_m_FunctionDef_read(input));
        }
        while (_bi2550 < was.generic_methods.count) {
            var _c = _changed2538.try_get(_bi2550);
            _f2546.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2550]);
            _bi2550 += 1;
        }
    } else if (_mode2549 == 3) {
        var _n2547 = input.count();
        for (var _ in 0.._n2547) {
            _f2546.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2547 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2547) {
            var _tag2548 = input.unsigned();
            if (_tag2548 & 1 == 1) {
                if (!input.merging) {
                    _f2546.append(was.generic_methods[_tag2548 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2546.append(_read);
                }
            }
        }
    }
    var _f2562 = Array<FunctionDef>();
    var _mode2565 = input.unsigned();
    if (_mode2565 == 2) {
        var _changed2554 = HashMap<ulong, FunctionDef>();
        ulong _bi2566 = 0;
        var _n2563 = input.count();
        for (var _ in 0.._n2563) {
            var _at2567 = input.unsigned();
            while (_f2562.count < _at2567 or (input.merging and _bi2566 < was.constructors.count)) {
                var _c = _changed2554.try_get(_bi2566);
                _f2562.append(_c.is_value() ? _c.value() : was.constructors[_bi2566]);
                _bi2566 += 1;
            }
            _f2562.append(_m_FunctionDef_read(input));
        }
        while (_bi2566 < was.constructors.count) {
            var _c = _changed2554.try_get(_bi2566);
            _f2562.append(_c.is_value() ? _c.value() : was.constructors[_bi2566]);
            _bi2566 += 1;
        }
    } else if (_mode2565 == 3) {
        var _n2563 = input.count();
        for (var _ in 0.._n2563) {
            _f2562.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2563 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2563) {
            var _tag2564 = input.unsigned();
            if (_tag2564 & 1 == 1) {
                if (!input.merging) {
                    _f2562.append(was.constructors[_tag2564 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2562.append(_read);
                }
            }
        }
    }
    var _f2569 = _m_FunctionDef_read(input);
    var _f2570 = _m_FunctionDef_read(input);
    var _f2571 = _m_FunctionDef_read(input);
    var _f2581 = Array<TypeName>();
    var _mode2584 = input.unsigned();
    if (_mode2584 == 2) {
        var _changed2573 = HashMap<ulong, TypeName>();
        ulong _bi2585 = 0;
        var _n2582 = input.count();
        for (var _ in 0.._n2582) {
            var _at2586 = input.unsigned();
            while (_f2581.count < _at2586 or (input.merging and _bi2585 < was.traits.count)) {
                var _c = _changed2573.try_get(_bi2585);
                _f2581.append(_c.is_value() ? _c.value() : was.traits[_bi2585]);
                _bi2585 += 1;
            }
            _f2581.append(_m_TypeName_read(input));
        }
        while (_bi2585 < was.traits.count) {
            var _c = _changed2573.try_get(_bi2585);
            _f2581.append(_c.is_value() ? _c.value() : was.traits[_bi2585]);
            _bi2585 += 1;
        }
    } else if (_mode2584 == 3) {
        var _n2582 = input.count();
        for (var _ in 0.._n2582) {
            _f2581.append(_m_TypeName_read(input));
        }
    } else {
        var _n2582 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2582) {
            var _tag2583 = input.unsigned();
            if (_tag2583 & 1 == 1) {
                if (!input.merging) {
                    _f2581.append(was.traits[_tag2583 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2581.append(_read);
                }
            }
        }
    }
    var _f2597 = Array<ast.Attribute>();
    var _mode2600 = input.unsigned();
    if (_mode2600 == 2) {
        var _changed2589 = HashMap<ulong, ast.Attribute>();
        ulong _bi2601 = 0;
        var _n2598 = input.count();
        for (var _ in 0.._n2598) {
            var _at2602 = input.unsigned();
            while (_f2597.count < _at2602 or (input.merging and _bi2601 < was.attributes.count)) {
                var _c = _changed2589.try_get(_bi2601);
                _f2597.append(_c.is_value() ? _c.value() : was.attributes[_bi2601]);
                _bi2601 += 1;
            }
            _f2597.append(_a_Attribute_read(input));
        }
        while (_bi2601 < was.attributes.count) {
            var _c = _changed2589.try_get(_bi2601);
            _f2597.append(_c.is_value() ? _c.value() : was.attributes[_bi2601]);
            _bi2601 += 1;
        }
    } else if (_mode2600 == 3) {
        var _n2598 = input.count();
        for (var _ in 0.._n2598) {
            _f2597.append(_a_Attribute_read(input));
        }
    } else {
        var _n2598 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2598) {
            var _tag2599 = input.unsigned();
            if (_tag2599 & 1 == 1) {
                if (!input.merging) {
                    _f2597.append(was.attributes[_tag2599 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2597.append(_read);
                }
            }
        }
    }
    var _f2604 = input.loc();
    var _o2606 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2607 = Array<EnumCaseDef>();
        var _n2608 = input.count();
        for (var _ in 0.._n2608) {
            _v2607.append(_m_EnumCaseDef_read(input));
        }
        _o2606 = Optional<Array<EnumCaseDef>>.Value(_v2607);
    }
    var _f2609 = _o2606;
    return StructDef(
        _f2487, _f2488, _f2498, _f2514, _f2530, _f2546, _f2562, _f2569, _f2570, _f2571, _f2581, _f2597, _f2604, _f2609
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2504 = 0;
        for (var _item2489 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2489);
            base.add($"t.{slot}.generic_params", scratch, _j2504);
            _j2504 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2520 = 0;
        for (var _item2505 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2505);
            base.add($"t.{slot}.field_members", scratch, _j2520);
            _j2520 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2536 = 0;
        for (var _item2521 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2521);
            base.add($"t.{slot}.method_members", scratch, _j2536);
            _j2536 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2552 = 0;
        for (var _item2537 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2537);
            base.add($"t.{slot}.generic_methods", scratch, _j2552);
            _j2552 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2568 = 0;
        for (var _item2553 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2553);
            base.add($"t.{slot}.constructors", scratch, _j2568);
            _j2568 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2587 = 0;
        for (var _item2572 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2572);
            base.add($"t.{slot}.traits", scratch, _j2587);
            _j2587 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2603 = 0;
        for (var _item2588 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2588);
            base.add($"t.{slot}.attributes", scratch, _j2603);
            _j2603 += 1;
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
        for (var _item2610 in value.imports) {
            _a_Import_write(out, _item2610);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2611 in value.structs) {
            _m_StructDef_write(out, _item2611);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.blank_bodies = false;
        out.unsigned(value.traits.count);
        for (var _item2612 in value.traits) {
            _m_TraitDef_write(out, _item2612);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2613 in value.extensions) {
            _m_ExtensionDef_write(out, _item2613);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2614 in value.functions) {
            _m_FunctionDef_write(out, _item2614);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2615 in value.externs) {
            _m_ExternDef_write(out, _item2615);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2616 in value.globals) {
            _m_VariableDef_write(out, _item2616);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2617 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2617);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2618 in value.enums) {
            _m_EnumDef_write(out, _item2618);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2619 in value.struct_specs) {
            _m_TypeName_write(out, _item2619);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2620 in value.func_specs) {
            _m_TypeName_write(out, _item2620);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2621 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2621);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2622 in value.withheld) {
            _m_Withheld_write(out, _item2622);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2623 in value.properties) {
            _m_PropertyDef_write(out, _item2623);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2624 in value.type_uses) {
            _m_TypeUse_write(out, _item2624);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2625 in value.use_contexts) {
            _m_UseContext_write(out, _item2625);
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
            for (var _item2626 in value.literal_args) {
                var (_t2627, _t2628, _t2629) = _item2626;
                out.loc(_t2627);
                out.unsigned(_t2628);
                out.loc(_t2629);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2630 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2630);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2631 in value.trait_types) {
            _m_TraitType_write(out, _item2631);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2632 in value.conversions) {
            _m_Conversion_write(out, _item2632);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2634 = Array<(u8[], u8[], String)>();
        for (var (_key2633, _) in value.overload_sets) {
            var _scratch2635 = out.scratch();
            _scratch2635.text(_key2633);
            var _vscratch2637 = out.scratch();
            _vscratch2637.unsigned(value.overload_sets[_key2633].count);
            for (var _item2638 in value.overload_sets[_key2633]) {
                _vscratch2637.text(_item2638);
            }
            _keys2634.append((_scratch2635.finish(), _vscratch2637.finish(), _key2633));
        }
        _keys2634.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2634.count);
        for (var (_bytes2636, _, _key2633) in _keys2634) {
            out.text(_key2633);
            out.unsigned(value.overload_sets[_key2633].count);
            for (var _item2639 in value.overload_sets[_key2633]) {
                out.text(_item2639);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2641 = Array<(u8[], u8[], String)>();
        for (var (_key2640, _) in value.overload_unions) {
            var _scratch2642 = out.scratch();
            _scratch2642.text(_key2640);
            var _vscratch2644 = out.scratch();
            _vscratch2644.unsigned(value.overload_unions[_key2640].count);
            for (var _item2645 in value.overload_unions[_key2640]) {
                _vscratch2644.unsigned(_item2645.count);
                for (var _item2646 in _item2645) {
                    _vscratch2644.text(_item2646);
                }
            }
            _keys2641.append((_scratch2642.finish(), _vscratch2644.finish(), _key2640));
        }
        _keys2641.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2641.count);
        for (var (_bytes2643, _, _key2640) in _keys2641) {
            out.text(_key2640);
            out.unsigned(value.overload_unions[_key2640].count);
            for (var _item2647 in value.overload_unions[_key2640]) {
                out.unsigned(_item2647.count);
                for (var _item2648 in _item2647) {
                    out.text(_item2648);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2650 = Array<(u8[], u8[], String)>();
        for (var (_key2649, _) in value.method_overload_sets) {
            var _scratch2651 = out.scratch();
            _scratch2651.text(_key2649);
            var _vscratch2653 = out.scratch();
            var _keys2655 = Array<(u8[], u8[], String)>();
            for (var (_key2654, _) in value.method_overload_sets[_key2649]) {
                var _scratch2656 = _vscratch2653.scratch();
                _scratch2656.text(_key2654);
                var _vscratch2658 = _vscratch2653.scratch();
                _vscratch2658.unsigned(value.method_overload_sets[_key2649][_key2654].count);
                for (var _item2659 in value.method_overload_sets[_key2649][_key2654]) {
                    _vscratch2658.text(_item2659);
                }
                _keys2655.append((_scratch2656.finish(), _vscratch2658.finish(), _key2654));
            }
            _keys2655.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2653.unsigned(_keys2655.count);
            for (var (_bytes2657, _, _key2654) in _keys2655) {
                _vscratch2653.text(_key2654);
                _vscratch2653.unsigned(value.method_overload_sets[_key2649][_key2654].count);
                for (var _item2660 in value.method_overload_sets[_key2649][_key2654]) {
                    _vscratch2653.text(_item2660);
                }
            }
            _keys2650.append((_scratch2651.finish(), _vscratch2653.finish(), _key2649));
        }
        _keys2650.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2650.count);
        for (var (_bytes2652, _, _key2649) in _keys2650) {
            out.text(_key2649);
            var _keys2662 = Array<(u8[], u8[], String)>();
            for (var (_key2661, _) in value.method_overload_sets[_key2649]) {
                var _scratch2663 = out.scratch();
                _scratch2663.text(_key2661);
                var _vscratch2665 = out.scratch();
                _vscratch2665.unsigned(value.method_overload_sets[_key2649][_key2661].count);
                for (var _item2666 in value.method_overload_sets[_key2649][_key2661]) {
                    _vscratch2665.text(_item2666);
                }
                _keys2662.append((_scratch2663.finish(), _vscratch2665.finish(), _key2661));
            }
            _keys2662.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2662.count);
            for (var (_bytes2664, _, _key2661) in _keys2662) {
                out.text(_key2661);
                out.unsigned(value.method_overload_sets[_key2649][_key2661].count);
                for (var _item2667 in value.method_overload_sets[_key2649][_key2661]) {
                    out.text(_item2667);
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
        var _keys2669 = Array<(u8[], u8[], Loc)>();
        for (var _key2668 in value.private_functions) {
            var _scratch2670 = out.scratch();
            _scratch2670.loc(_key2668);
            var _vscratch2672 = out.scratch();
            _keys2669.append((_scratch2670.finish(), _vscratch2672.finish(), _key2668));
        }
        _keys2669.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2669.count);
        for (var (_bytes2671, _, _key2668) in _keys2669) {
            out.loc(_key2668);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2674 = Array<(u8[], u8[], Loc)>();
        for (var _key2673 in value.file_private_functions) {
            var _scratch2675 = out.scratch();
            _scratch2675.loc(_key2673);
            var _vscratch2677 = out.scratch();
            _keys2674.append((_scratch2675.finish(), _vscratch2677.finish(), _key2673));
        }
        _keys2674.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2674.count);
        for (var (_bytes2676, _, _key2673) in _keys2674) {
            out.loc(_key2673);
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
            for (var _item2678 in value.call_targets) {
                var (_t2679, _t2680) = _item2678;
                out.loc(_t2679);
                out.text(_t2680);
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
            for (var _item2681 in value.argument_names) {
                var (_t2682, _t2683) = _item2681;
                out.loc(_t2682);
                out.text(_t2683);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2684 in value.namespaces) {
            out.text(_item2684);
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
            for (var _item2685 in value.cached_files) {
                out.flag(_item2685);
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
            var _keys2687 = Array<(u8[], u8[], Loc)>();
            for (var (_key2686, _) in value.recorded_summaries) {
                var _scratch2688 = out.scratch();
                _scratch2688.loc(_key2686);
                var _vscratch2690 = out.scratch();
                _vscratch2690.text(value.recorded_summaries[_key2686]);
                _keys2687.append((_scratch2688.finish(), _vscratch2690.finish(), _key2686));
            }
            _keys2687.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2687.count);
            for (var (_bytes2689, _, _key2686) in _keys2687) {
                out.loc(_key2686);
                out.text(value.recorded_summaries[_key2686]);
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
            var _keys2692 = Array<(u8[], u8[], Loc)>();
            for (var _key2691 in value.stripped) {
                var _scratch2693 = out.scratch();
                _scratch2693.loc(_key2691);
                var _vscratch2695 = out.scratch();
                _keys2692.append((_scratch2693.finish(), _vscratch2695.finish(), _key2691));
            }
            _keys2692.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2692.count);
            for (var (_bytes2694, _, _key2691) in _keys2692) {
                out.loc(_key2691);
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
        var _keys2697 = Array<(u8[], u8[], String)>();
        for (var (_key2696, _) in value.spec_requests) {
            var _scratch2698 = out.scratch();
            _scratch2698.text(_key2696);
            var _vscratch2700 = out.scratch();
            _m_SpecRequest_write(_vscratch2700, value.spec_requests[_key2696]);
            _keys2697.append((_scratch2698.finish(), _vscratch2700.finish(), _key2696));
        }
        _keys2697.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2697.count);
        for (var (_bytes2699, _, _key2696) in _keys2697) {
            out.text(_key2696);
            _m_SpecRequest_write(out, value.spec_requests[_key2696]);
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
            for (var _item2701 in value.summaries_to_record) {
                var (_t2702, _t2703) = _item2701;
                out.loc(_t2702);
                out.text(_t2703);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2705 = Array<(u8[], u8[], String)>();
        for (var (_key2704, _) in value.caller_copies) {
            var _scratch2706 = out.scratch();
            _scratch2706.text(_key2704);
            var _vscratch2708 = out.scratch();
            _vscratch2708.unsigned(value.caller_copies[_key2704].count);
            for (var _item2709 in value.caller_copies[_key2704]) {
                _vscratch2708.flag(_item2709);
            }
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
            out.text(_key2704);
            out.unsigned(value.caller_copies[_key2704].count);
            for (var _item2710 in value.caller_copies[_key2704]) {
                out.flag(_item2710);
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
    for (var _item2711 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2711);
        found.append(("structs " + _item2711.name, interface_text(out)));
    }
    for (var _item2712 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2712);
        found.append(("functions " + _item2712.name, interface_text(out)));
    }
    return found;
}
